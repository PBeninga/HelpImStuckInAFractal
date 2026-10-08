# Level sequences — design

A **level** is what today's saved view is: one JSON file of shape, bindings,
axes, preferences, camera and noise. A **sequence** is an ordered list of level
files, saved as its own kind of file. The console gains a third column, the
**Sequence** pane, that edits the open sequence; while a sequence is open, the
number keys **1–9** enter its first to ninth level. Every level also carries a
**start** pose — the position and orientation the player gets on entering it —
that is set deliberately, so flying around and quick-saving never moves it.

Decisions below were made without a question round on 2026-10-08, at the
user's request; the ones worth a second look are listed at the end under
**Decisions to review**.

## Goals

- Repurpose the save/load we have as **level** saves: same format, same
  directory, same panels, relabelled. Add a `start` section (position and
  orientation) that is written on every save and applied on every load.
- **Sequence** saves: a second file kind, `saves/sequences/*.json`, holding an
  ordered list of level files. Save / Save as… / Load… like the keymap strip.
- A **Sequence pane** in the console as a third column: the list of levels
  (numbered by the key that enters them), add / remove / reorder, enter one
  with a click, set and go to the current level's start, and the sequence file
  strip.
- Three columns in the console — Shape | Movement | Sequence — with a
  draggable divider between each pair.
- Number keys 1–9 enter level N of the open sequence (a transition in its
  most primitive form). Out of range or no sequence: a status line, nothing
  else.
- Everything tested headlessly in the style of `tests/`, the UI parts by
  `UiDriver`; the default picture unchanged.

## Non-goals

Authored transitions between levels (triggers, portals, timing): the entry
dictionaries leave room for them, nothing more. A keymap per level (a level
still loads a view and the keymap is still separate). Level names other than
the file name. Dirty tracking or "unsaved changes" prompts. Renaming the
`Workspace` / `WorkspaceFiles` classes: only user-facing strings and `Main`'s
method names change. A sequence in the pause menu (it lives in the console).
The web export's `user://` directory gets the same `sequences/` subdirectory
by the existing `WorkspaceFiles` logic; nothing more.

## The pieces

```
src/levels/
  level_sequence.gd        LevelSequence: the ordered entries, the JSON file; changed
src/workspace/
  workspace.gd             + "start" in capture/restore (position, forward, up)
  workspace_files.gd       + noun (dialog titles "Save level" / "Save sequence")
src/camera/
  camera_state.gd          + look_from(position, forward, up)
src/ui/console/
  console_window.gd        three columns in an HSplitContainer; setup takes the sequence
  sequence_pane.gd         SequencePane: the list, buttons, start row, file strip
src/main.gd                owns the LevelSequence, the level start, enters levels on 1–9
project.godot              + actions level_1 … level_9
saves/sequences/tour.json  a shipped sequence of the four shipped levels
```

### Level files: the `start` section

A level is the version-2 view file plus one optional section:

```json
"start": {
	"position": [8.175847, 3.81246, 3.283393],
	"forward": [-0.8516508, -0.3971313, -0.3420201],
	"up": [-0.3099755, -0.1445439, 0.9396928]
}
```

`position`, `forward` and `up` are in fractal coordinates, the camera
section's convention. The file version stays **2**: the section is optional,
a build without it ignores the key, and a file without it still loads.

`Main` holds the open level's start as a `Transform3D`, `_level_start`, or
null when none is known. The rules:

| event | what happens to the start |
|---|---|
| a level loads with a `start` section | `_level_start` = that pose; the camera is placed there |
| a level loads without one (every file saved before this change) | `_level_start` = the file's `camera` pose; the camera is placed there, as today |
| **Set start here** in the Sequence pane | `_level_start` = the camera's pose now; status "Start set — save the level to keep it" |
| **Go to start** | the camera is placed at `_level_start` (no-op with a status when null) |
| a level is saved (Save level…, ⌘S) | `start` = `_level_start`, or the camera's pose when null |
| Back to Menu / a new Main | null |

So quick-saving while flying keeps the start where it was set; only the
explicit button moves it. The `camera` section keeps being written and read as
today, so a file still records where the author was, but on load the camera
goes to `start`.

`Workspace.capture(..., start: Variant = null)` writes the section when `start`
is a `Transform3D`. `Workspace.load_file` returns `start` in its result
dictionary (a `Transform3D`, or null when absent or malformed, with a warning
"Malformed start ignored" in the malformed case); `restore()` is unchanged, so
the camera section is applied as before and `Main` then overrides the camera
from `start`. `CameraState.look_from(position, forward, up)` is the one place
that turns a pose into a transform (`Workspace._restore_camera` uses it too);
it rejects a zero or parallel pair the way `_restore_camera` does.

Placing the camera on a level load in Orbit mode calls `_orbit.enter()` after,
as `load_level_from` already does.

### Sequence files

`saves/sequences/<name>.json`:

```json
{
	"version": 1,
	"levels": [
		{"file": "default.json"},
		{"file": "juliaIceField.json"},
		{"file": "juliaIceTerraces.json"},
		{"file": "noiseRidges.json"}
	]
}
```

`file` is a path **relative to the saves directory** (`res://saves/` from
source, `user://saves/` in an export), so a sequence is the same file in both
and can be committed. A level may appear more than once. Each entry is a
dictionary so transitions can be added to it later without a format change.
The shipped `saves/sequences/tour.json` is the four shipped levels in the
order above, a one-click demo of the number keys.

`LevelSequence extends RefCounted`:

| member | what it does |
|---|---|
| `entries() -> Array[Dictionary]` | the entries in order (copies) |
| `size()`, `file(index) -> String` | the relative file name of entry `index` (0-based) |
| `path(index) -> String` | `WorkspaceFiles.directory() + file(index)`, the loadable path |
| `index_of(path) -> int` | the first entry whose `path()` equals `path`, else −1 |
| `append(file)`, `insert(index, file)`, `remove(index)`, `move(index, to)` | edits; each emits `changed` |
| `clear()` | empties the list; emits `changed` |
| `to_dict()` / `from_dict(d) -> Array` | the JSON above; `from_dict` returns warnings and skips entries that are not dictionaries with a string `file` |
| `save_file(path) -> Error` / `load_file(path) -> {ok, warnings}` | the file; `current_path` is set on success, as `Keymap` does |
| `current_path` | the open sequence file, or `""` |

`load_file` fails (`ok: false`, nothing changed) when the file is missing,
not JSON, has no `levels` array or an unsupported version — so a level file
picked by mistake in the sequence panel is refused with "… is not a
sequence". Entries whose level file does not exist on disk load fine and are
flagged in the pane; entering one reports the load failure like any other.

### Entering a level

`Main.enter_level(index: int)` (0-based) is the one path, used by the number
keys and by the pane's **Go** buttons:

1. No sequence open (`_sequence.size() == 0`) → status "No sequence open".
   `index` out of range → status "The sequence has no level N" (N 1-based).
2. The level file is loaded through `load_level_from(path)`, exactly as the
   pause menu's Load level… does: the file becomes the current level (so ⌘S
   saves it), the status line reports it, the start rule above places the
   camera.
3. `_current_level = index`; the pane highlights it.

Entering a level whose file has **no `noise` section clears the noise graph
first**, so the level you enter is the level you see; the pause menu's Load
level… keeps today's additive behaviour (a view without the key leaves the
field alone). `NoiseWindow` exposes `clear()` (what its New button does) for
this. `enter_level` reads the file's keys once to decide, through a small
`Workspace.has_section(path, "noise") -> bool`; a file that fails to load
there just falls through to the normal load failure.

After any level load — entered or loaded from the pause menu —
`_current_level = _sequence.index_of(path)` (−1 when the file is not in the
sequence), so the highlight follows whatever is loaded.

**Number keys.** `project.godot` gains nine actions, `level_1` … `level_9`,
on the physical keys 1–9 of the main row (not the keypad). `Main` handles them
in `_unhandled_input`, after the Ctrl tap, pause and screenshot checks and
before the noise toggle, ignoring them while a text field has focus in any
viewport (`TextFocus.any`, like N) and never while paused (the tree is paused,
so `Main` does not see them). A key the focused console window does not use
already reaches `Main` through `unhandled_key`, so the number keys work with
the console in front. A keymap axis bound to a number key would fire
alongside; the README says 1–9 are reserved.

**Pause menu.** Save view… / Load view… become **Save level…** / **Load
level…**, with tooltips to match; `WorkspaceFiles.noun` ("view" today) is
"level" for the main instance, so the panels are titled Save level / Load
level, and "sequence" for the pane's instance. `Main.save_view_to` /
`load_view_from` become `save_level_to` / `load_level_from`. Nothing else in
the pause menu changes.

### The console: three columns

`ConsoleWindow` replaces its `VSplitContainer` with **one `HSplitContainer`
holding three children**: the Shape inspector, the Movement pane and the
Sequence pane, in that order, each wrapped in a `MarginContainer` of 4 points
so the dragger has a gutter. Godot 4.6's `SplitContainer` lays out any number
of children with a dragger between each neighbouring pair, so both dividers
are draggable with no nesting; the implementer confirms this with the existing
`console_test.gd` structure check (if this build turned out not to, the
fallback is an outer split of inspector | inner split of movement | sequence,
and the spec's tests hold either way). Split positions are kept for the
session only, as before.

Default size becomes **1400×700** points, minimum **1000×400**: the Shape
rows are wide, the Movement lines about 450 points, and the Sequence pane
needs about 300. `UiScale.place_beside` already handles a console too wide to
sit beside the main window (it goes left, or to another screen, or where there
is most room). The Shape inspector gets `SIZE_EXPAND_FILL` horizontally with
`stretch_ratio` 2; the other two 1, so the opening layout is roughly
700 | 350 | 350. The Movement and Sequence panes keep `SIZE_FILL` vertically
and top-align; the Sequence pane's level list sits in a `ScrollContainer`
that expands, so a long sequence scrolls.

`setup(table, keymap, clock, group_tooltips, speed_source, sequence)` gains
the sequence as a trailing argument; `sequence_pane() -> SequencePane` joins
`inspector()` and `movement_pane()`.

### The Sequence pane

`SequencePane extends VBoxContainer`, a view over `LevelSequence` the way
`MovementPane` is over `Keymap`: it writes through the API and rebuilds on
`changed`. Top to bottom:

```
SEQUENCE                          tour.json
┌──────────────────────────────────────┐
│ 1  default.json           Go ▲ ▼ ✕   │
│ 2  juliaIceField.json  ▶  Go ▲ ▼ ✕   │
│ 3  juliaIceTerraces.json  Go ▲ ▼ ✕   │
│ 4  (missing) old.json     Go ▲ ▼ ✕   │
└──────────────────────────────────────┘
[Add level…] [Add current level]
Level start: [Set start here] [Go to start]
[Save] [Save as…] [Load…]
status line
```

- Each line: the 1-based number (the key that enters it; entries past the
  ninth show their number greyed, since no key reaches them), the file name,
  a **▶** marker on the current level, **Go** (emits `enter_requested(index)`),
  **▲** / **▼** (`move`, the ends disabled), **✕** (`remove`). A file that is
  not on disk is prefixed "(missing)" and greyed.
- **Add level…** opens a Load-type file panel on the saves directory (a
  `WorkspaceFiles` with `noun = "level"`, Load only) and appends the pick,
  stored relative to the saves directory; a pick outside that directory is
  refused with a status. **Add current level** appends the current level file
  (emits `add_current_requested`; `Main` answers with the path, or a status
  "No level is loaded" when there is none).
- **Set start here** / **Go to start** emit `set_start_requested` /
  `go_to_start_requested`; `Main` does the work and reports through the
  pane's `show_status`.
- **Save** / **Save as…** / **Load…** are the keymap strip's pattern on a
  second `WorkspaceFiles` with `subdir = "sequences/"`, `noun = "sequence"`,
  `quick_save_enabled = false`, filter `*.json ; Sequences`. Save with no
  current path opens Save as…. Load replaces the open sequence; the current
  level highlight is recomputed from the loaded level's path.
- `show_current(index)` moves the marker; `show_status(text)` is the status
  line (hidden when empty). `line(index) -> Dictionary` exposes a line's
  widgets for tests, like `MovementPane.axis_line`.

The pane and its signals are UI; `Main` owns the sequence and the start, wires
the signals in `_build_console`, and is the only one that loads levels.

### Main's wiring

`_ready` builds the `LevelSequence` before the console (the console's setup
needs it) and connects: `enter_requested` → `enter_level`,
`set_start_requested` → `_set_level_start`, `go_to_start_requested` →
`_go_to_level_start`, `add_current_requested` → `_add_current_level`. The
file panels the pane owns open while the mouse may be captured, so each of
its `WorkspaceFiles` has `prompting` connected to `_on_prompting`, as the
view's does. `sequence() -> LevelSequence` and `level_start() -> Variant`
are exposed for tests.

## Testing

Headless, in `tests/`, following `test_case.gd`; UI checks on `UiDriver`.
Write the failing test first.

- `level_sequence_test.gd` — append/insert/remove/move and `changed`; `path()`
  under the saves directory; `index_of`; JSON round trip through a file in a
  temporary directory; `load_file` refuses a missing file, non-JSON, a level
  file (no `levels`) and a bad version without changing the entries; entries
  without a string `file` are skipped with a warning.
- `workspace_test.gd` — `start` round trip; absent → null; a malformed start
  warns and returns null; `has_section`; `look_from` rejects a parallel pair.
- `camera_state_test.gd` — `look_from` places the eye and orients forward/up.
- `console_test.gd` — the window holds one `HSplitContainer` with three
  columns in order; `sequence_pane()` lists the entries, numbers them, marks
  `show_current`, rebuilds on `changed`, Go emits `enter_requested` with the
  index, ▲/▼/✕ edit the sequence, the end buttons are disabled.
- `main_test.gd` — with `tour.json` loaded: `press_action(&"level_2")` loads
  the second level (current file name, status, camera at its start when the
  file has one, `_current_level`); `level_9` on a four-level sequence reports
  and changes nothing; the keys are ignored while a LineEdit in the console
  has focus; Set start here then save writes a `start` equal to the camera;
  loading a file with a `start` puts the camera there; entering a level with
  no noise section clears the graph; loading from the pause menu does not.
- `ui_console_test.gd` — a real drag of each divider by `UiDriver` moves it
  (the middle column's x changes); a click on a line's Go enters that level;
  the sequence strip's Save as… and Load… round-trip a file through the panel
  as the noise test does.
- `menus_test.gd` — the buttons read Save level… / Load level….
- `tests/screenshots.gd` — unchanged in intent; the console capture now shows
  three columns and must still render.
- README: "Saved views" becomes "Levels" with the `start` section; a new
  "Level sequences" section (the file, the pane, the keys); the controls
  table gains **1–9**; the console section describes three columns and the
  draggable dividers; `tour.json` in the files table.

## Decisions to review

1. **A separate `start` pose, not the camera section.** The camera section
   is already saved, but ⌘S rewrites it from wherever you are, so it cannot
   serve as a spawn point you author once. `start` moves only on **Set start
   here**; the camera still goes to `start` on every load. If you would rather
   the camera section *be* the start (one pose, moved by every save), the
   `start` section and the two buttons go away and nothing else changes.
2. **Files saved before this change get a start on their next save** equal
   to the camera at that moment (there is nothing else to use). The four
   shipped levels are left as they are; loading them uses their camera pose.
3. **Entering a level clears the noise graph when the file has none**; the
   pause menu's Load level… stays additive. One rule for both would be
   simpler; this keeps the documented load behaviour and makes the sequence
   deterministic.
4. **Relative file names in sequences** (relative to the saves directory) so
   one sequence works from source and in an export. An absolute path cannot
   be added to a sequence.
5. **The console widens to 1400×700** to fit three columns; it may no longer
   fit beside the main window on a laptop screen, where `place_beside` puts
   it elsewhere.
6. **1–9 only**, physical main-row keys, as `InputMap` actions. Level 10 and
   beyond are reachable only by the pane's Go.
7. **The classes keep their names** (`Workspace`, `WorkspaceFiles`); only
   labels, tooltips, panel titles, `Main`'s method names and the docs say
   "level".
8. **The work runs in a worktree** (`.claude/worktrees/level-sequences`,
   branch `level-sequences` from `main`), because another session edits this
   checkout; you merge.
