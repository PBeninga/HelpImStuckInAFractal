// Live phone calls, one ConversationRelay WebSocket each. Twilio does the
// speech-to-text and text-to-speech; we only see text:
//
//   Twilio -> us   setup {callSid, from, ...}, prompt {voicePrompt, last},
//                  interrupt, dtmf {digit}, error {description}
//   us -> Twilio   text {token, last}, end {handoffData}
//
// What the caller says goes to the game (the pilot chat); what the agent says
// in the pilot chat comes back here and is spoken on every live call.

export class Calls {
  #sessions = new Set(); // {ws, callSid, from}

  constructor(game, { allowedCallers = [], log = console } = {}) {
    this.game = game;
    this.allowedCallers = allowedCallers;
    this.log = log;
    game.on("say", (text) => this.speak(text));
    game.on("disconnected", () => {
      if (this.#sessions.size > 0) this.speak("I've lost the connection to the game. Call back once it's running.", { end: true });
    });
  }

  get active() {
    return [...this.#sessions].filter((s) => s.callSid).map(({ callSid, from }) => ({ callSid, from }));
  }

  // A ConversationRelay socket Twilio opened (its signature already checked).
  attach(ws) {
    const session = { ws, callSid: null, from: null };
    this.#sessions.add(session);
    ws.on("message", (data) => {
      let msg;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      this.#onMessage(session, msg);
    });
    ws.on("close", () => {
      this.#sessions.delete(session);
      if (session.callSid) this.game.notify({ type: "call_ended", callSid: session.callSid });
    });
  }

  #onMessage(session, msg) {
    switch (msg.type) {
      case "setup":
        // The voice webhook already refused unknown callers; check again here,
        // since the socket URL is public.
        if (!this.allowedCallers.includes(msg.from)) {
          this.log.warn(`relay: refusing call from ${mask(msg.from)}`);
          this.#send(session, { type: "end" });
          session.ws.close();
          return;
        }
        session.callSid = msg.callSid;
        session.from = msg.from;
        this.log.info(`call ${msg.callSid} connected from ${mask(msg.from)}`);
        if (!this.game.notify({ type: "call_started", callSid: msg.callSid, from: mask(msg.from) })) {
          this.#say(session, "The game isn't linked right now. Start it on your computer and call back.", true);
        }
        break;
      case "prompt":
        if (!session.callSid || typeof msg.voicePrompt !== "string") return;
        this.game.notify({
          type: "utterance",
          callSid: session.callSid,
          text: msg.voicePrompt,
          final: msg.last !== false,
        });
        break;
      case "dtmf":
        if (session.callSid) this.game.notify({ type: "dtmf", callSid: session.callSid, digit: msg.digit });
        break;
      case "interrupt":
        if (session.callSid) this.game.notify({ type: "interrupt", callSid: session.callSid });
        break;
      case "error":
        this.log.warn(`relay error on ${session.callSid}: ${msg.description}`);
        break;
    }
  }

  // Speak on every live call.
  speak(text, { end = false } = {}) {
    for (const s of this.#sessions) if (s.callSid) this.#say(s, text, end);
  }

  #say(session, text, end) {
    this.#send(session, { type: "text", token: text, last: true });
    if (end) this.#send(session, { type: "end" });
  }

  #send(session, msg) {
    if (session.ws.readyState === 1) session.ws.send(JSON.stringify(msg));
  }
}

// "+15551234567" -> "…4567": enough to tell callers apart in the game's chat.
export function mask(number) {
  const digits = String(number || "").replace(/\D/g, "");
  return digits ? `…${digits.slice(-4)}` : "unknown";
}
