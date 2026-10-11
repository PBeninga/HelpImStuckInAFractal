# Sub-Dimensional Support: the phone line

Part of the call centre (`call_center/`, see [its README](../README.md)). This
is the relay that lets a stranded pilot **phone for help**. A Twilio number
answers the call. The call's audio goes to an OpenAI Realtime voice agent, a
tongue-in-cheek Tier 2 support agent. The agent flies the ship through the
game's own **MCP server**.

```
 phone ──► Twilio ──(Media Stream, μ-law 8 kHz)──► relay ──► OpenAI Realtime (voice agent)
                                                    │  ▲          │ tool calls
                                                    ▼  │          ▼
      call centre in the game ◄──── ship link: MCP JSON-RPC over WebSocket ────
      ship tools: scan, highlight, turn, thrust, fly_to_feature, resolve_issue … (+ the game's own)
      HUD: transcript, call state, highlights; ship events ──► the agent
```

- **The game is the MCP server.** The call centre's `mcp/ship_link.gd` dials
  out to the relay's `/game` WebSocket and answers `initialize`, `tools/list`
  and `tools/call` (implemented by `mcp/ship_tools.gd`). Because the game dials
  out, it needs no open port, and a web build can reach a `wss://` relay. When
  the game registers a tool, it sends `notifications/tools/list_changed`; the
  relay re-reads the list and updates the live call.
- **The relay is the MCP client.** It forwards the ship's tools to the
  Realtime session as function tools, and runs each function call on the game.
- **Other MCP clients can fly the ship too.** `POST /mcp` re-exposes the same
  tools over MCP's Streamable HTTP transport. For example:
  `claude mcp add --transport http icebox http://localhost:8787/mcp`.
- **The HUD follows the call.** The relay pushes `ship/call` (ringing,
  connected, ended) and `ship/transcript` notifications to the game. The game
  sends back `ship/event` notifications: a waypoint reached, a diagnostics
  issue that needs the pilot, the escape. The agent hears them as
  `SHIP EVENT` system messages.

## Try it without any accounts

```bash
cd call_center/server
npm install
npm run demo        # a scripted support call that really flies the ship
```

Then, from the repo root, run `call_center/run.sh --demo`. It starts the game
straight in the cockpit, on the call centre's sample escape route. The demo
waits for the crash report to finish, then rings, "talks" through the HUD, and
flies whatever route the game exposes through the MCP tools. It answers the
diagnostics questions and the exit-blocking waiver on the way, and ends at the
exit. Use `npm run demo -- --fast` for shorter pauses.

`npm test` runs the relay's tests. They use fakes for OpenAI, Twilio and the
game.

## The real phone line

1. **Keys.** `cp .env.example .env` and fill in `OPENAI_API_KEY`,
   `TWILIO_PHONE_NUMBER`, `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN`.
2. **A public URL for Twilio.** For example, `ngrok http 8787`. Put the https
   URL in `.env` as `PUBLIC_URL` (no trailing slash).
3. **Start the relay.** Run `npm start`. It prints its endpoints.
4. **Point the number at it.** Either run `npm run configure-twilio`, or set
   it by hand. In the Twilio console, go to *Phone Numbers* → your number →
   *A call comes in*, choose **Webhook**, enter `PUBLIC_URL/twilio/voice`, and
   choose **HTTP POST**.
5. **Start the game with the call centre**: `call_center/run.sh` from the
   repo root (or `--demo` for the sample route). The HUD's support panel shows
   the number once the ship link is up. Call it.

**Talk without a phone.** `npm run chat` starts the relay and a text
conversation with the same agent, tools and ship. It only needs
`OPENAI_API_KEY`.

### Settings (`.env`)

| variable | default | |
|---|---|---|
| `OPENAI_API_KEY` | | required for calls and chat |
| `OPENAI_REALTIME_MODEL` | `gpt-realtime-2.1` | any Realtime speech-to-speech model |
| `OPENAI_VOICE` | `cedar` | `marin`, `cedar`, `alloy`, `ash`, `ballad`, `coral`, `echo`, `sage`, `shimmer`, `verse` |
| `OPENAI_REASONING_EFFORT` | `low` | sent only for `gpt-realtime-2*` models |
| `OPENAI_TRANSCRIBE_MODEL` | `gpt-4o-mini-transcribe` | the caller's words on the HUD |
| `TWILIO_PHONE_NUMBER` | | shown on the HUD; used by `configure-twilio` |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` | | signature checks and `configure-twilio` |
| `PUBLIC_URL` | | the https URL Twilio uses; signatures are checked when it and the auth token are set |
| `PORT` | `8787` | |
| `SHIP_LINK_TOKEN` | | optional secret for `/game` and `/mcp` |
| `AGENT_NAME` | `Gary` | |

### Pointing the game at a relay elsewhere

The game dials `ws://127.0.0.1:8787/game` unless you tell it otherwise:

- desktop: `call_center/run.sh -- --ship-server=wss://example.ngrok.app/game --ship-token=…`
  (or set `SHIP_SERVER_URL` and `SHIP_LINK_TOKEN`)
- web build: `index.html?ship_server=wss://example.ngrok.app/game&ship_token=…`

### Security notes

- **The media WebSocket.** Each incoming-call webhook issues a one-time token,
  passed as a `<Parameter>` of the `<Stream>`. A media stream that does not
  present a fresh token is closed. So nobody can open `/twilio/media` and run
  up your OpenAI bill.
- **Webhook signatures.** `X-Twilio-Signature` is checked when both
  `TWILIO_AUTH_TOKEN` and `PUBLIC_URL` are set.
- **The game link and `/mcp`.** These are open unless `SHIP_LINK_TOKEN` is
  set. Set it whenever the relay is reachable from the internet.
- **One call at a time** (there is one ship). Other callers hear a busy
  message.

## Files

| file | |
|---|---|
| `src/server.js` | HTTP + WebSocket routes, one-time stream tokens, one call at a time |
| `src/twilio.js` | TwiML, signatures, the media bridge with mark-accurate barge-in |
| `src/realtime-session.js` | the OpenAI Realtime (GA) session: config, audio, tool calls, one response at a time |
| `src/support-call.js` | one call: session ⇄ ship tools, transcripts to the HUD, ship events to the agent |
| `src/game-link.js` | MCP client over the game's WebSocket |
| `src/mcp-http.js` | `POST /mcp` (Streamable HTTP, stateless) |
| `src/persona.js` | the agent's instructions |
| `src/chat.js` | `npm run chat` |
| `scripts/demo-call.js` | `npm run demo` |
| `scripts/configure-twilio.js` | `npm run configure-twilio` |
