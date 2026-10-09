# Perturbation Deep Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the fly camera zoom past the 32-bit floor: a 64-bit eye, a CPU reference orbit, and a GPU march that iterates only each pixel's small offset from that orbit for its first `k` iterations (perturbation), with the zoom guard moved down to where perturbation or 32 iterations run out.

**Architecture:** `CameraState` keeps the eye as three 64-bit floats (the `Transform3D` origin becomes their rounded shadow). Each time the camera or the shape changes, `FractalView._push_near()` builds a `ReferenceOrbit` from the 64-bit eye: the eye's own 32 iterates in 64-bit, plus a per-iteration record of small "gaps" (crease position minus the reference point) packed into four `PackedVector4Array`s. `FractalParams.pert_iters()` picks how many iterations `k` to perturb; when it is positive the shader's march calls `de_pert(dir × t, n)` instead of `de(eye + dir × t, n)`. `de_pert` iterates the offset with per-fold difference formulas, then adds it to `X_k` and finishes with the ordinary loop. With `pert_iters == 0` the shader runs exactly today's arithmetic. The fly camera's guard moves to `max(floor_pert, floor_iter)`.

**Tech Stack:** Godot 4.6.1 (standard build: GDScript `float` is 64-bit, `Vector3`/`Vector4` components are 32-bit), a `canvas_item` shader under GL Compatibility (GLSL ES 3.0 / WebGL 2 floats), headless SceneTree tests (`tests/*_test.gd`, `tests/run_all.sh`), the in-browser viz (`docs/viz/`, plain JS).

Spec: `docs/superpowers/specs/2026-10-09-perturbation-deep-zoom-design.md`. Format follows `docs/superpowers/plans/2026-10-08-deep-zoom-march.md`.

## Where to work

Everything happens in the worktree, on branch `perturbation`:

```bash
WT=/Users/adam/Godot/HelpImStuckInAFractal/.claude/worktrees/perturbation
```

Every git command is `git -C $WT ...`. Every Godot run is `godot4 --headless --path $WT ...`. Never touch the main checkout `/Users/adam/Godot/HelpImStuckInAFractal` (another session is editing it).

## Global Constraints

- **No pushing or history rewriting:** no `git push`, `git merge`, `git rebase`, `git cherry-pick`, `git revert`, `git am`, no PRs. Commit only.
- **Never run `rm -rf`** or any recursive force-delete, in any form. To drop a single file use `git -C $WT rm <path>` or plain `rm <one file>`.
- **Headless only:** every Godot run has `--headless`. Never launch a windowed app, never run `tests/screenshots.sh` (that is the user's).
- **Commit by explicit path** (`git -C $WT add <path> ...`, never `-A` or `.`). Godot tracks a `.uid` file beside every `.gd` / `.gdshaderinc`: commit the new file's `.uid` with it (it appears after `tests/run_all.sh` or `godot4 --headless --import --path $WT`).
- Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (pass it as a second `-m`). Subject style: `feat(scope): ...`, `test(scope): ...`, `docs(scope): ...`.
- `tests/run_all.sh` (run as `$WT/tests/run_all.sh`; it `cd`s itself) must exit 0 before every commit. One test alone: `godot4 --headless --path $WT -s tests/<name>_test.gd`. After adding a file with a new `class_name`, run `godot4 --headless --import --path $WT >/dev/null 2>&1` once before running a single test (the class cache must know it).
- **The invariant:** with `pert_iters == 0` the shader's arithmetic is exactly today's, and at the default view `pert_iters` is 0, so the default view renders bit-for-bit as before (the user checks this with `tests/screenshots.sh`). Every shader edit to an existing line must keep that true; say so in the commit.
- Everything is automatic: no new renderer option, the save stays version 2, no new console knob. The only UI change is the read-only `deep k=N` readout.
- Not perturbed (keep today's 32-bit floor, `pert_iters` 0): the Mandelbox's octahedral fold, the KIFS polyfold, the Mandelbulb. Noise displacement stays evaluated at the 32-bit position.
- Comments and README prose in plain language; anything above basic calculus gets a one-line explanation (the user is an engineer, not a mathematician).
- Constants (exact):
  - `ReferenceOrbit.PERT_MAX = 20` (uniform array length; `k` never exceeds it), `ReferenceOrbit.ITERATIONS = 32`.
  - `FractalParams.PERT_ON = 10.0`, `FractalParams.PERT_HANDOFF = 0.1` (see Spec findings 15; the spec says 1e-2), `FractalParams.ITER_FLOOR_RADIUS = 0.25` (see Spec findings 1).
  - `FlyCamera.SPEED_FLOOR = 1e-14`.
  - `pert_iters(orbit, near) = 0` if `not orbit.perturbable` or `near >= PERT_ON × floor32(eye)`; else the smallest `k` in `1..min(PERT_MAX, orbit.n)` with `orbit.mag[k] × near >= PERT_HANDOFF`, or `min(PERT_MAX, orbit.n)` if none reaches it. `near` is the raw estimate at the eye (not clamped to `NEAR_FLOOR`).
  - `floor32(eye) = ulp32(max |eye_i|) / (ZOOM_FLOOR_DIVISOR × eps)` (today's `zoom_floor`), `eps = precision / detail`.
  - `floor_pert = ulp32(max |X_K| over x, y, z, w) / (ZOOM_FLOOR_DIVISOR × eps × mag[K])`, `K = min(PERT_MAX, orbit.n)`.
  - `floor_iter = ITER_FLOOR_RADIUS / (eps × mag[32])`; 0 for the Kleinian.
  - `zoom_floor(eye64) = max(floor_pert, floor_iter)` for a perturbable orbit, `floor32(eye64)` otherwise.

## Spec findings (read before Task 1)

**This plan's code was dry-run.** Tasks 1 to 7 were applied, as written here, to a clean `git archive` copy of the branch in a scratch folder, and `tests/run_all.sh` passed there (44 suites, exit 0; `perturbation_test.gd` about 30 s). The worktree was not touched. Treat a failure you hit as a deviation from the text, or as something that changed on the branch since, before suspecting the maths.

While planning, the spec's numbers were checked headless against the real CPU estimators (a 64-bit march with the shader's hit test `estimate < eps × t`, 32 iterations each step, along each fixture's centre ray from its surface point). The spec's mechanism holds; several of its *test thresholds* cannot. The plan resolves each one as below. Tell the user about 1 and 2; they change what the feature delivers on the default box.

| fixture (eps) | λ_32 at the eye | spec `floor_iter` (bound_half) | measured: last depth that hits / first that misses | plan `floor_iter` (R = 0.25) | `k` at d = 1e-5 / 1e-6 / 1e-7 |
|---|---|---|---|---|---|
| default box (2.5e-5) | 1.76e10 | 4.6e-6 | 3e-7 / 1e-7 | 5.7e-7 | 10 / 13 / 16 |
| ice field save (2e-5) | 3.27e11 | 3.1e-6 | 1e-7 / 1e-8 | 3.8e-8 | 9 / 12 / 14 |
| terraces save (1e-4) | 1.2e9 to 1.6e9 | 1.7e-4 | 3e-6 / 1e-6 | 2.1e-6 | 11 / 14 / 18 |
| KIFS Menger (2.5e-5) | 1.85e15 | 5.6e-11 | 1e-8 / none | 5.4e-12 | 7 / 9 / 11 |
| Kleinian (2.5e-5) | about 1950 (saturates) | 2e5 (meaningless) | 1e-8 / none | 0 (not applied) | 6 / 20 / 20 |

(Depths are camera back-off distances along the centre ray. The camera's estimate at the eye, `near`, is about 0.2 to 0.5 of that: the default box at back 1e-5 has `near` 2.0e-6, at 1e-6 4.8e-7, at 1e-7 1.9e-8. The `k` column applied the handoff rule to the back-off distance; the shipped rule uses `near`, which gives `k` one to three higher. The `floor_iter` columns are in units of `near`, which the guard compares against, so the guard stops the camera a little further out than the last depth that hits: on the safe side.)

1. **`floor_iter`'s numerator.** `bound_half` (2, or 20 in Julia mode) overstates where the 32-iteration estimate bottoms out by 15 to 50 times on the three Mandelbox fixtures. The estimate floors at about `|z_32| / λ_32` with `|z_32|` a fraction of a unit at the surface. The plan uses a named constant `ITER_FLOOR_RADIUS = 0.25`, calibrated on these three fixtures: with it, a 128-step 64-bit march from `10 × floor_iter` hits within 1% on all three, and from `floor_iter / 10` it misses on all three (measured). That is the spec's own bracket test, which `bound_half` fails.
2. **The default box gains about 2 decades, not 6.** At the default view's own surface point, 32 iterations stop resolving at about 2e-7, so the new floor there is about `5.7e-7` (camera estimate), against today's `9.5e-5`. The spec's "zoom_floor below 1e-8 for the default box" and "a flight to 1e-8 on the default box must show detail" cannot hold without more than 32 iterations (out of scope per the spec). The KIFS and Kleinian fixtures do resolve at 1e-8. Tests are adapted: `fractal_params_test` checks the default box's floor is at least 50× below `floor32`; `center_ray_test` uses 3e-7 (measured: the 64-bit origin hits, t/back 1.001; the rounded origin misses, 1.143); the fly test starts below today's floor rather than at 1e-6 (which is under the new floor).
3. **The Kleinian has no `floor_iter`.** Its `bound_half` is a 1e4 sentinel, and its estimate (Knighty's thingy over `dr`) goes to 0 at the sheets rather than bottoming out. Its floor is `floor_pert` alone.
4. **Sort formula, "only the reference swaps".** The spec writes `δ'_a = δ_b + gap, δ'_b = δ_a − gap`. The correct one is `δ'_a = δ_a + gap, δ'_b = δ_b − gap` (the pixel's components stay put; the reference's swap). Derivation: `δ'_a = P_a − X_b = X_a + δ_a − X_b = δ_a + gap`. The plan uses the corrected form, and the 64-bit algebra check would catch the spec's.
5. **Diagonal, "both reflect":** `δ' = (−δ_b, −δ_a)` (swapped and negated, not just swapped). "Only the reference": `(δ_a + gap, δ_b + gap)`.
6. **`iters < pert_iters`** (the coarse pass asking for fewer iterations than `k`): the spec says "run `min(pert_iters, iters)`" but `pert_end` is `X_k`. The plan always runs `k` perturbed iterations and resumes to `max(iters, k)`. In practice it never binds: below `PERT_ON × floor32` the coarse count is already 24 to 32 and `k <= 20`.
7. **Record slots the spec leaves unused:** cylinder fold, `a.xy` holds the reference's own `X.xy` (instead of recovering it from `c` with `(L + g) / (L − g)`, which divides by zero at `r = 2L`); KIFS, `d` holds `X_{i+1}` (the GPU's per-iteration bailout test needs the point, and only `X_k` is a uniform).
8. **"Reproduces the reference exactly" in 64-bit:** two different 64-bit computations cannot agree bit-for-bit. The algebra check compares the perturbed offset with the direct orbit's difference iteration by iteration, within `1e-12 × λ_i × max(1, |X_i|, |P_i|) + 1e-9 × |δ_i|` (rounding is about 1e-16 × λ_i; a wrong formula is off by about `|δ_i|`), over random offsets of 1e-7 to 1e-1 that exercise every crossing case.
9. **The agreement grid's checks** apply to cells where the 64-bit reference hits on at least half the 27 rays. Below a fixture's 32-iteration floor (the terraces at 1e-6 and 1e-7, the default box at 1e-7) the reference runs out of steps on most rays and "agreement" says nothing. Every cell is printed. The spec's 27-ray fan, march budget and classes are defined in Task 1 (a 3 × 3 grid at three field fractions; 128 steps at 32 iterations; hit / beyond `10 d` / out of steps).
10. **Full-precision saves:** `Workspace.save_file` writes JSON with `JSON.stringify(..., "\t", false, true)`. The default (`full_precision = false`) keeps 15 significant digits, so a deep eye loses about 1e-14 (checked headless: `1.9600000012345678` comes back as `1.96000000123457`). Full precision prints the shortest exact form (`0.1` stays `0.1`), so other fields read the same. Godot's float parser is not correctly rounded, though: measured over 20,000 values, about a third come back one 64-bit ulp off (at most about 4e-15 for coordinates under 20). That is thousands of times below the deepest zoom floor (about 5e-12), so the plan accepts it: in-memory capture/restore is exact, and the file round-trip test allows one ulp. (Bit-exact files would need the doubles' bytes stored beside the numbers, e.g. base64; not worth a format addition.)
11. **GDScript has no overloading:** the scalar march is `CenterRay.march_at(ox, oy, oz, dir, params)`; `march(origin: Vector3, ...)` calls it.
12. **`mag` per shape:** Mandelbox, the product of the sphere-fold factors and `|scale|` (the `dz` without its `+ 1`s; the cylinder fold's xy factor is not included, as `dz` does not include it); KIFS, `|kifs_scale|^i` for every `i` regardless of bailout (an exterior eye always escapes early, and `floor_iter` needs what 32 iterations magnify); Kleinian, `dr` (constant after a fixed point).
13. **`ReferenceOrbit` has three fields beyond the spec's list:** `eye` (the doubles it was built from, for `floor32`), `points64` and `rec64` (the 64-bit copies the algebra check reads). `PERT_MAX` lives on `ReferenceOrbit` (it sizes its arrays); `FractalParams` reads it from there, so no constant crosses the two classes' cyclic reference at parse time.
14. **Not in this plan:** the spec's second pane, `perturbation-design` ("written now, before the code"), does not exist on the branch. It is a separate `/visualize` job.
15. **`PERT_HANDOFF` is 0.1, not the spec's 1e-2.** Task 1's code was run headless while planning (emulated float32, 27 rays per cell, 128 steps). With the hand-off at `mag[k] × near >= 1e-2`, the default box scored 85% at 1e-6 (k 14) and 96% at 1e-7 (k 18): four rays landed 0.15% to 0.5% off the reference, because the 32-bit point after an early hand-off is only a few times finer than the hit threshold. In 64-bit the same marches miss nothing, so the formulas are not at fault. With 0.1, every cell of the grid (five fixtures, plus the default box at 3e-6 and 3e-7) scored 100%, at the cost of at most three more perturbed iterations (k 17 instead of 14 at 1e-6; still at most 20):

    | fixture | d | k at 1e-2 | agrees | k at 0.1 | agrees |
    |---|---|---|---|---|---|
    | default box | 1e-5 / 3e-6 / 1e-6 / 3e-7 / 1e-7 | 12 / 13 / 14 / 17 / 18 | 100 / 100 / **85** / 100 / **96** % | 15 / 16 / 17 / 20 / 20 | 100% everywhere |
    | ice field | 1e-5 / 1e-6 / 1e-7 | 11 / 15 / 16 | 100% | 14 / 18 / 19 | 100% |
    | terraces | 1e-5 / 1e-6 / 1e-7 | 12 / 16 / 20 | 100% | 15 / 19 / 20 | 100% |
    | Menger | 1e-5 / 1e-6 / 1e-7 | 8 / 9 / 12 | 100% | 10 / 12 / 14 | 100% |
    | Kleinian | 1e-5 / 1e-6 / 1e-7 | 8 (its eye's orbit settles after 8: `n` caps `k`) | 100% | 8 | 100% |

    The self-similar note's rule (`λ_k × d ≥ 1e-2`) measured `d` as the back-off distance and judged glitches from too large an offset; perturbation here is exact algebra (no series approximation), so a later hand-off has no such cost. To restore the spec's value, change the one constant; Task 1's checks still pass then, because the two weak cells are below the default box's 32-iteration floor and the 1e-7 cell is unchecked.

## Merge hazards (for the user)

`main`'s Mandelbulb work and the other live session touch `mandelbox.gdshader`, `fractal_params.gd`, `fractal_view.gd` and `distance_estimator.gd`. This plan keeps those edits small and local:

- `distance_estimator.gd`: **not touched.** `ReferenceOrbit` calls its static helpers and computes the sphere factor itself.
- `mandelbox.gdshader`: one new function `mb_orbit` (after `mb_constant`), the Mandelbox loop in `de()` replaced by one call to it, one `#include` line, two `de(...)` → `march_de(...)` calls in `fragment()`'s loops, three `calc_normal(v, delta)` → `true_normal(v, dir * total, delta)`. Everything else is in the new `perturbation.gdshaderinc`.
- `kifs.gdshaderinc`, `kleinian.gdshaderinc`: each loop moved into an `*_orbit` function plus a `*_distance` function. The bodies are unchanged.
- `fractal_params.gd`: `zoom_floor(eye: Vector3)` becomes `floor32(eye: PackedFloat64Array)` (same body). New constants and functions are appended after it.
- `fractal_view.gd`: `_push_near()`'s body, two new vars and one accessor.

## File map

| file | change |
|---|---|
| `tests/perturbation_port.gd` (new, `class_name PerturbationPort`) | GDScript port of the shader's perturbed and direct estimates, in emulated float32 or 64-bit |
| `tests/reference_orbit_draft.gd` (new in Task 1, moved to `src/fractal/reference_orbit.gd` in Task 3) | the reference orbit and its per-iteration record |
| `tests/perturbation_test.gd` (new) | case tables, 64-bit algebra check, float32 agreement grid, the printed table |
| `tests/surface_fixture.gd` | `surface_from`, `backed`, `save_params`, `back_for_distance`, `march64`, `variants` |
| `src/camera/camera_state.gd` | `eye_x/y/z`, `set_eye64`, `eye64`, the transform setter keeps the doubles |
| `src/camera/fly_camera.gd` | 64-bit step, `move_allowed(PackedFloat64Array, PackedFloat64Array)`, `SPEED_FLOOR`, `base_speed` from the 64-bit eye |
| `src/camera/center_ray.gd` | `march_at` (scalar origin); the cache marches from `eye64` |
| `src/workspace/workspace.gd` | eye saved and restored at full precision |
| `src/fractal/reference_orbit.gd` (new, Task 3) | `ReferenceOrbit` |
| `src/fractal/fractal_params.gd` | `PERT_ON`, `PERT_HANDOFF`, `ITER_FLOOR_RADIUS`, `floor32`, `pert_iters`, `floor_pert`, `floor_iter`, `zoom_floor_for`, `zoom_floor(eye64)` |
| `src/fractal/perturbation.gdshaderinc` (new) | `pert_*` uniforms, the perturbed steps, `de_pert`, `march_de`, `calc_normal_pert`, `true_normal` |
| `src/fractal/mandelbox.gdshader`, `kifs.gdshaderinc`, `kleinian.gdshaderinc` | orbit loops take a start index; `fragment()` switch |
| `src/fractal/fractal_view.gd` | `_push_near()` builds the orbit and pushes `pert_*`; `pert_iters()` |
| `src/ui/console/movement_pane.gd`, `console_window.gd`, `src/main.gd` | `deep k=N` readout |
| tests | `camera_state_test`, `workspace_test`, `center_ray_test`, `fly_camera_test`, `reference_orbit_test` (new), `fractal_params_test`, `shader_test`, `fractal_view_test`, `console_test`, `ui_console_test`, `main_test` |
| `README.md` | Deep zoom, Fly camera, Saved views, Testing |
| `docs/viz/panes/deep-zoom.js` (new), `docs/viz/index.html`, `docs/viz/glossary.js` | the `deep-zoom` pane |

---

### Task 1: The proof: a float32 port of the perturbed step, and `perturbation_test.gd`

This runs before any shader work and proves the difference formulas. It has three layers: hand-picked cases for every step kind (each crossing case against the direct difference), whole orbits in 64-bit (the perturbed offset equals the direct orbit's difference, iteration by iteration, for every shape variant), and the march in emulated float32 (the spec's agreement table). The per-iteration record is built by a draft of `ReferenceOrbit` that lives in `tests/` for now, because the record layout is part of what is being proven. Task 3 moves it to `src/` unchanged.

**Files:**
- Create: `tests/perturbation_port.gd`, `tests/reference_orbit_draft.gd`, `tests/perturbation_test.gd`
- Modify: `tests/surface_fixture.gd`

**Interfaces:**
- Consumes: `DistanceEstimator._fold`, `_sphere_fold`, `_rot_plane`, `menger_fold`, `PLANES`; `KifsEstimator._angles`, `_rotate`, `_poly_fold`, `_box_distance`, `BAILOUT2`, `ROT_IDS`, `FoldSet`; `KleinianEstimator.thingy`; `MandelbulbEstimator.estimate_at`; `FractalParams.ulp32`, `ZOOM_FLOOR_DIVISOR`.
- Produces:
  - `ReferenceOrbitDraft.build(params: FractalParams, ex: float, ey: float, ez: float) -> ReferenceOrbitDraft`, consts `ITERATIONS := 32`, `PERT_MAX := 20`; fields `eye: PackedFloat64Array` (3), `distance: float`, `n: int`, `perturbable: bool`, `mag: PackedFloat64Array` (33), `points: PackedVector4Array` (33, 32-bit), `points64: PackedFloat64Array` (33 × 4), `a, b, c, d: PackedVector4Array` (20 each, 32-bit), `rec64: PackedFloat64Array` (20 × 4 slots × 4, index `(i * 4 + slot) * 4 + comp`, slot 0..3 = a..d).
  - `PerturbationPort.new(params, eye64: PackedFloat64Array, use_f32: bool)`; `de_pert(orbit, k: int, off: Array, iters: int) -> float`; `de_direct(pos: Array, iters: int) -> float`; the step functions `pert_clamp1`, `pert_clamp`, `pert_abs`, `pert_swap`, `pert_sort`, `pert_flip`, `pert_diagonal`, `pert_menger`, `pert_sphere`, `pert_cylinder`, `pert_mb_fold`; `r(x)`, `u(x)`; vars `crossings: Dictionary`, `tracing: bool`, `trace: Array`.
  - `SurfaceFixture.surface_from(params, eye: Vector3) -> Array`, `backed(s: Array, back: float) -> PackedFloat64Array`, `save_params(path: String) -> FractalParams`, `back_for_distance(params, s: Array, target: float) -> float`, `march64(o: PackedFloat64Array, dir: Array, params, steps: int) -> Array` (`[t, hit]`), `variants() -> Array` (`[name, params, eye: Vector3, perturbable: bool]`).

#### The per-iteration record (the GPU reads this; Task 5's shader and this port must agree)

`X` is the reference's point at that step, computed in 64-bit. Every entry is either a small gap (precise in 32 bits) or a value that only needs relative precision.

| shape | `a` (slot 0) | `b` (slot 1) | `c` (slot 2) | `d` (slot 3) |
|---|---|---|---|---|
| Mandelbox | fold's lower gaps `lo − F` per component, `F` = the fold's input; **cylinder:** `(F.x, F.y, −L − F.z, −L − F.w)` | upper gaps `hi − F`; **cylinder:** `(0, 0, L − F.z, L − F.w)` | the sphere fold's input `S` | `(|S|² − mr, |S|² − fr, m, r_xy − L)`: `mr = max(min_radius², 1e-12)`, `fr = max(fixed_radius², 1e-12)`, `m` the reference's sphere factor, `r_xy − L` the cylinder's radial gap (0 otherwise) |
| KIFS | `−X1` (abs-fold gaps, `X1` = `X` after R1) | coordinate set: `(A0 − A1, A0' − A2, A1' − A2', 0)`, each from the state at that comparison (`A` = `|X1|`); diagonal set: `(X0 + X1, X0 + X2, X1 + X2, X0 + X3)`, each from the state at that comparison | `.x`: the Menger gap `Z_z + t/2`, `Z` = the point after the scale, `t = o_z (s − 1)` | `X_{i+1}`, the point after the whole iteration |
| Kleinian | `−box − X` | `box − X` | the post-fold point `S` | `(|S|² − radius², m, 0, 0)` |

Box fold: `lo = −L`, `hi = L` (`L` = `fold_limit`). Hybrid iteration (`hybrid_mix > 0` and `i % every == every − 1`): `lo = −L (1 − mix)`, `hi = (L + mix) / max(1 − mix, 1e-6)`. `fold_order` 0: fold record from `X`, then sphere record from the post-fold point. `fold_order` 1: sphere record from `X`, then fold record from the post-sphere point.

#### The difference formulas, per step kind (the port and the shader implement exactly these)

`δ` is the pixel's offset entering the step, `δ'` leaving it. `P = X + δ`.

- **Clamp folds** (box, hybrid, Kleinian box), per component, gaps `g_lo = lo − X`, `g_hi = hi − X`:
  `δ' = 2 × (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ`. (Identity: `clamp(X + δ, lo, hi) = X + clamp(δ, lo − X, hi − X)`.)
- **KIFS abs fold**, `g = −X1`: `δ' = 2 × (max(δ, g) − max(0, g)) − δ`.
- **KIFS sort**, one compare-and-swap of `(a, b)` (swap when `a < b`), `gap = X_a − X_b`: pixel swaps when `δ_a − δ_b < −gap`, reference when `gap < 0`.
  both: `(δ_b, δ_a)`; only pixel: `(δ_b − gap, δ_a + gap)`; only reference: `(δ_a + gap, δ_b − gap)`; neither: unchanged. Order: (x, y), then (x, z), then (y, z).
- **KIFS diagonal**, one reflection of `(a, b)` (when `a + b < 0`, `(a, b) → (−b, −a)`), `gap = X_a + X_b`: pixel reflects when `δ_a + δ_b < −gap`, reference when `gap < 0`.
  both: `(−δ_b, −δ_a)`; only pixel: `(−gap − δ_b, −gap − δ_a)`; only reference: `(δ_a + gap, δ_b + gap)`. Order: (x, y), (x, z), (y, z), (x, w).
- **Menger correction** (`z += t` when `z < −t/2`), `g = Z_z + t/2`: `δ'_z = δ_z + t × ([δ_z < −g] − [g < 0])`.
- **Sphere fold / Kleinian inversion:** `δ' = m' δ + X (m' − m)`, `X` = the fold's input (record `c`), `q = 2 X·δ + δ·δ` (= `|P|² − |X|²`, a sum of products), `|P|² = |X|² + q`. Regimes: 0 inside (`|·|² < mr`, factor `fr / mr`), 1 shell (`< fr`, factor `fr / |·|²`), 2 outside (factor 1). Reference regime from `g_min = d.x < 0` / `g_fix = d.y < 0`; pixel regime from `g_min + q < 0` / `g_fix + q < 0`. `m'` is the pixel's own factor (`fr / max(|P|², 1e-12)` in the shell). `m' − m`:

  | reference → pixel | `m' − m` |
  |---|---|
  | shell → shell | `−fr q / (|P|² |X|²)` |
  | inside → shell | `−fr (g_min + q) / (|P|² mr)` |
  | shell → inside | `fr g_min / (mr |X|²)` |
  | shell → outside | `g_fix / |X|²` |
  | outside → shell | `−(g_fix + q) / |P|²` |
  | inside → outside | `1 − fr / mr` |
  | outside → inside | `fr / mr − 1` |
  | same regime, inside or outside | `0` |

  The running derivative multiplies by `m'` (`dz *= m'`). The Kleinian uses the same function with `g_min = 1e30` (no inner core), `mr = fr = radius²` and `g_fix = d.x`.
- **Cylinder fold, xy pair** (`r → 2L − r` outside radius `L`): `X` = record `a.xy`, `g = r − L` (record `d.w`), `rr = L + g`, `q = 2 X·δ + δ·δ`, `r' = sqrt(max(rr² + q, 0))`, `Δr = q / max(r' + rr, 1e-30)` (= `r' − r` without cancellation). Reference outside when `g > 0`, pixel when `g + Δr > 0`. `m' = (2L − r') / r'` if the pixel is outside, else 1.
  both outside: `m' − m = −2 L Δr / (rr r')`; only pixel outside: `−2 (g + Δr) / r'`; only reference outside: `2 g / rr`; both inside: 0. `δ'_xy = m' δ_xy + X (m' − m)`. The z and w components take the clamp formula with gaps `a.zw`, `b.zw`. `dz` is unchanged.
- **Linear steps:** iteration rotation, KIFS R1/R2 and twist apply to `δ` as they are (`mb_iter_rotate`, `kifs_rot1/2`, `mb_rot_plane`). Scale: `δ' = s δ` (the KIFS `−(s − 1) o` and the Kleinian shift cancel).
- **The add** (Mandelbox): `δ' = s δ + δc`, `δc = (off.x, off.y, off.z, 0)` with each of x, y, z zeroed where the Julia flag (`julia_all` or `julia_k`) is on. `dz = dz |s| + 1` as the direct path.
- **Bailout / fixed point:** the CPU caps `k` at `orbit.n`. KIFS: after each perturbed iteration, if `|d + δ|² > 1e6` (`d` = record `X_{i+1}`) the pixel escaped: the estimate is `kifs_distance(d + δ, i + 1)`. Kleinian: no fixed-point test inside the perturbed loop (a fixed reference is capped by `n`; the resumed loop tests as usual).
- **Handoff:** `z = X_k + δ_k` (`pert_end`), the pixel's own `dz` (or `dr`, or KIFS `n = k`), then the ordinary loop from iteration `k` to `max(iters, k)`. The Mandelbox's resumed `c` is `mb_constant(vec4(eye + off, w))`, formed in 32 bits (its rounding is shrunk by `λ_k` like everything else).

- [ ] **Step 1: Add the fixture helpers to `tests/surface_fixture.gd`.** Append to the file (keep `default_surface` as it is):

```gdscript


## The surface point the ray from `eye` toward the origin meets, refined in
## 64-bit like default_surface, but marched from the eye itself so any shape and
## eye work. Where round-off stalls the march it keeps the closest point it
## reached. Returns [x, y, z, fx, fy, fz].
static func surface_from(params: FractalParams, eye: Vector3) -> Array:
	var f := (Vector3.ZERO - eye).normalized()
	var x: float = eye.x
	var y: float = eye.y
	var z: float = eye.z
	var best := [x, y, z]
	var best_d := INF
	for _i in 3000:
		var d := DistanceEstimator.estimate_at(x, y, z, params)
		if d < best_d:
			best_d = d
			best = [x, y, z]
		if d < 1e-10:
			break
		x += f.x * d
		y += f.y * d
		z += f.z * d
	return [best[0], best[1], best[2], f.x, f.y, f.z]


## The camera `back` short of the surface point s along its ray, in 64-bit.
static func backed(s: Array, back: float) -> PackedFloat64Array:
	return PackedFloat64Array([s[0] - s[3] * back, s[1] - s[4] * back, s[2] - s[5] * back])


## FractalParams with a saved view's shape defaults applied (its bindings and
## camera ignored), e.g. save_params("res://saves/juliaIceTerraces.json").
static func save_params(path: String) -> FractalParams:
	var p := FractalParams.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var defaults: Dictionary = data["shape"]["defaults"]
	var values := {}
	for key in defaults:
		values[StringName(key)] = defaults[key]
	p.apply_resolved(values)
	return p


## How far back along s's ray the 32-iteration estimate at the eye is `target`
## (within 5%): a bisection on log10(back) over [-10, -1]. The estimate is not
## strictly monotone in back, so callers check what they got.
static func back_for_distance(params: FractalParams, s: Array, target: float) -> float:
	var lo := -10.0
	var hi := -1.0
	var mid := 0.0
	for _i in 80:
		mid = 0.5 * (lo + hi)
		var e := backed(s, pow(10.0, mid))
		var d := DistanceEstimator.estimate_at(e[0], e[1], e[2], params)
		if absf(d / target - 1.0) < 0.05:
			break
		if d < target:
			lo = mid
		else:
			hi = mid
	return pow(10.0, mid)


## A 64-bit march from o along unit dir with the shader's fine-pass test (32
## iterations, a hit once the estimate is under eps × t, eps = precision /
## detail), `steps` steps. Returns [t, hit].
static func march64(o: PackedFloat64Array, dir: Array, params: FractalParams, steps: int) -> Array:
	var eps := params.precision / params.detail
	var t := 0.0
	for _i in steps:
		var d := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if d < eps * t:
			return [t, true]
		t += d
	return [t, false]


## Every shape variant the perturbation tests run: [name, params, eye, perturbable].
## The eye is where surface_from starts (the fly tests' eyes for the other shapes).
static func variants() -> Array:
	var box_eye := CameraState.DEFAULT_EYE
	var menger_eye := Vector3(3.2, 2.4, 1.9)
	var kl_eye := Vector3(2.5, 1.6, 1.2)
	var kifs := FractalParams.Shape.KIFS
	var kl := FractalParams.Shape.KLEINIAN
	var cyl := MandelboxShape.FoldShape.CYLINDER
	return [
		["default box", _with({}), box_eye, true],
		["box, sphere first", _with({&"fold_order": 1}), box_eye, true],
		["cylinder", _with({&"fold_shape": cyl}), box_eye, true],
		["cylinder, sphere first", _with({&"fold_shape": cyl, &"fold_order": 1}), box_eye, true],
		["hybrid", _with({&"hybrid_mix": 0.5}), box_eye, true],
		["rotating, drifting", _with({&"iter_rot_xy": 5.0, &"iter_rot_xw": 3.0, &"scale_drift": 0.01}), box_eye, true],
		["partial Julia", _with({&"julia_0": true}), box_eye, true],
		["ice field", save_params("res://saves/juliaIceField.json"), box_eye, true],
		["terraces", save_params("res://saves/juliaIceTerraces.json"), box_eye, true],
		["octahedral", _with({&"fold_shape": MandelboxShape.FoldShape.OCTAHEDRAL}), box_eye, false],
		["Menger", _with({&"shape": kifs}), menger_eye, true],
		["Menger, rotated, twisted", _with({&"shape": kifs, &"kifs_rot1_xy": 12.0, &"kifs_rot2_yz": 7.0, &"kifs_twist": 4.0}), menger_eye, true],
		["Sierpinski", _with({&"shape": kifs, &"kifs_fold": KifsEstimator.FoldSet.DIAGONAL, &"kifs_scale": 2.0}), Vector3(3.5, -2.0, 2.2), true],
		["polyfold", _with({&"shape": kifs, &"kifs_fold": KifsEstimator.FoldSet.POLYFOLD}), menger_eye, false],
		["Kleinian", _with({&"shape": kl}), kl_eye, true],
		["Kleinian, shifted", _with({&"shape": kl, &"kleinian_shift_0": 0.1, &"kleinian_shift_2": -0.05}), kl_eye, true],
		["Mandelbulb", _with({&"shape": FractalParams.Shape.MANDELBULB}), Vector3(2.2, 1.6, 1.2), false],
	]


static func _with(values: Dictionary) -> FractalParams:
	var p := FractalParams.new()
	p.apply_resolved(values)
	return p
```

- [ ] **Step 2: Write the first part of the test: the emulation check and the case tables.** Create `tests/perturbation_test.gd`:

```gdscript
extends "res://tests/test_case.gd"
## The keystone of the perturbation work (spec:
## docs/superpowers/specs/2026-10-09-perturbation-deep-zoom-design.md). The GPU
## works in 32-bit floats, which near the fractal sit on a grid about 1e-7 apart:
## a camera 1e-6 from the surface sees a view only a few grid steps wide.
## Perturbation iterates only each pixel's small offset from the camera's own
## orbit (computed in 64-bit on the CPU), so the offset keeps its precision.
##
## Three layers, all against PerturbationPort (a line-for-line port of the shader):
## 1. each step kind's difference formula, case by case, against the direct
##    difference (64-bit);
## 2. whole orbits in 64-bit: the perturbed offset is the direct orbit's
##    difference, iteration by iteration, for every shape variant, over random
##    offsets big enough to cross every kind of crease;
## 3. the march in emulated float32, the spec's table: the direct float32 march
##    gets under 30% of rays right at 1e-6 (today's failure), the perturbed one at
##    least 90% at every depth, wherever the 64-bit reference itself resolves the
##    surface. Prints the table (lines start with MEASURED) for the viz's Measured tab.

const DEPTHS := [1e-5, 1e-6, 1e-7]
## The march budget: the shader's default 96 + 32, every step at 32 iterations.
const STEPS := 128
## Two hits agree when their distances differ by under 0.1% (about one pixel's
## depth footprint in an 800-pixel-high 40° view).
const AGREE_T := 1e-3
## Random offsets per shape variant in the algebra check.
const SAMPLES := 48
## Spec findings 1: the 32-iteration estimate bottoms out near this radius over λ_32.
## Spec findings 15: hand off once mag[k] × near reaches this.
## (Task 4 moves both to FractalParams and the helpers that use them to FractalParams.)
const ITER_FLOOR_RADIUS := 0.25
const PERT_HANDOFF := 0.1


func run() -> void:
	_check_emulation()
	_check_cases()


# ------------------------------------------------------------- 0. the emulation itself

func _check_emulation() -> void:
	var p := PerturbationPort.new(FractalParams.new(), PackedFloat64Array([0.0, 0.0, 0.0]), true)
	check_eq(p.r(1.0 + 1e-8), 1.0, "r() drops what a 32-bit float cannot hold (1 + 1e-8 is 1)")
	check_eq(p.r(0.1), 0.10000000149011612, "and rounds 0.1 to its 32-bit value")
	check_eq(p.r(0.1), float(Vector4(0.1, 0.0, 0.0, 0.0).x), "the value a Vector4 (the record's type) holds")
	p.f32 = false
	check_eq(p.r(1.0 + 1e-8), 1.0 + 1e-8, "f32 = false leaves 64-bit values alone")


# ------------------------------------------------------------- 1. each crossing case

func _check_cases() -> void:
	var p := PerturbationPort.new(FractalParams.new(), PackedFloat64Array([0.0, 0.0, 0.0]), false)

	# clamp folds: all nine side pairs of X and P against [-1, 1]
	for x in [-1.5, 0.2, 1.5]:
		for q in [-1.25, 0.5, 1.75]:
			var want: float = (2.0 * clampf(q, -1.0, 1.0) - q) - (2.0 * clampf(x, -1.0, 1.0) - x)
			check_approx(p.pert_clamp1(q - x, -1.0 - x, 1.0 - x, "clamp"), want,
				"clamp fold, X %s -> P %s" % [x, q], 1e-12)

	# the KIFS abs fold (crease at 0, nothing above)
	for x in [-0.7, 0.4]:
		for q in [-0.3, 0.9]:
			var got: float = p.pert_abs([q - x, 0.0, 0.0, 0.0], [-x, 0.0, 0.0, 0.0])[0]
			check_approx(got, absf(q) - absf(x), "abs fold, X %s -> P %s" % [x, q], 1e-12)

	# sort compare-and-swap: neither, both, only the pixel, only the reference
	for pair in [[[2.0, 1.0], [2.5, 0.5]], [[1.0, 2.0], [0.5, 2.5]],
			[[2.0, 1.9], [1.8, 2.1]], [[1.9, 2.0], [2.1, 1.8]]]:
		var x: Array = pair[0]
		var q: Array = pair[1]
		var got := p.pert_swap(q[0] - x[0], q[1] - x[1], x[0] - x[1])
		var sx := [maxf(x[0], x[1]), minf(x[0], x[1])]
		var sq := [maxf(q[0], q[1]), minf(q[0], q[1])]
		check(absf(got[0] - (sq[0] - sx[0])) < 1e-12 and absf(got[1] - (sq[1] - sx[1])) < 1e-12,
			"sort swap, X %s -> P %s (got %s)" % [x, q, got])

	# diagonal reflection: neither, both, only the pixel, only the reference
	for pair in [[[1.0, 0.5], [1.2, 0.1]], [[-1.0, -0.5], [-1.2, -0.1]],
			[[0.3, -0.2], [0.1, -0.4]], [[-0.3, 0.2], [-0.1, 0.4]]]:
		var x: Array = pair[0]
		var q: Array = pair[1]
		var got := p.pert_flip(q[0] - x[0], q[1] - x[1], x[0] + x[1])
		var fx := _flip(x)
		var fq := _flip(q)
		check(absf(got[0] - (fq[0] - fx[0])) < 1e-12 and absf(got[1] - (fq[1] - fx[1])) < 1e-12,
			"diagonal fold, X %s -> P %s (got %s)" % [x, q, got])

	# Menger correction, t = 2: z < -1 gains 2
	for xz in [-1.5, 0.5]:
		for qz in [-1.2, 0.2]:
			var want: float = (qz + (2.0 if qz < -1.0 else 0.0)) - (xz + (2.0 if xz < -1.0 else 0.0))
			check_approx(p.pert_menger(qz - xz, xz + 1.0, 2.0), want,
				"Menger correction, X_z %s -> P_z %s" % [xz, qz], 1e-12)

	# sphere fold, min_radius 0.7, fixed_radius 1: all nine regime pairs
	var mr2 := 0.49
	var fr2 := 1.0
	for xa in [0.5, 0.85, 1.3]:
		for qa in [0.5, 0.85, 1.3]:
			var x := [xa, 0.03, 0.0, 0.0]
			var q := [qa, 0.04, 0.01, 0.0]
			var x2: float = xa * xa + 0.0009
			var q2: float = qa * qa + 0.0016 + 0.0001
			var mx := _sphere_factor(x2, mr2, fr2)
			var mq := _sphere_factor(q2, mr2, fr2)
			var dl := [q[0] - x[0], q[1] - x[1], q[2] - x[2], 0.0]
			var got := p.pert_sphere(dl, 1.0, x, x2 - mr2, x2 - fr2, mr2, fr2, "sphere")
			var err := 0.0
			for j in 4:
				err = maxf(err, absf(got[0][j] - (mq * q[j] - mx * x[j])))
			check(err < 1e-12, "sphere fold, |X| %s -> |P| %s (error %s)" % [xa, qa, err])
			check_approx(got[1], mq, "and the pixel's dz takes its own factor", 1e-12)

	# cylinder fold (L = 1, the default fold_limit): xy radius inside/outside pairs
	for xr in [0.6, 1.4]:
		for qr in [0.7, 1.3]:
			var x0: float = 0.8 * xr
			var x1: float = 0.6 * xr
			var q0: float = 0.79 * qr
			var q1: float = 0.613 * qr
			var rx := sqrt(x0 * x0 + x1 * x1)
			var rq := sqrt(q0 * q0 + q1 * q1)
			var fx := (2.0 - rx) / rx if rx > 1.0 else 1.0
			var fq := (2.0 - rq) / rq if rq > 1.0 else 1.0
			var got := p.pert_cylinder(q0 - x0, q1 - x1, x0, x1, rx - 1.0)
			check(absf(got[0] - (fq * q0 - fx * x0)) < 1e-12 and absf(got[1] - (fq * q1 - fx * x1)) < 1e-12,
				"cylinder fold, r %s -> %s (got %s)" % [xr, qr, got])


func _flip(v: Array) -> Array:
	return [-v[1], -v[0]] if v[0] + v[1] < 0.0 else [v[0], v[1]]


func _sphere_factor(r2: float, mr2: float, fr2: float) -> float:
	if r2 < mr2:
		return fr2 / mr2
	if r2 < fr2:
		return fr2 / r2
	return 1.0
```

- [ ] **Step 3: Run it, expect FAIL.** `godot4 --headless --path $WT -s tests/perturbation_test.gd` → parse error: `PerturbationPort` not declared.

- [ ] **Step 4: Write the port.** Create `tests/perturbation_port.gd`. Every function mirrors the GLSL function of the same name in Task 5 (`mb_rot_plane` → `rot_plane`, `kifs_rot1/2` → `kifs_rot(p, 0/1)`, `kifs_rot1_on/2_on` → `kifs_rot_on(0/1)`):

```gdscript
class_name PerturbationPort
extends RefCounted
## A GDScript port of the shader's perturbed march (src/fractal/perturbation.gdshaderinc)
## and of its direct estimate (de() and the per-shape orbit loops in
## mandelbox.gdshader, kifs.gdshaderinc, kleinian.gdshaderinc), for
## tests/perturbation_test.gd. Each function mirrors the GLSL function of the same
## name; keep the two in step.
##
## f32 = true runs it as the GPU would: every arithmetic result is rounded to the
## nearest 32-bit float (r()) and every uniform is read as a 32-bit float (u()).
## A sum, difference, product, quotient or square root of two 32-bit floats worked
## out in 64-bit and rounded once is exactly the 32-bit IEEE result, so for those
## operations the emulation is exact (cos, sin and pow are the 64-bit results
## rounded, close to a GPU's but not bit-identical). f32 = false runs the same
## code in 64-bit: the algebra check.
##
## 4-vectors are Arrays of four floats. `orbit` is the reference orbit (its
## a, b, c, d, points, rec64, points64) and `k` its pert_iters: together they
## stand for the pert_* uniforms. Octahedral folds and the polyfold are not
## ported (they are never perturbed).

const PLANES := DistanceEstimator.PLANES

var f32 := true
var params: FractalParams
## The shader's `eye` uniform: the 64-bit eye, rounded when f32.
var eye: Array = [0.0, 0.0, 0.0]
## How many times the pixel and the reference fell on different sides of a
## crease, by kind: "clamp", "abs", "sort_p", "sort_r", "diag_p", "diag_r",
## "menger", "sphere", "cylinder", "inversion". The algebra check's coverage.
var crossings := {}
## While true, each perturbed iteration appends a copy of the offset to `trace`.
var tracing := false
var trace: Array = []

var _buf := PackedFloat32Array([0.0])


func _init(p: FractalParams, eye64: PackedFloat64Array, use_f32: bool) -> void:
	params = p
	f32 = use_f32
	eye = [r(eye64[0]), r(eye64[1]), r(eye64[2])]


## One arithmetic result, rounded to the nearest 32-bit float when f32.
func r(x: float) -> float:
	if not f32:
		return x
	_buf[0] = x
	return _buf[0]


## A uniform's value as the shader holds it.
func u(x: float) -> float:
	return r(x)


func _count(kind: String) -> void:
	crossings[kind] = int(crossings.get(kind, 0)) + 1


# ------------------------------------------------------------- vectors, in GLSL's order

func add4(a: Array, b: Array) -> Array:
	return [r(a[0] + b[0]), r(a[1] + b[1]), r(a[2] + b[2]), r(a[3] + b[3])]


func scale4(s: float, a: Array) -> Array:
	return [r(s * a[0]), r(s * a[1]), r(s * a[2]), r(s * a[3])]


## dot(a, b) = ((a.x b.x + a.y b.y) + a.z b.z) + a.w b.w
func dot4(a: Array, b: Array) -> float:
	return r(r(r(r(a[0] * b[0]) + r(a[1] * b[1])) + r(a[2] * b[2])) + r(a[3] * b[3]))


func dot2(a0: float, a1: float, b0: float, b1: float) -> float:
	return r(r(a0 * b0) + r(a1 * b1))


func length4(a: Array) -> float:
	return r(sqrt(dot4(a, a)))


# ------------------------------------------------------------- the record as the shader reads it

## pert_a..d[i] (32-bit) when f32, the 64-bit copy otherwise. slot 0..3 = a..d.
func rec(orbit, i: int, slot: int) -> Array:
	if f32:
		var arrs := [orbit.a, orbit.b, orbit.c, orbit.d]
		var v: Vector4 = arrs[slot][i]
		return [v.x, v.y, v.z, v.w]
	var base := (i * 4 + slot) * 4
	return [orbit.rec64[base], orbit.rec64[base + 1], orbit.rec64[base + 2], orbit.rec64[base + 3]]


## X_i (pert_end is X_k).
func point(orbit, i: int) -> Array:
	if f32:
		var v: Vector4 = orbit.points[i]
		return [v.x, v.y, v.z, v.w]
	return [orbit.points64[i * 4], orbit.points64[i * 4 + 1], orbit.points64[i * 4 + 2], orbit.points64[i * 4 + 3]]


# ------------------------------------------------------------- the direct estimate (today's shader)

## mb_rot_plane(p, a, b, deg): a' = a cos - b sin, b' = a sin + b cos.
func rot_plane(p: Array, ia: int, ib: int, deg: float) -> Array:
	var rad := r(u(deg) * r(PI / 180.0))
	var c := r(cos(rad))
	var s := r(sin(rad))
	var pa: float = p[ia]
	var pb: float = p[ib]
	var q := p.duplicate()
	q[ia] = r(r(pa * c) - r(pb * s))
	q[ib] = r(r(pa * s) + r(pb * c))
	return q


func mb_rotating() -> bool:
	return (absf(params.iter_rot_xy) + absf(params.iter_rot_xz) + absf(params.iter_rot_xw)
		+ absf(params.iter_rot_yz) + absf(params.iter_rot_yw) + absf(params.iter_rot_zw)) > 1e-6


func mb_iter_rotate(p: Array) -> Array:
	p = rot_plane(p, 0, 1, params.iter_rot_xy)
	p = rot_plane(p, 0, 2, params.iter_rot_xz)
	p = rot_plane(p, 0, 3, params.iter_rot_xw)
	p = rot_plane(p, 1, 2, params.iter_rot_yz)
	p = rot_plane(p, 1, 3, params.iter_rot_yw)
	p = rot_plane(p, 2, 3, params.iter_rot_zw)
	return p


## clamp(p, lo, hi) * 2.0 - p (the doubling is exact).
func _clamp_fold(p: Array, lo: float, hi: float) -> Array:
	return [r(clampf(p[0], lo, hi) * 2.0 - p[0]), r(clampf(p[1], lo, hi) * 2.0 - p[1]),
		r(clampf(p[2], lo, hi) * 2.0 - p[2]), r(clampf(p[3], lo, hi) * 2.0 - p[3])]


## mb_fold(p, i): the hybrid fold on a hybrid iteration, else the cylinder or box fold.
func mb_fold(p: Array, i: int) -> Array:
	var L := u(params.fold_limit)
	if params.hybrid_mix > 0.0:
		var every := maxi(params.hybrid_every, 1)
		if i % every == every - 1:
			var mix := u(params.hybrid_mix)
			var lo := r(-L * r(1.0 - mix))
			var hi := r(r(L + mix) / maxf(r(1.0 - mix), u(1e-6)))
			return _clamp_fold(p, lo, hi)
	if params.fold_shape == MandelboxShape.FoldShape.CYLINDER:
		var q := p.duplicate()
		var rr := r(sqrt(dot2(p[0], p[1], p[0], p[1])))
		if rr > L:
			var f := r(r(r(2.0 * L) - rr) / rr)
			q[0] = r(q[0] * f)
			q[1] = r(q[1] * f)
		q[2] = r(clampf(p[2], -L, L) * 2.0 - p[2])
		q[3] = r(clampf(p[3], -L, L) * 2.0 - p[3])
		return q
	assert(params.fold_shape == MandelboxShape.FoldShape.BOX, "the octahedral fold is not ported")
	return _clamp_fold(p, -L, L)


## mb_sphere_fold: returns [p, dz].
func mb_sphere_fold(p: Array, dz: float) -> Array:
	var r2 := dot4(p, p)
	var mr2 := maxf(r(u(params.min_radius) * u(params.min_radius)), u(1e-12))
	var fr2 := maxf(r(u(params.fixed_radius) * u(params.fixed_radius)), u(1e-12))
	if r2 < mr2:
		var f := r(fr2 / mr2)
		return [scale4(f, p), r(dz * f)]
	if r2 < fr2:
		var f := r(fr2 / maxf(r2, u(1e-12)))
		return [scale4(f, p), r(dz * f)]
	return [p, dz]


## mb_step: returns [z, dz].
func mb_step(z: Array, dz: float, c: Array, rotating: bool, i: int) -> Array:
	if params.fold_order == 0:
		z = mb_fold(z, i)
		var sf := mb_sphere_fold(z, dz)
		z = sf[0]
		dz = sf[1]
	else:
		var sf := mb_sphere_fold(z, dz)
		z = sf[0]
		dz = sf[1]
		z = mb_fold(z, i)
	if rotating:
		z = mb_iter_rotate(z)
	var s := r(u(params.box_scale) + r(u(params.scale_drift) * float(i)))
	z = add4(scale4(s, z), c)
	dz = r(r(dz * absf(s)) + 1.0)
	return [z, dz]


func mb_constant(z0: Array) -> Array:
	var j := params.julia_all
	return [u(params.c_0) if (j or params.julia_0) else z0[0], u(params.c_1) if (j or params.julia_1) else z0[1],
		u(params.c_2) if (j or params.julia_2) else z0[2], u(params.c_3) if (j or params.julia_3) else z0[3]]


## mb_orbit(z, dz, c, first, iters): iterations first..iters-1. Returns [z, dz].
func mb_orbit(z: Array, dz: float, c: Array, first: int, iters: int) -> Array:
	var rotating := mb_rotating()
	for i in range(first, 32):
		if i >= iters:
			break
		var st := mb_step(z, dz, c, rotating, i)
		z = st[0]
		dz = st[1]
	return [z, dz]


func kifs_rot_on(which: int) -> bool:
	var sum := 0.0
	for id in KifsEstimator.ROT_IDS[which]:
		sum += absf(float(params.get(id)))
	return sum > 1e-6


## kifs_rot1 (which 0) or kifs_rot2 (which 1).
func kifs_rot(p: Array, which: int) -> Array:
	var ids: Array = KifsEstimator.ROT_IDS[which]
	for j in 6:
		p = rot_plane(p, PLANES[j][0], PLANES[j][1], float(params.get(ids[j])))
	return p


func menger_fold(p: Array) -> Array:
	var q := [absf(p[0]), absf(p[1]), absf(p[2]), absf(p[3])]
	if q[0] < q[1]:
		var t: float = q[0]; q[0] = q[1]; q[1] = t
	if q[0] < q[2]:
		var t: float = q[0]; q[0] = q[2]; q[2] = t
	if q[1] < q[2]:
		var t: float = q[1]; q[1] = q[2]; q[2] = t
	return q


func kifs_diagonal_fold(p: Array) -> Array:
	var q := p.duplicate()
	for pair in [[0, 1], [0, 2], [1, 2], [0, 3]]:
		var ia: int = pair[0]
		var ib: int = pair[1]
		if r(q[ia] + q[ib]) < 0.0:
			var t: float = q[ia]
			q[ia] = -q[ib]
			q[ib] = -t
	return q


## kifs_orbit(p, n, first, iters): returns [p, n].
func kifs_orbit(p: Array, n: int, first: int, iters: int) -> Array:
	var s := u(params.kifs_scale)
	var o := [u(params.kifs_offset_0), u(params.kifs_offset_1), u(params.kifs_offset_2), u(params.kifs_offset_3)]
	var sm1 := r(s - 1.0)
	var rot1 := kifs_rot_on(0)
	var rot2 := kifs_rot_on(1)
	for i in range(first, 32):
		if i >= iters:
			break
		if rot1:
			p = kifs_rot(p, 0)
		if params.kifs_fold == KifsEstimator.FoldSet.DIAGONAL:
			p = kifs_diagonal_fold(p)
		else:
			assert(params.kifs_fold == KifsEstimator.FoldSet.COORDINATE, "the polyfold is not ported")
			p = menger_fold(p)
		if rot2:
			p = kifs_rot(p, 1)
		if params.kifs_twist != 0.0:
			p = rot_plane(p, 0, 1, r(u(params.kifs_twist) * float(i)))
		p = [r(r(s * p[0]) - r(sm1 * o[0])), r(r(s * p[1]) - r(sm1 * o[1])),
			r(r(s * p[2]) - r(sm1 * o[2])), r(r(s * p[3]) - r(sm1 * o[3]))]
		if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
			var t := r(o[2] * sm1)
			if p[2] < -0.5 * t:
				p[2] = r(p[2] + t)
		n = i + 1
		if dot4(p, p) > 1.0e6:
			break
	return [p, n]


func kifs_distance(p: Array, n: int) -> float:
	var d := 0.0
	if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
		var q := [r(absf(p[0]) - 1.0), r(absf(p[1]) - 1.0), r(absf(p[2]) - 1.0), r(absf(p[3]) - 1.0)]
		var outside := [maxf(q[0], 0.0), maxf(q[1], 0.0), maxf(q[2], 0.0), maxf(q[3], 0.0)]
		var inside := maxf(maxf(q[0], q[1]), maxf(q[2], q[3]))
		d = r(length4(outside) + minf(inside, 0.0))
	else:
		d = length4(p)
	return r(d * r(pow(u(params.kifs_scale), -float(n))))


## kleinian_orbit(p, dr, first, iters): returns [p, dr].
func kleinian_orbit(p: Array, dr: float, first: int, iters: int) -> Array:
	var b := [u(params.kleinian_box_0), u(params.kleinian_box_1), u(params.kleinian_box_2), u(params.kleinian_box_3)]
	var sh := [u(params.kleinian_shift_0), u(params.kleinian_shift_1), u(params.kleinian_shift_2), u(params.kleinian_shift_3)]
	var k := r(u(params.kleinian_radius) * u(params.kleinian_radius))
	for i in range(first, 32):
		if i >= iters:
			break
		var before := p.duplicate()
		var q := []
		for j in 4:
			q.append(r(clampf(p[j], -b[j], b[j]) * 2.0 - p[j]))
		var m := maxf(r(k / maxf(dot4(q, q), u(1e-12))), 1.0)
		p = [r(r(q[0] * m) + sh[0]), r(r(q[1] * m) + sh[1]), r(r(q[2] * m) + sh[2]), r(r(q[3] * m) + sh[3])]
		dr = r(dr * m)
		if p == before:
			break
	return [p, dr]


func kleinian_distance(p: Array, dr: float) -> float:
	var rxy := r(sqrt(dot2(p[0], p[1], p[0], p[1])))
	var t := u(params.kleinian_thickness)
	var num := r(0.5 * r(absf(r(rxy * p[2])) - t))
	return r(absf(r(num / r(sqrt(r(dot4(p, p) + absf(t)))))) / dr)


## de(pos, iters): today's direct estimate at a 32-bit point (no noise).
func de_direct(pos: Array, iters: int) -> float:
	var z0 := [pos[0], pos[1], pos[2], u(params.w)]
	if params.shape == FractalParams.Shape.KIFS:
		var kr := kifs_orbit(z0, 0, 0, iters)
		return kifs_distance(kr[0], kr[1])
	if params.shape == FractalParams.Shape.KLEINIAN:
		var lr := kleinian_orbit(z0, 1.0, 0, iters)
		return kleinian_distance(lr[0], lr[1])
	var mr := mb_orbit(z0.duplicate(), 1.0, mb_constant(z0), 0, iters)
	return r(length4(mr[0]) / absf(mr[1]))


# ------------------------------------------------------------- the perturbed steps

## -1 below [lo, hi], 0 inside, 1 above (for the crossing counts).
static func _side(v: float, lo: float, hi: float) -> int:
	return -1 if v < lo else (1 if v > hi else 0)


## pert_clamp, one component: 2 (clamp(d, glo, ghi) - clamp(0, glo, ghi)) - d.
func pert_clamp1(d: float, glo: float, ghi: float, kind: String) -> float:
	if _side(0.0, glo, ghi) != _side(d, glo, ghi):
		_count(kind)
	var t := r(clampf(d, glo, ghi) - clampf(0.0, glo, ghi))
	return r(2.0 * t - d)


func pert_clamp(dl: Array, glo: Array, ghi: Array, kind: String) -> Array:
	return [pert_clamp1(dl[0], glo[0], ghi[0], kind), pert_clamp1(dl[1], glo[1], ghi[1], kind),
		pert_clamp1(dl[2], glo[2], ghi[2], kind), pert_clamp1(dl[3], glo[3], ghi[3], kind)]


## pert_abs: 2 (max(d, g) - max(0, g)) - d, g = -X (the clamp with no upper crease).
func pert_abs(dl: Array, g: Array) -> Array:
	var out := []
	for j in 4:
		var d: float = dl[j]
		var gj: float = g[j]
		if (gj > 0.0) != (d < gj):
			_count("abs")
		var t := r(maxf(d, gj) - maxf(0.0, gj))
		out.append(r(2.0 * t - d))
	return out


## pert_swap: one compare-and-swap of the sort on (da, db), g = X_a - X_b. [da', db'].
func pert_swap(da: float, db: float, g: float) -> Array:
	var ps := r(da - db) < -g
	var rs := g < 0.0
	if ps and rs:
		return [db, da]
	if ps:
		_count("sort_p")
		return [r(db - g), r(da + g)]
	if rs:
		_count("sort_r")
		return [r(da + g), r(db - g)]
	return [da, db]


func pert_sort(dl: Array, g: Array) -> Array:
	var q := dl.duplicate()
	var s := pert_swap(q[0], q[1], g[0])
	q[0] = s[0]; q[1] = s[1]
	s = pert_swap(q[0], q[2], g[1])
	q[0] = s[0]; q[2] = s[1]
	s = pert_swap(q[1], q[2], g[2])
	q[1] = s[0]; q[2] = s[1]
	return q


## pert_flip: one diagonal reflection on (da, db), g = X_a + X_b. [da', db'].
func pert_flip(da: float, db: float, g: float) -> Array:
	var ps := r(da + db) < -g
	var rs := g < 0.0
	if ps and rs:
		return [-db, -da]
	if ps:
		_count("diag_p")
		return [r(-g - db), r(-g - da)]
	if rs:
		_count("diag_r")
		return [r(da + g), r(db + g)]
	return [da, db]


func pert_diagonal(dl: Array, g: Array) -> Array:
	var q := dl.duplicate()
	var s := pert_flip(q[0], q[1], g[0])
	q[0] = s[0]; q[1] = s[1]
	s = pert_flip(q[0], q[2], g[1])
	q[0] = s[0]; q[2] = s[1]
	s = pert_flip(q[1], q[2], g[2])
	q[1] = s[0]; q[2] = s[1]
	s = pert_flip(q[0], q[3], g[3])
	q[0] = s[0]; q[3] = s[1]
	return q


## pert_menger: dz + t ([dz < -g] - [g < 0]), g = X_z + t/2 after the scale.
func pert_menger(dz: float, g: float, t: float) -> float:
	var pc := dz < -g
	var rc := g < 0.0
	if pc != rc:
		_count("menger")
	return r(dz + r(t * ((1.0 if pc else 0.0) - (1.0 if rc else 0.0))))


## pert_sphere: returns [dl', dz']. See the regime table in the plan / shader.
func pert_sphere(dl: Array, dz: float, X: Array, gmin: float, gfix: float, mr2: float, fr2: float, kind: String) -> Array:
	var q := r(r(2.0 * dot4(X, dl)) + dot4(dl, dl))
	var x2 := dot4(X, X)
	var p2 := r(x2 + q)
	var gqmin := r(gmin + q)
	var gqfix := r(gfix + q)
	var rx := 0 if gmin < 0.0 else (1 if gfix < 0.0 else 2)
	var rp := 0 if gqmin < 0.0 else (1 if gqfix < 0.0 else 2)
	if rx != rp:
		_count(kind)
	var mp := 1.0
	if rp == 0:
		mp = r(fr2 / mr2)
	elif rp == 1:
		mp = r(fr2 / maxf(p2, u(1e-12)))
	var dm := 0.0
	if rx == 1 and rp == 1:
		dm = r(r(-fr2 * q) / r(p2 * x2))
	elif rx == 0 and rp == 1:
		dm = r(r(-fr2 * gqmin) / r(p2 * mr2))
	elif rx == 1 and rp == 0:
		dm = r(r(fr2 * gmin) / r(mr2 * x2))
	elif rx == 1 and rp == 2:
		dm = r(gfix / x2)
	elif rx == 2 and rp == 1:
		dm = r(-gqfix / p2)
	elif rx == 0 and rp == 2:
		dm = r(1.0 - r(fr2 / mr2))
	elif rx == 2 and rp == 0:
		dm = r(r(fr2 / mr2) - 1.0)
	return [add4(scale4(mp, dl), scale4(dm, X)), r(dz * mp)]


## pert_cylinder: the cylinder fold's xy pair. X = the reference's xy (record a.xy),
## g = r - L (record d.w). Returns [dx', dy'].
func pert_cylinder(d0: float, d1: float, X0: float, X1: float, g: float) -> Array:
	var L := u(params.fold_limit)
	var rr := r(L + g)
	var q := r(r(2.0 * dot2(X0, X1, d0, d1)) + dot2(d0, d1, d0, d1))
	var rp := r(sqrt(maxf(r(r(rr * rr) + q), 0.0)))
	var dr := r(q / maxf(r(rp + rr), u(1e-30)))
	var gdr := r(g + dr)
	var xo := g > 0.0
	var po := gdr > 0.0
	if xo != po:
		_count("cylinder")
	var mp := r(r(r(2.0 * L) - rp) / rp) if po else 1.0
	var dm := 0.0
	if xo and po:
		dm = r(r(r(-2.0 * L) * dr) / r(rr * rp))
	elif po:
		dm = r(r(-2.0 * gdr) / rp)
	elif xo:
		dm = r(r(2.0 * g) / rr)
	return [r(r(mp * d0) + r(X0 * dm)), r(r(mp * d1) + r(X1 * dm))]


## pert_mb_fold: the Mandelbox fold step on the offset.
func pert_mb_fold(dl: Array, ra: Array, rb: Array, gr: float, i: int) -> Array:
	var hybrid := false
	if params.hybrid_mix > 0.0:
		var every := maxi(params.hybrid_every, 1)
		hybrid = i % every == every - 1
	if params.fold_shape == MandelboxShape.FoldShape.CYLINDER and not hybrid:
		var xy := pert_cylinder(dl[0], dl[1], ra[0], ra[1], gr)
		return [xy[0], xy[1], pert_clamp1(dl[2], ra[2], rb[2], "clamp"), pert_clamp1(dl[3], ra[3], rb[3], "clamp")]
	return pert_clamp(dl, ra, rb, "clamp")


# ------------------------------------------------------------- de_pert

## de_pert(off, iters): the estimate at eye + off without forming that sum. k
## perturbed iterations from the record, then the ordinary loop from X_k + dl
## up to max(iters, k). No noise (the tests have none).
func de_pert(orbit, k: int, off: Array, iters: int) -> float:
	var dl := [r(off[0]), r(off[1]), r(off[2]), 0.0]
	var p := [r(eye[0] + dl[0]), r(eye[1] + dl[1]), r(eye[2] + dl[2])]
	if params.shape == FractalParams.Shape.KIFS:
		return de_pert_kifs(orbit, k, dl, iters)
	if params.shape == FractalParams.Shape.KLEINIAN:
		return de_pert_kleinian(orbit, k, dl, iters)
	return de_pert_mandelbox(orbit, k, dl, p, iters)


func de_pert_mandelbox(orbit, k: int, dl: Array, p: Array, iters: int) -> float:
	var j := params.julia_all
	var dc := [0.0 if (j or params.julia_0) else dl[0], 0.0 if (j or params.julia_1) else dl[1],
		0.0 if (j or params.julia_2) else dl[2], 0.0]
	var mr2 := maxf(r(u(params.min_radius) * u(params.min_radius)), u(1e-12))
	var fr2 := maxf(r(u(params.fixed_radius) * u(params.fixed_radius)), u(1e-12))
	var dz := 1.0
	var rotating := mb_rotating()
	for i in k:
		var ra := rec(orbit, i, 0)
		var rb := rec(orbit, i, 1)
		var rc := rec(orbit, i, 2)
		var rd := rec(orbit, i, 3)
		if params.fold_order == 0:
			dl = pert_mb_fold(dl, ra, rb, rd[3], i)
			var sf := pert_sphere(dl, dz, rc, rd[0], rd[1], mr2, fr2, "sphere")
			dl = sf[0]
			dz = sf[1]
		else:
			var sf := pert_sphere(dl, dz, rc, rd[0], rd[1], mr2, fr2, "sphere")
			dl = sf[0]
			dz = sf[1]
			dl = pert_mb_fold(dl, ra, rb, rd[3], i)
		if rotating:
			dl = mb_iter_rotate(dl)
		var s := r(u(params.box_scale) + r(u(params.scale_drift) * float(i)))
		dl = add4(scale4(s, dl), dc)
		dz = r(r(dz * absf(s)) + 1.0)
		if tracing:
			trace.append(dl.duplicate())
	var z := add4(point(orbit, k), dl)
	var c := mb_constant([p[0], p[1], p[2], u(params.w)])
	var res := mb_orbit(z, dz, c, k, maxi(iters, k))
	return r(length4(res[0]) / absf(res[1]))


func de_pert_kifs(orbit, k: int, dl: Array, iters: int) -> float:
	var s := u(params.kifs_scale)
	var oz := u(params.kifs_offset_2)
	var t := r(oz * r(s - 1.0))
	var rot1 := kifs_rot_on(0)
	var rot2 := kifs_rot_on(1)
	var n := 0
	for i in k:
		if rot1:
			dl = kifs_rot(dl, 0)
		if params.kifs_fold == KifsEstimator.FoldSet.DIAGONAL:
			dl = pert_diagonal(dl, rec(orbit, i, 1))
		else:
			dl = pert_sort(pert_abs(dl, rec(orbit, i, 0)), rec(orbit, i, 1))
		if rot2:
			dl = kifs_rot(dl, 1)
		if params.kifs_twist != 0.0:
			dl = rot_plane(dl, 0, 1, r(u(params.kifs_twist) * float(i)))
		dl = scale4(s, dl)
		if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
			dl[2] = pert_menger(dl[2], rec(orbit, i, 2)[0], t)
		if tracing:
			trace.append(dl.duplicate())
		n = i + 1
		var zi := add4(rec(orbit, i, 3), dl)
		if dot4(zi, zi) > 1.0e6:
			return kifs_distance(zi, n)
	var res := kifs_orbit(add4(point(orbit, k), dl), n, k, maxi(iters, k))
	return kifs_distance(res[0], res[1])


func de_pert_kleinian(orbit, k: int, dl: Array, iters: int) -> float:
	var kk := r(u(params.kleinian_radius) * u(params.kleinian_radius))
	var dr := 1.0
	for i in k:
		dl = pert_clamp(dl, rec(orbit, i, 0), rec(orbit, i, 1), "clamp")
		var sf := pert_sphere(dl, dr, rec(orbit, i, 2), 1.0e30, rec(orbit, i, 3)[0], kk, kk, "inversion")
		dl = sf[0]
		dr = sf[1]
		if tracing:
			trace.append(dl.duplicate())
	var res := kleinian_orbit(add4(point(orbit, k), dl), dr, k, maxi(iters, k))
	return kleinian_distance(res[0], res[1])
```

- [ ] **Step 5: Run, expect PASS** for the emulation and case checks (about 45 checks): `godot4 --headless --import --path $WT >/dev/null 2>&1; godot4 --headless --path $WT -s tests/perturbation_test.gd`. If a case fails, the formula in the port is wrong: fix the port, not the expectation (the expectations are the direct difference).

- [ ] **Step 6: Add the algebra check to the test.** In `run()`, after `_check_cases()`, add `_check_algebra()`, and append:

```gdscript
# ------------------------------------------------------------- 2. whole orbits, 64-bit

## For every perturbable variant: an eye 1e-3 short of its surface, the reference
## orbit X there, and SAMPLES random offsets of 1e-7 to 1e-1 (big enough to cross
## every kind of crease). In 64-bit the perturbed offset after each iteration must
## be P_i - X_i, where P is the direct orbit of eye + off; the tolerance allows
## rounding (about 1e-16 x the magnification) but not a wrong formula (off by
## about the offset itself). Then every crossing kind must have happened.
func _check_algebra() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var by_shape := {}
	for v in SurfaceFixture.variants():
		if not v[3]:
			continue
		var name: String = v[0]
		var params: FractalParams = v[1]
		var s := SurfaceFixture.surface_from(params, v[2])
		var e := SurfaceFixture.backed(s, 1e-3)
		var X := ReferenceOrbitDraft.build(params, e[0], e[1], e[2])
		var k := mini(ReferenceOrbitDraft.PERT_MAX, X.n)
		var port := PerturbationPort.new(params, e, false)
		var worst := 0.0
		var worst_de := 0.0
		for _j in SAMPLES:
			var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var size := pow(10.0, rng.randf_range(-7.0, -1.0))
			var off := [dir.x * size, dir.y * size, dir.z * size]
			var P := ReferenceOrbitDraft.build(params, e[0] + off[0], e[1] + off[1], e[2] + off[2])
			port.trace = []
			port.tracing = true
			var dp := port.de_pert(X, k, off, 32)
			for i in port.trace.size():
				if i + 1 > P.n:
					break
				var dl: Array = port.trace[i]
				var err := 0.0
				var dmax := 0.0
				var xmax := 1.0
				for c in 4:
					var xv: float = X.points64[(i + 1) * 4 + c]
					var pv: float = P.points64[(i + 1) * 4 + c]
					err = maxf(err, absf(dl[c] - (pv - xv)))
					dmax = maxf(dmax, absf(pv - xv))
					xmax = maxf(xmax, maxf(absf(xv), absf(pv)))
				var tol := 1e-12 * X.mag[i + 1] * xmax + 1e-9 * dmax
				worst = maxf(worst, err / tol)
			worst_de = maxf(worst_de, absf(dp - P.distance) / maxf(absf(P.distance), 1e-300))
		check(worst <= 1.0, "%s: the 64-bit perturbed offset is the direct orbit's, iteration by iteration (worst %s of tolerance)" % [name, worst])
		# after the handoff both orbits run on in 64-bit through up to 32 - k more
		# iterations, which amplify round-off chaotically (measured up to 7e-5), so the
		# bar here is the march's own agreement, 0.1%
		check(worst_de <= AGREE_T, "%s: and the estimate after the handoff is the direct one within 0.1%% (worst relative difference %s)" % [name, worst_de])
		var merged: Dictionary = by_shape.get(params.shape, {})
		for kind in port.crossings:
			merged[kind] = int(merged.get(kind, 0)) + int(port.crossings[kind])
		by_shape[params.shape] = merged
	print("crossings by shape: ", by_shape)
	var want := {
		FractalParams.Shape.MANDELBOX: ["clamp", "sphere", "cylinder"],
		FractalParams.Shape.KIFS: ["abs", "sort_p", "sort_r", "menger", "diag_p", "diag_r"],
		FractalParams.Shape.KLEINIAN: ["clamp", "inversion"],
	}
	for shape in want:
		for kind in want[shape]:
			check(int(by_shape.get(shape, {}).get(kind, 0)) > 0,
				"shape %d: the sample crossed a '%s' crease somewhere (coverage)" % [shape, kind])
```

- [ ] **Step 7: Run, expect FAIL**: parse error, `ReferenceOrbitDraft` not declared.

- [ ] **Step 8: Write the record builder.** Create `tests/reference_orbit_draft.gd`. It mirrors `DistanceEstimator.mandelbox_at`, `KifsEstimator.estimate_at` and `KleinianEstimator.estimate_at` operation for operation (same expressions, same order), so `distance` equals theirs exactly; the record and `mag` are computed beside the orbit and never feed back into it.

```gdscript
class_name ReferenceOrbitDraft
extends RefCounted
## DRAFT, moved to src/fractal/reference_orbit.gd as ReferenceOrbit in Task 3.
##
## The camera's own orbit, iterated in 64-bit on the CPU from the 64-bit eye, and
## the per-iteration record the shader's perturbed march reads
## (src/fractal/perturbation.gdshaderinc). The record holds, for each of the first
## PERT_MAX iterations, the gaps between the reference point X and each fold's
## creases (crease minus X, worked out in 64-bit). A gap is small exactly when
## precision matters, and a 32-bit float holds a small number to the same
## relative precision as a large one, so the GPU can tell which side of a crease
## a pixel lands on without forming the pixel's point.
##
##   var orbit := ReferenceOrbit.build(params, ex, ey, ez)
##   orbit.distance   # == DistanceEstimator.estimate_at(ex, ey, ez, params), exactly
##   orbit.n          # iterations run before a KIFS bailout or a Kleinian fixed point (32 otherwise)
##   orbit.mag        # λ_0 .. λ_32 (λ_0 = 1): how much the orbit has magnified after i iterations
##   orbit.points     # X_0 .. X_32 as 32-bit Vector4s (X_k is the handoff point, pert_end)
##   orbit.a, .b, .c, .d   # the record, PERT_MAX Vector4s each (layout: see the shader's header)
##   orbit.perturbable     # false for the octahedral fold, the polyfold and the Mandelbulb
##
## The shader reads 32-bit copies; points64 and rec64 keep the 64-bit values for
## the algebra check (tests/perturbation_test.gd). rec64 index: (i * 4 + slot) * 4
## + component, slot 0..3 = a..d.

const ITERATIONS := 32
## The uniform arrays' length: at most this many iterations are perturbed.
const PERT_MAX := 20
const PLANES := DistanceEstimator.PLANES

var eye := PackedFloat64Array([0.0, 0.0, 0.0])
var distance := 0.0
var n := ITERATIONS
var perturbable := false
var mag := PackedFloat64Array()
var points := PackedVector4Array()
var points64 := PackedFloat64Array()
var a := PackedVector4Array()
var b := PackedVector4Array()
var c := PackedVector4Array()
var d := PackedVector4Array()
var rec64 := PackedFloat64Array()


static func build(params: FractalParams, ex: float, ey: float, ez: float) -> ReferenceOrbitDraft:
	var o := ReferenceOrbitDraft.new()
	o.eye = PackedFloat64Array([ex, ey, ez])
	o.mag.resize(ITERATIONS + 1)
	o.mag.fill(1.0)
	o.points64.resize((ITERATIONS + 1) * 4)
	o.points64.fill(0.0)
	o.rec64.resize(PERT_MAX * 16)
	o.rec64.fill(0.0)
	match params.shape:
		FractalParams.Shape.KIFS:
			o._kifs(params, ex, ey, ez)
		FractalParams.Shape.KLEINIAN:
			o._kleinian(params, ex, ey, ez)
		FractalParams.Shape.MANDELBULB:
			o._mandelbulb(params, ex, ey, ez)
		_:
			o._mandelbox(params, ex, ey, ez)
	o._pack()
	return o


# ------------------------------------------------------------- Mandelbox

func _mandelbox(params: FractalParams, px: float, py: float, pz: float) -> void:
	var scale := params.box_scale
	var drift := params.scale_drift
	var fold_shape := params.fold_shape
	var mix := params.hybrid_mix
	var every := maxi(params.hybrid_every, 1)
	var mr2 := params.min_radius * params.min_radius
	var fr2 := params.fixed_radius * params.fixed_radius
	var fold := params.fold_limit
	var fold_order := params.fold_order
	perturbable = fold_shape != MandelboxShape.FoldShape.OCTAHEDRAL

	var z0 := [px, py, pz, params.w]
	var cst := [
		params.c_0 if (params.julia_all or params.julia_0) else z0[0],
		params.c_1 if (params.julia_all or params.julia_1) else z0[1],
		params.c_2 if (params.julia_all or params.julia_2) else z0[2],
		params.c_3 if (params.julia_all or params.julia_3) else z0[3],
	]
	var angles := [params.iter_rot_xy, params.iter_rot_xz, params.iter_rot_xw,
		params.iter_rot_yz, params.iter_rot_yw, params.iter_rot_zw]
	var rotating := false
	for ang in angles:
		if absf(ang) > 1e-6:
			rotating = true
			break
	var cosv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var sinv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if rotating:
		for j in 6:
			var rad := deg_to_rad(angles[j])
			cosv[j] = cos(rad)
			sinv[j] = sin(rad)

	var z := [z0[0], z0[1], z0[2], z0[3]]
	var dz := 1.0
	var lam := 1.0
	_set_point(0, z)
	for i in ITERATIONS:
		var hybrid := mix > 0.0 and i % every == every - 1
		var keep := i < PERT_MAX
		if fold_order == 0:
			if keep:
				_fold_record(i, z, fold, fold_shape, hybrid, mix)
			DistanceEstimator._fold(z, fold, fold_shape, hybrid, mix)
			lam *= _sphere_record(i, z, mr2, fr2, keep)
			dz = DistanceEstimator._sphere_fold(z, dz, mr2, fr2)
		else:
			lam *= _sphere_record(i, z, mr2, fr2, keep)
			dz = DistanceEstimator._sphere_fold(z, dz, mr2, fr2)
			if keep:
				_fold_record(i, z, fold, fold_shape, hybrid, mix)
			DistanceEstimator._fold(z, fold, fold_shape, hybrid, mix)
		if rotating:
			for j in 6:
				DistanceEstimator._rot_plane(z, PLANES[j][0], PLANES[j][1], cosv[j], sinv[j])
		var s := scale + drift * i
		z[0] = s * z[0] + cst[0]
		z[1] = s * z[1] + cst[1]
		z[2] = s * z[2] + cst[2]
		z[3] = s * z[3] + cst[3]
		dz = dz * absf(s) + 1.0
		lam *= absf(s)
		mag[i + 1] = lam
		_set_point(i + 1, z)
	n = ITERATIONS
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	distance = sqrt(r2) / absf(dz)


## The fold's gaps for iteration i, from the fold's input point z (see the
## record table in the shader's header).
func _fold_record(i: int, z: Array, fold: float, fold_shape: int, hybrid: bool, mix: float) -> void:
	if hybrid:
		var lo := -fold * (1.0 - mix)
		var hi := (fold + mix) / maxf(1.0 - mix, 1e-6)
		_rec(i, 0, lo - z[0], lo - z[1], lo - z[2], lo - z[3])
		_rec(i, 1, hi - z[0], hi - z[1], hi - z[2], hi - z[3])
	elif fold_shape == MandelboxShape.FoldShape.CYLINDER:
		# a.xy carries the reference's own xy: the radial step needs X, not a gap
		_rec(i, 0, z[0], z[1], -fold - z[2], -fold - z[3])
		_rec(i, 1, 0.0, 0.0, fold - z[2], fold - z[3])
		_rec1(i, 3, 3, sqrt(z[0] * z[0] + z[1] * z[1]) - fold)
	else:
		_rec(i, 0, -fold - z[0], -fold - z[1], -fold - z[2], -fold - z[3])
		_rec(i, 1, fold - z[0], fold - z[1], fold - z[2], fold - z[3])


## The sphere fold's factor at z (the rule DistanceEstimator._sphere_fold
## applies) and, for a recorded iteration, its input point (c) and its gaps and
## factor (d.x, d.y, d.z).
func _sphere_record(i: int, z: Array, mr2: float, fr2: float, keep: bool) -> float:
	var mr := maxf(mr2, 1e-12)
	var fr := maxf(fr2, 1e-12)
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	var f := 1.0
	if r2 < mr:
		f = fr / mr
	elif r2 < fr:
		f = fr / maxf(r2, 1e-12)
	if keep:
		_rec(i, 2, z[0], z[1], z[2], z[3])
		_rec1(i, 3, 0, r2 - mr)
		_rec1(i, 3, 1, r2 - fr)
		_rec1(i, 3, 2, f)
	return f


# ------------------------------------------------------------- KIFS

func _kifs(params: FractalParams, px: float, py: float, pz: float) -> void:
	var s := params.kifs_scale
	var fold_set := params.kifs_fold
	var sector := TAU / float(maxi(int(floor(params.kifs_poly_k + 0.5)), 2))
	var twist := deg_to_rad(params.kifs_twist)
	var o := [params.kifs_offset_0, params.kifs_offset_1, params.kifs_offset_2, params.kifs_offset_3]
	var r1 := KifsEstimator._angles(params, 0)
	var r2 := KifsEstimator._angles(params, 1)
	perturbable = fold_set != KifsEstimator.FoldSet.POLYFOLD

	var p := [px, py, pz, params.w]
	_set_point(0, p)
	n = 0
	var escaped := false
	for i in ITERATIONS:
		# |s|^i whatever the bailout: floor_iter asks what 32 iterations magnify
		mag[i + 1] = pow(absf(s), i + 1)
		if escaped:
			_set_point(i + 1, p)
			continue
		var keep := i < PERT_MAX
		if not r1.is_empty():
			KifsEstimator._rotate(p, r1)
		if fold_set == KifsEstimator.FoldSet.COORDINATE:
			# DistanceEstimator.menger_fold, with the gap taken at each comparison
			if keep:
				_rec(i, 0, -p[0], -p[1], -p[2], -p[3])
			for j in 4:
				p[j] = absf(p[j])
			var g01: float = p[0] - p[1]
			if p[0] < p[1]:
				var t: float = p[0]; p[0] = p[1]; p[1] = t
			var g02: float = p[0] - p[2]
			if p[0] < p[2]:
				var t: float = p[0]; p[0] = p[2]; p[2] = t
			var g12: float = p[1] - p[2]
			if p[1] < p[2]:
				var t: float = p[1]; p[1] = p[2]; p[2] = t
			if keep:
				_rec(i, 1, g01, g02, g12, 0.0)
		elif fold_set == KifsEstimator.FoldSet.DIAGONAL:
			# KifsEstimator._diagonal_fold, with the gap taken at each comparison
			var g := [0.0, 0.0, 0.0, 0.0]
			var pairs := [[0, 1], [0, 2], [1, 2], [0, 3]]
			for j in 4:
				var ia: int = pairs[j][0]
				var ib: int = pairs[j][1]
				g[j] = p[ia] + p[ib]
				if p[ia] + p[ib] < 0.0:
					var t: float = p[ia]
					p[ia] = -p[ib]
					p[ib] = -t
			if keep:
				_rec(i, 1, g[0], g[1], g[2], g[3])
		else:
			KifsEstimator._poly_fold(p, sector)
			DistanceEstimator.menger_fold(p)
		if not r2.is_empty():
			KifsEstimator._rotate(p, r2)
		if twist != 0.0:
			var ang := twist * i
			var cs := cos(ang)
			var sn := sin(ang)
			var x: float = p[0]
			var y: float = p[1]
			p[0] = x * cs - y * sn
			p[1] = x * sn + y * cs
		for j in 4:
			p[j] = s * p[j] - (s - 1.0) * o[j]
		if fold_set == KifsEstimator.FoldSet.COORDINATE:
			var t: float = o[2] * (s - 1.0)
			if keep:
				_rec1(i, 2, 0, p[2] + 0.5 * t)
			if p[2] < -0.5 * t:
				p[2] += t
		if keep:
			_rec(i, 3, p[0], p[1], p[2], p[3])
		_set_point(i + 1, p)
		n = i + 1
		if p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3] > KifsEstimator.BAILOUT2:
			escaped = true
	var dist := 0.0
	if fold_set == KifsEstimator.FoldSet.COORDINATE:
		dist = KifsEstimator._box_distance(p)
	else:
		dist = sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
	distance = dist * pow(s, -float(n))


# ------------------------------------------------------------- Kleinian

func _kleinian(params: FractalParams, px: float, py: float, pz: float) -> void:
	var bx := [params.kleinian_box_0, params.kleinian_box_1, params.kleinian_box_2, params.kleinian_box_3]
	var shift := [params.kleinian_shift_0, params.kleinian_shift_1, params.kleinian_shift_2, params.kleinian_shift_3]
	var k := params.kleinian_radius * params.kleinian_radius
	perturbable = true
	var p := [px, py, pz, params.w]
	var dr := 1.0
	_set_point(0, p)
	n = ITERATIONS
	var settled := false
	for i in ITERATIONS:
		if settled:
			mag[i + 1] = dr
			_set_point(i + 1, p)
			continue
		var keep := i < PERT_MAX
		var before := [p[0], p[1], p[2], p[3]]
		if keep:
			_rec(i, 0, -bx[0] - p[0], -bx[1] - p[1], -bx[2] - p[2], -bx[3] - p[3])
			_rec(i, 1, bx[0] - p[0], bx[1] - p[1], bx[2] - p[2], bx[3] - p[3])
		for j in 4:
			p[j] = clampf(p[j], -bx[j], bx[j]) * 2.0 - p[j]
		var r2: float = p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3]
		var m := maxf(k / maxf(r2, 1e-12), 1.0)
		if keep:
			_rec(i, 2, p[0], p[1], p[2], p[3])
			_rec(i, 3, r2 - k, m, 0.0, 0.0)
		for j in 4:
			p[j] = p[j] * m + shift[j]
		dr *= m
		mag[i + 1] = dr
		_set_point(i + 1, p)
		if p == before:
			n = i + 1
			settled = true
	distance = KleinianEstimator.thingy(p, params.kleinian_thickness) / dr


# ------------------------------------------------------------- Mandelbulb (not perturbed)

func _mandelbulb(params: FractalParams, px: float, py: float, pz: float) -> void:
	perturbable = false
	n = ITERATIONS
	distance = MandelbulbEstimator.estimate_at(px, py, pz, params)
	for i in ITERATIONS + 1:
		_set_point(i, [px, py, pz, 0.0])


# ------------------------------------------------------------- storage

func _set_point(i: int, z: Array) -> void:
	for j in 4:
		points64[i * 4 + j] = z[j]


func _rec(i: int, slot: int, v0: float, v1: float, v2: float, v3: float) -> void:
	var base := (i * 4 + slot) * 4
	rec64[base] = v0
	rec64[base + 1] = v1
	rec64[base + 2] = v2
	rec64[base + 3] = v3


func _rec1(i: int, slot: int, comp: int, v: float) -> void:
	rec64[(i * 4 + slot) * 4 + comp] = v


func _vec(i: int, slot: int) -> Vector4:
	var base := (i * 4 + slot) * 4
	return Vector4(rec64[base], rec64[base + 1], rec64[base + 2], rec64[base + 3])


## The 32-bit copies the shader reads.
func _pack() -> void:
	points.resize(ITERATIONS + 1)
	for i in ITERATIONS + 1:
		points[i] = Vector4(points64[i * 4], points64[i * 4 + 1], points64[i * 4 + 2], points64[i * 4 + 3])
	a.resize(PERT_MAX)
	b.resize(PERT_MAX)
	c.resize(PERT_MAX)
	d.resize(PERT_MAX)
	for i in PERT_MAX:
		a[i] = _vec(i, 0)
		b[i] = _vec(i, 1)
		c[i] = _vec(i, 2)
		d[i] = _vec(i, 3)
```

- [ ] **Step 9: Run, expect PASS** (`--import` first: a new `class_name`). The algebra check prints `crossings by shape: {...}`. If a coverage check fails (a kind never crossed), widen the offsets to `rng.randf_range(-7.0, 0.0)` or raise `SAMPLES` to 96; never drop a kind from `want`. If an iteration check fails, print that variant's first failing iteration and step kind and fix the port's formula there.

- [ ] **Step 10: Add the agreement grid.** In `run()`, after `_check_algebra()`, add `_check_agreement()`, and append:

```gdscript
# ------------------------------------------------------------- 3. the march in float32

## The spec's fixtures: the default box, the ice-field and terraces saves (Julia
## mode), a KIFS (Menger) and a Kleinian. [name, params, surface point].
func _fixtures() -> Array:
	var box := FractalParams.new()
	var out := [["default box", box, SurfaceFixture.default_surface(box)]]
	for v in SurfaceFixture.variants():
		if v[0] in ["ice field", "terraces", "Menger", "Kleinian"]:
			out.append([v[0], v[1], SurfaceFixture.surface_from(v[1], v[2])])
	return out


## 27 directions within the 40° field of view around forward f: a 3 × 3 grid of
## screen offsets at three field fractions (the whole view, its middle third, its
## middle ninth), nudged off-centre so no two coincide. 32-bit, as the GPU's are.
func _fan(f: Vector3) -> Array:
	var right := f.cross(Vector3(0, 0, 1)).normalized()
	var up := right.cross(f).normalized()
	var out := []
	for frac in [1.0, 1.0 / 3.0, 1.0 / 9.0]:
		for ia in [-1, 0, 1]:
			for ib in [-1, 0, 1]:
				var du: float = (ia + 0.37) * 0.5 * frac * FractalView.TAN_HALF_FOV
				var dv: float = (ib + 0.21) * 0.5 * frac * FractalView.TAN_HALF_FOV
				var dir := (f + right * du + up * dv).normalized()
				out.append([dir.x, dir.y, dir.z])
	return out


## [class, t]: class 0 a hit (estimate under eps × t), 1 beyond (t past 10 d),
## 2 out of steps. The 64-bit reference: DistanceEstimator at o + dir t in doubles.
func _march_ref(o: PackedFloat64Array, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := params.precision / params.detail
	var t := 0.0
	for _i in STEPS:
		var de := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if de < eps * t:
			return [0, t]
		t += de
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


## Today's shader in float32: the position eye + dir t formed in 32 bits.
func _march_direct(port: PerturbationPort, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := port.u(params.precision / params.detail)
	var t := 0.0
	for _i in STEPS:
		var pos := [port.r(port.eye[0] + port.r(dir[0] * t)), port.r(port.eye[1] + port.r(dir[1] * t)),
			port.r(port.eye[2] + port.r(dir[2] * t))]
		var de := port.de_direct(pos, 32)
		if de < port.r(eps * t):
			return [0, t]
		t = port.r(t + de)
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


## The perturbed shader in float32: only the offset dir t is formed.
func _march_pert(port: PerturbationPort, orbit, k: int, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := port.u(params.precision / params.detail)
	var t := 0.0
	for _i in STEPS:
		var off := [port.r(dir[0] * t), port.r(dir[1] * t), port.r(dir[2] * t)]
		var de := port.de_pert(orbit, k, off, 32)
		if de < port.r(eps * t):
			return [0, t]
		t = port.r(t + de)
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


func _agree(got: Array, want: Array) -> bool:
	return got[0] == want[0] and (got[0] != 0 or absf(got[1] - want[1]) <= AGREE_T * want[1])


## Task 4 replaces these three with FractalParams.pert_iters / floor_pert / floor_iter.
func _handoff(orbit, near: float) -> int:
	var top := mini(ReferenceOrbitDraft.PERT_MAX, orbit.n)
	for k in range(1, top + 1):
		if orbit.mag[k] * near >= PERT_HANDOFF:
			return k
	return top


func _floor_pert(orbit, params: FractalParams) -> float:
	var eps := params.precision / params.detail
	var kk := mini(ReferenceOrbitDraft.PERT_MAX, orbit.n)
	var x: Vector4 = orbit.points[kk]
	var m := maxf(maxf(absf(x.x), absf(x.y)), maxf(absf(x.z), absf(x.w)))
	return FractalParams.ulp32(m) / (FractalParams.ZOOM_FLOOR_DIVISOR * eps * orbit.mag[kk])


func _floor_iter(orbit, params: FractalParams) -> float:
	if params.shape == FractalParams.Shape.KLEINIAN:
		return 0.0
	return ITER_FLOOR_RADIUS / (params.precision / params.detail * orbit.mag[ReferenceOrbitDraft.ITERATIONS])


## A cell is checked when the 64-bit reference hits on at least half its rays:
## below a fixture's 32-iteration floor (the terraces at 1e-6) every reference ray
## runs out of steps, and "agreeing" on that says nothing.
func _check_agreement() -> void:
	print("MEASURED | fixture | d | near | k | floor_pert | floor_iter | reference hit/beyond/none | direct agrees | perturbed agrees | checked")
	for fx in _fixtures():
		var name: String = fx[0]
		var params: FractalParams = fx[1]
		var s: Array = fx[2]
		var fan := _fan(Vector3(s[3], s[4], s[5]))
		for dd in DEPTHS:
			var d: float = dd
			var e := SurfaceFixture.backed(s, d)
			var orbit := ReferenceOrbitDraft.build(params, e[0], e[1], e[2])
			var near := orbit.distance
			var k := _handoff(orbit, near)
			var fp := _floor_pert(orbit, params)
			var fi := _floor_iter(orbit, params)
			var port := PerturbationPort.new(params, e, true)
			var classes := [0, 0, 0]
			var direct := 0
			var pert := 0
			for dir in fan:
				var want := _march_ref(e, dir, params, d)
				classes[want[0]] += 1
				if _agree(_march_direct(port, dir, params, d), want):
					direct += 1
				if _agree(_march_pert(port, orbit, k, dir, params, d), want):
					pert += 1
			var checked: bool = classes[0] * 2 >= fan.size()
			print("MEASURED | %s | %s | %s | %d | %s | %s | %d/%d/%d | %d%% | %d%% | %s" % [name, d, near, k, fp, fi,
				classes[0], classes[1], classes[2], direct * 100 / fan.size(), pert * 100 / fan.size(), checked])
			# exact comparison: is_equal_approx's tolerance never falls below 1e-5, so it
			# would call 1e-5, 1e-6 and 1e-7 all equal
			if d == 1e-6 and checked:
				check(direct * 10 < fan.size() * 3,
					"%s at 1e-6: today's float32 march gets under 30%% right (%d of %d)" % [name, direct, fan.size()])
			if checked:
				check(pert * 10 >= fan.size() * 9,
					"%s at %s (k %d): the perturbed float32 march gets at least 90%% right (%d of %d)" % [name, d, k, pert, fan.size()])
```

- [ ] **Step 11: Run, expect PASS.** It takes about a minute (about 2,000 emulated-float32 marches). Measured while planning, with this exact code: the algebra check passes on all 14 perturbable variants and every crossing kind occurs (clamp about 3,400 times, sphere 154, cylinder 50, abs 431, sort 184/177, menger 236, diagonal 149/152, Kleinian 111/111); perturbed 100% in every cell; direct at 1e-6 0% (default box), 11% (ice field), 0% (Menger), 0% (Kleinian); the terraces at 1e-6 and 1e-7 and the default box at 1e-7 are unchecked (the reference hits on 0, 0 and 11 of 27 rays: below their 32-iteration floors). **If a checked cell scores under 90%, stop and report it** (fixture, depth, k, the MEASURED line): it is a finding about the method, not a threshold to loosen.

- [ ] **Step 12: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add tests/perturbation_test.gd tests/perturbation_test.gd.uid tests/perturbation_port.gd tests/perturbation_port.gd.uid tests/reference_orbit_draft.gd tests/reference_orbit_draft.gd.uid tests/surface_fixture.gd
git -C $WT commit -m "test(perturbation): a float32 port of the perturbed step proves the difference formulas" -m "Case tables for every step kind, the 64-bit algebra check over every shape variant, and the spec's agreement grid in emulated float32. The reference orbit's record is drafted in tests/ (moved to src/ next)." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The 64-bit eye

**Files:**
- Modify: `src/camera/camera_state.gd`, `src/camera/fly_camera.gd` (the step only), `src/camera/center_ray.gd`, `src/workspace/workspace.gd`
- Test: `tests/camera_state_test.gd`, `tests/workspace_test.gd`, `tests/center_ray_test.gd`, `tests/fly_camera_test.gd`

**Interfaces:**
- Produces: `CameraState.eye_x/eye_y/eye_z: float` (exported), `CameraState.set_eye64(x: float, y: float, z: float) -> void`, `CameraState.eye64() -> PackedFloat64Array`; `CenterRay.march_at(ox: float, oy: float, oz: float, dir: Vector3, params: FractalParams) -> Array` (`[t, hit]` as `march`).
- `eye()` still returns `transform.origin` (the rounded shadow) for every 32-bit consumer. `FlyCamera.move_allowed` keeps its `Vector3` signature until Task 6.

- [ ] **Step 1: Failing tests.**

`tests/camera_state_test.gd`: add the call `_eye64()` as the last line of `run()`, and the function:

```gdscript
## The 64-bit eye: the doubles are the truth, the transform's origin their rounded shadow.
func _eye64() -> void:
	var d := CameraState.make_default()
	var e0 := d.eye64()
	check_eq(e0.size(), 3, "eye64() has three entries")
	check(Vector3(e0[0], e0[1], e0[2]) == d.eye(), "the default eye's doubles are its 32-bit origin")
	check_eq(d.transform, Transform3D(Basis.IDENTITY, CameraState.DEFAULT_EYE).looking_at(Vector3.ZERO, Vector3(0, 0, 1)),
		"make_default is unchanged")
	var emits := [0]
	d.changed.connect(func(): emits[0] += 1)
	var x := 1.9600000012345678
	d.set_eye64(x, 0.914, 0.787)
	check_eq(emits[0], 1, "set_eye64 emits changed")
	check_eq(d.eye64()[0], x, "and keeps the double exactly")
	check(d.eye() == Vector3(x, 0.914, 0.787), "eye() is the rounded shadow")
	d.set_eye64(x + 1e-12, 0.914, 0.787)
	check_eq(d.eye64()[0], x + 1e-12, "a 1e-12 move round-trips")
	check(d.eye() == Vector3(x, 0.914, 0.787), "under the same 32-bit shadow")
	check_eq(emits[0], 2, "and still emits: the doubles moved")
	d.set_eye64(x + 1e-12, 0.914, 0.787)
	check_eq(emits[0], 2, "the same doubles emit nothing")
	# re-basing at the shadow origin (FlyCamera._set_forward) keeps the doubles
	d.transform = Transform3D(Basis.IDENTITY, d.eye()).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	check_eq(d.eye64()[0], x + 1e-12, "a transform whose origin is the shadow keeps the doubles")
	# a new origin (orbit camera, Reset camera) replaces them
	d.transform = Transform3D(d.transform.basis, Vector3(1, 2, 3))
	check_eq(d.eye64(), PackedFloat64Array([1.0, 2.0, 3.0]), "a new origin replaces the doubles")
```

`tests/workspace_test.gd`: add the call `_deep_eye()` as the last line of `run()`, and the function:

```gdscript
## The eye is saved at full precision, so a deep view comes back exactly through
## capture/restore and to within one 64-bit rounding step through a file; the
## shipped default save loads to the same camera as before.
func _deep_eye() -> void:
	var deep_params := FractalParams.new()
	var s := SurfaceFixture.default_surface(deep_params)
	var deep := SurfaceFixture.backed(s, 1e-9)
	var dc := CameraState.make_default()
	dc.set_eye64(deep[0], deep[1], deep[2])
	var cap := Workspace.capture(_table(), Axes.new(), deep_params, dc)
	var back := CameraState.make_default()
	Workspace.restore(cap, _table(), Axes.new(), FractalParams.new(), back)
	check_eq(back.eye64(), dc.eye64(), "a capture 1e-9 from the surface restores the 64-bit eye exactly")
	check(back.transform.basis.is_equal_approx(dc.transform.basis), "and the same orientation")
	check_eq(Workspace.save_file(TMP, _table(), Axes.new(), deep_params, dc), OK, "a deep view saves")
	var from_file := CameraState.make_default()
	Workspace.load_file(TMP, _table(), Axes.new(), FractalParams.new(), from_file)
	# Godot's float parser is not correctly rounded: about a third of doubles come
	# back one 64-bit step (ulp) off, at most about 4e-15 for coordinates under 20,
	# thousands of times below the deepest zoom floor (about 5e-12)
	var fe := from_file.eye64()
	var want := dc.eye64()
	var worst := 0.0
	for j in 3:
		worst = maxf(worst, absf(fe[j] - want[j]))
	check(worst <= 4e-15, "and loads from the file to within a 64-bit rounding step (%s): full-precision JSON" % worst)

	# --- saves/default.json loads to the same camera as before ---
	var dj := CameraState.new()
	var res := Workspace.load_file("res://saves/default.json", _table(), Axes.new(), FractalParams.new(), dj)
	check(res["ok"], "saves/default.json loads")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://saves/default.json"))["camera"]
	var re := Vector3(raw["eye"][0], raw["eye"][1], raw["eye"][2])
	var rf := Vector3(raw["forward"][0], raw["forward"][1], raw["forward"][2]).normalized()
	var ru := Vector3(raw["up"][0], raw["up"][1], raw["up"][2]).normalized()
	check_eq(dj.transform, Transform3D(Basis.IDENTITY, re).looking_at(re + rf, ru),
		"to exactly the transform it loaded to before")
	check_eq(dj.eye64(), PackedFloat64Array([raw["eye"][0], raw["eye"][1], raw["eye"][2]]),
		"with the file's own digits as the 64-bit eye")
```

`tests/center_ray_test.gd`, append before the `# --- Main: R toggles the dot` block:

```gdscript
	# --- the 64-bit march: march() is march_at() on the same origin, and from
	# 3e-7 short of the surface only a 64-bit origin hits (measured while
	# planning: t/back 1.001 from the 64-bit origin; the 32-bit-rounded origin
	# misses, t/back 1.143) ---
	var e := CameraState.make_default().eye()
	var f0 := CameraState.make_default().forward()
	check_eq(CenterRay.march_at(e.x, e.y, e.z, f0, params), CenterRay.march(e, f0, params),
		"march() is march_at() on the same origin")
	var sf := SurfaceFixture.default_surface(params)
	var sdir := Vector3(sf[3], sf[4], sf[5])
	var o := SurfaceFixture.backed(sf, 3e-7)
	var r64 := CenterRay.march_at(o[0], o[1], o[2], sdir, params)
	check(r64[1] and absf(r64[0] / 3e-7 - 1.0) < 0.01,
		"from 3e-7 the 64-bit origin hits at about 3e-7 (hit %s, t/back %s)" % [r64[1], r64[0] / 3e-7])
	var r32 := CenterRay.march(Vector3(o[0], o[1], o[2]), sdir, params)
	check(not r32[1] or absf(r32[0] / 3e-7 - 1.0) > 0.05,
		"the same ray from the 32-bit-rounded origin does not (hit %s, t/back %s)" % [r32[1], r32[0] / 3e-7])
	var deep_cam := CameraState.make_default()
	deep_cam.set_eye64(o[0], o[1], o[2])
	check_eq(CenterRay.new(params, deep_cam).distance(), r64[0], "the cached ray marches from the 64-bit eye")
```

(The fixture's direction is the default camera's forward, so `deep_cam` looks along `sdir`.)

`tests/fly_camera_test.gd`, insert after the block `# --- the physics step really moves by speed x dt ...` (after `cam.transform = CameraState.make_default().transform`):

```gdscript
	# --- the step is added in 64-bit: a step far below the 32-bit grid still moves the eye ---
	cam.speed_factor = 1e-9   # about 1e-10 per tick at the default view (the grid there is ~1e-6)
	var e32 := cam.eye()
	var e64 := cam.eye64()
	var step := fly.current_speed() / Engine.physics_ticks_per_second
	fly.enabled = true
	await _tick(&"move_forward")
	fly.enabled = false
	var moved := cam.eye64()
	var dv := Vector3(moved[0] - e64[0], moved[1] - e64[1], moved[2] - e64[2])
	var dist := sqrt((moved[0] - e64[0]) ** 2 + (moved[1] - e64[1]) ** 2 + (moved[2] - e64[2]) ** 2)
	check(cam.eye() == e32, "a 1e-10 step cannot move the 32-bit shadow")
	# (the move is measured as a difference of doubles near 8, whose last bits are
	# about 1.5e-5 of a 1e-10 step: hence 1e-4)
	check(absf(dist / step - 1.0) < 1e-4, "but the 64-bit eye moves by the whole step (%s of %s)" % [dist, step])
	check(dv.normalized().is_equal_approx(cam.forward()), "along forward")
	cam.speed_factor = 1.0
	cam.transform = CameraState.make_default().transform
```

- [ ] **Step 2: Run the four tests, expect FAIL** (`set_eye64`, `eye64`, `march_at` not found).

- [ ] **Step 3: Implement `CameraState`.** Replace the file body (keep the header comment, add a paragraph):

```gdscript
class_name CameraState
extends Resource
## The camera as a Transform3D (Godot convention: forward = -basis.z) plus a
## distance-speed multiplier. Setters emit Resource's built-in `changed`, but
## only when the value actually differs: stray input that re-assigns the same
## transform must not make the governor re-render a still view. The comparison
## is exact, so even a deep-zoom move of 1e-7 counts.
##
## The eye's true position is eye_x, eye_y, eye_z, three 64-bit floats (a
## Transform3D's origin is 32-bit: near the default eye it can only sit on a grid
## about 1e-6 apart). transform.origin is their rounded shadow, which every 32-bit
## consumer reads through eye(). The deep-zoom code reads eye64(). Assigning a
## transform whose origin is the shadow keeps the doubles (FlyCamera._set_forward
## rebuilds the basis that way); any other origin replaces them.

const DEFAULT_EYE := Vector3(8.175847, 3.812460, 3.283393)

@export var transform: Transform3D = Transform3D.IDENTITY:
	set(v):
		if v == transform:
			return
		if v.origin != Vector3(eye_x, eye_y, eye_z):
			eye_x = v.origin.x
			eye_y = v.origin.y
			eye_z = v.origin.z
		transform = v
		emit_changed()
@export var speed_factor: float = 1.0:
	set(v):
		if v == speed_factor:
			return
		speed_factor = v
		emit_changed()
## The 64-bit eye. Set them through set_eye64(), which keeps the transform's
## origin in step. (Declared after `transform` so a loaded resource ends with the
## exact doubles.)
@export var eye_x: float = 0.0
@export var eye_y: float = 0.0
@export var eye_z: float = 0.0


## Move the eye to (x, y, z) in 64-bit; the origin becomes its rounding. Emits
## changed when any double differs, even when the 32-bit shadow does not move.
func set_eye64(x: float, y: float, z: float) -> void:
	if x == eye_x and y == eye_y and z == eye_z:
		return
	eye_x = x
	eye_y = y
	eye_z = z
	var t := transform
	t.origin = Vector3(x, y, z)
	if t == transform:
		emit_changed()   # the doubles moved under the same shadow
	else:
		transform = t    # its origin is the new shadow, so the doubles stay


func eye64() -> PackedFloat64Array:
	return PackedFloat64Array([eye_x, eye_y, eye_z])


func eye() -> Vector3:
	return transform.origin
```

(keep `forward()`, `right()`, `up()` and `make_default()` exactly as they are.)

- [ ] **Step 4: Implement the fly camera's 64-bit step.** In `FlyCamera._physics_process` replace the three lines from `var t := _camera.transform` to `_camera.transform = t` with:

```gdscript
	# The step is added in 64-bit: below about 1e-6 a 32-bit origin could not move.
	var step := current_speed() * delta
	var e := _camera.eye64()
	var nx: float = e[0] + dir.x * step
	var ny: float = e[1] + dir.y * step
	var nz: float = e[2] + dir.z * step
	if not move_allowed(_camera.eye(), Vector3(nx, ny, nz)):   # Task 6 makes the guard 64-bit
		at_zoom_limit = true
		return
	at_zoom_limit = false
	_camera.set_eye64(nx, ny, nz)
```

- [ ] **Step 5: Implement `CenterRay.march_at`.** In `center_ray.gd`: `_update()` marches from the 64-bit eye, `point()` adds in 64-bit, and the march takes a scalar origin.

```gdscript
func point() -> Vector3:
	_update()
	var e := _camera.eye64()
	var f := _camera.forward()
	var t := _distance if _hit else 0.0
	return Vector3(e[0] + f.x * t, e[1] + f.y * t, e[2] + f.z * t)
```

```gdscript
func _update() -> void:
	if not _dirty:
		return
	_dirty = false
	var e := _camera.eye64()
	var r := march_at(e[0], e[1], e[2], _camera.forward(), _params)
	_distance = r[0]
	_hit = r[1]


## march_at() from a Vector3 origin (32-bit: fine away from the surface).
static func march(origin: Vector3, dir: Vector3, params: FractalParams) -> Array:
	return march_at(origin.x, origin.y, origin.z, dir, params)


## Sphere-trace from the 64-bit origin (ox, oy, oz) along unit `dir`: each sample
## point o + dir t is formed in 64-bit scalars, so the march resolves the surface
## below the 32-bit grid. Returns [distance, hit]: [t, true] on a hit, [INF,
## false] when the ray leaves the shape's cube (or passes the Kleinian's view
## distance), [t_reached, false] when the step budget runs out first.
static func march_at(ox: float, oy: float, oz: float, dir: Vector3, params: FractalParams) -> Array:
	var tb := _box_intersect(Vector3(ox, oy, oz), dir, params.bound_half())   # the cube needs no precision
	if params.view_distance() > 0.0:
		tb.y = minf(tb.y, params.view_distance())   # the shader stops there too
	if tb.y < maxf(tb.x, 0.0):
		return [INF, false]
	var near := maxf(DistanceEstimator.estimate_at(ox, oy, oz, params), FractalParams.NEAR_FLOOR)
	var t := maxf(tb.x, 0.0)
	for _i in MAX_STEPS:
		var d := DistanceEstimator.estimate_at(ox + dir.x * t, oy + dir.y * t, oz + dir.z * t, params)
		if d < params.hit_epsilon(t, near):
			return [t, true]
		t += d
		if t > tb.y:
			return [INF, false]
	return [t, false]
```

(Delete the old `march(origin, dir, params)` body; `_box_intersect` is unchanged.)

- [ ] **Step 6: Implement the full-precision save.** In `workspace.gd`:
  - `capture`: `"eye": _eye_to_array(camera),` with

```gdscript
## The 64-bit eye at full precision (no _tidy: a deep view needs every digit).
static func _eye_to_array(camera: CameraState) -> Array:
	var e := camera.eye64()
	return [e[0], e[1], e[2]]
```

  - `save_file`: `file.store_string(JSON.stringify(capture(table, axes, params, camera, noise), "\t", false, true))` (`full_precision`: the default keeps 15 digits and a 64-bit eye would not round-trip; full precision prints the shortest exact form, so other fields read the same).
  - `_restore_camera`: read the eye as doubles, set it, then the basis at the shadow origin:

```gdscript
static func _restore_camera(cam: Dictionary, camera: CameraState, warnings: Array) -> void:
	var eye: Variant = _array_to_doubles(cam.get("eye", null))
	var forward: Variant = _array_to_vec(cam.get("forward", null))
	var up: Variant = _array_to_vec(cam.get("up", null))
	if eye != null and forward != null and up != null:
		var f := (forward as Vector3).normalized()
		var u := (up as Vector3).normalized()
		if f.is_zero_approx() or u.is_zero_approx() or absf(f.dot(u)) > 0.999:
			warnings.append("Malformed camera orientation ignored")
		else:
			var e: PackedFloat64Array = eye
			camera.set_eye64(e[0], e[1], e[2])
			var o := camera.eye()   # the rounded shadow: assigning it keeps the doubles
			camera.transform = Transform3D(Basis.IDENTITY, o).looking_at(o + f, u)
	elif cam.has("eye") or cam.has("forward") or cam.has("up"):
		warnings.append("Malformed camera position ignored")
	# (the speed_factor part stays as it is)
```

```gdscript
## Three numbers as 64-bit floats, or null when malformed.
static func _array_to_doubles(raw: Variant) -> Variant:
	if not (raw is Array) or raw.size() != 3:
		return null
	for v in raw:
		if not (v is float or v is int):
			return null
	return PackedFloat64Array([float(raw[0]), float(raw[1]), float(raw[2])])
```

  - Update the file's header comment: the eye is written at full precision; `forward` and `up` keep 7 significant figures.

- [ ] **Step 7: Run the four tests, then the suite.** `$WT/tests/run_all.sh; echo exit=$?`: everything passes (`deep_zoom_test` unchanged; the centre ray now marches in 64-bit, which shifts the fixture's starting hit by round-off only).

- [ ] **Step 8: Commit.**

```bash
git -C $WT add src/camera/camera_state.gd src/camera/fly_camera.gd src/camera/center_ray.gd src/workspace/workspace.gd tests/camera_state_test.gd tests/workspace_test.gd tests/center_ray_test.gd tests/fly_camera_test.gd
git -C $WT commit -m "feat(camera): a 64-bit eye for the fly step, the centre ray and saves" -m "CameraState keeps eye_x/y/z as the truth and the transform's origin as their rounded shadow; eye() is unchanged for every 32-bit consumer. CenterRay.march_at marches from a scalar origin. Saves write the eye at full precision (JSON full_precision); saves/default.json loads to the same transform." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: `ReferenceOrbit`

The draft from Task 1 becomes the production class, unchanged apart from its name and header, and gets its own test.

**Files:**
- Move: `tests/reference_orbit_draft.gd` → `src/fractal/reference_orbit.gd` (and its `.uid`)
- Modify: `tests/perturbation_test.gd`, `tests/perturbation_port.gd` (names only)
- Create: `tests/reference_orbit_test.gd`

**Interfaces:**
- Produces: `ReferenceOrbit` (`class_name`), exactly the draft's API: `build(params, ex, ey, ez) -> ReferenceOrbit`, `ITERATIONS`, `PERT_MAX`, `eye`, `distance`, `n`, `perturbable`, `mag`, `points`, `points64`, `a`, `b`, `c`, `d`, `rec64`.

- [ ] **Step 1: Write the failing test.** Create `tests/reference_orbit_test.gd`:

```gdscript
extends "res://tests/test_case.gd"
## ReferenceOrbit: the camera's own orbit in 64-bit and the per-iteration record
## the perturbed shader reads. Its distance is the CPU estimator's, exactly (the
## loop is duplicated so the record can be taken beside it; this keeps it
## honest), its magnification never falls, and the folds it cannot perturb say so.


func run() -> void:
	for v in SurfaceFixture.variants():
		var name: String = v[0]
		var params: FractalParams = v[1]
		var s := SurfaceFixture.surface_from(params, v[2])
		for back in [1e-1, 1e-3, 1e-6]:
			var e := SurfaceFixture.backed(s, back)
			var o := ReferenceOrbit.build(params, e[0], e[1], e[2])
			check_eq(o.distance, DistanceEstimator.estimate_at(e[0], e[1], e[2], params),
				"%s, %s back: distance is the estimator's, exactly" % [name, back])
		var o0 := ReferenceOrbit.build(params, s[0], s[1], s[2])
		check_eq(o0.perturbable, v[3], "%s: perturbable is %s" % [name, v[3]])
		check(o0.mag.size() == 33 and o0.points.size() == 33 and o0.points64.size() == 132,
			"%s: 33 magnifications and points" % name)
		check(o0.a.size() == ReferenceOrbit.PERT_MAX and o0.d.size() == ReferenceOrbit.PERT_MAX
			and o0.rec64.size() == ReferenceOrbit.PERT_MAX * 16, "%s: PERT_MAX records" % name)
		check_eq(o0.eye, PackedFloat64Array([s[0], s[1], s[2]]), "%s: it remembers its 64-bit eye" % name)

	# the magnification never falls on the spec's fixtures (every factor is >= 1 there)
	for v in SurfaceFixture.variants():
		if not (v[0] in ["default box", "ice field", "terraces", "Menger", "Kleinian"]):
			continue
		var s := SurfaceFixture.surface_from(v[1], v[2])
		var o := ReferenceOrbit.build(v[1], s[0], s[1], s[2])
		var ok := o.mag[0] == 1.0
		for i in 32:
			ok = ok and o.mag[i + 1] >= o.mag[i]
		check(ok, "%s: mag starts at 1 and never falls (mag[32] %s)" % [v[0], o.mag[32]])

	# n: 32 for the Mandelbox, fewer for a KIFS eye whose orbit escapes
	var box := FractalParams.new()
	var e := CameraState.DEFAULT_EYE
	check_eq(ReferenceOrbit.build(box, e.x, e.y, e.z).n, 32, "the Mandelbox always runs 32 iterations")
	var kifs := FractalParams.new()
	kifs.shape = FractalParams.Shape.KIFS
	var ko := ReferenceOrbit.build(kifs, 3.2, 2.4, 1.9)
	check(ko.n < 32, "a KIFS eye outside the sponge escapes early (n %d)" % ko.n)
	check_eq(ko.mag[32], pow(3.0, 32), "and its mag is |scale|^i regardless (floor_iter reads mag[32])")

	# record spot checks, default box at its surface (fold order 0, box fold)
	var s := SurfaceFixture.default_surface(box)
	var o := ReferenceOrbit.build(box, s[0], s[1], s[2])
	var x0 := [s[0], s[1], s[2], 0.0]
	check_eq(o.points[0], Vector4(s[0], s[1], s[2], 0.0), "X_0 is the eye (w 0)")
	check_eq(o.a[0], Vector4(-1.0 - x0[0], -1.0 - x0[1], -1.0 - x0[2], -1.0 - x0[3]), "a[0] is -L - X_0")
	check_eq(o.b[0], Vector4(1.0 - x0[0], 1.0 - x0[1], 1.0 - x0[2], 1.0 - x0[3]), "b[0] is L - X_0")
	var folded := x0.duplicate()
	DistanceEstimator._fold(folded, 1.0, 0, false, 0.0)
	check_eq(o.c[0], Vector4(folded[0], folded[1], folded[2], folded[3]), "c[0] is the sphere fold's input (post box fold)")
	check_eq(o.rec64[3 * 4 + 2] * absf(box.box_scale), o.mag[1], "mag[1] is the sphere factor d[0].z times |scale|")

	# KIFS: d[i] is X_{i+1}; Kleinian: d[i].y is the inversion factor and mag multiplies by it
	for i in mini(ko.n, ReferenceOrbit.PERT_MAX):
		check_eq(ko.d[i], ko.points[i + 1], "KIFS d[%d] is X_%d" % [i, i + 1])
	var kl := FractalParams.new()
	kl.shape = FractalParams.Shape.KLEINIAN
	var ls := SurfaceFixture.surface_from(kl, Vector3(2.5, 1.6, 1.2))
	var lo := ReferenceOrbit.build(kl, ls[0], ls[1], ls[2])
	var factors_ok := true
	for i in mini(ReferenceOrbit.PERT_MAX, lo.n):   # past a fixed point the record is empty
		factors_ok = factors_ok and is_equal_approx(lo.mag[i + 1], lo.mag[i] * lo.rec64[(i * 4 + 3) * 4 + 1])
	check(factors_ok, "Kleinian: mag[i+1] = mag[i] x d[i].y (the factor m)")
```

- [ ] **Step 2: Run, expect FAIL** (`ReferenceOrbit` not declared).

- [ ] **Step 3: Move the draft.**

```bash
git -C $WT mv tests/reference_orbit_draft.gd src/fractal/reference_orbit.gd
git -C $WT mv tests/reference_orbit_draft.gd.uid src/fractal/reference_orbit.gd.uid
```

Then in `src/fractal/reference_orbit.gd`: `class_name ReferenceOrbitDraft` → `class_name ReferenceOrbit`, `-> ReferenceOrbitDraft` → `-> ReferenceOrbit`, `ReferenceOrbitDraft.new()` → `ReferenceOrbit.new()`, and delete the line `## DRAFT, moved to src/fractal/reference_orbit.gd as ReferenceOrbit in Task 3.` plus the blank `##` after it. Add to the header, after the usage block: `## Built by FractalView._push_near() (the record it pushes), FlyCamera.move_allowed() and FractalParams.zoom_floor() (the floors).` In `tests/perturbation_test.gd` and `tests/perturbation_port.gd` replace every `ReferenceOrbitDraft` with `ReferenceOrbit` (and the port's header comment "Task 3: ReferenceOrbit" wording if present).

- [ ] **Step 4: Run, expect PASS**: `godot4 --headless --import --path $WT >/dev/null 2>&1`, then `reference_orbit_test.gd` and `perturbation_test.gd` (unchanged results: the production record is the proven one).

- [ ] **Step 5: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add src/fractal/reference_orbit.gd src/fractal/reference_orbit.gd.uid tests/reference_orbit_test.gd tests/reference_orbit_test.gd.uid tests/perturbation_test.gd tests/perturbation_port.gd
git -C $WT commit -m "feat(fractal): ReferenceOrbit, the camera's 64-bit orbit and the perturbed march's record" -m "Moved from the proof's draft unchanged; its distance equals every estimator's exactly." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git mv` already staged the removal of the draft paths.)

### Task 4: `FractalParams.pert_iters` and the two floors

**Files:**
- Modify: `src/fractal/fractal_params.gd`, `src/camera/fly_camera.gd` (one call), `tests/perturbation_test.gd`
- Test: `tests/fractal_params_test.gd`, `tests/fly_camera_test.gd`

**Interfaces:**
- Consumes: `ReferenceOrbit` (Task 3).
- Produces: `FractalParams.PERT_ON := 10.0`, `PERT_HANDOFF := 0.1`, `ITER_FLOOR_RADIUS := 0.25`; `func floor32(eye: PackedFloat64Array) -> float`; `func pert_iters(orbit: ReferenceOrbit, near: float) -> int`; `func floor_pert(orbit: ReferenceOrbit) -> float`; `func floor_iter(orbit: ReferenceOrbit) -> float`; `func zoom_floor_for(orbit: ReferenceOrbit) -> float`; `func zoom_floor(eye: PackedFloat64Array) -> float` (replaces `zoom_floor(eye: Vector3)`).

- [ ] **Step 1: Failing tests.**

In `tests/fractal_params_test.gd`, rewrite the existing `# zoom_floor: ...` block (the one using `near_box`) as the `floor32` block, same checks, 64-bit input:

```gdscript
	# floor32: today's 32-bit floor (the guard for shapes that are not perturbed)
	var zf := FractalParams.new()
	var near_box := PackedFloat64Array([1.96, 0.914, 0.787])   # the default view's surface point
	check(absf(zf.floor32(near_box) - 1e-4) <= 0.2e-4,
		"near the box at the default precision the 32-bit floor is about 1e-4 (%s)" % zf.floor32(near_box))
	check_eq(zf.floor32(PackedFloat64Array([-1.96, -0.914, -0.787])), zf.floor32(near_box), "it uses the largest |coordinate|")
	var zf10 := FractalParams.new()
	zf10.detail = 10.0
	check_approx(zf10.floor32(near_box) / zf.floor32(near_box), 10.0,
		"it scales with Detail: a finer hit threshold needs more room above the float grid", 1e-9)
	check(zf.floor32(PackedFloat64Array([8.18, 3.81, 3.28])) > zf.floor32(near_box),
		"larger coordinates have a coarser grid, so a further floor")
	check(is_finite(zf.floor32(PackedFloat64Array([0.0, 0.0, 0.0]))), "the origin stays finite")
```

and add the call `_perturbation()` as the last line of `run()`, and the function:

```gdscript
## pert_iters and the two zoom floors (ReferenceOrbit at a camera on the default
## view's line of sight, backed off its surface point).
func _perturbation() -> void:
	# pert_iters: off at the default view and above PERT_ON x floor32, on below it,
	# rising as the camera closes in, never above PERT_MAX
	var pp := FractalParams.new()
	var de := CameraState.DEFAULT_EYE
	var home := ReferenceOrbit.build(pp, de.x, de.y, de.z)
	check_eq(pp.pert_iters(home, home.distance), 0, "the default view does not perturb")
	var sp := SurfaceFixture.default_surface(pp)
	var switch_at := FractalParams.PERT_ON * pp.floor32(PackedFloat64Array([sp[0], sp[1], sp[2]]))
	for cs in [[2.0, false], [0.5, true]]:
		var eb := SurfaceFixture.backed(sp, SurfaceFixture.back_for_distance(pp, sp, cs[0] * switch_at))
		var ob := ReferenceOrbit.build(pp, eb[0], eb[1], eb[2])
		check(absf(ob.distance / (cs[0] * switch_at) - 1.0) < 0.1, "placed at %s x the switch (near %s)" % [cs[0], ob.distance])
		check_eq(pp.pert_iters(ob, ob.distance) > 0, cs[1], "%s x the switch distance: perturbing is %s" % [cs[0], cs[1]])
	var last := 0
	for back in [1e-4, 1e-5, 1e-6, 1e-7]:
		var eb := SurfaceFixture.backed(sp, back)
		var ob := ReferenceOrbit.build(pp, eb[0], eb[1], eb[2])
		var kk := pp.pert_iters(ob, ob.distance)
		check(kk >= last and kk >= 1 and kk <= ReferenceOrbit.PERT_MAX, "back %s: k %d (rising, within 1..20)" % [back, kk])
		var smallest := true
		for j in range(1, kk):
			smallest = smallest and ob.mag[j] * ob.distance < FractalParams.PERT_HANDOFF
		check(smallest and (ob.mag[kk] * ob.distance >= FractalParams.PERT_HANDOFF or kk == mini(ReferenceOrbit.PERT_MAX, ob.n)),
			"back %s: k is the smallest with mag[k] x near >= PERT_HANDOFF (or the cap)" % back)
		last = kk
	var kifs := FractalParams.new()
	kifs.shape = FractalParams.Shape.KIFS
	var ks := SurfaceFixture.surface_from(kifs, Vector3(3.2, 2.4, 1.9))
	var ke := SurfaceFixture.backed(ks, 1e-7)
	var ko := ReferenceOrbit.build(kifs, ke[0], ke[1], ke[2])
	check(kifs.pert_iters(ko, ko.distance) <= ko.n, "a KIFS k never passes the eye's own bailout (n %d)" % ko.n)
	for v in SurfaceFixture.variants():
		if v[3]:
			continue
		var vs := SurfaceFixture.surface_from(v[1], v[2])
		var vb := SurfaceFixture.backed(vs, 1e-5)
		var vo := ReferenceOrbit.build(v[1], vb[0], vb[1], vb[2])
		check_eq(v[1].pert_iters(vo, vo.distance), 0, "%s is never perturbed" % v[0])
		check_eq(v[1].zoom_floor(vb), v[1].floor32(vb), "and keeps the 32-bit floor")

	# the two floors: far below the 32-bit floor on the default box (measured while
	# planning: about 5.7e-7, against 9.5e-5), the Kleinian has no iteration floor
	var e5 := SurfaceFixture.backed(sp, 1e-5)
	var o5 := ReferenceOrbit.build(pp, e5[0], e5[1], e5[2])
	check(pp.zoom_floor(e5) > 0.0 and pp.zoom_floor(e5) < pp.floor32(e5) / 50.0,
		"the default box's zoom floor (%s) is at least 50x below the 32-bit one (%s)" % [pp.zoom_floor(e5), pp.floor32(e5)])
	check_eq(pp.zoom_floor(e5), maxf(pp.floor_pert(o5), pp.floor_iter(o5)), "and it is the larger of the two floors")
	var kl := FractalParams.new()
	kl.shape = FractalParams.Shape.KLEINIAN
	var lo := ReferenceOrbit.build(kl, 2.5, 1.6, 1.2)
	check_eq(kl.floor_iter(lo), 0.0, "the Kleinian has no iteration floor (its estimate reaches 0 at the sheets)")

	# floor_iter brackets where 32 iterations stop resolving: a 128-step 64-bit march
	# from 10 x floor_iter hits within 1%; from floor_iter / 10 it does not
	for v in SurfaceFixture.variants():
		if not (v[0] in ["default box", "ice field", "terraces"]):
			continue
		var bp: FractalParams = v[1]
		var bs := SurfaceFixture.surface_from(bp, v[2])
		var be := SurfaceFixture.backed(bs, 1e-5)
		var fi := bp.floor_iter(ReferenceOrbit.build(bp, be[0], be[1], be[2]))
		var dir := [bs[3], bs[4], bs[5]]
		var above := SurfaceFixture.march64(SurfaceFixture.backed(bs, 10.0 * fi), dir, bp, 128)
		check(above[1] and absf(above[0] / (10.0 * fi) - 1.0) < 0.01,
			"%s: from 10 x floor_iter (%s) the ray hits (t/back %s)" % [v[0], 10.0 * fi, above[0] / (10.0 * fi)])
		var below := SurfaceFixture.march64(SurfaceFixture.backed(bs, 0.1 * fi), dir, bp, 128)
		check(not below[1] or absf(below[0] / (0.1 * fi) - 1.0) >= 0.01,
			"%s: from floor_iter / 10 it does not (hit %s, t/back %s)" % [v[0], below[1], below[0] / (0.1 * fi)])
```

In `tests/fly_camera_test.gd`, the zoom-guard test moves to the octahedral fold (a shape that keeps the 32-bit floor, so the 32-bit guard stays tested), and placements become adaptive. Replace `_place` and `_depth`, and the start of `_zoom_floor_guard` up to and including its first precondition check:

```gdscript
## A camera on the default view's line of sight, `back` short of the surface (64-bit).
func _place(cam: CameraState, s: Array, back: float) -> void:
	cam.transform = CameraState.make_default().transform
	var e := SurfaceFixture.backed(s, back)
	cam.set_eye64(e[0], e[1], e[2])


## [distance to the surface, the zoom floor] at the camera's 64-bit eye.
func _depth(cam: CameraState, params: FractalParams) -> Array:
	var e := cam.eye64()
	return [DistanceEstimator.estimate_at(e[0], e[1], e[2], params), params.zoom_floor(e)]


## Place the camera where its distance is `ratio` x the zoom floor.
func _place_ratio(cam: CameraState, s: Array, params: FractalParams, ratio: float) -> void:
	var f := params.zoom_floor(PackedFloat64Array([s[0], s[1], s[2]]))
	_place(cam, s, SurfaceFixture.back_for_distance(params, s, ratio * f))
```

```gdscript
## The fly camera refuses a move below FractalParams.zoom_floor, says so through
## at_zoom_limit, and always lets the camera back off. Run on the octahedral fold,
## which is not perturbed and keeps the 32-bit floor (the deep flight on the
## default box is _deep_flight).
func _zoom_floor_guard() -> void:
	var ctx := _fresh()
	var params: FractalParams = ctx[0]
	var cam: CameraState = ctx[1]
	var fly: FlyCamera = ctx[2]
	params.fold_shape = MandelboxShape.FoldShape.OCTAHEDRAL
	var s := SurfaceFixture.default_surface(params)
	check_eq(fly.at_zoom_limit, false, "a new fly camera is not at the zoom limit")

	# just above the floor, W held: it closes in, then stops at the floor
	_place_ratio(cam, s, params, 1.7)
	var dz := _depth(cam, params)
	check(dz[0] > 1.2 * dz[1] and dz[0] < 2.5 * dz[1],
		"the camera starts just above the floor (%s over %s)" % [dz[0], dz[1]])
```

and in the rest of that function: replace the two later `_place(cam, s, 2.5e-4)` calls with `_place_ratio(cam, s, params, 0.5)` (the following precondition `dz[0] < 0.8 * dz[1] and dz[0] > 0.2 * dz[1]` stays); replace every `cam.eye()` with `cam.eye64()` (so `start`, `held` and `below` are 64-bit and the `==` / `!=` comparisons compare the doubles); and replace each `DistanceEstimator.estimate(cam.eye(), params)` with `_depth(cam, params)[0]`.

- [ ] **Step 2: Run both tests, expect FAIL** (`floor32`, `pert_iters`, `zoom_floor` with a `PackedFloat64Array` not found).

- [ ] **Step 3: Implement in `fractal_params.gd`.** Replace `zoom_floor(eye: Vector3)` (and its doc comment) with `floor32`, then append the rest after it:

```gdscript
## The 32-bit floor: how close the fly camera may come to the surface with its
## eye at `eye` when the shader forms ray positions in 32-bit floats, which near
## the eye can only land on a grid ulp32(largest |coordinate|) apart. Once the hit
## threshold (eps × distance, eps = precision / detail) is much finer than that
## grid, rays reach the surface only by luck. ulp32 / (ZOOM_FLOOR_DIVISOR × eps):
## about 1e-4 near the box at the default precision. The guard for shapes that
## are not perturbed, and the scale pert_iters() switches on at. Uses the unshed
## detail, like coarse_iters.
func floor32(eye: PackedFloat64Array) -> float:
	var m := maxf(absf(eye[0]), maxf(absf(eye[1]), absf(eye[2])))
	return ulp32(m) / (ZOOM_FLOOR_DIVISOR * maxf(precision / detail, 1e-30))


## Perturbation (see ReferenceOrbit and perturbation.gdshaderinc) switches on
## once the camera is within PERT_ON × the 32-bit floor: an order of magnitude
## before the 32-bit march breaks, where both agree, so there is no pop.
const PERT_ON := 10.0
## Hand the offset back to the ordinary loop once the view has been magnified
## until it is this big (mag[k] × near): from there a 32-bit point is fine enough
## for the hit threshold. Measured (tests/perturbation_test.gd's grid): 1e-2, the
## self-similar note's figure, left four rays in 27 off by 0.15-0.5% on the default
## box at 1e-6; 0.1 agrees everywhere for at most three more perturbed iterations.
const PERT_HANDOFF := 0.1
## Inside the shape the 32-iteration estimate |z_32| / dz_32 bottoms out near this
## radius over the magnification mag[32]: measured on the default box, the
## ice-field and the terraces saves (|z_32| is a fraction of a unit at the
## surface; the plan's Spec findings 1 has the table).
const ITER_FLOOR_RADIUS := 0.25


## How many iterations the shader perturbs for a camera whose reference orbit is
## `orbit` and whose raw distance to the surface is `near`: 0 (off: the direct
## march, exactly as before) when the shape is not perturbable or the camera is at
## least PERT_ON × floor32 away; else the smallest k with mag[k] × near >=
## PERT_HANDOFF, capped at min(PERT_MAX, orbit.n).
func pert_iters(orbit: ReferenceOrbit, near: float) -> int:
	if not orbit.perturbable or near >= PERT_ON * floor32(orbit.eye):
		return 0
	var top := mini(ReferenceOrbit.PERT_MAX, orbit.n)
	for k in range(1, top + 1):
		if orbit.mag[k] * near >= PERT_HANDOFF:
			return k
	return top


## The perturbed march's own floor: the 32-bit floor applied at the handoff point
## X_K (K = min(PERT_MAX, n)), where the view is mag[K] times bigger.
func floor_pert(orbit: ReferenceOrbit) -> float:
	var k := mini(ReferenceOrbit.PERT_MAX, orbit.n)
	var x: Vector4 = orbit.points[k]
	var m := maxf(maxf(absf(x.x), absf(x.y)), maxf(absf(x.z), absf(x.w)))
	return ulp32(m) / (ZOOM_FLOOR_DIVISOR * maxf(precision / detail, 1e-30) * maxf(orbit.mag[k], 1e-300))


## Where 32 iterations stop resolving: a ray only hits where the estimate is
## under eps × t, and the estimate cannot fall much below ITER_FLOOR_RADIUS /
## mag[32]. 0 for the Kleinian, whose estimate reaches 0 at its sheets.
func floor_iter(orbit: ReferenceOrbit) -> float:
	if shape == Shape.KLEINIAN:
		return 0.0
	return ITER_FLOOR_RADIUS / (maxf(precision / detail, 1e-30) * maxf(orbit.mag[ReferenceOrbit.ITERATIONS], 1e-300))


## The zoom floor for a reference orbit already built at the eye: the larger of
## the two floors when the shape is perturbable, else the 32-bit floor.
func zoom_floor_for(orbit: ReferenceOrbit) -> float:
	if not orbit.perturbable:
		return floor32(orbit.eye)
	return maxf(floor_pert(orbit), floor_iter(orbit))


## How close the fly camera may come to the surface with its eye at `eye` (64-bit).
func zoom_floor(eye: PackedFloat64Array) -> float:
	return zoom_floor_for(ReferenceOrbit.build(self, eye[0], eye[1], eye[2]))
```

(If Godot reports a cyclic-reference parse error on the `ReferenceOrbit` type hints, drop the hints to plain `orbit` and say so in the commit; keep the code otherwise.)

- [ ] **Step 4: Keep the fly camera compiling.** In `FlyCamera.move_allowed(from: Vector3, to: Vector3)` replace `_params.zoom_floor(to)` with `_params.zoom_floor(PackedFloat64Array([to.x, to.y, to.z]))` (Task 6 makes the whole guard 64-bit).

- [ ] **Step 5: The proof uses the production rule.** In `tests/perturbation_test.gd`: delete the constants `ITER_FLOOR_RADIUS` and `PERT_HANDOFF` and the helpers `_handoff`, `_floor_pert` and `_floor_iter`; in `_check_agreement` use `params.pert_iters(orbit, near)`, `params.floor_pert(orbit)` and `params.floor_iter(orbit)`.

- [ ] **Step 6: Run `fractal_params_test`, `fly_camera_test`, `perturbation_test`, expect PASS.** If the floor_iter bracket fails on one fixture, report the fixture and the two `t/back` values; do not retune `ITER_FLOOR_RADIUS` without saying so in the commit (it was calibrated on exactly these three).

- [ ] **Step 7: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add src/fractal/fractal_params.gd src/camera/fly_camera.gd tests/fractal_params_test.gd tests/fly_camera_test.gd tests/perturbation_test.gd
git -C $WT commit -m "feat(params): pert_iters and the two zoom floors (perturbed precision, 32 iterations)" -m "zoom_floor(eye64) = max(floor_pert, floor_iter) for perturbable shapes, the old 32-bit formula (now floor32) otherwise. floor_iter's radius is 0.25, calibrated on the default box and the ice-field and terraces saves (the spec's bound_half overstated it 15-50x); the Kleinian has none. The fly guard test moves to the octahedral fold, which keeps the 32-bit floor." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The shader and the view's pushes

**Files:**
- Create: `src/fractal/perturbation.gdshaderinc`
- Modify: `src/fractal/mandelbox.gdshader`, `src/fractal/kifs.gdshaderinc`, `src/fractal/kleinian.gdshaderinc`, `src/fractal/fractal_view.gd`
- Test: `tests/shader_test.gd`, `tests/fractal_view_test.gd`

**Interfaces:**
- Consumes: `ReferenceOrbit` (Task 3), `FractalParams.pert_iters` (Task 4).
- Produces: shader uniforms `int pert_iters`, `vec4 pert_a[20]`, `pert_b[20]`, `pert_c[20]`, `pert_d[20]`, `vec4 pert_end`; GLSL `mb_orbit(inout vec4 z, inout float dz, vec4 c, int first, int iters)`, `kifs_orbit(inout vec4 p, inout int n, int first, int iters)`, `kifs_distance(vec4 p, int n)`, `kifs_rot1_on()`, `kifs_rot2_on()`, `kleinian_orbit(inout vec4 p, inout float dr, int first, int iters)`, `kleinian_distance(vec4 p, float dr)`, `de_pert(vec3 off, int iters)`, `march_de(vec3 pos, vec3 off, int iters)`, `calc_normal_pert(vec3 off, float delta)`, `true_normal(vec3 v, vec3 off, float delta)`; `FractalView.pert_iters() -> int`, `FractalView._pert_pushes: int`.
- The GLSL below is a line-for-line twin of `tests/perturbation_port.gd`. A reviewer should diff them function by function.

- [ ] **Step 1: Failing tests.**

`tests/shader_test.gd`: add `"pert_iters", "pert_a", "pert_b", "pert_c", "pert_d", "pert_end"` to `RENDERER_UNIFORMS`, and append to `run()`:

```gdscript
	# the record arrays are as long as ReferenceOrbit's record
	var inc := FileAccess.get_file_as_string("res://src/fractal/perturbation.gdshaderinc")
	for arr in ["pert_a", "pert_b", "pert_c", "pert_d"]:
		var m := RegEx.create_from_string("uniform vec4 %s\\[(\\d+)\\];" % arr).search(inc)
		check(m != null and int(m.get_string(1)) == ReferenceOrbit.PERT_MAX,
			"%s has ReferenceOrbit.PERT_MAX entries" % arr)
```

`tests/fractal_view_test.gd`: right after the first `await frames(1)` that follows `view.setup(params, cam)`, insert:

```gdscript
	# perturbation is off at the default view, and nothing of it is pushed
	check_eq(view.pert_iters(), 0, "the default view does not perturb")
	check_eq(int(view._material.get_shader_parameter("pert_iters")), 0, "and pushes pert_iters 0")
	check_eq(view._pert_pushes, 0, "and never pushes the record arrays")
```

and after the line `check_eq(float(mat.get_shader_parameter("nf_weight")), 1.0, "and the probe's lighting")`, insert:

```gdscript
	# a camera 1e-5 short of the surface perturbs: the record and X_k are pushed, once
	# (the close camera above, 1e-3 short, already perturbed, so count from here)
	var sdeep := SurfaceFixture.default_surface(params)
	var edeep := SurfaceFixture.backed(sdeep, 1e-5)
	var pushes_before := view._pert_pushes
	cam.set_eye64(edeep[0], edeep[1], edeep[2])
	var orbit := ReferenceOrbit.build(params, edeep[0], edeep[1], edeep[2])
	var kdeep := params.pert_iters(orbit, orbit.distance)
	check(kdeep > 0, "precondition: 1e-5 from the surface perturbs (k %d)" % kdeep)
	check_eq(view.pert_iters(), kdeep, "the view reports k")
	check_eq(int(mat.get_shader_parameter("pert_iters")), kdeep, "and pushes it")
	for arr in ["pert_a", "pert_b", "pert_c", "pert_d"]:
		check_eq((mat.get_shader_parameter(arr) as PackedVector4Array).size(), ReferenceOrbit.PERT_MAX,
			"%s has PERT_MAX entries" % arr)
	check_eq(mat.get_shader_parameter("pert_a"), orbit.a, "the record is the orbit's")
	check_eq(Vector4(mat.get_shader_parameter("pert_end")), orbit.points[kdeep], "pert_end is X_k")
	var pushes := view._pert_pushes
	check_eq(pushes, pushes_before + 1, "one camera move pushes the arrays once")
	await frames(3)
	check_eq(view._pert_pushes, pushes, "a still frame pushes nothing more")
	cam.transform = home
	check_eq(view.pert_iters(), 0, "back home: off again")
	check_eq(int(mat.get_shader_parameter("pert_iters")), 0, "and pert_iters 0 is pushed")
```

(`home` is the variable the existing coarse-iteration block already holds.)

- [ ] **Step 2: Run both, expect FAIL** (missing uniforms; `pert_iters()` not found).

- [ ] **Step 3: Refactor the KIFS and Kleinian loops to take a start index.** In `kifs.gdshaderinc` replace `kifs_de` with (the loop body is unchanged, only moved):

```glsl
bool kifs_rot1_on() {
	return (abs(kifs_rot1_xy) + abs(kifs_rot1_xz) + abs(kifs_rot1_xw)
		+ abs(kifs_rot1_yz) + abs(kifs_rot1_yw) + abs(kifs_rot1_zw)) > 1e-6;
}

bool kifs_rot2_on() {
	return (abs(kifs_rot2_xy) + abs(kifs_rot2_xz) + abs(kifs_rot2_xw)
		+ abs(kifs_rot2_yz) + abs(kifs_rot2_yw) + abs(kifs_rot2_zw)) > 1e-6;
}

// Iterations first..iters-1 of the KIFS orbit p; n counts the iterations run. The
// direct kifs_de runs them all from 0, the perturbed de_pert from its handoff.
void kifs_orbit(inout vec4 p, inout int n, int first, int iters) {
	float s = kifs_scale;
	vec4 o = vec4(kifs_offset_0, kifs_offset_1, kifs_offset_2, kifs_offset_3);
	bool rot1 = kifs_rot1_on();
	bool rot2 = kifs_rot2_on();
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		if (rot1) { p = kifs_rot1(p); }
		if (kifs_fold == 1) {
			p = kifs_diagonal_fold(p);
		} else {
			if (kifs_fold == 2) { p = kifs_poly_fold(p); }
			p = menger_fold(p);
		}
		if (rot2) { p = kifs_rot2(p); }
		if (kifs_twist != 0.0) { p = mb_rot_plane(p, 0, 1, kifs_twist * float(i)); }
		p = s * p - (s - 1.0) * o;
		if (kifs_fold == 0) {
			// The Menger correction: reflect the far z layer back.
			float t = o.z * (s - 1.0);
			if (p.z < -0.5 * t) { p.z += t; }
		}
		n = i + 1;
		if (dot(p, p) > 1.0e6) { break; }
	}
}

// The distance from the orbit's end point, shrunk by the scale once per iteration.
float kifs_distance(vec4 p, int n) {
	float d = kifs_fold == 0 ? kifs_box_distance(p) : length(p);
	return d * pow(kifs_scale, -float(n));
}

float kifs_de(vec4 p, int iters) {
	int n = 0;
	kifs_orbit(p, n, 0, iters);
	return kifs_distance(p, n);
}
```

In `kleinian.gdshaderinc` replace `kleinian_de` with:

```glsl
// Iterations first..iters-1 of the Kleinian orbit p with running scale dr; stops
// early once a step leaves the point unchanged.
void kleinian_orbit(inout vec4 p, inout float dr, int first, int iters) {
	vec4 b = vec4(kleinian_box_0, kleinian_box_1, kleinian_box_2, kleinian_box_3);
	vec4 shift = vec4(kleinian_shift_0, kleinian_shift_1, kleinian_shift_2, kleinian_shift_3);
	float k = kleinian_radius * kleinian_radius;
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		vec4 before = p;
		p = clamp(p, -b, b) * 2.0 - p;
		float m = max(k / max(dot(p, p), 1e-12), 1.0);
		p = p * m + shift;
		dr *= m;
		if (p == before) { break; }
	}
}

float kleinian_distance(vec4 p, float dr) {
	float rxy = length(p.xy);
	float t = kleinian_thickness;
	return abs(0.5 * (abs(rxy * p.z) - t) / sqrt(dot(p, p) + abs(t))) / dr;
}

float kleinian_de(vec4 p, int iters) {
	float dr = 1.0;
	kleinian_orbit(p, dr, 0, iters);
	return kleinian_distance(p, dr);
}
```

- [ ] **Step 4: The Mandelbox loop takes a start index.** In `mandelbox.gdshader`, after `mb_constant(...)` and before the `#include` lines, add:

```glsl
// Iterations first..iters-1 of the Mandelbox orbit: the direct de() runs them all
// from 0 (exactly the loop it always ran), the perturbed de_pert() from its handoff.
void mb_orbit(inout vec4 z, inout float dz, vec4 c, int first, int iters) {
	bool rotating = mb_rotating();
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		mb_step(z, dz, c, rotating, i);
	}
}
```

and in `de()` replace the five lines from `bool rotating = mb_rotating();` through the loop's closing `}` with `mb_orbit(z, dz, c, 0, iters);`. The function now reads: `vec4 z0 = vec4(p, w); vec4 c = mb_constant(z0); vec4 z = z0; float dz = 1.0; mb_orbit(z, dz, c, 0, iters); return length(z) / abs(dz) + noise_displace(p);`. Same arithmetic in the same order.

- [ ] **Step 5: Write `src/fractal/perturbation.gdshaderinc`.**

```glsl
// Perturbation: the march past the 32-bit floor (spec: docs/superpowers/specs/
// 2026-10-09-perturbation-deep-zoom-design.md). Included by mandelbox.gdshader
// after calc_nf. While pert_iters > 0 the march never forms eye + dir * t for the
// estimate. The CPU (ReferenceOrbit) runs the camera's own orbit X_0 .. X_32 in
// 64-bit and hands down, for each of the first iterations, the gaps between X and
// each fold's creases: small numbers, which a 32-bit float holds precisely. The
// GPU iterates only the pixel's offset dl = P - X, with a difference formula per
// step that never subtracts two nearly equal large numbers, then adds the offset
// back at the handoff point X_k and finishes with the ordinary loop.
// tests/perturbation_port.gd is this file's GDScript twin: keep them in step.
//
// The record for iteration i (ReferenceOrbit builds it):
//   Mandelbox  a: lo - X per component of the fold's input (cylinder: a.xy = X.xy itself)
//              b: hi - X              c: the sphere fold's input point
//              d: (|c|^2 - min_r^2, |c|^2 - fixed_r^2, the reference's factor m, cylinder r_xy - L)
//   KIFS       a: -X after R1 (the abs gaps)
//              b: the three sort gaps, or the four diagonal gaps, each at its comparison
//              c.x: the Menger gap X_z + t/2 after the scale    d: X_{i+1}
//   Kleinian   a: -box - X    b: box - X    c: the post-fold point
//              d: (|c|^2 - radius^2, m, 0, 0)

uniform int pert_iters;    // k, the perturbed iterations; 0 = off (the direct march, exactly as before)
uniform vec4 pert_a[20];   // the record, ReferenceOrbit.PERT_MAX = 20 iterations
uniform vec4 pert_b[20];
uniform vec4 pert_c[20];
uniform vec4 pert_d[20];
uniform vec4 pert_end;     // X_k, the handoff point

const int PERT_MAX = 20;

// ---- the perturbed steps: each turns the offset entering a step into the offset leaving it

// A reflection through [lo, hi] (box fold, hybrid fold, Kleinian box), per
// component, given glo = lo - X and ghi = hi - X. One formula covers all nine
// side pairs (inside -> inside gives dl, inside -> above 2 ghi - dl, ...).
vec4 pert_clamp(vec4 dl, vec4 glo, vec4 ghi) {
	return 2.0 * (clamp(dl, glo, ghi) - clamp(vec4(0.0), glo, ghi)) - dl;
}

vec2 pert_clamp2(vec2 dl, vec2 glo, vec2 ghi) {
	return 2.0 * (clamp(dl, glo, ghi) - clamp(vec2(0.0), glo, ghi)) - dl;
}

// The KIFS abs fold: the clamp with its crease at 0 and none above; g = -X.
vec4 pert_abs(vec4 dl, vec4 g) {
	return 2.0 * (max(dl, g) - max(vec4(0.0), g)) - dl;
}

// One compare-and-swap of the KIFS sort (swap when a < b) on the offset pair
// d = (a, b), given g = X_a - X_b at that comparison.
vec2 pert_swap(vec2 d, float g) {
	bool ps = d.x - d.y < -g;   // the pixel swaps
	bool rs = g < 0.0;          // the reference swaps
	if (ps && rs) { return d.yx; }
	if (ps) { return vec2(d.y - g, d.x + g); }
	if (rs) { return vec2(d.x + g, d.y - g); }
	return d;
}

vec4 pert_sort(vec4 dl, vec4 g) {
	dl.xy = pert_swap(dl.xy, g.x);
	dl.xz = pert_swap(dl.xz, g.y);
	dl.yz = pert_swap(dl.yz, g.z);
	return dl;
}

// One diagonal reflection ((a, b) -> (-b, -a) when a + b < 0), given g = X_a + X_b.
vec2 pert_flip(vec2 d, float g) {
	bool ps = d.x + d.y < -g;
	bool rs = g < 0.0;
	if (ps && rs) { return -d.yx; }
	if (ps) { return vec2(-g - d.y, -g - d.x); }
	if (rs) { return vec2(d.x + g, d.y + g); }
	return d;
}

vec4 pert_diagonal(vec4 dl, vec4 g) {
	dl.xy = pert_flip(dl.xy, g.x);
	dl.xz = pert_flip(dl.xz, g.y);
	dl.yz = pert_flip(dl.yz, g.z);
	dl.xw = pert_flip(dl.xw, g.w);
	return dl;
}

// The Menger correction (z += t when z < -t/2) on the offset's z, given
// g = X_z + t/2 after the scale.
float pert_menger(float dz, float g, float t) {
	float pc = dz < -g ? 1.0 : 0.0;
	float rc = g < 0.0 ? 1.0 : 0.0;
	return dz + t * (pc - rc);
}

// The sphere fold (and the Kleinian inversion): dl' = m' dl + X (m' - m), m and m'
// the reference's and the pixel's factors. X is the fold's input (record c);
// gmin = |X|^2 - mr2 and gfix = |X|^2 - fr2 come from the CPU in full precision;
// q = |P|^2 - |X|^2 = 2 X.dl + dl.dl is a sum of products, so no cancellation.
// Regimes: 0 inside (factor fr2 / mr2), 1 shell (fr2 / |P|^2), 2 outside (1).
// m' - m is written per regime pair as a precise small number over a product,
// never as a difference of two factors.
void pert_sphere(inout vec4 dl, inout float dz, vec4 X, float gmin, float gfix, float mr2, float fr2) {
	float q = 2.0 * dot(X, dl) + dot(dl, dl);
	float x2 = dot(X, X);
	float p2 = x2 + q;
	int rx = gmin < 0.0 ? 0 : (gfix < 0.0 ? 1 : 2);
	int rp = gmin + q < 0.0 ? 0 : (gfix + q < 0.0 ? 1 : 2);
	float mp = rp == 0 ? fr2 / mr2 : (rp == 1 ? fr2 / max(p2, 1e-12) : 1.0);
	float dm = 0.0;
	if (rx == 1 && rp == 1) { dm = -fr2 * q / (p2 * x2); }
	else if (rx == 0 && rp == 1) { dm = -fr2 * (gmin + q) / (p2 * mr2); }
	else if (rx == 1 && rp == 0) { dm = fr2 * gmin / (mr2 * x2); }
	else if (rx == 1 && rp == 2) { dm = gfix / x2; }
	else if (rx == 2 && rp == 1) { dm = -(gfix + q) / p2; }
	else if (rx == 0 && rp == 2) { dm = 1.0 - fr2 / mr2; }
	else if (rx == 2 && rp == 0) { dm = fr2 / mr2 - 1.0; }
	dl = mp * dl + X * dm;
	dz *= mp;
}

// The cylinder fold's xy pair (r -> 2L - r outside the circle of radius L): the
// sphere fold's template with m = (2L - r) / r. X is the reference's xy (record
// a.xy), g = r - L its radial gap (record d.w).
vec2 pert_cylinder(vec2 d, vec2 X, float g) {
	float L = fold_limit;
	float rr = L + g;
	float q = 2.0 * dot(X, d) + dot(d, d);
	float rp = sqrt(max(rr * rr + q, 0.0));
	float dr = q / max(rp + rr, 1e-30);   // r' - r without cancellation
	bool xo = g > 0.0;
	bool po = g + dr > 0.0;
	float mp = po ? (2.0 * L - rp) / rp : 1.0;
	float dm = 0.0;
	if (xo && po) { dm = -2.0 * L * dr / (rr * rp); }
	else if (po) { dm = -2.0 * (g + dr) / rp; }
	else if (xo) { dm = 2.0 * g / rr; }
	return mp * d + X * dm;
}

// The Mandelbox's fold step on the offset: the clamp on every component (the
// box fold, or on a hybrid iteration the hybrid interval: the CPU's gaps already
// use the right creases), or the cylinder fold on xy and the clamp on zw.
vec4 pert_mb_fold(vec4 dl, vec4 a, vec4 b, float gr, int i) {
	bool hybrid = false;
	if (hybrid_mix > 0.0) {
		int every = max(hybrid_every, 1);
		hybrid = i % every == every - 1;
	}
	if (fold_shape == 1 && !hybrid) {
		return vec4(pert_cylinder(dl.xy, a.xy, gr), pert_clamp2(dl.zw, a.zw, b.zw));
	}
	return pert_clamp(dl, a, b);
}

// ---- the perturbed estimates

float de_pert_mandelbox(vec4 dl, vec3 p, int iters) {
	int k = pert_iters;
	// The pixel's c differs from the reference's by its own starting offset where
	// c follows the point (Mandelbrot mode), by nothing where c is the Julia
	// constant; w is the slice's own, the same for both.
	vec4 dc = vec4(
		(julia_all || julia_0) ? 0.0 : dl.x,
		(julia_all || julia_1) ? 0.0 : dl.y,
		(julia_all || julia_2) ? 0.0 : dl.z,
		0.0);
	float mr2 = max(min_radius * min_radius, 1e-12);
	float fr2 = max(fixed_radius * fixed_radius, 1e-12);
	float dz = 1.0;
	bool rotating = mb_rotating();
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= k) { break; }
		vec4 ra = pert_a[i];
		vec4 rb = pert_b[i];
		vec4 rc = pert_c[i];
		vec4 rd = pert_d[i];
		if (fold_order == 0) {
			dl = pert_mb_fold(dl, ra, rb, rd.w, i);
			pert_sphere(dl, dz, rc, rd.x, rd.y, mr2, fr2);
		} else {
			pert_sphere(dl, dz, rc, rd.x, rd.y, mr2, fr2);
			dl = pert_mb_fold(dl, ra, rb, rd.w, i);
		}
		if (rotating) { dl = mb_iter_rotate(dl); }
		float s = box_scale + scale_drift * float(i);
		dl = s * dl + dc;
		dz = dz * abs(s) + 1.0;
	}
	vec4 z = pert_end + dl;
	vec4 c = mb_constant(vec4(p, w));   // 32-bit c: its rounding is shrunk by the magnification like everything else
	mb_orbit(z, dz, c, k, max(iters, k));
	return length(z) / abs(dz);
}

float de_pert_kifs(vec4 dl, int iters) {
	int k = pert_iters;
	float s = kifs_scale;
	float t = kifs_offset_2 * (s - 1.0);
	bool rot1 = kifs_rot1_on();
	bool rot2 = kifs_rot2_on();
	int n = 0;
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= k) { break; }
		if (rot1) { dl = kifs_rot1(dl); }
		if (kifs_fold == 1) {
			dl = pert_diagonal(dl, pert_b[i]);
		} else {
			dl = pert_sort(pert_abs(dl, pert_a[i]), pert_b[i]);
		}
		if (rot2) { dl = kifs_rot2(dl); }
		if (kifs_twist != 0.0) { dl = mb_rot_plane(dl, 0, 1, kifs_twist * float(i)); }
		dl = s * dl;   // the offset term -(s - 1) o cancels
		if (kifs_fold == 0) { dl.z = pert_menger(dl.z, pert_c[i].x, t); }
		n = i + 1;
		vec4 zi = pert_d[i] + dl;   // the pixel's point: large, fine in 32 bits
		if (dot(zi, zi) > 1.0e6) { return kifs_distance(zi, n); }   // the pixel escapes first
	}
	vec4 z = pert_end + dl;
	kifs_orbit(z, n, k, max(iters, k));
	return kifs_distance(z, n);
}

float de_pert_kleinian(vec4 dl, int iters) {
	int k = pert_iters;
	float kk = kleinian_radius * kleinian_radius;
	float dr = 1.0;
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= k) { break; }
		dl = pert_clamp(dl, pert_a[i], pert_b[i]);
		// the inversion: the sphere fold's template with no inner core and
		// fixed_radius^2 = radius^2; the shift cancels
		pert_sphere(dl, dr, pert_c[i], 1.0e30, pert_d[i].x, kk, kk);
	}
	vec4 z = pert_end + dl;
	kleinian_orbit(z, dr, k, max(iters, k));
	return kleinian_distance(z, dr);
}

// The estimate at eye + off while pert_iters > 0, without forming that sum for the
// orbit. The noise field is still evaluated at the 32-bit point: a displaced
// surface is smooth below the displacement's size, so there is nothing finer to
// resolve.
float de_pert(vec3 off, int iters) {
	vec3 p = eye + off;
	if (shape == 3) { return de(p, iters); }   // never perturbed (ReferenceOrbit.perturbable is false)
	vec4 dl = vec4(off, 0.0);
	float d;
	if (shape == 1) { d = de_pert_kifs(dl, iters); }
	else if (shape == 2) { d = de_pert_kleinian(dl, iters); }
	else { d = de_pert_mandelbox(dl, p, iters); }
	return d + noise_displace(p);
}

// The march's estimate at ray distance t: the perturbed one while pert_iters > 0,
// else exactly today's de(eye + dir * t). pos is that 32-bit point, off = dir * t.
float march_de(vec3 pos, vec3 off, int iters) {
	if (pert_iters > 0) { return de_pert(off, iters); }
	return de(pos, iters);
}

// calc_normal for the perturbed march: central differences of de_pert around off.
vec3 calc_normal_pert(vec3 off, float delta) {
	vec2 e = vec2(delta, 0.0);
	return normalize(vec3(
		de_pert(off + e.xyy, 32) - de_pert(off - e.xyy, 32),
		de_pert(off + e.yxy, 32) - de_pert(off - e.yxy, 32),
		de_pert(off + e.yyx, 32) - de_pert(off - e.yyx, 32)));
}

// The true surface normal at v = eye + off: today's calc_normal(v, delta) while
// pert_iters is 0.
vec3 true_normal(vec3 v, vec3 off, float delta) {
	if (pert_iters > 0) { return calc_normal_pert(off, delta); }
	return calc_normal(v, delta);
}
```

- [ ] **Step 6: Wire it into `mandelbox.gdshader`.** Four small edits, nothing else:
  1. After `calc_nf(...)`'s closing brace: `#include "res://src/fractal/perturbation.gdshaderinc"`.
  2. Phase 1 loop: `float d = de(pos, n_coarse);` → `float d = march_de(pos, dir * total, n_coarse);`.
  3. Phase 2 loop: `float d = de(pos, 32);` → `float d = march_de(pos, dir * total, 32);`.
  4. In the normal block, each of the three `calc_normal(v, delta)` → `true_normal(v, dir * total, delta)`.
  Add one line to the file's header comment: "Past the 32-bit floor the march runs perturbed (perturbation.gdshaderinc); with pert_iters 0 every path is exactly the direct one."

- [ ] **Step 7: Push from the view.** In `fractal_view.gd` add, beside `_center_ray`:

```gdscript
## The perturbed march's iteration count last pushed (0: off). Main shows it in
## the Movement pane as "deep k=N".
var _pert_iters := 0
## How many times the per-iteration record was pushed: never while perturbation
## is off, once per camera or shape change while it is on (the tests read it).
var _pert_pushes := 0
```

an accessor after `center_ray()`:

```gdscript
## How many iterations the shader perturbs for the current camera (0: off).
func pert_iters() -> int:
	return _pert_iters
```

and replace `_push_near()` (and its comment):

```gdscript
## The camera's distance to the nearest surface, which the level-of-detail range
## is measured in, and the coarse pass's iteration count and the shading
## crossfade that follow from it; and the perturbed march's iteration count and
## record. All come from one ReferenceOrbit built at the 64-bit eye (its distance
## is the estimate, so nothing is computed twice). They depend on both the camera
## and the shape, so both pushes refresh them. The record arrays are pushed only
## while perturbation is on.
func _push_near() -> void:
	if _material == null or _params == null or _camera == null:
		return
	var e := _camera.eye64()
	var orbit := ReferenceOrbit.build(_params, e[0], e[1], e[2])
	var near := maxf(orbit.distance, FractalParams.NEAR_FLOOR)
	_material.set_shader_parameter("near_dist", near)
	_material.set_shader_parameter("coarse_iters", _params.coarse_iters(near))
	_material.set_shader_parameter("nf_weight", FractalParams.nf_weight(near))
	_pert_iters = _params.pert_iters(orbit, orbit.distance)
	_material.set_shader_parameter("pert_iters", _pert_iters)
	if _pert_iters > 0:
		_material.set_shader_parameter("pert_a", orbit.a)
		_material.set_shader_parameter("pert_b", orbit.b)
		_material.set_shader_parameter("pert_c", orbit.c)
		_material.set_shader_parameter("pert_d", orbit.d)
		_material.set_shader_parameter("pert_end", orbit.points[_pert_iters])
		_pert_pushes += 1
```

At the default view `orbit.distance` is `DistanceEstimator.estimate(eye)` exactly (the eye's doubles are its 32-bit origin), so `near_dist`, `coarse_iters` and `nf_weight` are bit-for-bit what they were.

- [ ] **Step 8: Run `shader_test` and `fractal_view_test`, expect PASS.** A shader that fails to compile shows up as an empty uniform list: read Godot's error output for the line.

- [ ] **Step 9: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add src/fractal/perturbation.gdshaderinc src/fractal/perturbation.gdshaderinc.uid src/fractal/mandelbox.gdshader src/fractal/kifs.gdshaderinc src/fractal/kleinian.gdshaderinc src/fractal/fractal_view.gd tests/shader_test.gd tests/fractal_view_test.gd
git -C $WT commit -m "feat(shader): the perturbed march past the 32-bit floor" -m "de_pert iterates each pixel's offset from the CPU's reference orbit with per-fold difference formulas (the twin of tests/perturbation_port.gd), then hands off at X_k to the ordinary loop. Each shape's loop takes a start index; the direct path calls it from 0, the same arithmetic in the same order, and with pert_iters 0 every path is today's: the default view is unchanged. FractalView pushes pert_* from the orbit it builds at the 64-bit eye, the record only while on." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: The fly camera's guard in 64-bit, and the speed floor

**Files:**
- Modify: `src/camera/fly_camera.gd`
- Test: `tests/fly_camera_test.gd`, `tests/center_ray_test.gd`

**Interfaces:**
- Consumes: `ReferenceOrbit`, `FractalParams.zoom_floor_for`.
- Produces: `FlyCamera.SPEED_FLOOR := 1e-14`; `FlyCamera.move_allowed(from: PackedFloat64Array, to: PackedFloat64Array) -> bool`.

- [ ] **Step 1: Failing tests.** In `tests/fly_camera_test.gd`:
  - In the speed block, `clampf(minf(ahead, near * FlyCamera.NEAR_CAP), 1e-6, 20.0)` → `clampf(..., FlyCamera.SPEED_FLOOR, 20.0)` and `clampf(near, 1e-6, 20.0)` → `clampf(near, FlyCamera.SPEED_FLOOR, 20.0)`. Do the same for the two `clampf(..., 1e-6, 20.0)` in `tests/center_ray_test.gd`. Add `check_eq(FlyCamera.SPEED_FLOOR, 1e-14, "the speed floor is 1e-14, below any zoom floor")`.
  - `_fly_at` steps in 64-bit (a 32-bit origin stalls below about 1e-6). Replace its stepping lines (from `var t := cam.transform` to the `inside` check) with:

```gdscript
		var e := cam.eye64()
		var f := cam.forward()
		var to := PackedFloat64Array([e[0] + f.x * step, e[1] + f.y * step, e[2] + f.z * step])
		if not fly.move_allowed(e, to):
			break   # at the zoom floor
		travelled += step
		cam.set_eye64(to[0], to[1], to[2])
		if DistanceEstimator.estimate_at(to[0], to[1], to[2], params) < 0.0:
			inside = true
```


  - `_surface_within` marches from a 64-bit origin (called as `_surface_within(cam.eye64(), cam.forward(), step, params)`):

```gdscript
func _surface_within(origin: PackedFloat64Array, dir: Vector3, length: float, params: FractalParams) -> bool:
	var near := maxf(DistanceEstimator.estimate_at(origin[0], origin[1], origin[2], params), FractalParams.NEAR_FLOOR)
	var t := 0.0
	for i in 400:
		var d := DistanceEstimator.estimate_at(origin[0] + dir.x * t, origin[1] + dir.y * t, origin[2] + dir.z * t, params)
		if d < params.hit_epsilon(maxf(t, near), near):
			return t < length
		t += 0.25 * d
		if t >= length:
			return false
	return false
```

  - Add `await _deep_flight()` after `await _zoom_floor_guard()` in `run()`, and the function:

```gdscript
## On the default box, from below today's 32-bit floor (where the old guard
## refused W), holding W closes in by more than ten times and stops at the new
## floor, with the steps shrinking as the distance does.
func _deep_flight() -> void:
	var ctx := _fresh()
	var params: FractalParams = ctx[0]
	var cam: CameraState = ctx[1]
	var fly: FlyCamera = ctx[2]
	var s := SurfaceFixture.default_surface(params)
	var f32 := params.floor32(PackedFloat64Array([s[0], s[1], s[2]]))
	_place(cam, s, SurfaceFixture.back_for_distance(params, s, 0.5 * f32))
	var e0 := cam.eye64()
	var d0 := DistanceEstimator.estimate_at(e0[0], e0[1], e0[2], params)
	check(d0 < params.floor32(e0), "the camera starts below the 32-bit floor (%s < %s): the old guard refused W" % [d0, params.floor32(e0)])
	check(d0 > params.zoom_floor(e0), "and above the new one (%s)" % params.zoom_floor(e0))
	fly.enabled = true
	var first_step := -1.0
	var last_step := 0.0
	Input.action_press("move_forward")
	for _i in 2000:
		var before := cam.eye64()
		await physics_frame
		if fly.at_zoom_limit:
			break
		var now := cam.eye64()
		last_step = sqrt((now[0] - before[0]) ** 2 + (now[1] - before[1]) ** 2 + (now[2] - before[2]) ** 2)
		if first_step <= 0.0:
			first_step = last_step   # the first tick after the press may not have moved yet
	Input.action_release("move_forward")
	check(fly.at_zoom_limit, "holding W reaches the new zoom limit")
	var e1 := cam.eye64()
	var d1 := DistanceEstimator.estimate_at(e1[0], e1[1], e1[2], params)
	check(d1 < 0.1 * d0, "after closing in more than ten times (%s from %s)" % [d1, d0])
	check(d1 >= params.zoom_floor(e1), "and stopping at the floor, not past it (%s over %s)" % [d1, params.zoom_floor(e1)])
	check(last_step < 0.1 * first_step and last_step < 2e-7,
		"the speed follows the distance: the last step %s against the first %s" % [last_step, first_step])
	fly.enabled = false
	fly.queue_free()
	await frames(1)
```


- [ ] **Step 2: Run, expect FAIL** (`SPEED_FLOOR` not found; `move_allowed` given `PackedFloat64Array`s; the deep flight stalls at the 1e-6 speed clamp).

- [ ] **Step 3: Implement in `fly_camera.gd`.**

```gdscript
## base_speed()'s lowest value. The speed is about the distance to the surface,
## so it must be able to fall below any zoom floor or the camera would outrun its
## own stop.
const SPEED_FLOOR := 1e-14
```

In `_physics_process`, replace the block Task 2 added (from `# The step is added in 64-bit` through `_camera.set_eye64(nx, ny, nz)`) with this, where the guard is 64-bit too:

```gdscript
	# The step is added in 64-bit: below about 1e-6 a 32-bit origin could not move.
	var step := current_speed() * delta
	var e := _camera.eye64()
	var to := PackedFloat64Array([e[0] + dir.x * step, e[1] + dir.y * step, e[2] + dir.z * step])
	if not move_allowed(e, to):
		at_zoom_limit = true
		return
	at_zoom_limit = false
	_camera.set_eye64(to[0], to[1], to[2])
```

```gdscript
## Whether the camera may move from `from` to `to` (64-bit eyes): yes when `to` is
## at least the zoom floor from the surface, or no closer than `from` is (backing
## away is always allowed, so a camera already past the floor, say from a loaded
## save, can leave). One ReferenceOrbit at `to` gives both its distance and its
## floor. The speed already shrinks with the distance, so the last accepted step
## before the floor is tiny and the stop does not pop.
func move_allowed(from: PackedFloat64Array, to: PackedFloat64Array) -> bool:
	var orbit := ReferenceOrbit.build(_params, to[0], to[1], to[2])
	if orbit.distance >= _params.zoom_floor_for(orbit):
		return true
	return orbit.distance >= DistanceEstimator.estimate_at(from[0], from[1], from[2], _params)
```

`base_speed()`: the distance from the 64-bit eye, and the new floor:

```gdscript
func base_speed() -> float:
	var e := _camera.eye64()
	var near := DistanceEstimator.estimate_at(e[0], e[1], e[2], _params)
	var d := minf(_ray.distance(), near * NEAR_CAP)
	return clampf(d, SPEED_FLOOR, 20.0) * _camera.speed_factor * speed_limit
```

Update the class header: "A move that would take the camera below the zoom floor (FractalParams.zoom_floor: where the perturbed march or 32 iterations run out, or the 32-bit floor for shapes that are not perturbed) is refused. The eye moves in 64-bit."

- [ ] **Step 4: Run `fly_camera_test`, `center_ray_test`, `main_test`, `ui_journey_test`, expect PASS.**

- [ ] **Step 5: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add src/camera/fly_camera.gd tests/fly_camera_test.gd tests/center_ray_test.gd
git -C $WT commit -m "feat(fly): the zoom guard in 64-bit at the new floor, speed floor 1e-14" -m "move_allowed builds one ReferenceOrbit at the candidate eye for both its distance and its floor. On the default box a camera below today's 32-bit floor now closes in more than ten times before the limit." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: `deep k=N` in the Movement pane

**Files:**
- Modify: `src/ui/console/movement_pane.gd`, `src/ui/console/console_window.gd`, `src/main.gd`
- Test: `tests/console_test.gd`, `tests/ui_console_test.gd`, `tests/main_test.gd`

**Interfaces:**
- Consumes: `FractalView.pert_iters()` (Task 5).
- Produces: `MovementPane.deep_label: Label`, `MovementPane.show_deep(k: int) -> void`, `ConsoleWindow.show_deep(k: int) -> void`.

- [ ] **Step 1: Failing tests.**

`tests/console_test.gd`, after the zoom-limit block:

```gdscript
	# --- Movement pane: "deep k=N" while the march is perturbed, hidden at 0 ---
	check(movement.deep_label != null and not movement.deep_label.visible, "the deep readout starts hidden")
	console.show_deep(14)
	check(movement.deep_label.visible and movement.deep_label.text == "deep k=14",
		"show_deep(14) shows 'deep k=14' in the Movement pane")
	console.show_deep(0)
	check(not movement.deep_label.visible, "and 0 hides it again")
```

`tests/ui_console_test.gd`, beside the zoom-limit layout check (the worst case: both readouts shown):

```gdscript
	pane.show_zoom_limit(true)
	pane.show_deep(20)
	await ui.frames(1)
	check(pane.deep_label.is_visible_in_tree() and win.encloses(ui.global_rect(pane.deep_label)),
		"the deep readout, shown beside the zoom limit, is inside the window (%s)" % ui.global_rect(pane.deep_label))
	check(win.encloses(ui.global_rect(pane.reset_camera_button)),
		"and Reset camera still is (%s)" % ui.global_rect(pane.reset_camera_button))
	pane.show_deep(0)
	pane.show_zoom_limit(false)
	await ui.frames(1)
```

`tests/main_test.gd`, after the zoom-limit block:

```gdscript
	# the perturbed march's k reaches the Movement pane each frame
	var deep_label: Label = main.console().movement_pane().deep_label
	main.view._pert_iters = 14
	main._process(0.0)
	check(deep_label.visible and deep_label.text == "deep k=14", "Main shows the view's k in the Movement pane")
	main.view._pert_iters = 0
	main._process(0.0)
	check(not deep_label.visible, "and hides it at 0")
```

- [ ] **Step 2: Run, expect FAIL** (`deep_label`, `show_deep` not found).

- [ ] **Step 3: Implement.** `movement_pane.gd`: beside `zoom_label`:

```gdscript
## "deep k=14", on the speed readout line, shown only while the renderer is
## perturbing (FractalView.pert_iters() > 0).
var deep_label: Label
var _deep_k := 0
```

In the speed row, right after `show_zoom_limit(_zoom_limit)`:

```gdscript
	deep_label = Label.new()
	deep_label.tooltip_text = "The renderer is past the 32-bit limit: each ray's first k iterations follow the camera's own orbit, worked out in 64-bit on the CPU, and the GPU iterates only the ray's small offset from it (perturbation). Hidden while off."
	speed_row.add_child(deep_label)
	show_deep(_deep_k)
```

Update `zoom_label.tooltip_text` to: "The fly camera is as close to the surface as the renderer can draw: nearer, 32 iterations run out of detail or the perturbed march runs out of precision (for shapes it does not perturb, the 32-bit positions). Moving away is always allowed." Add:

```gdscript
## The perturbed march's iteration count; the readout shows only while it is above 0.
func show_deep(k: int) -> void:
	_deep_k = k
	if deep_label == null:
		return
	deep_label.text = "deep k=%d" % k
	deep_label.visible = k > 0
```

and extend the file's header line about the readout ("with "zoom limit" and "deep k=N" beside it while ..."). `console_window.gd`:

```gdscript
## The perturbed march's k, shown in the Movement pane while above 0.
func show_deep(k: int) -> void:
	_movement.show_deep(k)
```

`main.gd` `_process`, after `show_zoom_limit`: `_console.show_deep(view.pert_iters())`, and extend its comment ("and the view's perturbed iteration count").

- [ ] **Step 4: Run the three tests, expect PASS.**

- [ ] **Step 5: Full suite and commit.**

```bash
$WT/tests/run_all.sh; echo exit=$?
git -C $WT add src/ui/console/movement_pane.gd src/ui/console/console_window.gd src/main.gd tests/console_test.gd tests/ui_console_test.gd tests/main_test.gd
git -C $WT commit -m "feat(console): Movement pane shows \"deep k=N\" while the march is perturbed" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: README

**Files:** Modify `README.md`.

- [ ] **Step 1: Rewrite the Deep zoom section's "Zoom limit" bullet** into three bullets (keep "Coarse pass iterations" and "Lighting" as they are; update the section's opening line: four things now adjust themselves):
  - **A 64-bit eye.** The camera's position is three 64-bit numbers; the 32-bit transform the renderer reads is their rounding. The fly step, the centre ray and saves use the 64-bit ones (a saved view keeps the eye to within one 64-bit rounding step).
  - **Perturbation.** Plain words first: the CPU runs the camera's own orbit once per frame in 64-bit (`X_0` the eye, `X_1` its first iterate, ...); each pixel starts a small offset `δ_0 = dir × t` away, and for its first `k` iterations the GPU follows only `δ_{i+1} = f(X_i + δ_i) − f(X_i)`, never the pixel's own point. Each fold's difference is worked out from the gap between the crease and `X` (crease minus `X`, computed in 64-bit, small when precision matters), so nothing subtracts two nearly equal large numbers ("catastrophic cancellation": one line of explanation). Once the offset has grown by the magnification `λ_k` to `λ_k × d₀ ≥ 0.1`, the GPU adds it back to `X_k` and finishes with the ordinary loop. `k` is the smallest such, at most 20; it switches on within `10 ×` the 32-bit floor, where both marches agree, so there is no pop. The Movement pane shows `deep k=N` while it is on. Link the spec and Wikipedia's [perturbation theory](https://en.wikipedia.org/wiki/Plotting_algorithms_for_the_Mandelbrot_set#Perturbation_theory_and_series_approximation) section.
  - **Zoom limit.** Two floors, the camera stops at the larger: `floor_pert = ulp32(max |X_K|) / (50 × eps × λ_K)` (the old 32-bit rule applied at the handoff point, `K = min(20, n)`) and `floor_iter = 0.25 / (eps × λ_32)` (where 32 iterations stop adding detail: inside the shape the estimate cannot fall below about a quarter over the 32-iteration magnification). Give the numbers: about `6e-7` for the default box (the old floor was about `1e-4`), `4e-8` for the ice field, `2e-6` for the terraces, far lower for the KIFS; the Kleinian has only `floor_pert`. Shapes it does not perturb (the octahedral fold, the KIFS polyfold, the Mandelbulb) keep the 32-bit floor `ulp32(largest |eye coordinate|) / (50 × eps)`. A noise field's displacement is still evaluated at the 32-bit position (a displaced surface is smooth below its displacement anyway). Going deeper than `floor_iter` needs more than 32 iterations (a follow-up). Keep the existing sentences about the `zoom limit` readout and moving away always being allowed.
- [ ] **Step 2: Fly camera section:** the zoom-limit sentence links the new floors; mention the speed can fall to `1e-14`.
- [ ] **Step 3: Saved views section:** the eye is written at full precision (search the section for "significant" or "7" and adjust any statement that all numbers are tidied).
- [ ] **Step 4: Testing section:** add a paragraph: `perturbation_test.gd` (a GDScript port of the shader's perturbed step run in emulated float32: each fold's difference formula case by case, whole orbits in 64-bit against the direct orbit, and the march at 1e-5, 1e-6 and 1e-7 from five fixtures, where today's float32 march gets under 30% of rays right and the perturbed one at least 90%); `reference_orbit_test.gd` (the reference orbit's distance is the estimator's exactly).
- [ ] **Step 5: Run `$WT/tests/run_all.sh` (unchanged code, still green) and commit.**

```bash
git -C $WT add README.md
git -C $WT commit -m "docs(readme): deep zoom: the 64-bit eye, perturbation, the handoff and the two floors" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: The `deep-zoom` viz pane (last)

**Files:**
- Create: `docs/viz/panes/deep-zoom.js`
- Modify: `docs/viz/index.html` (one `<script>` line under the `PANES:` comment), `docs/viz/glossary.js`

- [ ] **Step 1: Invoke the `visualize` skill** (Skill tool, `visualize`, args `deep-zoom: perturbation past the 32-bit floor, per the spec's part 7`) and follow it. Read `.claude/skills/visualize/reference.md` and `docs/viz/panes/mandelbox.js` first (the stepper pattern). Pass the user's rules to any agent it dispatches: headless only (the in-app browser pane and headless Chrome are fine, no windowed app), no `rm -rf`, no push, commit by explicit path.

- [ ] **Step 2: Pin the commit.** `git -C $WT rev-parse HEAD` after Task 8 (the branch's final code). `pinNote: "perturbation branch, unpushed: links 404 until it is pushed"`. Read every cited line at that commit (`git -C $WT show HEAD:<path>`).

- [ ] **Step 3: Get the Measured table.** `godot4 --headless --path $WT -s tests/perturbation_test.gd | grep MEASURED`: these rows are tab 8's data (copy the numbers; the tab's note says they come from `perturbation_test.gd` at the pinned commit).

- [ ] **Step 4: Write the pane**, id `deep-zoom`, short `Deep zoom`. `ctx`: `cpu` (64-bit CPU, hue 1), `bridge` (the uniforms, hue 4), `gpu` (float32 GPU, hue 2), `test` (tests, hue 6). The ten tabs, in order (each tab one diagram):
  1. **Architecture** (graph, first, carries title and subtitle): zones *64-bit CPU* (`CameraState` eye64, `FlyCamera`, `CenterRay`, `ReferenceOrbit`, `Workspace`, `FractalParams` pert_iters / floors), *the bridge* (`pert_iters`, `pert_a..d`, `pert_end`, `near_dist`, `coarse_iters`, `nf_weight`), *float32 GPU* (`fragment`, `march_de`, `de` / `de_pert`, `true_normal` / `calc_normal_pert`). Edges link the calls (`_push_near` → `ReferenceOrbit.build`, `move_allowed` → `zoom_floor_for`, `set_shader_parameter`, ...).
  2. **Why 32-bit breaks** (live figure): a log slider for the camera distance `d` (1e-3 .. 1e-10); draw the float32 grid near the eye (`ulp32(2) ≈ 2.4e-7`), the view's width in grid steps (`2 d tan 20°` / ulp), the hit threshold `eps × d`, and the same view after `k` perturbed iterations (`λ_k × d`), with `k` from the default box's λ (port `ReferenceOrbit`'s Mandelbox loop in JS doubles).
  3. **One frame at depth** (seq): camera `changed` → `FractalView._on_camera_changed` → `_push_near` → `ReferenceOrbit.build` → `FractalParams.pert_iters` → `set_shader_parameter` (pert_*) → `fragment`: `box_intersect`, coarse loop (`march_de`), fine loop, `true_normal`, shade.
  4. **The reference orbit** (live figure): per save (default box, ice field, terraces; the JS port finds each surface point from the default eye as `SurfaceFixture.surface_from` does), the eye's 32 iterates, `λ_i` on a log axis, and the hoverable per-iteration record (`a`, `b`, `c`, `d` with what each slot means).
  5. **δ step by step** (stepper, the mandelbox pane's pattern): one pixel's offset through the iterations; the frame read beside the frame written; Step / Back / Reset; each stage (fold, sphere fold, rotate, scale, add) with its shader line (`perturbation.gdshaderinc`) and GDScript line (`tests/perturbation_port.gd`); three columns: 64-bit exact (JS doubles), float32 perturbed and float32 direct (`Math.fround` after every operation, as the port's `r()`); crossings flagged. A JS port of `pert_clamp`, `pert_sphere` and the Mandelbox `de_pert` loop.
  6. **Crossing a fold** (figure): the clamp-difference formula on a draggable axis (`X`, `δ`, the two creases, the 3 × 3 case table lighting up), and the sphere fold's three regimes with the `m' − m` row for the current pair.
  7. **Handoff and floors** (live figure + table, grouped): `λ_k` against `k` per save on a log axis with the `PERT_HANDOFF` (0.1) line and the chosen `k` for a slider'd `d`; a table of `floor32`, `floor_pert`, `floor_iter` per save computed by the port.
  8. **Measured** (table): the MEASURED rows from Step 3.
  9. **Coarse pass and lighting** (live figure): `coarse_iters(near)` and `nf_weight(near)` against `d` on a log axis, with the formulas (`FractalParams.coarse_iters`, `nf_weight`).
  10. **Cards**: invariants (hue 3: the default view is bit-for-bit; `pert_iters == 0` is today's path; `eye()` is the rounded shadow; `ReferenceOrbit.distance` equals the estimator exactly), gotchas (hue 2: `Vector3` is 32-bit; `Workspace._tidy` and JSON's 15 digits; the old 1e-6 speed clamp; the WebGL uniform budget (80 `vec4`s); folds that keep the 32-bit floor; noise at 32-bit; `iters < k` resumes to `max(iters, k)`), history (hue 6: the self-similar substitution note; the two-float option; `floor_iter`'s radius recalibrated from `bound_half`; the sort formula corrected), open (hue 4: polyfold and octahedral folds, the Mandelbulb, more than 32 iterations past `floor_iter`, the orbit camera, the `perturbation-design` pane).

- [ ] **Step 5: Glossary entries** in `docs/viz/glossary.js` (ids new; check the existing ids first: `orbit` and `ulp` exist, so match `reference orbit` as a phrase and do not re-add `ulp`):
  - `perturbation`: "Following a pixel's small difference from a nearby reference instead of the pixel itself. Here the reference is the camera's own orbit, worked out once per frame in 64-bit on the CPU; the GPU iterates only each pixel's offset from it, which 32-bit floats hold precisely because it is small. Deep Mandelbrot-set zoomers use the same trick." Links: Wikipedia's perturbation section (URL above), then a friendlier explainer if one is found.
  - `reference_orbit` (match `["reference orbit"]`): "The camera eye's own 32 iterates, X_0 .. X_32, computed on the CPU in 64-bit (ReferenceOrbit). Every pixel's orbit is described as this one plus a small offset."
  - `catastrophic_cancellation` (match `["catastrophic cancellation", "cancellation"]`): "Subtracting two nearly equal numbers: the leading digits cancel and only the noisy last ones remain. 2.0000001 − 2.0000000 in 32-bit floats keeps about one correct digit. The perturbed step is written so it never does this." Wikipedia: Catastrophic_cancellation.
  - `magnification` (match `["magnification", "magnifies"]`): "How much the iteration has stretched a small neighbourhood after i steps, λ_i: the product of |scale| and the sphere fold's factors (the running derivative dz without its + 1s). A view 1e-7 wide is λ_k × 1e-7 wide after k iterations."
  - `piecewise_linear` (match `["piecewise-linear", "piecewise linear"]`): "A map made of straight-line pieces joined at creases: a box fold is linear on each side of its mirror. The difference of a linear map is the same map applied to the difference, so only the creases need care." Wikipedia: Piecewise_linear_function.
  - `double_float` (term "Double-float (two-float)", match `["double-float", "two-float", "double-double"]`): "Carrying each number as the sum of two ordinary floats for about twice the precision. Exact, but about 7 times the cost per ray here, and a GPU compiler may reorder the steps that make it work." Wikipedia: Quadruple-precision_floating-point_format#Double-double_arithmetic.

- [ ] **Step 6: Verify as the skill says:** `node tools/viz/check.mjs --print --pane deep-zoom` exits 0 and every printed line is the one its tooltip describes; open every tab (`#deep-zoom/1` .. `/10`) in the in-app browser (or headless Chrome with the skill's command), `VIZ.errors` is `[]`, screenshot each and fix overlaps; `VIZ.frameMs` well under 16 ms on the live tabs and about 0 on the others; the new glossary marks land on the right words.

- [ ] **Step 7: Final verification of the branch.** `$WT/tests/run_all.sh; echo exit=$?`: every suite PASSED, exit 0. Report the counts and the perturbation table. The windowed check is the user's: `tests/screenshots.sh` must show the default view pixel-identical before and after, and a flight on the default box down to its new floor (about `6e-7`) and on the Menger sponge to `1e-8` must show detail, not speckle.

- [ ] **Step 8: Commit.**

```bash
git -C $WT add docs/viz/panes/deep-zoom.js docs/viz/index.html docs/viz/glossary.js
git -C $WT commit -m "docs(viz): deep-zoom pane: the 64-bit eye, the reference orbit and the perturbed march" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Then tell the user the branch is ready (`./viz.sh deep-zoom` once merged; the links 404 until pushed). Do not push.
