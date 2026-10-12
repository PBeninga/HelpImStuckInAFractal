// Test doubles for the voice agent: a fake OpenAI Realtime server, and a fake
// game bridge that speaks McpBridge's line protocol with the pilot chat and
// the call centre's commands (ship_tools, ship_tool, ship_events, call_center).

import net from "node:net";
import { once } from "node:events";
import { WebSocketServer } from "ws";

export const quiet = { info() {}, warn() {}, error() {} };

export async function until(fn, ms = 3000, what = "condition") {
  const end = Date.now() + ms;
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

// Stands in for wss://api.openai.com/v1/realtime and records client events.
export async function fakeOpenAI() {
  const wss = new WebSocketServer({ port: 0, host: "127.0.0.1" });
  await once(wss, "listening");
  const fake = {
    port: wss.address().port,
    events: [],
    sockets: [],
    headers: null,
    url: null,
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
  wss.on("connection", (ws, req) => {
    fake.sockets.push(ws);
    fake.headers = req.headers;
    fake.url = req.url;
    ws.on("message", (d) => fake.events.push(JSON.parse(d.toString())));
  });
  return fake;
}

export const SHIP_TOOLS = [
  { name: "get_ship_status", description: "status", inputSchema: { type: "object", properties: {} } },
  { name: "fly_to_feature", description: "fly", inputSchema: { type: "object", properties: { feature_id: { type: "string" } }, required: ["feature_id"] } },
];

// A game bridge with a pilot chat and a call centre.
export async function fakeCallCenterBridge() {
  const chat = []; // {id, role, text, source}
  const events = []; // {id, kind, summary, notify_agent, ...}
  const calls = []; // every request
  const state = { tools: [...SHIP_TOOLS], callCenter: {}, drafts: [] };
  let nextChat = 1;
  let nextEvent = 1;
  const addChat = (role, text, source = "") => {
    const m = { id: nextChat++, role, text, source };
    chat.push(m);
    return m;
  };
  const pushEvent = (ev) => {
    const e = { id: nextEvent++, ...ev };
    events.push(e);
    return e;
  };
  const longPoll = async (list, after, timeout) => {
    const deadline = Date.now() + (timeout ?? 20) * 1000;
    while (!list.some((m) => m.id > after) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 20));
    return list.filter((m) => m.id > after);
  };
  // Each request is served on its own, as McpBridge does: a long-poll never
  // holds up the requests behind it.
  async function serve(sock, req) {
    calls.push(req);
    const reply = (result) => sock.write(JSON.stringify({ id: req.id, ok: true, result }) + "\n");
    const fail = (error) => sock.write(JSON.stringify({ id: req.id, ok: false, error }) + "\n");
    const a = req.args || {};
    switch (req.cmd) {
      case "status":
        return reply({ in_game: true });
      case "chat_post":
        state.drafts.push("");
        return reply(addChat(a.role || "human", a.text, a.source ?? "voice"));
      case "chat_say":
        return reply(addChat("agent", a.text, a.source ?? ""));
      case "chat_draft":
        state.drafts.push(a.text);
        return reply({});
      case "chat_watch": {
        const last = () => (chat.length ? chat[chat.length - 1].id : 0);
        if (a.after === undefined) return reply({ messages: [], last_id: last() });
        const fresh = await longPoll(chat, a.after, a.timeout);
        return reply({ messages: fresh, last_id: Math.max(last(), a.after) });
      }
      case "ship_tools":
        return reply({ tools: state.tools });
      case "ship_tool":
        if (!state.tools.some((t) => t.name === a.name)) return fail(`unknown ship tool '${a.name}'`);
        return reply({ ok: true, message: `did ${a.name}`, arguments: a.arguments, ...(a.name === "get_ship_status" ? { shape_run: { run_id: "test-run", active_shape: 0, next_command: "inversion -0.5", stages: [{ shape_index: 0, next_level_distance: 20, next_level_threshold: 20, commands: ["inversion -0.5"] }] } } : {}) });
      case "ship_events": {
        const last = () => (events.length ? events[events.length - 1].id : 0);
        if (a.after === undefined) return reply({ events: [], last_id: last() });
        const fresh = await longPoll(events, a.after, a.timeout);
        return reply({ events: fresh, last_id: Math.max(last(), a.after) });
      }
      case "call_center":
        Object.assign(state.callCenter, a);
        return reply({ ...state.callCenter });
      default:
        return fail(`unknown command '${req.cmd}'`);
    }
  }
  const server = net.createServer((sock) => {
    let buf = "";
    sock.setEncoding("utf8");
    sock.on("data", (chunk) => {
      buf += chunk;
      let nl;
      while ((nl = buf.indexOf("\n")) !== -1) {
        const req = JSON.parse(buf.slice(0, nl));
        buf = buf.slice(nl + 1);
        serve(sock, req);
      }
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return {
    server,
    port: server.address().port,
    chat,
    events,
    calls,
    state,
    addChat,
    pushEvent,
    requests: (cmd) => calls.filter((c) => c.cmd === cmd),
  };
}
