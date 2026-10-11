# Help I'm Stuck In A Fractal

A from-scratch Godot 4.6 Mandelbox viewer that emulates the renderer at
[icefractal.com/mandelbox/](https://icefractal.com/mandelbox/): the same default
view, the four shape sliders, the thirteen colour modes, the precision control,
Julia mode and an orbit camera. On top of the site it adds three more fractals
— a kaleidoscopic IFS (the Menger sponge, the Sierpinski tetrahedron and their
kin) and a pseudo-Kleinian limit set, ported from Fractacular, and the
Mandelbulb — and
cylinder, octahedral and abs-fold hybrid folds for the Mandelbox, a distance-scaled
free-fly camera, an adaptive-resolution governor that keeps the frame rate up
while you move, a **scene of shapes** (up to eight fractals, each with its own
knobs, position, rotation and size, so they can be nested inside one another;
see **Shapes and nesting**), and a **console** window — a collapsible Shape
panel per shape with every fractal knob and Fractacular's binding model, Light and Material tabs with
Fractacular's cosine-palette window, a tunable light with scattering and
shadows, and noise-driven texture and bump, and a Movement pane of
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

Tap **Ctrl** to open the **console**, a separate OS window: the **Shape** tab
(one collapsible panel per shape, with a row for every fractal and placement
knob), the **Light** and **Material** tabs, with a row for every light and
material knob, and the **View** tab (Save / Load level, the Camera mode, the
mouse sensitivity, the
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
tab) is the player's preference, not part of a level: it is kept in
`user://settings.cfg`, survives restarts, and loading a saved level does not
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

### Deep zoom

Three things adjust themselves as you fly close to the fractal. None has a
setting, and none changes a saved level; at the default view all three are off,
so the picture there is exactly the site's.

- **Coarse pass iterations.** Each ray marches in two phases: a cheap coarse
  pass, then 32 fine steps at full precision. The coarse pass normally runs 16
  Mandelbox iterations, which describe a slightly smoother surface than the
  real one (each iteration adds detail about 2× finer, so 16 of them leave the
  surface rough by about 2 / 2.09¹⁶ ≈ 1e-5). Once you are within about 0.3 of
  the surface the hit threshold gets finer than that gap, and the coarse pass
  would spend its whole budget creeping toward a surface it can never reach:
  the picture darkens and dark pits open. So the coarse count rises with your
  distance `d₀` to the nearest surface, to
  `ceil(log(2 / (2 × eps × d₀)) / log|scale|)` kept between 16 and 32
  (`eps = precision / detail`): 24 at `d₀ = 0.001`, 32 by about `3e-6`. The
  KIFS runs the same rule on its own Scale and the Mandelbulb on its Power (an
  iteration near its surface stretches by about the power); the Kleinian,
  which has no steady magnification per iteration, always marches its coarse
  pass at 32.
- **Lighting.** The Ice Fractal colour modes (1 to 9, on the Mandelbox outside Julia mode) light
  the surface with their own normal, which samples the formula 0.01 units from
  the hit point. Up close 0.01 spans far more than a pixel and that shading
  turns to noise, so between `d₀ = 2` and `d₀ = 0.1` it fades smoothly
  (a `smoothstep`, an S-shaped blend with no kink at either end) into the true
  surface normal, the one the Julia and metal modes already use.
- **Zoom limit.** The shader works out positions in 32-bit floats, which near
  a coordinate `x` can only land on a grid `ulp32(x) = 2^(floor(log2 x) − 23)`
  apart (about `1.2e-7` near the box). Once the hit threshold is much finer
  than that grid, rays reach the surface only by luck. The fly camera therefore
  will not go closer than `ulp32(largest |eye coordinate|) / (50 × eps)`,
  about `1e-4` near the box at the default precision; a higher Detail (a
  finer threshold) or Julia mode's larger coordinates stop it further out.
  While a move is being refused the console's Movement pane shows
  `zoom limit` beside the speed readout. Moving away is always allowed, so a
  saved level already past the limit can still leave.

### Load shedding

With Fast Controls on, the render scale is the first thing to give while you
move. Once it is at **Min resolution** and the frame rate is still under 24 fps,
the governor sheds quality a level at a time:

| level | distance fog (× d₀) | detail | step budget | shadow march | Fly speed |
|---|---|---|---|---|---|
| 0 | none | 100% | 100% | 48 steps | — |
| 1 | 400 | 75% | 100% | 24 steps | — |
| 2 | 150 | 55% | 75% | off | — |
| 3 | 60 | 40% | 50% | off | — |
| 4 | 40 | 35% | 50% | off | capped at 40% |

The shadow march (when Shadows is on) halves at level 1 and drops out from
level 2; scattering and bump cost no extra marches and stay at every level.

Rays stop at the fog distance, and the view fades into a tint of the current
colour mode on the way there. The thresholds are sticky: a shed needs 0.5 s
under 24 fps (and 1 s since the last change), a restore needs 2 s over 40 fps,
nothing changes in between, and a shed soon after a restore doubles the next
restore's wait (up to 16 s). A level coming off eases in over 18 frames
instead of snapping to full quality: the fog recedes, and when it is going
entirely it also thins, with the march no longer stopping at it, so the far
geometry fades in; the detail and step budget climb back alongside it. A level
going on snaps straight in. The level is kept while you are still, but the
still frame always renders at full quality (eased in over its first frames). The console's Movement pane shows
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
It will not fly closer to the surface than the 32-bit zoom limit (see
[Deep zoom](#deep-zoom)); the Movement pane shows `zoom limit` while it is
holding you there. The centre ray marches whichever fractal is drawn, in that
fractal's own bounds, and on the Kleinian it stops at the View distance just as
the picture does (anything further is a miss, so the cap applies).
`fly_camera_test` holds W at every fractal and fold option and checks no
frame's step jumps a surface.

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
separate OS window: the **Shape**, **Light**, **Material** and **View** tabs on top, taking the full
width and most of the height, and the **Movement** pane below them at its
natural height (drag the bar between them to share the height differently).
**⌘=** / **⌘−** (Ctrl elsewhere) zoom everything in the console, text and
controls, a step at a time from 50% to 200%, and **⌘0** resets; the window keeps
its size and the panes reflow. The zoom is remembered between runs.

**Shape tab.** An **Add shape** button and a read-only **Self-similar: yes /
no (reason)** line head the tab, over a list with one entry per shape in the
scene. Each entry is a header line — a **▾ / ▸** arrow that expands or
collapses its panel, the shape's editable name, and a **✕** that removes it
(the last shape cannot be removed) — above that shape's full control panel.
Clicking a header makes the shape the **active** one (its name turns blue):
the self-similarity line and the Julia marker follow it, and **Add shape**
makes a copy of its knobs (bindings aside) at a tenth of its size, centred in
front of the camera, and selects it. The self-similarity line says whether the
active shape is exactly self-similar, following the shape and
the noise graph live. On the Mandelbox that is Julia mode with the constant
fixed in x, y and z, an iteration that magnifies, no scale drift and no noise
displacement; the KIFS qualifies without a twist, the Kleinian always (both
without noise), the Mandelbulb never (its power map stretches some directions
more than others, so its deep copies are distorted). It is information only;
[docs/reference/self-similar-substitution.md](docs/reference/self-similar-substitution.md)
explains what it means for deep zoom. A panel has one row per knob of the
fractal that shape draws, grouped **Placement**, **Fractal**, that fractal's
own groups, then **Render**. Rows and headings of the fractals not chosen are
hidden.

- **Placement** — **Position x/y/z** (the shape's centre, in world
  coordinates; the sliders cover ±10 and the box takes any typed value, to six
  decimals), **Rotation x/y/z** (degrees about the world axes, applied x, then
  y, then z) and **Size** (world units per local unit, a log slider from 1e-4
  to 10). These are knobs like any other: bind a position to Time to set a
  shape drifting, a rotation to an axis to tumble it.
- **Fractal** — which fractal: **Mandelbox**, **KIFS**, **Kleinian** or
  **Mandelbulb**, and **W**, the fourth coordinate of the 4D sample point (0 is
  the 3D shape; hidden on the Mandelbulb, which is 3D). The camera stays where
  it is when the fractal changes.
- **Box** (Mandelbox) — Scale, Fold limit, Min radius, Fixed radius, Fold order
  (Box→Sphere or Sphere→Box), **Fold shape** (Box, Cylinder — the xy radius
  folded — or Octahedral — reflected through |x|+|y|+|z| ≤ Fold limit),
  **Hybrid mix** and **Hybrid every** (on every 1st, 2nd or 3rd iteration, morph
  the fold from the box fold toward the abs fold, KIFS's fold into the positive
  corner: 0 is off, 1 swaps it outright, and the shape grows through the middle
  of the range; bind the mix to sweep) and **Scale drift** (iteration i scales by
  Scale + drift × i).
- **Julia** — a master **Julia (all)** toggle and four per-component toggles,
  each revealing its **Constant** (the rows collapse until Julia is on). While
  Julia is on, a white ring marks the point in the view; drag it (with the mouse
  free) to move Constants x/y/z, which survives the next resolve.
- **Iteration rotation** (Mandelbox) — the six 4D plane angles applied inside
  every iteration (they change the fractal itself, not just the view).
- **KIFS** — Scale (3 with the Coordinate fold is the Menger sponge), **Fold set**
  (Coordinate: cube symmetry; Diagonal: the Sierpinski tetrahedron at scale 2;
  Polyfold: k-fold mirror symmetry in xy, with its **Polyfold k**), **Twist**
  (an xy turn growing with the iteration) and the 4D **Offset** the copies
  scale away from. Ported from Fractacular, with its diagonal fold fixed to
  actually fire and a mirror polyfold that a ray march can trust.
- **KIFS rotation** — R1 (before the fold) and R2 (after it), six 4D plane
  angles each.
- **Kleinian** — Knighty's pseudo-Kleinian: the fold **Box** (one half-width
  per axis), **Inversion radius**, 4D **Shift**, **Thickness** of the sheets, and
  **View distance**: the set fills space, so rays stop at this distance (10 by
  default) and the last third fades into the background.
- **Mandelbulb** — White and Nylander's triplex power: every iteration writes
  the point in spherical coordinates, raises the radius to the **Power** (8, the
  classic bulb) and multiplies both angles by it, then adds c. **Theta phase**
  and **Phi phase** add a turn to the polar angle and the azimuth each
  iteration (the lobes lean and swirl), and **Julia** swaps c for a fixed
  **Constant** x/y/z. The distance is the escape-time estimate
  0.5 · r · ln r / dr. The bulb lies within radius 2^(1/(Power − 1)) (about 1.1
  at power 8), so it marches in the usual cube of half-side 2; fly in to about
  2 from the origin to frame it.
- **Render** — the ray-march Precision (log slider).

**Light tab.** The one lamp every lit mode shares — **Light colour**, **Light
yaw** / **Light pitch** (swing the headlight about the view's up and right
axes), **Light size** (a point light at 0, a broad soft source above it),
**Ambient** / **Diffuse**, and **Shadows** (0 is off and casts no shadow ray;
only visible with the light swung off the headlight). Then **Scattering** —
**Density**, **Glow** and **Brightness** of a light-tinted distance haze
(analytic, no extra rays). Then **Picture** — **Exposure** and **Saturation**
on the final colour of every mode but Grayscale. The defaults are the site's,
so the picture is unchanged until one is moved.

**Material tab.** Fractacular's Colour window at the top of one scrolling list
(the twelve cosine-palette sliders, curves and strip), then rows grouped
**Colour** / **Surface** / **Texture** / **Palette**:

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
- **Surface** — **Surface colour**, **Roughness** (glassy with tight glints at
  low, matte at high; it replaces the old Shininess — the specular exponent is
  `2/roughness² − 2`, so the default 1/9 is the site's 160) and **Specular**
  (the glint strength). The defaults are the site's, so every mode looks exactly
  as before until one is moved; they apply to every mode but Grayscale.
- **Texture** — **Texture** and **Bump**, driven by the noise editor's Texture
  and Bump outputs: Texture recolours the surface, Bump tilts the normal for a
  fake relief. Nothing wired, nothing changes.
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
then press a key) and a remove button — plus **Add axis**, the clock readout and
the fly camera's speed factor beside a **Reset camera** button. The keys and
axes have no file of their own: they are saved inside the level (the View tab's
**Save level…**) and restored when a level is loaded. Key pairs push an axis at
its speed; a Shape row bound to that axis reads the value, so the row's gain is
the key's sensitivity.

**⌘S** (Ctrl+S elsewhere) saves the level over the current file without a panel;
with no current file it opens the Save panel.

**⌘P** (Ctrl+P elsewhere) copies a screenshot of the fractal, without any UI, to
the clipboard as a PNG. On Linux this needs `xclip`.

### View tab (console)

The console's View tab holds what is not a shape knob: a **Save level…** /
**Load level…** row with the current file's name and a status line, the
**Camera** mode (Fly / Orbit), the **mouse sensitivity**, a **Noise editor…**
button, the **Renderer** options (above, with Fast Controls and Reset camera)
and **Back to Menu**.

## Keys and axes

The virtual axes and their key pairs have no file of their own: they are saved
inside the level (the `axes` list below) and restored when a level is loaded.
Until a level is loaded the keymap is the shipped default — one **Axis A** on
**E** (positive) / **Q** (negative) at one unit per second. Keys are stored by
name (layout-independent), `""` meaning unbound, and each axis registers two
input actions, `axis_<id>_pos` and `axis_<id>_neg`.

## Shapes and nesting

The scene is a list of up to eight shapes, each a full fractal (Mandelbox,
KIFS, Kleinian or Mandelbulb) with its own knobs plus a **placement**: a world
point `p` is evaluated in a shape as `q = Rᵀ (p − position) / size` and the
shape's distance comes back as `d_local × size`. The picture is the union: at
every march step each shape's distance is taken in its own frame and the
smallest wins (a shape whose bounding cube is further away than the best so
far is skipped, so far-off shapes cost nothing). The hit shape's own
**Precision** stops the ray and its frame shades the pixel; the light, colour
mode, material and palette are the scene's, shared by every shape (the Light
and Material tabs). Flight speed is the distance to the nearest surface of
*any* shape, so inside a small shape you crawl at its scale and speed up as
you escape; the zoom floor, the deep-zoom coarse pass and the level of detail
are likewise the nearest shape's, at its scale.

**Nesting.** A shape an order of magnitude smaller than its parent fits in one
of the parent's cavities. Fly into a cavity, **Add shape** (a tenth-size copy
appears in front of you), tune its Position and Size, repeat. To start a run
inside the innermost shape, save with the camera there: a loaded level puts
the player back exactly. `saves/nestedEscape.json` is a ready-made three-level
nest (sizes 1, 0.04, 0.0016, each turned so no straight line leads out) with
the camera in the innermost pocket.

**Why it stays sharp at any size.** Everything the fold sees is O(1): the
shader never forms `eye + dir·t` in world space and subtracts a position (a
float32 cancellation that would lose a shape a thousandth the size), because
the CPU hands it each shape's frame already applied to the eye — `local_eye`,
computed in 64-bit, and the frame's axes — so a ray samples
`local_eye + Rᵀdir · t / size`. The camera's eye is itself kept in 64-bit
(`CameraState.set_eye` / `move_by`; `transform.origin` is its float32 mirror)
so a frame's travel inside a tiny shape is not rounded away, and a save writes
the eye with 15 significant digits. Two limits remain: the ray parameter `t`
is float32, so a surface further than about 1e7 × its own detail from the eye
is below resolution (never the case for a shape you can see), and the orbit
camera moves the eye through 32-bit transforms, so switch to Orbit only at
ordinary scales.

## The level save

There is one save file — the **level** — a small JSON file tagged
`"kind": "level"`, **version 4**. (`"kind": "sequence"` is reserved for the
level-sequence editor to come; a sequence file handed to the level loader is
refused by name, and so is an old stand-alone keymap file.)

- **`shapes`** — one entry per shape, in list order: its `label`, a
  `defaults` map (every per-shape catalogue id to its value, the fractal and
  the Placement ids among them) and a `bindings` map (only active bindings,
  each a source / gain / waveform / period). A file from before the fractal
  could be chosen has no `shape` id and loads as a Mandelbox.
- **`active`** — the index of the console's selected shape.
- **`look`** — the scene's light, colour, material and palette knobs, the same
  `defaults` / `bindings` shape as one shape entry.
- **`axes`** — the keymap: a list of `{id, label, speed, positive, negative,
  value}` entries. Loading a level replaces the keymap in hand with these,
  rebinding the input actions.
- **`fractal`** — the non-shape preferences: `fast_controls`, `camera_mode`
  (`"fly"`/`"orbit"`), `mouse_sensitivity` and the renderer options.
- **`camera`** — the eye (15 significant digits, so a camera inside a nested
  shape lands where it was), forward and up vectors and the speed factor. **Reset
  camera** (in the console's Movement pane and the View tab's Renderer options)
  puts the camera and speed factor back to these, as the current file was last
  loaded or saved; with no file current it goes to the starting view.
- **`noise`** — the noise graph, when one is wired (additive; see below).

Loading skips anything it does not recognise or cannot read, with a warning, and
leaves values a file does not mention as they are. Older levels still load: a
**version-3** file (one `shape` table over the whole catalogue) loads as a
one-shape scene at the identity placement, its light and material rows going
to the look table; a **version-2** file (whose `axes` is a dict of values by
id) applies those values onto the axes in hand and leaves the keys alone; a
**version-1** file (the old flat `fractal` section) has its keys mapped
(`scale`→`box_scale`, `inner_radius`→`min_radius`,
`outer_radius`→`fixed_radius`, `julia_enabled`→`julia_all`,
`julia_point`→the three Constants); all without a warning. Saving always
writes version 4. An exported build cannot write into the
project, so it saves to `user://saves/` instead.

| file | what it is |
|---|---|
| `saves/default.json` | the opening level |
| `saves/juliaIceField.json` | Julia mode at `(-0.23, 1.512, 1.892)`, Scale −2.29, Min 0, Fold 0.72, Fixed 0.29, Ice Fractal, precision 0.00002 |
| `saves/juliaIceTerraces.json` | Julia mode at `(-0.23, 1.512, 1.892)`, Scale −1.88, Min 0.49, Fold 0.81, Fixed 0.53, Ice Fractal, precision 0.0001 |
| `saves/noiseRidges.json` | the default Ice Fractal level with a noise field wired: value-noise ridges displacing the surface and tinting it blue (see **Noise fields**) |
| `saves/nestedEscape.json` | three default Mandelboxes nested through the same cavity (Outer 1 ⊃ Middle 0.04 ⊃ Inner 0.0016), the camera inside the innermost: escape all three (see **Shapes and nesting**) |

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
- **Texture** — a Vec3 (each channel clamped to 0…1) the surface colour is
  multiplied by, scaled by the Material tab's **Texture** row.
- **Bump** — a Float height whose across-surface slope tilts the normal for a
  fake relief (the surface does not move), scaled by the Material tab's **Bump**
  row.

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
| **Output** | **Output** — Displace, Tint, **Texture** and **Bump** inputs, Amplitude, Step scale, Tint colour and strength (one per graph). Texture multiplies the surface colour; Bump tilts the normal for a fake relief (the Material tab's Texture and Bump rows scale them). |

**Saving.** The graph is saved inside the level, as an additive `"noise"` key in
the same JSON file — a level without the key leaves the current field alone. The
graph has no file of its own; the editor's **New** button clears it back to the
default (Position and Output). Load **`saves/noiseRidges.json`** for a one-click
demo: value-noise ridges displacing and blue-tinting the default Ice Fractal
level.

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
each `tests/*_test.gd` headlessly; it exits non-zero if any test fails. The CPU
distance estimators (`DistanceEstimator`, `KifsEstimator`, `KleinianEstimator`,
`MandelbulbEstimator`) are pinned by captured fixtures, and `march_safety_test.gd` checks every
fractal and fold option is safe to sphere-trace: a full-step march never jumps
a surface that a quarter-step march finds. Because
the headless renderer produces no pixels, the actual render is verified by
`tests/screenshots.sh`, which launches Godot windowed **without stealing focus**
(via `open -g`), renders the default view, each colour mode, a
`console_bound_axis` frame (Axis A bound to the scale, required to differ from
the default), a `lighting_raked` frame (the light swung and broadened, also
required to differ) and the `nested_escape` level (required to differ from its
outer shape alone), and writes the results plus a `PASS`/`FAIL` log to
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

`deep_zoom_test.gd` replays the shader's two-phase march on the CPU from a
camera 1e-3 and 1e-5 short of the default view's surface: with the old fixed
16-iteration coarse pass the ray spends its whole budget or misses, with the
distance-following count it hits in under half.

The reference capture from the site lives at
**`docs/reference/icefractal-default.jpg`**. Put `screenshots/default_view.png`
next to it to eyeball the default view against the original — float32 and no
HiDPI mean the pixels differ, but the shape and the blue colour family should
match.

## Systems viz

`docs/viz/` is an in-browser, pannable, zoomable explainer of how the viewer
works: the architecture, one input to one frame, the distance estimator fold
by fold, every dial, the two-phase ray march, the colour modes, the two
normals, the cameras and the resolution governor, and the scene of shapes
with the tough calls behind nesting (`./viz.sh shape-nesting`, its second tab
the calls). Its live figures run
JavaScript ports of the shader and the GDScript (checked at load against the
24 distance-estimator fixtures), and every tooltip links the `file:line` it
describes at a pinned commit (the panes written before the scene of shapes
are pinned at the single-shape commit, where their lines are right).

```bash
./viz.sh                  # open it in your default browser
./viz.sh mandelbox/5      # straight to a tab (1-based)
node tools/viz/check.mjs --print --pane mandelbox   # every cited line exists at the pinned commit
```

It is a dependency-free static page that works from `file://`; the engine is
ported from the sibling project spellfactory. Extend or refresh it with the
`/visualize` skill (`.claude/skills/visualize/`). The links 404 until the
pinned commit is pushed.

## MCP server (agent control)

`mcp/` is an [MCP](https://modelcontextprotocol.io) server that lets an agent
fly through the fractal, look at it and draw on the screen. It speaks MCP over
stdio and relays each tool call to the **`McpBridge`** autoload
(`src/mcp/mcp_bridge.gd`), which listens on `127.0.0.1:9077`
(`FRACTAL_MCP_PORT` to change it) for newline-delimited JSON while the game runs.
The server is off in a web build and in headless runs.

```bash
cd mcp && npm install     # once
```

The repo's `.mcp.json` registers it as `fractal` for Claude Code in this folder.
Elsewhere: `claude mcp add fractal -- node /path/to/repo/mcp/server.mjs`.

| tool | what it does |
|---|---|
| `launch_game` | start the game straight into the explorer and wait for the bridge (see below) |
| `status`, `start_game` | where things stand; leave the title or pause menu |
| `get_camera`, `set_camera` | eye / look_at / forward / up, optionally animated (`duration`) |
| `move` | move in the camera's frame, in **surface units** by default (multiples of the distance to the nearest surface, so `forward: 0.5` always halves the gap at any zoom depth); `safe` stops short of walls |
| `rotate` | yaw (about +Z) / pitch / roll in degrees |
| `dive` | fly part of the way to the surface under a pixel and face it: repeat to zoom into a feature |
| `raycast`, `probe`, `project` | surface point + normal under a pixel; distance estimate at a point; pixel of a point |
| `get_shape`, `set_shape` | every Mandelbox knob with ranges and descriptions; set any of them by id |
| `list_views`, `load_view`, `save_view` | the JSON views in `saves/` |
| `screenshot` | the window as an image, after the full-quality still frame (`overlay: false` for the bare fractal) |
| `draw` | line, polygon, circle, text or labelled point, in **screen** pixels or **world** (fractal) coordinates that stay attached to the fractal as you fly |
| `clear_drawings`, `list_drawings` | remove one drawing by id, or all |
| `trail` | record the camera's path as a world-space line |
| `wait_for_message`, `say`, `chat_history` | the pilot chat (below) |

Traversal tools take `look: true` to return a screenshot of the new view with
the result. World drawings are drawn on top of the fractal (not occluded) and
clipped where they pass behind the camera.

**Pilot chat.** A translucent column down the right of the view holds the
conversation between you and the agent (`src/chat/`). **Enter** focuses its
input (WASD and the axis keys fall silent while you type), Enter sends, Escape
or a click on the view leaves it; clicks elsewhere on the column go through to
the view. The agent long-polls `wait_for_message`, acts, and answers with `say`;
the header shows whether an agent is listening, working, or absent. The MCP
server's `pilot` prompt starts that loop. The log lives in `McpBridge`, so it
survives Back to Menu.

It is built for voice input: a speech-to-text process talks straight to the
bridge socket with `chat_post {text, source: "voice"}` for a finished utterance
(shown tagged "(voice)") and `chat_draft {text}` for the live transcript, which
fills the input box as you speak.

**Phone.** `server/` takes this to a phone call: a Twilio number answered by
ConversationRelay, a server on Railway, and a link on your machine that posts
the caller's words with `chat_post` and speaks the agent's replies (it follows
the chat with `chat_watch`). See `server/README.md`.

**Launching from a Claude session.** `launch_game` runs `tools/launch.sh -- --play
--background-window`, the same way Spellgraft launches: the window is parked
off screen bar a 4 px always-on-top corner (a fully hidden macOS window draws no
frames; screenshots read the viewport, so they are still full size), and the
launcher hands focus back to whatever app had it every time Godot takes it.
Any game started from a Claude Code session (`CLAUDECODE=1`) parks itself the
same way (`src/session/session_launch.gd`); `-- --foreground-window` or
`FRACTAL_PLAY=1` gives a normal window, and `launch_game {foreground: true}`
opens one for a person to watch. `./run.sh` stays the launcher for people.

`node mcp/smoke.mjs` drives the real server end to end (launch, raycast, draw,
dive, trail, screenshots into `mcp/out/`).

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
