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
	main.shapes().set_stage(0, 100.0, [])
	main.params.gameplay.spawn_x = 10.0
	main.return_to_spawn()
	# Deep-zoom travel must reach both the 64-bit eye and the visible label.
	# Three fixed decimal places incorrectly render every one of these as zero.
	main.params.gameplay.spawn_x = 0.0
	main.return_to_spawn()
	for i in range(1, 5):
		await frames(1)
		main.camera.move_by(Vector3(3e-14, 4e-14, 0.0))
		check_approx(main.camera.eye_x(), i * 3e-14, "frame %d retains tiny internal X movement" % i, 1e-20)
		check_approx(main.camera.eye_y(), i * 4e-14, "frame %d retains tiny internal Y movement" % i, 1e-20)
		var shown: float = menu.readout.text.get_slice("Distance from origin (spawn): ", 1).get_slice(" world units", 0).to_float()
		check_approx(shown, i * 5e-14, "frame %d writes the tiny origin distance to F4" % i, 1e-20)
	main.params.gameplay.spawn_x = 10.0
	main.return_to_spawn()
	main.camera.set_eye(13.0, 4.0, 0.0)
	check(menu.readout.text.contains("Shape / level: 1"), "F4 displays the gameplay stage using one-based numbering")
	check(menu.readout.text.contains("5.000"), "F4 distance uses the same run origin as progression")
	main.camera.set_eye(16.0, 8.0, 0.0)
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
	check(not main.shape_run.transitioning(), "the exact active boundary does not advance")
	main.camera.move_by(Vector3(0.25, 0.0, 0.0))
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
	main.camera.move_by(Vector3(0.25, 0.0, 0.0))
	check(not main.shape_run.escaped, "the next level checks its own larger threshold")
	main.camera.move_by(Vector3(0.5, 0.0, 0.0))
	check(main.shape_run.escaped, "the last level completes on movement beyond its own threshold")
	check(menu.readout.text.contains("Status: Escaped"), "F4 immediately reports final completion")
	main.load_level_from(path)
	check(menu.readout.text.contains("Shape / level: 1 / 1"), "loading fewer levels refreshes F4 after resetting the old active index")
	check(menu.readout.text.contains("Distance from origin (spawn): 10.000"), "F4 shows the loaded camera's distance")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not FrameProfiler.enabled, "F4 never enables performance profiling")
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
	main.queue_free()
	await frames(2)
	check(menu.readout.text.contains("No active run"), "scene exit releases the gameplay source")
	menu.hide()
