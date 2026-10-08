# Deep zoom: a march that survives small detail — design

Date: 2026-10-08

## Problem

Fly close to the fractal (the nearest surface within about a hundredth of a
unit, a few seconds of holding W) and fine detail falls apart: the surface
turns dark and speckled, dark pits open inside intricate areas, and the Ice
Fractal shading goes flat or scrambled. Nothing is "loaded" in this renderer
that could be reloaded finer: every pixel is recomputed from the formula each
frame. The breakdown is arithmetic, and it has three separate causes.

### 1. The coarse pass is blind to fine detail (the big one)

The shader marches each ray in two phases: 96 steps with a 16-iteration
distance estimate, then 32 steps at 32 iterations (`mandelbox.gdshader`,
`fragment()`). The 16-iteration estimate describes a slightly different,
smoother surface, offset from the real one by roughly one hundred-thousandth
of a unit (the Mandelbox gains a factor `|box_scale|` of detail per
iteration, so after 16 of them its features are about `2.09^-16` of the box).
The hit threshold is `precision × t`, and `t` is about the camera's distance
to the surface. Once the camera is closer than about 0.01, the threshold is
finer than the offset between the two surfaces: the coarse pass creeps toward
a surface it can never reach, spends all 96 steps, and the fine pass has 32
steps left to finish. The step count is the Ice Fractal colour (`ce`), so the
picture darkens, and rays that run out of budget are the dark pits.

This happens in exact arithmetic. It was measured with a Python copy of the
shader's march, 40 rays from the default view's surface, camera placed at
decreasing distances. "Dark" is a hit whose step count pushes `ce` past 0.6.

| camera distance | site scheme, float64 hits / dark | site scheme, float32 | all 128 steps at 32 iterations, float64 | same, float32 |
|---|---|---|---|---|
| 0.1 | 37 / 3 | 37 / 3 | 40 / 3 | 40 / 3 |
| 0.01 | 36 / 11 | 36 / 13 | 39 / 0 | 39 / 0 |
| 0.003 | 34 / 24 | 34 / 24 | 40 / 3 | 40 / 3 |
| 0.001 | 35 / 27 | 34 / 27 | 40 / 2 | 40 / 2 |
| 0.0003 | 37 / 31 | 36 / 31 | 40 / 2 | 40 / 3 |
| 0.0001 | 36 / 32 | 34 / 32 | 40 / 1 | 38 / 5 |
| 0.00001 | 33 / 32 | 32 / 32 | 40 / 1 | 29 / 5 |
| 0.000001 | 35 / 35 | 33 / 33 | 39 / 2 | 15 / 3 |

The coarse pass costs about two orders of magnitude of zoom before 32-bit
floats do.

### 2. 32-bit positions

The ray position is `eye + dir * t` in 32-bit floats (WebGL 2 has nothing
wider). Near the fractal, where the eye's coordinates are around 2, that sum
can only land on a grid about `1.2e-7` apart. Below a camera distance of
roughly `1e-4` the hit threshold is far finer than the grid, rays reach the
surface only by luck and otherwise creep inside it: speckle, shimmer, pits.
The right-hand columns above show it starting at `1e-4`. The fix for this
(a two-float camera for the first iterations) is a separate, later spec; this
one stops the camera at the floor instead.

### 3. The lighting probe has a fixed size

The Ice Fractal normal (`calc_nf`, colour modes 1 to 9 outside Julia mode)
samples the field 0.01 units from the hit point, a constant copied from the
site. At the default view that is about 3 pixels; at a camera distance of
0.001 it spans ten views' worth of geometry, so the shading is noise. It is
not a gradient (its baseline sample is at half the hit point, by design), so
shrinking the offset does not fix it: as the offset shrinks the three
differences converge to the same number and the normal collapses to one
fixed direction, which lights everything flat.

## Design

Three changes, all automatic, no new renderer option, no change to the save
format. Everything is bit-for-bit the site at the default view.

### A. Depth-aware coarse pass

The coarse pass's iteration count follows the camera's distance to the
nearest surface instead of being fixed at 16. It is the smallest count whose
surface sits within the coarse hit threshold of the real one:

```
coarse_iters(near) = clamp(ceil(ln(2 / (2 × eps × near)) / ln|box_scale|), 16, 32)
eps = precision / detail   (the value the shader's `precision` uniform holds)
```

The 2 in the numerator is the box's half-size: the measured constant that
reproduces the table (24 iterations at a distance of 0.001). `|box_scale| ≤ 1`
has no shrinking detail: 32. At the default view (`near ≈ 6.57`, the
estimator's own fixture for the default eye) the formula gives 12, clamped to
16, so the site look is unchanged; the count starts rising once the camera is
within about 0.3 of the surface and reaches 32 by about `3e-6`.

- `FractalParams.coarse_iters(near: float) -> int`, next to `hit_epsilon`,
  using the unshed detail: the still frame renders at level 0, and the load
  shedder's cheaper detail while moving already trades detail away.
- `FractalView._push_near()` pushes the new `coarse_iters` int uniform
  alongside `near_dist` (both depend on the camera and the shape). The
  shader's phase 1 calls `de(pos, coarse_iters)`; `de` already takes the
  count. The 3:1 split of the step budget is unchanged.
- `tests/shader_test.gd`'s `RENDERER_UNIFORMS` gains `coarse_iters`.
- `DistanceEstimator.estimate_at` gains an optional `iters` argument
  (default 32) so the CPU can mirror the coarse estimate.

### B. Zoom-following lighting

The shading normal crossfades from the Ice Fractal probe to the true normal
(`calc_normal`, whose offset already scales with the hit threshold) as the
camera closes in:

```
nf_weight = smoothstep(0.1, 2.0, near)
```

A new float uniform `nf_weight`, pushed from `_push_near()`. In the shader,
for the colour modes that use the probe: weight 1 computes only `calc_nf`
(bit-for-bit today), weight 0 only `calc_normal`, in between both and
`normalize(mix(true, nf, weight))`. The band's ends are constants in
`FractalParams` (`NF_FADE_NEAR`, `NF_FADE_FAR`); the default view, at
`near ≈ 6.6`, is well above the band. The true normal is what the Julia and
metal modes already use at every distance, so the close-up look is one the
app already has.

### D. Zoom guard

The fly camera refuses moves that would put the camera below the 32-bit
floor, and the console says so.

```
zoom_floor(eye) = ulp32(max(|eye.x|, |eye.y|, |eye.z|)) / (50 × eps)
ulp32(x) = 2^(floor(log2 x) − 23)      (the gap between neighbouring 32-bit floats near x)
```

The 50 comes from the table: hits start failing at a distance of `1e-4` with
`ulp32 ≈ 1.2e-7` and `eps = 2.5e-5`, which is `ulp32 / (48 × eps)`; the floor
sits at that distance with no margin, so the guard stops the camera right
where the picture would start to break. At the default precision near the
box that is about `1e-4`. A higher Detail setting makes the hit threshold
finer, so the 32-bit grid fails sooner and the floor moves further out;
Julia mode's larger box (bigger eye coordinates, coarser grid) also moves it
further out.

- `FractalParams.zoom_floor(eye: Vector3) -> float`, unshed detail as in A.
- `FlyCamera._physics_process`: compute the candidate position; accept it if
  the estimator's distance there is at least the floor, or at least the
  distance at the current position (moving away is always allowed, so a
  camera already past the floor, e.g. from a loaded save, can leave). Reject
  otherwise and set `at_zoom_limit = true` for that tick; it clears on the
  next accepted move or when no key is held. One extra CPU distance estimate
  per tick while moving. Speed is untouched: the speed already shrinks with
  the distance, so the last step before the floor is tiny and the stop is
  not a visible pop.
- `Main` forwards `at_zoom_limit` to the Movement pane each frame the way the
  shed level reaches it; the pane shows `zoom limit` on the readout line
  while it is set (same style as `load shed N/4`).
- Orbit camera: out of scope; it cannot approach the surface the same way.

## Not doing

- **Sub-chunk loading / substituting self-similar regions.** There is no
  stored geometry to load, and a Mandelbox with `c` following the point is
  not self-similar enough to stand in for its own detail (a separate note
  investigates the Julia-mode case, where it may be).
- **Two-float camera (option C).** Pushes the 32-bit floor down several
  orders of magnitude. Next spec, once A/B/D have been flown.
- **Supersampling the still frame.** The hit threshold is about 20× finer
  than a pixel at every distance, so sub-pixel detail aliases into sparkle
  even at normal distances. Separate concern, separate spec.

## Testing

Headless, in `tests/` (the project's TestCase style; nothing windowed).

- `fractal_params_test.gd`: `coarse_iters` is 16 at the default view, 24 at
  `1e-3`, 32 at `1e-6` and for `|box_scale| ≤ 1`; Detail 10 raises the count
  at a given distance; `zoom_floor` at the default eye and precision is
  within 20% of `1e-4` when the eye is near the box and scales with Detail.
- `deep_zoom_test.gd` (new): a CPU copy of the shader's two-phase march
  (96 coarse + 32 fine, `hit_epsilon`), run from the default view's surface
  point (found with `CenterRay.march`) with the camera backed off to
  `1e-3` and `1e-5`: with the fixed 16-iteration coarse pass the hit uses
  more than 60% of the budget or fails; with `coarse_iters(near)` it hits
  using under half. This is the table above as a regression test.
- `shader_test.gd`: the two new uniforms are declared; the shader compiles.
- `fly_camera_test.gd`: a camera placed just above the floor with W held
  stops at the floor and reports `at_zoom_limit`; moving away is accepted
  and clears it; a camera below the floor may move away but not closer.
- `console_test.gd` / `ui_console_test.gd`: the Movement pane shows
  `zoom limit` while the flag is set and clears it.
- `README.md`: the Renderer section describes the automatic coarse count,
  the shading crossfade and the zoom limit readout.

The windowed check (`tests/screenshots.sh`) is the user's to run; the default
view must be pixel-identical before and after.
