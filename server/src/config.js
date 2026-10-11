// Settings for the support-line relay, from the environment (and server/.env).

const DEFAULTS = {
  PORT: '8787',
  OPENAI_REALTIME_URL: 'wss://api.openai.com/v1/realtime',
  OPENAI_REALTIME_MODEL: 'gpt-realtime-2.1',
  OPENAI_VOICE: 'cedar',
  OPENAI_TRANSCRIBE_MODEL: 'gpt-4o-mini-transcribe',
  OPENAI_REASONING_EFFORT: 'low',
  AGENT_NAME: 'Gary',
};

/** Load server/.env into process.env if it exists (Node >= 20.12). */
export function loadDotEnv(path = new URL('../.env', import.meta.url)) {
  try {
    process.loadEnvFile(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * Build the config object from an env map. Nothing is required to start: a
 * missing OpenAI key only fails when a call comes in, so the game link and the
 * /mcp endpoint can be tried without any accounts.
 */
export function loadConfig(env = process.env) {
  const get = (k) => (env[k] ?? DEFAULTS[k] ?? '').toString().trim();
  const publicUrl = get('PUBLIC_URL').replace(/\/+$/, '');
  return {
    port: Number(get('PORT')) || 8787,
    host: get('HOST') || '0.0.0.0',
    publicUrl,
    openai: {
      apiKey: get('OPENAI_API_KEY'),
      url: get('OPENAI_REALTIME_URL'),
      model: get('OPENAI_REALTIME_MODEL'),
      voice: get('OPENAI_VOICE'),
      transcribeModel: get('OPENAI_TRANSCRIBE_MODEL'),
      reasoningEffort: get('OPENAI_REASONING_EFFORT'),
    },
    twilio: {
      accountSid: get('TWILIO_ACCOUNT_SID'),
      authToken: get('TWILIO_AUTH_TOKEN'),
      phoneNumber: get('TWILIO_PHONE_NUMBER'),
      // Signatures are checked when we know both the token and the exact public
      // URL Twilio calls; behind a tunnel the Host header alone is not reliable.
      validateSignatures: Boolean(get('TWILIO_AUTH_TOKEN') && publicUrl) && get('TWILIO_VALIDATE') !== 'false',
    },
    shipLinkToken: get('SHIP_LINK_TOKEN'),
    agentName: get('AGENT_NAME'),
  };
}

/** "+15550109001" -> "+1 (555) 010-9001"; anything else is returned as is. */
export function formatPhoneNumber(n) {
  const m = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(n || '');
  return m ? `+1 (${m[1]}) ${m[2]}-${m[3]}` : n || '';
}
