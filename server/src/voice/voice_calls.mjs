// Phone calls answered by the OpenAI Realtime voice agent (VOICE_AGENT=openai):
// Twilio streams the call's audio here (MediaBridge), the agent hears and
// speaks it, and flies the ship by calling the call centre's ship tools in the
// game, through the link (game.call("ship_tool", ...)). The game's ship events
// come back the same way and are dropped into the call; the conversation is
// mirrored into the game's pilot chat (the caller's words as voice messages,
// the agent's as "phone" messages), and what the pilot types there is passed
// to the agent.

import crypto from "node:crypto";
import { EventEmitter } from "node:events";
import { RealtimeSession } from "./realtime.mjs";
import { MediaBridge } from "./media.mjs";
import { buildInstructions, shipEventMessage, LINK_DOWN_NOTE, LINK_UP_NOTE } from "./persona.mjs";
import { mask } from "../calls.mjs";

const TOKEN_TTL_MS = 60_000;
const TOOL_TIMEOUT_MS = 15_000;

export class VoiceCalls {
  #tokens = new Map(); // one-time media-stream tokens -> {from, expires}

  constructor(game, config, { log = console, WebSocketImpl } = {}) {
    this.game = game;
    this.config = config;
    this.log = log;
    this.WebSocketImpl = WebSocketImpl;
    this.current = null;
  }

  get busy() {
    return this.current !== null;
  }

  get active() {
    return this.current ? [{ callSid: this.current.callSid, from: mask(this.current.from), voice: "openai" }] : [];
  }

  // For the <Stream> of a call the webhook accepted.
  issueToken(from) {
    const now = Date.now();
    for (const [t, v] of this.#tokens) if (v.expires < now) this.#tokens.delete(t);
    const token = crypto.randomUUID();
    this.#tokens.set(token, { from, expires: now + TOKEN_TTL_MS });
    return token;
  }

  #acceptToken(token) {
    const v = token ? this.#tokens.get(token) : null;
    if (!v) return null;
    this.#tokens.delete(token);
    return v.expires >= Date.now() ? v : null;
  }

  // A media socket Twilio opened (its signature already checked).
  attach(ws) {
    return new MediaBridge({
      ws,
      log: this.log,
      acceptToken: (t) => this.#acceptToken(t),
      createCall: (info) => this.newCall(info),
    });
  }

  // One call at a time: there is one ship.
  newCall({ callSid = `local-${Date.now()}`, from = "", mode = "audio", transport = "phone" } = {}) {
    if (this.current) return null;
    const call = new VoiceCall({ game: this.game, config: this.config, log: this.log, callSid, from, mode, transport, WebSocketImpl: this.WebSocketImpl });
    this.current = call;
    call.on("ended", () => {
      if (this.current === call) this.current = null;
    });
    return call;
  }
}

export class VoiceCall extends EventEmitter {
  constructor({ game, config, log, callSid, from, mode, transport = "phone", WebSocketImpl }) {
    super();
    this.game = game;
    this.config = config;
    this.log = log;
    this.callSid = callSid;
    this.from = from;
    this.mode = mode;
    this.transport = transport;
    this.WebSocketImpl = WebSocketImpl;
    this.session = null;
    this.ended = false;
    this.toolNames = [];
    this.handlers = {
      ship_event: (ev) => this.#onShipEvent(ev),
      chat: (text) => this.session?.sendUserText(`(typed in the pilot chat) ${text}`),
      connected: () => this.#onLinkUp(),
      disconnected: () => this.session?.injectSystem(LINK_DOWN_NOTE, { respond: false }),
    };
  }

  // The ship's tools as Realtime function tools, from the game (none when unlinked).
  async shipTools() {
    try {
      const { tools = [] } = await this.game.call("ship_tools", {}, 5000);
      const available = tools.filter((t) => t.name !== "resolve_issue");
      this.toolNames = available.map((t) => t.name);
      return available.map((t) => ({ type: "function", name: t.name, description: t.description ?? "", parameters: t.inputSchema ?? { type: "object", properties: {} } }));
    } catch {
      return [];
    }
  }

  async start() {
    const tools = await this.shipTools();
    if (this.ended) return this;
    let shapeRun = null;
    if (tools.length > 0) {
      try {
        const status = await this.game.call("ship_tool", { name: "get_ship_status", arguments: {} }, 5000);
        shapeRun = status.shape_run ?? null;
      } catch { /* Reconnect/status tools can recover a missing briefing. */ }
    }
    if (this.ended) return this;
    const opts = {
      config: this.config.openai,
      instructions: buildInstructions({ agentName: this.config.agentName, mode: this.mode === "audio" ? "voice" : "text", transport: this.transport, shapeRun }),
      tools,
      mode: this.mode,
      onToolCall: (name, args) => this.runTool(name, args),
      log: this.log,
    };
    if (this.WebSocketImpl) opts.WebSocketImpl = this.WebSocketImpl;
    this.session = new RealtimeSession(opts);
    this.session.on("open", () => {
      if (this.ended) return;
      this.emit("ready");
      if (tools.length === 0) this.session.injectSystem(LINK_DOWN_NOTE, { respond: false });
      this.session.requestResponse(); // the greeting
    });
    this.session.on("transcript", (t) => this.#onTranscript(t));
    this.session.on("close", (code, reason) => this.end(`the AI session closed (${code ?? "unknown"}): ${reason || "no reason provided"}`));
    this.session.on("error", (err) => this.end(`the AI connection failed: ${err.message}`));
    this.session.on("api_error", (e) => this.emit("api_error", e));
    for (const [event, fn] of Object.entries(this.handlers)) this.game.on(event, fn);
    this.game.notify({ type: "call_started", callSid: this.callSid, from: mask(this.from), agent_name: this.config.agentName, voice: "openai", transport: this.transport });
    this.session.connect();
    this.log.info(`voice call ${this.callSid} started with ${this.config.agentName}`);
    return this;
  }

  async runTool(name, args) {
    if (this.ended) return JSON.stringify({ ok: false, message: "The voice session has ended." });
    this.log.info(`voice call: ${name} ${JSON.stringify(args)}`);
    let out;
    try {
      out = await this.game.call("ship_tool", { name, arguments: args }, TOOL_TIMEOUT_MS);
    } catch (err) {
      out = { ok: false, message: this.game.connected ? `Ship systems error: ${err.message}` : "The ship link is down: the game is not running or not linked." };
    }
    this.emit("tool_result", { name, args, output: out });
    return JSON.stringify(out);
  }

  #onTranscript(t) {
    if (this.ended || !t.text) return;
    if (t.role === "agent") {
      if (t.final) this.game.notify({ type: "agent_said", callSid: this.callSid, transport: this.transport, text: t.text });
    } else {
      this.game.notify({ type: "utterance", callSid: this.callSid, text: t.text, final: t.final });
    }
    this.emit("transcript", t);
  }

  async #onShipEvent(ev) {
    if (this.ended || !ev || ev.kind === "pilot_input_required") return;
    if (ev.kind === "tools_changed") {
      this.session.updateTools(await this.shipTools());
    } else if (ev.notify_agent) {
      this.session.injectSystem(shipEventMessage(ev));
    }
  }

  async #onLinkUp() {
    if (this.ended) return;
    this.session.updateTools(await this.shipTools());
    this.session.injectSystem(LINK_UP_NOTE);
  }

  end(reason = "hung up") {
    if (this.ended) return;
    this.ended = true;
    for (const [event, fn] of Object.entries(this.handlers)) this.game.off(event, fn);
    this.session?.close();
    this.game.notify({ type: "call_ended", callSid: this.callSid, transport: this.transport, reason });
    this.log.info(`voice call ${this.callSid} ended: ${reason}`);
    this.emit("ended", reason);
  }
}
