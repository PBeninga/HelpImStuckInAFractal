extends "res://tests/test_case.gd"

func key(echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F4
	event.pressed = true
	event.echo = echo
	return event

func run() -> void:
	await frames(1)
	var menu := root.get_node_or_null("GameplayMenu")
	check(menu != null, "F4 gameplay menu is available across scenes")
	if menu == null:
		return
	check(not menu.visible and not menu.is_processing(), "hidden gameplay menu does no polling")
	root.push_input(key())
	check(menu.visible, "F4 opens globally without a game")
	root.push_input(key(true))
	check(menu.visible, "key repeat does not close F4")
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main.set_process(false)
	main.params.gameplay.distance_scaling = false
	main._check_shape_progress()
	main.shapes().set_stage(0, 100.0, [])
	main.params.gameplay.spawn_x = 10.0
	main.params.gameplay.spawn_y = 0.0
	main.params.gameplay.spawn_z = 0.0
	main.return_to_spawn()
	# Deep-zoom travel must reach both the 64-bit eye and the visible label.
	# Three fixed decimal places incorrectly render every one of these as zero.
	main.params.gameplay.spawn_x = 0.0
	main.params.gameplay.spawn_z = 1.0
	main.return_to_spawn()
	for i in range(1, 5):
		await frames(1)
		main.camera.move_by(Vector3(3e-14, 4e-14, 0.0))
		check_approx(main.camera.eye_x(), i * 3e-14, "frame %d retains tiny internal X movement" % i, 1e-20)
		check_approx(main.camera.eye_y(), i * 4e-14, "frame %d retains tiny internal Y movement" % i, 1e-20)
		var shown: float = menu.readout.text.get_slice("Distance from origin (spawn): ", 1).get_slice(" world units", 0).to_float()
		check_approx(shown, i * 5e-14, "frame %d writes the tiny origin distance to F4" % i, 1e-20)
	main.params.gameplay.spawn_x = 10.0
	main.params.gameplay.spawn_y = 0.0
	main.params.gameplay.spawn_z = 0.0
	main.return_to_spawn()
	main.camera.set_eye(13.0, 4.0, 0.0)
	main._check_shape_progress()
	check(menu.readout.text.contains("Shape / level: 1"), "F4 displays the gameplay stage using one-based numbering")
	check(menu.readout.text.contains("5.000"), "F4 distance uses the same run origin as progression")
	main.camera.set_eye(16.0, 8.0, 0.0)
	main._check_shape_progress()
	check(menu.readout.text.contains("Distance from origin (spawn): 10.000"), "F4 updates immediately on every move")
	check(menu.readout.text.contains("Level boundary: > 100.000"), "F4 shows the active level's threshold")
	main.shapes().set_stage(0, 11.0, [])
	check(menu.readout.text.contains("Level boundary: > 11.000"), "editing the active boundary updates F4 without moving")
	var path := "user://gameplay_menu_single_level.json"
	main.save_level_to(path)
	main.shapes().add()
	check(main.shapes().set_stage(0, 11.0, ["pos_x 1"]), "first level has an unexecuted scripted command")
	check(main.shapes().set_stage(1, 12.0, ["pos_x 1"]), "second level has an unexecuted scripted command")
	main.return_to_spawn()
	main.params.active = 1
	main.camera.set_eye(21.0, 0.0, 0.0)
	main._check_shape_progress()
	check(not main.shape_run.transitioning(), "the exact active boundary does not advance")
	main.camera.move_by(Vector3(0.25, 0.0, 0.0))
	main._check_shape_progress()
	check(main.shape_run.transitioning(), "movement beyond the gameplay level's boundary advances even with unexecuted commands")
	check(menu.readout.text.contains("Status: Transitioning"), "F4 immediately reports the transition")
	main.shape_run.step(1.0)
	check(menu.readout.text.contains("Shape / level: 2 / 2"), "F4 updates when the fade activates the next level")
	check(menu.readout.text.contains("Distance from origin (spawn): 0.000"), "F4 updates on the hidden return to origin")
	check(menu.readout.text.contains("Level boundary: > 12.000"), "F4 switches to the new level's threshold")
	main.shape_run.step(0.1)
	main.shape_run.step(1.0)
	check(menu.readout.text.contains("Status: Fly beyond the level boundary"), "F4 shows distance-only advancement despite unexecuted commands")
	main.camera.set_eye(21.5, 0.0, 0.0)
	main._check_shape_progress()
	main.camera.move_by(Vector3(0.25, 0.0, 0.0))
	main._check_shape_progress()
	check(not main.shape_run.escaped, "the next level checks its own larger threshold")
	main.camera.move_by(Vector3(0.5, 0.0, 0.0))
	main._check_shape_progress()
	check(main.shape_run.escaped, "the last level completes on movement beyond its own threshold")
	check(menu.readout.text.contains("Status: Escaped"), "F4 immediately reports final completion")
	main.load_level_from(path)
	check(menu.readout.text.contains("Shape / level: 1 / 1"), "loading fewer levels refreshes F4 after resetting the old active index")
	check(menu.readout.text.contains("Distance from origin (spawn): 0.000"), "F4 shows the fresh run at spawn")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not FrameProfiler.enabled, "F4 never enables performance profiling")
	main.shapes().set_stage(0, 100.0, [])
	main.params.gameplay.move_speed = 2.0
	main.return_to_spawn()
	check_eq(main.params.world_unit_size, 2.0, "restart captures speed before the first movement")
	main.camera.set_eye(20.0, 0.0, 0.0)
	main._process(0.0)
	check(menu.readout.text.contains("Distance from origin (spawn): 5.000"), "one world unit is one second of starting travel")
	main.params.gameplay.move_speed = 4.0
	main.set_process(true)
	await frames(2)
	main.set_process(false)
	check_eq(main.params.world_unit_size, 2.0, "the game loop preserves the starting scale")
	check(menu.readout.text.contains("Distance from origin (spawn): 5.000"), "speed changes do not rescale distance")
	main.camera.speed_factor = 2.0
	main._process(0.0)
	check(menu.readout.text.contains("Distance from origin (spawn): 5.000"), "wheel speed preserves the world unit")
	main.fly.sprinting = true
	main._process(0.0)
	check(menu.readout.text.contains("Distance from origin (spawn): 5.000"), "sprint preserves the world unit")
	main.fly.speed_limit = 0.5
	main._process(0.0)
	check(menu.readout.text.contains("Distance from origin (spawn): 5.000"), "speed limiter preserves the world unit")
	main.fly.sprinting = false
	main.fly.speed_limit = 1.0
	main.camera.speed_factor = 1.0
	main.shapes().set_stage(0, 3.0, [])
	main.return_to_spawn()
	check_eq(main.params.world_unit_size, 4.0, "a new run captures the new starting speed")
	main.camera.set_eye(20.0, 0.0, 0.0)
	main._process(0.0)
	check(not main.shape_run.escaped, "distance 10 stays within three world units at starting speed 4")
	menu.hide()
	main.params.gameplay.move_speed = 2.0
	main._process(0.0)
	check(not main.shape_run.escaped, "speed change cannot cross the fixed boundary with F4 hidden")
	main.camera.set_eye(22.1, 0.0, 0.0)
	main._process(0.0)
	check(main.shape_run.escaped, "movement beyond the fixed boundary advances with F4 hidden")
	menu.show()
	check(menu.readout.text.contains("Status: Escaped"), "F4 and advancement agree on fixed units")
	var edit := LineEdit.new()
	main.console().add_child(edit)
	edit.grab_focus()
	main.console().push_input(key())
	check(not menu.visible and not menu.is_processing(), "F4 closes from a focused child-window text field")
	var previous: String = menu.readout.text
	main.return_to_spawn()
	check_eq(menu.readout.text, previous, "hidden F4 does no readout work when the camera and run change")
	main.noise_window().open()
	main.noise_window().push_input(key())
	check(menu.visible, "F4 opens from another child window")
	check(menu.readout.text.contains("Distance from origin (spawn): 0.000"), "reopening F4 shows the latest position")
	_ray_scaled_units(main)
	main.queue_free()
	await frames(2)
	check(menu.readout.text.contains("No active run"), "scene exit releases the gameplay source")
	menu.hide()

func _ray_scaled_units(main: Node) -> void:
	main.shapes().table(0).set_default(&"shape", FractalParams.Shape.MANDELBOX)
	main.params.gameplay.distance_scaling = true
	main.params.gameplay.move_speed = 1.0
	var overview := SurfaceFixture.overview_camera()
	main.params.gameplay.spawn_x = overview.eye_x()
	main.params.gameplay.spawn_y = overview.eye_y()
	main.params.gameplay.spawn_z = overview.eye_z()
	main.camera.set_basis(overview.transform.basis)
	main.return_to_spawn()
	var starting_speed: float = main.fly.current_speed()
	check_eq(main.params.world_unit_size, starting_speed, "start captures ray-scaled speed after returning to spawn")
	main.camera.move_by(main.camera.forward() * 2.0)
	main._process(0.0)
	check(absf(main.fly.current_speed() - starting_speed) > 0.01, "moving toward geometry changes the live ray-scaled speed")
	check_eq(main.params.world_unit_size, starting_speed, "changing raycast distance preserves the starting world unit")
	check_approx(main.shape_run.distance_from_origin() * starting_speed, 2.0, "ray-scaled movement measures distance using the fixed unit")
