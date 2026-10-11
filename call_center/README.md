# The call centre: Sub-Dimensional Support

The stranded pilot's help line, kept apart from the game. When a hyperspace
jump strands the ship inside the fractal, the pilot phones **Sub-Dimensional
Support**, a real phone number. A tongue-in-cheek AI support agent answers,
explains the disaster in breathless mathematical babble, and flies the ship to
the exit as the pilot talks. Meanwhile a **diagnostics log** scrolls past,
fixing problems on its own and now and then needing the pilot's answer, and
the HUD **highlights whatever the agent is talking about**.

Everything for this lives in this folder: the HUD, the ship's MCP server, the
diagnostics log and the relay server. It changes **no game file** and
**no project setting**:

- **No global class names.** Scripts use `preload`, so nothing here can clash
  with the game's classes.
- **One file knows the game.** `adapter/explorer_adapter.gd` uses Main's
  public `camera`, `params`, `view`, `fly` and `table()`.
  `tests/run_tests.sh` fails if any other file names a game class.
- **It attaches at runtime.** `boot.tscn` puts the call centre at
  `/root/CallCenter`, where an autoload would sit, then loads the game's own
  main scene. From there it watches for the game scene and steps aside on the
  title menu.

```
phone ─► Twilio ─(audio)─► server/ relay ─► OpenAI Realtime voice agent
                                  ▲   │ MCP over WebSocket (the game dials out)
                                  │   ▼
                     ┌──────── call_center/ (in the game process) ────────┐
                     │ mcp/ship_link.gd   the ship's MCP server            │
                     │ mcp/ship_tools.gd  scan, highlight, turn, thrust,   │
                     │                    fly_to_feature, resolve_issue …  │
                     │ hud/               log · status · call · brackets   │
                     │ log/               crash report, issues, questions  │
                     │ features.gd        the game's points of interest    │
                     │ adapter/ ──────────► the game (Main), untouched      │
                     └─────────────────────────────────────────────────────┘
```

## Run it

```bash
call_center/run.sh                # the game as usual, with the call centre
call_center/run.sh --demo         # straight to the cockpit on the sample escape route
```

`run.sh` calls the game's own `./run.sh` with `call_center/boot.tscn` (or
`demo.tscn`). Arguments after `--` reach the game, e.g.
`-- --ship-server=wss://….ngrok.app/game --ship-token=…`.

**Try a full call without any accounts.** In one terminal:

```bash
cd call_center/server && npm install && npm run demo
```

In another, run `call_center/run.sh --demo`. The scripted call flies the real
game through its MCP tools from the crash report to the exit.

For the real phone line (Twilio + OpenAI keys, ngrok), the text chat
(`npm run chat`), and the relay's settings and security, see
[`server/README.md`](server/README.md).

## What the pilot sees

- **The crash report.** The SHIP DIAGNOSTICS log (top right) plays it:
  *Error: punch jump not completed successfully · Error #13432 Mandelbrought
  recurrence generator has animalifolds instead of manifolds · Resolved
  successfully, via forced evfoldlution · … · Error #33423 Stuck in fractal
  space · Unable to automatically resolve, connecting to agent…*
- **Self-resolving issues.** After that, a new problem arrives and fixes itself
  every few seconds. Now and then one **needs the pilot**, and the agent asks
  them on the call. Unanswered questions take a default answer after 25 s
  (120 s with an agent on the line).
- **The support panel** (bottom left). It shows the number to call, the call
  state and a live transcript.
- **Highlights.** Brackets and labels mark each characteristic the agent
  mentions, by `#id` or by name. Off-screen ones get an arrow at the edge. The
  exit has its own marker and a glow ring.
- **Ship status** (top left): clearance, heading, autopilot, exit, waypoints
  and open issues.

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

    # a new tool for the agent; the relay picks it up mid-call
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
| `agent_said(text)` / `pilot_said(text)` | a finished line of the call |
| `pilot_issue_resolved(issue_id, answer, by)` | a question was answered; `by` is `pilot` or `timeout` |

**A different ship.** If the game moves on from today's camera, give the game
scene a method `call_center_adapter() -> Node` that returns a node extending
`adapter/ship_adapter.gd`. Override what the ship supports: `pose`,
`clearance`, `project`, `path_clear`, `turn`, `thrust`, `fly_to`, `stop`, and
so on. Each method has a safe default. The call centre uses the game's adapter
instead of the explorer one.

**Making it permanent.** When the game wants the call centre in every build,
there are two options. One is a single autoload line in `project.godot`:
`CallCenter="*res://call_center/call_center.gd"`. The other is making
`call_center/boot.tscn` the main scene. Until then, `call_center/run.sh` does
the same thing from outside.

## The ship's MCP tools

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
| *game-registered tools* | added and removed at runtime; the relay is told (`notifications/tools/list_changed`) |

Distances are in metres. The explorer's world unit is 1 km, so its tunnels
are 20–80 m wide.

## Tests

```bash
GODOT=godot4 call_center/tests/run_tests.sh
```

This runs four checks:

- **The boundary.** Only the adapter names game classes.
- **`call_center_test.gd`.** The unmodified `main.tscn` with the call centre
  attached. It covers finding the game, the MCP JSON-RPC, game-registered
  tools, the call and transcript, the demo route to a locked exit, the escape,
  and detaching.
- **`issue_log_test.gd`** and **`sample_route_test.gd`.** The second checks
  that every leg of the sample route clears the fractal.
- **The relay's Node tests.** These use fakes for Twilio, OpenAI and the game.

The game's own suite (`tests/run_all.sh`) is untouched and does not depend on
this folder.

## Layout

| path | |
|---|---|
| `call_center.gd` | the node at `/root/CallCenter`: finds the game, the API above, ship events → the agent |
| `boot.gd`, `boot.tscn`, `demo.tscn`, `run.sh` | attach to the unmodified game |
| `adapter/ship_adapter.gd` | the contract with the game |
| `adapter/explorer_adapter.gd` | the contract for today's explorer, the only file that knows game classes |
| `features.gd` | points of interest, route, exit, bearings |
| `mcp/ship_tools.gd`, `mcp/ship_link.gd` | the ship's MCP tools and server |
| `log/issue_log.gd`, `log/issue_catalogue.gd` | the diagnostics log and its jokes |
| `hud/hud.gd`, `hud/feature_overlay.gd` | the HUD |
| `demo/` | the sample escape route and the demo rules (uses only the API) |
| `server/` | the relay: Twilio ⇄ OpenAI Realtime ⇄ the ship's MCP (Node) |
| `tests/` | the call centre's tests |
