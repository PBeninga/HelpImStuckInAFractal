// A client for the game's McpBridge socket (src/mcp/mcp_bridge.gd):
// newline-delimited JSON, {id, cmd, args} -> {id, ok, result | error}.
// Reconnects on the next call after the game restarts.

import net from "node:net";

export class BridgeClient {
  #socket = null;
  #buffer = "";
  #nextId = 1;
  #pending = new Map();

  constructor({ host = "127.0.0.1", port = 9077 } = {}) {
    this.host = host;
    this.port = port;
  }

  get connected() {
    return this.#socket !== null;
  }

  #connect() {
    return new Promise((resolve, reject) => {
      const s = net.createConnection({ host: this.host, port: this.port });
      s.setEncoding("utf8");
      s.once("connect", () => {
        this.#socket = s;
        this.#buffer = "";
        resolve();
      });
      s.once("error", (err) => {
        if (this.#socket !== s) reject(err);
      });
      s.on("data", (chunk) => this.#onData(chunk));
      s.on("close", () => {
        if (this.#socket === s) this.#socket = null;
        for (const [id, p] of this.#pending) {
          clearTimeout(p.timer);
          p.reject(new Error("the game closed the connection"));
          this.#pending.delete(id);
        }
      });
    });
  }

  #onData(chunk) {
    this.#buffer += chunk;
    let nl;
    while ((nl = this.#buffer.indexOf("\n")) !== -1) {
      const line = this.#buffer.slice(0, nl);
      this.#buffer = this.#buffer.slice(nl + 1);
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      const p = this.#pending.get(msg.id);
      if (!p) continue;
      this.#pending.delete(msg.id);
      clearTimeout(p.timer);
      if (msg.ok) p.resolve(msg.result);
      else p.reject(new Error(msg.error));
    }
  }

  async call(cmd, args = {}, timeoutMs = 30_000) {
    if (!this.#socket) {
      try {
        await this.#connect();
      } catch {
        throw new Error(`the game is not running (nothing on ${this.host}:${this.port})`);
      }
    }
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new Error(`'${cmd}' timed out`));
      }, timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.#socket.write(JSON.stringify({ id, cmd, args }) + "\n");
    });
  }

  close() {
    this.#socket?.destroy();
    this.#socket = null;
  }
}
