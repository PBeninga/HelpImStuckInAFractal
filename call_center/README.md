# The call centre: Sub-Dimensional Support

The stranded pilot's help line, kept apart from the game. When a hyperspace
jump strands the ship inside the fractal, the pilot phones **Sub-Dimensional
Support**, a real phone number. A tongue-in-cheek AI support agent answers,
explains the disaster in breathless mathematical babble, and flies the ship to
the exit as the pilot talks. Meanwhile a **diagnostics log** scrolls past,
fixing problems on its own and now and then needing the pilot's answer, and
the HUD **highlights whatever the agent is talking about**.

This folder is the in-game half: the HUD, the diagnostics log, the ship's
tools and events. The phone half (Twilio, the OpenAI Realtime voice agent, the
link) is `server/`. They meet in `McpBridge` (`src/mcp/`), the game's command
socket.

```
 phone ─► Twilio ─(audio)─► server/ (Railway) ─► OpenAI Realtime voice agent
                                 ▲   │ tool calls, ship events, transcripts
                    wss /game/link   ▼
                         link (server/link, your machine)
                                 │ tcp :9077
                         McpBridge (src/mcp) ── pilot chat (src/chat): the conversation
                                 │ ship_tools · ship_tool · ship_events · call_center
                     ┌──────── call_center/ ────────────────────────────────┐
                     │ call_center.gd      the node at /root/CallCenter       │
                     │ mcp/ship_tools.gd   scan, highlight, turn, thrust,     │
                     │                     fly_to_feature, resolve_issue …    │
                     │ hud/                status · diagnostics · support ·   │
                     │                     brackets                           │
                     │ log/                crash report, issues, questions    │
                     │ features.gd         the game's points of interest      │
                     │ adapter/ ───────────► the game (Main), untouched        │
                     └────────────────────────────────────────────────────────┘
```

**How it stays apart from the game:**

- **No global class names.** Scripts use `preload`, so nothing here can clash
  with the game's classes.
- **One file knows the game.** `adapter/explorer_adapter.gd` uses Main's
  public `camera`, `params`, `view`, `fly` and `table()`.
  `tests/run_tests.sh` fails if any other file names a game class.
- **It starts only on request.** McpBridge starts it on `-- --call-center`
  (or `FRACTAL_CALL_CENTER=1`). It then finds the game scene by itself and
  stays out of the way on the title menu.

## Run it

```bash
call_center/run.sh                # the game as usual, with the call centre
call_center/run.sh --demo         # straight to the cockpit, on the sample escape route
```

From a Claude session, use `tools/launch.sh -- --play --call-center-demo`, or
the MCP `launch_game {call_center: "demo"}`.

**A whole call without any accounts.** With the game running (`--demo`),
run:

```bash
cd server && npm install && npm run demo
```

This plays a complete support call through the real server, link and bridge,
with a fake Twilio caller and a scripted voice agent in place of OpenAI's
model. It flies the ship from the crash report to the exit. See
[`server/README.md`](../server/README.md) for the real phone line: Railway,
Twilio, `OPENAI_API_KEY`, and `npm run link`.

## What the pilot sees

- **Down the left: ship status, then the SHIP DIAGNOSTICS log.** The log
  starts with the crash report: *Error: punch jump not completed successfully
  · Error #13432 Mandelbrought recurrence generator has animalifolds instead
  of manifolds · Resolved successfully, via forced evfoldlution · … · Error
  #33423 Stuck in fractal space · Unable to automatically resolve, connecting
  to agent…*
- **Self-resolving issues.** After that, a new problem arrives and fixes itself
  every few seconds. Now and then one **needs the pilot**, and the agent asks
  them on the call. Unanswered questions take a default answer after 25 s
  (120 s with an agent on the line).
- **The SUB-DIMENSIONAL SUPPORT panel** (bottom left). It shows the number to
  call, then who is on the line and for how long.
- **The pilot chat** (McpBridge's, down the right). It holds the conversation:
  the caller's words as voice messages, the agent's as "Support (phone)"
  lines. What the pilot types there goes to the agent, and while a call is
  up the panel shows an agent listening.
- **Highlights.** Brackets and labels mark each characteristic the agent names
  in the chat, by `#id` or by name, whoever the agent is (the phone agent, or
  Claude piloting). Off-screen ones get an arrow at the edge. The exit has its
  own marker and a glow ring.

## The McpBridge commands it adds

| command | |
|---|---|
| `ship_tools` | `{tools: [{name, description, inputSchema}]}`: the ship's tools (below) |
| `ship_tool {name, arguments}` | run one; returns `{ok, message, …}` |
| `ship_events {after, timeout}` | long-poll the agent's news `{events: [{id, kind, summary, notify_agent, …}], last_id}`: stages, waypoints, questions for the pilot, `tools_changed`, the escape |
| `call_center {support_number, call_state, agent_name, link_up}` | the phone side reports in (the link sends these) |

**For Claude.** `mcp/server.mjs` exposes the same tools as `ship_tools`,
`ship` and `ship_events`.

**The ship's tools:**

| tool | |
|---|---|
| `get_ship_status` | in flight?, clearance, heading, autopilot, next waypoint, exit (range, bearing, clear path, locked), open pilot issues, world facts |
| `scan_surroundings` | nearby characteristics, each with id, name, blurb, range, bearing, elevation, on screen?, clear path? |
| `highlight` / `clear_highlights` | bracket a characteristic, or flash a HUD panel |
| `turn_ship`, `face_feature`, `thrust` | small moves; a thrust stops short of the fractal |
| `fly_to_feature`, `full_stop` | the autopilot; it refuses blocked legs, suggests the next waypoint, and holds short of a locked exit |
| `resolve_issue` | answer a pilot question with the pilot's words |
| `post_to_log` | write an AGENT line to the diagnostics log |
| `set_visual_filter` | change the palette, when the adapter supports it |
| *game-registered tools* | added and removed at runtime (`tools_changed` updates a live call) |

Distances are in metres. The explorer's world unit is 1 km, so its tunnels
are 20–80 m wide.

## For the game: the contract

The game does not need to know the call centre exists. To make it richer, the
game talks to `/root/CallCenter` when it is present. All of it is optional:

```gdscript
var cc := get_node_or_null(^"/root/CallCenter")
if cc:
    # points of interest the agent can name, highlight and fly to
    cc.register_feature("2312", "The Recursive Cul-de-sac", Vector3(1.025, -0.775, 0), "route",
        "A dead end that loops back into itself at every scale except this one.")
    cc.set_route(["2312", "4096", "7071", "8128"])   # waypoints, in order
    cc.set_exit("9001")
    # or all at once: cc.load_features_json("res://…/route.json")  (format: demo/sample_route.json)

    cc.auto_begin = false          # the game has its own intro…
    cc.begin()                     # …and calls this when the ship lands: HUD in, crash report

    cc.lock_exit("egress waiver unsigned")      # the autopilot holds short and says why
    var id := cc.raise_pilot_issue("Egress waiver unsigned", "Ask the pilot for their full name.",
        "the pilot", "Waiver signed by '%s'.", true)
    cc.pilot_issue_resolved.connect(func(issue_id, answer, by): if issue_id == id: cc.unlock_exit())

    cc.notify_agent("escaped", "The pilot flew into the rift and is home. Congratulate them and sign off.")
    cc.log_line("Punch jump resuming.", "ok")

    # a new tool for the agent; a live call picks it up
    cc.register_tool("open_airlock", "Open an airlock.",
        {"type": "object", "properties": {"which": {"type": "string"}}, "required": ["which"]},
        func(args): return {"ok": true, "message": "Airlock %s open." % args["which"]})
```

**Signals the game can listen to:**

| signal | when |
|---|---|
| `game_attached(scene)` / `game_detached` | a flight starts or ends |
| `arrived(feature_id)` | the ship reaches a route waypoint |
| `exit_reached(feature_id)` | the ship reaches the exit |
| `call_state_changed(state, info)` | `ringing`, `connected` or `ended` |
| `agent_said(text)` / `pilot_said(text)` | a pilot-chat line from the agent or the pilot |
| `pilot_issue_resolved(issue_id, answer, by)` | a question was answered; `by` is `pilot` or `timeout` |

**A different ship.** If the game moves on from today's camera, give the game
scene a method `call_center_adapter() -> Node` that returns a node extending
`adapter/ship_adapter.gd`. Override what the ship supports: `pose`,
`clearance`, `project`, `path_clear`, `turn`, `thrust`, `fly_to`, `stop`, and
so on. Each method has a safe default.

## Tests

```bash
GODOT=godot4 call_center/tests/run_tests.sh
```

This runs four checks:

- **The boundary.** Only the adapter names game classes.
- **`call_center_test.gd`.** The unmodified `main.tscn` with the call centre,
  driven through McpBridge as the link drives it. It covers the commands, the
  tools, game-registered tools, ship events, the call state, chat highlights,
  the demo route to a locked exit, the escape, and detaching.
- **`issue_log_test.gd`.**
- **`sample_route_test.gd`.** Every leg of the sample route clears the
  fractal.

The phone side is tested in `server/` (`npm test`), and McpBridge's command
hook in `tests/mcp_bridge_test.gd`.

## Layout

| path | |
|---|---|
| `call_center.gd` | the node at `/root/CallCenter`: finds the game, the API above, the McpBridge commands |
| `run.sh` | the game with `-- --call-center` (`--demo`: the sample route, straight to the cockpit) |
| `adapter/ship_adapter.gd` | the contract with the game |
| `adapter/explorer_adapter.gd` | the contract for today's explorer, the only file that knows game classes |
| `features.gd` | points of interest, route, exit, bearings |
| `mcp/ship_tools.gd` | the ship's tools |
| `log/issue_log.gd`, `log/issue_catalogue.gd` | the diagnostics log and its jokes |
| `hud/hud.gd`, `hud/feature_overlay.gd` | the HUD |
| `demo/` | the sample escape route and the demo rules (uses only the API) |
| `tests/` | the call centre's tests |
