// The phone link: runs on the machine with the game and joins it to the phone
// server on Railway. The game sits behind NAT, so the link dials out:
//
//   phone server  <--wss /game/link-->  this link  <--tcp 127.0.0.1:9077-->  game (McpBridge)
//
// What a caller says lands in the game's pilot chat (chat_post / chat_draft),
// whatever the agent says there is spoken back on the call, and the server can
// run any bridge command through it (rpc). With the call centre in the game
// (call_center/), the link also tells it about the line and the call (the
// call_center command), forwards its ship events to the server, and passes
// what the pilot types in the chat to the server's voice agent.
//
//   FRACTAL_SERVER_URL  the server's public URL (https:// or wss://), e.g. https://fractal.up.railway.app
//   GAME_LINK_TOKEN     the same secret as the server's
//   FRACTAL_MCP_PORT    the game's bridge port (default 9077)
//
//   npm run link        (reads server/.env when present)

import { pathToFileURL } from "node:url";
import { WebSocket } from "ws";
import { BridgeClient } from "./bridge_client.mjs";

export function startLink({
  serverUrl = process.env.FRACTAL_SERVER_URL,
  token = process.env.GAME_LINK_TOKEN,
  bridgePort = Number(process.env.FRACTAL_MCP_PORT || 9077),
  log = console,
} = {}) {
  if (!serverUrl || !token) throw new Error("set FRACTAL_SERVER_URL and GAME_LINK_TOKEN");
  const url = serverUrl.replace(/\/$/, "").replace(/^http/, "ws") + "/game/link";
  const bridge = new BridgeClient({ port: bridgePort });
  let ws = null;
  let stopped = false;
  let backoff = 1000;

  const send = (msg) => ws?.readyState === WebSocket.OPEN && ws.send(JSON.stringify(msg));

  function connect() {
    if (stopped) return;
    const sock = new WebSocket(url, { headers: { Authorization: `Bearer ${token}` } });
    ws = sock;
    sock.on("open", async () => {
      backoff = 1000;
      log.info(`linked to ${url}`);
      callCenter({ link_up: true });
      let game = null;
      try {
        game = await bridge.call("status");
      } catch {}
      send({ type: "hello", game });
    });
    sock.on("message", (data) => {
      let msg;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      if (msg.type === "event") onEvent(msg.event).catch((err) => log.warn(`event: ${err.message}`));
      else if (msg.type === "rpc") onRpc(msg);
    });
    sock.on("unexpected-response", (_req, res) => log.warn(`server refused the link: HTTP ${res.statusCode}`));
    sock.on("error", (err) => log.warn(`link: ${err.message}`));
    sock.on("close", (code) => {
      if (ws === sock) ws = null;
      callCenter({ link_up: false });
      if (stopped) return;
      if (code === 4000) log.warn("another link replaced this one");
      setTimeout(connect, backoff);
      backoff = Math.min(backoff * 2, 30_000);
    });
  }

  // Tell the call centre (if the game runs one) about the line and the call.
  function callCenter(args) {
    return bridge.call("call_center", args).catch(() => {});
  }

  async function onEvent(e) {
    switch (e.type) {
      case "config":
        await callCenter({ support_number: e.support_number || "", link_up: true });
        break;
      case "call_ringing":
        await callCenter({ call_state: "ringing" });
        break;
      case "call_started":
        await callCenter({ call_state: "connected", agent_name: e.agent_name || "" });
        await post({ role: "system", text: `Phone call connected (${e.from})` });
        break;
      case "agent_said":
        // the voice agent said it on the call; "phone" keeps it from being spoken again
        await bridge.call("chat_say", { text: e.text, source: "phone" });
        break;
      case "utterance":
        if (e.final) await post({ text: e.text, source: "voice" });
        else await bridge.call("chat_draft", { text: e.text }).catch(() => {});
        break;
      case "call_ended":
        await callCenter({ call_state: "ended" });
        await bridge.call("chat_draft", { text: "" }).catch(() => {});
        await post({ role: "system", text: "Phone call ended" });
        break;
    }
  }

  // Into the pilot chat; if the game is down, tell the caller.
  async function post(args) {
    try {
      await bridge.call("chat_post", args);
    } catch (err) {
      if (args.source === "voice") send({ type: "say", text: "The game on your computer isn't running." });
      throw err;
    }
  }

  async function onRpc({ id, cmd, args }) {
    try {
      send({ type: "rpc_result", id, ok: true, result: await bridge.call(cmd, args || {}) });
    } catch (err) {
      send({ type: "rpc_result", id, ok: false, error: err.message });
    }
  }

  // Follow the pilot chat: send each agent reply to the server to be spoken
  // (not the phone agent's own lines, which it already said), and what the
  // pilot types, for a voice agent on a call.
  async function watchChat() {
    let after = null;
    while (!stopped) {
      try {
        if (after === null) after = (await bridge.call("chat_watch", {})).last_id;
        const r = await bridge.call("chat_watch", { after, timeout: 20 }, 35_000);
        after = r.last_id;
        for (const m of r.messages) {
          if (m.role === "agent" && m.source !== "phone") send({ type: "say", text: m.text });
          else if (m.role === "human" && m.source === "typed") send({ type: "chat", text: m.text });
        }
      } catch {
        after = null; // the game restarted: its ids start over
        await new Promise((res) => setTimeout(res, 2000));
      }
    }
  }

  // Follow the call centre's ship events (waypoints, questions for the pilot,
  // the escape) and send them to the server for the voice agent.
  async function watchShipEvents() {
    let after = null;
    while (!stopped) {
      try {
        if (after === null) after = (await bridge.call("ship_events", {})).last_id;
        const r = await bridge.call("ship_events", { after, timeout: 20 }, 35_000);
        after = r.last_id;
        for (const event of r.events) send({ type: "ship_event", event });
      } catch {
        after = null; // the game restarted, or runs without its call centre
        await new Promise((res) => setTimeout(res, 3000));
      }
    }
  }

  connect();
  watchChat();
  watchShipEvents();

  return {
    bridge,
    get linked() {
      return ws?.readyState === WebSocket.OPEN;
    },
    stop() {
      stopped = true;
      ws?.close();
      bridge.close();
    },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    startLink();
  } catch (err) {
    console.error(`link: ${err.message}`);
    process.exit(1);
  }
}
