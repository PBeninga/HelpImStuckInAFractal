# Sequential active shapes

Status: implemented. The user explicitly approved the performance cost and session work.

## Requested behavior

The level's ordered shape list becomes a sequence of escape stages. Only the
gameplay-active shape is rendered or used for collision, clearance, scans and
route planning. The first entry is active on launch. Completing a stage advances
to the next entry beneath a fog-in/fog-out transition. Completing the last stage
runs the existing escape animation.

At the beginning of a run the agent receives the ordered shape-change commands.
Commands execute only when the agent calls the corresponding tool in response
to a human utterance. Startup, timers, movement completion, stage changes and
other system events must never authorize a shape change.

## Assumptions to make explicit

- Distances are absolute world-unit radii about the configured spawn, which is
  the run's origin. Stage changes do not teleport the player. Default radii
  increase by the existing Gameplay exit radius for each entry.
- Editor selection remains independent of gameplay-active shape. Selecting a
  different inspector must not advance the run or reveal that shape.
- Explicitly authored commands are stage objectives as well as geometry edits.
  A scripted stage advances only after its commands are applied and its radius
  is exceeded. Unscripted stages advance on distance alone; autopilot obeys collision.
- `inversion -0.5` means a delta of -0.5 to the existing inversion radius:
  `kleinian_radius` for Kleinian, `fixed_radius` for Mandelbox. It is not a new
  distance estimator. Reject unsupported fractal types and out-of-range changes
  explicitly. Other commands name an existing numeric shape attribute and its
  absolute target value. Scripts must be editable and saved with each entry.
- New entries and old levels missing commands have empty command lists.
  `inversion -0.5` is an example only, never an automatic gameplay requirement.
  Scripts run only when explicitly authored into a level. Invalid saved scripts
  remain blocked with a warning rather than silently dropping required objectives.
- Return to spawn and loading a level restart the sequence and restore scripted
  runtime edits. Saving stores authoring data, not partially completed progress.

## Integration

Keep run state in a small gameplay controller, separate from authoring tables.
It owns stage index, command cursor, run generation and transition phase. A
monotonic human-message token authorizes a single scripted command; consuming
it, changing stage or resetting the run invalidates it. Tool calls carry the
expected run/stage/command cursor/human token so stale work cannot mutate the new
active shape or consume a later utterance. A grant expires after 60 seconds.

Shape entries persist escape distance and ordered command strings. The console
shows both fields and labels the gameplay-active entry independently of editor
selection. Agent status includes the entire script, current stage, next command,
radius, origin and transition state. Supply the same initial briefing to the
voice session and the direct MCP path, including on late connection and reset.

Filter renderer uploads and CPU scene queries through the same active-shape
selection. Preserve original indices in CPU query results. Snapshot consumers
(ship-depth scans and route planner) copy the active stage and detect stage
changes as stale results. Route planning targets the current spawn-centered
radius; only the final completed stage reports `escaped`.

Reuse existing fog uniforms, with a temporary full-screen fog-colored veil for
guaranteed opacity. Each half of the fog animation lasts 0.7 seconds, with an
opaque frame held at the switch. Switch geometry only at full fog
coverage, invalidate cached imagery/depth at the swap, then reveal the new
shape. Suspend progression during the transition so a large movement cannot
skip several stages. Do not mutate the saved fog settings.

## Performance and verification

No extra rays are planned. The new work is CPU stage/authorization bookkeeping,
radius checks and temporary fog animation updates. Rendering a single shape
reduces geometry work for multi-shape levels. Net frame-time impact has not been
measured. The user explicitly approved the cost. The veil adds temporary
compositing while visible, but no geometry rays or distance-estimator math.

Headless regression coverage: stage order; radius boundary and nonzero spawn;
required commands; no unsolicited command execution; stale/duplicate commands;
editor selection independence; only active geometry in renderer and CPU scans;
fog fully covering the swap; final-stage-only escape; reset/load/save behavior;
invalid scripts and unsupported inversion; voice and MCP initial briefing.

Run the affected Godot suites, call-center tests and server Node tests. Do not
launch a desktop window. Visual fog/tunnel verification requires a separately
authorized windowed run; headless checks can validate state and uniforms only.


## Verified implementation and limits

- The first shape is selected for gameplay on launch/load; existing saved camera
  positions are preserved. Return to spawn resets the run and moves the camera.
- Escape settings appear behind each shape header's Escape settings button;
  Enter saves semicolon-separated commands. Changing stage settings restarts
  progression. Inspector selection remains independent.
- Both direct MCP and voice/call-center tools expose the briefing and strict
  command protocol. Startup, reset and late call-center attachment carry it.
- An independent review identified bound-radius delta handling and identical
  command retries; both were reproduced by failing tests and fixed.
- Visual fog/tunnel appearance has not been checked in a GPU window. The
  headless tests cover uniform packing, opaque swap timing and cached-history
  resets. No claim is made that a radius edit geometrically seals every possible
  route; required objectives enforce necessity because flight bypasses collision.
