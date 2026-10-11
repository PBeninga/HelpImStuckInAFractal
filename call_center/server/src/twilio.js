// Twilio: the TwiML that connects an inbound call to our media WebSocket,
// webhook signature checks, and the bridge between a Media Stream and a
// SupportCall. Audio is G.711 mu-law at 8 kHz both ways, which the Realtime
// API speaks natively, so payloads pass through untouched.
//
// Barge-in: every audio chunk sent to Twilio is followed by a mark; Twilio
// echoes a mark once the caller has heard everything before it. So the marks
// that came back say exactly how much of the agent's current item was played,
// and when the caller starts talking over it we truncate the item there and
// tell Twilio to clear its buffer.

import crypto from 'node:crypto';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export function streamTwiml(streamUrl, parameters = {}) {
  const params = Object.entries(parameters)
    .map(([k, v]) => `<Parameter name="${esc(k)}" value="${esc(v)}"/>`).join('');
  return `<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="${esc(streamUrl)}">${params}</Stream></Connect></Response>`;
}

export function busyTwiml() {
  return '<?xml version="1.0" encoding="UTF-8"?><Response><Say voice="Polly.Amy">Thank you for calling Sub-Dimensional Support. All of our agents are currently assisting other pilots stranded in other fractals. Your call is important to us, at every scale. Please try again shortly.</Say><Hangup/></Response>';
}

/** Twilio's X-Twilio-Signature: base64 HMAC-SHA1 of the URL + sorted params. */
export function computeSignature(authToken, url, params = {}) {
  const data = Object.keys(params).sort().reduce((acc, k) => acc + k + params[k], url);
  return crypto.createHmac('sha1', authToken).update(Buffer.from(data, 'utf8')).digest('base64');
}

export function validSignature(authToken, url, params, signature) {
  if (!signature) return false;
  const expected = Buffer.from(computeSignature(authToken, url, params));
  const given = Buffer.from(String(signature));
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}

export class TwilioMediaBridge {
  /**
   * @param {object} o
   * @param {import('ws').WebSocket} o.ws        the Twilio media socket
   * @param {(token: string) => boolean} o.acceptToken  one-time token check
   * @param {() => import('./support-call.js').SupportCall|null} o.createCall
   */
  constructor({ ws, acceptToken, createCall, log = console }) {
    this.ws = ws;
    this.acceptToken = acceptToken;
    this.createCall = createCall;
    this.log = log;
    this.call = null;
    this.streamSid = null;
    this.latestMediaTimestamp = 0;
    this.markQueue = [];          // [{ name, itemId, ms }]
    this.playedMs = new Map();    // itemId -> ms the caller has heard
    this._markN = 0;
    ws.on('message', (data) => this.onTwilioMessage(data));
    ws.on('close', () => this.call?.end('the caller hung up'));
    ws.on('error', (err) => this.log.warn?.(`[twilio] socket error: ${err.message}`));
  }

  onTwilioMessage(data) {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    switch (msg.event) {
      case 'start':
        this.onStart(msg);
        break;
      case 'media':
        if (!this.call) return;
        this.latestMediaTimestamp = Number(msg.media?.timestamp ?? this.latestMediaTimestamp);
        if (!msg.media?.track || msg.media.track === 'inbound') this.call.session.appendAudio(msg.media.payload);
        break;
      case 'mark': {
        const i = this.markQueue.findIndex((m) => m.name === msg.mark?.name);
        if (i >= 0) {
          for (const m of this.markQueue.splice(0, i + 1)) {
            this.playedMs.set(m.itemId, (this.playedMs.get(m.itemId) ?? 0) + m.ms);
          }
        }
        break;
      }
      case 'stop':
        this.call?.end('the call ended');
        try { this.ws.close(); } catch { /* gone */ }
        break;
      default:
        break;
    }
  }

  onStart(msg) {
    const start = msg.start ?? {};
    this.streamSid = start.streamSid ?? msg.streamSid;
    const token = start.customParameters?.token;
    if (!this.acceptToken(token)) {
      this.log.warn?.('[twilio] media stream with a missing or stale token; closing');
      this.ws.close(1008, 'bad token');
      return;
    }
    const call = this.createCall();
    if (!call) {
      this.ws.close(1013, 'busy');
      return;
    }
    this.call = call;
    call.on('ended', () => {
      try { if (this.ws.readyState === 1) this.ws.close(); } catch { /* gone */ }
    });
    call.start();
    call.session.on('audio', ({ delta, itemId }) => this.sendAudio(delta, itemId));
    call.session.on('speech_started', () => this.bargeIn());
  }

  sendAudio(delta, itemId) {
    if (!this.streamSid || this.ws.readyState !== 1) return;
    this.ws.send(JSON.stringify({ event: 'media', streamSid: this.streamSid, media: { payload: delta } }));
    const name = `m${++this._markN}`;
    this.ws.send(JSON.stringify({ event: 'mark', streamSid: this.streamSid, mark: { name } }));
    // mu-law at 8 kHz: 8 bytes per millisecond
    this.markQueue.push({ name, itemId, ms: Buffer.from(delta, 'base64').length / 8 });
  }

  /** The caller spoke over the agent: cut the agent's item where they stopped hearing it. */
  bargeIn() {
    if (this.markQueue.length === 0) return;
    const itemId = this.markQueue[0].itemId;
    if (itemId) this.call.session.truncate(itemId, this.playedMs.get(itemId) ?? 0);
    this.ws.send(JSON.stringify({ event: 'clear', streamSid: this.streamSid }));
    this.markQueue = [];
  }
}
