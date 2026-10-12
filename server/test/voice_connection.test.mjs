import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { VoiceCalls } from "../src/voice/voice_calls.mjs";
import { loadConfig } from "../src/config.mjs";

class FailedSocket extends EventEmitter {
  constructor() { super(); this.readyState = 0; }
  close() { this.readyState = 3; }
}

test("an upstream connection error ends the call without crashing and frees the line", async () => {
  const notices = [];
  const game = Object.assign(new EventEmitter(), {
    call: async () => ({ tools: [] }),
    notify: (message) => notices.push(message),
  });
  const log = { info() {}, error() {}, warn() {} };
  const calls = new VoiceCalls(game, loadConfig({ OPENAI_API_KEY: "test" }), { log, WebSocketImpl: FailedSocket });
  const call = calls.newCall({ callSid: "connection-failure" });
  await call.start();
  let reason;
  call.on("ended", (value) => { reason = value; });
  assert.doesNotThrow(() => call.session.ws.emit("error", new Error("upstream rejected connection")));
  assert.equal(call.ended, true);
  assert.equal(calls.busy, false);
  assert.match(reason, /upstream rejected connection/);
  assert.equal(call.session.ws.readyState, 3);
  assert.equal(game.listenerCount("ship_event"), 0);
  assert.equal(notices.filter((message) => message.type === "call_ended").length, 1);
});


test("voice excludes scripted question tools and ignores legacy question events", async () => {
  const game = Object.assign(new EventEmitter(), {
    call: async () => ({ tools: [{ name: "resolve_issue" }, { name: "get_console_controls" }, { name: "set_console_controls" }, { name: "console_action" }] }),
    notify() {},
  });
  const log = { info() {}, error() {}, warn() {} };
  const calls = new VoiceCalls(game, loadConfig({ OPENAI_API_KEY: "test" }), { log, WebSocketImpl: FailedSocket });
  const call = calls.newCall();
  await call.start();
  assert.deepEqual(call.toolNames, ["get_console_controls", "set_console_controls", "console_action"]);
  const messages = [];
  call.session.injectSystem = (text) => messages.push(text);
  game.emit("ship_event", { kind: "pilot_input_required", notify_agent: true, summary: "What rhymes with fractal?" });
  assert.equal(messages.length, 0);
  game.emit("ship_event", { kind: "waypoint_reached", notify_agent: true, summary: "Arrived." });
  assert.equal(messages.length, 1);
  call.end();
});
