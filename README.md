# Help I'm Stuck In A Fractal

A from-scratch Godot 4.6 Mandelbox viewer that emulates the renderer at
[icefractal.com/mandelbox/](https://icefractal.com/mandelbox/): the same default
view, the four shape sliders, the thirteen colour modes, the precision control,
Julia mode and an orbit camera. On top of the site it adds a distance-scaled
free-fly camera, an adaptive-resolution governor that keeps the frame rate up
while you move, and a **console** window — a Shape inspector of every
Mandelbox knob with Fractacular's binding model, a Colour tab with
Fractacular's cosine-palette window and a tunable light, and a Movement pane of
virtual axes driven by key pairs. It is built on the **GL Compatibility** renderer
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

Tap **Ctrl** to open the **console**, a separate OS window: the **Shape** and
**Colour** tabs, with a row for every Mandelbox, colour and lighting knob, and
the **View** tab (Save / Load view, the Camera mode, the mouse sensitivity, the
Noise editor button, the Window buttons, the Renderer options and Back to Menu), stacked above the
**Movement** pane of virtual axes.
Everything the console does not own is driven directly by the mouse and
keyboard. **Escape** only frees the mouse: nothing pauses, and it never opens
or closes the console. Click the view to take the mouse back.

The console opens **beside** the main window — or on another monitor when
there is no room beside it — and can be dragged anywhere. Keep it off the main
window: on macOS (Godot 4.6.1, GL Compatibility) a separate window overlapping
the main one corrupts its picture (the fractal squeezed into the uncovered
strip, or black) until it is moved away. On a single laptop screen with the
main window at its default size there is no room beside it, so shrink the main
window, drag the console aside, or use **Fullscreen** (below). (On the web it is
a window inside the page.)

The main window first opens over **half of its screen's pixels** (each side
about 71 % of the screen's), centred. After that the game remembers where you
left the main window and the console, and reopens them there (kept in
`user://settings.cfg`; a monitor that has since been unplugged falls back to
the default). The View tab's **Window** row has:

- **Fullscreen** — one fullscreen window (on a Mac, a desktop of its own) with
  the view on the left and the console docked on the right, at 40 % of the
  width (never under the console's 700-point minimum, never over 60 %). A Ctrl
  tap still hides and shows the docked console, and the view takes the whole
  width while it is hidden. The window's own green button does the same.
  **Exit fullscreen** (or leaving fullscreen any other way) makes the console a
  separate window again.
- **Reset window** — back to the default size in the middle of its screen, with
  the console beside it, forgetting the remembered places.
The noise editor is a window **inside the main window**, always drawn above the
view: drag it by its title bar, close it with its ✕. An open window takes the
keyboard, but the keys it does not use — Escape, N, a Ctrl tap, ⌘S, ⌘P — still
reach the game.

The **mouse sensitivity** (the title menu's **Settings**, or the console's View
tab) is the player's preference, not part of a view: it is kept in
`user://settings.cfg`, survives restarts, and loading a saved view does not
change it.

The **Renderer** options on the console's View tab tune how the open view is
rendered, and are saved with the view. Their **Reset camera** button puts the
camera back where the current save file has it (below).

| Renderer option | what it does |
|---|---|
| **Detail** | scales the precision everywhere (higher = finer structure, more steps) |
| **Full-detail range** | how far full detail reaches, in multiples of the camera's distance to the nearest surface, so it means the same at any zoom depth |
| **Detail falloff** | how quickly detail coarsens past that range; 0 (the default) keeps detail matched to the pixel at every distance |
| **Max march steps** | the step budget per ray (default 128: 96 coarse + 32 fine) |
| **Min resolution** | the lowest render scale Fast Controls may drop to while moving (default 25%) |
| **Fast Controls** | drop the render scale while anything moves, then snap back to full resolution when it stops |

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
| **Escape** | free the mouse (click the view to recapture). Nothing else: no pause, and the console stays as it is. While the noise editor has the keyboard, Escape closes it |
| **W / A / S / D** | move forward / left / back / right |
| **Space / Backspace** | move up / down (world-relative to the camera's own up) |
| **Shift** (hold) | sprint — doubles the speed while held |
| **R** | show / hide the centre-ray probe: a white dot painted on the surface straight ahead, where the speed is measured to (remembered between runs) |
| mouse move | mouse-look while captured (yaw about world +Z, pitch about the camera's right; no roll) |
| mouse wheel | adjust the speed factor (×1.25 per tick up, ÷1.25 down; clamped 0.01–100) |
| click | with the mouse free, click the view to recapture the mouse (and close the noise editor); the console stays open so its readouts stay in sight. A click on the console itself stays in the console |

Movement speed follows the distance along the ray through the middle of the
screen to the surface it hits — roughly one second covers the gap to whatever
you are looking at — so flight stays usable from far away and slows down
automatically as you approach the fractal. It is capped at 10× the distance to
the nearest surface in any direction, so looking down a long corridor with a
wall at your elbow cannot carry you sideways through the wall, and a ray that
hits nothing takes that cap. The load shedder's speed cap still applies on top.

### Orbit camera

Switch to **Orbit** from the Camera option on the console's View tab. The mouse is never
captured in this mode.

| action | what it does |
|---|---|
| left-drag | orbit around the centre point |
| **Shift** + left-drag | pan (moves both the camera and the centre) |
| right-drag, or **Alt** + left-drag | dolly in and out |
| mouse wheel | zoom toward the point under the cursor |
| click (no drag) | re-centre on the surface under the cursor (or the origin if nothing is hit nearby) |

### Console (Ctrl)

A Ctrl tap opens the console, a
separate OS window: the **Shape**, **Colour** and **View** tabs on top, taking the full
width and most of the height, and the **Movement** pane below them at its
natural height (drag the bar between them to share the height differently).
**⌘=** / **⌘−** (Ctrl elsewhere) zoom everything in the console, text and
controls, a step at a time from 50% to 200%, and **⌘0** resets; the window keeps
its size and the panes reflow. The zoom is remembered between runs.

**Shape tab.** One row per Mandelbox knob, grouped **Box** / **Julia** /
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
- **Render** — the ray-march Precision (log slider).

**Colour tab.** Fractacular's Colour window at the top of one scrolling list,
then rows grouped **Colour** / **Lighting** / **Palette**:

- **Colour window** — the cosine palette `color(t) = A + B · cos(2π (C·t + D))`:
  twelve sliders (A, B, C and D over red, green and blue), the three channel
  curves they make and the gradient strip they come out as, and **Reset** (back
  to the rainbow). The strip is the shader's own formula, and follows a bound
  component live. A hint shows while the Colour mode is not Palette.
- **Colour** — the site's thirteen colour modes plus **Palette**, which paints
  with the window's palette. In Palette mode four more rows appear: **Palette
  input** (Steps, the march's step count; Radius, the hit point's distance from
  the centre; or Normal, the surface's facing), **Palette frequency** and
  **Palette offset** (position = fract(input × frequency + offset); bind the
  offset to Time for a colour cycle) and **Palette occlusion** (how much the
  step count darkens crevices).
- **Lighting** — **Ambient**, **Diffuse**, **Specular** and **Shininess** (the
  light term `diffuse·|N·L| + specular·|N·L|^shininess + ambient`), **Light
  yaw** / **Light pitch** (swing the camera headlight about the view's up and
  right axes), and **Exposure** / **Saturation** on the final colour. The
  defaults are the site's constants, so every site mode looks exactly as before
  until one is moved; they apply to every mode but Grayscale.
- **Palette** (Palette mode only) — the same twelve numbers as rows, so each
  channel's A, B, C or D can have its own Source, gain and waveform: a Sine on
  B.r pulses the red, a Linear Time drive on D.b cycles the blue.

All of it is saved with the view (the shape section), like any other row.

Each bindable row carries Fractacular's binding widgets: a **Source** (None,
Time, or a virtual axis), a **Gain**, a **Waveform** (Linear / Sine / Triangle)
and a **Period**. The value in use each frame is `default + gain ×
waveform(source)`, shown as a live readout while a binding is active.

**Movement pane.** One line per virtual axis — an editable label, its id, the
live value, a **0** button, the push **speed**, two key-capture buttons (click,
then press a key) and a remove button — plus **Add axis**, the clock readout,
the fly camera's speed factor beside a **Reset camera** button, and **Save** /
**Save as…** / **Load…** for the keymap file. Key pairs push an axis at its speed; a Shape row bound to that axis
reads the value, so the row's gain is the key's sensitivity.

**⌘S** (Ctrl+S elsewhere) saves the view over the current file without a panel;
with no current file it opens the Save panel.

**⌘P** (Ctrl+P elsewhere) copies a screenshot of the fractal, without any UI, to
the clipboard as a PNG. On Linux this needs `xclip`.

### View tab (console)

The console's View tab holds what is not a shape knob: a **Save view…** /
**Load view…** row with the current file's name and a status line, the
**Camera** mode (Fly / Orbit), the **mouse sensitivity**, a **Noise editor…**
button, the **Renderer** options (above, with Fast Controls and Reset camera)
and **Back to Menu**.

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
- **`camera`** — the eye, forward and up vectors and the speed factor. **Reset
  camera** (in the console's Movement pane and the View tab's Renderer options)
  puts the camera and speed factor back to these, as the current file was last
  loaded or saved; with no file current it goes to the starting view.
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

Press **N** (or the **Noise editor…** button on the console's View tab) to open the
noise-field editor: an in-app node graph, ported from Fractacular's Isolation
window, that builds a 3D scalar field and overlays it on the Mandelbox. Wiring it
to the **Output** node does two things to the picture, live as you edit:

- **Displace** — the field is multiplied by Amplitude and added to the distance
  estimate, so the surface ripples, bulges or erodes. A positive value pushes the
  surface *in*. While Displace is wired, each ray-march step is shortened by the
  Output's **Step scale** so the march does not step over the displaced surface.
- **Tint** — the surface colour is blended toward the Output's **Tint colour** by
  the field, scaled by **Tint strength**.

The editor is a window inside the main window (unlike the console): drag it by its
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
(via `open -g`), renders the default view, each colour mode, a
`console_bound_axis` frame (Axis A bound to the scale, required to differ from
the default) and a `lighting_raked` frame (the light swung and broadened, also
required to differ), and writes the results plus a `PASS`/`FAIL` log to
`tests/out/screenshots.txt`.

The UI suites drive the real widgets the way a player does, still headless.
`tests/ui_driver.gd` (`UiDriver`) turns the 64x64 headless root into a
1280x800 logical surface and pushes synthetic mouse, wheel, trackpad-pan and
key events through the root at window-aware global coordinates, so clicks
land in the console and noise windows (embedded, headless), their dropdown popups and
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
