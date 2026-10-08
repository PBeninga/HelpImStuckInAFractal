# Deep-Zoom March Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the picture intact when the fly camera gets very close to the fractal: a coarse march pass whose iteration count follows the camera's distance to the surface (A), a shading normal that crossfades from the Ice Fractal probe to the true normal up close (B), and a fly-camera guard that stops at the 32-bit floor and says so in the Movement pane (D).

**Architecture:** Two new helpers on `FractalParams` (`coarse_iters(near)`, `nf_weight(near)`) feed two new shader uniforms that `FractalView._push_near()` pushes beside `near_dist`. A third helper (`zoom_floor(eye)`) is used by `FlyCamera._physics_process` to refuse moves below the floor, raising `at_zoom_limit`, which `Main._process` forwards through `ConsoleWindow` to a `zoom limit` label in the Movement pane. The CPU estimator gains an optional iteration count so a headless test can replay the shader's two-phase march.

**Tech Stack:** Godot 4.6, GDScript, a `canvas_item` shader (GLSL ES 3.0 / WebGL 2 floats), headless SceneTree tests (`tests/*_test.gd`, `tests/run_all.sh`).

Spec: `docs/superpowers/specs/2026-10-08-deep-zoom-march-design.md`.

## Global Constraints

- Everything is automatic: no new Renderer option, no save-format change, no new console knob. The only UI change is the read-only `zoom limit` readout in the Movement pane.
- The default view stays bit-for-bit identical: `coarse_iters` is 16 there and `nf_weight` is 1 there, and each code path is exactly today's maths at those values.
- `DistanceEstimator.estimate_at` gains an optional `iters` argument defaulting to 32; every existing fixture passes unchanged.
- `coarse_iters(near) = clamp(ceil(ln(2 / (2 × eps × near)) / ln|box_scale|), 16, 32)`, `eps = precision / detail` (unshed detail); `|box_scale| ≤ 1` gives 32.
- `nf_weight = smoothstep(0.1, 2.0, near)`, band ends `FractalParams.NF_FADE_NEAR` / `NF_FADE_FAR`.
- `zoom_floor(eye) = ulp32(max(|eye.x|, |eye.y|, |eye.z|)) / (50 × eps)`, `ulp32(x) = 2^(floor(log2 x) − 23)`.
- Orbit camera, the two-float camera (option C), supersampling and sub-chunk loading are out of scope.
- Headless only: never run `tests/screenshots.sh` or any windowed Godot. Run tests as `cd <worktree> && tests/run_all.sh` or `godot4 --headless --path <worktree> -s tests/<name>_test.gd`.
- Comments and README prose in plain language; anything above basic calculus gets a one-line explanation.
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never push, merge or rebase.

## File map

| file | change |
|---|---|
| `src/fractal/distance_estimator.gd` | `estimate_at(..., iters := ITERATIONS)` |
| `src/fractal/fractal_params.gd` | `COARSE_ITERS_MIN`, `COARSE_BOX_HALF`, `coarse_iters()`, `NF_FADE_NEAR/FAR`, `nf_weight()`, `ZOOM_FLOOR_DIVISOR`, `zoom_floor()`, `ulp32()` |
| `src/fractal/mandelbox.gdshader` | `uniform int coarse_iters`, `uniform float nf_weight`; phase 1 uses `coarse_iters`; normal crossfade |
| `src/fractal/fractal_view.gd` | `_push_near()` pushes `coarse_iters` and `nf_weight` |
| `src/camera/fly_camera.gd` | `at_zoom_limit`, `move_allowed()`, guard in `_physics_process` |
| `src/ui/console/movement_pane.gd` | `zoom_label`, `show_zoom_limit()` |
| `src/ui/console/console_window.gd` | `show_zoom_limit()` forwards to the pane |
| `src/main.gd` | `_process` forwards `fly.at_zoom_limit` |
| `tests/surface_fixture.gd` (new) | shared: the default view's surface point, refined in 64-bit |
| `tests/deep_zoom_test.gd` (new) | CPU two-phase march regression |
| `tests/distance_estimator_test.gd`, `fractal_params_test.gd`, `shader_test.gd`, `fractal_view_test.gd`, `fly_camera_test.gd`, `console_test.gd`, `ui_console_test.gd`, `main_test.gd` | new checks |
| `README.md` | Renderer section, Fly camera section, Testing list |
| `docs/viz/panes/mandelbox.js`, `docs/viz/glossary.js` | march description, new terms |

---

### Task 1: The CPU estimator takes an iteration count

**Files:**
- Modify: `src/fractal/distance_estimator.gd`
- Test: `tests/distance_estimator_test.gd`

**Interfaces:**
- Produces: `DistanceEstimator.estimate_at(px: float, py: float, pz: float, params: FractalParams, iters: int = ITERATIONS) -> float` — `iters` is clamped to `[0, ITERATIONS]`; 32 is today's result exactly.

- [ ] **Step 1: Write the failing test** — append to `run()` in `tests/distance_estimator_test.gd`:

```gdscript
	# --- an iteration count: 32 is the default, fewer is a different (smoother) surface ---
	var q := [1.2, -0.3, 0.8]
	check_eq(DistanceEstimator.estimate_at(q[0], q[1], q[2], d, 32),
		DistanceEstimator.estimate_at(q[0], q[1], q[2], d), "iters 32 is the default, exactly")
	var d16 := DistanceEstimator.estimate_at(q[0], q[1], q[2], d, 16)
	check(d16 != DistanceEstimator.estimate_at(q[0], q[1], q[2], d), "16 iterations give a different estimate")
	check(d16 > 0.0 and is_finite(d16), "and a finite positive one (%s)" % d16)
	check_eq(DistanceEstimator.estimate_at(q[0], q[1], q[2], d, 99),
		DistanceEstimator.estimate_at(q[0], q[1], q[2], d), "a count past 32 clamps to 32")
```

- [ ] **Step 2: Run, expect FAIL** — `godot4 --headless --path . -s tests/distance_estimator_test.gd` → parse error: too many arguments to `estimate_at`.

- [ ] **Step 3: Implement** — in `distance_estimator.gd`, change the doc line to say the count is optional, and:

```gdscript
static func estimate_at(px: float, py: float, pz: float, params: FractalParams,
		iters: int = ITERATIONS) -> float:
	...
	for _i in clampi(iters, 0, ITERATIONS):
```

- [ ] **Step 4: Run, expect PASS** (all 24 site fixtures untouched).
- [ ] **Step 5: Commit** `feat(de): optional iteration count on the CPU estimator`.

### Task 2: `FractalParams.coarse_iters` and the deep-zoom regression

**Files:**
- Modify: `src/fractal/fractal_params.gd`
- Create: `tests/surface_fixture.gd`, `tests/deep_zoom_test.gd`
- Test: `tests/fractal_params_test.gd`

**Interfaces:**
- Consumes: `estimate_at(..., iters)` (Task 1).
- Produces: `FractalParams.COARSE_ITERS_MIN := 16`, `FractalParams.COARSE_BOX_HALF := 2.0`, `func coarse_iters(near: float) -> int`; `SurfaceFixture.default_surface(params) -> Array` = `[x, y, z, fx, fy, fz]` (64-bit floats: a point on the default view's surface where the 32-iteration estimate is under 1e-12, and the default camera's forward).

- [ ] **Step 1: Failing tests.** In `fractal_params_test.gd`, append:

```gdscript
	# coarse_iters: the coarse pass's iteration count follows the camera's distance
	var ci := FractalParams.new()
	check_eq(ci.coarse_iters(6.5655845), 16, "the default view (near ~6.57) keeps 16")
	check_eq(ci.coarse_iters(1e-3), 24, "1e-3 from the surface takes 24")
	check_eq(ci.coarse_iters(1e-6), 32, "1e-6 takes all 32")
	check_eq(ci.coarse_iters(0.0), 32, "a camera on the surface stays at 32")
	check_eq(ci.coarse_iters(1000.0), 16, "far away never drops below 16")
	var ci_fine := FractalParams.new()
	ci_fine.detail = 10.0
	check(ci_fine.coarse_iters(1e-2) > ci.coarse_iters(1e-2), "Detail 10 raises the count at a given distance")
	ci.box_scale = 1.0
	check_eq(ci.coarse_iters(6.5), 32, "|box_scale| <= 1 has no shrinking detail: 32")
	ci.box_scale = -0.8
	check_eq(ci.coarse_iters(6.5), 32, "nor does a negative one inside 1")
```

`tests/surface_fixture.gd`:

```gdscript
class_name SurfaceFixture
extends RefCounted
## The default view's surface point, for the deep-zoom tests: the centre ray's
## hit (CenterRay.march), then marched on in 64-bit until the 32-iteration
## estimate is under 1e-12, so a camera backed off from it by d is about d
## (along the ray) from the real surface. Returns [x, y, z, fx, fy, fz].
static func default_surface(params: FractalParams) -> Array:
	var cam := CameraState.make_default()
	var e := cam.eye()
	var f := cam.forward()
	var t: float = CenterRay.march(e, f, params)[0]
	var x: float = e.x + f.x * t
	var y: float = e.y + f.y * t
	var z: float = e.z + f.z * t
	for _i in 400:
		var d := DistanceEstimator.estimate_at(x, y, z, params)
		if d < 1e-12:
			break
		x += f.x * d
		y += f.y * d
		z += f.z * d
	return [x, y, z, f.x, f.y, f.z]
```

`tests/deep_zoom_test.gd`: the shader's two-phase march (96 coarse at `coarse` iterations under twice the threshold, 32 fine at 32 under it) in 64-bit scalars from the camera backed off the surface point by `1e-3` and `1e-5`; the fixed 16-count pass uses more than 60% of 128 or misses; `coarse_iters(near)` hits in under half; at the default view the two schemes are the same march.

```gdscript
extends "res://tests/test_case.gd"
## The deep-zoom regression (the design spec's table, one ray). ...

const COARSE := 96
const FINE := 32
const BUDGET := COARSE + FINE

## [steps used, hit], the way the shader counts them for its step shading.
func _march(o: Array, dir: Array, params: FractalParams, coarse: int) -> Array:
	var near := maxf(DistanceEstimator.estimate_at(o[0], o[1], o[2], params), FractalParams.NEAR_FLOOR)
	var t := 0.0
	var n1 := COARSE
	for i in COARSE:
		var d := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params, coarse)
		if d < params.hit_epsilon(t, near) * 2.0:
			n1 = i
			break
		t += d
	for i in FINE:
		var d := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if d < params.hit_epsilon(t, near):
			return [n1 + i, true]
		t += d
	return [n1 + FINE, false]

func run() -> void:
	var params := FractalParams.new()
	var s := SurfaceFixture.default_surface(params)
	var dir := [s[3], s[4], s[5]]
	for back in [1e-3, 1e-5]:
		var o := [s[0] - dir[0] * back, s[1] - dir[1] * back, s[2] - dir[2] * back]
		var near := DistanceEstimator.estimate_at(o[0], o[1], o[2], params)
		var fixed := _march(o, dir, params, 16)
		var ci := params.coarse_iters(near)
		var depth := _march(o, dir, params, ci)
		check(not fixed[1] or fixed[0] > 0.6 * BUDGET, ...)
		check(depth[1] and depth[0] < BUDGET / 2, ...)
	# default view: same count, same march
	...
```

- [ ] **Step 2: Run both, expect FAIL** (`coarse_iters` not found).
- [ ] **Step 3: Implement** in `fractal_params.gd`, after `hit_epsilon`:

```gdscript
## The coarse pass's fewest iterations, and the box half-size its formula uses.
const COARSE_ITERS_MIN := 16
const COARSE_BOX_HALF := 2.0

## How many iterations the march's coarse pass needs for a camera `near` from
## the nearest surface. Each iteration adds detail |box_scale| times finer, so
## n iterations leave the surface rough by about box / |box_scale|^n; the coarse
## pass needs that under its own hit threshold (2 × eps × near), which gives
## n = log(box / (2 eps near)) / log|box_scale|, rounded up, kept in [16, 32].
## Uses the unshed detail. 16 at the default view, so the picture is unchanged.
func coarse_iters(near: float) -> int:
	var s := absf(box_scale)
	if s <= 1.0:
		return DistanceEstimator.ITERATIONS
	var gap := maxf(2.0 * precision / detail * maxf(near, 0.0), 1e-300)
	var n := ceilf(log(COARSE_BOX_HALF / gap) / log(s))
	return clampi(int(minf(n, 1e6)), COARSE_ITERS_MIN, DistanceEstimator.ITERATIONS)
```

- [ ] **Step 4: Run both, expect PASS.**
- [ ] **Step 5: Commit** `feat(params): coarse_iters follows the camera's distance, with the deep-zoom regression test`.

### Task 3: The shader's coarse pass uses `coarse_iters`

**Files:** Modify `src/fractal/mandelbox.gdshader`, `src/fractal/fractal_view.gd`; Test `tests/shader_test.gd`, `tests/fractal_view_test.gd`.

**Interfaces:** Consumes `coarse_iters(near)`. Produces shader `uniform int coarse_iters;` pushed by `_push_near()`.

- [ ] **Step 1: Failing tests.** `shader_test.gd`: add `"coarse_iters"` to `RENDERER_UNIFORMS`. `fractal_view_test.gd`: after setup,

```gdscript
	var mat: ShaderMaterial = view._material
	var near := DistanceEstimator.estimate(cam.eye(), params)
	check_eq(int(mat.get_shader_parameter("coarse_iters")), 16, "the default view's coarse pass keeps 16 iterations")
	var close := cam.transform
	close.origin = cam.eye() + cam.forward() * (view.center_ray().distance() - 1e-3)
	cam.transform = close
	var near2 := maxf(DistanceEstimator.estimate(cam.eye(), params), FractalParams.NEAR_FLOOR)
	check_eq(int(mat.get_shader_parameter("coarse_iters")), params.coarse_iters(near2), "a close camera pushes its own count")
	check(int(mat.get_shader_parameter("coarse_iters")) > 16, "which is above 16")
	params.detail = 10.0   # a params change re-pushes too
	check_eq(int(...), params.coarse_iters(near2), "a Detail change re-pushes it")
```
(restore camera and detail afterwards).

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Shader: declare `uniform int coarse_iters;` under `near_dist` with a comment; phase 1 becomes `float d = de(pos, ci);` with `int ci = clamp(coarse_iters, 16, 32);` before the loop (an unpushed 0 reads as 16, today's count). View `_push_near()`: `_material.set_shader_parameter("coarse_iters", _params.coarse_iters(near))`. Update the comment above `_push_near` and the `MAX_STEPS` comment in `fractal_params.gd` ("three quarters coarse (N=16..32, see coarse_iters)").
- [ ] **Step 4: Run, expect PASS** (shader still compiles: non-empty uniform list).
- [ ] **Step 5: Commit** `feat(shader): the coarse pass's iteration count follows the camera's distance`.

### Task 4: Zoom-following lighting

**Files:** Modify `fractal_params.gd`, `mandelbox.gdshader`, `fractal_view.gd`; Test `fractal_params_test.gd`, `shader_test.gd`, `fractal_view_test.gd`.

**Interfaces:** Produces `FractalParams.NF_FADE_NEAR := 0.1`, `NF_FADE_FAR := 2.0`, `static func nf_weight(near: float) -> float` (= `smoothstep(NF_FADE_NEAR, NF_FADE_FAR, near)`); shader `uniform float nf_weight;`.

- [ ] **Step 1: Failing tests.** Params:

```gdscript
	check_eq(FractalParams.nf_weight(6.5655845), 1.0, "the default view lights with the Ice Fractal probe alone (exactly 1)")
	check_eq(FractalParams.nf_weight(FractalParams.NF_FADE_FAR), 1.0, "the far end of the band is 1")
	check_eq(FractalParams.nf_weight(FractalParams.NF_FADE_NEAR), 0.0, "the near end is 0")
	check_eq(FractalParams.nf_weight(1e-4), 0.0, "closer still is the true normal alone")
	var mid := FractalParams.nf_weight(1.05)
	check(mid > 0.0 and mid < 1.0, "inside the band it blends (%s)" % mid)
	check(FractalParams.nf_weight(0.5) < FractalParams.nf_weight(1.5), "rising with the distance")
```
Shader: `"nf_weight"` in `RENDERER_UNIFORMS`. View: default view pushes exactly 1.0; the close camera pushes 0.0.

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Params constants + `nf_weight`. Shader: `uniform float nf_weight;` and, in `fragment()`:

```glsl
			if (color_mode >= 1 && color_mode <= 9 && !julia_all) {
				if (nf_weight >= 1.0) {
					n = calc_nf(v, h);
				} else if (nf_weight <= 0.0) {
					n = calc_normal(v, delta);
				} else {
					vec3 nf = calc_nf(v, h);
					vec3 m = mix(calc_normal(v, delta), nf, nf_weight);
					n = dot(m, m) > 1e-12 ? normalize(m) : nf;
				}
			}
```
View `_push_near()`: `_material.set_shader_parameter("nf_weight", FractalParams.nf_weight(near))`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(shader): Ice Fractal lighting crossfades to the true normal up close`.

### Task 5: `FractalParams.zoom_floor`

**Files:** Modify `fractal_params.gd`; Test `fractal_params_test.gd`.

**Interfaces:** Produces `const ZOOM_FLOOR_DIVISOR := 50.0`, `static func ulp32(x: float) -> float`, `func zoom_floor(eye: Vector3) -> float`.

- [ ] **Step 1: Failing tests.**

```gdscript
	check_eq(FractalParams.ulp32(1.0), pow(2.0, -23.0), "ulp32(1) is 2^-23")
	check_eq(FractalParams.ulp32(1.96), pow(2.0, -23.0), "the same through [1, 2)")
	check_eq(FractalParams.ulp32(2.0), pow(2.0, -22.0), "and doubles at 2")
	check_eq(FractalParams.ulp32(8.18), pow(2.0, -20.0), "2^-20 at the default eye's x")
	var zf := FractalParams.new()
	var near_box := Vector3(1.96, 0.914, 0.787)   # the default view's surface point
	check(absf(zf.zoom_floor(near_box) - 1e-4) <= 0.2e-4, "near the box at the default precision the floor is about 1e-4 (%s)" % zf.zoom_floor(near_box))
	check_eq(zf.zoom_floor(-near_box), zf.zoom_floor(near_box), "it uses the largest |coordinate|")
	var zf10 := FractalParams.new(); zf10.detail = 10.0
	check_approx(zf10.zoom_floor(near_box) / zf.zoom_floor(near_box), 10.0, "it scales with Detail (a finer threshold needs more room above the grid)", 1e-9)
	check(zf.zoom_floor(Vector3(8.18, 3.81, 3.28)) > zf.zoom_floor(near_box), "a larger eye coordinate has a coarser grid, so a further floor")
	check(zf.zoom_floor(Vector3.ZERO) >= 0.0 and is_finite(zf.zoom_floor(Vector3.ZERO)), "the origin stays finite")
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**

```gdscript
const ZOOM_FLOOR_DIVISOR := 50.0

## The gap between neighbouring 32-bit floats near x: 2^(floor(log2 x) − 23).
static func ulp32(x: float) -> float:
	x = absf(x)
	if x < 1e-30:
		return pow(2.0, -126.0)   # the smallest normal float's spacing scale; never reached in practice
	var e := floori(log(x) / log(2.0))
	if pow(2.0, e + 1) <= x: e += 1     # log() rounding at exact powers of two
	elif pow(2.0, e) > x: e -= 1
	return pow(2.0, e - 23)

## The closest the fly camera may come to the surface at `eye` before the
## shader's 32-bit positions are too coarse for its hit threshold ...
func zoom_floor(eye: Vector3) -> float:
	var m := maxf(absf(eye.x), maxf(absf(eye.y), absf(eye.z)))
	return ulp32(m) / (ZOOM_FLOOR_DIVISOR * maxf(precision / detail, 1e-30))
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(params): zoom_floor, the 32-bit limit on how close the camera can get`.

### Task 6: The fly camera stops at the floor

**Files:** Modify `src/camera/fly_camera.gd`; Test `tests/fly_camera_test.gd`.

**Interfaces:** Consumes `zoom_floor`. Produces `FlyCamera.at_zoom_limit: bool`, `func move_allowed(from: Vector3, to: Vector3) -> bool`.

- [ ] **Step 1: Failing test** (appended before `fly.queue_free()`): place the default camera at the surface fixture backed off so `DE` is ~1.5× the floor (`back = 7e-4`), hold `move_forward` for up to 180 physics ticks until `at_zoom_limit`; check it was raised, the eye's DE is still at or above the floor, a further tick with W does not move the eye; `move_back` for one tick moves it and clears the flag; releasing every key clears it. Then place the camera below the floor (`back = 2.5e-4`, DE ~0.5× floor): one W tick does not move and flags; one S tick moves away. Each placement checks its precondition (`DE / floor` in the intended range) so a fixture drift fails loudly.
- [ ] **Step 2: Run, expect FAIL** (`at_zoom_limit` not found).
- [ ] **Step 3: Implement.**

```gdscript
## True on a tick that refused a move because it would take the camera below
## FractalParams.zoom_floor; cleared by the next accepted move, a tick with no
## move key held, or disabling the camera. Main shows it in the Movement pane.
var at_zoom_limit := false

func _physics_process(delta: float) -> void:
	if not enabled:
		at_zoom_limit = false
		return
	var dir := move_direction()
	sprinting = Input.is_action_pressed("sprint")
	if dir.length() == 0.0:
		at_zoom_limit = false
		return
	var t := _camera.transform
	t.origin += dir * current_speed() * delta
	if not move_allowed(_camera.eye(), t.origin):
		at_zoom_limit = true
		return
	at_zoom_limit = false
	_camera.transform = t

func move_allowed(from: Vector3, to: Vector3) -> bool:
	var d_to := DistanceEstimator.estimate(to, _params)
	if d_to >= _params.zoom_floor(to):
		return true
	return d_to >= DistanceEstimator.estimate(from, _params)
```
- [ ] **Step 4: Run, expect PASS** (and `center_ray_test`, `main_test`, `ui_journey_test` still pass).
- [ ] **Step 5: Commit** `feat(fly): stop at the 32-bit zoom floor`.

### Task 7: `zoom limit` in the Movement pane

**Files:** Modify `movement_pane.gd`, `console_window.gd`, `main.gd`; Test `console_test.gd`, `ui_console_test.gd`, `main_test.gd`.

**Interfaces:** Produces `MovementPane.zoom_label: Label`, `MovementPane.show_zoom_limit(on: bool)`, `ConsoleWindow.show_zoom_limit(on: bool)`.

- [ ] **Step 1: Failing tests.** console_test: hidden by default; `console.show_zoom_limit(true)` shows it with text `zoom limit`; `false` hides. ui_console_test `_layout_at_default_size`: with the readout shown, it and Reset camera lie inside the window, then hide it. main_test: set `main.fly.at_zoom_limit = true`, call `main._process(0.0)`, the pane's label is visible; set false, `_process`, hidden.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Pane: a `zoom_label` on the speed readout row, between the speed and Reset camera, styled like `shed_label` (plain Label, hidden while off):

```gdscript
	zoom_label = Label.new()
	zoom_label.text = "zoom limit"
	zoom_label.tooltip_text = "The fly camera is as close to the surface as the renderer's 32-bit positions can draw, and will not go nearer. Back off to move freely; a lower Detail lets it a little closer."
	speed_row.add_child(zoom_label)
	show_zoom_limit(_zoom_limit)

func show_zoom_limit(on: bool) -> void:
	_zoom_limit = on
	if zoom_label != null:
		zoom_label.visible = on
```
Console: `func show_zoom_limit(on: bool) -> void: _movement.show_zoom_limit(on)`. Main `_process`: after `_resolve_once()`, `if _console != null: _console.show_zoom_limit(fly.at_zoom_limit)`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(console): Movement pane shows "zoom limit" while the fly camera is held at the floor`.

### Task 8: README

- [ ] Renderer section: after the hit-threshold formula, a short "Deep zoom" subsection: the coarse pass's iteration count (16 normally, up to 32 within ~0.3 of the surface; formula with a plain-language gloss), the shading crossfade (Ice Fractal probe → true normal between 2 and 0.1 units), and the zoom limit (floor formula, what `ulp32` means, the `zoom limit` readout, moving away always allowed, higher Detail = stops further out). Fly camera section: one line pointing at it. Testing: mention `deep_zoom_test.gd`.
- [ ] Run `tests/run_all.sh` → all pass. Commit `docs(readme): deep zoom: coarse count, lighting crossfade, zoom limit`.

### Task 9: Viz pane and glossary

- [ ] Read `docs/viz/panes/mandelbox.js` (the march and normals tabs) and `docs/viz/glossary.js`; update the two-phase march description (coarse count follows `near`), the normals description (crossfade band), and add a zoom guard note; add glossary terms (e.g. `ulp`, `smoothstep`, `float32 grid`) with a plain explanation and a link; run `node tools/viz/check.mjs` before and after. Commit `docs(viz): mandelbox pane follows the deep-zoom march`.

### Task 10: Verify

- [ ] `cd <worktree> && tests/run_all.sh; echo exit=$?` — every suite PASSED, exit 0. Report counts. `tests/screenshots.sh` is the owner's to run (windowed): the default view must be pixel-identical.
