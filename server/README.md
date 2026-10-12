# Phone server

Call a phone number and get flown out of the fractal by voice. Twilio answers;
this server, deployed on Railway, joins the call to the game on your machine.
Who answers is `VOICE_AGENT`:

- **`openai`** (the default when `OPENAI_API_KEY` is set). The call
  centre's **voice agent**, "Gary from Sub-Dimensional Support", answers.
  Twilio streams the call's audio (`<Connect><Stream>`, G.711 μ-law) to
  `/twilio/media`. The server joins that audio to an **OpenAI Realtime**
  session, which listens and speaks directly. The agent flies the ship with
  the **call centre's ship tools** (`call_center/` in the game: scan,
  highlight, autopilot, console settings …), called through the link.
- **`relay`**. Twilio's
  [ConversationRelay](https://www.twilio.com/docs/voice/conversationrelay)
  turns speech into text and back. The text goes to the game's pilot chat,
  for an agent such as Claude on the `pilot` loop (`mcp/`).

```
 phone ──► Twilio ──wss /twilio/media (audio)──► server (Railway) ──► OpenAI Realtime   (VOICE_AGENT=openai)
                 └─wss /twilio/relay (text)───►    src/  ◄──wss /game/link── link ──tcp :9077──► game: McpBridge
                                                                              link/                  + call_center/
```

The game is behind NAT, so it never takes connections from the internet: it
dials out to the server itself when it starts (**ServerLink**,
`src/mcp/server_link.gd`, inside McpBridge) and holds the socket open,
reconnecting if it drops. It finds the server in `FRACTAL_SERVER_URL` and
`GAME_LINK_TOKEN`, from the environment or `server/.env`; `-- --no-link` (or
`FRACTAL_LINK=0`) keeps it offline. `link/link.mjs` (`npm run link`) does the
same job as a separate process next to the game; if both run, it takes over.

- What the caller says lands in the game's **pilot chat** as a voice message
  (`chat_post`); an unfinished transcript shows in the chat's input box
  (`chat_draft`, with `PARTIAL_PROMPTS=true`).
- Whatever the agent says in the pilot chat (`say` over MCP) is spoken back on
  the call. The agent itself is unchanged: it runs the `pilot` loop
  (`wait_for_message` → act → `say`) whether the words were typed or spoken.
- The server can run any McpBridge command on the game through the link
  (`game.call(cmd, args)` in `src/game_link.mjs`, or `POST /api/game/:cmd`),
  for anything that later drives the game straight from the server.

**With the OpenAI voice agent** (`src/voice/`):

- **Tools.** The agent's tools are the call centre's ship tools
  (`ship_tools`), and each call runs on the game (`ship_tool`). A tool the
  game registers mid-call reaches the live session.
- **Ship events.** The link long-polls the call centre's events
  (`ship_events`) and sends them to the server. The agent hears them as
  `SHIP EVENT` system messages and reacts: each instruction completing or being cancelled, and the escape. Depth scans are request-only and never pushed as events. Scripted pilot-question events are ignored.
  The agent can inspect and edit all console sections through
  `get_console_controls`, `set_console_controls`, and `console_action`.
- **The pilot chat.** The conversation is mirrored there: the caller's words
  as voice messages (live in the input box while they speak), the agent's as
  "Support (phone)" lines, never spoken twice. What the pilot **types** in
  the chat goes to the agent during a call.
- **The call centre's HUD.** It shows the support number and the call's state
  (the link's `call_center` command).
- **Barge-in.** When the caller talks over the agent, the agent's speech is
  cut exactly where the caller stopped hearing it (Twilio marks), and
  Twilio's buffer is cleared.
- **One call at a time.** There is one ship; other callers hear a polite
  busy message.

| route | |
|---|---|
| `GET /health` | liveness, whether a game is linked, live call count (Railway healthcheck) |
| `POST /twilio/voice` | the number's incoming-call webhook: refuses callers not in `ALLOWED_CALLERS`, says so when no game is linked, else `<Connect><Stream>` (openai; with a one-time token) or `<Connect><ConversationRelay>` (relay) |
| `POST /twilio/session-end` | `<Connect action>`: logs how the session ended |
| `WS /twilio/media` | the call's audio for the OpenAI voice agent |
| `WS /twilio/relay` | ConversationRelay, one socket per call |
| `WS /game/link` | the link (Bearer `GAME_LINK_TOKEN`) |
| `GET /api/status`, `POST /api/game/:cmd` | debug: link and calls; run a bridge command (Bearer `GAME_LINK_TOKEN`) |
| `POST /mcp` | the call centre's ship tools as an MCP server (Streamable HTTP; Bearer `GAME_LINK_TOKEN`), for any MCP client |

Every Twilio request and both Twilio socket handshakes must carry a valid
`X-Twilio-Signature` (checked against `PUBLIC_BASE_URL` + the path). The
relay's `setup` message re-checks the caller. A media stream must present the
one-time token its webhook issued.

## Set up

### Text test mode in the chatbox

Set `OPENAI_API_KEY` and `GAME_LINK_TOKEN` on the server. Link the game with
`FRACTAL_SERVER_URL` and the same `GAME_LINK_TOKEN`, using the game's built-in
ServerLink. Start a flight and click **Start text agent** in the pilot chat.
Type messages and read its replies there. **End text agent**, leaving the
cockpit, or losing the game link closes the session.

This uses the same support agent, model, ship tools and events as phone mode,
with Realtime configured for text output. There is no microphone capture or
spoken audio. You can test navigation, raycasts and screen tints from chat
without making a phone call or setting up Twilio. The API key stays on the
server. Model usage still applies; this is not a mock or offline mode.

Restart the server and game after updating. For a local server,
`FRACTAL_SERVER_URL=http://127.0.0.1:3000` works without a tunnel. The server's
missing Twilio configuration warnings can be ignored for text mode.
Use the built-in game link; the separate `npm run link` relay does not carry
these session controls. Phone and text sessions share a one-session limit.

### Phone calls

**1. Deploy to Railway.** Create a service from this repository with its
**Root Directory** set to `/server`; `railway.json` gives the build (Railpack,
Node), the start command and the `/health` healthcheck. Generate a public domain
(Settings → Networking). Set the variables from `.env.example`:
`TWILIO_AUTH_TOKEN`, `ALLOWED_CALLERS`, `GAME_LINK_TOKEN` (`openssl rand -hex 32`),
and `PUBLIC_BASE_URL` only for a custom domain. For the voice agent, also set
`OPENAI_API_KEY` (and optionally `TWILIO_PHONE_NUMBER`, which the HUD shows,
plus `OPENAI_REALTIME_MODEL`, `OPENAI_VOICE` and `AGENT_NAME`).

**2. Set up Twilio.** Buy or pick a voice number and set its *A call comes
in* webhook to `POST https://<your domain>/twilio/voice`. For
`VOICE_AGENT=relay`, also accept the *Predictive and Generative AI/ML Features
Addendum* (Voice → Settings), which ConversationRelay needs.

**3. Link the game.** The game dials the server itself. On the machine
running it, give it the server's URL and the same token:

```bash
cp server/.env.example server/.env   # FRACTAL_SERVER_URL + the same GAME_LINK_TOKEN
```

(or export both). Start the game **with its call centre**:
`call_center/run.sh` from the repo root, or `tools/launch.sh -- --play
--call-center`, or the MCP `launch_game {call_center: "on"}`. It prints
`ServerLink: linked to wss://…/game/link`, and the support panel shows the
number to call. Then call it. (With the OpenAI voice agent, a game started
without its call centre starts it when it links: its tools are how the agent
flies the ship.) With `VOICE_AGENT=relay`, also
start an agent on the `pilot` loop.

## Develop

```bash
npm test          # fake Twilio + fake OpenAI + the real link + a fake game bridge, all local
npm run dev       # the server, reading .env
npm run demo      # a whole call against the real game, no accounts (below)
```

**`npm run demo`** plays one complete support call against the real game.
Start the game with `call_center/run.sh --demo` first. The demo runs the real
server and the real link in-process, with two stand-ins:

- a fake Twilio caller: signed webhook, signed media stream, μ-law audio both
  ways;
- a scripted agent that speaks the OpenAI Realtime protocol in place of the
  model.

Every hop of a real call runs: Twilio's wire format → the server → Realtime
events → tool calls → the link → McpBridge → the call centre → the ship. Only
the agent's choices are scripted. It reads the ship's status, follows
whatever route the game exposes, answers the diagnostics questions as the
caller, and flies out of the exit. Use `-- --fast` for shorter pauses and
`DEMO_DEBUG=1` to see every event. With `-- --in-game-link` the game dials the
demo server itself, as it dials Railway: run `GAME_LINK_TOKEN=demo npm run
demo -- --in-game-link`, then start the game with
`FRACTAL_SERVER_URL=http://127.0.0.1:3077 GAME_LINK_TOKEN=demo`. It works for rehearsal, as an end-to-end
check, and as a fallback when the venue Wi-Fi gives up.

To take real calls against a local server, expose it with a tunnel (e.g.
`cloudflared tunnel --url http://localhost:3000`), set `PUBLIC_BASE_URL` to the
tunnel's https URL, and point the number's webhook there.
