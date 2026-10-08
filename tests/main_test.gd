extends "res://tests/test_case.gd"


## A non-echo physical key event for feeding Main._unhandled_input directly.
func _key(physical_keycode: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = pressed
	ev.echo = false
	return ev


func _tap_ctrl(main: Node) -> void:
	main._unhandled_input(_key(KEY_CTRL, true))
	main._unhandled_input(_key(KEY_CTRL, false))


func run() -> void:
	var settings: Node = root.get_node("Settings")
	var original_sens: float = settings.mouse_sensitivity
	settings.config_path = "user://main_test_settings.cfg"

	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)

	var fly: FlyCamera = main.get_node("FlyCamera")
	var console: ConsoleWindow = main.console()

	# With no file current, Reset camera goes back to the built-in starting view
	main.camera.transform = main.camera.transform.translated(Vector3(1, 2, 3))
	main.camera.speed_factor = 3.0
	main.reset_camera()
	check(main.camera.transform.is_equal_approx(CameraState.make_default().transform),
		"with no file, Reset camera restores the starting view")
	check_approx(main.camera.speed_factor, 1.0, "and the starting speed factor")

	# console hidden by default, fly camera active, mouse captured
	check(not console.visible, "the console starts hidden")
	check(fly.enabled, "fly camera is enabled in FLY mode")
	check(main.is_mouse_captured(), "the mouse starts captured in fly mode")

	# the console's zoom comes from Settings and goes back to it
	check_approx(console.zoom, settings.console_zoom, "the console opens at the saved zoom")
	var original_zoom: float = settings.console_zoom
	console.step_zoom(1)
	check_approx(settings.console_zoom, console.zoom, "a zoom change is kept in Settings")
	console.set_zoom(original_zoom)

	# A Ctrl tap while captured frees the mouse and opens the console
	_tap_ctrl(main)
	check(console.visible, "a Ctrl tap while captured opens the console")
	check(not main.is_mouse_captured(), "and frees the mouse")
	# A Ctrl tap while free closes the console and recaptures
	_tap_ctrl(main)
	check(not console.visible, "a Ctrl tap while free closes the console")
	check(main.is_mouse_captured(), "and recaptures the mouse")

	# Ctrl+chord (Ctrl+S) does not toggle
	main._unhandled_input(_key(KEY_CTRL, true))
	main._unhandled_input(_key(KEY_S, true))
	main._unhandled_input(_key(KEY_S, false))
	main._unhandled_input(_key(KEY_CTRL, false))
	check(not console.visible, "Ctrl+S does not toggle the console")
	# Ctrl+P: copy_screenshot consumes the P key-down, so the arm must clear first
	main._unhandled_input(_key(KEY_CTRL, true))
	var p_down := _key(KEY_P, true)
	p_down.ctrl_pressed = true
	main._unhandled_input(p_down)
	check(not main._ctrl.is_armed(), "Ctrl+P disarms the toggle before the screenshot consumes it")
	main._unhandled_input(_key(KEY_CTRL, false))
	check(not console.visible, "Ctrl+P does not toggle the console")

	# Q and E are the default axis
	check(InputMap.has_action(&"axis_a_pos"), "the default keymap registers axis_a_pos")
	var pos_events := InputMap.action_get_events(&"axis_a_pos")
	check(pos_events.size() == 1 and (pos_events[0] as InputEventKey).physical_keycode == KEY_E,
		"E is the positive key of the default axis")
	var neg_events := InputMap.action_get_events(&"axis_a_neg")
	check(neg_events.size() == 1 and (neg_events[0] as InputEventKey).physical_keycode == KEY_Q,
		"Q is the negative key")

	# A binding to Axis A changes params.box_scale as the axis is pushed
	var b := Binding.new(); b.source = &"a"; b.gain = 0.5
	main.table().set_binding(&"box_scale", b)
	await frames(1)
	var before_scale: float = main.params.box_scale
	await hold(&"axis_a_pos", 0.4)
	check(main.params.box_scale > before_scale + 0.05,
		"holding E pushes Axis A, which drives box_scale (%.3f -> %.3f)" % [before_scale, main.params.box_scale])
	main.table().set_binding(&"box_scale", Binding.new())   # clear it
	main._keymap.axes().set_value(&"a", 0.0)

	# switching to ORBIT disables the fly camera
	main.params.camera_mode = FractalParams.CameraMode.ORBIT
	await frames(1)
	check(not fly.enabled, "fly camera is disabled in ORBIT mode")
	var orbit = main.get_node_or_null("OrbitCamera")
	if orbit != null:
		check(orbit.enabled, "orbit camera is enabled in ORBIT mode")
	main.params.camera_mode = FractalParams.CameraMode.FLY
	await frames(1)

	# a click in the view in FLY mode recaptures and LEAVES the console open
	_tap_ctrl(main)                      # open the console, free the mouse
	check(console.visible and not main.is_mouse_captured(), "console open, mouse free")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(400, 300)
	main._unhandled_input(click)
	check(console.visible, "a click in the view leaves the console open")
	check(main.is_mouse_captured(), "and recaptures the mouse")
	console.hide_console()
	main._free_requested = false
	main._update_mouse()

	# The same with real clicks through the root, where the console is embedded
	# in the main window (headless has no native sub-windows; on the desktop it
	# is its own OS window): a click on the console is the console's own, a
	# click on the view beside it recaptures, and the console stays open.
	var ui := UiDriver.new(self)
	await ui.setup()
	_tap_ctrl(main)
	await frames(1)
	check(console.force_native, "the console asks to be a native OS window")
	check(console.visible and console.is_embedded(), "headless, it falls back to embedded in the main window")
	await ui.click(console.inspector().row(&"box_scale").get_child(0) as Control)
	check(console.visible and not main.is_mouse_captured(),
		"a click on the console stays in the console: it is open and the mouse is still free")
	var beside := Vector2(ui.global_rect(console.inspector()).position.x * 0.5, 400)
	check(not Rect2(Vector2(console.position), Vector2(console.size)).has_point(beside), "a point on the view beside the console")
	await ui.click_at(beside)
	check(main.is_mouse_captured(), "a click on the view beside the console recaptures the mouse")
	check(console.visible, "and the console stays open and visible over the view")
	console.hide_console()
	main._free_requested = false
	main._update_mouse()

	# the pause menu owns Save / Load / Camera / Noise
	var pause = main.pause_menu()   # untyped: see menus_test.gd
	var files: WorkspaceFiles = main.workspace_files()
	check(pause.save_requested.is_connected(files.prompt_save), "pause Save opens the save panel")
	check(pause.load_requested.is_connected(files.prompt_load), "pause Load opens the open panel")

	# save and load: the real path round-trips a knob (the shape table), the
	# axes and the camera
	var tmp := "user://main_test_view.json"
	main.table().set_default(&"fold_limit", 0.72)
	main.camera.speed_factor = 2.0
	main.save_view_to(tmp)
	check_eq(files.current_path, tmp, "a save that worked becomes current")
	check_eq(pause.file_label.text, "main_test_view.json", "and the pause menu names it")
	main.table().set_default(&"fold_limit", 0.3)
	main.camera.speed_factor = 1.0
	main.load_view_from(tmp)
	check_approx(main.table().get_default(&"fold_limit"), 0.72, "loading restores the shape table")
	await frames(1)
	check_approx(main.params.fold_limit, 0.72, "and the resolve pushes it into params")
	check_approx(main.camera.speed_factor, 2.0, "and the camera")
	check(pause.status_label.text.begins_with("Loaded"), "the pause menu reports the load: %s" % pause.status_label.text)
	main.load_view_from("user://no_such_view.json")
	check_eq(files.current_path, tmp, "a failed load does not change the current file")

	# Reset camera goes back to the current file's camera and speed factor, from
	# the console's Movement pane and from the Settings menu's Renderer tab
	var file_view: Transform3D = main.camera.transform
	main.camera.transform = file_view.translated(Vector3(0.5, -1, 2))
	main.camera.speed_factor = 7.0
	console.movement_pane().reset_camera_button.pressed.emit()
	check(main.camera.transform.is_equal_approx(file_view), "the console's Reset camera restores the file's camera")
	check_approx(main.camera.speed_factor, 2.0, "and its speed factor")
	main.pause()
	pause.settings_button.pressed.emit()
	main.camera.transform = file_view.rotated(Vector3(0, 0, 1), 0.3)
	pause.settings_menu.renderer.reset_camera_button.pressed.emit()
	check(main.camera.transform.is_equal_approx(file_view), "the Settings menu's Reset camera does too")
	check(paused and pause.settings_menu.visible, "and Settings stays open")
	main.resume()
	# a save makes the saved camera the new reset point
	main.camera.transform = file_view.translated(Vector3(0, 0, 1))
	var resaved: Transform3D = main.camera.transform
	main.save_view_to(tmp)
	main.camera.transform = file_view
	main.reset_camera()
	check(main.camera.transform.is_equal_approx(resaved), "after a save, Reset camera goes to the saved camera")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# the pause menu's Camera row switches mode
	pause.camera_option.select(1)
	pause.camera_option.item_selected.emit(1)
	check_eq(main.params.camera_mode, FractalParams.CameraMode.ORBIT, "the pause Camera row switches to orbit")
	pause.camera_option.select(0)
	pause.camera_option.item_selected.emit(0)
	await frames(1)

	# the view ignores the mouse, so drags reach Main through the real GUI pass
	check_eq(main.view.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the view ignores the mouse")

	# WASD does not fly the camera while a console text field has focus
	console.open()
	await frames(1)
	var label_edit: LineEdit = console.movement_pane().axis_line(&"a")["label"]
	label_edit.grab_focus()
	await frames(1)
	Input.action_press(&"move_forward")
	check(fly.move_direction().is_zero_approx(), "WASD is silenced while a console text field has focus")
	Input.action_release(&"move_forward")
	label_edit.release_focus()
	console.hide_console()
	main._free_requested = false
	main._update_mouse()
	await frames(1)

	# the sensitivity follows Settings, and a loaded view does not override it
	settings.mouse_sensitivity = 0.33
	check_approx(main.params.mouse_sensitivity, 0.33, "params follow the Settings sensitivity")

	# N opens the noise editor and frees the mouse; a click in Fly mode closes it
	var nw = main.noise_window()
	check(not nw.visible, "the noise editor starts closed")
	await press_action("toggle_noise_editor")
	check(nw.visible, "N opens the noise editor")
	check(not main.is_mouse_captured(), "opening it frees the mouse")
	var nclick := InputEventMouseButton.new()
	nclick.button_index = MOUSE_BUTTON_LEFT
	nclick.pressed = true
	nclick.position = Vector2(400, 300)
	main._unhandled_input(nclick)
	check(not nw.visible, "a click in Fly mode closes the noise editor")

	# the pause menu's Noise button opens the editor and resumes
	main.pause()
	pause.noise_button.pressed.emit()
	check(nw.visible and not paused, "the pause Noise button opens the editor and resumes")
	nw.close()
	main._update_mouse()

	# the pause menu's Console button opens the console, keeps the mouse free and
	# resumes (the way in when a browser swallows the Ctrl tap)
	check(main.is_mouse_captured() and not console.visible, "flying, console closed")
	main.pause()
	pause.console_button.pressed.emit()
	check(console.visible, "the pause Console button opens the console")
	check(not paused and not pause.visible, "and resumes")
	check(not main.is_mouse_captured(), "with the mouse left free to use it")
	# The console holds keyboard focus once open (an embedded window takes it
	# when shown), so keys it does not use are handed on to Main: Escape pauses.
	# Embedded windows draw above the pause menu, so pausing hides them and
	# resuming brings them back.
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	console._unhandled_input(esc)
	check(paused and pause.visible, "Escape in the focused console reaches Main and pauses")
	check(not console.visible, "pausing hides the console so the pause menu is not covered")
	main.resume()
	check(not paused and console.visible, "resuming shows the console again")
	_tap_ctrl(main)
	check(not console.visible and main.is_mouse_captured(), "a Ctrl tap then closes it and recaptures")

	# A Ctrl tap in the focused noise window reaches Main too and opens the console
	nw.open()
	nw._unhandled_input(_key(KEY_CTRL, true))
	nw._unhandled_input(_key(KEY_CTRL, false))
	check(console.visible, "a Ctrl tap in the focused noise window opens the console")
	console.hide_console()
	nw.close()
	main._free_requested = false
	main._update_mouse()
	check(main.is_mouse_captured(), "flying again")

	# a view save carries the noise graph, and loading restores it
	nw.editor().add_node_requested.emit(&"value_noise", Vector2(200, 200))
	await frames(1)
	var vn := &""
	for id in nw.graph().nodes:
		if nw.graph().node(id).type_id == &"value_noise":
			vn = id
	nw.graph().connect_ports(nw.graph().position_id(), 0, vn, 0)
	nw.graph().connect_ports(vn, 0, nw.graph().output_id(), 0)
	await frames(1)
	var ntmp := "user://main_noise_view.json"
	main.save_view_to(ntmp)
	var ndata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ntmp))
	check(ndata.has("noise"), "a view save embeds the noise graph under a 'noise' key")
	nw.editor().new_requested.emit()
	await frames(1)
	main.load_view_from(ntmp)
	await frames(1)
	check_eq(nw.graph().nodes.size(), 3, "loading the view restored the noise graph")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ntmp))

	# Escape pauses and opens the pause menu; Escape again resumes
	main.params.camera_mode = FractalParams.CameraMode.FLY
	await frames(1)
	check(not pause.visible, "the pause menu starts hidden")
	await press_action("pause")
	check(paused and pause.visible, "Escape pauses and opens the pause menu")
	check_eq(pause.menu_button.text, "Back to Menu", "it offers Back to Menu")
	pause.settings_button.pressed.emit()
	check(pause.settings_menu.visible, "and Settings")
	var tabs: TabContainer = pause.settings_menu.tabs
	check(not tabs.is_tab_disabled(1), "in game, the Renderer tab is enabled")
	var dark: float = pause.dim.color.a
	tabs.current_tab = 1
	check(pause.dim.color.a < dark, "the Renderer tab lightens the dim")
	var ro = pause.settings_menu.renderer
	ro.falloff_slider.value = 1.25
	check_approx(main.params.detail_falloff, 1.25, "its falloff slider edits the view's params")
	ro.steps_slider.value = 256
	check_eq(main.params.max_steps, 256, "and its step budget")
	main.params.detail = 3.0
	check_approx(ro.detail_slider.value, 3.0, "and it follows outside changes")
	ro.reset_button.pressed.emit()
	check(main.params.detail == 1.0 and main.params.detail_falloff == 0.0 and main.params.max_steps == 128,
		"Reset puts the renderer defaults back")
	check_eq(main.governor.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the governor keeps running while paused, so edits get a final frame")
	tabs.current_tab = 0
	check_approx(pause.dim.color.a, dark, "back on Controls the dim returns")
	tabs.current_tab = 1
	await press_action("pause")
	check(paused and pause.visible and not pause.settings_menu.visible,
		"Escape in its settings goes back to the pause list")
	await press_action("pause")
	check(not paused and not pause.visible, "Escape again resumes")

	# the load shedder's top level caps the Fly speed and shows in the console
	var top := LoadShedder.top()
	main.governor.shed_level_changed.emit(top)
	check_approx(main.fly.speed_limit, LoadShedder.settings(top)["speed"], "the top shed level caps Fly speed")
	var shed_label: Label = main.console().movement_pane().shed_label
	check(shed_label.visible and shed_label.text == "load shed %d/%d" % [top, top],
		"the console's Movement pane shows the shed level")
	main.governor.shed_level_changed.emit(1)
	check_approx(main.fly.speed_limit, 1.0, "lower levels leave the speed alone")
	main.governor.shed_level_changed.emit(0)
	check(not shed_label.visible, "level 0 hides the readout")

	# Back to Menu unpauses and swaps to the main menu
	await press_action("pause")
	pause.menu_button.pressed.emit()
	await frames(2)
	check(not paused, "Back to Menu unpauses")
	check(current_scene != null and current_scene.name == "MainMenu", "and loads the main menu")
	if current_scene:
		current_scene.queue_free()

	# clean up the runtime InputMap actions the keymap registered
	for action in [&"axis_a_pos", &"axis_a_neg"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	main.queue_free()
	await frames(1)
	settings.mouse_sensitivity = original_sens
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://main_test_settings.cfg"))
