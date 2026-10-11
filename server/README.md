# Phone server

Call a phone number and pilot the fractal by voice. Twilio answers the call and
turns speech into text (and text back into speech) with
[ConversationRelay](https://www.twilio.com/docs/voice/conversationrelay); this
server, deployed on Railway, carries that text to the game on your machine and
back.

```
 phone ──► Twilio ──wss /twilio/relay──► server (Railway) ◄──wss /game/link── link ──tcp :9077──► game
          speech⇄text                    src/                                   link/            McpBridge
```

The game is behind NAT, so it never takes connections from the internet: the
**link** (`link/link.mjs`, run on your machine next to the game) dials out to
the server and holds the socket open.

- What the caller says lands in the game's **pilot chat** as a voice message
  (`chat_post`); an unfinished transcript shows in the chat's input box
  (`chat_draft`, with `PARTIAL_PROMPTS=true`).
- Whatever the agent says in the pilot chat (`say` over MCP) is spoken back on
  the call. The agent itself is unchanged: it runs the `pilot` loop
  (`wait_for_message` → act → `say`) whether the words were typed or spoken.
- The server can run any McpBridge command on the game through the link
  (`game.call(cmd, args)` in `src/game_link.mjs`, or `POST /api/game/:cmd`),
  for anything that later drives the game straight from the server.

| route | |
|---|---|
| `GET /health` | liveness, whether a game is linked, live call count (Railway healthcheck) |
| `POST /twilio/voice` | the number's incoming-call webhook: refuses callers not in `ALLOWED_CALLERS`, says so when no game is linked, else `<Connect><ConversationRelay>` |
| `POST /twilio/session-end` | `<Connect action>`: logs how the relay session ended |
| `WS /twilio/relay` | ConversationRelay, one socket per call |
| `WS /game/link` | the link (Bearer `GAME_LINK_TOKEN`) |
| `GET /api/status`, `POST /api/game/:cmd` | debug: link and calls; run a bridge command (Bearer `GAME_LINK_TOKEN`) |

Every Twilio request and the relay handshake must carry a valid
`X-Twilio-Signature` (checked against `PUBLIC_BASE_URL` + the path); the
relay's `setup` message re-checks the caller.

## Set up

**1. Deploy to Railway.** Create a service from this repository with its
**Root Directory** set to `/server`; `railway.json` gives the build (Railpack,
Node), the start command and the `/health` healthcheck. Generate a public domain
(Settings → Networking). Set the variables from `.env.example`:
`TWILIO_AUTH_TOKEN`, `ALLOWED_CALLERS`, `GAME_LINK_TOKEN` (`openssl rand -hex 32`),
and `PUBLIC_BASE_URL` only for a custom domain.

**2. Set up Twilio.** Accept the *Predictive and Generative AI/ML Features
Addendum* (Voice → Settings), which ConversationRelay needs. Buy or pick a voice
number and set its *A call comes in* webhook to
`POST https://<your domain>/twilio/voice`.

**3. Link the game.** On the machine running the game:

```bash
cd server && npm install
cp .env.example .env      # FRACTAL_SERVER_URL + the same GAME_LINK_TOKEN
npm run link
```

Start the game (`tools/launch.sh -- --play`, or the MCP `launch_game`) and an
agent on the `pilot` loop, then call the number.

## Develop

```bash
npm test          # fake Twilio + the real link + a fake game bridge, all local
npm run dev       # the server, reading .env
```

To take real calls against a local server, expose it with a tunnel (e.g.
`cloudflared tunnel --url http://localhost:3000`), set `PUBLIC_BASE_URL` to the
tunnel's https URL, and point the number's webhook there.
