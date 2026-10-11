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
	check_eq(tabs.get_tab_count(), 2, "settings has two tabs")
	check_eq([tabs.get_tab_title(0), tabs.get_tab_title(1)], ["Controls", "Renderer"], "Controls and Renderer")
	check(tabs.is_tab_disabled(1), "with no view open, the Renderer tab is disabled")
	check(tabs.get_tab_tooltip(1) != "", "and says where to find it")
	await press_action("pause")
	check(not menu.settings_menu.visible and menu.play_button.is_visible_in_tree(),
		"Escape goes back to the list")
	menu.settings_button.pressed.emit()
	menu.settings_menu.back_button.pressed.emit()
	check(not menu.settings_menu.visible, "so does Back")

	menu.queue_free()
	await frames(1)

	# --- the pause menu's controls block: Save/Load/Camera/Fast/Console/Noise ---
	# Untyped (like MainMenu above): naming PauseMenu would compile its
	# SettingsMenu/Settings-autoload dependency at this test's own compile time.
	var params := FractalParams.new()
	var pause = load("res://src/ui/pause_menu.gd").new()
	root.add_child(pause)
	pause.setup(params)
	await frames(1)
	check_eq(pause.save_button.text, "Save view…", "pause menu has a Save view button")
	check_eq(pause.load_button.text, "Load view…", "pause menu has a Load view button")
	check_eq(pause.noise_button.text, "Noise editor…", "pause menu has a Noise editor button")
	check_eq(pause.console_button.text, "Console…", "pause menu has a Console button")
	check(pause.console_button.tooltip_text.contains("Ctrl"), "whose tooltip names the Ctrl tap")
	check(pause.camera_option.item_count == 2, "pause menu has a Camera option (Fly / Orbit)")
	check(pause.fast_check != null, "pause menu has a Fast Controls checkbox")
	# the camera option writes params
	pause.camera_option.select(1)
	pause.camera_option.item_selected.emit(1)
	check_eq(params.camera_mode, FractalParams.CameraMode.ORBIT, "the Camera option writes params.camera_mode")
	# the fast checkbox writes params
	pause.fast_check.button_pressed = false
	pause.fast_check.toggled.emit(false)
	check_eq(params.fast_controls, false, "the Fast Controls checkbox writes params.fast_controls")
	# external change refreshes the widgets
	params.camera_mode = FractalParams.CameraMode.FLY
	await frames(1)
	check_eq(pause.camera_option.selected, 0, "an external camera-mode change refreshes the option")
	# the file name and status helpers
	pause.show_file("my_view.json")
	check_eq(pause.file_label.text, "my_view.json", "show_file names the current save")
	pause.show_status("Saved my_view.json")
	check(pause.status_label.visible and pause.status_label.text.begins_with("Saved"), "show_status reports a line")
	# save/load/noise emit their signals
	var fired := {}
	pause.save_requested.connect(func(): fired["save"] = true)
	pause.load_requested.connect(func(): fired["load"] = true)
	pause.noise_requested.connect(func(): fired["noise"] = true)
	pause.console_requested.connect(func(): fired["console"] = true)
	pause.save_button.pressed.emit()
	pause.load_button.pressed.emit()
	pause.noise_button.pressed.emit()
	pause.console_button.pressed.emit()
	check(fired.has("save") and fired.has("load") and fired.has("noise"), "Save/Load/Noise emit their signals")
	check(fired.has("console"), "Console emits console_requested")
	pause.queue_free()
	await frames(1)

	settings.mouse_sensitivity = original
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _find_label(node: Node, text: String) -> Label:
	for child in node.find_children("*", "Label", true, false):
		if child.text == text:
			return child
	return null
