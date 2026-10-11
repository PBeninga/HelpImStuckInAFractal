#!/usr/bin/env node
// Start the Sub-Dimensional Support relay.
//
//   npm start          the phone line (Twilio) + ship link + /mcp
//   npm run chat       the same, plus a text chat with the agent in this terminal

import { loadDotEnv, loadConfig, formatPhoneNumber } from './config.js';
import { createRelay } from './server.js';
import { runChat } from './chat.js';

loadDotEnv();
const config = loadConfig();
const relay = createRelay({ config });
const port = await relay.listen();

const base = config.publicUrl || `http://localhost:${port}`;
console.log(`
  Sub-Dimensional Support relay on port ${port}
    ship link (game dials in)   ws://localhost:${port}/game${config.shipLinkToken ? '?token=...' : ''}
    Twilio voice webhook        ${base}/twilio/voice   (POST)
    MCP for other clients       ${base}/mcp
    status                      ${base}/
    support number              ${formatPhoneNumber(config.twilio.phoneNumber) || '(set TWILIO_PHONE_NUMBER)'}
    model                       ${config.openai.model}, voice ${config.openai.voice}`);
if (!config.openai.apiKey) console.log('\n  ! OPENAI_API_KEY is not set: calls will fail until it is.');
if (!config.publicUrl) console.log('  ! PUBLIC_URL is not set: Twilio needs a public https URL (e.g. ngrok http ' + port + ').');
console.log('');

const shutdown = async () => {
  await relay.close();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

if (process.argv.includes('--chat')) {
  await runChat({ relay, config });
  await shutdown();
}
