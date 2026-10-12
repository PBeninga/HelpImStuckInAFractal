# The call centre: Sub-Dimensional Support

The stranded pilot's help line, kept apart from the game. When a hyperspace
jump strands the ship inside the fractal, the pilot phones **Sub-Dimensional
Support**, a real phone number. A tongue-in-cheek AI support agent answers,
explains the disaster in breathless mathematical babble, and flies the ship to
the exit as the pilot talks. Meanwhile a **diagnostics log** scrolls past,
fixing problems on its own, and
the HUD **highlights whatever the agent is talking about**.

This folder is the in-game half: the HUD, the diagnostics log, the ship's
tools and events. The phone half (Twilio, the OpenAI Realtime voice agent, the
link) is `server/`. They meet in `McpBridge` (`src/mcp/`), the game's command
socket.

```
 phone ─► Twilio ─(audio)─► server/ (Railway) ─► OpenAI Realtime voice agent
                                 ▲   │ tool calls, ship events, transcripts
                    wss /game/link   ▼   (the game dials out when it starts)
                         McpBridge (src/mcp) + its ServerLink
                                 │        ── pilot chat (src/chat): the conversation
                                 │ ship_tools · ship_tool · ship_events · call_center
                     ┌──────── call_center/ ────────────────────────────────┐
                     │ call_center.gd      the node at /root/CallCenter       │
                     │ mcp/ship_tools.gd   scan, highlight, turn, thrust,     │
                     │                     fly_to_point, plan_escape …    │
                     │ hud/                status · diagnostics · support ·   │
                     │                     brackets                           │
                     │ log/                crash report, issues, questions    │
                     │ features.gd         legacy overlay support      │
                     │ adapter/ ───────────► the game (Main), untouched        │
                     └────────────────────────────────────────────────────────┘
```

**How it stays apart from the game:**

- **No global class names.** Scripts use `preload`, so nothing here can clash
  with the game's classes.
- **The adapter knows the game.** `adapter/explorer_adapter.gd` uses Main's
  public `camera`, `params`, `view`, `fly` and `table()`.
  It delegates route timing to `src/mcp/escape_planner.gd` in the game layer.
- **It starts only on request.** McpBridge starts it on `-- --call-center`
  (or `FRACTAL_CALL_CENTER=1`). It then finds the game scene by itself and
  stays out of the way on the title menu.

## Run it

```bash
call_center/run.sh                # the game as usual, with the call centre
call_center/run.sh --demo         # straight to the cockpit, with live geometry navigation
```

The root `./run.sh` always delegates to this launcher with the same arguments.
Both support `--editor` to open the game in the Godot editor.

From a Claude session, use `tools/launch.sh -- --play --call-center-demo`, or
the MCP `launch_game {call_center: "demo"}`.

**A whole call without any accounts.** With the game running (`--demo`),
run:

```bash
cd server && npm install && npm run demo
```

This plays a complete support call through the real server, link and bridge,
with a fake Twilio caller and a scripted voice agent in place of OpenAI's
model. It attempts escape using live route estimates and waits for each instruction outcome. See
[`server/README.md`](../server/README.md) for the real phone line: Railway,
Twilio and `OPENAI_API_KEY`. The game links itself to the server when it
starts, given `FRACTAL_SERVER_URL` and `GAME_LINK_TOKEN` (in the environment
or `server/.env`).

## What the pilot sees

- **Ship status upper-left; diagnostics lower-right.** The square log
  starts with the crash report: *Error: punch jump not completed successfully
  · Error #13432 Mandelbrought recurrence generator has animalifolds instead
  of manifolds · Resolved successfully, via forced evfoldlution · … · Error
  #33423 Stuck in fractal space · Unable to automatically resolve, connecting
  to agent…*
- **Self-resolving issues.** After that, a new problem arrives and fixes itself
  every 50–100 seconds (the first after 30 seconds). Random pilot questions are disabled. Escape means crossing the Gameplay exit sphere. The voice agent asks only for clarification needed
  to carry out a pilot request.
- **The SUB-DIMENSIONAL SUPPORT panel** (bottom left). It shows the number to
  call, then who is on the line and for how long.
- **The pilot chat** (McpBridge's, upper-right). It holds the conversation:
  the caller's words as voice messages, the agent's as "Support (phone)"
  lines. What the pilot types there goes to the agent, and while a call is
  up the panel shows an agent listening.
- **Directions.** The agent can point a turning arrow toward a world coordinate
  or flash a HUD panel. Scripted characteristics and waypoint routes are no
  longer loaded or exposed to the agent.

## The McpBridge commands it adds

| command | |
|---|---|
| `ship_tools` | `{tools: [{name, description, inputSchema}]}`: the ship's tools (below) |
| `ship_tool {name, arguments}` | run one; returns `{ok, message, …}` |
| `ship_events {after, timeout}` | long-poll the agent's news `{events: [{id, kind, summary, notify_agent, …}], last_id}`: stages, instruction completion/cancellation, autopilot slowdown, `tools_changed`, escape |
| `call_center {support_number, call_state, agent_name, link_up}` | the phone side reports in (the link sends these) |

**For Claude.** `mcp/server.mjs` exposes the same tools as `ship_tools`,
`ship` and `ship_events`.

**The ship's tools:**

| tool | |
|---|---|
| `get_ship_status` | compact position, facing, Gameplay speed, autopilot and exit-sphere boundary; no scan arrays |
| `scan_surroundings` | tunable multidirectional raycast geometry, requested explicitly |
| `scan_ship_depth` | **expensive**, full sphere or a wide cone around `direction`; compact recommendations by default, raw depths with `include_rays: true`; 96 rays, configurable 24–256 |
| `get_depth_scan` | cached screen-depth summary; `include_grid: true` requests the 2D distance array and status mask |
| `plan_escape` | one leg toward the furthest measured corridor; optional `candidate_directions` restricts to current scan recommendations |
| `highlight` / `clear_highlights` | flash or clear HUD panels |
| `turn_ship`, `face_point`, `thrust` | rotate or move at player Gameplay speed; movement obeys collision and local-clearance step limits |
| `fly_to_point`, `full_stop` | fly to world coordinates or cancel the active instruction |
| `point_direction`, `clear_direction` | show/clear a turning arrow toward `point: [x,y,z]`; optional label and seconds (1–300, default 30) |
| `set_screen_tints`, `clear_screen_tints` | color up to 8 screen regions using depth-scan `uv` coordinates; radius, RGB and strength per region; expires after 1–30 seconds (default 5) |
| `get_console_controls` | inspect shapes, light/material/palette, view/renderer, gameplay, axes and noise |
| `set_console_controls` | edit those settings through the same models as the console |
| `console_action` | add/remove/select/rename shapes, resets, spawn, levels, windows, start, pause/resume |
| `resolve_issue` | legacy game-extension API; not offered to the voice agent |
| `post_to_log` | write an AGENT line to the diagnostics log |
| `set_visual_filter` | change the palette, when the adapter supports it |
| *game-registered tools* | added and removed at runtime (`tools_changed` updates a live call) |

### Screen-space guidance

`set_screen_tints` draws soft circular color overlays using a small canvas shader,
after the fractal and below the cockpit UI. It adds no raycasts or shape lookup.
Take `open_patches[].uv` from a current `get_depth_scan` and use it directly:

```json
{"name":"set_screen_tints","arguments":{"regions":[{"center":[0.7,0.4],"radius":0.12,"color":[0.2,1,0.4],"strength":0.45}],"seconds":5}}
```

Coordinates are normalized with `[0,0]` at the top left. Radius is measured as
a fraction of view height. Each call replaces the previous marks (up to eight).
They remain at their screen coordinates when the camera moves: refresh using a
new observation, call `clear_screen_tints`, or let them expire. The shader colors
screen pixels, including background, and does not identify or track world shapes.

Positions, route points, route lengths and screen-depth distances are in **world
units**; one explorer world unit is 1000 metres. `thrust.meters` and fields
ending in `_m` use metres. Agent flight uses the same Gameplay speed as the
player, including distance scaling, wheel speed, Shift state and load shedding.

The Gameplay tab controls the surrounding ray count (4–64), screen-depth
columns (8–128, default 32) and capture interval (1–30 frames, default 2).
Depth capture is a small pass of the current scene shader, including displaced
geometry, with about 0.2% logarithmic distance precision. Only complete frames
are published to a local cache; headless rendering reports unavailable.

**Agent bandwidth:** local capture never sends an event. `get_depth_scan`
returns metadata and up to six broad 3×3 far-distance patches by default.
Only `include_grid: true` includes `distances[row][column]` and `status`; delivery
is limited to one request every two seconds, and `after_frame` suppresses a
previously seen frame. Transmitted grids are capped to 32 cells per axis by
default, at most 64 when explicitly requested through `max_columns`. The local
cache can remain higher fidelity. Subsampled grids include source row/column
indices. Captured pose, frame ID and age describe what was actually measured.
Range-limited cells mean no hit up to the cutoff and are useful steering evidence.
Unknown and exhausted rays are excluded. Patches report `no_hit_fraction` and
`exit_clear`; they rank by minimum observed depth, with no-hit fraction breaking ties.

If the visible screen offers no promising route, the agent can explicitly call
`scan_ship_depth {ray_count: 96}` (or pass `max_distance` in world units).
It computes new rays around the full ship, including the six camera axes and
uniformly spread spherical samples. The default response contains status counts
and up to six recommendations; `include_rays: true` adds each ray's world
direction, depth, status and step count. Unknown/exhausted rays have null depth;
range-limited rays retain their measured clear-distance lower bound. Recommendations rank the minimum
depth across five neighbouring rays; their `look_at` coordinates can be passed
to `face_point` to inspect another direction before planning a flight.

Once a candidate direction is identified, refine it with
`scan_ship_depth {direction: [x, y, z], cone_degrees: 90}`. The vector is a world
direction, not a target point. The full cone angle is configurable from 15° to
180°; samples cover the centre, edges and interior. Pass up to six recommended
`direction` vectors to `plan_escape {candidate_directions: [...]}` to compare
bounded legs using those measured directions. No unobserved shortcuts are added.
Both scan modes share the same cooldown.

This call is marked **expensive** in both MCP and the voice-agent instructions.
Navigation rays extend to twice the display horizon, capped at the exit sphere,
and have 1,200 steps each (previously 600). This extends only the scan copy;
renderer settings are unchanged. It has an eight-second work cutoff, checked
inside each ray, yields between small ray batches, and reports
partial coverage if the budget expires, and shares a five-second cooldown
between phone and direct MCP requests. It never runs automatically or sends
scan events. The captured pose and stale flag describe the snapshot used.
These CPU raycasts omit shader-only noise displacement, so inspect the new
screen before selecting the next flight leg.

`plan_escape` uses the current deeper CPU scan, falling back to fresh screen
patches. It ranks observed corridors by clear distance, then no-hit fraction,
then estimated travel time. Supplied direction vectors must match an observation;
missing or stale observations return `scan_required` without a destination.
Each leg travels 75% of the minimum observed depth, keeping a buffer before a
wall or an unknown region. A patch whose rays all reach the exit can produce a
final leg across the boundary. Timing covers only this leg, not a complete escape.
After each leg, observe again and replan. Samples may miss thin obstacles.

Autopilot thrust and flight now cap each movement tick to 80% of local surface
clearance and call the player's adaptive collision check before moving, including
the final arrival step. This uses at most three additional distance evaluations
per movement tick, without additional rays. Blocked or numerically unresolvable
moves cancel with a `collision:` reason and the current pose. The agent must
rescan and pick a new direction rather than repeatedly driving at that target.
CPU collision does not include shader-only displacement.

During translation, the adapter emits `autopilot_slowdown` when the Gameplay
speed used for movement drops at least 10% below its reference for 0.75 seconds.
It sends at most one alert every five seconds across instructions. Each alert
resets the reference to the current speed, so steady slow travel does not keep
alerting; recovered speed raises the reference again. Turns and the shortened
final arrival step do not trigger alerts. Speed changes can reflect geometry,
wheel/Shift settings or load shedding; the event does not assume a cause.

Alerts include the instruction ID, previous/current speed in world units per
second, drop fraction, actual motion direction, pose, target and approximate
remaining time. No ray arrays or depth grids are attached. The agent ignores
obsolete instruction IDs and may stop the current instruction to replan before
arrival. It waits for cancellation, obtains a candidate, requests a wide cone
scan and compares measured clearances. No expensive scan runs automatically.

Every accepted movement or turn returns an `instruction_id`. Exactly one
`instruction_completed` or `instruction_cancelled` event carries that ID,
reason, final position and facing; events contain no depth grids. Replacing an
instruction, manual control, full stop or ending the flight cancels it.

## For the game: the contract

The game does not need to know the call centre exists. To make it richer, the
game talks to `/root/CallCenter` when it is present. All of it is optional:

```gdscript
var cc := get_node_or_null(^"/root/CallCenter")
if cc:
    cc.auto_begin = false          # the game has its own intro…
    cc.begin()                     # …and calls this when the ship lands: HUD in, crash report

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
| `exit_reached(feature_id)` | the ship crosses the exit sphere; legacy argument is empty |
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
  legacy route behavior and detaching. The route fixtures predate live navigation.
- **`issue_log_test.gd`.**
- **`sample_route_test.gd`.** Every leg of the sample route clears the
  fractal.

The phone side is tested in `server/` (`npm test`), and McpBridge's command
hook in `tests/mcp_bridge_test.gd`.

## Layout

| path | |
|---|---|
| `call_center.gd` | the node at `/root/CallCenter`: finds the game, the API above, the McpBridge commands |
| `run.sh` | the game with `-- --call-center` (`--demo`: straight to the cockpit) |
| `adapter/ship_adapter.gd` | the contract with the game |
| `adapter/explorer_adapter.gd` | the contract for today's explorer, the game-specific flight adapter |
| `src/mcp/escape_planner.gd` | sampled travel-time route estimates |
| `features.gd` | dormant legacy overlay registry; not exposed to the agent |
| `mcp/ship_tools.gd` | the ship's tools |
| `log/issue_log.gd`, `log/issue_catalogue.gd` | the diagnostics log and its jokes |
| `hud/hud.gd`, `hud/feature_overlay.gd` | the HUD |
| `demo/` | archived sample route fixtures; no longer loaded by the call centre |
| `tests/` | the call centre's tests |
