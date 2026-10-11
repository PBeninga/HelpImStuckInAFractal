#!/usr/bin/env node
// Point your Twilio number's incoming-call webhook at this relay:
//   VoiceUrl = PUBLIC_URL/twilio/voice (POST)
// Needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER and
// PUBLIC_URL (in server/.env or the environment).

import { loadDotEnv, loadConfig } from '../src/config.js';

loadDotEnv();
const config = loadConfig();
const { accountSid, authToken, phoneNumber } = config.twilio;
const missing = [
  ['TWILIO_ACCOUNT_SID', accountSid], ['TWILIO_AUTH_TOKEN', authToken],
  ['TWILIO_PHONE_NUMBER', phoneNumber], ['PUBLIC_URL', config.publicUrl],
].filter(([, v]) => !v).map(([k]) => k);
if (missing.length) {
  console.error(`Missing: ${missing.join(', ')}`);
  process.exit(1);
}

const api = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}`;
const headers = { Authorization: 'Basic ' + Buffer.from(`${accountSid}:${authToken}`).toString('base64') };

const list = await fetch(`${api}/IncomingPhoneNumbers.json?PhoneNumber=${encodeURIComponent(phoneNumber)}`, { headers });
if (!list.ok) {
  console.error(`Twilio lookup failed: ${list.status} ${await list.text()}`);
  process.exit(1);
}
const number = (await list.json()).incoming_phone_numbers?.[0];
if (!number) {
  console.error(`No number ${phoneNumber} on this account.`);
  process.exit(1);
}
const voiceUrl = `${config.publicUrl}/twilio/voice`;
const upd = await fetch(`${api}/IncomingPhoneNumbers/${number.sid}.json`, {
  method: 'POST',
  headers: { ...headers, 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ VoiceUrl: voiceUrl, VoiceMethod: 'POST' }),
});
if (!upd.ok) {
  console.error(`Twilio update failed: ${upd.status} ${await upd.text()}`);
  process.exit(1);
}
console.log(`${phoneNumber} now calls ${voiceUrl}`);
