# KIFS and Kleinian shapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add KIFS and pseudo-Kleinian shapes beside the Mandelbox, plus the Mandelbox fold-shape, hybrid and scale-drift options.

**Architecture:** One `shape` catalogue row switches `de()` in the existing raymarcher; each shape's GLSL lives in an include with its own uniforms, and each has a 64-bit CPU twin behind `DistanceEstimator`. `ShapeCatalogue` assembles the per-shape spec lists; `show_when` hides the rows of the shapes not in use.

**Tech Stack:** Godot 4.6.1 GL Compatibility, GDScript, headless `TestCase` tests (`tests/run_all.sh`).

Spec: `docs/superpowers/specs/2026-10-08-kifs-kleinian-shapes-design.md`.
Executed inline by the session that wrote it, so each task names files,
interfaces and tests; the code lands in that task's commit.

## Global Constraints

- GDScript only; GL Compatibility (WebGL 2): highp float32 in shaders, no `double`.
- CPU estimators use 64-bit scalar `float` locals, never Vector math, and mirror the shader at N = 32.
- Every new knob at its default leaves today's Mandelbox picture and CPU fixtures bit-for-bit unchanged.
- Catalogue ids = shader uniform names = FractalParams fields; `RESOLVED_KEYS == ShapeCatalogue.catalogue_ids()`.
- Saves stay version 2; a file without `shape` loads as Mandelbox.
- Godot runs headless only (`--headless`), except the single agreed screenshot batch through `tests/screenshots.sh` (`open -g`).
- Work only in `.claude/worktrees/shapes-kifs-kleinian`; commit, never push.

---

### Task 1: Mandelbox options (CPU)

**Files:** Modify `src/fractal/fractal_params.gd`, `src/fractal/distance_estimator.gd`, `src/fractal/mandelbox_shape.gd`; Test `tests/distance_estimator_test.gd`, new `tests/lipschitz_test.gd`.

**Interfaces — Produces:** FractalParams fields `fold_shape:int`, `hybrid_mix:float`, `hybrid_every:int`, `scale_drift:float`; `MandelboxShape.FoldShape {BOX, CYLINDER, OCTAHEDRAL}`.

- [ ] Fixtures: existing ones unchanged; one captured fixture per option (cylinder, octahedral, hybrid mix 0.5 every 2nd, drift 0.02).
- [ ] Lipschitz test over the Mandelbox defaults and each option: 400 seeded pairs within ±2.5, |ΔDE| ≤ |Δp|(1+1e-3)+1e-9.
- [ ] Implement in the CPU core, run, commit.

### Task 2: KIFS and Kleinian CPU estimators

**Files:** Create `src/fractal/kifs_estimator.gd`, `src/fractal/kleinian_estimator.gd`; Modify `distance_estimator.gd` (dispatch on `params.shape`), `fractal_params.gd` (shape, kifs_*, kleinian_* fields; `bound_half()`; `julia_enabled()` Mandelbox-only); Test `tests/kifs_estimator_test.gd`, `tests/kleinian_estimator_test.gd`, `tests/lipschitz_test.gd`.

**Interfaces — Produces:** `KifsEstimator.estimate_at(px, py, pz, params) -> float`, `KleinianEstimator.estimate_at(...) -> float`, `FractalParams.Shape {MANDELBOX, KIFS, KLEINIAN}`, `FractalParams.bound_half() -> float` (Kleinian: its view distance), `FractalParams.view_distance() -> float` (0 = none).

- [ ] Fixtures + invariants (Menger hole positive, octant symmetry), Lipschitz for each fold set and the Kleinian.
- [ ] Implement, run, commit.

### Task 3: Catalogue

**Files:** Create `src/fractal/shape_catalogue.gd`, `kifs_shape.gd`, `kleinian_shape.gd`; Modify `mandelbox_shape.gd` (Mandelbox-only groups, `show_when` on shape), every `MandelboxShape.specs()/group_tooltips()/SHAPE_GROUPS/COLOUR_GROUPS/catalogue_ids()` call site in `src/` and `tests/`; `fractal_params.gd` RESOLVED_KEYS; Test `tests/shape_catalogue_test.gd` (from mandelbox_shape_test), `fractal_params_test.gd`.

**Interfaces — Produces:** `ShapeCatalogue.specs()`, `.group_tooltips()`, `.catalogue_ids()`, `.SHAPE_GROUPS`, `.COLOUR_GROUPS`, `ShapeCatalogue.shown_for(shape:int, inner:Callable=Callable()) -> Callable`.

- [ ] Run, commit.

### Task 4: Shader

**Files:** Create `src/fractal/kifs.gdshaderinc`, `src/fractal/kleinian.gdshaderinc`; Modify `src/fractal/mandelbox.gdshader` (options, `shape` switch, view distance + fade, normals), `src/fractal/fractal_view.gd` (push every resolved shape key; `box_half` from `bound_half()`; `view_distance`), `src/camera/orbit_camera.gd` (bound + view distance); Test `tests/shader_test.gd` (renderer uniforms gain `view_distance`).

- [ ] Run all tests, commit.

### Task 5: Inspector, saves, docs

**Files:** Modify `src/ui/console/attribute_inspector.gd` (hide a heading whose rows are all hidden), `src/workspace/workspace.gd` (missing `shape` → Mandelbox), README; Test `tests/ui_console_test.gd` or `console_test.gd`, `tests/workspace_test.gd`.

- [ ] Run all tests, commit.

### Task 6: Screenshots

**Files:** Modify `tests/screenshots.gd` (one PNG per shape and option).

- [ ] The one agreed windowed batch; look at every PNG; fix; commit.
