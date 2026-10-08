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
