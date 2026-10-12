class_name EscapeAnimationPane
extends ScrollContainer
## Level-owned timing for the sky reveal and distance fog clearing.

var controls := {}
var _settings: GameplaySettings


func _init() -> void:
	name = "Escape Animation"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	add_child(list)
	var description := Label.new()
	description.text = "Cross the exit sphere to reveal the sky and clear the distance fog.\nBoth fades start together. Returning inside resets the effect."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(description)
	for field in [[&"escape_sky_duration", "Skybox fade in"], [&"escape_fog_duration", "Distance fog fade out"]]:
		var key: StringName = field[0]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = field[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = 60.0
		spin.allow_greater = true
		spin.step = 0.1
		spin.suffix = "s"
		spin.custom_minimum_size.x = 180
		spin.tooltip_text = "Seconds from escape to completion. Zero makes this transition immediate. Saved with the level."
		spin.value_changed.connect(func(value: float):
			if _settings != null:
				_settings.set(key, value))
		row.add_child(spin)
		list.add_child(row)
		controls[key] = spin


func setup(settings: GameplaySettings) -> void:
	if _settings != null and _settings.changed.is_connected(_refresh):
		_settings.changed.disconnect(_refresh)
	_settings = settings
	_settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for key in controls:
		controls[key].set_value_no_signal(_settings.get(key))
