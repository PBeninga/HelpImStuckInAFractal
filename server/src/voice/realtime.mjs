// One conversation with the OpenAI Realtime API (GA interface) over a
// WebSocket. Audio mode speaks G.711 mu-law both ways, so Twilio's media can be
// forwarded untouched; text mode is for trying the agent from a terminal.
//
// Function calls: the arguments arrive during a response; the tool runs at
// once, and when that response is done its outputs go back as
// function_call_output items followed by one response.create. Only one
// response may be active, so every response.create goes through
// requestResponse(), which waits for the current one to finish.

import { EventEmitter } from 'node:events';
import WebSocket from 'ws';
import { openaiKeyProblem } from '../config.mjs';

export class RealtimeSession extends EventEmitter {
  /**
   * @param {object} o
   * @param {object} o.config    config.openai (apiKey, url, model, voice, transcribeModel, reasoningEffort)
   * @param {string} o.instructions
   * @param {Array}  o.tools      Realtime function tools
   * @param {'audio'|'text'} [o.mode]
   * @param {(name: string, args: object) => Promise<string>} o.onToolCall
   */
  constructor({ config, instructions, tools = [], mode = 'audio', onToolCall, log = console, WebSocketImpl = WebSocket }) {
    super();
    this.config = config;
    this.instructions = instructions;
    this.tools = tools;
    this.mode = mode;
    this.onToolCall = onToolCall;
    this.log = log;
    this.WebSocketImpl = WebSocketImpl;
    this.ws = null;
    this.responseActive = false;
    this._wantResponse = false;
    this._toolRuns = [];
    this._transcripts = new Map();
    this._closed = false;
    // Optional session fields the API rejected; sessionConfig() leaves them out.
    this._dropped = new Set();
  }

  connect() {
    const keyProblem = openaiKeyProblem(this.config.apiKey);
    if (keyProblem) throw new Error(keyProblem);
    const url = `${this.config.url}?model=${encodeURIComponent(this.config.model)}`;
    this.ws = new this.WebSocketImpl(url, { headers: { Authorization: `Bearer ${this.config.apiKey}` } });
    this.ws.on('open', () => {
      this.send({ type: 'session.update', session: this.sessionConfig() });
      this.emit('open');
    });
    this.ws.on('message', (data) => this._onEvent(data));
    this.ws.on('close', (code, reason) => {
      this._closed = true;
      this.emit('close', code, reason?.toString());
    });
    this.ws.on('error', (err) => {
      this.log.error?.(`[openai] socket error: ${err.message}`);
      this.emit('error', err);
    });
    return this;
  }

  sessionConfig() {
    const session = {
      type: 'realtime',
      model: this.config.model,
      instructions: this.instructions,
      output_modalities: [this.mode === 'audio' ? 'audio' : 'text'],
      tools: this.tools,
      tool_choice: 'auto',
    };
    if (this.mode === 'audio') {
      const input = {
        format: { type: 'audio/pcmu' },
        turn_detection: { type: 'server_vad', threshold: 0.5, prefix_padding_ms: 300, silence_duration_ms: 500, create_response: true, interrupt_response: true },
      };
      if (!this._dropped.has('transcription')) input.transcription = { model: this.config.transcribeModel };
      if (!this._dropped.has('noise_reduction')) input.noise_reduction = { type: 'near_field' };
      session.audio = { input, output: { format: { type: 'audio/pcmu' }, voice: this.config.voice } };
    }
    if (this.config.reasoningEffort && /^gpt-realtime-2/.test(this.config.model) && !this._dropped.has('reasoning')) {
      session.reasoning = { effort: this.config.reasoningEffort };
    }
    return session;
  }

  /**
   * If the API rejected an optional session field (an older model without
   * reasoning, an unknown transcription model), resend the session without
   * it rather than run with no instructions or tools. Returns true if it did.
   */
  _retryWithout(param = '') {
    const optional = ['reasoning', 'transcription', 'noise_reduction'].find((k) => param.includes(k));
    if (!optional || this._dropped.has(optional)) return false;
    this._dropped.add(optional);
    this.log.warn?.(`[openai] session rejected ${param}; retrying without ${optional}`);
    this.send({ type: 'session.update', session: this.sessionConfig() });
    return true;
  }

  send(event) {
    if (this.ws && this.ws.readyState === 1) {
      this.ws.send(JSON.stringify(event));
      return true;
    }
    return false;
  }

  close() {
    this._closed = true;
    try { this.ws?.close(); } catch { /* already closed */ }
  }

  /** Ask for a response now, or as soon as the active one is done. */
  requestResponse() {
    if (this.responseActive || this._toolRuns.length > 0) {
      this._wantResponse = true;
      return;
    }
    this._wantResponse = false;
    this.responseActive = true;
    this.send({ type: 'response.create' });
  }

  appendAudio(base64) {
    this.send({ type: 'input_audio_buffer.append', audio: base64 });
  }

  /** The caller typed something (text mode). */
  sendUserText(text) {
    this.send({ type: 'conversation.item.create', item: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] } });
    this.requestResponse();
  }

  /** Tell the agent something mid-call (a ship event); optionally have it respond. */
  injectSystem(text, { respond = true } = {}) {
    this.send({ type: 'conversation.item.create', item: { type: 'message', role: 'system', content: [{ type: 'input_text', text }] } });
    if (respond) this.requestResponse();
  }

  updateTools(tools) {
    this.tools = tools;
    this.send({ type: 'session.update', session: { type: 'realtime', tools, tool_choice: 'auto' } });
  }

  truncate(itemId, audioEndMs) {
    this.send({ type: 'conversation.item.truncate', item_id: itemId, content_index: 0, audio_end_ms: Math.max(0, Math.round(audioEndMs)) });
  }

  _onEvent(data) {
    let ev;
    try {
      ev = JSON.parse(data.toString());
    } catch {
      return;
    }
    switch (ev.type) {
      case 'response.created':
        this.responseActive = true;
        break;
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        this.emit('audio', { delta: ev.delta, itemId: ev.item_id });
        break;
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
      case 'response.output_text.delta':
      case 'response.text.delta': {
        const text = (this._transcripts.get(ev.item_id) ?? '') + (ev.delta ?? '');
        this._transcripts.set(ev.item_id, text);
        this.emit('transcript', { role: 'agent', itemId: ev.item_id, text, final: false });
        break;
      }
      case 'response.output_audio_transcript.done':
      case 'response.audio_transcript.done':
      case 'response.output_text.done':
      case 'response.text.done': {
        const text = ev.transcript ?? ev.text ?? this._transcripts.get(ev.item_id) ?? '';
        this._transcripts.delete(ev.item_id);
        this.emit('transcript', { role: 'agent', itemId: ev.item_id, text, final: true });
        break;
      }
      case 'conversation.item.input_audio_transcription.delta': {
        const key = `in:${ev.item_id}`;
        const text = (this._transcripts.get(key) ?? '') + (ev.delta ?? '');
        this._transcripts.set(key, text);
        this.emit('transcript', { role: 'caller', itemId: ev.item_id, text: text.trim(), final: false });
        break;
      }
      case 'conversation.item.input_audio_transcription.completed':
        this._transcripts.delete(`in:${ev.item_id}`);
        this.emit('transcript', { role: 'caller', itemId: ev.item_id, text: (ev.transcript ?? '').trim(), final: true });
        break;
      case 'input_audio_buffer.speech_started':
        this.emit('speech_started', ev);
        break;
      case 'response.function_call_arguments.done':
        this._runTool(ev.call_id, ev.name, ev.arguments);
        break;
      case 'response.done':
        this._onResponseDone(ev.response ?? {});
        break;
      case 'error':
        this._onError(ev.error ?? {});
        break;
      default:
        break;
    }
    this.emit('event', ev);
  }

  _runTool(callId, name, rawArgs) {
    if (this._toolRuns.some((r) => r.callId === callId)) return;
    let args = {};
    try {
      args = rawArgs ? JSON.parse(rawArgs) : {};
    } catch {
      args = {};
    }
    this.emit('tool_call', { name, args });
    const output = Promise.resolve()
      .then(() => this.onToolCall(name, args))
      .catch((err) => JSON.stringify({ ok: false, message: `Tool failed: ${err.message}` }));
    this._toolRuns.push({ callId, output });
  }

  async _onResponseDone(response) {
    this.responseActive = false;
    // Function calls the arguments.done events missed (defensive).
    for (const item of response.output ?? []) {
      if (item.type === 'function_call') this._runTool(item.call_id, item.name, item.arguments);
    }
    if (this._toolRuns.length > 0) {
      const runs = this._toolRuns;
      const outputs = await Promise.all(runs.map((r) => r.output));
      this._toolRuns = [];
      runs.forEach((r, i) => {
        this.send({ type: 'conversation.item.create', item: { type: 'function_call_output', call_id: r.callId, output: String(outputs[i]) } });
      });
      this._wantResponse = false;
      if (!this._closed) this.requestResponse();
      return;
    }
    if (this._wantResponse) this.requestResponse();
  }

  _onError(error) {
    if (error.code === 'conversation_already_has_active_response') {
      this.responseActive = true;
      this._wantResponse = true;
      return;
    }
    if (error.code === 'response_cancel_not_active') return;
    if (String(error.param ?? '').startsWith('session.') && this._retryWithout(String(error.param))) return;
    this.log.error?.(`[openai] ${error.type ?? 'error'}: ${error.message ?? JSON.stringify(error)}`);
    this.emit('api_error', error);
  }
}
