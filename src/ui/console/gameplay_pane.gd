class_name GameplayPane
extends ScrollContainer
## Level files, the escape boundary and flight/spawn controls.

signal save_requested
signal load_requested
signal return_requested

var save_button: Button
var load_button: Button
var return_button: Button
var file_label: Label
var status_label: Label
var scaling_check: CheckBox
var controls := {}
var _settings: GameplaySettings
var _list: VBoxContainer
var _syncing := false


func _init() -> void:
	name = "Gameplay"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)

	_heading("LEVEL")
	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 8)
	save_button = _button("Save level…", "Save shapes, gameplay, camera, keys and noise. Cmd/Ctrl+S overwrites the current file.")
	load_button = _button("Load level…", "Load a level from saves/.")
	file_label = Label.new()
	file_label.text = "—"
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	files.add_child(save_button)
	files.add_child(load_button)
	files.add_child(file_label)
	_list.add_child(files)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.visible = false
	_list.add_child(status_label)

	_heading("EXIT SPHERE")
	_number(&"exit_radius", "Exit Radius", 0.001, 1000000.0, "World-space sphere centered at (0, 0, 0). Outside its radius, you escaped.")
	_heading("SPAWN")
	for axis in ["x", "y", "z"]:
		_number(StringName("spawn_" + axis), "Spawn " + axis.to_upper(), -1000000.0, 1000000.0,
			"World-space spawn coordinate. Editing it does not move the camera until Return to spawn.", true)
	return_button = _button("Return to spawn", "Go to the configured spawn, keep your view direction, and reset the mouse-wheel speed factor to 1.")
	return_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_list.add_child(return_button)

	_heading("MOVEMENT")
	_number(&"move_speed", "Move speed", 0.001, 1000.0, "Travel multiplier with distance scaling on; world units per second with it off. Mouse-wheel speed applies on top.")
	_number(&"shift_multiplier", "Shift speed multiplier", 0.001, 100.0, "Multiplies move speed while Shift is held; default 2.")
	scaling_check = CheckBox.new()
	scaling_check.text = "Scale speed by camera-ray distance"
	scaling_check.tooltip_text = "Slow near the surface straight ahead; turn off for fixed travel speed. The player zoom-limit stop applies to manual flight; agent movement bypasses it."
	scaling_check.focus_mode = Control.FOCUS_NONE
	_list.add_child(scaling_check)
	_number(&"distance_power", "Distance response power", 0.01, 4.0, "1 is linear. Below 1 softens distance changes; above 1 exaggerates them. Nearest-surface and speed caps still apply.")
	_number(&"near_cap", "Nearest-surface cap", 0.001, 1000.0, "Cap the distance speed at this times the distance to the closest surface, even when looking along a corridor. Default 10.")
	_number(&"max_distance_speed", "Max distance speed", 0.001, 1000000.0, "Upper limit on distance speed before the move, Shift, mouse-wheel and load-shed multipliers. Default 20.")
	_heading("AGENT PERCEPTION")
	_integer(&"surrounding_ray_count", "Surrounding geometry rays", 4, 64,
		"Number of multidirectional surface rays in the geometry estimate sent to the support agent. More rays give a denser estimate.")

	_integer(&"depth_scan_width", "Screen depth columns", 8, 128,
		"Width of the cached screen depth grid. Height follows the view aspect ratio. Higher values reveal smaller openings.")
	_integer(&"depth_scan_interval", "Depth refresh frames", 1, 30,
		"Refresh the screen depth cache every this many rendered frames. Default 2.")

	save_button.pressed.connect(save_requested.emit)
	load_button.pressed.connect(load_requested.emit)
	return_button.pressed.connect(return_requested.emit)
	scaling_check.toggled.connect(func(on):
		if _settings != null:
			_settings.distance_scaling = on)


func setup(settings: GameplaySettings) -> void:
	_settings = settings
	settings.changed.connect(_refresh)
	_refresh()


func show_file(display_name: String) -> void:
	file_label.text = display_name if display_name != "" else "—"
	file_label.tooltip_text = display_name


func show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


func _refresh() -> void:
	_syncing = true
	for key in controls:
		controls[key].value = _settings.get(key)
	scaling_check.set_pressed_no_signal(_settings.distance_scaling)
	for key in [&"distance_power", &"near_cap", &"max_distance_speed"]:
		controls[key].editable = _settings.distance_scaling
	_syncing = false


func _number(key: StringName, text: String, minimum: float, maximum: float, tooltip: String, signed := false) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	# Spawn coordinates retain all typed digits. DecimalSpinBox intentionally
	# shortens long numbers for ordinary knobs, which SpinBox can re-commit
	# as shortened text on Enter; use the full-precision field for spawn.
	var spin: SpinBox = SpinBox.new() if signed else DecimalSpinBox.new()
	spin.step = 0.0
	# Positive gameplay fields accept any finite positive double, including
	# tiny nested-level scales. Zero is rejected by their Resource setters.
	spin.min_value = minimum if signed else 0.0
	spin.max_value = maximum
	spin.allow_greater = key != &"distance_power"
	spin.allow_lesser = signed
	spin.custom_minimum_size.x = 180
	spin.tooltip_text = tooltip
	var changed: Signal = spin.value_changed if signed else (spin as DecimalSpinBox).number_changed
	changed.connect(func(v):
		if _settings != null and not _syncing:
			_settings.set(key, v)
			if _settings.get(key) != v:
				_refresh())
	row.add_child(spin)
	_list.add_child(row)
	controls[key] = spin


func _integer(key: StringName, text: String, minimum: int, maximum: int, tooltip: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.custom_minimum_size.x = 180
	spin.tooltip_text = tooltip
	spin.value_changed.connect(func(v):
		if _settings != null and not _syncing:
			_settings.set(key, int(v)))
	row.add_child(spin)
	_list.add_child(row)
	controls[key] = spin


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0))
	_list.add_child(label)


func _button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	return button
