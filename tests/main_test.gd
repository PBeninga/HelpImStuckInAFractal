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

	# the console opens beside the game at startup (for now), the fly camera is
	# active and the mouse captured; the rest of the journey starts it closed
	check(console.visible, "the console starts open")
	console.hide_console()
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

	# Fullscreen: the View tab's button docks the console into the right-hand
	# strip of the main window and narrows the view to the rest. (Headless
	# cannot really go fullscreen; the layout is what is checked.)
	_tap_ctrl(main)
	console.show_tab(2)
	await frames(1)
	var vpane: ViewPane = console.view_pane()
	check(await ui.scroll_to(vpane, vpane.fullscreen_button), "the Fullscreen button scrolls into view")
	await ui.click(vpane.fullscreen_button)
	await frames(1)
	check(main.is_docked() and console.is_docked(), "the Fullscreen button docks the console")
	check_eq(vpane.fullscreen_button.text, "Exit fullscreen", "and relabels itself")
	check(console.visible and console.is_embedded() and console.borderless, "docked, it is a borderless window inside the main one")
	var canvas := root.get_visible_rect()
	var strip := Rect2(Vector2(console.position), Vector2(console.size))
	check_approx(strip.end.x, canvas.end.x, "the strip reaches the right edge", 1.0)
	check_approx(strip.size.y, canvas.size.y, "and fills the height", 1.0)
	check_approx(strip.size.x, WindowGeometry.dock_width(canvas.size.x), "its width is dock_width() of the window", 1.0)
	check_approx(main.view.size.x, canvas.size.x - strip.size.x, "the view fills the rest", 1.0)
	check_approx(main.view.position.x, 0.0, "on the left")
	console.show_tab(0)
	await frames(1)
	await ui.click(console.inspector().row(&"box_scale").get_child(0) as Control)
	check(console.visible and not main.is_mouse_captured(), "a click on the docked console is the console's")
	await ui.click_at(Vector2(main.view.size.x * 0.5, canvas.size.y * 0.5))
	check(main.is_mouse_captured() and console.visible, "a click on the view beside it recaptures")
	_tap_ctrl(main)   # free the mouse; the console stays open
	_tap_ctrl(main)   # close it
	check(not console.visible, "a Ctrl tap still hides the docked console")
	check_approx(main.view.size.x, canvas.size.x, "and the view takes the whole width back", 1.0)
	_tap_ctrl(main)
	check(console.visible and console.is_docked(), "and opens it docked again")
	check_approx(main.view.size.x, canvas.size.x - strip.size.x, "beside the narrowed view", 1.0)
	console.show_tab(2)
	await frames(1)
	await ui.click(vpane.fullscreen_button)
	await frames(1)
	check(not main.is_docked() and not console.is_docked(), "Exit fullscreen undocks the console")
	check_eq(vpane.fullscreen_button.text, "Fullscreen", "and the button says so")
	check(console.force_native and not console.borderless, "it asks to be a native window again")
	check_approx(main.view.size.x, canvas.size.x, "and the view fills the window", 1.0)
	check(not console.visible, "it waits for the window to settle")
	await create_timer(main.WINDOW_SETTLE_DELAY + 0.2).timeout
	check(console.visible, "then reopens beside the main window")

	# Reset window forgets where the windows were left.
	settings.set_window_rect(&"console", Rect2i(10, 10, 900, 600))
	console.remembered_rect = Rect2i(10, 10, 900, 600)
	vpane.reset_window_requested.emit()
	await frames(1)   # deferred, like the button's own press
	check_eq(settings.window_rect(&"console"), Rect2i(), "Reset window forgets the remembered places")
	check_eq(console.remembered_rect, Rect2i(), "and the console's")
	console.hide_console()
	main._free_requested = false
	main._update_mouse()

	# the console's View tab owns Save / Load / Camera / Noise / Renderer
	var vp: ViewPane = main.view_pane()
	check(vp == console.view_pane(), "the View tab is the console's")
	var files: WorkspaceFiles = main.workspace_files()
	check(vp.save_requested.is_connected(files.prompt_save), "View Save opens the save panel")
	check(vp.load_requested.is_connected(files.prompt_load), "View Load opens the open panel")

	# save and load: the real path round-trips a knob (the shape table), the
	# axes and the camera
	var tmp := "user://main_test_view.json"
	main.table().set_default(&"fold_limit", 0.72)
	main.camera.speed_factor = 2.0
	main.save_view_to(tmp)
	check_eq(files.current_path, tmp, "a save that worked becomes current")
	check_eq(vp.file_label.text, "main_test_view.json", "and the View tab names it")
	main.table().set_default(&"fold_limit", 0.3)
	main.camera.speed_factor = 1.0
	main.load_view_from(tmp)
	check_approx(main.table().get_default(&"fold_limit"), 0.72, "loading restores the shape table")
	await frames(1)
	check_approx(main.params.fold_limit, 0.72, "and the resolve pushes it into params")
	check_approx(main.camera.speed_factor, 2.0, "and the camera")
	check(vp.status_label.text.begins_with("Loaded"), "the View tab reports the load: %s" % vp.status_label.text)
	main.load_view_from("user://no_such_view.json")
	check_eq(files.current_path, tmp, "a failed load does not change the current file")

	# Reset camera goes back to the current file's camera and speed factor, from
	# the console's Movement pane and from the View tab's Renderer options
	var file_view: Transform3D = main.camera.transform
	main.camera.transform = file_view.translated(Vector3(0.5, -1, 2))
	main.camera.speed_factor = 7.0
	console.movement_pane().reset_camera_button.pressed.emit()
	check(main.camera.transform.is_equal_approx(file_view), "the console's Reset camera restores the file's camera")
	check_approx(main.camera.speed_factor, 2.0, "and its speed factor")
	main.camera.transform = file_view.rotated(Vector3(0, 0, 1), 0.3)
	vp.renderer.reset_camera_button.pressed.emit()
	check(main.camera.transform.is_equal_approx(file_view), "the View tab's Reset camera does too")
	# a save makes the saved camera the new reset point
	main.camera.transform = file_view.translated(Vector3(0, 0, 1))
	var resaved: Transform3D = main.camera.transform
	main.save_view_to(tmp)
	main.camera.transform = file_view
	main.reset_camera()
	check(main.camera.transform.is_equal_approx(resaved), "after a save, Reset camera goes to the saved camera")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# the View tab's Camera row switches mode
	vp.camera_option.select(1)
	vp.camera_option.item_selected.emit(1)
	check_eq(main.params.camera_mode, FractalParams.CameraMode.ORBIT, "the View Camera row switches to orbit")
	vp.camera_option.select(0)
	vp.camera_option.item_selected.emit(0)
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
	check_approx(vp.sens_slider.value, 0.33, "and so does the View tab's slider")
	vp.sens_slider.value = 0.2
	check_approx(settings.mouse_sensitivity, 0.2, "which writes Settings")

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

	# the View tab's Noise button opens the editor
	vp.noise_button.pressed.emit()
	check(nw.visible, "the View Noise button opens the editor")
	check(not main.is_mouse_captured(), "with the mouse free")
	nw.close()
	main._free_requested = false
	main._update_mouse()

	# Escape frees the mouse and does nothing else: no pause, the console stays
	# shut, and a click in the view recaptures
	check(main.is_mouse_captured() and not console.visible, "flying, console closed")
	await press_action("cancel")
	check(not main.is_mouse_captured(), "Escape frees the mouse")
	check(not paused, "without pausing the tree")
	check(not console.visible, "and without opening the console")
	main._unhandled_input(nclick)
	check(main.is_mouse_captured(), "a click in the view recaptures")
	# Escape never closes the console: with it open and holding keyboard focus,
	# its unused keys reach Main, and Escape there only frees the mouse
	_tap_ctrl(main)
	check(console.visible and not main.is_mouse_captured(), "a Ctrl tap opens the console and frees the mouse")
	main._unhandled_input(nclick)
	check(main.is_mouse_captured() and console.visible, "a click recaptures with the console left open")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	console._unhandled_input(esc)
	check(not main.is_mouse_captured(), "Escape in the focused console reaches Main and frees the mouse")
	check(console.visible and not paused, "and leaves the console open, unpaused")
	_tap_ctrl(main)
	check(not console.visible and main.is_mouse_captured(), "a Ctrl tap then closes it and recaptures")
	# WASD in the console hands focus back to the game and recaptures, the
	# console left open
	_tap_ctrl(main)
	check(console.visible and not main.is_mouse_captured(), "a Ctrl tap opens the console again")
	console.game_focus_requested.emit()
	check(main.is_mouse_captured() and console.visible, "WASD in the console recaptures with the console left open")
	_tap_ctrl(main)
	_tap_ctrl(main)
	check(not console.visible and main.is_mouse_captured(), "closed again, flying")

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

	# the console's Shape tab says whether the shape is self-similar, and follows
	# both the shape and the noise graph (the loaded graph displaces the surface)
	console.open()
	await frames(1)
	var ss := console.self_similarity_label()
	check_eq(ss.text, "Self-similar: no (noise field displaces the surface)", "a displacing noise field is never self-similar")
	nw.editor().new_requested.emit()
	await frames(1)
	check_eq(ss.text, "Self-similar: no (c follows the point)", "with the field gone, the default Mandelbox still is not")
	main.table().set_default(&"julia_all", true)
	await frames(1)
	check_eq(ss.text, "Self-similar: yes (Julia: all four c fixed)", "Julia (all) is, and the line follows the shape")
	var dvn: StringName = nw.graph().add_node(&"value_noise", Vector2(200, 200))
	nw.graph().connect_ports(nw.graph().position_id(), 0, dvn, 0)
	nw.graph().connect_ports(dvn, 0, nw.graph().output_id(), 0)
	await frames(1)
	check_eq(ss.text, "Self-similar: no (noise field displaces the surface)", "wiring Displace turns it off again")
	nw.editor().new_requested.emit()
	main.table().set_default(&"julia_all", false)
	await frames(1)
	console.hide_console()

	# the View tab's Renderer options edit the view's params
	main.params.camera_mode = FractalParams.CameraMode.FLY
	await frames(1)
	check_eq(vp.menu_button.text, "Back to Menu", "the View tab offers Back to Menu")
	var ro: RendererOptions = vp.renderer
	ro.falloff_slider.value = 1.25
	check_approx(main.params.detail_falloff, 1.25, "its falloff slider edits the view's params")
	ro.steps_slider.value = 256
	check_eq(main.params.max_steps, 256, "and its step budget")
	main.params.detail = 3.0
	check_approx(ro.detail_slider.value, 3.0, "and it follows outside changes")
	ro.reset_button.pressed.emit()
	check(main.params.detail == 1.0 and main.params.detail_falloff == 0.0 and main.params.max_steps == 128,
		"Reset puts the renderer defaults back")

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

	# the fly camera's zoom limit reaches the Movement pane each frame
	var zoom_label: Label = main.console().movement_pane().zoom_label
	main.fly.at_zoom_limit = true
	main._process(0.0)
	check(zoom_label.visible, "Main shows the fly camera's zoom limit in the Movement pane")
	main.fly.at_zoom_limit = false
	main._process(0.0)
	check(not zoom_label.visible, "and hides it once the limit clears")

	# Back to Menu swaps to the main menu
	vp.menu_button.pressed.emit()
	await frames(2)
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
