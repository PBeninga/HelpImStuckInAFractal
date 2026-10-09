extends "res://tests/test_case.gd"
## The main menu's layout and navigation, and the shared settings page.

const TMP := "user://menus_test_settings.cfg"


func run() -> void:
	var settings: Node = root.get_node("Settings")
	var original: float = settings.mouse_sensitivity
	settings.config_path = TMP

	check_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://src/ui/main_menu.tscn",
		"the game starts on the main menu")

	# Untyped: naming MainMenu here would compile it (and its use of the Settings
	# autoload) before the autoloads exist, which fails under -s.
	var menu = load("res://src/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await frames(1)

	var title := _find_label(menu, "Icebox Nav")
	check(title != null, "the title reads Icebox Nav")
	if title:
		check(title.get_theme_font_size("font_size") >= 64, "in big text")
	check_eq(menu.play_button.text, "Play Game", "Play Game button")
	check_eq(menu.settings_button.text, "Settings", "Settings button")
	check_eq(menu.quit_button.text, "Quit", "Quit button")
	check(not menu.settings_menu.visible, "settings start hidden")

	menu.settings_button.pressed.emit()
	check(menu.settings_menu.visible and not menu.play_button.is_visible_in_tree(),
		"Settings swaps the list for the settings page")
	menu.settings_menu.sens_slider.value = 0.2
	check_approx(settings.mouse_sensitivity, 0.2, "the slider sets the mouse sensitivity")
	settings.mouse_sensitivity = 0.15
	check_approx(menu.settings_menu.sens_slider.value, 0.15, "and follows outside changes")
	var tabs: TabContainer = menu.settings_menu.tabs
	check_eq(tabs.get_tab_count(), 1, "settings has one tab")
	check_eq(tabs.get_tab_title(0), "Controls", "Controls (the renderer is in the console's View tab)")
	await press_action("cancel")
	check(not menu.settings_menu.visible and menu.play_button.is_visible_in_tree(),
		"Escape goes back to the list")
	menu.settings_button.pressed.emit()
	menu.settings_menu.back_button.pressed.emit()
	check(not menu.settings_menu.visible, "so does Back")

	menu.queue_free()
	await frames(1)

	# --- the console's View tab: Save/Load/Camera/Sensitivity/Noise/Renderer/Menu ---
	var params := FractalParams.new()
	var vp := ViewPane.new()
	root.add_child(vp)
	vp.setup(params)
	await frames(1)
	check_eq(vp.name, &"View", "the tab is named View")
	check_eq(vp.save_button.text, "Save level…", "View has a Save level button")
	check_eq(vp.load_button.text, "Load level…", "View has a Load level button")
	check_eq(vp.noise_button.text, "Noise editor…", "View has a Noise editor button")
	check_eq(vp.menu_button.text, "Back to Menu", "View has a Back to Menu button")
	check(vp.camera_option.item_count == 2, "View has a Camera option (Fly / Orbit)")
	check(vp.renderer.fast_check != null, "and the Renderer options with Fast Controls")
	# A focused button or checkbox takes Space (fly up): Reset camera would snap
	# the camera back on every tap, so no Renderer control holds keyboard focus.
	var focusable: Array[String] = []
	for c in vp.renderer.find_children("*", "Control", true, false):
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			focusable.append("%s %s" % [c.get_class(), c.get("text") if c is BaseButton else c.name])
	check(focusable.is_empty(), "no Renderer control takes keyboard focus (%s)" % ", ".join(focusable))
	# the camera option writes params
	vp.camera_option.select(1)
	vp.camera_option.item_selected.emit(1)
	check_eq(params.camera_mode, FractalParams.CameraMode.ORBIT, "the Camera option writes params.camera_mode")
	# the fast checkbox writes params
	vp.renderer.fast_check.toggled.emit(false)
	check_eq(params.fast_controls, false, "the Fast Controls checkbox writes params.fast_controls")
	# external change refreshes the widgets
	params.camera_mode = FractalParams.CameraMode.FLY
	await frames(1)
	check_eq(vp.camera_option.selected, 0, "an external camera-mode change refreshes the option")
	# the sensitivity goes out by signal and comes in without one
	var sens := []
	vp.sensitivity_changed.connect(func(v): sens.append(v))
	vp.set_sensitivity(0.3)
	check(sens.is_empty() and is_equal_approx(vp.sens_slider.value, 0.3), "set_sensitivity shows a value silently")
	vp.sens_slider.value = 0.25
	check(sens.size() == 1 and is_equal_approx(sens[0], 0.25), "dragging the slider emits sensitivity_changed")
	# the file name and status helpers
	vp.show_file("my_view.json")
	check_eq(vp.file_label.text, "my_view.json", "show_file names the current save")
	vp.show_status("Saved my_view.json")
	check(vp.status_label.visible and vp.status_label.text.begins_with("Saved"), "show_status reports a line")
	# the buttons emit their signals
	var fired := {}
	vp.save_requested.connect(func(): fired["save"] = true)
	vp.load_requested.connect(func(): fired["load"] = true)
	vp.noise_requested.connect(func(): fired["noise"] = true)
	vp.menu_requested.connect(func(): fired["menu"] = true)
	vp.save_button.pressed.emit()
	vp.load_button.pressed.emit()
	vp.noise_button.pressed.emit()
	vp.menu_button.pressed.emit()
	check(fired.has("save") and fired.has("load") and fired.has("noise") and fired.has("menu"),
		"Save/Load/Noise/Back to Menu emit their signals")
	vp.queue_free()
	await frames(1)

	settings.mouse_sensitivity = original
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _find_label(node: Node, text: String) -> Label:
	for child in node.find_children("*", "Label", true, false):
		if child.text == text:
			return child
	return null
