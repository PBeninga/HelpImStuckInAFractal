class_name ViewPane
extends ScrollContainer
## The console's View tab: everything the old pause menu held that is not a
## shape knob. A Save level… / Load level… row with the current file's name and a
## status line, the Camera mode (Fly / Orbit), the Noise editor… button, the
## mouse sensitivity, the Window buttons (Fullscreen, Reset window), the
## Renderer options (detail, march steps, Fast Controls, Reset camera) and Back
## to Menu. It hands each choice back through its signals; Main owns the files,
## the noise window, the windows and the scene change.
##
## The sensitivity is the player's (the Settings autoload keeps it), so Main
## wires it through `sensitivity_changed` / set_sensitivity(): naming the
## autoload here would stop a `-s` test from compiling the console.

signal save_requested
signal load_requested
signal noise_requested
signal menu_requested
signal fullscreen_requested
signal reset_window_requested
signal sensitivity_changed(value: float)

## The autoload's script, for its range constants only.
const SettingsScript := preload("res://src/settings/settings.gd")

var save_button: Button
var load_button: Button
var noise_button: Button
var menu_button: Button
var fullscreen_button: Button
var reset_window_button: Button
var camera_option: OptionButton
var sens_slider: HSlider
var sens_value: Label
var file_label: Label
var status_label: Label
var renderer: RendererOptions

var _params: FractalParams
var _syncing := false


func _init() -> void:
	name = "View"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	add_child(list)

	list.add_child(_heading("FILE"))
	var files_row := HBoxContainer.new()
	files_row.add_theme_constant_override("separation", 8)
	save_button = _button("Save level…",
		"Save the level to a file in saves/: the shape, the bindings, the keys and axes, the camera, the noise graph and the preferences (Cmd/Ctrl+S overwrites the current file).")
	load_button = _button("Load level…", "Load a saved level from saves/.")
	file_label = Label.new()
	files_row.add_child(save_button)
	files_row.add_child(load_button)
	files_row.add_child(file_label)
	list.add_child(files_row)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.visible = false
	list.add_child(status_label)

	list.add_child(_heading("CAMERA"))
	var camera_row := HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 8)
	var cam_label := Label.new()
	cam_label.text = "Camera"
	camera_option = OptionButton.new()
	camera_option.focus_mode = Control.FOCUS_NONE
	camera_option.add_item("Fly", 0)
	camera_option.add_item("Orbit", 1)
	camera_row.add_child(cam_label)
	camera_row.add_child(camera_option)
	list.add_child(camera_row)
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 8)
	var sens_label := Label.new()
	sens_label.text = "Mouse sensitivity"
	sens_slider = HSlider.new()
	sens_slider.min_value = SettingsScript.SENSITIVITY_MIN
	sens_slider.max_value = SettingsScript.SENSITIVITY_MAX
	sens_slider.step = 0.001
	sens_slider.focus_mode = Control.FOCUS_NONE
	sens_slider.custom_minimum_size = Vector2(240, 0)
	sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sens_value = Label.new()
	sens_value.custom_minimum_size = Vector2(56, 0)
	sens_row.add_child(sens_label)
	sens_row.add_child(sens_slider)
	sens_row.add_child(sens_value)
	list.add_child(sens_row)

	noise_button = _button("Noise editor…",
		"Open the noise-field editor (also the N key): author a 3D noise field as a node graph and see it displace and tint the fractal live.")
	noise_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	list.add_child(noise_button)

	# The browser places the canvas itself, and only a click's own handler may
	# ask it for fullscreen, so the web build has no Window row.
	var window_heading := _heading("WINDOW")
	window_heading.visible = not OS.has_feature("web")
	list.add_child(window_heading)
	var window_row := HBoxContainer.new()
	window_row.add_theme_constant_override("separation", 8)
	fullscreen_button = _button("Fullscreen",
		"Fill the screen with one window: the view on the left, this console docked on the right. On a Mac it gets a desktop of its own.")
	reset_window_button = _button("Reset window",
		"Put the game window back at its default size (half the screen) in the middle of its screen, and the console beside it.")
	window_row.add_child(fullscreen_button)
	window_row.add_child(reset_window_button)
	window_row.visible = window_heading.visible
	list.add_child(window_row)

	list.add_child(_heading("RENDERER"))
	renderer = RendererOptions.new()
	list.add_child(renderer)

	list.add_child(HSeparator.new())
	menu_button = _button("Back to Menu", "Leave the view for the title menu. Unsaved changes are lost.")
	menu_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	list.add_child(menu_button)

	save_button.pressed.connect(save_requested.emit)
	load_button.pressed.connect(load_requested.emit)
	noise_button.pressed.connect(noise_requested.emit)
	menu_button.pressed.connect(menu_requested.emit)
	fullscreen_button.pressed.connect(fullscreen_requested.emit)
	reset_window_button.pressed.connect(reset_window_requested.emit)
	camera_option.item_selected.connect(_on_camera_selected)
	sens_slider.value_changed.connect(_on_sens_changed)
	show_file("")


## Wire the camera option and the Renderer options to params. Call once.
func setup(params: FractalParams) -> void:
	_params = params
	renderer.setup(params)
	params.changed.connect(_refresh)
	_refresh()


## The current save's name, or an em dash when there is none.
func show_file(display_name: String) -> void:
	file_label.text = display_name if display_name != "" else "—"


## One line about the last save or load; "" hides it.
func show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


## Label the Fullscreen button for the layout in force.
func show_fullscreen(on: bool) -> void:
	fullscreen_button.text = "Exit fullscreen" if on else "Fullscreen"


## Show the sensitivity without emitting `sensitivity_changed`.
func set_sensitivity(value: float) -> void:
	sens_slider.set_value_no_signal(value)
	sens_value.text = "%.3f" % value


func _on_sens_changed(value: float) -> void:
	sens_value.text = "%.3f" % value
	sensitivity_changed.emit(value)


func _on_camera_selected(index: int) -> void:
	if _syncing or _params == null:
		return
	_params.camera_mode = index


func _refresh() -> void:
	if _params == null:
		return
	_syncing = true
	camera_option.select(_params.camera_mode)
	_syncing = false


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0))
	return l


func _button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	return b
