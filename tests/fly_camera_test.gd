extends "res://tests/test_case.gd"


func _fresh() -> Array:
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var fly := FlyCamera.new()
	root.add_child(fly)
	fly.setup(params, cam)
	return [params, cam, fly]


func run() -> void:
	# --- each action moves along the matching camera axis ---
	var ctx := _fresh()
	var cam: CameraState = ctx[1]
	var fly: FlyCamera = ctx[2]
	var cases := {
		"move_forward": cam.forward(), "move_back": -cam.forward(),
		"move_right": cam.right(), "move_left": -cam.right(),
		"move_up": cam.up(), "move_down": -cam.up(),
	}
	for action in cases:
		Input.action_press(action)
		var dir: Vector3 = fly.move_direction()
		Input.action_release(action)
		check(dir.is_equal_approx(cases[action]), "%s moves along its axis (got %s)" % [action, dir])

	# --- combined input is normalised ---
	Input.action_press("move_forward")
	Input.action_press("move_right")
	var combo: Vector3 = fly.move_direction()
	Input.action_release("move_forward")
	Input.action_release("move_right")
	check_approx(combo.length(), 1.0, "diagonal input is normalised")

	# --- Cmd+S saves, so S under Cmd does not also fly backwards ---
	var meta := InputEventKey.new()
	meta.keycode = KEY_META
	meta.physical_keycode = KEY_META
	meta.pressed = true
	Input.parse_input_event(meta)
	await frames(1)
	Input.action_press("move_back")
	var under_cmd: Vector3 = fly.move_direction()
	Input.action_release("move_back")
	meta.pressed = false
	Input.parse_input_event(meta)
	await frames(1)
	check(under_cmd == Vector3.ZERO, "no movement while Cmd is held (got %s)" % under_cmd)

	# --- speed is min(centre ray, NEAR_CAP x D(eye)) within [1e-6, 20], times the factor ---
	var params: FractalParams = ctx[0]
	var near := DistanceEstimator.estimate(cam.eye(), params)
	var ahead: float = CenterRay.march(cam.eye(), cam.forward(), params)[0]
	var expected := clampf(minf(ahead, near * FlyCamera.NEAR_CAP), 1e-6, 20.0) * cam.speed_factor
	check_approx(fly.current_speed(), expected, "speed follows the centre ray, capped by the nearest surface", 1e-6)
	check(fly.current_speed() > clampf(near, 1e-6, 20.0) * cam.speed_factor,
		"the default view looks further than its nearest surface, so it flies faster than D(eye)")

	# --- sprint: Shift doubles the speed, and that is all ---
	var base_speed := fly.current_speed()
	fly.sprinting = true
	check_approx(fly.current_speed(), base_speed * FlyCamera.SPRINT_MULTIPLIER, "Shift doubles the speed", 1e-9)
	check_approx(FlyCamera.SPRINT_MULTIPLIER, 2.0, "SPRINT_MULTIPLIER is 2")
	fly.sprinting = false
	check_approx(fly.current_speed(), base_speed, "letting go of Shift is back to the base speed", 1e-9)

	# --- the physics step really moves by speed x dt, and not at all with no keys ---
	var before := cam.eye()
	fly.enabled = true
	await physics_frame
	check(cam.eye() == before, "no move keys: the camera does not move")
	Input.action_press("move_forward")
	await physics_frame
	Input.action_release("move_forward")
	check(cam.eye() != before and (cam.eye() - before).normalized().is_equal_approx(cam.forward()),
		"move_forward flies along forward")
	await physics_frame
	var stopped := cam.eye()
	await physics_frame
	check(cam.eye() == stopped, "and stops on the frame the key is released")
	fly.enabled = false
	cam.transform = CameraState.make_default().transform

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

	# --- the wheel scales the factor by 1.25, clamped to [0.01, 100] ---
	var f0 := cam.speed_factor
	fly.scroll(true)
	check_approx(cam.speed_factor, f0 * 1.25, "wheel up multiplies the factor")
	fly.scroll(false)
	check_approx(cam.speed_factor, f0, "wheel down divides it back")
	for i in 60: fly.scroll(false)
	check(cam.speed_factor >= 0.01, "factor floors at 0.01")
	for i in 120: fly.scroll(true)
	check(cam.speed_factor <= 100.0, "factor ceils at 100")

	# --- yaw keeps the camera level ---
	cam.transform = CameraState.make_default().transform
	fly.apply_look(100.0, 0.0)   # pure yaw
	check_approx(cam.right().z, 0.0, "after yaw the right axis is still level", 1e-5)

	# --- pitching down actually tilts the view by a real amount ---
	cam.transform = CameraState.make_default().transform   # forward.z ~ -0.342
	fly.apply_look(0.0, 300.0)   # 30 deg down at sensitivity 0.1
	check(cam.forward().z < -0.75,
		"pitching down drops forward.z well below the start (got %s)" % cam.forward().z)

	# --- pitch saturates at 89 deg; it never reaches +/-Z and never wraps ---
	fly.apply_look(0.0, 1e6)     # extreme pitch down
	check_approx(absf(cam.forward().z), sin(deg_to_rad(89.0)), "pitch saturates 89 deg down", 1e-3)
	fly.apply_look(0.0, -1e6)    # extreme pitch up
	check_approx(absf(cam.forward().z), sin(deg_to_rad(89.0)), "pitch saturates 89 deg up", 1e-3)

	# --- a zero mouse delta changes nothing and emits nothing ---
	var emitted := [0]
	cam.changed.connect(func(): emitted[0] += 1)
	fly.apply_look(0.0, 0.0)
	check_eq(emitted[0], 0, "apply_look(0, 0) emits no change")

	# --- the load shedder's speed limit scales the travel speed ---
	var full := fly.current_speed()
	fly.speed_limit = 0.4
	check_approx(fly.current_speed(), full * 0.4, "speed_limit scales current_speed()", 1e-9)
	fly.speed_limit = 1.0

	fly.queue_free()
	await frames(1)

	# --- every fractal flies the same way: hold W straight at it, sprinting ---
	for shot in [
			["Mandelbox", {}, CameraState.DEFAULT_EYE],
			["octahedral fold", {&"fold_shape": MandelboxShape.FoldShape.OCTAHEDRAL}, CameraState.DEFAULT_EYE],
			["hybrid fold", {&"hybrid_mix": 0.5}, CameraState.DEFAULT_EYE],
			["Menger", {&"shape": FractalParams.Shape.KIFS}, Vector3(3.2, 2.4, 1.9)],
			["Sierpinski", {&"shape": FractalParams.Shape.KIFS, &"kifs_fold": KifsEstimator.FoldSet.DIAGONAL, &"kifs_scale": 2.0}, Vector3(3.5, -2.0, 2.2)],
			["Kleinian", {&"shape": FractalParams.Shape.KLEINIAN}, Vector3(2.5, 1.6, 1.2)],
			["Mandelbulb", {&"shape": FractalParams.Shape.MANDELBULB}, Vector3(2.2, 1.6, 1.2)],
			["Julia Mandelbulb", {&"shape": FractalParams.Shape.MANDELBULB, &"mandelbulb_julia": true}, Vector3(2.2, -1.6, 1.2)]]:
		await _fly_at(shot[0], shot[1], shot[2])

	await _zoom_floor_guard()



## A camera on the default view's line of sight, `back` short of the surface.
func _place(cam: CameraState, s: Array, back: float) -> void:
	var t := CameraState.make_default().transform
	t.origin = Vector3(s[0] - s[3] * back, s[1] - s[4] * back, s[2] - s[5] * back)
	cam.transform = t


## [distance to the surface, the zoom floor] at the camera.
func _depth(cam: CameraState, params: FractalParams) -> Array:
	return [DistanceEstimator.estimate(cam.eye(), params), params.zoom_floor(cam.eye())]


## One physics tick with `action` held ("" for no key).
func _tick(action: StringName) -> void:
	if action != &"":
		Input.action_press(action)
	await physics_frame
	if action != &"":
		Input.action_release(action)


## The fly camera refuses a move below FractalParams.zoom_floor (the 32-bit
## limit), says so through at_zoom_limit, and always lets the camera back off.
func _zoom_floor_guard() -> void:
	var ctx := _fresh()
	var params: FractalParams = ctx[0]
	var cam: CameraState = ctx[1]
	var fly: FlyCamera = ctx[2]
	var s := SurfaceFixture.default_surface(params)
	check_eq(fly.at_zoom_limit, false, "a new fly camera is not at the zoom limit")

	# just above the floor, W held: it closes in, then stops at the floor
	_place(cam, s, 7e-4)
	var dz := _depth(cam, params)
	check(dz[0] > 1.2 * dz[1] and dz[0] < 2.5 * dz[1],
		"the camera starts just above the floor (%s over %s)" % [dz[0], dz[1]])
	var start := cam.eye()
	fly.enabled = true
	Input.action_press("move_forward")
	for _i in 300:
		await physics_frame
		if fly.at_zoom_limit:
			break
	check(fly.at_zoom_limit, "holding W reaches the zoom limit")
	check(cam.eye() != start, "after closing in")
	dz = _depth(cam, params)
	check(dz[0] >= dz[1], "and stops at the floor, not past it (%s over %s)" % [dz[0], dz[1]])
	var held := cam.eye()
	await physics_frame
	Input.action_release("move_forward")
	check(cam.eye() == held and fly.at_zoom_limit, "W still held: the camera stays put and the limit stays up")
	await _tick(&"")
	check(not fly.at_zoom_limit, "no key held clears it")
	await _tick(&"move_forward")
	check(fly.at_zoom_limit and cam.eye() == held, "W again: refused again")
	await _tick(&"move_back")
	check(cam.eye() != held and DistanceEstimator.estimate(cam.eye(), params) > dz[0],
		"moving away is accepted")
	check(not fly.at_zoom_limit, "and clears the limit")

	# below the floor (e.g. from a loaded save): it may back off, not close in
	_place(cam, s, 2.5e-4)
	dz = _depth(cam, params)
	check(dz[0] < 0.8 * dz[1] and dz[0] > 0.2 * dz[1],
		"the camera starts below the floor (%s under %s)" % [dz[0], dz[1]])
	var below := cam.eye()
	await _tick(&"move_forward")
	check(cam.eye() == below and fly.at_zoom_limit, "below the floor, W is refused")
	await _tick(&"move_back")
	check(cam.eye() != below and DistanceEstimator.estimate(cam.eye(), params) > dz[0],
		"but S backs away")
	check(not fly.at_zoom_limit, "clearing the limit")

	# disabling the camera (Orbit mode) clears a raised limit
	_place(cam, s, 2.5e-4)
	await _tick(&"move_forward")
	check(fly.at_zoom_limit, "refused again")
	fly.enabled = false
	await _tick(&"")
	check(not fly.at_zoom_limit, "a disabled camera never reports the limit")
	fly.queue_free()
	await frames(1)


## Hold W (and Shift) for ten seconds at 60 fps toward the surface the centre
## ray first meets, stepping as _physics_process does (a move below the zoom
## floor is refused, and that ends the flight). No frame's step may
## tunnel: a careful quarter-step march along it must find no surface (up close
## the camera does fly on into finer gaps, as zooming in should, but never
## through a wall). The eye never ends up inside, the camera closes in on the
## first surface and slows as it goes, and it never stalls far out.
func _fly_at(label: String, knobs: Dictionary, eye: Vector3) -> void:
	var params := FractalParams.new()
	params.apply_resolved(knobs)
	var cam := CameraState.new()
	cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	var fly := FlyCamera.new()
	root.add_child(fly)
	fly.setup(params, cam)
	fly.sprinting = true
	var start: Array = CenterRay.march(cam.eye(), cam.forward(), params)
	check(start[1], "%s: the centre ray meets the surface" % label)
	var hit_t: float = start[0]
	var first_speed := fly.current_speed()
	var travelled := 0.0
	var tunnels := 0
	var inside := false
	var slowest_far := INF
	for frame in 600:
		var step := fly.current_speed() / 60.0
		if _surface_within(cam.eye(), cam.forward(), step, params):
			tunnels += 1
		if travelled < 0.5 * hit_t:
			slowest_far = minf(slowest_far, step)
		var t := cam.transform
		t.origin += cam.forward() * step
		if not fly.move_allowed(cam.eye(), t.origin):
			break   # at the 32-bit zoom floor
		travelled += step
		cam.transform = t
		var e := cam.eye()
		if DistanceEstimator.estimate_at(e.x, e.y, e.z, params) < 0.0:
			inside = true
	check_eq(tunnels, 0, "%s: no frame's step jumps a surface" % label)
	check(not inside, "%s: the eye never ends up inside" % label)
	check(travelled > 0.9 * hit_t, "%s: closes 90%% of the way in ten seconds (%s of %s)" % [label, travelled, hit_t])
	check(fly.current_speed() < first_speed * 0.5, "%s: slowing down on the way in" % label)
	check(slowest_far > 1e-3 * hit_t, "%s: no stall on the far half of the way" % label)
	fly.queue_free()
	await frames(1)


## Whether a quarter-step march from `origin` along `dir` meets the surface
## (the hit threshold at that distance) before going `length`.
func _surface_within(origin: Vector3, dir: Vector3, length: float, params: FractalParams) -> bool:
	var near := maxf(DistanceEstimator.estimate(origin, params), FractalParams.NEAR_FLOOR)
	var t := 0.0
	for i in 400:
		var p := origin + dir * t
		var d := DistanceEstimator.estimate_at(p.x, p.y, p.z, params)
		if d < params.hit_epsilon(maxf(t, near), near):
			return t < length
		t += 0.25 * d
		if t >= length:
			return false
	return false
