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
	main.camera.set_eye(13.0, 4.0, 0.0)
	menu._process(1.0)
	check(menu.readout.text.contains("Shape / level: 1"), "F4 displays the gameplay stage using one-based numbering")
	check(menu.readout.text.contains("5.000"), "F4 distance uses the same run origin as progression")
	var previous: String = menu.readout.text
	main.camera.set_eye(16.0, 8.0, 0.0)
	menu._process(0.5)
	check_eq(menu.readout.text, previous, "F4 does not refresh before one second")
	menu._process(0.5)
	check(menu.readout.text.contains("10.000"), "F4 updates after one second")
	check(not FrameProfiler.enabled, "F4 never enables performance profiling")
	var edit := LineEdit.new()
	main.console().add_child(edit)
	edit.grab_focus()
	main.console().push_input(key())
	check(not menu.visible and not menu.is_processing(), "F4 closes from a focused child-window text field")
	main.noise_window().open()
	main.noise_window().push_input(key())
	check(menu.visible, "F4 opens from another child window")
	main.queue_free()
	await frames(2)
	check(menu.readout.text.contains("No active run"), "scene exit releases the gameplay source")
	menu.hide()
