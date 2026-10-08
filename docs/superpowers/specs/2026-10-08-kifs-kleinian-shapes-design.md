# KIFS and Kleinian shapes, and three Mandelbox options — design

Port two of Fractacular's six techniques into this 3D raymarcher — the
kaleidoscopic IFS (KIFS) and the pseudo-Kleinian limit set — and add three
Mandelbox variations from Fractacular's `fractal-fields-reference.md`: a
cylinder or octahedral fold in place of the box fold, a KIFS-fold hybrid, and a
scale that drifts with the iteration. Newton, Lyapunov and the ℂ² quadratic map
are out of scope (no distance estimate that fits the sphere tracer).

Decisions taken with the user (2026-10-08): the shape switch is a catalogue row
at the top of the Shape tab; the Kleinian's render distance is a Kleinian knob;
the hybrid is a mix plus a period; one windowed screenshot batch at the end.

## Shape switch

A new ENUM catalogue row `shape` (label **Fractal**: Mandelbox 0, KIFS 1,
Kleinian 2, default Mandelbox) heads the Shape tab in its own **Fractal** group,
followed by `w` (moved out of Box: every shape is 4D) — so the console's Shape
tab is Fractal, Box, Julia, Iteration rotation, KIFS, KIFS rotation, Kleinian,
Render. Every Mandelbox, KIFS and Kleinian row carries a `show_when` on `shape`,
and the inspector hides a group heading whose rows are all hidden.

It is an ordinary resolved value: saved in the view's shape table (still
version 2), pushed as the `shape` uniform, read by FractalParams. A file
without `shape` (every save made before this) loads as Mandelbox, whatever is
showing.

## Catalogue

`ShapeCatalogue` (new) owns the full spec list, the group tooltips and the two
tab group lists; it concatenates `MandelboxShape.specs()` (Box, Julia,
Iteration rotation — Mandelbox only), `KifsShape.specs()`,
`KleinianShape.specs()` and the shared rows (Fractal, Render, Colour, Lighting,
Palette). Every call site of `MandelboxShape.specs()` / `group_tooltips()` /
`SHAPE_GROUPS` / `COLOUR_GROUPS` / `catalogue_ids()` moves to ShapeCatalogue.
Ids are shader uniform names and FractalParams fields, as now.

Order: shape, w | Box | Julia | Iteration rotation | KIFS | KIFS rotation |
Kleinian | precision | colour… palette (unchanged).

### Mandelbox additions (Box group)

| id | label | type | default | range |
|---|---|---|---|---|
| `fold_shape` | Fold shape | ENUM Box 0 / Cylinder 1 / Octahedral 2 | Box | |
| `hybrid_mix` | Hybrid mix | FLOAT | 0 | 0..1 |
| `hybrid_every` | Hybrid every | ENUM 1st 1 / 2nd 2 / 3rd 3 | 2 | |
| `scale_drift` | Scale drift | FLOAT | 0 | -0.1..0.1 (hard ±1) |

- **Cylinder**: radial fold of the xy pair, r' = clamp(r, -L, L)·2 − r applied
  along p.xy/r; z and w get the 1D box fold.
- **Octahedral**: d = |x|+|y|+|z|; if d > L reflect xyz across that face,
  p.xyz −= (2/3)(d − L)·s where s is the sign vector (sign 0 → +1); w gets the
  1D box fold.
- **Hybrid**: on iterations i with i mod hybrid_every == hybrid_every − 1 the
  fold result is mix(fold(p), menger(p), hybrid_mix), menger(p) = abs(p) then
  sort x ≥ y ≥ z. A convex mix of two 1-Lipschitz maps is 1-Lipschitz, so the
  running derivative is unchanged. hybrid_mix 0 skips it entirely.
- **Scale drift**: iteration i uses s_i = box_scale + scale_drift·i in both the
  scale and the derivative.

All four at their defaults reproduce today's Mandelbox bit-for-bit (guarded
branches), and the existing 30+ CPU fixtures still pass unchanged.

### KIFS (groups KIFS, KIFS rotation)

`kifs_scale` (3, 1.05..4, hard 1.01..6), `kifs_fold` (Coordinate / Diagonal /
Polyfold, default Coordinate), `kifs_poly_k` (FLOAT 5, 2..12 — rounded to an
int in the shader; FLOAT so it is bindable), `kifs_twist` (0, ±45°),
`kifs_offset_0..3` (1, 1, 1, 0; ±3), `kifs_rot1_xy..zw`, `kifs_rot2_xy..zw`
(degrees, ±180, wrap). Iteration from Fractacular's `kifs.gdshader`: rot1, abs,
fold set, rot2, twist·i in xy, p = s·p − (s−1)·offset, the Menger z-correction
for the coordinate fold, bailout at |p| > 1000 (squared 1e6).
Distance: coordinate fold — the 4D box distance to [-1,1]⁴ times s⁻ⁿ (crisp
Menger edges); diagonal and polyfold — |p|·s⁻ⁿ. The coarse/fine iteration
counts (16/32) are the Mandelbox's.

### Kleinian (group Kleinian)

`kleinian_box_0..3` (0.92436, 0.90756, 0.92436, 0.92436; 0.1..2),
`kleinian_radius` (1, 0.1..2: inversion k = radius²), `kleinian_shift_0..3`
(0; ±1), `kleinian_thickness` (0.01, 0..0.2), `kleinian_view_distance`
(10, 1..100, log). Iteration (Knighty's pseudo-Kleinian, 4D): box fold
clamp(p, −b, b)·2 − p, m = max(k/|p|², 1), p = p·m + shift, dr ·= m.
Distance: r = |p.xy|, max(r − thickness, |r·p.z|/|p|) / dr.

## Shader

`mandelbox.gdshader` keeps its name (the viz links into it) and gains
`#include`s of `res://src/fractal/kifs.gdshaderinc` and
`kleinian.gdshaderinc`, each holding its own uniforms and `kifs_de(vec4, int)` /
`kleinian_de(vec4, int)`. `de()` switches on `shape`; noise_displace is added
for every shape. The NOISE splice is untouched (it works on the main file's
code; includes resolve at compile).

Bounds, replacing the hard-coded `box_half` 2 / 20 in the view and the orbit
camera with one helper, `FractalParams.bound_half()`: Mandelbox 2 (20 in
Julia); KIFS max(2, 1.5·|offset|) (the attractor of p → s·p − (s−1)·offset under
isometric folds lies within |offset| of the origin; the margin covers the
rotations); Kleinian — no cube: rays
stop at `kleinian_view_distance` from the eye, and hits past two thirds of it
fade into the background colour (`view_fade`), so the corridors end in a soft
horizon rather than a hard edge.

The Ice Fractal "field normal" (calc_nf) is Mandelbox-only; KIFS and Kleinian
always use the true DE-gradient normal. `julia_enabled()` is false off the
Mandelbox, so the Julia marker hides.

## CPU estimator

`DistanceEstimator.estimate_at` dispatches on `params.shape`: the existing
Mandelbox core (extended with the four options), `KifsEstimator.estimate_at`
and `KleinianEstimator.estimate_at` — 64-bit scalar locals, mirroring the
shader at N = 32. Fly speed, the orbit camera and near_dist need no change.

## Tests

- distance_estimator_test: the existing fixtures unchanged; new fixtures for
  each Mandelbox option; kifs_estimator_test and kleinian_estimator_test with
  captured fixtures and invariants (Menger hole has positive distance; symmetry
  where the defaults are symmetric).
- A Lipschitz test for every shape and option: on seeded random pairs a, b in
  the bound, |DE(a) − DE(b)| ≤ |a − b|·(1 + 1e-3) + 1e-9.
- Catalogue, fractal_params, shader (uniform set = catalogue ids), inspector
  (hidden groups), workspace (a file without `shape` loads as Mandelbox) tests
  updated.
- One windowed screenshot batch (permission given): default KIFS, Sierpinski,
  polyfold, Kleinian, and the three Mandelbox options.
