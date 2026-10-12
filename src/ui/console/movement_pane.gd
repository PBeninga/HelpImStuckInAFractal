class_name MovementPane
extends VBoxContainer
## The Movement pane: one line per virtual axis (editable label, id, live value,
## a "0" button, speed, two key-capture buttons and a remove button), an "Add
## axis" button, the clock readout and the fly camera's speed-factor readout
## (with "zoom limit" beside it while the camera is held at the zoom floor, and
## "deep N" while the renderer is perturbing) beside a Reset camera button. The keys and axes have no file of their own any
## more — they are saved inside the level (the View tab's Save level…). It is a
## view over Keymap: it writes through the rebind API and refreshes on
## `Keymap.changed`.

## The Reset camera button was pressed; Main owns the camera and does the reset.
signal reset_camera_requested

var _keymap: Keymap
var _clock: Clock
## Optional `Callable() -> float`: the fly camera's speed factor, for a readout.
var _speed_source: Callable = Callable()

var _list: VBoxContainer
var _add_button: Button
var _clock_label: Label
var _speed_label: Label
var reset_camera_button: Button
## The governor's load-shed level, shown only while it is above 0.
var shed_label: Label
var _shed_level := 0
## "zoom limit", on the speed readout line, shown only while the fly camera is
## refusing to go nearer the surface (FlyCamera.at_zoom_limit).
var zoom_label: Label
var _zoom_limit := false
## "deep 20", on the speed readout line, shown only while the renderer is
## perturbing (FractalView.pert_iters() > 0).
var deep_label: Label
var _deep_n := 0
## id -> {label, value, zero, speed, pos, neg, remove}
var _lines: Dictionary = {}
var _updating := false
var _next_id := 1


func setup(keymap: Keymap, clock: Clock, speed_source: Callable = Callable()) -> void:
	_keymap = keymap
	_clock = clock
	_speed_source = speed_source


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = "MOVEMENT"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0))
	add_child(heading)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)

	_add_button = Button.new()
	_add_button.text = "Add axis"
	_add_button.tooltip_text = "Add a new virtual axis with no keys bound yet."
	_add_button.focus_mode = Control.FOCUS_NONE
	_add_button.pressed.connect(_on_add_pressed)
	add_child(_add_button)

	add_child(HSeparator.new())

	_clock_label = Label.new()
	_clock_label.tooltip_text = "The global clock, in seconds. Attributes bound to the Time source read this value."
	add_child(_clock_label)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 12)
	_speed_label = Label.new()
	_speed_label.tooltip_text = "The fly camera's speed factor (the mouse wheel changes it)."
	speed_row.add_child(_speed_label)
	zoom_label = Label.new()
	zoom_label.text = "zoom limit"
	zoom_label.tooltip_text = "The fly camera is as close to the surface as the renderer can draw: nearer, the perturbed march runs out of 32-bit precision after its last handoff (for shapes it does not perturb, the 32-bit positions run out). Moving away is always allowed."
	speed_row.add_child(zoom_label)
	show_zoom_limit(_zoom_limit)
	deep_label = Label.new()
	deep_label.tooltip_text = "The renderer is past the 32-bit limit: the camera's own orbit is worked out in 64-bit on the CPU, k iterations of it are handed to the GPU, and each ray iterates only its small offset from it (perturbation) until the offset is big enough for 32 bits. Hidden while off."
	speed_row.add_child(deep_label)
	show_deep(_deep_n)
	reset_camera_button = _flat_button("Reset camera",
		"Put the camera's position, view and speed factor back where the current save file has them (the starting view when no file is loaded).")
	reset_camera_button.pressed.connect(reset_camera_requested.emit)
	speed_row.add_child(reset_camera_button)
	add_child(speed_row)
	shed_label = Label.new()
	shed_label.tooltip_text = "The resolution governor is shedding quality to hold the frame rate: level / top. Hidden at level 0."
	add_child(shed_label)
	show_shed_level(_shed_level)

	if _keymap != null:
		_keymap.changed.connect(_on_keymap_changed)
	_rebuild()


func _process(_delta: float) -> void:
	_refresh_readouts()


func add_button() -> Button:
	return _add_button


## The widgets of one axis line, for tests: {label, value, zero, speed, pos, neg, remove}.
func axis_line(id: StringName) -> Dictionary:
	return _lines.get(id, {})


func line_ids() -> Array:
	return _lines.keys()


# ----------------------------------------------------------------- building

func _rebuild() -> void:
	_lines.clear()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _keymap == null:
		return
	for axis in _keymap.axes().list():
		_list.add_child(_build_line(axis.id))
	_refresh_readouts()


func _build_line(id: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var label_edit := LineEdit.new()
	label_edit.text = _keymap.axes().label(id)
	label_edit.custom_minimum_size = Vector2(90, 0)
	label_edit.tooltip_text = "The axis label, shown in the Shape pane's source dropdown."
	label_edit.text_submitted.connect(func(t): _on_label_submitted(id, t))
	label_edit.focus_exited.connect(func(): _on_label_submitted(id, label_edit.text))
	row.add_child(label_edit)

	var id_label := Label.new()
	id_label.text = String(id)
	id_label.custom_minimum_size = Vector2(40, 0)
	id_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
	row.add_child(id_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.tooltip_text = "The axis's current value (unbounded). Key pairs push it; bindings read it."
	row.add_child(value_label)

	var zero := Button.new()
	zero.text = "0"
	zero.tooltip_text = "Set this axis back to zero."
	zero.focus_mode = Control.FOCUS_NONE
	zero.pressed.connect(func(): _keymap.axes().set_value(id, 0.0))
	row.add_child(zero)

	var speed := SpinBox.new()
	speed.min_value = -1000000.0
	speed.max_value = 1000000.0
	speed.step = 0.1
	speed.custom_minimum_size = Vector2(72, 0)
	speed.tooltip_text = "Units per second this axis moves while its key is held."
	speed.value = _keymap.axes().speed(id)
	speed.value_changed.connect(func(v): _on_speed_changed(id, v))
	row.add_child(speed)

	var pos := KeyCaptureButton.new()
	pos.tooltip_text = "The key that pushes this axis in the positive direction."
	pos.set_key(_keymap.positive_key(id))
	pos.key_captured.connect(func(k): _on_key_captured(id))
	row.add_child(pos)

	var neg := KeyCaptureButton.new()
	neg.tooltip_text = "The key that pushes this axis in the negative direction."
	neg.set_key(_keymap.negative_key(id))
	neg.key_captured.connect(func(k): _on_key_captured(id))
	row.add_child(neg)

	var remove := Button.new()
	remove.text = "✕"
	remove.tooltip_text = "Remove this axis. Any binding to it falls back to its default."
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func(): _keymap.remove_axis(id))
	row.add_child(remove)

	_lines[id] = {"label": label_edit, "value": value_label, "zero": zero,
		"speed": speed, "pos": pos, "neg": neg, "remove": remove}
	return row


func _flat_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	return b


# ------------------------------------------------------------------ editing

func _on_add_pressed() -> void:
	var id := _unique_id()
	_keymap.add_axis(id, "Axis %s" % String(id).to_upper(), 1.0, KEY_NONE, KEY_NONE)


func _unique_id() -> StringName:
	while true:
		var candidate := StringName("ax%d" % _next_id)
		_next_id += 1
		if not _keymap.axes().has(candidate):
			return candidate
	return &"ax"


func _on_label_submitted(id: StringName, text: String) -> void:
	if _updating or not _keymap.axes().has(id):
		return
	_updating = true
	_keymap.set_label(id, text)
	_updating = false


func _on_speed_changed(id: StringName, value: float) -> void:
	if _updating:
		return
	_updating = true
	_keymap.set_speed(id, value)
	_updating = false


func _on_key_captured(id: StringName) -> void:
	if not _lines.has(id):
		return
	var line: Dictionary = _lines[id]
	_updating = true
	_keymap.bind(id, (line["pos"] as KeyCaptureButton).key(), (line["neg"] as KeyCaptureButton).key())
	_updating = false


func _on_keymap_changed() -> void:
	# A value/speed/label edit I made keeps the current rows (no focus loss);
	# a structural change (add/remove) rebuilds the list.
	if _updating:
		return
	if _lines.size() != _keymap.axes().list().size():
		_rebuild()
	else:
		for id in _lines:
			if not _keymap.axes().has(id):
				_rebuild()
				return


## The governor's load-shed level; shown only while it is above 0.
func show_shed_level(level: int) -> void:
	_shed_level = level
	if shed_label == null:
		return
	shed_label.text = "load shed %d/%d" % [level, LoadShedder.top()]
	shed_label.visible = level > 0


## Whether the fly camera is held at the zoom floor; the readout shows only then.
func show_zoom_limit(on: bool) -> void:
	_zoom_limit = on
	if zoom_label == null:
		return
	zoom_label.visible = on


## The perturbed march's iteration count; the readout shows only while it is above 0.
func show_deep(n: int) -> void:
	_deep_n = n
	if deep_label == null:
		return
	deep_label.text = "deep %d" % n
	deep_label.visible = n > 0


func _refresh_readouts() -> void:
	for id in _lines:
		(_lines[id]["value"] as Label).text = "%.3f" % _keymap.axes().value(id)
	if _clock_label != null:
		_clock_label.text = "t = %.2f s" % (_clock.t if _clock != null else 0.0)
	if _speed_label != null:
		if _speed_source.is_valid():
			_speed_label.text = "speed x%.2f" % float(_speed_source.call())
		else:
			_speed_label.text = ""
