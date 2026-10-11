# Help I'm Stuck In A Fractal

A from-scratch Godot 4.6 Mandelbox viewer that emulates the renderer at
[icefractal.com/mandelbox/](https://icefractal.com/mandelbox/): the same default
view, the four shape sliders, the thirteen colour modes, the precision control,
Julia mode and an orbit camera. On top of the site it adds a distance-scaled
free-fly camera, an adaptive-resolution governor that keeps the frame rate up
while you move, and a **console** window — a Shape inspector of every
Mandelbox knob with Fractacular's binding model, and a Movement pane of virtual
axes driven by key pairs. It is built on the **GL Compatibility** renderer
(WebGL 2) so it is web-exportable.

GDScript only — no C#, even though the Godot build on disk is the Mono build.

## Run

```bash
./run.sh            # run the project
./run.sh --editor   # open it in the Godot editor instead
```

`run.sh` finds `godot4` on your `PATH` (or falls back to `Godot_mono.app` /
`Godot.app`), refreshes Godot's script-class cache when a script has changed,
and then launches the main scene: the **Icebox Nav** title menu (Play Game,
Settings, Quit; Quit is hidden in a web build). Set `GODOT=/path/to/godot` to use a different
binary.

## Controls

Tap **Ctrl** to open the **console**: the **Shape** inspector, with a row for
every Mandelbox knob, stacked above the **Movement** pane of virtual axes.
Everything the console does not own is driven directly by the mouse and
keyboard. Press **Escape** to pause: the pause menu offers Save view / Load
view, the Camera mode, Fast Controls, Console and Noise editor buttons, and
Resume / Settings / Back to Menu; Escape again steps back out.

The console and the noise editor are windows **inside the main window**, always
drawn above the view: drag one by its title bar, close it with its ✕, and
enlarge or maximise the main window when you want more room for them. (They
cannot be dragged to another monitor: separate OS windows corrupted the main
window's picture on macOS.) An open window takes the keyboard, but the keys it
does not use — Escape, N, a Ctrl tap, ⌘S, ⌘P — still reach the game; pausing
tucks the windows away and resuming brings them back.

**Settings** (from the title menu or the pause menu) has two tabs.

- **Controls** holds the mouse sensitivity. It is the player's preference, not
  part of a view: it is kept in `user://settings.cfg`, survives restarts, and
  loading a saved view does not change it.
- **Renderer** tunes how the open view is rendered, and is saved with the view
  (so it is only enabled from the pause menu). While it is showing, the pause
  dim lightens so each change can be seen behind the menu.

| Renderer option | what it does |
|---|---|
| **Detail** | scales the precision everywhere (higher = finer structure, more steps) |
| **Full-detail range** | how far full detail reaches, in multiples of the camera's distance to the nearest surface, so it means the same at any zoom depth |
| **Detail falloff** | how quickly detail coarsens past that range; 0 (the default) keeps detail matched to the pixel at every distance |
| **Max march steps** | the step budget per ray (default 128: 96 coarse + 32 fine) |
| **Min resolution** | the lowest render scale Fast Controls may drop to while moving (default 25%) |
| **Fast Controls** | the same toggle as in the Q panel |

A ray stops once the distance estimate falls below
`precision / detail × t × max(1, t / (range × d₀))^falloff`, where `t` is the
distance along the ray and `d₀` the camera's distance to the nearest surface.

### Load shedding

With Fast Controls on, the render scale is the first thing to give while you
move. Once it is at **Min resolution** and the frame rate is still under 24 fps,
the governor sheds quality a level at a time:

| level | distance fog (× d₀) | detail | step budget | Fly speed |
|---|---|---|---|---|
| 0 | none | 100% | 100% | — |
| 1 | 400 | 75% | 100% | — |
| 2 | 150 | 55% | 75% | — |
| 3 | 60 | 40% | 50% | — |
| 4 | 40 | 35% | 50% | capped at 40% |

Rays stop at the fog distance, and the view fades into a tint of the current
colour mode on the way there. The thresholds are sticky: a shed needs 0.5 s
under 24 fps (and 1 s since the last change), a restore needs 2 s over 40 fps,
nothing changes in between, and a shed soon after a restore doubles the next
restore's wait (up to 16 s). The level is kept while you are still, but the
still frame always renders at full quality. The console's Movement pane shows
`load shed N/4` while a level is active.

### Fly camera (default)

| key / action | what it does |
|---|---|
| **Ctrl** (tap) | open the console and free the mouse; tap again to close it and recapture. Fires on release, so Ctrl+S and Ctrl+P still work |
| **Q / E** | the default virtual **Axis A** (negative / positive). Bind a Shape row to Axis A to give Q and E that knob |
| **N** | toggle the noise-field editor (also releases/recaptures the mouse) |
| **Escape** | pause menu (releases the mouse; resuming recaptures it). While the noise editor has the keyboard, Escape closes it first |
| **W / A / S / D** | move forward / left / back / right |
| **Space / Backspace** | move up / down (world-relative to the camera's own up) |
| **Shift** (hold) | sprint — multiply the travel speed by 4 while held |
| mouse move | mouse-look while captured (yaw about world +Z, pitch about the camera's right; no roll) |
| mouse wheel | adjust the speed factor (×1.25 per tick up, ÷1.25 down; clamped 0.01–100) |
| click | with the mouse free, click the view to recapture the mouse (and close the noise editor); the console stays open over the view so its readouts stay in sight. A click on the console itself stays in the console |

Movement speed scales with the distance to the nearest surface — roughly one
second covers the gap to whatever you are looking at — so flight stays usable
from far away and slows down automatically as you approach the fractal.

### Orbit camera

Switch to **Orbit** from the pause menu's Camera option. The mouse is never
captured in this mode.

| action | what it does |
|---|---|
| left-drag | orbit around the centre point |
| **Shift** + left-drag | pan (moves both the camera and the centre) |
| right-drag, or **Alt** + left-drag | dolly in and out |
| mouse wheel | zoom toward the point under the cursor |
| click (no drag) | re-centre on the surface under the cursor (or the origin if nothing is hit nearby) |

### Console (Ctrl)

A Ctrl tap (or the pause menu's **Console…** button) opens the console, a
window inside the main window: the **Shape** pane on top, taking the full width
and most of the height, and the **Movement** pane below it at its natural
height (drag the bar between them to share the height differently).

**Shape pane.** One row per Mandelbox knob, grouped **Box** / **Julia** /
**Iteration rotation** / **Render**:

- **Box** — Scale, Fold limit, Min radius, Fixed radius, Fold order (Box→Sphere
  or Sphere→Box) and **W**, the fourth coordinate of the 4D sample point (0 is
  today's 3D box).
- **Julia** — a master **Julia (all)** toggle and four per-component toggles,
  each revealing its **Constant** (the rows collapse until Julia is on). While
  Julia is on, a white ring marks the point in the view; drag it (with the mouse
  free) to move Constants x/y/z, which survives the next resolve.
- **Iteration rotation** — the six 4D plane angles applied inside every
  iteration (they change the fractal itself, not just the view).
- **Render** — the thirteen Colour modes and the ray-march Precision (log slider).

Each bindable row carries Fractacular's binding widgets: a **Source** (None,
Time, or a virtual axis), a **Gain**, a **Waveform** (Linear / Sine / Triangle)
and a **Period**. The value in use each frame is `default + gain ×
waveform(source)`, shown as a live readout while a binding is active.

**Movement pane.** One line per virtual axis — an editable label, its id, the
live value, a **0** button, the push **speed**, two key-capture buttons (click,
then press a key) and a remove button — plus **Add axis**, the clock readout,
the fly camera's speed factor, and **Save** / **Save as…** / **Load…** for the
keymap file. Key pairs push an axis at its speed; a Shape row bound to that axis
reads the value, so the row's gain is the key's sensitivity.

**⌘S** (Ctrl+S elsewhere) saves the view over the current file without a panel;
with no current file it opens the Save panel.

**⌘P** (Ctrl+P elsewhere) copies a screenshot of the fractal, without any UI, to
the clipboard as a PNG. On Linux this needs `xclip`.

### Pause menu (Escape)

Escape pauses and opens the menu, which holds what the old Q panel kept that is
not a shape knob: a **Save view…** / **Load view…** row with the current file's
name and a status line, the **Camera** mode (Fly / Orbit), the **Fast Controls**
toggle (let the resolution governor drop render scale while you interact), a
**Console…** button (opens the console and resumes with the mouse free — the
way in when a browser swallows the Ctrl tap), a **Noise editor…** button, and
Resume / **Settings** / Back to Menu. Settings holds the mouse sensitivity.

## Keymap

The virtual axes and their key pairs live in **`saves/keymap.json`**, separate
from any view (a level loads a view and a keymap independently, and the same
view can play under different keys):

```json
{
  "version": 1,
  "axes": [
    {"id": "a", "label": "Axis A", "speed": 1.0, "positive": "E", "negative": "Q"}
  ]
}
```

Keys are stored by name (layout-independent), `""` meaning unbound. The shipped
default is one Axis A on Q/E at one unit per second. Each axis registers two
input actions, `axis_<id>_pos` and `axis_<id>_neg`. The Movement pane's Save /
Load edit this file; a missing or malformed file falls back to the default.

## Saved views

A save is a small JSON file, **version 2**:

- **`shape`** — `AttributeTable.to_dict()`: a `defaults` map (every catalogue id
  to its value) and a `bindings` map (only active bindings, each a source /
  gain / waveform / period).
- **`axes`** — every virtual axis value by id.
- **`fractal`** — the non-shape preferences: `fast_controls`, `camera_mode`
  (`"fly"`/`"orbit"`) and `mouse_sensitivity`.
- **`camera`** — the eye, forward and up vectors and the speed factor.
- **`noise`** — the noise graph, when one is wired (additive; see below).

Loading skips anything it does not recognise or cannot read, with a warning, and
leaves values a file does not mention as they are. A **version-1** file (the old
flat `fractal` section) still loads: its keys are mapped (`scale`→`box_scale`,
`inner_radius`→`min_radius`, `outer_radius`→`fixed_radius`,
`julia_enabled`→`julia_all`, `julia_point`→the three Constants) without a
warning. Saving always writes version 2. An exported build cannot write into the
project, so it saves to `user://saves/` instead.

| file | what it is |
|---|---|
| `saves/default.json` | the opening view |
| `saves/juliaIceField.json` | Julia mode at `(-0.23, 1.512, 1.892)`, Scale −2.29, Min 0, Fold 0.72, Fixed 0.29, Ice Fractal, precision 0.00002 |
| `saves/juliaIceTerraces.json` | Julia mode at `(-0.23, 1.512, 1.892)`, Scale −1.88, Min 0.49, Fold 0.81, Fixed 0.53, Ice Fractal, precision 0.0001 |
| `saves/noiseRidges.json` | the default Ice Fractal view with a noise field wired: value-noise ridges displacing the surface and tinting it blue (see **Noise fields**) |

## Noise fields

Press **N** (or the **Noise editor…** button in the pause menu) to open the
noise-field editor: an in-app node graph, ported from Fractacular's Isolation
window, that builds a 3D scalar field and overlays it on the Mandelbox. Wiring it
to the **Output** node does two things to the picture, live as you edit:

- **Displace** — the field is multiplied by Amplitude and added to the distance
  estimate, so the surface ripples, bulges or erodes. A positive value pushes the
  surface *in*. While Displace is wired, each ray-march step is shortened by the
  Output's **Step scale** so the march does not step over the displaced surface.
- **Tint** — the surface colour is blended toward the Output's **Tint colour** by
  the field, scaled by **Tint strength**.

The editor is a window inside the main window, like the console: drag it by its
title bar; its ✕, or N or Escape while it has the keyboard, closes it. Opening
the editor frees the mouse; a click in the view in Fly mode closes it and
recaptures. **Orbit** mode (Camera dropdown) is the
comfortable way to author, since the mouse is never captured. Each node with an
output carries a live preview — a flat slice of the field — and the toolbar's
**Extent** and **Slice Z** choose which slice every preview shows. Right-click the
canvas for the add menu; drag between the coloured ports to wire (green is a
Float scalar field, amber a Vec3 vector field); Delete, Backspace or right-click a
wire to remove it.

| group | nodes |
|---|---|
| **Source** | **Position** — the sample point, in fractal coordinates (one per graph) |
| **Noise** | **Value noise**, **Gradient noise** (both with Octaves/Lacunarity/Gain FBM), **Cellular** (Worley F1) |
| **Vector** | **Transform** (offset, scale, rotate), **Warp** (domain warp), **Combine XYZ**, **Split XYZ** |
| **Math** | **Constant**, **Math** (Add…Fract), **Remap**, **Clamp**, **Mix**, **Length** |
| **Output** | **Output** — Displace and Tint inputs, Amplitude, Step scale, Tint colour and strength (one per graph) |

**Saving.** The graph is saved with the view, as an additive `"noise"` key in the
same JSON file — a view without the key leaves the current field alone. The editor
can also save and load graphs on their own, as `saves/noise/*.json`
(`{"version": 1, "noise": {…}}`), with its own **Save…** / **Load…** buttons.
Load **`saves/noiseRidges.json`** for a one-click demo: value-noise ridges
displacing and blue-tinting the default Ice Fractal view.

A FLOAT parameter edit only re-pushes a shader uniform; an Octaves/op/toggle edit
(baked into the generated GLSL) recompiles the shader. An unwired graph compiles
to nothing, so the picture and its cost are exactly as if there were no editor.

## Default view

The viewer opens on the site's initial framing exactly.

| quantity | value |
|---|---|
| eye | `(8.175847, 3.812460, 3.283393)` |
| looks at | the origin |
| vertical field of view | 40° |
| world up | +Z |

All positions are in **fractal coordinates** — the space the distance estimator
is evaluated in. The site's own camera coordinates are half of ours: a point the
site reports at `(x, y, z)` is `(2x, 2y, 2z)` here.

## Testing

```bash
tests/run_all.sh      # every headless SceneTree test
tests/screenshots.sh  # windowed render check (writes PNGs to screenshots/)
```

`tests/run_all.sh` imports the project (refreshing the class cache) and then runs
each `tests/*_test.gd` headlessly; it exits non-zero if any test fails. Because
the headless renderer produces no pixels, the actual render is verified by
`tests/screenshots.sh`, which launches Godot windowed **without stealing focus**
(via `open -g`), renders the default view, each colour mode, and a
`console_bound_axis` frame (Axis A bound to the scale, required to differ from
the default), and writes the results plus a `PASS`/`FAIL` log to
`tests/out/screenshots.txt`.

The UI suites drive the real widgets the way a player does, still headless.
`tests/ui_driver.gd` (`UiDriver`) turns the 64x64 headless root into a
1280x800 logical surface and pushes synthetic mouse, wheel, trackpad-pan and
key events through the root at window-aware global coordinates, so clicks
land in the embedded console and noise windows, their dropdown popups and
file panels through Godot's own hit-testing. `ui_driver_test.gd` checks each
primitive; `ui_console_test.gd` scrolls the Shape list, picks dropdown items,
clicks and drags sliders, types values and edits axes; `ui_noise_test.gd` adds
a node from the right-click menu, wires it, edits it live and saves and loads
the graph; `ui_journey_test.gd` plays one session from the title menu to Back
to Menu.

The reference capture from the site lives at
**`docs/reference/icefractal-default.jpg`**. Put `screenshots/default_view.png`
next to it to eyeball the default view against the original — float32 and no
HiDPI mean the pixels differ, but the shape and the blue colour family should
match.

## Systems viz

`docs/viz/` is an in-browser, pannable, zoomable explainer of how the viewer
works: the architecture, one input to one frame, the distance estimator fold
by fold, every dial, the two-phase ray march, the colour modes, the two
normals, the cameras and the resolution governor. Its live figures run
JavaScript ports of the shader and the GDScript (checked at load against the
24 distance-estimator fixtures), and every tooltip links the `file:line` it
describes at a pinned commit.

```bash
./viz.sh                  # open it in your default browser
./viz.sh mandelbox/5      # straight to a tab (1-based)
node tools/viz/check.mjs --print --pane mandelbox   # every cited line exists at the pinned commit
```

It is a dependency-free static page that works from `file://`; the engine is
ported from the sibling project spellfactory. Extend or refresh it with the
`/visualize` skill (`.claude/skills/visualize/`). The links 404 until the
pinned commit is pushed.

## Web export

A single **Web** export preset (threads off) targets the git-ignored
`build/web/`:

```bash
mkdir -p build/web
godot4 --headless --path . --export-release Web build/web/index.html
```

This needs Godot's Web export templates installed; without them the export
reports missing templates rather than writing files. The export must run from a
standard (non-mono) editor: a .NET build of Godot 4 refuses the Web preset
even for a GDScript-only project like this one.

To try the build locally, serve `build/web/` over HTTP (it will not run from
`file://`), e.g. `python3 -m http.server --directory build/web`.

### Deploying

`.github/workflows/deploy-web.yml` exports the Web preset on every push to
`main` and publishes it to GitHub Pages, at
`https://adam-g-klein.github.io/HelpImStuckInAFractal/`. It installs Godot
and the web templates itself; the repository only needs Pages enabled with
**GitHub Actions** as the source (Settings > Pages), which the workflow also
attempts on its own.
