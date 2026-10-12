// The OpenAI voice agent (VOICE_AGENT=openai) end to end, locally: a fake
// Twilio (signed webhook, signed media socket), the real server, the real
// link, a fake game bridge with a pilot chat and a call centre, and a fake
// OpenAI Realtime server standing in for the voice agent.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import twilio from "twilio";
import { WebSocket } from "ws";
import { loadConfig } from "../src/config.mjs";
import { createApp, wsUrl } from "../src/app.mjs";
import { startLink } from "../link/link.mjs";
import { fakeOpenAI, fakeCallCenterBridge, until, quiet, SHIP_TOOLS } from "./fakes.mjs";

const AUTH = "test-auth-token";
const TOKEN = "test-link-token";
const CALLER = "+15550001234";

let config, server, game, voice, base, bridge, link, openai;

before(async () => {
  openai = await fakeOpenAI();
  bridge = await fakeCallCenterBridge();
  config = loadConfig({
    TWILIO_AUTH_TOKEN: AUTH,
    GAME_LINK_TOKEN: TOKEN,
    ALLOWED_CALLERS: CALLER,
    OPENAI_API_KEY: "sk-test",
    OPENAI_REALTIME_URL: `ws://127.0.0.1:${openai.port}/v1/realtime`,
    TWILIO_PHONE_NUMBER: "+15550109001",
  });
  ({ server, game, voice } = createApp(config, { log: quiet }));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  base = `http://127.0.0.1:${server.address().port}`;
  config.publicBaseUrl = base;
  link = startLink({ serverUrl: base, token: TOKEN, bridgePort: bridge.port, log: quiet });
  await until(() => game.connected, 3000, "link");
});

after(async () => {
  link?.stop();
  await new Promise((r) => server.close(r));
  server.closeAllConnections?.();
  bridge.server.close();
  await openai.close();
});

function signedPost(path, params) {
  const sig = twilio.getExpectedTwilioSignature(AUTH, base + path, params);
  return fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "X-Twilio-Signature": sig },
    body: new URLSearchParams(params),
  });
}

async function mediaSocket({ signed = true } = {}) {
  const url = wsUrl(base, "/twilio/media");
  const headers = signed ? { "X-Twilio-Signature": twilio.getExpectedTwilioSignature(AUTH, url, {}) } : {};
  const ws = new WebSocket(url, { headers });
  const inbox = [];
  ws.on("message", (d) => inbox.push(JSON.parse(d.toString())));
  await new Promise((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("unexpected-response", (_req, res) => reject(Object.assign(new Error("refused"), { status: res.statusCode })));
    ws.once("error", reject);
  });
  return { ws, inbox, send: (m) => ws.send(JSON.stringify(m)), of: (e) => inbox.filter((m) => m.event === e) };
}

test("the config tells the call centre the support number, and the line is up", async () => {
  await until(() => bridge.state.callCenter.support_number, 3000, "call_center config");
  assert.equal(bridge.state.callCenter.support_number, "+1 (555) 010-9001");
  assert.equal(bridge.state.callCenter.link_up, true);
  assert.equal(config.voiceAgent, "openai");
});

test("an unsigned media socket is refused", async () => {
  await assert.rejects(mediaSocket({ signed: false }), (e) => e.status === 403);
});

test("a phone call with the OpenAI voice agent, through the link to the call centre", async () => {
  const said = [];
  game.on("say", (t) => said.push(t));

  // the webhook streams the call to /twilio/media with a one-time token
  const r = await signedPost("/twilio/voice", { From: CALLER, CallSid: "CA1" });
  const twiml = await r.text();
  assert.match(twiml, new RegExp(`<Stream url="${wsUrl(base, "/twilio/media")}">`));
  const token = /name="token" value="([^"]+)"/.exec(twiml)?.[1];
  assert.ok(token, "the TwiML carries a token");
  await until(() => bridge.state.callCenter.call_state === "ringing", 3000, "ringing");

  const tw = await mediaSocket();
  tw.send({ event: "connected", protocol: "Call", version: "1.0.0" });
  tw.send({ event: "start", streamSid: "MZ1", start: { streamSid: "MZ1", callSid: "CA1", customParameters: { token } } });

  // the session: phone audio, the ship's tools from the game, the persona, a greeting
  const update = await until(() => openai.of("session.update")[0], 3000, "session.update");
  assert.equal(openai.headers.authorization, "Bearer sk-test");
  assert.match(openai.url, /model=gpt-realtime-2\.1/);
  assert.deepEqual(update.session.audio.input.format, { type: "audio/pcmu" });
  assert.deepEqual(update.session.audio.output.format, { type: "audio/pcmu" });
  assert.deepEqual(update.session.tools.map((t) => t.name), SHIP_TOOLS.filter((t) => t.name !== "resolve_issue").map((t) => t.name));
  assert.equal(update.session.tools[1].parameters.required[0], "feature_id");
  assert.match(update.session.instructions, /Sub-Dimensional Support/);
  await until(() => openai.of("response.create").length === 1, 3000, "greeting");
  await until(() => bridge.state.callCenter.call_state === "connected", 3000, "connected");
  assert.equal(bridge.state.callCenter.agent_name, "Gary");
  await until(() => bridge.chat.some((m) => m.role === "system" && /Phone call connected/.test(m.text)), 3000, "chat notice");

  // caller audio reaches OpenAI untouched; agent audio reaches Twilio with a mark
  tw.send({ event: "media", streamSid: "MZ1", media: { track: "inbound", chunk: "1", timestamp: "20", payload: "AAAA" } });
  await until(() => openai.of("input_audio_buffer.append").length === 1, 3000, "append");
  assert.equal(openai.of("input_audio_buffer.append")[0].audio, "AAAA");
  openai.send({ type: "response.created", response: { id: "r1" } });
  const chunk = Buffer.alloc(160, 0xff).toString("base64");
  openai.send({ type: "response.output_audio.delta", item_id: "a1", delta: chunk });
  await until(() => tw.of("media").length === 1 && tw.of("mark").length === 1, 3000, "audio out");

  // a tool call runs on the game's call centre, its output goes back after response.done
  openai.send({ type: "response.function_call_arguments.done", call_id: "call_1", name: "fly_to_feature", arguments: '{"feature_id":"#2312"}' });
  await until(() => bridge.requests("ship_tool").length === 1, 3000, "ship_tool");
  assert.deepEqual(bridge.requests("ship_tool")[0].args, { name: "fly_to_feature", arguments: { feature_id: "#2312" } });
  openai.send({ type: "response.done", response: { id: "r1", status: "completed", output: [{ type: "function_call", call_id: "call_1", name: "fly_to_feature", arguments: '{"feature_id":"#2312"}' }] } });
  const out = await until(() => openai.of("conversation.item.create").find((e) => e.item.type === "function_call_output"), 3000, "output");
  assert.equal(JSON.parse(out.item.output).message, "did fly_to_feature");
  await until(() => openai.of("response.create").length === 2, 3000, "response after tool");

  // what the agent says lands in the pilot chat as a "phone" line, and is not spoken twice
  openai.send({ type: "response.output_audio_transcript.done", item_id: "a1", transcript: "See characteristic #2312, off to your left?" });
  await until(() => bridge.chat.some((m) => m.role === "agent" && m.source === "phone" && /#2312/.test(m.text)), 3000, "agent line");
  // the caller's words: live in the chat box, then as a voice message
  openai.send({ type: "conversation.item.input_audio_transcription.delta", item_id: "u1", delta: "Fly me " });
  await until(() => bridge.state.drafts.includes("Fly me"), 3000, "draft");
  openai.send({ type: "conversation.item.input_audio_transcription.completed", item_id: "u1", transcript: "Fly me there." });
  await until(() => bridge.chat.some((m) => m.role === "human" && m.source === "voice" && m.text === "Fly me there."), 3000, "caller line");

  // the call centre's news reaches the agent as a SHIP EVENT; quiet events stay out
  bridge.pushEvent({ kind: "stage", summary: "quiet", notify_agent: false });
  bridge.pushEvent({ kind: "waypoint_reached", summary: "Waypoint reached.", notify_agent: true });
  const sys = await until(() => openai.of("conversation.item.create").find((e) => e.item.role === "system" && /SHIP EVENT/.test(e.item.content[0].text)), 4000, "ship event");
  assert.match(sys.item.content[0].text, /^SHIP EVENT \(waypoint_reached\): Waypoint reached/);
  assert.equal(openai.of("conversation.item.create").filter((e) => e.item.role === "system" && /quiet/.test(e.item.content[0].text)).length, 0);

  // what the pilot types in the chat goes to the agent
  bridge.addChat("human", "Can you highlight it?", "typed");
  const typed = await until(() => openai.of("conversation.item.create").find((e) => e.item.role === "user"), 4000, "typed chat");
  assert.equal(typed.item.content[0].text, "(typed in the pilot chat) Can you highlight it?");

  // a tool the game adds mid-call reaches the session
  bridge.state.tools = [...SHIP_TOOLS, { name: "open_airlock", description: "open it", inputSchema: { type: "object", properties: {} } }];
  bridge.pushEvent({ kind: "tools_changed", summary: "", notify_agent: false });
  await until(() => openai.of("session.update").some((e) => e.session.tools?.length === 3), 4000, "tools pushed");

  // barge-in: the caller talks over 20 ms into a 40 ms item
  openai.send({ type: "response.created", response: { id: "r3" } });
  openai.send({ type: "response.output_audio.delta", item_id: "a2", delta: chunk });
  openai.send({ type: "response.output_audio.delta", item_id: "a2", delta: chunk });
  await until(() => tw.of("mark").length === 3, 3000, "marks");
  tw.send({ event: "mark", streamSid: "MZ1", mark: { name: tw.of("mark")[1].mark.name } });
  await new Promise((r) => setTimeout(r, 30));
  openai.send({ type: "input_audio_buffer.speech_started", audio_start_ms: 1000, item_id: "u2" });
  const trunc = await until(() => openai.of("conversation.item.truncate")[0], 3000, "truncate");
  assert.deepEqual(trunc, { type: "conversation.item.truncate", item_id: "a2", content_index: 0, audio_end_ms: 20 });
  await until(() => tw.of("clear").length === 1, 3000, "clear");

  // one call at a time
  const busy = await (await signedPost("/twilio/voice", { From: CALLER, CallSid: "CA2" })).text();
  assert.match(busy, /All of our agents are currently assisting/);

  // hang up
  tw.send({ event: "stop", streamSid: "MZ1", stop: { callSid: "CA1" } });
  await until(() => bridge.state.callCenter.call_state === "ended", 3000, "ended");
  await until(() => bridge.chat.some((m) => m.role === "system" && m.text === "Phone call ended"), 3000, "chat notice");
  await until(() => !voice.busy, 3000, "call cleared");
  await until(() => openai.sockets.every((s) => s.readyState !== 1), 3000, "openai closed");
  assert.deepEqual(said, [], "the phone agent's chat lines are never sent back to be spoken");
});

test("/mcp serves the call centre's ship tools through the link", async () => {
  const rpc = async (body, auth = true) => {
    const res = await fetch(base + "/mcp", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(auth ? { Authorization: `Bearer ${TOKEN}` } : {}) },
      body: JSON.stringify(body),
    });
    return { status: res.status, body: res.status === 200 ? await res.json() : null };
  };
  assert.equal((await rpc({ jsonrpc: "2.0", id: 1, method: "ping" }, false)).status, 401);
  const init = await rpc({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
  assert.equal(init.body.result.protocolVersion, "2025-06-18");
  const listed = await rpc({ jsonrpc: "2.0", id: 2, method: "tools/list" });
  assert.ok(listed.body.result.tools.some((t) => t.name === "fly_to_feature"));
  const called = await rpc({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_ship_status", arguments: {} } });
  assert.equal(JSON.parse(called.body.result.content[0].text).message, "did get_ship_status");
  assert.equal(called.body.result.isError, false);
  const unknown = await rpc({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "warp", arguments: {} } });
  assert.match(unknown.body.error.message, /unknown ship tool/);
  assert.equal((await rpc({ jsonrpc: "2.0", method: "notifications/initialized" })).status, 202);
});

test("sockets outlive the heartbeat (the link and a call are not dropped as dead)", async () => {
  const { server: hbServer, game: hbGame } = createApp(
    loadConfig({ GAME_LINK_TOKEN: TOKEN, ALLOWED_CALLERS: CALLER, TWILIO_VALIDATE: "false" }),
    { log: quiet, heartbeatMs: 40 },
  );
  hbServer.listen(0, "127.0.0.1");
  await once(hbServer, "listening");
  const hbBase = `http://127.0.0.1:${hbServer.address().port}`;
  let drops = 0;
  hbGame.on("disconnected", () => drops++);
  const hbLink = startLink({ serverUrl: hbBase, token: TOKEN, bridgePort: bridge.port, log: quiet });
  try {
    await until(() => hbGame.connected, 3000, "link");
    const media = new WebSocket(wsUrl(hbBase, "/twilio/media"));
    await once(media, "open");
    let mediaClosed = false;
    media.on("close", () => (mediaClosed = true));
    await new Promise((r) => setTimeout(r, 400)); // ten heartbeats
    assert.equal(drops, 0, "the link survived");
    assert.equal(hbGame.connected, true);
    assert.equal(mediaClosed, false, "the media socket survived");
    media.close();
  } finally {
    hbLink.stop();
    await new Promise((r) => hbServer.close(r));
    hbServer.closeAllConnections?.();
  }
});

test("a bad media token is refused", async () => {
  const tw = await mediaSocket();
  const closed = new Promise((r) => tw.ws.on("close", (code) => r(code)));
  tw.send({ event: "start", streamSid: "MZ9", start: { streamSid: "MZ9", callSid: "CA9", customParameters: { token: "forged" } } });
  assert.equal(await closed, 1008);
  assert.equal(voice.busy, false);
});
