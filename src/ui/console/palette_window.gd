class_name PaletteWindow
extends VBoxContainer
## The console's Colour window, ported from Fractacular: twelve sliders over the
## Palette, the three cosine curves they make, and the gradient they come out
## as. It sits at the top of the console's Colour tab, above the Colour,
## Lighting and Palette rows.
##
## It owns no colour itself. Every slider writes one component through
## `Palette.set_component()` (so into the shape table) and every readout is
## drawn back from the model, so an edit from anywhere (a slider, the matching
## Palette row, Reset, a loaded view) moves the same widgets.
##
## The curve plot and the strip sit under the sliders because twelve numbers
## mean nothing until you see what they do, and the strip is the only honest
## preview of the fractal: it is the same formula the shader runs, fed the
## driven values while a component is bound (set_resolved).

const FORMULA := "color(x) = A + B · cos(2π (Cx + D))"

const FORMULA_TOOLTIP := "Inigo Quilez's cosine palette. Each of A, B, C and D is a red, green and blue triple, so twelve numbers describe a whole run of colour. The Palette colour mode paints the surface through it; Palette input, frequency and offset (below) say what runs along it and how fast. Each number is also a row under Palette, where it can be bound to an axis or Time with its own waveform."
const HINT := "Set Colour to Palette (below) to paint the fractal with this."
const HINT_TOOLTIP := "The palette is only used by the Palette colour mode. Editing it in any other mode changes nothing on screen until you switch."
const VECTOR_TOOLTIPS := [
	"A — the middle level each channel oscillates around. All three at 0.5 is a balanced palette; lowering one tints the whole run away from that colour, and raising A above 1 − B clips the bright end flat.",
	"B — the contrast: how far each channel swings either side of A. 0 freezes a channel at its A level (B all zero is one flat colour); 0.5 with A at 0.5 uses the full range. A + B over 1, or A − B under 0, clips.",
	"C — how many times each channel cycles across one pass of the palette. 1 is one smooth sweep; equal whole numbers above 1 repeat the gradient that many times; different values per channel make long, non-repeating runs.",
	"D — where each channel starts in its cycle, in turns. Channels a third of a turn apart (0, 0.33, 0.67) are what make the default a rainbow; setting all three equal gives greys.",
]
const CHANNEL_NAMES := ["red", "green", "blue"]
const RESET_TOOLTIP := "Put all twelve numbers back to the default rainbow (A and B 0.5, C 1, D 0 / 0.33 / 0.67). Bindings are kept."

var _palette: Palette
var _formula: Label
var _hint: Label
var _letters: Array[Label] = []
var _sliders: Array[HSlider] = []
var _values: Array[Label] = []
var _curves: PaletteCurves
var _strip: PaletteStrip
var _reset: Button
var _updating := false


## Which palette this window edits. Call before adding it to the tree.
func setup(palette: Palette) -> void:
	_palette = palette


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_formula()
	_hint = Label.new()
	_hint.text = HINT
	_hint.tooltip_text = HINT_TOOLTIP
	_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	add_child(_hint)
	for vector in Palette.VECTOR_NAMES.size():
		_build_vector_row(vector)

	_curves = PaletteCurves.new()
	_curves.setup(_palette)
	_curves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_curves)

	_strip = PaletteStrip.new()
	_strip.setup(_palette)
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_strip)

	_reset = Button.new()
	_reset.text = "Reset"
	_reset.tooltip_text = RESET_TOOLTIP
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(_on_reset_pressed)
	add_child(_reset)

	if _palette != null:
		_palette.changed.connect(_refresh)
	_refresh()


## The slider for one component: `vector` 0..3 = A..D, `channel` 0..2 = r, g, b.
func slider(vector: int, channel: int) -> HSlider:
	var i := _index(vector, channel)
	return _sliders[i] if i < _sliders.size() else null


## The two-decimal readout under that slider.
func value_label(vector: int, channel: int) -> Label:
	var i := _index(vector, channel)
	return _values[i] if i < _values.size() else null


## The bold A / B / C / D at the head of a row.
func letter_label(vector: int) -> Label:
	var i := clampi(vector, 0, 3)
	return _letters[i] if i < _letters.size() else null


func formula_label() -> Label:
	return _formula


## "Set Colour to Palette…", shown while another colour mode is in use.
func hint_label() -> Label:
	return _hint


## Feed one frame of resolved values, so the curves and strip follow any
## bound component.
func set_resolved(values: Dictionary) -> void:
	if _palette != null:
		_palette.set_live(values)


func curves() -> PaletteCurves:
	return _curves


func strip() -> PaletteStrip:
	return _strip


func reset_button() -> Button:
	return _reset


# ----------------------------------------------------------------- building

func _build_formula() -> void:
	_formula = Label.new()
	_formula.text = FORMULA
	_formula.tooltip_text = FORMULA_TOOLTIP
	_formula.mouse_filter = Control.MOUSE_FILTER_STOP
	_formula.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_formula.add_theme_color_override("font_color", Color(0.65, 0.66, 0.72))
	add_child(_formula)


func _build_vector_row(vector: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var letter := Label.new()
	letter.text = Palette.VECTOR_NAMES[vector]
	letter.tooltip_text = VECTOR_TOOLTIPS[vector]
	letter.mouse_filter = Control.MOUSE_FILTER_STOP
	letter.custom_minimum_size = Vector2(16, 0)
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 15)
	# The default theme has no bold face; an outline in the text colour is
	# the cheapest way to make the letter read heavier than the readouts.
	letter.add_theme_constant_override("outline_size", 1)
	letter.add_theme_color_override("font_outline_color", Color(0.9, 0.9, 0.9))
	row.add_child(letter)
	_letters.append(letter)

	for channel in 3:
		row.add_child(_build_cell(vector, channel))


## One slider over its readout, the readout tinted so the row reads r, g, b.
func _build_cell(vector: int, channel: int) -> Control:
	var tooltip := "%s, %s channel.\n\n%s" % [
		Palette.VECTOR_NAMES[vector], CHANNEL_NAMES[channel], VECTOR_TOOLTIPS[vector]]
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var range_: Vector2 = Palette.RANGES[vector]
	var s := HSlider.new()
	s.min_value = range_.x
	s.max_value = range_.y
	s.step = Palette.STEP
	s.tooltip_text = tooltip
	s.focus_mode = Control.FOCUS_NONE
	# The wheel scrolls the panel, never the value.
	s.scrollable = false
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(_on_slider_changed.bind(vector, channel))
	cell.add_child(s)
	_sliders.append(s)

	var readout := Label.new()
	readout.text = "0.00"
	readout.tooltip_text = tooltip
	readout.mouse_filter = Control.MOUSE_FILTER_STOP
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", 11)
	readout.add_theme_color_override("font_color", PaletteCurves.CHANNEL_COLORS[channel])
	cell.add_child(readout)
	_values.append(readout)
	return cell


# ------------------------------------------------------------------ editing

func _index(vector: int, channel: int) -> int:
	return clampi(vector, 0, 3) * 3 + clampi(channel, 0, 2)


func _on_slider_changed(value: float, vector: int, channel: int) -> void:
	if _updating or _palette == null:
		return
	_palette.set_component(vector, channel, value)


## Draw every widget back from the model. The guard keeps a refresh from
## looking like twelve fresh edits.
func _refresh() -> void:
	if _palette == null:
		return
	_hint.visible = not _palette.in_use()
	_updating = true
	for vector in 4:
		for channel in 3:
			var v := _palette.get_component(vector, channel)
			var i := _index(vector, channel)
			_sliders[i].value = v
			_values[i].text = "%.2f" % v
	_updating = false


func _on_reset_pressed() -> void:
	if _palette != null:
		_palette.reset()
