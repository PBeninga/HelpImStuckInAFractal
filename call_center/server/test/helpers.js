// Test doubles: a fake OpenAI Realtime server, a fake game (the ship's MCP
// server dialling in), a Twilio media-stream client, and a quiet logger.

import { WebSocketServer, WebSocket } from 'ws';
import { createRelay } from '../src/server.js';
import { loadConfig } from '../src/config.js';

export const quiet = { info() {}, warn() {}, error() {} };

/** Resolve when `pred()` is truthy (polling), or reject after `ms`. */
export async function until(pred, ms = 2000, what = 'condition') {
  const t0 = Date.now();
  for (;;) {
    const v = pred();
    if (v) return v;
    if (Date.now() - t0 > ms) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 5));
  }
}

/** A stand-in for wss://api.openai.com/v1/realtime that records client events. */
export async function fakeOpenAI() {
  const wss = new WebSocketServer({ port: 0 });
  const fake = {
    events: [],
    sockets: [],
    headers: null,
    url: null,
    port: 0,
    send(ev) {
      for (const s of fake.sockets) if (s.readyState === 1) s.send(JSON.stringify(ev));
    },
    of(type) {
      return fake.events.filter((e) => e.type === type);
    },
    close() {
      for (const s of fake.sockets) s.terminate();
      return new Promise((r) => wss.close(() => r()));
    },
  };
  wss.on('connection', (ws, req) => {
    fake.sockets.push(ws);
    fake.headers = req.headers;
    fake.url = req.url;
    ws.on('message', (d) => fake.events.push(JSON.parse(d.toString())));
  });
  await new Promise((r) => wss.on('listening', r));
  fake.port = wss.address().port;
  return fake;
}

export const FAKE_TOOLS = [
  { name: 'get_ship_status', description: 'status', inputSchema: { type: 'object', properties: {} } },
  { name: 'fly_to_feature', description: 'fly', inputSchema: { type: 'object', properties: { feature_id: { type: 'string' } }, required: ['feature_id'] } },
];

/** A fake game: answers MCP on the ship link and records what it is sent. */
export async function fakeGame(port, { token = '' } = {}) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/game${token ? `?token=${token}` : ''}`);
  const game = {
    ws,
    requests: [],
    notifications: [],
    calls: [],
    tools: [...FAKE_TOOLS],
    toolResult: (name, args) => ({ ok: true, message: `did ${name}`, args }),
    announceToolsChanged() {
      ws.send(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/tools/list_changed' }));
    },
    sendEvent(params) {
      ws.send(JSON.stringify({ jsonrpc: '2.0', method: 'ship/event', params }));
    },
    notes(method) {
      return game.notifications.filter((n) => n.method === method);
    },
    close() {
      ws.close();
    },
  };
  ws.on('message', (d) => {
    const msg = JSON.parse(d.toString());
    if (msg.id === undefined) {
      game.notifications.push(msg);
      return;
    }
    game.requests.push(msg);
    let result;
    if (msg.method === 'initialize') result = { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'icebox-ship', version: '1' }, instructions: 'fake ship' };
    else if (msg.method === 'tools/list') result = { tools: game.tools };
    else if (msg.method === 'tools/call') {
      game.calls.push(msg.params);
      const r = game.toolResult(msg.params.name, msg.params.arguments);
      result = { content: [{ type: 'text', text: JSON.stringify(r) }], structuredContent: r, isError: !r.ok };
    } else {
      ws.send(JSON.stringify({ jsonrpc: '2.0', id: msg.id, error: { code: -32601, message: 'nope' } }));
      return;
    }
    ws.send(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result }));
  });
  await new Promise((r, j) => { ws.on('open', r); ws.on('error', j); });
  return game;
}

/** A relay on an ephemeral port, pointed at `openai` (a fakeOpenAI). */
export async function startRelay(openai, env = {}) {
  const config = loadConfig({
    OPENAI_API_KEY: 'sk-test',
    OPENAI_REALTIME_URL: `ws://127.0.0.1:${openai?.port ?? 1}/v1/realtime`,
    TWILIO_PHONE_NUMBER: '+15550109001',
    ...env,
  });
  const relay = createRelay({ config, log: quiet });
  const port = await relay.listen(0, '127.0.0.1');
  return { relay, port, config };
}

export async function post(port, path, body, headers = {}) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, { method: 'POST', body, headers });
  return { status: res.status, text: await res.text(), headers: res.headers };
}

/** Place a "phone call": the voice webhook, then a media stream with its token. */
export async function twilioCall(port) {
  const voice = await post(port, '/twilio/voice', new URLSearchParams({ From: '+15551234567', CallSid: 'CA1' }).toString(),
    { 'Content-Type': 'application/x-www-form-urlencoded', Host: `127.0.0.1:${port}` });
  const token = /name="token" value="([^"]+)"/.exec(voice.text)?.[1];
  const ws = new WebSocket(`ws://127.0.0.1:${port}/twilio/media`);
  const tw = { ws, received: [], voice, token,
    of(event) { return tw.received.filter((m) => m.event === event); },
    send(m) { ws.send(JSON.stringify(m)); } };
  ws.on('message', (d) => tw.received.push(JSON.parse(d.toString())));
  await new Promise((r, j) => { ws.on('open', r); ws.on('error', j); });
  tw.send({ event: 'connected', protocol: 'Call', version: '1.0.0' });
  tw.send({ event: 'start', sequenceNumber: '1', streamSid: 'MZ1', start: { streamSid: 'MZ1', callSid: 'CA1', tracks: ['inbound'], customParameters: { token }, mediaFormat: { encoding: 'audio/x-mulaw', sampleRate: 8000, channels: 1 } } });
  return tw;
}
