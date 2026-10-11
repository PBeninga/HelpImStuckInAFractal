// The phone server end to end, locally: a fake Twilio (signed webhooks and a
// signed ConversationRelay socket), the real link, and a fake game bridge that
// speaks McpBridge's line protocol.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import twilio from "twilio";
import { WebSocket } from "ws";
import { loadConfig } from "../src/config.mjs";
import { createApp, wsUrl } from "../src/app.mjs";
import { startLink } from "../link/link.mjs";

const AUTH = "test-auth-token";
const TOKEN = "test-link-token";
const CALLER = "+15550001234";
const quiet = { info() {}, warn() {}, error() {} };

// ---------------------------------------------------------------- fake game bridge

function fakeBridge() {
  const chat = []; // {id, role, text, source}
  const calls = [];
  let nextId = 1;
  const add = (role, text, source = "") => {
    const m = { id: nextId++, role, text, source };
    chat.push(m);
    return m;
  };
  const server = net.createServer((sock) => {
    let buf = "";
    sock.setEncoding("utf8");
    sock.on("data", async (chunk) => {
      buf += chunk;
      let nl;
      while ((nl = buf.indexOf("\n")) !== -1) {
        const req = JSON.parse(buf.slice(0, nl));
        buf = buf.slice(nl + 1);
        calls.push(req);
        const reply = (result) => sock.write(JSON.stringify({ id: req.id, ok: true, result }) + "\n");
        const a = req.args || {};
        switch (req.cmd) {
          case "status":
            reply({ in_game: true });
            break;
          case "chat_post":
            reply(add(a.role || "human", a.text, a.source ?? "voice"));
            break;
          case "chat_draft":
            reply({});
            break;
          case "chat_watch": {
            const last = () => (chat.length ? chat[chat.length - 1].id : 0);
            if (a.after === undefined) {
              reply({ messages: [], last_id: last() });
              break;
            }
            const deadline = Date.now() + (a.timeout ?? 20) * 1000;
            while (!chat.some((m) => m.id > a.after) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 20));
            reply({ messages: chat.filter((m) => m.id > a.after), last_id: Math.max(last(), a.after) });
            break;
          }
          default:
            sock.write(JSON.stringify({ id: req.id, ok: false, error: `unknown command '${req.cmd}'` }) + "\n");
        }
      }
    });
  });
  return { server, chat, calls, add };
}

// ---------------------------------------------------------------- harness

let config, server, game, base, bridge, link;

before(async () => {
  bridge = fakeBridge();
  bridge.server.listen(0, "127.0.0.1");
  await once(bridge.server, "listening");

  config = loadConfig({
    TWILIO_AUTH_TOKEN: AUTH,
    GAME_LINK_TOKEN: TOKEN,
    ALLOWED_CALLERS: CALLER,
  });
  ({ server, game } = createApp(config, { log: quiet }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  base = `http://127.0.0.1:${server.address().port}`;
  config.publicBaseUrl = base; // what Twilio would be told, and signs over
});

after(async () => {
  link?.stop();
  await new Promise((r) => server.close(r));
  server.closeAllConnections?.();
  bridge.server.close();
});

function signedPost(path, params) {
  const sig = twilio.getExpectedTwilioSignature(AUTH, base + path, params);
  return fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "X-Twilio-Signature": sig },
    body: new URLSearchParams(params),
  });
}

async function relaySocket() {
  const url = wsUrl(base, "/twilio/relay");
  const ws = new WebSocket(url, { headers: { "X-Twilio-Signature": twilio.getExpectedTwilioSignature(AUTH, url, {}) } });
  await once(ws, "open");
  const inbox = [];
  ws.on("message", (d) => inbox.push(JSON.parse(d.toString())));
  return { ws, inbox, send: (m) => ws.send(JSON.stringify(m)) };
}

async function until(fn, ms = 3000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = await fn();
    if (v) return v;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error("timed out waiting");
}

// ---------------------------------------------------------------- tests

test("health reports no game linked", async () => {
  const r = await (await fetch(base + "/health")).json();
  assert.deepEqual(r, { ok: true, game_linked: false, calls: 0 });
});

test("an unsigned voice webhook is refused", async () => {
  const r = await fetch(base + "/twilio/voice", { method: "POST", body: new URLSearchParams({ From: CALLER }) });
  assert.equal(r.status, 403);
});

test("an unknown caller is told no and hung up on", async () => {
  const xml = await (await signedPost("/twilio/voice", { From: "+15559999999", CallSid: "CA1" })).text();
  assert.match(xml, /can't pilot/);
  assert.match(xml, /<Hangup\/>/);
  assert.doesNotMatch(xml, /ConversationRelay/);
});

test("an allowed caller hears that the game is offline when nothing is linked", async () => {
  const xml = await (await signedPost("/twilio/voice", { From: CALLER, CallSid: "CA2" })).text();
  assert.match(xml, /offline/);
});

test("the link needs the token", async () => {
  const ws = new WebSocket(wsUrl(base, "/game/link"), { headers: { Authorization: "Bearer wrong" } });
  const [, res] = await once(ws, "unexpected-response");
  assert.equal(res.statusCode, 401);
});

test("an unsigned relay socket is refused", async () => {
  const ws = new WebSocket(wsUrl(base, "/twilio/relay"));
  const [, res] = await once(ws, "unexpected-response");
  assert.equal(res.statusCode, 403);
});

test("the link joins the game, and calls connect to ConversationRelay", async () => {
  link = startLink({ serverUrl: base, token: TOKEN, bridgePort: bridge.server.address().port, log: quiet });
  await until(() => game.connected && game.info);
  assert.deepEqual(game.info, { in_game: true }, "the link says hello with the game's status");

  const xml = await (await signedPost("/twilio/voice", { From: CALLER, CallSid: "CA3" })).text();
  assert.match(xml, /<Connect action="[^"]*\/twilio\/session-end">/);
  assert.match(xml, new RegExp(`<ConversationRelay url="${wsUrl(base, "/twilio/relay")}"`));
  assert.match(xml, /welcomeGreeting=/);
});

test("speech goes into the pilot chat and agent replies are spoken", async () => {
  const call = await relaySocket();
  call.send({ type: "setup", callSid: "CA4", from: CALLER, to: "+15550000000" });
  await until(() => bridge.chat.find((m) => m.role === "system" && m.text.includes("…1234")));

  call.send({ type: "prompt", voicePrompt: "dive into the cube", lang: "en-US", last: true });
  const said = await until(() => bridge.chat.find((m) => m.text === "dive into the cube"));
  assert.equal(said.source, "voice");

  call.send({ type: "prompt", voicePrompt: "turn le", last: false });
  await until(() => bridge.calls.find((c) => c.cmd === "chat_draft" && c.args.text === "turn le"));

  bridge.add("agent", "Diving in now.");
  const spoken = await until(() => call.inbox.find((m) => m.type === "text"));
  assert.deepEqual(spoken, { type: "text", token: "Diving in now.", last: true });

  const status = await (await fetch(base + "/api/status", { headers: { Authorization: `Bearer ${TOKEN}` } })).json();
  assert.deepEqual(status.calls, [{ callSid: "CA4", from: CALLER }]);

  call.ws.close();
  await until(() => bridge.chat.find((m) => m.text === "Phone call ended"));
});

test("a relay setup from a stranger is ended", async () => {
  const call = await relaySocket();
  call.send({ type: "setup", callSid: "CA5", from: "+15559999999" });
  await once(call.ws, "close");
  assert.deepEqual(call.inbox, [{ type: "end" }]);
});

test("the API runs bridge commands on the game, behind the token", async () => {
  const auth = { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" };
  let r = await fetch(base + "/api/game/status", { method: "POST", headers: auth, body: "{}" });
  assert.deepEqual(await r.json(), { ok: true, result: { in_game: true } });
  r = await fetch(base + "/api/game/nope", { method: "POST", headers: auth, body: "{}" });
  assert.equal(r.status, 400);
  assert.match((await r.json()).error, /unknown command/);
  r = await fetch(base + "/api/game/status", { method: "POST" });
  assert.equal(r.status, 401);
});
