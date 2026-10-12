import { test } from "node:test";
import assert from "node:assert/strict";
import { validateHeaderValue } from "node:http";
import { loadConfig, configProblems, openaiKeyProblem } from "../src/config.mjs";
import { RealtimeSession } from "../src/voice/realtime.mjs";

test("copied surrounding whitespace is removed before building the authorization header", () => {
  const config = loadConfig({ OPENAI_API_KEY: " \r\nsk-proj-example_123-abc\n " });
  assert.equal(config.openai.apiKey, "sk-proj-example_123-abc");
  assert.doesNotThrow(() => validateHeaderValue("Authorization", `Bearer ${config.openai.apiKey}`));
  assert.equal(openaiKeyProblem(config.openai.apiKey), "");
});

test("embedded newlines and hidden Unicode are diagnosed without printing the key", () => {
  for (const character of ["\n", "\u200b", "\u2026"]) {
    const key = `sk-proj-secret${character}suffix`;
    const config = loadConfig({ OPENAI_API_KEY: key });
    const problem = openaiKeyProblem(config.openai.apiKey);
    assert.match(problem, /OPENAI_API_KEY contains an invalid character \(U\+/);
    assert.equal(problem.includes("secret"), false);
    assert.ok(configProblems(config).includes(problem));
    let socketCreated = false;
    const session = new RealtimeSession({ config: config.openai, WebSocketImpl: class { constructor() { socketCreated = true; } } });
    assert.throws(() => session.connect(), { message: problem });
    assert.equal(socketCreated, false);
  }
});
