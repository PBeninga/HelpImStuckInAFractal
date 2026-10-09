# Perturbation: zooming past the 32-bit floor — design

Date: 2026-10-09. Builds on
[the deep-zoom march spec](2026-10-08-deep-zoom-march-design.md) (its cause 2
and option C) and the measurements in
[the self-similar substitution note](../reference/self-similar-substitution.md).

## Problem

The fly camera stops at about `1e-4` from the surface (`FractalParams.zoom_floor`)
because the shader works out every ray position as `eye + dir × t` in 32-bit
floats. Near the box, where the eye's coordinates are around 2 to 8, those
floats sit on a grid about `1.2e-7` to `9.5e-7` apart; once the hit threshold
is much finer than the grid, rays reach the surface only by luck. The surface
has detail far below that (the default Mandelbox resolves to about `1e-15`
with 32 iterations), and nothing in the renderer can draw it.

The self-similar note measured three fixes. Mapping the camera through `k`
iterations (the "substitution") leaves seams by design. A two-float camera is
exact but costs about 7× per ray and depends on how a WebGL driver rounds.
**Perturbation** got 94–100% of rays right at `1e-5` to `1e-7` for every shape
at an estimated 1.5–2× per ray, in ordinary float arithmetic. This spec builds
perturbation.

### The idea in plain words

Run the camera's own orbit once per frame on the CPU, in 64-bit: `X_0` is the
eye, `X_1` its first iterate, and so on. Each pixel's starting point is the eye
plus a small offset `δ_0 = dir × t`. Instead of iterating the pixel's point
`P = X + δ` (whose 32-bit value has already lost the offset), the GPU iterates
**only the offset**: `δ_{i+1} = f(X_i + δ_i) − f(X_i)`. That difference is
small, so 32 bits hold it to plenty of relative precision, as long as the
formula never subtracts two nearly equal large numbers. Every step of the
iteration is either linear (rotation, scale, add a constant), where the
difference is just the same step applied to `δ`, or a fold, where the
difference depends on which side of the fold's crease `X` and `P` fall. For
the fold cases the CPU hands down the *gap*: the crease's position minus
`X_i`, computed in 64-bit. A gap is small exactly when precision matters, and
a 32-bit float holds a small number to the same relative precision as a large
one. This is how deep Mandelbrot-set zoomers work
([perturbation theory](https://en.wikipedia.org/wiki/Plotting_algorithms_for_the_Mandelbrot_set#Perturbation_theory_and_series_approximation)).

After `k` iterations the offset has grown by the magnification `λ_k`
(about `|scale|` per iteration, more with the sphere fold); once `λ_k × d`
reaches about `1e-2` the offset is big enough that `X_k + δ_k` in 32 bits is
as good as exact, and the GPU hands off to today's loop for the remaining
`32 − k` iterations.

## Scope

- Shapes: Mandelbox (box, hybrid and cylinder folds, sphere fold, iteration
  rotation, scale drift, Julia and Mandelbrot modes), KIFS (coordinate and
  diagonal fold sets, rotations, twist, offset, the Menger correction, bailout)
  and Kleinian (box fold, inversion, shift, fixed-point exit).
- **Not perturbed**, keeping today's floor: the Mandelbox's octahedral fold and
  the KIFS poly fold (many-region piecewise maps whose crossing cases are not
  worth enumerating now), and the Mandelbulb shape another branch is adding
  (follow-up spec). With these `pert_iters` is 0 and `zoom_floor` is today's.
- Noise displacement stays evaluated at the 32-bit position. A displaced
  surface is smooth below the displacement's size, so there is nothing to zoom
  into; the test and the readme say so.
- Orbit camera: out of scope (it cannot approach the surface).
- Iterations beyond 32 past the iteration floor: out of scope (follow-up).

## Design

Seven parts. Everything is automatic: no new renderer option, the save stays
version 2, and the default view is bit-for-bit the site's.

### 1. A 64-bit eye

`CameraState.transform` is a `Transform3D`, whose origin is 32-bit: near the
default eye (coordinate 8.2) it can only sit on a grid about `1e-6` apart, so
a move of `1e-7` rounds to nothing. Today's floor is already only ~100 eye
steps away.

- `CameraState` gains `@export var eye_x: float`, `eye_y`, `eye_z` (GDScript
  floats are 64-bit): the truth. `transform.origin` becomes the rounded
  shadow.
  - `set_eye64(x, y, z)`: sets the doubles, sets `transform.origin` to the
    rounded `Vector3`, emits `changed` when any double differs.
  - `eye64() -> PackedFloat64Array` (3 entries).
  - `eye()` keeps returning `transform.origin` (the rounded shadow) for every
    32-bit consumer: the `eye` uniform, `box_intersect`, the orbit camera, the
    probe, `project`/`unproject`.
  - The `transform` setter replaces the doubles only when the new origin
    differs from the rounded shadow `Vector3(eye_x, eye_y, eye_z)`. So
    `FlyCamera._set_forward`, which rebuilds the transform from `eye()`, is a
    no-op on the eye, while the orbit camera and `make_default` still set it.
  - `DEFAULT_EYE` unchanged; `make_default` goes through the setter.
- `FlyCamera._physics_process`: the step is added in 64-bit:
  `set_eye64(ex + dir.x × step, …)`. `dir` stays a unit `Vector3`; only the
  add needs the precision.
- `FlyCamera.move_allowed(from: PackedFloat64Array, to: PackedFloat64Array)`,
  `FractalParams.zoom_floor(eye: PackedFloat64Array)`,
  `CenterRay.march(ox, oy, oz, dir, params)` (scalar origin; the loop forms
  `o + dir × t` in doubles; the `Vector3` overload calls it): all in 64-bit.
  `DistanceEstimator.estimate(Vector3)` stays for the callers that do not
  care.
- `FlyCamera.base_speed`'s clamp floor drops from `1e-6` to `1e-14`
  (`SPEED_FLOOR`). The speed is about the distance to the surface, so below
  `1e-6` the camera would otherwise outrun its own stop.
- `Workspace.capture` writes `"eye"` from `eye64()` at full precision (no
  `_tidy`, which rounds to 7 significant figures; `forward` and `up` keep it).
  `restore` reads the three doubles and calls `set_eye64`, then sets the basis
  with `looking_at`. Version stays 2: an old file is the same shape with fewer
  digits; a new file loads in an old build with the eye rounded.

### 2. The reference orbit (CPU)

New `ReferenceOrbit` (`src/fractal/reference_orbit.gd`, `RefCounted`), built
from the 64-bit eye for the current shape:

```
var orbit := ReferenceOrbit.build(params, ex, ey, ez)
orbit.distance   # == DistanceEstimator.estimate_at(ex, ey, ez, params), exactly
orbit.n          # iterations run before a KIFS bailout or Kleinian fixed point (32 otherwise)
orbit.mag        # PackedFloat64Array, λ_0 .. λ_32 (λ_0 = 1): the magnification after i iterations
orbit.points     # PackedVector4Array, X_0 .. X_32 (32-bit copies; X_k is the handoff point)
orbit.a, .b, .c, .d   # PackedVector4Array of PERT_MAX entries each: the per-iteration record
orbit.perturbable     # false for the octahedral fold, the poly fold, and shapes without support
```

It reuses the estimators' static fold helpers (`DistanceEstimator._fold`,
`_sphere_fold`, `_rot_plane`, `menger_fold`, `KifsEstimator._diagonal_fold`,
…) so the fold maths is not duplicated; only the loop body is, and the
`distance` equality test keeps it honest. `λ_i` is the product of the scale
magnitudes and radial-fold factors through iteration `i` (the Mandelbox's
`dz` without its `+ 1`s; `|kifs_scale|^i`; the Kleinian's `dr`).

The per-iteration record, four `vec4`s per iteration, written for the GPU
(every value is what a 32-bit float can hold precisely: a small gap, or a
multiplier that only needs relative precision):

| shape | `a` | `b` | `c` | `d` |
|---|---|---|---|---|
| Mandelbox | lower-crease gaps `lo − X` per component | upper gaps `hi − X` | the sphere fold's input point | (`\|Xs\|² − min_radius²`, `\|Xs\|² − fixed_radius²`, the reference's sphere factor `m`, the cylinder fold's radial gap `r_xy − fold_limit`) |
| KIFS | abs-fold gaps `−X` (after R1) | the three sort gaps (`X_x − X_y`, then `X_x − X_z`, `X_y − X_z`, each from the state at that comparison), or the four diagonal gaps `X_a + X_b` | `.x`: the Menger-correction gap `X_z + t/2` after the scale | unused |
| Kleinian | box gaps `−b − X` | `b − X` | the post-fold point | (`\|Xs\|² − radius²`, the reference's factor `m`, 0, 0) |

For the Mandelbox the clamp gaps use the fold's own interval: `±fold_limit`
for the box fold and for the cylinder fold's z and w components, or the
hybrid interval `[lo, hi]` on a hybrid iteration (the cylinder fold's xy
pair uses the radial gap in `d.w` instead; the octahedral fold is not
perturbed). With `fold_order` 1 (sphere first) the sphere gaps are of the
pre-fold point and the clamp gaps of the post-sphere point; the record's `c`
is always the sphere fold's input, and the GPU recovers whatever else it
needs from `c`, `m` and the radial gap (the cylinder fold's pre-fold xy is
`c.xy` scaled back by `(L + gap_r) / (L − gap_r)` in fold order 0, or `c.xy
× m` in fold order 1).

### 3. The perturbed step (GPU)

New uniforms: `int pert_iters` (0 = off), `vec4 pert_a[PERT_MAX]`,
`pert_b`, `pert_c`, `pert_d` (`PERT_MAX = 20`), `vec4 pert_end` (`X_k`).
Uniform arrays compile in a `canvas_item` shader under GL Compatibility and
take a `PackedVector4Array` (checked headless on 4.6.1). 80 `vec4`s plus the
existing ~110 scalars stay well inside WebGL 2's 224-vector minimum.

`float de_pert(vec3 off, int iters)`, where `off = dir × t` (the shader never
forms `eye + off` on this path): run `min(pert_iters, iters)` perturbed
iterations on `δ` (a `vec4`, `δ.w = 0`), then `z = pert_end + δ`, `dz` as
accumulated, and continue with the existing loop body from iteration `k` to
`iters`. To share that body, each shape's loop moves into a function taking a
start index (`mb_orbit(z, dz, c, first, iters)` and the like); the direct
path calls it with `first = 0`, which is the same arithmetic in the same
order, so the default view stays bit-for-bit (the user's screenshot check
confirms).

The difference formulas, per step kind. `X` is the reference's point at that
step (from the record), `P = X + δ` the pixel's.

- **Clamp folds** (box, hybrid, Kleinian box, KIFS abs with `hi = +∞`), per
  component with gaps `g_lo = lo − X`, `g_hi = hi − X`:
  `δ' = 2 × (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ`.
  One formula covers all nine side pairs (checked: inside→inside gives `δ`,
  inside→above `2 g_hi − δ`, above→inside `δ − 2 g_hi`, above→above `−δ`,
  …). Both clamps are of small numbers.
- **Radial folds** (sphere fold, Kleinian inversion, cylinder fold on xy):
  `δ' = m' δ + X (m' − m)`, where `q = 2 X·δ + δ·δ` is `|P|² − |X|²` (no
  cancellation: every term is a product), the pixel's regime is decided by
  `g + q` against 0 for each gap `g` (`|X|² − min_radius²`, `|X|² −
  fixed_radius²`, `|X|² − radius²`, or for the cylinder `r − L` against
  `(r' − r) = q_xy / (r' + r)`), `m'` is the pixel's own factor, and
  `m' − m` is written per regime pair so that it is a small precise number
  over a product, never a difference of two factors: shell→shell
  `−fixed² q / (|P|² |X|²)`; inside→shell `−fixed² (g_min + q) / (|P|² min²)`;
  shell→inside `fixed² g_min / (min² |X|²)`; shell→outside `g_fix / |X|²`;
  outside→shell `−(g_fix + q) / |P|²`; same regime, constant factor: 0;
  inside↔outside (a huge `δ`): the constant difference. The cylinder fold is
  the same template with `m = (2L − r)/r`. The pixel's `dz` (or `dr`)
  multiplies by `m'`, as the direct path's does.
- **Sorts and diagonal swaps** (KIFS): the pixel swaps when
  `δ_a − δ_b < −gap` (sort) or `δ_a + δ_b < −gap` (diagonal). Both or neither
  swap: `δ` swapped or not. Only the pixel swaps (sort): `δ'_a = δ_b − gap`,
  `δ'_b = δ_a + gap`; only the reference: `δ'_a = δ_b + gap`, `δ'_b = δ_a −
  gap`; diagonal: `δ'_a = −gap − δ_b`, `δ'_b = −gap − δ_a` (and the mirror
  case with `+gap`).
- **Menger correction** (KIFS): `δ'_z = δ_z + t × ([P crosses] − [X
  crosses])`, crossing decided by `δ_z` against the gap.
- **Rotations, twist, scale, offset**: linear. The existing shader functions
  (`mb_iter_rotate`, `kifs_rot1/2`, `mb_rot_plane`) run on `δ`; the scale is
  `δ' = s δ` (the KIFS `−(s − 1) o` and the Kleinian shift cancel).
- **The add** (Mandelbox): `δ' = s δ + δc`, with `δc = off` masked by the
  Julia flags per component (`δc.w = 0`): in Mandelbrot mode the pixel's own
  `c` differs from the reference's by exactly its starting offset.
- **KIFS bailout and Kleinian fixed point**: the CPU caps `pert_iters` at
  `orbit.n`; a pixel that bails out earlier (`|X_i + δ_i|² > 1e6`, a large
  number, fine in 32 bits) hands off there.

`fragment()`: when `pert_iters > 0` both passes call `de_pert(dir × total,
n)` and the normal is `calc_normal_pert(off, delta)`, sampling `de_pert(off ±
e)`; `v = eye + dir × total` is still formed in 32 bits for everything that
only needs it roughly (Rainbow's radius, the probe dot, fog, the noise tint,
`noise_displace`). When `pert_iters == 0` the shader runs exactly today's
code.

### 4. When, and how many iterations

```
PERT_MAX     = 20      # uniform array length; k never exceeds it
PERT_ON      = 10.0    # switch on at 10 × today's floor, where both paths still agree
PERT_HANDOFF = 1e-2    # hand off once λ_k × near reaches this (the note's rule)

pert_iters(orbit, near):
    0 if not orbit.perturbable or near >= PERT_ON × floor32(eye)   # floor32 = today's zoom_floor formula
    else the smallest k in 1..min(PERT_MAX, orbit.n) with orbit.mag[k] × near >= PERT_HANDOFF,
         or min(PERT_MAX, orbit.n) if none reaches it
```

Switching on an order of magnitude before the 32-bit path breaks means the
two paths agree within the hit threshold at the switch, so there is no pop.

`FractalView._push_near()` builds the orbit from `eye64()` (its `distance` is
`near`, so the estimate is not computed twice), pushes `near_dist`,
`coarse_iters`, `nf_weight` as today, plus `pert_iters`; when it is positive,
the four arrays and `pert_end = orbit.points[k]`. The arrays are pushed only
while on (a still frame at depth pushes once).

### 5. The zoom guard, moved

`FractalParams.zoom_floor(eye64)` becomes `max(floor_pert, floor_iter)`,
computed from a `ReferenceOrbit` at `eye`:

- `floor_pert = ulp32(max |X_K|) / (ZOOM_FLOOR_DIVISOR × eps × λ_K)`, with
  `K = min(PERT_MAX, orbit.n)`: today's formula applied at the handoff point,
  where the view is `λ_K` times bigger. About `1e-11` for the default box.
- `floor_iter = bound_half / (eps × λ_32)`: where 32 iterations stop
  resolving. Inside the shape the estimate `|z_32| / dz_32` cannot fall below
  about `bound_half / λ_32` (the orbit stays bounded, the derivative does
  not), and a ray only hits where the estimate is under `eps × t`, so the
  camera needs `t > bound_half / (eps × λ_32)`. This is an estimate; its
  test measures where a 64-bit march actually stops hitting rather than
  pinning a number. The note's figures put the terraces save at about `5e-6`
  and the default box far lower.
- Shapes that are not perturbable keep today's formula.

`FlyCamera.move_allowed` is unchanged in shape (accept if `d_to >= floor(to)`
or `d_to >= d_from`), now in 64-bit. The Movement pane's `zoom limit` readout
stays; its tooltip says the limit is now where 32 iterations run out of
detail or the perturbed march runs out of precision.

### 6. Console

The Movement pane shows `deep k=14` on the speed line while `pert_iters > 0`
(`MovementPane.show_deep(k)`, `k = 0` hides it), forwarded by `Main._process`
from `FractalView.pert_iters()` the way `at_zoom_limit` is. Nothing else in
the console changes; the Shape tab's Self-similar line stays as a description.

### 7. The `deep-zoom` viz pane

A new pane (`docs/viz/panes/deep-zoom.js`), written with the `/visualize`
skill after the code lands (its `file:line` links pin a commit). Ten tabs:

1. **Architecture** (graph): zones *64-bit CPU* (CameraState eye64, FlyCamera,
   CenterRay, ReferenceOrbit, Workspace), *the bridge* (the uniforms:
   `pert_iters`, `pert_a..d`, `pert_end`, `near_dist`, `coarse_iters`,
   `nf_weight`), *float32 GPU* (`fragment`, `de` / `de_pert`, the normals).
2. **Why 32-bit breaks** (live figure): a log slider for the camera distance
   `d`; the float32 grid near the eye, the view's width in grid steps, the hit
   threshold, and the same view after `k` perturbed iterations (`λ_k × d`).
3. **One frame at depth** (seq): camera `changed` → `_push_near` →
   `ReferenceOrbit.build` → `pert_iters` → `set_shader_parameter` →
   `fragment`: `box_intersect`, coarse loop, fine loop, normal, shade.
4. **The reference orbit** (live figure): the eye's 32 iterates, `λ_i`, and
   the hoverable per-iteration record, per save.
5. **δ step by step** (stepper): one pixel's offset through the iterations,
   the frame read beside the frame written, Step / Back / Reset, each stage
   with its shader and GDScript lines, and three columns: 64-bit exact,
   float32 perturbed, float32 direct (`Math.fround` for the 32-bit columns),
   crossings flagged. A port of the shader's `pert_*` functions.
6. **Crossing a fold** (figure): the clamp-difference formula on a draggable
   axis (`X`, `δ`, the two creases, the 3×3 case table lighting up), and the
   radial fold's three regimes with the `m' − m` formula per pair.
7. **Handoff and floors** (live figure + table): `λ_k` against `k` per save
   on a log axis with the `1e-2` line and the chosen `k` for a slider'd `d`;
   today's floor, `floor_pert`, `floor_iter` per save, computed by the port.
8. **Measured** (table): the agreement numbers from `perturbation_test.gd`.
9. **Coarse pass and lighting** (live figure): `coarse_iters(near)` and
   `nf_weight(near)` against `d` on a log axis, with the formulas (the
   existing rules, which have no tab of their own).
10. **Cards**: invariants (default view bit-for-bit; `pert_iters == 0` is
    today's path; `eye()` is the rounded shadow), gotchas (`Vector3` is
    32-bit; `_tidy`; the speed clamp; the WebGL uniform budget; folds that
    keep the old floor; noise at 32-bit), history (the substitution note, the
    two-float option), open (poly and octahedral folds, Mandelbulb, more than
    32 iterations, orbit camera).

Glossary entries to add: perturbation, reference orbit, catastrophic
cancellation, magnification, piecewise-linear map, double-float (two-float).

A second, smaller pane, `perturbation-design`, explains this document itself
(the problem, the three approaches and their trade-offs, the seven parts, what
is decided and why) and is written now, before the code, pinned to the spec's
commit; it links spec lines rather than code.

## Testing

Headless, `tests/` TestCase style, nothing windowed.

- `perturbation_test.gd` (new, the keystone): a GDScript port of the
  perturbed step and of the direct step, both run in **emulated float32**
  (every arithmetic result rounded through a `PackedFloat32Array`, as the note
  did with numpy), plus the 64-bit reference. For each shape fixture (the
  default Mandelbox, the ice-field and terraces saves in Julia mode, a KIFS
  and a Kleinian default), a `SurfaceFixture`-style surface point, a camera
  backed off by `d ∈ {1e-5, 1e-6, 1e-7}`, and 27 rays (a 3 × 3 × 3 fan of
  directions within the field of view). Agreement as in the note: same class
  (hit / beyond / no hit) and, for hits, distance within 0.1%. Checks: the
  direct float32 march agrees on under 30% at `1e-6` (today's failure), the
  perturbed march on at least 90% at every depth, and the perturbed step in
  64-bit reproduces the reference exactly (the algebra check). Prints the
  table for the viz's Measured tab. This runs before any shader work and
  proves the formulas.
- `reference_orbit_test.gd`: `distance` equals `DistanceEstimator.estimate_at`
  exactly for every shape fixture; `mag` is non-decreasing; `n` is 32 for the
  Mandelbox and under 32 for a KIFS point that bails out; `perturbable` is
  false for the octahedral and poly folds.
- `camera_state_test.gd`: `set_eye64` round-trips `1e-12` and emits
  `changed`; assigning a transform whose origin is the rounded shadow keeps
  the doubles; a new origin replaces them; `make_default` is unchanged.
- `workspace_test.gd`: a capture with an eye `1e-9` from a surface point
  restores it exactly; `saves/default.json` loads to the same camera as before.
- `fractal_params_test.gd`: `pert_iters` is 0 at the default view and at
  `1e-3`, positive at `1e-5`, rising as `d` falls, never above 20;
  `zoom_floor` at the surface fixture is below `1e-8` for the default box;
  `floor_iter`'s prediction brackets the measured stop (a 64-bit march from
  `10 × floor_iter` hits, from `floor_iter / 10` it does not).
- `fly_camera_test.gd`: a camera at `1e-6` with W held moves closer (refused
  today) and stops at the new floor with `at_zoom_limit`; the eye moves by
  less than `1e-9` per tick there (the speed follows the distance).
- `center_ray_test.gd`: the scalar march agrees with the `Vector3` one at
  the default view and resolves a hit at `1e-8` that the `Vector3` one cannot.
- `fractal_view_test.gd`: at the default view `pert_iters` is 0 and no array
  is pushed; at a deep camera `pert_iters` is positive and `pert_a` has
  `PERT_MAX` entries.
- `shader_test.gd`: `RENDERER_UNIFORMS` gains `pert_iters`, `pert_a`,
  `pert_b`, `pert_c`, `pert_d`, `pert_end`; the shader compiles.
- `console_test.gd` / `ui_console_test.gd` / `main_test.gd`: the `deep k=N`
  readout shows with `k`, hides at 0.
- `deep_zoom_test.gd`: unchanged.
- `README.md`: the Deep zoom section describes the 64-bit eye, the reference
  orbit, the handoff and the two floors; the zoom-limit paragraph is rewritten.

The windowed check (`tests/screenshots.sh`) is the user's: the default view
must be pixel-identical before and after, and a flight to `1e-8` on the
default box must show detail, not speckle.
