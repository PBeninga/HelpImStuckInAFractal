// Settings from the environment (Railway service variables in production,
// server/.env or the shell locally). See .env.example.

export function loadConfig(env = process.env) {
  const list = (s) =>
    (s || "")
      .split(",")
      .map((x) => x.trim())
      .filter(Boolean);
  return {
    port: Number(env.PORT || 3000),
    // The public https origin Twilio reaches us at, e.g. https://fractal.up.railway.app.
    // Twilio signs requests over the exact URL it called, so validation needs it;
    // on Railway it defaults to the service's public domain.
    publicBaseUrl: (env.PUBLIC_BASE_URL ||
      (env.RAILWAY_PUBLIC_DOMAIN ? `https://${env.RAILWAY_PUBLIC_DOMAIN}` : "")).replace(/\/$/, ""),
    twilioAuthToken: env.TWILIO_AUTH_TOKEN || "",
    // Off only for local experiments: every Twilio request is otherwise signed.
    validateTwilio: env.TWILIO_VALIDATE !== "false",
    // E.164 numbers allowed to call in. Empty = nobody (calls are refused).
    allowedCallers: list(env.ALLOWED_CALLERS),
    // Shared secret for the game link (and the /api/game debug endpoint).
    gameLinkToken: env.GAME_LINK_TOKEN || "",
    // ConversationRelay voice settings (see the TwiML <ConversationRelay> docs).
    welcomeGreeting: env.WELCOME_GREETING || "You're connected to the fractal. Where shall we fly?",
    ttsProvider: env.TTS_PROVIDER || "",
    voice: env.TTS_VOICE || "",
    language: env.LANGUAGE || "en-US",
    // Unfinalised transcripts (needs Deepgram's flux model): shown live in the
    // game's chat input as you speak.
    partialPrompts: env.PARTIAL_PROMPTS === "true",
    // Who answers: "openai" (the call centre's voice agent: Twilio streams the
    // audio to OpenAI Realtime, which flies the ship with the call centre's
    // tools) or "relay" (ConversationRelay into the pilot chat, for an agent
    // such as Claude on the pilot loop). Defaults to openai when its key is set.
    voiceAgent: (env.VOICE_AGENT || (env.OPENAI_API_KEY ? "openai" : "relay")).toLowerCase(),
    openai: {
      apiKey: env.OPENAI_API_KEY || "",
      url: env.OPENAI_REALTIME_URL || "wss://api.openai.com/v1/realtime",
      model: env.OPENAI_REALTIME_MODEL || "gpt-realtime-2.1",
      voice: env.OPENAI_VOICE || "cedar",
      transcribeModel: env.OPENAI_TRANSCRIBE_MODEL || "gpt-4o-mini-transcribe",
      reasoningEffort: env.OPENAI_REASONING_EFFORT ?? "low",
    },
    // The support agent's name, and the number shown on the game's HUD.
    agentName: env.AGENT_NAME || "Gary",
    supportNumber: env.SUPPORT_NUMBER || env.TWILIO_PHONE_NUMBER || "",
  };
}

// "+15550109001" -> "+1 (555) 010-9001"; anything else is returned as is.
export function formatPhoneNumber(n) {
  const m = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(n || "");
  return m ? `+1 (${m[1]}) ${m[2]}-${m[3]}` : n || "";
}

// Problems that make the server unusable for real calls; logged at boot.
export function configProblems(config) {
  const out = [];
  if (!config.publicBaseUrl) out.push("PUBLIC_BASE_URL is not set (and no RAILWAY_PUBLIC_DOMAIN)");
  if (config.validateTwilio && !config.twilioAuthToken) out.push("TWILIO_AUTH_TOKEN is not set");
  if (!config.gameLinkToken) out.push("GAME_LINK_TOKEN is not set: the game cannot link");
  if (config.allowedCallers.length === 0) out.push("ALLOWED_CALLERS is empty: every call is refused");
  if (config.voiceAgent === "openai" && !config.openai.apiKey) out.push("VOICE_AGENT=openai but OPENAI_API_KEY is not set");
  if (!["openai", "relay"].includes(config.voiceAgent)) out.push(`VOICE_AGENT must be openai or relay, not '${config.voiceAgent}'`);
  return out;
}
