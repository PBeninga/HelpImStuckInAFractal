class_name SettingsMenu
extends VBoxContainer
## The title menu's settings page. Its Controls tab edits the Settings autoload
## directly. (The open view's renderer options live in the console's View tab.)
## `back` asks the owner to show its own list again.

signal back

var tabs: TabContainer
var sens_slider: HSlider
var sens_value: Label
var back_button: Button


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	add_child(title)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(600, 0)
	var panel := StyleBoxFlat.new()   # padded, and dark enough to read over the view
	panel.bg_color = Color(0, 0, 0, 0.6)
	panel.set_content_margin_all(16)
	panel.set_corner_radius_all(4)
	tabs.add_theme_stylebox_override("panel", panel)
	add_child(tabs)

	var controls := VBoxContainer.new()
	controls.name = "Controls"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Mouse sensitivity"
	sens_slider = HSlider.new()
	sens_slider.min_value = Settings.SENSITIVITY_MIN
	sens_slider.max_value = Settings.SENSITIVITY_MAX
	sens_slider.step = 0.001
	sens_slider.custom_minimum_size = Vector2(240, 0)
	sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sens_value = Label.new()
	sens_value.custom_minimum_size = Vector2(56, 0)
	row.add_child(label)
	row.add_child(sens_slider)
	row.add_child(sens_value)
	controls.add_child(row)
	tabs.add_child(controls)

	back_button = MenuButtons.make("Back")
	add_child(back_button)

	sens_slider.value_changed.connect(func(v): Settings.mouse_sensitivity = v)
	back_button.pressed.connect(back.emit)


func _ready() -> void:
	Settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	sens_slider.set_value_no_signal(Settings.mouse_sensitivity)
	sens_value.text = "%.3f" % Settings.mouse_sensitivity
