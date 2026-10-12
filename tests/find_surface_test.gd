extends "res://tests/test_case.gd"
## Recovery searches all around the eye, chooses hits rather than shape
## centres, preserves deep-zoom coordinates, and works through Gameplay.


func run() -> void:
	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	var pane = main.gameplay_pane()
	var button: Button = pane.get("find_surface_button")
	check(button != null, "Gameplay offers a Find nearest surface button")
	if button == null:
		main.queue_free()
		await frames(1)
		return
	var params: FractalParams = main.params
	var camera: CameraState = main.camera
	camera.set_eye(0.123456789012345, 0.0, 0.0)
	camera.speed_factor = 3.25
	var eye := camera.eye64()
	params.shape().size = 0.1
	# Find a small shape in each hemisphere, even straight above/below the eye.
	for offset in [Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 6, 0),
			Vector3(0, -6, 0), Vector3(0, 0, 6), Vector3(0, 0, -6), Vector3(3.7, -4.2, 2.1)]:
		params.shape().pos_x = eye[0] + offset.x
		params.shape().pos_y = eye[1] + offset.y
		params.shape().pos_z = eye[2] + offset.z
		button.pressed.emit()
		check(pane.status_label.visible and pane.status_label.text.contains("Facing"),
			"a successful search reports the recovery")
		check(camera.forward().dot(offset.normalized()) > 0.99,
			"the button finds the shape along %s" % offset)
		check(CenterRay.march_at(eye[0], eye[1], eye[2], camera.forward(), params)[1],
			"the recovered view actually hits a surface")
		check(camera.transform.basis.is_finite() and absf(camera.transform.basis.determinant() - 1.0) < 1e-5,
			"vertical recovery keeps a valid camera basis")
	check_eq(camera.eye64(), eye, "recovery preserves all 64-bit eye coordinates")
	check_eq(camera.speed_factor, 3.25, "recovery preserves wheel speed")

	# The farther centre has the nearer surface: do not just look at the
	# closest shape centre, the selected shape, or the first ray that hits.
	params.shape().pos_x = eye[0]
	params.shape().pos_y = 5.0
	params.shape().pos_z = 0.0
	params.shape().size = 0.1
	var large := params.add_shape()
	large.pos_x = eye[0]
	large.pos_y = -6.0
	large.size = 1.0
	camera.set_basis(Basis.looking_at(Vector3(0, 1, 0), Vector3(0, 0, 1)))
	button.pressed.emit()
	check(camera.forward().y < -0.8, "the closest surface wins even behind the view and with a farther centre")
	var hit := CenterRay.march_at(eye[0], eye[1], eye[2], camera.forward(), params)
	check(hit[1] and hit[0] < 4.9, "the chosen hit is nearer than the small shape")

	params.camera_mode = FractalParams.CameraMode.ORBIT
	button.pressed.emit()
	var orbit: OrbitCamera = main.get_node("OrbitCamera")
	check((orbit.center - camera.eye()).normalized().dot(camera.forward()) > 0.999,
		"orbit recentres on the recovered hit")
	check_eq(camera.eye64(), eye, "orbit recovery also leaves the eye unchanged")

	params.set_shape_count(1)
	params.shape().pos_x = eye[0]
	params.shape().pos_y = 0.0
	params.shape().pos_z = 6.0
	button.pressed.emit()
	var pole_basis := camera.transform.basis
	orbit.rotate_view(10.0, 0.0)
	check(camera.transform.basis.is_equal_approx(pole_basis),
		"an orbit drag at the pole does not introduce a sudden roll")

	# Both shapes outside the visible exit sphere: a failed search must not
	# move the camera or reset the orbit pivot, and must explain the miss.
	params.gameplay.exit_radius = 0.5
	var before := camera.transform
	var pivot := orbit.center
	button.pressed.emit()
	check_eq(camera.transform, before, "a miss leaves the view unchanged")
	check_eq(orbit.center, pivot, "a miss leaves the orbit pivot unchanged")
	check(pane.status_label.visible and pane.status_label.text.contains("No surface"),
		"a miss gives visible feedback")
	check_eq(button.focus_mode, Control.FOCUS_NONE, "Space will not retrigger recovery during flight")
	main.queue_free()
	await frames(1)
