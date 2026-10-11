extends "res://tests/test_case.gd"
## DecimalSpinBox: a value shows as its short decimal (typed digits kept, float
## noise and long tails dropped), and the arrows step the last digit shown —
## 4.01 -> 4.02, 4.00001 -> 4.00002, 4 -> 5 — through real clicks, with the
## field keeping the short text through focus, typing and submit.

var ui: UiDriver
var spin: DecimalSpinBox
var emitted: Array = []


func run() -> void:
	_formatting()
	ui = UiDriver.new(self)
	await ui.setup()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	spin = DecimalSpinBox.new()
	spin.min_value = -1000.0
	spin.max_value = 1000.0
	spin.position = Vector2(40, 40)
	spin.size = Vector2(160, 32)
	spin.value = 0.1 + 0.2
	holder.add_child(spin)
	spin.number_changed.connect(func(v: float) -> void: emitted.append(v))
	await ui.frames(2)
	check_eq(_text(), "0.3", "a value set before entering the tree shows short (0.1 + 0.2 -> 0.3)")
	await _arrows()
	await _typing()
	await _sticky_digit()
	await _max_unit()


func _formatting() -> void:
	var cases := [
		[0.1 + 0.2, "0.3"], [4.01, "4.01"], [4.00001, "4.00001"], [4.0, "4"],
		[400.0, "400"], [-2.09, "-2.09"], [0.0, "0"], [1.0 / 9.0, "0.1111"],
		[0.000025, "2.5e-05"], [1e-6, "1e-06"], [0.123456789, "0.123456789"],
		[12345.6789012345678, "12346"], [123456.789012345678, "123457"],
		[0.1000000000000000055511, "0.1"], [2.0 / 3.0 * 1e-5, "6.667e-06"],
	]
	for c in cases:
		check_eq(DecimalSpinBox.format(c[0]), c[1], "%s shows as %s" % [c[0], c[1]])
	check_eq(DecimalSpinBox.power_of_ten_below(0.2), 0.1, "the power of ten below 0.2 is 0.1")
	check_eq(DecimalSpinBox.power_of_ten_below(14.0), 10.0, "below 14 is 10")
	check_eq(DecimalSpinBox.power_of_ten_below(1.0), 1.0, "below 1 is 1")


func _text() -> String:
	return spin.get_line_edit().text


## A click on the spin box's up (or down) arrow, through the input pipeline.
func _click_arrow(up: bool) -> void:
	await ui.click_at(ui.global_point(spin, Vector2(0.95, 0.25 if up else 0.75)))
	await ui.frames(1)


func _arrows() -> void:
	var steps := [
		[4.01, true, 4.02, "4.02"], [4.00001, true, 4.00002, "4.00002"], [4.0, true, 5.0, "5"],
		[4.01, false, 4.0, "4.00"], [-2.09, true, -2.08, "-2.08"], [0.000025, true, 0.000026, "2.6e-05"],
		[1.0 / 9.0, true, 0.1112, "0.1112"], [400.0, true, 401.0, "401"],
	]
	for s in steps:
		spin.value = s[0]
		await ui.frames(1)
		emitted.clear()
		await _click_arrow(s[1])
		check_eq(spin.value, s[2], "%s %s steps to exactly %s" % [s[0], "up" if s[1] else "down", s[2]])
		check_eq(_text(), s[3], "and shows %s" % s[3])
		check_eq(emitted, [s[2]], "number_changed fires once, with the stepped value")
	spin.get_line_edit().release_focus()
	await ui.frames(1)


func _typing() -> void:
	await ui.type_text(spin.get_line_edit(), "3.14159")
	await ui.frames(2)
	check_eq(spin.value, 3.14159, "typing 3.14159 sets it exactly (nothing quantizes it)")
	check_eq(_text(), "3.14159", "and it shows as typed, even while focused")
	await _click_arrow(true)
	check_eq(spin.value, 3.1416, "then the up arrow steps the last typed digit (3.1416)")
	spin.get_line_edit().release_focus()
	await ui.frames(2)
	check_eq(_text(), "3.14160", "leaving the field keeps the short text")
	await ui.click(spin.get_line_edit())
	await ui.frames(1)
	check_eq(_text(), "3.14160", "and clicking into it again shows the same digits, not 16 decimals")
	await ui.wheel(spin, false)
	await ui.frames(1)
	check_eq(spin.value, 3.14161, "the wheel, while editing, steps the same digit (3.14161)")
	spin.get_line_edit().release_focus()
	await ui.frames(1)


func _sticky_digit() -> void:
	spin.value = 4.09
	await ui.frames(1)
	await _click_arrow(true)
	check_eq(_text(), "4.10", "4.09 steps to 4.10, keeping the hundredths digit")
	await _click_arrow(true)
	check_eq(spin.value, 4.11, "so the next step is 4.11, not 4.2")
	for i in 100:
		spin.value = spin.value + spin.custom_arrow_step
	check_eq(spin.value, 5.11, "a hundred steps land on 5.11 exactly, without drift")
	check_eq(_text(), "5.11", "and show it")
	spin.get_line_edit().release_focus()
	await ui.frames(1)


func _max_unit() -> void:
	spin.max_unit = 0.1
	spin.value = 0.0
	await ui.frames(1)
	await _click_arrow(true)
	check_eq(spin.value, 0.1, "with max_unit 0.1, 0 steps to 0.1 rather than 1")
	check_eq(_text(), "0.1", "and shows 0.1")
	spin.get_line_edit().release_focus()
	await ui.frames(1)
