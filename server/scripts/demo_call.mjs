#!/usr/bin/env node
// A whole support call, end to end, with no accounts: the real phone server
// and the real link, a fake Twilio caller (signed webhook, signed media
// stream, mu-law audio both ways) and a scripted voice agent speaking the
// OpenAI Realtime protocol in place of the model. Every hop the real call
// takes runs for real (Twilio wire format -> server -> OpenAI wire format ->
// tool calls -> link -> McpBridge -> the call centre -> the ship), only the
// agent's decisions are scripted: it reads the ship's status, follows
// whatever route the game exposes, answers the diagnostics questions as the
// "caller", and flies out of the exit.
//
//   1. the game, with its call centre:   call_center/run.sh --demo
//   2. this:                             cd server && npm run demo [-- --fast]
//
// With --in-game-link the game dials this server itself (ServerLink) instead
// of the node link: start the game with the URL and token this prints, e.g.
//   GAME_LINK_TOKEN=demo npm run demo -- --in-game-link
//   FRACTAL_SERVER_URL=http://127.0.0.1:3077 GAME_LINK_TOKEN=demo call_center/run.sh --demo
//
// Rehearsal, screenshots, an end-to-end check, and a fallback when the venue
// Wi-Fi gives up.

import crypto from "node:crypto";
import { once } from "node:events";
import twilio from "twilio";
import { WebSocket, WebSocketServer } from "ws";
import { loadConfig } from "../src/config.mjs";
import { createApp, wsUrl } from "../src/app.mjs";
import { startLink } from "../link/link.mjs";
import { BridgeClient } from "../link/bridge_client.mjs";

const FAST = process.argv.includes("--fast");
const IN_GAME_LINK = process.argv.includes("--in-game-link");
const BRIDGE_PORT = Number(process.env.FRACTAL_MCP_PORT || 9077);
const CALLER = "+15550001234";
const AUTH = crypto.randomBytes(16).toString("hex");
const LINK = IN_GAME_LINK ? process.env.GAME_LINK_TOKEN || "demo" : crypto.randomBytes(16).toString("hex");
const DEMO_PORT = IN_GAME_LINK ? Number(process.env.DEMO_PORT || 3077) : 0;
const pace = (s) => new Promise((r) => setTimeout(r, s * 1000 * (FAST ? 0.35 : 1)));
const quiet = { info: process.env.DEMO_DEBUG ? (m) => console.log(`  [server] ${m}`) : () => {}, warn: (m) => console.warn(`  [server] ${m}`), error: (m) => console.error(`  [server] ${m}`) };
const SILENCE_20MS = Buffer.alloc(160, 0xff).toString("base64");

// ---------------------------------------------------------------- the scripted agent (fake OpenAI Realtime)

class ScriptedAgent {
  events = [];
  #cursor = 0;
  #pending = 0; // response.create requests not yet answered
  #n = 0;

  constructor(ws) {
    this.ws = ws;
    ws.on("message", (d) => {
      const ev = JSON.parse(d.toString());
      if (ev.type === "response.create") this.#pending++;
      if (process.env.DEMO_DEBUG && ev.type !== "input_audio_buffer.append") console.log(`    <- ${ev.type}${ev.item ? " " + (ev.item.type ?? "") + " " + (ev.item.role ?? ev.item.call_id ?? "") : ""} pending=${this.#pending}`);
      this.events.push(ev);
    });
  }

  send(ev) {
    if (this.ws.readyState === 1) this.ws.send(JSON.stringify(ev));
  }

  // The next client event matching `pred` after the last one consumed.
  async next(pred, seconds = 30) {
    const end = Date.now() + seconds * 1000;
    for (;;) {
      for (let i = this.#cursor; i < this.events.length; i++) {
        if (pred(this.events[i])) {
          this.#cursor = i + 1;
          return this.events[i];
        }
      }
      if (Date.now() > end) return null;
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  // A SHIP EVENT the server dropped into the conversation.
  shipEvent(kindRe, seconds = 60) {
    return this.next((e) => e.type === "conversation.item.create" && e.item?.role === "system" && kindRe.test(e.item.content?.[0]?.text ?? ""), seconds);
  }

  #turn() {
    if (this.#pending > 0) this.#pending--;
    const id = ++this.#n;
    this.send({ type: "response.created", response: { id: `resp_${id}` } });
    return id;
  }

  // Speak a line: audio, transcript, done.
  async say(text) {
    const id = this.#turn();
    const item = `item_a${id}`;
    const words = text.split(" ");
    const step = Math.max(1, Math.ceil(words.length / 5));
    for (let i = 0; i < words.length; i += step) {
      this.send({ type: "response.output_audio.delta", item_id: item, delta: SILENCE_20MS });
      this.send({ type: "response.output_audio_transcript.delta", item_id: item, delta: words.slice(i, i + step).join(" ") + " " });
      await pace(Math.min(0.6, step * 0.18));
    }
    this.send({ type: "response.output_audio_transcript.done", item_id: item, transcript: text });
    this.send({ type: "response.output_audio.done", item_id: item });
    this.send({ type: "response.done", response: { id: `resp_${id}`, status: "completed", output: [{ type: "message", role: "assistant", id: item }] } });
    console.log(`agent:  ${text}`);
    await pace(0.8 + text.length / 45);
  }

  // Call one of the ship's tools and return its output.
  async tool(name, args = {}) {
    const id = this.#turn();
    const callId = `call_${id}`;
    const call = { type: "function_call", call_id: callId, name, arguments: JSON.stringify(args) };
    this.send({ type: "response.function_call_arguments.done", call_id: callId, name, arguments: call.arguments });
    this.send({ type: "response.done", response: { id: `resp_${id}`, status: "completed", output: [call] } });
    const out = await this.next((e) => e.type === "conversation.item.create" && e.item?.call_id === callId, 30);
    const result = out ? JSON.parse(out.item.output) : { ok: false, message: "no answer" };
    console.log(`  [tool] ${name} ${JSON.stringify(args)} -> ${result.message ?? ""}`);
    return result;
  }

  // The caller speaks (server VAD's events, and the transcription of their words).
  async caller(text) {
    const item = `item_u${++this.#n}`;
    this.send({ type: "input_audio_buffer.speech_started", audio_start_ms: 0, item_id: item });
    const words = text.split(" ");
    for (let i = 0; i < words.length; i += 2) {
      this.send({ type: "conversation.item.input_audio_transcription.delta", item_id: item, content_index: 0, delta: words.slice(i, i + 2).join(" ") + " " });
      await pace(0.25);
    }
    this.send({ type: "input_audio_buffer.speech_stopped", audio_end_ms: 1000, item_id: item });
    this.send({ type: "conversation.item.input_audio_transcription.completed", item_id: item, content_index: 0, transcript: text });
    console.log(`caller: ${text}`);
    await pace(0.6);
  }
}

// ---------------------------------------------------------------- the call

// Wait for this specific instruction; cancellation is not arrival.
async function untilArrived(agent, instructionId, seconds = 120) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    const ev = await agent.shipEvent(/SHIP EVENT \((instruction_completed|instruction_cancelled)\)/, 2);
    if (!ev) continue;
    const text = ev.item.content[0].text;
    if (!text.includes(`"instruction_id":${instructionId},`)) continue;
    return text.includes('(instruction_completed)');
  }
  return false;
}

async function script(agent) {
  await agent.next((e) => e.type === "session.update", 30);
  await agent.say("Thank you for calling Sub-Dimensional Support, you're through to Gary in Tier 2. I can see your ticket here... ah. You've punched yourself into a fractal.");
  await agent.caller("Yeah. What happened? I just pressed the jump button.");
  const status = await agent.tool("get_ship_status");
  const w = status.world ?? {};
  await agent.say(
    w.type === "Mandelbox"
      ? `Right, so, technically: your jump vector clipped a box fold at scale minus ${String(Math.abs(w.scale)).replace(".", " point ")}, got sphere-inverted between radius ${w.min_radius} and ${w.fixed_radius}, and your running derivative went to infinity, which collapsed the Lipschitz bound. You're now living on a surface of Hausdorff dimension about two point eight. Very fashionable.`
      : "Right, so, technically: your manifolds came back as animalifolds. Very fashionable.",
  );
  await agent.caller("Can you get me out?");
  await agent.tool("scan_surroundings");
  await agent.say("Absolutely. Sensor sweep's done. This call may be recorded for quality and training purposes across all branches of the fractal.");

  for (let leg = 0; leg < 12; leg++) {
    const s = await agent.tool("get_ship_status");
    if (!s.in_flight || s.escape?.escaped) break;
    const route = await agent.tool("plan_escape");
    if (!route.ok || route.scene_or_pose_changed || !route.points?.length) break;
    const point = route.points[0];
    await agent.tool("point_direction", { point, label: "Escape route" });
    await agent.tool("post_to_log", { message: "Estimated escape route selected. Flying the next leg at Gameplay speed." });
    await agent.say("I've compared the travel times. Taking the next leg toward open space now.");
    const result = await agent.tool("fly_to_point", { point });
    if (!result.ok || !await untilArrived(agent, result.instruction_id)) break;
  }
  const final = await agent.tool("get_ship_status");
  await agent.say(final.escape?.escaped
    ? "And you are out! Welcome back to ordinary three-space. Thank you for calling Sub-Dimensional Support."
    : "We're still inside the fractal. I'll leave the controls with you; call again when you'd like more help.");
}

// ---------------------------------------------------------------- run it

const fakeOpenAI = new WebSocketServer({ port: 0, host: "127.0.0.1" });
await once(fakeOpenAI, "listening");
const agentReady = new Promise((resolve) => fakeOpenAI.on("connection", (ws) => resolve(new ScriptedAgent(ws))));

const config = loadConfig({
  ...process.env,
  VOICE_AGENT: "openai",
  OPENAI_API_KEY: "demo",
  OPENAI_REALTIME_URL: `ws://127.0.0.1:${fakeOpenAI.address().port}/v1/realtime`,
  TWILIO_AUTH_TOKEN: AUTH,
  GAME_LINK_TOKEN: LINK,
  ALLOWED_CALLERS: CALLER,
  TWILIO_PHONE_NUMBER: process.env.TWILIO_PHONE_NUMBER || "+15550109001",
  PUBLIC_BASE_URL: "",
});
const { server, game } = createApp(config, { log: quiet });
server.listen(DEMO_PORT, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
config.publicBaseUrl = base;

// Wait for the game and its call centre, and for the crash report to finish.
let link = null;
if (IN_GAME_LINK) {
  console.log(`Waiting for the game to dial in: start it with FRACTAL_SERVER_URL=${base} GAME_LINK_TOKEN=${LINK}`);
  for (;;) {
    try {
      if (game.connected) {
        const r = await game.call("ship_events", { after: 0, timeout: 1 }, 5000);
        if (r.events.some((e) => e.stage === "awaiting_call")) break;
      }
    } catch {
      // no call centre yet
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  console.log(`The game linked itself (${game.info?.server_link?.url ?? "in-game link"}). Ringing...`);
} else {
  console.log(`Waiting for the game's bridge on 127.0.0.1:${BRIDGE_PORT} (call_center/run.sh --demo)...`);
  const probe = new BridgeClient({ port: BRIDGE_PORT });
  for (;;) {
    try {
      const r = await probe.call("ship_events", { after: 0, timeout: 1 }, 5000);
      if (r.events.some((e) => e.stage === "awaiting_call")) break;
    } catch {
      // not up yet, or no call centre yet
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  probe.close();
  link = startLink({ serverUrl: base, token: LINK, bridgePort: BRIDGE_PORT, log: { info() {}, warn: console.warn } });
  while (!game.connected) await new Promise((r) => setTimeout(r, 100));
  console.log("Game linked. Ringing...");
}
await pace(3);

// The call: Twilio's webhook, then its media stream.
const params = { From: CALLER, CallSid: "CAdemo" };
const twiml = await (
  await fetch(base + "/twilio/voice", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "X-Twilio-Signature": twilio.getExpectedTwilioSignature(AUTH, base + "/twilio/voice", params) },
    body: new URLSearchParams(params),
  })
).text();
const token = /name="token" value="([^"]+)"/.exec(twiml)?.[1];
if (!token) throw new Error(`the webhook did not stream the call: ${twiml}`);
await pace(2);
const mediaUrl = wsUrl(base, "/twilio/media");
const twilioWs = new WebSocket(mediaUrl, { headers: { "X-Twilio-Signature": twilio.getExpectedTwilioSignature(AUTH, mediaUrl, {}) } });
await once(twilioWs, "open");
let heard = 0;
twilioWs.on("message", (d) => {
  const m = JSON.parse(d.toString());
  if (m.event === "media") heard++;
  if (m.event === "mark") twilioWs.send(JSON.stringify({ event: "mark", streamSid: "MZdemo", mark: m.mark })); // "played"
});
twilioWs.send(JSON.stringify({ event: "connected", protocol: "Call", version: "1.0.0" }));
twilioWs.send(JSON.stringify({ event: "start", streamSid: "MZdemo", start: { streamSid: "MZdemo", callSid: "CAdemo", customParameters: { token } } }));
let ts = 0;
const mic = setInterval(() => {
  ts += 20;
  if (twilioWs.readyState === 1) twilioWs.send(JSON.stringify({ event: "media", streamSid: "MZdemo", media: { track: "inbound", timestamp: String(ts), payload: SILENCE_20MS } }));
}, 20);

const agent = await agentReady;
await script(agent);
const sent = agent.events.filter((e) => e.type === "input_audio_buffer.append").length;
clearInterval(mic);
twilioWs.send(JSON.stringify({ event: "stop", streamSid: "MZdemo", stop: { callSid: "CAdemo" } }));
await pace(2);
console.log(`Call finished: ${heard} audio chunks reached the caller, ${sent} reached the agent.`);
link?.stop();
server.close();
server.closeAllConnections?.();
fakeOpenAI.close();
process.exit(0);
