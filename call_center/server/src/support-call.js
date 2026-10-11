// One support call: an OpenAI Realtime session wired to the ship. Tool calls
// go to the game's MCP server, transcripts go to the game's HUD, and ship
// events the game flags for the agent are dropped into the conversation as
// system messages. The Twilio bridge adds audio on top; chat mode adds stdin.

import { EventEmitter } from 'node:events';
import { RealtimeSession } from './realtime-session.js';
import { buildInstructions, shipEventMessage, LINK_DOWN_NOTE, LINK_UP_NOTE } from './persona.js';

export class SupportCall extends EventEmitter {
  constructor({ config, gameLink, mode = 'audio', log = console, WebSocketImpl }) {
    super();
    this.config = config;
    this.gameLink = gameLink;
    this.mode = mode;
    this.log = log;
    this.WebSocketImpl = WebSocketImpl;
    this.session = null;
    this.ended = false;
    this._onGameEvent = (ev) => this.handleGameEvent(ev);
    this._onLinkUp = () => this.handleLinkUp();
    this._onLinkDown = () => this.handleLinkDown();
    this._onToolsChanged = () => {
      if (!this.ended) this.session.updateTools(this.gameLink.toolsForRealtime());
    };
  }

  start() {
    const opts = {
      config: this.config.openai,
      instructions: buildInstructions({ agentName: this.config.agentName, mode: this.mode === 'audio' ? 'voice' : 'text' }),
      tools: this.gameLink.toolsForRealtime(),
      mode: this.mode,
      onToolCall: (name, args) => this.runTool(name, args),
      log: this.log,
    };
    if (this.WebSocketImpl) opts.WebSocketImpl = this.WebSocketImpl;
    this.session = new RealtimeSession(opts);
    this.session.on('open', () => {
      if (!this.gameLink.connected) this.session.injectSystem(LINK_DOWN_NOTE, { respond: false });
      this.session.requestResponse();   // the greeting
    });
    this.session.on('transcript', (t) => {
      this.gameLink.notify('ship/transcript', { role: t.role, item_id: t.itemId ?? '', text: t.text, final: t.final });
      this.emit('transcript', t);
    });
    this.session.on('close', () => this.end('the AI session closed'));
    this.session.on('api_error', (e) => this.emit('api_error', e));
    this.gameLink.on('event', this._onGameEvent);
    this.gameLink.on('ready', this._onLinkUp);
    this.gameLink.on('disconnected', this._onLinkDown);
    this.gameLink.on('tools_changed', this._onToolsChanged);
    this.gameLink.notify('ship/call', { state: 'connected', agent_name: this.config.agentName }, { sticky: true });
    this.session.connect();
    this.log.info?.(`[call] ${this.mode} call started with ${this.config.agentName}`);
    return this;
  }

  async runTool(name, args) {
    this.log.info?.(`[call] tool ${name} ${JSON.stringify(args)}`);
    const out = await this.gameLink.callTool(name, args);
    this.emit('tool_result', { name, args, output: out });
    return out;
  }

  handleGameEvent(ev) {
    if (!ev || !ev.notify_agent || this.ended) return;
    this.session.injectSystem(shipEventMessage(ev));
  }

  handleLinkUp() {
    if (this.ended) return;
    this.session.updateTools(this.gameLink.toolsForRealtime());
    this.session.injectSystem(LINK_UP_NOTE);
  }

  handleLinkDown() {
    if (this.ended) return;
    this.session.injectSystem(LINK_DOWN_NOTE, { respond: false });
  }

  end(reason = 'hung up') {
    if (this.ended) return;
    this.ended = true;
    this.gameLink.off('event', this._onGameEvent);
    this.gameLink.off('ready', this._onLinkUp);
    this.gameLink.off('disconnected', this._onLinkDown);
    this.gameLink.off('tools_changed', this._onToolsChanged);
    this.session?.close();
    this.gameLink.notify('ship/call', { state: 'ended' }, { sticky: true });
    this.log.info?.(`[call] ended: ${reason}`);
    this.emit('ended', reason);
  }
}
