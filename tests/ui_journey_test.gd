extends "res://tests/test_case.gd"
## One player session through the real scenes, driven only by synthetic mouse
## and keyboard input in a scaled headless root: Play from the title menu; a
## Ctrl tap opens the console and frees the mouse; typing into the Scale row
## reaches the shader; Fold limit bound to Axis A at gain 0.5 moves while E is
## held; WASD flies the camera and the wheel changes its speed; Escape only
## frees the mouse and never closes the console; the console's View tab opens
## the noise window; a Value noise is added and wired; Save level… then New +
## Load level… (on the View tab) restores the shape, the binding, the camera and
## the noise; a resized window asks the view for a frame; the View tab's Back
## to Menu returns to the title.
##
## Main and MainMenu are used untyped (as main_test.gd does): their
## scripts name the Settings autoload, which a `-s` script cannot see when it
## is compiled.

const SAVE := "user://ui_journey.json"
const SETTINGS := "user://ui_journey_settings.cfg"
const MAIN_SCRIPT := "res://src/main.gd"
const MENU_SCRIPT := "res://src/ui/main_menu.gd"

var ui: UiDriver
var main: Node
var settings: Node
var original_sens := 0.0
var original_zoom := 1.0


func run() -> void:
	ui = UiDriver.new(self)
	await ui.setup()
	settings = root.get_node("Settings")
	original_sens = settings.mouse_sensitivity
	original_zoom = settings.console_zoom
	settings.config_path = SETTINGS
	# The autoload has already read the player's file. The journey runs at the
	# default zoom: zoomed in, the View tab shows too little of its pane for
	# its buttons to be clicked without scrolling to them first.
	settings.console_zoom = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	await _play_from_title()
	if main == null:
		check(false, "Main loaded; the rest of the journey needs it")
	else:
		await _ctrl_opens_console()
		await _scale_row_reaches_shader()
		await _axis_drives_fold_limit()
		await _fly_with_keys_and_wheel()
		await _escape_and_view_tab()
		await _wire_value_noise()
		await _save_new_and_reload()
		await _resize_requests_frame()
		await _back_to_menu()

	for action in InputMap.get_actions():
		if String(action).begins_with("axis_"):
			InputMap.erase_action(action)
	if current_scene != null:
		current_scene.queue_free()
	paused = false
	await ui.frames(2)
	settings.mouse_sensitivity = original_sens
	settings.console_zoom = original_zoom
	await ui.frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


# ------------------------------------------------------------ helpers

## Poll the root for a node the predicate accepts, for up to `limit` frames.
func _wait_for(predicate: Callable, limit: int = 60) -> Node:
	for i in limit:
		for n in root.get_children():
			if predicate.call(n):
				return n
		await ui.frames(1)
	return null


## Whether a node runs the script at `path` (compared by path so the script is
## never preloaded into this file).
func _is(n: Node, path: String) -> bool:
	var script: Script = n.get_script()
	return script != null and script.resource_path == path


## Scenes may reset the root's content scale in _ready (UiScale.apply); put the
## driver's 1280x800 logical surface back.
func _rescale() -> void:
	if Vector2i(root.get_visible_rect().size) != UiDriver.SURFACE:
		await ui.setup()


func _material() -> ShaderMaterial:
	return main.view.get_node("SubViewport/ColorRect").material as ShaderMaterial


## A uniform's value; a per-shape array's first slot (the one shape there is).
func _uniform(name: String) -> Variant:
	var v: Variant = _material().get_shader_parameter(name)
	if v is PackedFloat32Array or v is PackedInt32Array or v is PackedVector3Array:
		return v[0]
	return v


func _scroll() -> ScrollContainer:
	return main.console().shape_pane().scroll_container()


## The player clicks somewhere neutral so no text field keeps keyboard focus
## (a focused field silences WASD, the axis keys and the Ctrl tap by design).
func _click_away_from_text(window: Window) -> void:
	var owner := window.gui_get_focus_owner()
	if owner is LineEdit:
		owner.release_focus()
	await ui.frames(1)


# ------------------------------------------------------------ the journey

func _play_from_title() -> void:
	var menu: Node = load("res://src/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await ui.frames(2)
	await _rescale()
	check(menu.play_button.is_visible_in_tree(), "the title menu shows Play Game")
	await ui.click(menu.play_button)
	main = await _wait_for(func(n: Node) -> bool: return _is(n, MAIN_SCRIPT))
	check(main != null, "a click on Play Game loads the explorer")
	if main == null:
		return
	await ui.frames(2)
	await _rescale()
	check(current_scene == main, "the explorer is the current scene")
	check(main.is_mouse_captured(), "flying starts with the mouse captured")
	check(main.console().visible, "and the console open beside it (for now)")
	# The journey opens it with a Ctrl tap, so close it first.
	main.console().hide_console()


func _ctrl_opens_console() -> void:
	await ui.tap(KEY_CTRL)
	await ui.frames(1)
	var console: ConsoleWindow = main.console()
	check(console.visible, "a Ctrl tap opens the console")
	check(not main.is_mouse_captured(), "and frees the mouse")
	var rect := Rect2(Vector2(console.position), Vector2(console.size))
	check(root.get_visible_rect().encloses(rect), "the console opens inside the main window (%s)" % rect)


func _scale_row_reaches_shader() -> void:
	var row: AttributeRow = main.console().inspector().row(&"box_scale")
	check(await ui.scroll_to(_scroll(), row.spin_box()), "the Scale row is in view")
	await ui.type_text(row.spin_box().get_line_edit(), "-1.5")
	await ui.frames(2)
	check_approx(float(main.table().get_default(&"box_scale")), -1.5, "typing -1.5 into Scale writes the shape table")
	check_approx(float(_uniform("box_scale")), -1.5, "and the view's shader sees box_scale = -1.5")
	await _click_away_from_text(main.console())


func _axis_drives_fold_limit() -> void:
	var row: AttributeRow = main.console().inspector().row(&"fold_limit")
	check(await ui.scroll_to(_scroll(), row.source_option()), "the Fold limit row is in view")
	check(await ui.select_option(row.source_option(), "Axis A"), "its Source dropdown picks Axis A")
	await ui.type_text(row.gain_spin().get_line_edit(), "0.5")
	await _click_away_from_text(main.console())
	var b: Binding = main.table().binding(&"fold_limit")
	check(b != null and b.source == &"a" and is_equal_approx(b.gain, 0.5), "Fold limit is bound to Axis A at gain 0.5")
	var axis_before: float = main.keymap().axes().value(&"a")
	var uniform_before := float(_uniform("fold_limit"))
	await ui.hold(KEY_E, 1.0)
	await ui.frames(2)
	var axis_after: float = main.keymap().axes().value(&"a")
	check(axis_after > axis_before + 0.5, "holding E for a second pushes Axis A (%.2f -> %.2f)" % [axis_before, axis_after])
	var expected := 1.0 + 0.5 * axis_after
	check_approx(float(_uniform("fold_limit")), expected,
		"the fold_limit uniform follows default + 0.5 x axis (%.3f -> %.3f)" % [uniform_before, float(_uniform("fold_limit"))], 0.01)
	var shown := float(row.readout().text.trim_prefix("→ "))
	check(row.readout().visible and absf(shown - expected) < 0.01,
		"the row's readout shows the value in use (%s)" % row.readout().text)


func _fly_with_keys_and_wheel() -> void:
	# a Ctrl tap closes the console and recaptures the mouse
	await ui.tap(KEY_CTRL)
	await ui.frames(1)
	check(not main.console().visible, "a second Ctrl tap closes the console")
	check(main.is_mouse_captured(), "and recaptures the mouse")
	var eye: Vector3 = main.camera.eye()
	await ui.hold(KEY_W, 0.3)
	check(main.camera.eye().distance_to(eye) > 1e-4, "holding W flies the camera forward")
	var forward: Vector3 = main.camera.forward()
	var eye2: Vector3 = main.camera.eye()
	await ui.hold(KEY_D, 0.3)
	check((main.camera.eye() - eye2).dot(main.camera.right()) > 0.0, "holding D strafes it right")
	check(main.camera.forward().is_equal_approx(forward), "keys alone do not turn it")

	var speed: float = main.camera.speed_factor
	await ui.wheel(Vector2(640, 400), false)
	check(main.camera.speed_factor > speed, "the wheel up over the view raises the fly speed (%.2f -> %.2f)" % [speed, main.camera.speed_factor])
	await ui.wheel(Vector2(640, 400), true)
	check_approx(main.camera.speed_factor, speed, "and the wheel down lowers it again")

	await ui.move_to(Vector2(640, 400))
	await ui.move_to(Vector2(700, 380))
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		check(not main.camera.forward().is_equal_approx(forward), "mouse motion turns the captured camera")
	else:
		# Headless cannot capture the mouse, and FlyCamera only looks while
		# Input.mouse_mode reports CAPTURED; mouse look is covered by
		# fly_camera_test.gd through apply_look instead.
		check(main.camera.forward().is_equal_approx(forward),
			"uncaptured mouse motion leaves the heading alone (headless cannot capture; look is covered in fly_camera_test)")


func _escape_and_view_tab() -> void:
	var console: ConsoleWindow = main.console()
	check(main.is_mouse_captured() and not console.visible, "flying, console closed")
	await ui.tap(KEY_ESCAPE)
	check(not main.is_mouse_captured(), "Escape frees the mouse")
	check(not paused and not console.visible, "and does nothing else: no pause, no console")
	await ui.click_at(Vector2(640, 400))
	check(main.is_mouse_captured(), "a click in the view recaptures")

	var vp := await _show_view_tab()
	check(vp.noise_button.is_visible_in_tree(), "the View tab offers Noise editor…")
	await ui.click(vp.noise_button)
	await ui.frames(1)
	check(main.noise_window().visible, "a click on Noise editor… opens the noise window")
	check(not main.is_mouse_captured(), "with the mouse free to use it")

	# The noise window opened focused, and a focused noise window takes Escape
	# for itself and closes. Escape never closes the console.
	await ui.tap(KEY_ESCAPE)
	check(not main.noise_window().visible, "Escape closes the focused noise window")
	check(console.visible, "but leaves the console open")
	await ui.tap(KEY_ESCAPE)
	check(console.visible and not paused, "a second Escape leaves the console open too")
	await ui.tap(KEY_CTRL)
	await ui.frames(1)
	check(not console.visible and main.is_mouse_captured(), "a Ctrl tap closes the console and recaptures")


## Open the console (if shut) and click its View tab. Returns the tab.
func _show_view_tab() -> ViewPane:
	var console: ConsoleWindow = main.console()
	if not console.visible:
		await ui.tap(KEY_CTRL)
		await ui.frames(1)
	var bar := console.tabs().get_tab_bar()
	var title := ui.control_point(bar, bar.get_tab_rect(3).get_center())
	await ui.click_at(title)
	if console.tabs().current_tab != 3:
		# The console had lost focus (a file panel closed over it): the first
		# click only focuses it, as it would for a player.
		await ui.click_at(title)
	check_eq(console.tabs().current_tab, 3, "a click on the View tab shows it")
	return console.view_pane()


func _wire_value_noise() -> void:
	var nw: NoiseWindow = main.noise_window()
	if not nw.visible:
		nw.open()
		await ui.frames(1)
	var editor := nw.editor()
	var ge := editor.graph_edit()
	var canvas := ui.global_rect(ge)
	var at := canvas.position + canvas.size * Vector2(0.2, 0.5)
	await ui.right_click(at)
	check(editor.add_menu().visible, "a right-click on the noise canvas opens the add menu")
	check(await ui.select_popup_item(editor.add_menu(), "Value noise"), "and Value noise is clicked")
	await ui.frames(2)
	var g := nw.graph()
	var vn: StringName = &""
	for id in g.nodes:
		if g.node(id).type_id == &"value_noise":
			vn = id
	check(vn != &"", "the graph has a Value noise node")
	if vn == &"":
		return
	ge.connection_request.emit(String(g.position_id()), 0, String(vn), 0)
	ge.connection_request.emit(String(vn), 0, String(g.output_id()), 0)
	await ui.frames(2)
	check(main.view.shader_uniform_names().has(StringName("n_%s_scale" % vn)), "wired to Displace, it reaches the view's shader")


## On the console's View tab, click Save level… or Load level…, point the panel at
## user:// and type the file name. Returns the panel.
func _use_view_panel(save: bool) -> FileDialog:
	var vp := await _show_view_tab()
	await ui.click(vp.save_button if save else vp.load_button)
	await ui.frames(1)
	var files: WorkspaceFiles = main.workspace_files()
	var dialog := files.save_dialog() if save else files.load_dialog()
	check(dialog.visible, "a click on %s opens the file panel" % ("Save level…" if save else "Load level…"))
	if not dialog.visible:
		return dialog
	dialog.current_dir = ProjectSettings.globalize_path(SAVE.get_base_dir())
	await ui.frames(1)
	await ui.type_text(dialog.get_line_edit(), SAVE.get_file())
	await ui.frames(2)
	return dialog


func _save_new_and_reload() -> void:
	var nw: NoiseWindow = main.noise_window()
	var saved_eye: Vector3 = main.camera.eye()
	var saved_nodes := nw.graph().nodes.size()
	await ui.tap(KEY_N)
	check(not nw.visible, "N closes the noise window")

	var dialog := await _use_view_panel(true)
	check(not dialog.visible, "typing a name into the Save level… panel and Enter closes it")
	check(FileAccess.file_exists(SAVE), "and writes user://ui_journey.json")
	check_eq(main.view_pane().file_label.text, SAVE.get_file(), "the View tab names the saved file")
	main.console().hide_console()
	await ui.frames(1)

	# change everything: shape, binding, camera, noise
	main.table().set_default(&"box_scale", -2.5)
	var cleared := Binding.new()
	main.table().set_binding(&"fold_limit", cleared)
	await ui.hold(KEY_S, 0.3)
	await ui.tap(KEY_N)
	check(nw.visible, "N opens the noise window again")
	await ui.click(nw.editor().new_button)
	await ui.frames(2)
	check_eq(nw.graph().nodes.size(), 2, "New noise field resets the graph")
	await ui.tap(KEY_N)
	check(not nw.visible, "N closes it")
	# the file panel freed the mouse; a click in the view takes it back
	await ui.click_at(Vector2(640, 400))
	check(main.is_mouse_captured(), "a click in the view recaptures the mouse")
	check(main.camera.eye().distance_to(saved_eye) > 1e-4, "the camera moved away since the save")

	var load_dialog := await _use_view_panel(false)
	check(not load_dialog.visible, "typing the name into the Load level… panel and Enter loads it and closes the panel")
	await ui.frames(2)
	check_approx(float(main.table().get_default(&"box_scale")), -1.5, "loading restores the shape (Scale -1.5)")
	var b: Binding = main.table().binding(&"fold_limit")
	check(b != null and b.source == &"a" and is_equal_approx(b.gain, 0.5), "and the Axis A binding at gain 0.5")
	check(main.camera.eye().distance_to(saved_eye) < 1e-4, "and the camera")
	check_eq(nw.graph().nodes.size(), saved_nodes, "and the noise graph")


func _resize_requests_frame() -> void:
	var view: FractalView = main.view
	# let the governor settle into IDLE, then mark the last frame as consumed
	await ui.wait(0.6)
	view._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.content_scale_size = Vector2i(1100, 700)
	await ui.frames(2)
	check_eq(Vector2i(view.size), Vector2i(1100, 700), "the view follows the resized window")
	check_eq(view.viewport_size(), Vector2i(1100, 700), "its SubViewport is resized to match")
	# _apply_size requests a frame whenever the pixel size changes, or the
	# resized target would stay black until the camera or a parameter moved.
	check(view._viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED,
		"a resize asks the view for a frame")
	root.content_scale_size = UiDriver.SURFACE
	await ui.frames(2)


func _back_to_menu() -> void:
	var vp := await _show_view_tab()
	# Wheel over the empty right-hand side: a button under the pointer (the
	# left edge, where scroll_to wheels) keeps the wheel from the scroll.
	var view := ui.global_rect(vp)
	await ui.wheel(Vector2(view.end.x - 40.0, view.get_center().y), true, 20)
	check(view.encloses(ui.global_rect(vp.menu_button)), "the wheel brings Back to Menu into view")
	await ui.click(vp.menu_button)
	var menu := await _wait_for(func(n: Node) -> bool: return _is(n, MENU_SCRIPT))
	check(menu != null, "a click on Back to Menu returns to the title")
	await ui.frames(1)
	check(not is_instance_valid(main) or not main.is_inside_tree(), "and the explorer is gone")
