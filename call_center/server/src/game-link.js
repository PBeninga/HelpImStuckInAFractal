// The relay's end of the ship link. The game (call_center/mcp/ship_link.gd) dials in
// on /game and serves MCP JSON-RPC over the socket; this is the MCP client.
// It also pushes the HUD's notifications (ship/config, ship/call,
// ship/transcript), turns the game's ship/event notifications into events, and
// re-reads the tool list when the game announces notifications/tools/list_changed.

import { EventEmitter } from 'node:events';

const PROTOCOL_VERSION = '2025-06-18';
const REQUEST_TIMEOUT_MS = 8000;

export class GameLink extends EventEmitter {
  constructor({ log = console } = {}) {
    super();
    this.log = log;
    this.ws = null;
    this.tools = [];
    this.serverInfo = null;
    this.instructions = '';
    this.ready = false;
    this._nextId = 1;
    this._pending = new Map();
    // Re-sent to every newly connected game so its HUD is current.
    this._sticky = new Map();
  }

  get connected() {
    return Boolean(this.ws && this.ws.readyState === 1 && this.ready);
  }

  /** Take over a new game socket (a newer connection replaces an older one). */
  attach(ws) {
    if (this.ws && this.ws !== ws) {
      const old = this.ws;
      this._detach(old, 'replaced by a newer game connection');
      try { old.close(4000, 'replaced'); } catch { /* already gone */ }
    }
    this.ws = ws;
    this.ready = false;
    ws.on('message', (data) => this._onMessage(ws, data));
    ws.on('close', () => this._detach(ws, 'game disconnected'));
    ws.on('error', (err) => this.log.warn?.(`[game] socket error: ${err.message}`));
    this._handshake(ws).catch((err) => {
      this.log.warn?.(`[game] MCP handshake failed: ${err.message}`);
    });
  }

  async _handshake(ws) {
    const init = await this.request('initialize', {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: { name: 'sub-dimensional-support-relay', version: '1.0.0' },
    });
    if (ws !== this.ws) return;
    this.serverInfo = init.serverInfo ?? null;
    this.instructions = init.instructions ?? '';
    this.notify('notifications/initialized', {}, { force: true });
    const listed = await this.request('tools/list', {});
    if (ws !== this.ws) return;
    this.tools = Array.isArray(listed.tools) ? listed.tools : [];
    this.ready = true;
    for (const [method, params] of this._sticky) this.notify(method, params);
    this.log.info?.(`[game] ship link up: ${this.serverInfo?.name ?? 'ship'} with ${this.tools.length} tools`);
    this.emit('ready', this.tools);
  }

  _detach(ws, reason) {
    if (ws !== this.ws) return;
    this.ws = null;
    const wasReady = this.ready;
    this.ready = false;
    for (const { reject, timer } of this._pending.values()) {
      clearTimeout(timer);
      reject(new Error(reason));
    }
    this._pending.clear();
    if (wasReady) {
      this.log.info?.(`[game] ship link down: ${reason}`);
      this.emit('disconnected', reason);
    }
  }

  _onMessage(ws, data) {
    if (ws !== this.ws) return;
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      this.log.warn?.('[game] dropped a non-JSON message');
      return;
    }
    if (msg.id !== undefined && msg.id !== null && !msg.method) {
      const key = String(msg.id);
      const p = this._pending.get(key);
      if (!p) return;
      this._pending.delete(key);
      clearTimeout(p.timer);
      if (msg.error) p.reject(Object.assign(new Error(msg.error.message ?? 'MCP error'), { code: msg.error.code }));
      else p.resolve(msg.result ?? {});
      return;
    }
    if (msg.method === 'ship/event') {
      this.emit('event', msg.params ?? {});
    } else if (msg.method === 'notifications/tools/list_changed') {
      this.refreshTools().catch((err) => this.log.warn?.(`[game] could not refresh tools: ${err.message}`));
    }
  }

  /** Re-read the ship's tool list (the game registered or removed a tool). */
  async refreshTools() {
    const listed = await this.request('tools/list', {});
    this.tools = Array.isArray(listed.tools) ? listed.tools : [];
    this.log.info?.(`[game] tool list changed: ${this.tools.length} tools`);
    this.emit('tools_changed', this.tools);
  }

  /** Send a JSON-RPC request to the game; resolves with its result. */
  request(method, params = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
    const ws = this.ws;
    if (!ws || ws.readyState !== 1) return Promise.reject(new Error('the game is not connected'));
    const id = this._nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this._pending.delete(String(id));
        reject(new Error(`the game did not answer ${method} in time`));
      }, timeoutMs);
      this._pending.set(String(id), { resolve, reject, timer });
      ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }

  /**
   * Send a notification. With `sticky`, it is remembered and re-sent when a
   * game (re)connects (the support number, the call state).
   */
  notify(method, params = {}, { sticky = false, force = false } = {}) {
    if (sticky) this._sticky.set(method, params);
    if (!this.ws || this.ws.readyState !== 1 || (!this.ready && !force)) return false;
    this.ws.send(JSON.stringify({ jsonrpc: '2.0', method, params }));
    return true;
  }

  /** Call one of the ship's tools; resolves with the text to give the model. */
  async callTool(name, args = {}) {
    if (!this.connected) {
      return JSON.stringify({ ok: false, message: 'The ship link is down: the game is not running or not connected to the support relay. Ask the pilot to start the game.' });
    }
    try {
      const result = await this.request('tools/call', { name, arguments: args });
      const text = (result.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('\n');
      return text || JSON.stringify(result.structuredContent ?? { ok: !result.isError });
    } catch (err) {
      return JSON.stringify({ ok: false, message: `Ship systems error: ${err.message}` });
    }
  }

  /** The ship's tools as OpenAI Realtime function tools. */
  toolsForRealtime() {
    return this.tools.map((t) => ({
      type: 'function',
      name: t.name,
      description: t.description ?? '',
      parameters: t.inputSchema ?? { type: 'object', properties: {} },
    }));
  }
}
