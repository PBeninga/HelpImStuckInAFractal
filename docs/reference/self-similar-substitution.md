# Self-similar substitution for deep zoom: a research note

Date: 2026-10-08. Status: investigation only. Nothing renders differently; the
console's Shape tab gained a read-only **Self-similar** line (below).

Related: [the deep-zoom march spec](../superpowers/specs/2026-10-08-deep-zoom-march-design.md),
whose cause 2 (32-bit ray positions) is the problem this note is about.

## The question

> Can we render deep zooms by substituting self-similar portions of the
> fractal, if the shape is self-similar enough? Flag in the debug console which
> shapes qualify.

## The answer, short

- **The self-similarity is real, but only in Julia mode.** With the Julia
  constant `c` fixed in x, y and z, one iteration maps the shape onto itself, so
  the structure around a deep point *is* the structure around its next iterate,
  magnified by about `|scale|` (exactly a magnified, rotated or mirrored copy:
  measured stretch ratio 1.00). In the default Mandelbrot mode (`c` follows the
  point) it is not: the deep structure is a *stretched* copy (stretch ratios 2.3
  to 6.2 measured) of a *different* shape, and treating it as a copy of itself
  gets 0 to 17% of rays right.
- **Substituting does fix the precision, but not well enough.** Mapping the
  camera through `k` iterations in float64 on the CPU and rendering from the
  image camera takes a deep view from 0–23% of rays correct (today's float32
  march) to 68–100% at the best `k`. The remaining rays are wrong because one
  straight-line camera map cannot follow the folds where a fold's crease crosses
  the view, and the range of `k` that is both precise enough and straight enough
  is only one or two values wide.
- **Self-similarity turns out not to matter.** The same trick works just as well
  in Mandelbrot mode, provided the GPU keeps adding the pixel's own position as
  `c`. What limits it is the folds, not the shape's symmetry.
- **Recommendation: do not build the substitution.** Build the spec's option C
  (exact per-pixel precision for the first iterations) instead, preferably as
  *perturbation* against a float64 reference orbit computed on the CPU. In the
  same experiment that gets 94–100% of rays right at `k` = 16 to 20 for every
  shape, at an estimated 1.5 to 2 times today's per-ray cost at depth, against
  about 7 times for a two-float camera.

The console flag answers the question as asked (which shapes are exactly
self-similar), and this note explains why the answer should not steer the
renderer.

## Background in plain words

**One iteration.** Every pixel runs the same step 32 times on a 4D point `z`:
`z → scale × fold(z) + c`. The box fold reflects each coordinate that leaves
`±fold_limit` back inside (a mirror). The sphere fold blows up points near the
centre: inside `min_radius` by a constant factor, between `min_radius` and
`fixed_radius` by an [inversion](https://en.wikipedia.org/wiki/Inversive_geometry)
(`z → z × fixed² / |z|²`). Then everything is scaled and `c` is added. In
**Mandelbrot mode** `c` is the pixel's own starting point; in **Julia mode** it
is one fixed constant for every pixel. See
[Mandelbox](https://en.wikipedia.org/wiki/Mandelbox) and
[Julia set](https://en.wikipedia.org/wiki/Julia_set).

**Self-similar** ([Wikipedia](https://en.wikipedia.org/wiki/Self-similarity))
here means: a small piece of the shape is an exact, magnified copy of a bigger
piece of the same shape. In Julia mode that is guaranteed: if a point belongs to
the shape, so does its next iterate, and one iteration magnifies everything
nearby by about `|scale|` (times the sphere fold's factor). So zooming in on a
point by `|scale|` shows the same thing as looking, unzoomed, at its iterate.

**Locally a copy.** Mirrors, uniform scaling, rotation and adding a constant
move a small neighbourhood rigidly and scale it evenly. The inversion is not
linear, but over a small enough neighbourhood it also acts as an even scale plus
a mirror (it is [conformal](https://en.wikipedia.org/wiki/Conformal_map):
angles are kept). So `k` iterations act on a small neighbourhood like
"move, mirror/rotate, magnify by `λ_k`". `λ_k`, the magnification after `k`
iterations, is what the shader already accumulates as `dz`. Replacing a curved
map by its straight-line approximation over a small region is called
[linearisation](https://en.wikipedia.org/wiki/Linearization); the straight-line
map is the [Jacobian](https://en.wikipedia.org/wiki/Jacobian_matrix_and_determinant)
(the 4×3 table of how each output coordinate changes with each input
coordinate).

**Why it might help.** The problem in the deep-zoom spec is that the shader
computes the ray position `eye + dir × t` in 32-bit floats, whose spacing near a
coordinate of 2 is about `1.2e-7`
([unit in the last place](https://en.wikipedia.org/wiki/Unit_in_the_last_place)).
At a camera distance of `1e-6` the whole view is only about 8 grid steps wide.
After `k` iterations the same view is `λ_k` times bigger (`λ_8` is around
1000), but the grid of 32-bit numbers is no finer, so detail that was lost in
the rounding at the start is resolved. The substitution does those first `k`
iterations once per frame in float64 on the CPU, for the camera only, and hands
the GPU the **image camera**: where the eye, and the right/up/forward
directions, land after `k` iterations. The GPU then marches from there with
`32 − k` iterations. This is what `|z| / |dz|` already does per ray; the only
gain is precision, and the price is the straight-line approximation over the
whole view.

## How it was measured

A Python copy of the shader's estimator (`mb_step`, `de`; box then sphere fold,
4D, iteration rotation, the shader's `dz` including its `+1`), run either in
float64 or in emulated float32 (numpy's 32-bit floats, every operation rounded,
as a GPU would).

- **Views.** For each shape, three surface points with visible structure were
  found by marching from the opening camera to within `1e-12` of the surface.
  A deep camera was placed a distance `d` back along that ray, looking at the
  point, 40° field of view, and 81 rays (a 9 × 9 grid over the frame) were
  marched from it: 243 rays per row in the tables.
- **Reference.** Each ray marched in float64 with 32 iterations at every step,
  stopping when the estimate falls below `precision × t` (the shader's fine-pass
  test, default detail). Rays that go past `10 d` are recorded as "beyond"
  (the region a camera map has to cover), and runs out of steps as "no hit".
- **Agreement.** A ray agrees when it lands in the same class as the reference
  and, for hits, at a distance within 0.1% of the reference (about one pixel's
  depth footprint: a pixel of an 800-pixel-high 40° view spans
  `2 tan 20° / 800 ≈ 0.09%` of its distance).
- **Substitution.** The CPU iterates the eye `k` times in float64, also
  carrying the Jacobian. The image ray is `z_k(eye) + J × dir × t`, with `t`
  still in original units, and the GPU's `dz` starts at the eye's `dz_k`, so
  distances come out already divided by the magnification and the hit test is
  unchanged.
- **Shapes.** Julia mode with the default box; Julia mode with the saved
  *ice field* shape (`min_radius` 0, so pure inversion near the centre); the
  ice field with iteration rotation (5° xy, 3° xw, which tilts the view into
  the fourth dimension); the ice field with only x, y, z fixed and `W` 0.3; the
  default Mandelbox (Mandelbrot mode); and the default box with only Julia x on.

Not covered: noise fields (only the GPU evaluates them), colour, and
`fold_order` Sphere → Box (the same argument applies; not run).

## Results

### 1. In Julia mode the deep region is a magnified copy (float64, no rounding)

Percentage of rays that agree with the reference when the first `k`
iterations are replaced by the camera map, everything else exact. This
isolates the straight-line approximation.

Julia, default box (magnification at `d = 1e-6`: `λ_4` = 19, `λ_8` = 364,
`λ_12` = 53 000):

| camera distance d | k = 4 | k = 8 | k = 12 | k = 16 | k = 20 |
|---|---|---|---|---|---|
| 1e-3 | 67% | 64% | 0% | 0% | 0% |
| 1e-4 | 73% | 67% | 8% | 14% | 14% |
| 1e-5 | 93% | 93% | 3% | 4% | 4% |
| 1e-6 | 100% | 100% | 30% | 0% | 0% |
| 1e-7 | 100% | 100% | 68% | 13% | 12% |

Julia ice field + rotation (`λ_8` = 756, `λ_12` = 21 000, `λ_16` = 570 000):

| camera distance d | k = 4 | k = 8 | k = 12 | k = 16 | k = 20 |
|---|---|---|---|---|---|
| 1e-3 | 100% | 58% | 6% | 6% | 6% |
| 1e-4 | 100% | 89% | 23% | 14% | 14% |
| 1e-5 | 100% | 99% | 85% | 7% | 6% |
| 1e-6 | 100% | 100% | 98% | 69% | 9% |
| 1e-7 | 100% | 100% | 100% | 90% | 56% |

Julia ice field, as saved (`min_radius` 0: pure inversion near the centre):

| camera distance d | k = 4 | k = 8 | k = 12 | k = 16 | k = 20 |
|---|---|---|---|---|---|
| 1e-3 | 34% | 10% | 2% | 2% | 2% |
| 1e-4 | 46% | 46% | 6% | 5% | 5% |
| 1e-5 | 75% | 75% | 29% | 12% | 10% |
| 1e-6 | 96% | 96% | 61% | 42% | 9% |
| 1e-7 | 99% | 99% | 72% | 72% | 7% |

The hypothesis holds: where the map is accurate, it is accurate to a few parts
in a billion (median relative error `1e-9` to `1e-11`), and the Jacobian is an
even magnification (largest stretch / smallest stretch = 1.00 in every Julia
case). Iteration rotation, including rotation into the fourth dimension, and a
`W` that is not 0 change nothing, as long as the image camera is 4D (the image
of the 3D view is a tilted 3D slice of 4D space).

It breaks once the view's image reaches about a hundredth to a tenth of the
distance to the nearest fold crease, roughly when `λ_k × d` passes `1e-3` to
`1e-2`: a mirror plane, a sphere, or (for `min_radius` 0) the inversion's
centre falls inside the view, and the single straight-line map is right on one
side and a mirror image on the other. Where the camera is matters: the ice
field's inversion centre makes it break much earlier than the same shape with
rotation, whose views happened to sit away from it.

### 2. In Mandelbrot mode it is not a copy of itself, but the trick still works

Float64, default Mandelbox, three ways to treat `c` in the image:

- **as if Julia**: the camera map ignores that `c` moves with the point, and
  the GPU adds the eye's `c` to every pixel;
- **c frozen**: the camera map includes `c`'s movement, the GPU adds the eye's
  `c` to every pixel;
- **c follows**: the camera map includes it and the GPU adds each pixel's own
  original position, `eye + dir × t`, computed in 32-bit.

| d | treatment | k = 4 | k = 8 | k = 12 | k = 16 | k = 20 |
|---|---|---|---|---|---|---|
| 1e-6 | as if Julia | 0% | 0% | 0% | 6% | 14% |
| 1e-6 | c frozen | 17% | 55% | 88% | 53% | 16% |
| 1e-6 | c follows | 100% | 90% | 90% | 53% | 16% |
| 1e-7 | as if Julia | 1% | 1% | 1% | 1% | 7% |
| 1e-7 | c frozen | 16% | 50% | 93% | 65% | 9% |
| 1e-7 | c follows | 100% | 97% | 97% | 65% | 9% |

(The default box with only Julia x on behaves the same: 0–17% as if Julia, up
to 100% with c following.)

- **As if Julia fails**, as the starting hypothesis said: each iteration adds a
  copy of the point's own movement, a correction of relative size about
  `1 / |scale|` per iteration, so the camera map is off by tens of percent.
- **c frozen improves as `k` grows**: freezing `c` across the view is an error
  of the view's size, against image structure `λ_k` times bigger, so its
  relative effect is about `1 / λ_k`. Near-Julia, not Julia.
- **The deep structure is a stretched copy**: in Mandelbrot mode the Jacobian
  stretches one direction 2.3 to 6.2 times more than another (Julia: 1.00). So
  the deep view is a linearly distorted copy of the Julia shape for `c` = that
  point, not of the Mandelbox. (The [Mandelbrot set](https://en.wikipedia.org/wiki/Mandelbrot_set#Self-similarity)
  behaves the same way: near a point it resembles that point's Julia set.)
- **c follows works as well as Julia mode.** A straight-line map takes rays to
  rays even when it stretches, so the distortion costs nothing, and the 32-bit
  rounding of the pixel's own `c` is shrunk by `λ_k` like everything else.

So the substitution does not need self-similarity at all. What it needs, in
every mode, is that no fold crease crosses the view within the first `k`
iterations.

### 3. What a float32 GPU would see

All in emulated float32 (the GPU), against the float64 reference. "Best k" is
the single `k` (of 4–20) that did best across the three views, picked with
hindsight; "CPU rule" picks `k` per view on the CPU, as a renderer would: the
largest `k` whose image of the view stays under a tenth of the distance to every
crease. Two-float and perturbation are the exact alternatives (section 5), run
for the first 16 or 20 iterations.

| shape | d | today | substitution, best k | substitution, CPU rule | two-float k=16 | two-float k=20 | perturbation k=16 | perturbation k=20 |
|---|---|---|---|---|---|---|---|---|
| Julia, default box | 1e-5 | 9% | 92% (k=8) | 92% | 100% | 100% | 100% | 100% |
| Julia, default box | 1e-6 | 0% | 88% (k=10) | 78% | 100% | 100% | 100% | 100% |
| Julia, default box | 1e-7 | 7% | 83% (k=10) | 97% | 100% | 100% | 100% | 100% |
| Julia ice field + rotation | 1e-5 | 10% | 98% (k=8) | 98% | 100% | 100% | 100% | 100% |
| Julia ice field + rotation | 1e-6 | 9% | 98% (k=12) | 94% | 100% | 100% | 100% | 100% |
| Julia ice field + rotation | 1e-7 | 2% | 87% (k=14) | 64% | 97% | 100% | 97% | 100% |
| Julia x, y, z, W 0.3 | 1e-5 | 16% | 100% (k=10) | 94% | 100% | 100% | 100% | 100% |
| Julia x, y, z, W 0.3 | 1e-6 | 16% | 100% (k=12) | 99% | 100% | 100% | 100% | 100% |
| Julia x, y, z, W 0.3 | 1e-7 | 4% | 98% (k=16) | 56% | 98% | 100% | 98% | 100% |
| Julia ice field (save) | 1e-5 | 14% | 74% (k=8) | 68% | 100% | 100% | 100% | 94% |
| Julia ice field (save) | 1e-6 | 8% | 92% (k=8) | 93% | 100% | 100% | 100% | 100% |
| Julia ice field (save) | 1e-7 | 5% | 72% (k=16) | 56% | 99% | 100% | 99% | 100% |
| Default Mandelbox | 1e-5 | 19% | 68% (k=6) | 86% | 100% | 100% | 100% | 100% |
| Default Mandelbox | 1e-6 | 14% | 89% (k=12) | 67% | 100% | 100% | 100% | 100% |
| Default Mandelbox | 1e-7 | 11% | 91% (k=14) | 86% | 100% | 100% | 100% | 100% |
| Default box, Julia x only | 1e-5 | 23% | 68% (k=4) | 79% | 100% | 100% | 100% | 100% |
| Default box, Julia x only | 1e-6 | 17% | 87% (k=8) | 75% | 100% | 100% | 100% | 100% |
| Default box, Julia x only | 1e-7 | 0% | 82% (k=12) | 90% | 100% | 100% | 100% | 100% |

(The CPU rule can beat "best k" because it picks a different `k` per view.)
Where the substitution agrees, the step count, which drives the Ice Fractal
colour, matches to within a few steps (median 0 to 3); today's float32 march
is off by a median of 25 to 190 steps at these depths.

### 4. Why the substitution is squeezed

Two conditions pull `k` in opposite directions:

- **Enough magnification.** The image of the view has to be big compared with
  the 32-bit grid at the image camera's coordinates (about `1e-7` to `5e-7`):
  roughly `λ_k × d ≳ 1e-3` before float32 stops hurting. At `d = 1e-7` that is
  `k` ≈ 12 or more.
- **Few enough iterations to stay straight.** The image of the view (out to
  `10 d`) has to stay well inside the distance to every fold crease, roughly
  `λ_k × d ≲ 1e-3` to `1e-2`, and less near the inversion centre.

They meet in a band one or two iterations wide, its position depends on where
the camera is, and some rays always fall on the wrong side of a crease. In a
picture that would show as a seam: correct geometry on one side of a line, a
mirror image on the other, moving as the camera moves, with a jump whenever `k`
changes.

## Which shapes qualify (the console flag)

The Shape tab's first line reads `Self-similar: yes (…)` or `Self-similar: no
(…)`. It comes from `MandelboxShape.self_similarity(values, displaced)` on the
resolved values (so a bound knob is followed live) and whether the noise graph
displaces the surface (`NoiseCompiler.displaces`). Main refreshes it every frame
the console is open.

| shape | self-similar? | reason shown | why |
|---|---|---|---|
| Mandelbrot mode (no Julia toggle) | no | `c follows the point` | the deep region is a stretched copy of a different shape (section 2) |
| Partial Julia (some of x, y, z) | no | `partial Julia: c follows the point in y, z` | the same, in the components that follow |
| Julia (all), or all four toggles | yes | `Julia: all four c fixed` | one iteration maps the shape onto itself |
| Julia x, y, z, w unchecked | yes | `Julia: x, y, z fixed (w is the slice's own)` | c's w is then the slice's `W`, the same at every pixel, so `c` is still one constant (measured: as good as Julia (all)) |
| any of the above with iteration rotation | unchanged | | the rotation is linear and keeps the copy exact |
| a noise field wired to Displace (Amplitude not 0) | no | `noise field displaces the surface` | the field is tied to positions, not carried along by the iteration; the displaced surface is no longer the Mandelbox's |
| a noise field wired to Tint only | unchanged | | colour only; the geometry is untouched |
| `|scale| × max(1, (fixed / min radius)²) ≤ 1` | no | `no iteration magnifies (|scale| too small)` | no iteration magnifies anywhere, so there is no deeper copy to use |

Read the line as information about the shape, not as permission for a
renderer: section 2 shows the rendering trick does not need it, and section 3
shows the trick is not good enough where it does apply.

## If the substitution were built anyway

For the record, what it would take (none of it is implemented):

1. Each frame, on the CPU in float64: iterate the eye `k` times (4D, with the
   rotation), carrying the Jacobian and the shader's `dz`. Pick `k` (section 4).
2. Push the image eye and the images of right, up and forward as `vec4`s, plus
   the starting `dz` and, in Julia mode, `c`. In Mandelbrot mode the GPU keeps
   computing `c = eye + dir × t` from the original camera.
3. In `de`, start from `z = eye' + dir' × t` (still in original `t`) with the
   pushed `dz`, and run `32 − k` iterations (and `coarse_iters − k` in the
   coarse pass). The hit test, the step budget and the fog stay as they are.
4. The normal's sample offsets go through the same map (the image right, up,
   forward). Anything coloured by world position (Rainbow's radius, the Ice
   Fractal field probe, the headlight) and the bounding-box clip use the
   original `eye + dir × t`; a normal used in world space is mapped back.
5. Rays that run past the trusted region (`t` beyond a few `d`) continue in the
   original space; far geometry needs far less precision, so this is safe but a
   second code path.

## Limits that apply whatever is built

- **The 32-iteration floor.** Inside the shape the estimate `|z| / dz` does
  not reach 0 after 32 iterations; it bottoms out at a floor set by how much the
  32 iterations magnify. Measured over 200 000 random points: about `1e-15` for
  the default Mandelbox (its sphere fold multiplies the magnification at every
  pass) but about `5e-10` for the *ice terraces* save (scale 1.88, weak sphere
  fold). A ray cannot hit closer than roughly `floor / precision`: about
  `1e-10` for the default box, far below anything here, but about `5e-6` for
  the ice terraces, which runs out of detail long before 32-bit positions do.
  So how much depth a precision fix opens up depends on the shape; going past
  that floor needs more iterations as well.
- **Noise fields.** A displaced surface is smooth below the displacement's
  size, so there is little to zoom into, and the noise itself is evaluated at
  the 32-bit position.

## Comparison with the two-float camera (and its cheaper cousin)

**Two-float camera** (the spec's option C). The GPU keeps each number of the
first `k` iterations as a pair of 32-bit floats whose sum carries about 48 bits
([double-double arithmetic](https://en.wikipedia.org/wiki/Quadruple-precision_floating-point_format#Double-double_arithmetic)),
per pixel, then rounds to ordinary floats and finishes. It is exact per pixel:
no straight-line approximation, no seams, any `k`.

**Perturbation.** The CPU computes one **reference orbit**, the eye's 32
iterates, in float64 (the substitution needs this anyway), and the GPU iterates
only each pixel's small *difference* from it, in ordinary floats. The folds'
differences can be written without subtracting nearly equal numbers (for
example, a mirror crossed between the reference and the pixel gives
`2 × (fold_limit − X) − δ`, with `fold_limit − X` supplied by the CPU in full
precision), so 32 bits are enough. After `k` iterations the pixel's point is
`X_k + δ_k`, large enough for ordinary floats, and the rest runs as today. This
is how deep Mandelbrot-set zoomers work
([perturbation theory](https://en.wikipedia.org/wiki/Plotting_algorithms_for_the_Mandelbrot_set#Perturbation_theory_and_series_approximation));
the substitution is its first-order shortcut, which the Mandelbrot community
calls *series approximation*. Mandelbrot mode is natural here: the pixel's
difference in `c` is just its difference in starting point.

Both were emulated with the same harness (section 3); the perturbation's
fold-difference formulas reproduce the float64 reference exactly when run in
float64, which checks the algebra.

| | substitution | two-float camera | perturbation |
|---|---|---|---|
| accuracy at d = 1e-5 … 1e-7 (section 3) | 68–100% at the best k, seams elsewhere | 97–100% (k = 16), 100% (k = 20) | 97–100% (k = 16), 94–100% (k = 20) |
| shapes | all without noise displacement (needs `c` following in Mandelbrot mode) | all | all |
| GPU cost per ray at depth (estimate) | none extra (fewer GPU iterations) | about 7× today's estimate: each paired-float iteration costs roughly 13 plain ones, × 16 iterations | about 1.5–2×: a difference iteration costs roughly 2 plain ones |
| CPU cost | one orbit and Jacobian per frame | none | one orbit per frame (32 iterates, microseconds) |
| GPU data | 4 `vec4` + 2 floats | the eye as two `vec3`s | about 10 floats per iteration, as uniform arrays |
| shader complexity | moderate, many special cases (normals, colour, clip, fallback) | moderate (a small paired-float library), isolated in `de` | moderate (case analysis per fold), isolated in `de` |
| risk | seams and pops by design | the GPU compiler must not fuse or reorder the paired-float steps; WebGL 2 has no way to forbid that (`precise` arrives in later GLSL) | glitches if the difference grows too large (seen at k = 24 for the ice field: 49% at 1e-5): stop perturbing once `λ_k × d` reaches about `1e-2`, which also sets `k` |

Cost figures are estimates from operation counts, not measurements: this
investigation had no GPU (headless only). They apply only below the zoom floor,
where the method is switched on; normal views cost exactly what they cost now.

## Recommendation

1. **Do not build the self-similar substitution.** It does not actually need
   self-similarity (so the console flag would not gate it), and it is
   approximate by construction: even at the best `k` it leaves up to a third of
   the rays wrong, as seams, at the depths it is meant for.
2. **Build option C as perturbation.** Same precision as the two-float camera
   in the experiment, an estimated quarter of its GPU cost, ordinary float
   arithmetic (no dependence on how a WebGL driver rounds), and a CPU reference
   orbit that is a small extension of `DistanceEstimator` (already float64).
   Choose `k` per frame as the smallest with `λ_k × d ≥ 1e-2` (about 14 at
   `1e-7` for the default box). Keep the two-float camera as the fallback if
   the per-fold case analysis proves fiddly in GLSL.
3. **Then revisit the zoom guard** (spec D): its floor moves from `1e-4` down
   to the 32-iteration floor above.
4. **Keep the console flag** as a description of the shape. It costs a few
   dictionary lookups a frame and nothing reads it.

## Reproducing

The scripts live outside the repository (in the session's scratchpad), as
asked for this investigation: a batched Python/numpy copy of `mb_step` and `de`
(float64 or float32), the forward-mode Jacobian of the first `k` iterations, the
camera map, the march, and the two-float and perturbation emulations. The method
above is complete enough to rebuild them; ask if they should be committed (for
example under `tools/`). The console flag is covered by the headless tests in
`tests/mandelbox_shape_test.gd`, `tests/noise_compiler_test.gd`,
`tests/console_test.gd`, `tests/ui_console_test.gd` and `tests/main_test.gd`.
