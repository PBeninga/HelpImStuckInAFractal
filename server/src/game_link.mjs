// The one game linked to this server. The game runs on someone's machine
// behind NAT, so it dials out to us (link/link.mjs) over a WebSocket; this end
// keeps that socket and talks JSON over it:
//
//   server -> link   {type: "event", event: {...}}           call activity, fire and forget
//                    {type: "rpc", id, cmd, args}            any McpBridge command
//   link -> server   {type: "rpc_result", id, ok, result | error}
//                    {type: "say", text}                     the agent spoke in the pilot chat
//                    {type: "hello", game: {...}}            sent once on connect

import { EventEmitter } from "node:events";

const RPC_TIMEOUT_MS = 30_000;

export class GameLink extends EventEmitter {
  #ws = null;
  #nextId = 1;
  #pending = new Map();
  info = null;

  get connected() {
    return this.#ws !== null && this.#ws.readyState === 1;
  }

  // A new link replaces the old one (the game restarted, or a second machine
  // took over).
  attach(ws) {
    if (this.#ws) this.#ws.close(4000, "replaced by a newer link");
    this.#ws = ws;
    this.info = null;
    ws.on("message", (data) => this.#onMessage(ws, data));
    ws.on("close", () => {
      if (this.#ws !== ws) return;
      this.#ws = null;
      this.info = null;
      for (const [id, p] of this.#pending) {
        clearTimeout(p.timer);
        p.reject(new Error("the game link closed"));
        this.#pending.delete(id);
      }
      this.emit("disconnected");
    });
    this.emit("connected");
  }

  // Tell the game something happened (a call started, the caller spoke...).
  // Returns false when no game is linked.
  notify(event) {
    if (!this.connected) return false;
    this.#ws.send(JSON.stringify({ type: "event", event }));
    return true;
  }

  // Run one McpBridge command on the game and resolve with its result.
  call(cmd, args = {}, timeoutMs = RPC_TIMEOUT_MS) {
    if (!this.connected) return Promise.reject(new Error("no game is linked"));
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new Error(`'${cmd}' timed out`));
      }, timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.#ws.send(JSON.stringify({ type: "rpc", id, cmd, args }));
    });
  }

  #onMessage(ws, data) {
    if (ws !== this.#ws) return;
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    switch (msg.type) {
      case "hello":
        this.info = msg.game ?? {};
        this.emit("hello", this.info);
        break;
      case "say":
        if (typeof msg.text === "string" && msg.text.trim()) this.emit("say", msg.text.trim());
        break;
      case "rpc_result": {
        const p = this.#pending.get(msg.id);
        if (!p) return;
        this.#pending.delete(msg.id);
        clearTimeout(p.timer);
        if (msg.ok) p.resolve(msg.result);
        else p.reject(new Error(msg.error || "the game refused the command"));
        break;
      }
    }
  }
}
