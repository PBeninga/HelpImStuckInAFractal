// One Twilio Media Stream (bidirectional, G.711 mu-law at 8 kHz) joined to a
// VoiceCall's OpenAI Realtime session. The Realtime API speaks mu-law too, so
// payloads pass through untouched.
//
//   Twilio -> us   connected, start {streamSid, callSid, customParameters},
//                  media {timestamp, payload}, mark {name}, stop
//   us -> Twilio   media {payload}, mark {name}, clear
//
// Barge-in: every audio chunk sent to Twilio is followed by a mark; Twilio
// echoes a mark once the caller has heard everything before it. So the marks
// that came back say exactly how much of the agent's current item was played,
// and when the caller talks over it we truncate the item there and tell Twilio
// to drop what it has buffered.

export class MediaBridge {
  /**
   * @param {object} o
   * @param {import("ws").WebSocket} o.ws        the Twilio media socket
   * @param {(token: string) => object|null} o.acceptToken  a one-time token -> {from}, or null
   * @param {(info: {callSid, from}) => import("./voice_calls.mjs").VoiceCall|null} o.createCall
   */
  constructor({ ws, acceptToken, createCall, log = console }) {
    this.ws = ws;
    this.acceptToken = acceptToken;
    this.createCall = createCall;
    this.log = log;
    this.call = null;
    this.streamSid = null;
    this.markQueue = []; // [{name, itemId, ms}]
    this.playedMs = new Map(); // itemId -> ms the caller has heard
    this.markN = 0;
    ws.on("message", (data) => this.onMessage(data));
    ws.on("close", () => this.call?.end("the caller hung up"));
    ws.on("error", (err) => this.log.warn(`media socket: ${err.message}`));
  }

  onMessage(data) {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    switch (msg.event) {
      case "start":
        this.onStart(msg).catch((err) => {
          this.log.warn(`voice call failed to start: ${err.message}`);
          this.ws.close(1011, "could not start");
        });
        break;
      case "media":
        if (!this.call?.session) return; // still starting: a few ms of audio is lost
        if (!msg.media?.track || msg.media.track === "inbound") this.call.session.appendAudio(msg.media.payload);
        break;
      case "mark": {
        const i = this.markQueue.findIndex((m) => m.name === msg.mark?.name);
        if (i >= 0) {
          for (const m of this.markQueue.splice(0, i + 1)) {
            this.playedMs.set(m.itemId, (this.playedMs.get(m.itemId) ?? 0) + m.ms);
          }
        }
        break;
      }
      case "stop":
        this.call?.end("the call ended");
        this.ws.close();
        break;
    }
  }

  async onStart(msg) {
    const start = msg.start ?? {};
    this.streamSid = start.streamSid ?? msg.streamSid;
    const caller = this.acceptToken(start.customParameters?.token);
    if (!caller) {
      this.log.warn("media stream with a missing or stale token; closing");
      this.ws.close(1008, "bad token");
      return;
    }
    const call = this.createCall({ callSid: start.callSid, from: caller.from });
    if (!call) {
      this.ws.close(1013, "busy");
      return;
    }
    this.call = call;
    call.on("ended", () => {
      if (this.ws.readyState === 1) this.ws.close();
    });
    await call.start();
    call.session.on("audio", ({ delta, itemId }) => this.sendAudio(delta, itemId));
    call.session.on("speech_started", () => this.bargeIn());
  }

  sendAudio(delta, itemId) {
    if (!this.streamSid || this.ws.readyState !== 1) return;
    this.ws.send(JSON.stringify({ event: "media", streamSid: this.streamSid, media: { payload: delta } }));
    const name = `m${++this.markN}`;
    this.ws.send(JSON.stringify({ event: "mark", streamSid: this.streamSid, mark: { name } }));
    // mu-law at 8 kHz: 8 bytes per millisecond
    this.markQueue.push({ name, itemId, ms: Buffer.from(delta, "base64").length / 8 });
  }

  // The caller spoke over the agent: cut the agent's item where they stopped hearing it.
  bargeIn() {
    if (this.markQueue.length === 0) return;
    const itemId = this.markQueue[0].itemId;
    if (itemId) this.call.session.truncate(itemId, this.playedMs.get(itemId) ?? 0);
    this.ws.send(JSON.stringify({ event: "clear", streamSid: this.streamSid }));
    this.markQueue = [];
  }
}
