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
  };
}

// Problems that make the server unusable for real calls; logged at boot.
export function configProblems(config) {
  const out = [];
  if (!config.publicBaseUrl) out.push("PUBLIC_BASE_URL is not set (and no RAILWAY_PUBLIC_DOMAIN)");
  if (config.validateTwilio && !config.twilioAuthToken) out.push("TWILIO_AUTH_TOKEN is not set");
  if (!config.gameLinkToken) out.push("GAME_LINK_TOKEN is not set: the game cannot link");
  if (config.allowedCallers.length === 0) out.push("ALLOWED_CALLERS is empty: every call is refused");
  return out;
}
