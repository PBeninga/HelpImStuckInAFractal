// The phone server. HTTP for Twilio's webhooks and a small debug API,
// WebSockets for ConversationRelay (one per call) and for the game link.
//
//   GET  /health              liveness + whether a game is linked (Railway's healthcheck)
//   POST /twilio/voice        incoming call: TwiML that connects it to the voice agent
//                             (VOICE_AGENT=openai: <Stream> to /twilio/media) or to
//                             ConversationRelay (VOICE_AGENT=relay)
//   POST /twilio/session-end  <Connect action>: the session finished
//   WS   /twilio/media        Media Stream audio for the OpenAI voice agent (Twilio-signed)
//   WS   /twilio/relay        ConversationRelay (Twilio-signed)
//   WS   /game/link           the game's link (Bearer GAME_LINK_TOKEN)
//   POST /api/game/:cmd       run any McpBridge command on the linked game (Bearer GAME_LINK_TOKEN)
//   POST /mcp                 the call centre's ship tools as an MCP server (Bearer GAME_LINK_TOKEN)

import http from "node:http";
import crypto from "node:crypto";
import express from "express";
import twilio from "twilio";
import { WebSocketServer } from "ws";
import { GameLink } from "./game_link.mjs";
import { Calls, mask } from "./calls.mjs";
import { VoiceCalls } from "./voice/voice_calls.mjs";
import { handleMcp } from "./mcp_http.mjs";
import { formatPhoneNumber } from "./config.mjs";

export function createApp(config, { log = console, WebSocketImpl, heartbeatMs = 25_000 } = {}) {
  const game = new GameLink();
  const calls = new Calls(game, { allowedCallers: config.allowedCallers, log });
  const voice = new VoiceCalls(game, config, { log, WebSocketImpl });
  game.on("connected", () => {
    log.info("game linked");
    // the support number and who answers, for the call centre's HUD
    game.notify({
      type: "config",
      support_number: formatPhoneNumber(config.supportNumber),
      voice_agent: config.voiceAgent,
      agent_name: config.agentName,
    });
  });
  game.on("disconnected", () => log.info("game unlinked"));

  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", true);
  app.use(express.urlencoded({ extended: false }));
  app.use(express.json());

  // ---------------------------------------------------------------- twilio

  const twilioOnly = (req, res, next) => {
    if (!config.validateTwilio) return next();
    const url = config.publicBaseUrl + req.originalUrl;
    const ok = twilio.validateRequest(
      config.twilioAuthToken,
      req.get("X-Twilio-Signature") || "",
      url,
      req.body || {},
    );
    if (!ok) {
      log.warn(`rejected unsigned request to ${req.originalUrl}`);
      return res.status(403).send("invalid Twilio signature");
    }
    next();
  };

  app.post("/twilio/voice", twilioOnly, (req, res) => {
    const from = req.body.From;
    const vr = new twilio.twiml.VoiceResponse();
    if (!config.allowedCallers.includes(from)) {
      log.warn(`refused call from ${mask(from)}`);
      vr.say("Sorry, this number can't pilot the fractal.");
      vr.hangup();
    } else if (!game.connected) {
      vr.say("The fractal is offline. Start the game and its phone link on your computer, then call back.");
      vr.hangup();
    } else if (config.voiceAgent === "openai") {
      if (voice.busy) {
        vr.say("Thank you for calling Sub-Dimensional Support. All of our agents are currently assisting other pilots stranded in other fractals. Your call is important to us, at every scale. Please try again shortly.");
        vr.hangup();
      } else {
        game.notify({ type: "call_ringing", from: mask(from) });
        const stream = vr.connect({ action: `${config.publicBaseUrl}/twilio/session-end` }).stream({ url: wsUrl(config.publicBaseUrl, "/twilio/media") });
        stream.parameter({ name: "token", value: voice.issueToken(from) });
      }
    } else {
      const relay = {
        url: wsUrl(config.publicBaseUrl, "/twilio/relay"),
        welcomeGreeting: config.welcomeGreeting,
        language: config.language,
        dtmfDetection: "true",
        interruptible: "any",
      };
      if (config.ttsProvider) relay.ttsProvider = config.ttsProvider;
      if (config.voice) relay.voice = config.voice;
      if (config.partialPrompts) relay.partialPrompts = "true";
      vr.connect({ action: `${config.publicBaseUrl}/twilio/session-end` }).conversationRelay(relay);
    }
    res.type("text/xml").send(vr.toString());
  });

  app.post("/twilio/session-end", twilioOnly, (req, res) => {
    const { CallSid, SessionStatus, ErrorCode, ErrorMessage } = req.body;
    if (ErrorCode) log.warn(`relay session ${CallSid} ${SessionStatus}: ${ErrorCode} ${ErrorMessage}`);
    else log.info(`relay session ${CallSid} ${SessionStatus || "ended"}`);
    const vr = new twilio.twiml.VoiceResponse();
    vr.hangup();
    res.type("text/xml").send(vr.toString());
  });

  // ---------------------------------------------------------------- status / debug

  app.get("/health", (req, res) => {
    res.json({ ok: true, game_linked: game.connected, calls: calls.active.length + voice.active.length, voice_agent: config.voiceAgent });
  });

  const tokenOnly = (req, res, next) => {
    if (!checkBearer(req.get("Authorization"), config.gameLinkToken)) return res.status(401).json({ error: "unauthorized" });
    next();
  };

  app.get("/api/status", tokenOnly, (req, res) => {
    res.json({ game_linked: game.connected, game: game.info, voice_agent: config.voiceAgent, calls: [...calls.active, ...voice.active] });
  });

  // The ship's tools for any MCP client (Streamable HTTP, stateless JSON).
  app.post("/mcp", tokenOnly, (req, res) => handleMcp(req, res, game, log));
  app.all("/mcp", (req, res) => res.set("Allow", "POST").status(405).end());

  app.post("/api/game/:cmd", tokenOnly, async (req, res) => {
    try {
      res.json({ ok: true, result: await game.call(req.params.cmd, req.body || {}) });
    } catch (err) {
      res.status(game.connected ? 400 : 503).json({ ok: false, error: err.message });
    }
  });

  // ---------------------------------------------------------------- websockets

  const server = http.createServer(app);
  const relayWss = new WebSocketServer({ noServer: true });
  const linkWss = new WebSocketServer({ noServer: true, maxPayload: 32 * 1024 * 1024 });

  server.on("upgrade", (req, socket, head) => {
    const { pathname } = new URL(req.url, "http://x");
    const refuse = (status) => {
      socket.write(`HTTP/1.1 ${status}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
    };
    if (pathname === "/twilio/relay" || pathname === "/twilio/media") {
      if (config.validateTwilio && !validRelaySignature(config, req)) {
        log.warn(`rejected unsigned ${pathname} socket`);
        return refuse("403 Forbidden");
      }
      // handleUpgrade does not emit "connection" itself; emitting it starts
      // the heartbeat's pong tracking (below), without which every socket was
      // dropped as dead after two heartbeats.
      relayWss.handleUpgrade(req, socket, head, (ws) => {
        relayWss.emit("connection", ws, req);
        if (pathname === "/twilio/media") voice.attach(ws);
        else calls.attach(ws);
      });
    } else if (pathname === "/game/link") {
      if (!checkBearer(req.headers.authorization, config.gameLinkToken)) return refuse("401 Unauthorized");
      linkWss.handleUpgrade(req, socket, head, (ws) => {
        linkWss.emit("connection", ws, req);
        game.attach(ws);
      });
    } else {
      refuse("404 Not Found");
    }
  });

  // Keep idle sockets alive through Railway's proxy, and drop dead ones.
  const heartbeat = setInterval(() => {
    for (const wss of [relayWss, linkWss]) {
      for (const ws of wss.clients) {
        if (ws.isAlive === false) {
          ws.terminate();
          continue;
        }
        ws.isAlive = false;
        ws.ping();
      }
    }
  }, heartbeatMs);
  for (const wss of [relayWss, linkWss]) {
    wss.on("connection", (ws) => {
      ws.isAlive = true;
      ws.on("pong", () => (ws.isAlive = true));
    });
  }
  server.on("close", () => clearInterval(heartbeat));

  return { server, app, game, calls, voice };
}

export function wsUrl(base, path) {
  return base.replace(/^http/, "ws") + path;
}

// Twilio signs the relay handshake over the socket URL it was given. Accept the
// wss:// form or its https:// twin; both need the auth token to forge.
function validRelaySignature(config, req) {
  const sig = req.headers["x-twilio-signature"];
  if (!sig || !config.twilioAuthToken) return false;
  const https = config.publicBaseUrl + req.url;
  return [wsUrl(config.publicBaseUrl, req.url), https].some((url) =>
    twilio.validateRequest(config.twilioAuthToken, sig, url, {}),
  );
}

function checkBearer(header, token) {
  if (!token) return false;
  const given = Buffer.from(String(header || "").replace(/^Bearer\s+/i, ""));
  const want = Buffer.from(token);
  return given.length === want.length && crypto.timingSafeEqual(given, want);
}
