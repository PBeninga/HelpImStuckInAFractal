class_name AttributeRow
extends HBoxContainer
## One knob in the Shape inspector: a label, a value widget, and — when the
## attribute is bindable — the four binding widgets.
##
##   [label (log)]  [slider ──── spin]   [source ▾] [gain] [wave ▾] [period]
##                  [ min   mid    max ]           (log rows only)
##                  [→ 1.234 ]                     (while a binding is active)
##
## Every edit goes through the AttributeTable, which emits `changed`; the row
## then re-reads itself in `refresh()`. `_updating` guards that round trip.
## Ported from Fractacular's AttributeRow, with compact mode removed and the
## source dropdown made dynamic (None, Time, then one item per virtual axis).

const LABEL_MIN_WIDTH := 140.0
const SPIN_MIN_WIDTH := 92.0
const SMALL_SPIN_WIDTH := 76.0
const OPTION_MIN_WIDTH := 92.0
const WIDE_ROW_MIN_WIDTH := 627.0
const FLASH_SECONDS := 0.3
const FLASH_COLOR := Color(1.0, 0.45, 0.45)

const WAVE_LABELS := ["Linear", "Sine", "Triangle"]

const SOURCE_TOOLTIP := "Source: which live value drives this attribute on top of its default. None leaves the default alone. Time is the global clock in seconds; the others are virtual axes pushed by key pairs."
const GAIN_TOOLTIP := "Gain: multiplies the source before it is added to the default. Negative flips the direction; 0 silences the drive without forgetting the rest of the setting."
const WAVE_TOOLTIP := "Waveform: how the source is shaped before it is added. Linear passes it straight through, so the value tracks the source. Sine and Triangle oscillate between -1 and +1 once per Period."
const PERIOD_TOOLTIP := "Period: how many units of the source make one full oscillation. Used by Sine and Triangle only, so it is disabled for Linear."
const READOUT_TOOLTIP := "The value in use this frame: default + gain x waveform(source)."

var spec: AttributeSpec

var _table: AttributeTable
var _label: Label
var _slider: HSlider
var _spin: SpinBox
var _check: CheckBox
var _option: OptionButton
var _picker: ColorPickerButton
var _readout: Label
var _source: OptionButton
var _gain: DecimalSpinBox
var _wave: OptionButton
var _period: DecimalSpinBox
var _updating := false
var _flash: Tween
var _cost_score := -1.0
var _slider_tip := ""
## Array of {id: StringName, label: String} for the source dropdown's axes.
var _axis_list: Array = []


## Build the row for one attribute of one table. Call before adding the row to a
## parent; it creates its own children.
func setup(attribute: AttributeSpec, table: AttributeTable) -> void:
	spec = attribute
	_table = table
	add_theme_constant_override("separation", 6)
	_build_label()
	_build_value()
	if spec.bindable:
		_build_binding()
	_table.changed.connect(_on_table_changed)
	refresh()


## The axes available as binding sources: Array of {id, label}.
func set_sources(axis_list: Array) -> void:
	_axis_list = axis_list
	_rebuild_source_items()
	refresh()


## Re-read every widget from the table: value and visibility (`show_when`).
func refresh() -> void:
	if _table == null or spec == null:
		return
	_updating = true
	var values := _table.defaults()
	visible = spec.is_shown(values)
	var value: Variant = _table.get_default(spec.id)
	if _slider != null:
		_slider.value = _to_slider(float(value))
	if _spin != null:
		_spin.value = float(value)
	if _check != null:
		_check.button_pressed = bool(value)
	if _option != null:
		_select_id(_option, int(value))
	if _picker != null:
		_picker.color = value as Color
	if _source != null:
		var b := _table.binding(spec.id)
		if b != null:
			_select_source(b.source)
			_gain.value = b.gain
			_select_id(_wave, int(b.waveform))
			_period.value = b.period
			_period.editable = b.waveform != Binding.Waveform.LINEAR
			if not b.is_active():
				_readout.visible = false
	_updating = false
	refresh_cost(values)


## Show the value actually used this frame, for a row whose binding is active.
func set_resolved(value: Variant) -> void:
	if _readout == null:
		return
	var b: Binding = _table.binding(spec.id) if _table != null else null
	if b == null or not b.is_active() or value == null:
		_readout.visible = false
		return
	_readout.visible = true
	_readout.text = "→ %s" % _format(value)


## The full resolved dictionary lets one control react to another (shadow yaw).
## The inspector feeds existing resolved values; there is no new process loop.
func refresh_cost(values: Dictionary) -> void:
	if _slider == null:
		return
	var value := float(values.get(spec.id, _table.get_default(spec.id)))
	var cost := RenderCost.score(spec.id, value, values)
	if cost == _cost_score:
		return
	_cost_score = cost
	_slider.modulate = RenderCost.tint(cost)
	if _slider_tip.is_empty():
		_slider_tip = _slider.tooltip_text
	var level := "Low" if cost == 0.0 else ("High" if cost >= 0.75 else "Moderate")
	_slider.tooltip_text = _slider_tip + "\n\n" + level + " estimated cost. " + RenderCost.explanation(spec.id) + "\n" + RenderCost.LEGEND


func value_control() -> Control:
	if _slider != null:
		return _slider
	if _check != null:
		return _check
	if _picker != null:
		return _picker
	return _option


func spin_box() -> SpinBox:
	return _spin


func source_option() -> OptionButton:
	return _source


func gain_spin() -> SpinBox:
	return _gain


func wave_option() -> OptionButton:
	return _wave


func period_spin() -> SpinBox:
	return _period


func readout() -> Label:
	return _readout


# ----------------------------------------------------------------- building

func _build_label() -> void:
	_label = Label.new()
	_label.text = spec.label + (" (log)" if spec.log_scale else "")
	var tip := spec.tooltip + "\n\n" + spec.effects
	if spec.log_scale:
		tip += "\n\nThe slider is logarithmic: equal distances along it are equal ratios, not equal steps."
	if spec.wrap:
		tip += "\n\nThis value wraps: past the end of the range it reappears at the other end."
	_label.tooltip_text = tip
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.custom_minimum_size = Vector2(LABEL_MIN_WIDTH, 0)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _build_value() -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	match spec.type:
		AttributeSpec.Type.FLOAT, AttributeSpec.Type.INT:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_child(row)

			_slider = HSlider.new()
			_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_slider.scrollable = false
			if spec.log_scale:
				_slider.min_value = 0.0
				_slider.max_value = 1.0
				_slider.step = 0.001
				_slider.tooltip_text = "Drag to set %s between %s and %s on a logarithmic track." % [
					spec.label, _format_number(spec.min_value), _format_number(spec.max_value)]
			else:
				_slider.min_value = spec.min_value
				_slider.max_value = spec.max_value
				_slider.step = spec.step
				_slider.tooltip_text = "Drag to set %s between %s and %s." % [
					spec.label, _format_number(spec.min_value), _format_number(spec.max_value)]
			_slider.value_changed.connect(_on_slider_changed)
			row.add_child(_slider)

			if spec.type == AttributeSpec.Type.FLOAT:
				var decimal := DecimalSpinBox.new()
				# Steps no coarser than the slider range: 0 in a ±0.1 range steps 0.1, not 1.
				decimal.max_unit = DecimalSpinBox.power_of_ten_below(spec.max_value - spec.min_value)
				decimal.number_changed.connect(_on_spin_changed)
				_spin = decimal
			else:
				_spin = SpinBox.new()
				_spin.step = spec.step
				_spin.value_changed.connect(_on_spin_changed)
			_spin.min_value = spec.hard_min
			_spin.max_value = spec.hard_max
			_spin.custom_minimum_size = Vector2(SPIN_MIN_WIDTH, 0)
			_spin.tooltip_text = "Type an exact value. The slider covers %s ... %s; typing is allowed out to %s ... %s, and anything beyond that is clamped (the box flashes red)." % [
				_format_number(spec.min_value), _format_number(spec.max_value),
				_format_number(spec.hard_min), _format_number(spec.hard_max)]
			_spin.get_line_edit().text_submitted.connect(_on_spin_text_submitted)
			row.add_child(_spin)

			if spec.log_scale:
				column.add_child(_build_ticks())
		AttributeSpec.Type.BOOL:
			_check = CheckBox.new()
			_check.text = "on"
			_check.tooltip_text = "Turn %s on or off. %s" % [spec.label, spec.tooltip]
			_check.toggled.connect(_on_check_toggled)
			column.add_child(_check)
		AttributeSpec.Type.ENUM:
			_option = OptionButton.new()
			_option.custom_minimum_size = Vector2(OPTION_MIN_WIDTH, 0)
			for i in spec.enum_labels.size():
				_option.add_item(spec.enum_labels[i], spec.enum_values[i])
			_option.tooltip_text = "%s\n\n%s" % [spec.tooltip, spec.effects]
			_option.item_selected.connect(_on_option_selected)
			column.add_child(_option)
		AttributeSpec.Type.COLOR:
			_picker = ColorPickerButton.new()
			_picker.edit_alpha = false
			_picker.custom_minimum_size = Vector2(SPIN_MIN_WIDTH, 0)
			_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_picker.tooltip_text = "%s\n\n%s" % [spec.tooltip, spec.effects]
			_picker.color_changed.connect(_on_color_changed)
			column.add_child(_picker)

	_readout = Label.new()
	_readout.visible = false
	_readout.tooltip_text = READOUT_TOOLTIP
	_readout.mouse_filter = Control.MOUSE_FILTER_STOP
	_readout.add_theme_font_size_override("font_size", 11)
	_readout.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
	column.add_child(_readout)


func _build_ticks() -> HBoxContainer:
	var ticks := HBoxContainer.new()
	var lo := maxf(spec.min_value, 1e-9)
	var hi := maxf(spec.max_value, 1e-9)
	var values := [spec.min_value, sqrt(lo * hi), spec.max_value]
	var alignments := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]
	var tip := "Logarithmic track: its left, middle and right are %s, %s and %s." % [
		_format_number(values[0]), _format_number(values[1]), _format_number(values[2])]
	for i in 3:
		var tick := Label.new()
		tick.text = _format_number(values[i])
		tick.horizontal_alignment = alignments[i]
		tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tick.tooltip_text = tip
		tick.mouse_filter = Control.MOUSE_FILTER_STOP
		tick.add_theme_font_size_override("font_size", 10)
		tick.add_theme_color_override("font_color", Color(0.6, 0.63, 0.72))
		ticks.add_child(tick)
	return ticks


func _build_binding() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	_source = OptionButton.new()
	_source.custom_minimum_size = Vector2(OPTION_MIN_WIDTH, 0)
	_source.tooltip_text = SOURCE_TOOLTIP
	_source.item_selected.connect(_on_source_selected)
	box.add_child(_source)
	_rebuild_source_items()

	_gain = DecimalSpinBox.new()
	_gain.min_value = -1000000.0
	_gain.max_value = 1000000.0
	_gain.custom_minimum_size = Vector2(SMALL_SPIN_WIDTH, 0)
	_gain.tooltip_text = GAIN_TOOLTIP
	_gain.number_changed.connect(_on_gain_changed)
	box.add_child(_gain)

	_wave = OptionButton.new()
	_wave.custom_minimum_size = Vector2(OPTION_MIN_WIDTH, 0)
	for i in WAVE_LABELS.size():
		_wave.add_item(WAVE_LABELS[i], i)
	_wave.tooltip_text = WAVE_TOOLTIP
	_wave.item_selected.connect(_on_wave_selected)
	box.add_child(_wave)

	_period = DecimalSpinBox.new()
	_period.min_value = 0.001
	_period.max_value = 1000000.0
	_period.custom_minimum_size = Vector2(SMALL_SPIN_WIDTH, 0)
	_period.tooltip_text = PERIOD_TOOLTIP
	_period.number_changed.connect(_on_period_changed)
	box.add_child(_period)


## Build the source dropdown: None, Time, then one item per axis. Each item
## stores its source id (a StringName) as metadata. If the current binding's
## source is an axis no longer listed, a "(missing: id)" item preserves it.
func _rebuild_source_items() -> void:
	if _source == null:
		return
	var current: StringName = &""
	var b := _table.binding(spec.id) if _table != null else null
	if b != null:
		current = b.source
	_source.clear()
	_add_source_item("None", &"")
	_add_source_item("Time", &"time")
	var have := {&"": true, &"time": true}
	for axis in _axis_list:
		_add_source_item(String(axis["label"]), StringName(axis["id"]))
		have[StringName(axis["id"])] = true
	if current != &"" and not have.has(current):
		_add_source_item("(missing: %s)" % current, current)
	_select_source(current)


func _add_source_item(text: String, id: StringName) -> void:
	var idx := _source.item_count
	_source.add_item(text)
	_source.set_item_metadata(idx, id)


func _select_source(id: StringName) -> void:
	for i in _source.item_count:
		if StringName(_source.get_item_metadata(i)) == id:
			_source.select(i)
			return


# ------------------------------------------------------------------ editing

func _on_table_changed(_id: StringName) -> void:
	refresh()


func _on_slider_changed(value: float) -> void:
	if _updating:
		return
	_table.set_default(spec.id, _from_slider(value))


func _on_spin_changed(value: float) -> void:
	if _updating:
		return
	_table.set_default(spec.id, value)


func _on_spin_text_submitted(text: String) -> void:
	var typed := float(text)
	if typed < spec.hard_min or typed > spec.hard_max:
		_flash_spin()


func _on_check_toggled(pressed: bool) -> void:
	if _updating:
		return
	_table.set_default(spec.id, pressed)


func _on_option_selected(index: int) -> void:
	if _updating:
		return
	_table.set_default(spec.id, _option.get_item_id(index))


func _on_color_changed(c: Color) -> void:
	if _updating:
		return
	_table.set_default(spec.id, c)


func _on_source_selected(index: int) -> void:
	if _updating:
		return
	var b := _table.binding(spec.id)
	if b == null:
		return
	b.source = StringName(_source.get_item_metadata(index))
	_table.notify_binding_changed(spec.id)


func _on_gain_changed(value: float) -> void:
	if _updating:
		return
	var b := _table.binding(spec.id)
	if b == null:
		return
	b.gain = value
	_table.notify_binding_changed(spec.id)


func _on_wave_selected(index: int) -> void:
	if _updating:
		return
	var b := _table.binding(spec.id)
	if b == null:
		return
	b.waveform = _wave.get_item_id(index) as Binding.Waveform
	_table.notify_binding_changed(spec.id)


func _on_period_changed(value: float) -> void:
	if _updating:
		return
	var b := _table.binding(spec.id)
	if b == null:
		return
	b.period = maxf(value, 0.001)
	_table.notify_binding_changed(spec.id)


func _flash_spin() -> void:
	if _spin == null or not is_inside_tree():
		return
	if _flash != null and _flash.is_valid():
		_flash.kill()
	_spin.modulate = FLASH_COLOR
	_flash = create_tween()
	_flash.tween_property(_spin, "modulate", Color.WHITE, FLASH_SECONDS)


# ------------------------------------------------------------------ helpers

func _select_id(option: OptionButton, id: int) -> void:
	for i in option.item_count:
		if option.get_item_id(i) == id:
			option.select(i)
			return


func _to_slider(value: float) -> float:
	if not spec.log_scale:
		return value
	var lo := log(maxf(spec.min_value, 1e-9))
	var hi := log(maxf(spec.max_value, 1e-9))
	if hi <= lo:
		return 0.0
	return clampf((log(maxf(value, 1e-9)) - lo) / (hi - lo), 0.0, 1.0)


func _from_slider(t: float) -> float:
	if not spec.log_scale:
		return t
	var lo := log(maxf(spec.min_value, 1e-9))
	var hi := log(maxf(spec.max_value, 1e-9))
	return exp(lerpf(lo, hi, clampf(t, 0.0, 1.0)))


func _format_number(value: float) -> String:
	return DecimalSpinBox.format(value)


func _format(value: Variant) -> String:
	match spec.type:
		AttributeSpec.Type.INT:
			return str(int(value))
		AttributeSpec.Type.BOOL:
			return "on" if bool(value) else "off"
		AttributeSpec.Type.ENUM:
			for i in spec.enum_values.size():
				if spec.enum_values[i] == int(value):
					return spec.enum_labels[i]
			return str(value)
	return DecimalSpinBox.format(float(value))
