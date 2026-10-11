class_name DecimalSpinBox
extends SpinBox
## A float SpinBox that shows its value as a short decimal and whose arrows step
## the least significant digit shown:
##
##   4.01 -> 4.02     4.00001 -> 4.00002     4 -> 5     2.5e-05 -> 2.6e-05
##
## A value that is a short decimal (up to CLEAN_DIGITS significant digits, give
## or take float noise) shows exactly that, so whatever was typed shows as
## typed. Anything else (a log-slider value, 1/9) is rounded to SHORT_DIGITS
## significant digits for display. The value itself is never rounded except by
## an arrow step, which lands on the stepped decimal exactly.
##
## Stepping keeps its digit: 4.09 steps to 4.10 (shown with the zero), not 4.1,
## so a run of clicks keeps moving the same digit. Typing, or any other change,
## picks the digit afresh from the new value.
##
## Range.step is 0, so nothing quantizes a typed value; SpinBox's own text (16
## decimals at step 0) is overwritten wherever SpinBox writes it. Listen to
## `number_changed`, not `value_changed`: it fires once per change, with the
## stepped value.

signal number_changed(value: float)

## Significant digits a value may need and still count as a short decimal.
const CLEAN_DIGITS := 10
## Relative error allowed between a value and the short decimal it shows as.
const CLEAN_TOLERANCE := 1e-12
## Significant digits shown for a value that is not a short decimal.
const SHORT_DIGITS := 4
## Below this magnitude (and at or above SCI_MAX) the text is scientific.
const SCI_MIN := 1e-4
const SCI_MAX := 1e15

## The largest step the arrows take, or 0 for no limit. A row sets it to the
## power of ten that fits its slider range, so 0 in a ±0.1 range steps 0.1.
var max_unit := 0.0:
	set(v):
		max_unit = v
		_adopt(value)

## The decimal shown: value ≈ _digits × 10^_exponent. The arrows step _digits.
var _digits := 0
var _exponent := 0
## The value the decimal was taken from, to tell a fresh value from the same one
## and an arrow step (this ± unit) from any other change.
var _value := 0.0
var _typing := false
var _stepping := false


func _init() -> void:
	step = 0.0
	value_changed.connect(_on_value_changed)
	var line := get_line_edit()
	line.text_changed.connect(func(_t: String) -> void: _typing = true)
	# SpinBox handles both deferred, rewriting the text; ours queue after it.
	line.editing_toggled.connect(_on_editing_toggled, CONNECT_DEFERRED)
	line.text_submitted.connect(_on_text_submitted, CONNECT_DEFERRED)
	_adopt(value)


func _notification(what: int) -> void:
	# Both run after SpinBox's own handling, which has just written its text.
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_DRAW:
		_show()


func _gui_input(event: InputEvent) -> void:
	# SpinBox wheels by Range.step, which is 0 here; wheel by the shown digit.
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not get_line_edit().is_editing():
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		value = _stepped(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		accept_event()


## The text the field shows (or will, once any typing ends).
func shown_text() -> String:
	return _text(_digits, _exponent)


## The size of one arrow step: the place value of the last digit shown.
func unit() -> float:
	return _compose(1, _exponent)


# ------------------------------------------------------------------ changes

func _on_value_changed(v: float) -> void:
	if _stepping:
		return
	var direction := _step_direction(v)
	if direction != 0:
		_digits += direction
		var exact := _compose(_digits, _exponent)
		_value = exact
		if exact != v:
			_stepping = true
			value = exact
			_stepping = false
	else:
		_adopt(v)
	_typing = false
	_show()
	number_changed.emit(value)


## +1 or -1 when `v` is one arrow step up or down from the value (as SpinBox
## computes it, float noise and all), else 0. The step lands on the shown
## decimal ± one, so a value shown rounded (0.1111 for 1/9) steps to 0.1112.
func _step_direction(v: float) -> int:
	var tolerance := unit() * 1e-6
	if absf(v - (_value + unit())) <= tolerance:
		return 1
	if absf(v - (_value - unit())) <= tolerance:
		return -1
	return 0


func _stepped(direction: int) -> float:
	return clampf(_compose(_digits + direction, _exponent), min_value, max_value)


func _on_editing_toggled(_on: bool) -> void:
	# Entering: SpinBox has written its 16 decimals; put the short text back.
	# Leaving: SpinBox has submitted and rewritten; if the value did not change,
	# no value_changed follows to restore it.
	_typing = false
	_show()


func _on_text_submitted(_t: String) -> void:
	_typing = false
	_show()


## Take the decimal afresh from `v`.
func _adopt(v: float) -> void:
	_value = v
	var d := decompose(v)
	_digits = d[0]
	_exponent = d[1]
	while not _within_max_unit():
		_exponent -= 1
		_digits *= 10
	custom_arrow_step = unit()


func _within_max_unit() -> bool:
	return max_unit <= 0.0 or unit() <= max_unit * (1.0 + 1e-9)


func _show() -> void:
	custom_arrow_step = unit()
	if value != _value:
		_adopt(value)
	var line := get_line_edit()
	var text := shown_text()
	if _typing or line.text == text:
		return
	var all := line.has_selection() and line.get_selected_text() == line.text
	var caret := line.caret_column
	line.text = text
	if all:
		line.select_all()
	else:
		line.caret_column = mini(caret, text.length())


# ------------------------------------------------------------------ decimals

## The decimal a value shows as: [digits, exponent] with value ≈ digits × 10^exponent,
## no trailing zeros in `digits` past the decimal point, and exponent ≤ 0 for a
## value below SCI_MAX (an integer shows every digit, so 400 steps to 401).
static func decompose(v: float) -> Array:
	if v == 0.0 or not is_finite(v):
		return [0, 0]
	var magnitude := _magnitude(v)
	var start := mini(magnitude, 0) if absf(v) < SCI_MAX else magnitude - CLEAN_DIGITS + 1
	# Shortest decimal within the tolerance: the value is a short decimal.
	for e in range(start, magnitude - CLEAN_DIGITS, -1):
		var k := _round_at(v, e)
		if absf(_compose(k, e) - v) <= absf(v) * CLEAN_TOLERANCE:
			return _trimmed(k, e)
	# Otherwise round to SHORT_DIGITS significant digits, keeping integer digits.
	var e_short := magnitude - SHORT_DIGITS + 1
	if absf(v) < SCI_MAX:
		e_short = mini(e_short, 0)
	return _trimmed(_round_at(v, e_short), e_short)


## A value as the console shows it.
static func format(v: float) -> String:
	if not is_finite(v):
		return str(v)
	var d := decompose(v)
	return _text(d[0], d[1])


## The largest power of ten no bigger than `span` (0 for no span).
static func power_of_ten_below(span: float) -> float:
	if span <= 0.0 or not is_finite(span):
		return 0.0
	return _compose(1, _magnitude(span))


## digits × 10^exponent as the nearest float (exact division by a power of ten).
static func _compose(digits: int, exponent: int) -> float:
	if exponent >= 0:
		return float(digits) * pow(10.0, exponent)
	if exponent >= -22:
		return float(digits) / pow(10.0, -exponent)
	return float(digits) * pow(10.0, exponent)


## Decimal exponent of the leading digit: 0 for 4.01, -5 for 0.0000123.
static func _magnitude(v: float) -> int:
	var m := int(floor(log(absf(v)) / log(10.0)))
	if absf(v) >= pow(10.0, m + 1):
		m += 1
	elif absf(v) < pow(10.0, m):
		m -= 1
	return m


static func _round_at(v: float, exponent: int) -> int:
	if exponent >= 0:
		return int(roundf(v / pow(10.0, exponent)))
	return int(roundf(v * pow(10.0, -exponent)))


static func _trimmed(digits: int, exponent: int) -> Array:
	while exponent < 0 and digits != 0 and digits % 10 == 0:
		digits /= 10
		exponent += 1
	if digits == 0:
		exponent = mini(exponent, 0)
	return [digits, exponent]


## The text for digits × 10^exponent, every digit kept (4.10 stays 4.10).
static func _text(digits: int, exponent: int) -> String:
	var sign := "-" if digits < 0 else ""
	var s := str(absi(digits))
	var v := absf(_compose(digits, exponent))
	if digits != 0 and (v < SCI_MIN or v >= SCI_MAX):
		var e := exponent + s.length() - 1
		var mantissa := s.left(1) + ("." + s.substr(1) if s.length() > 1 else "")
		return "%s%se%s%02d" % [sign, mantissa, "-" if e < 0 else "+", absi(e)]
	if exponent >= 0:
		return sign + s + "0".repeat(exponent if digits != 0 else 0)
	var places := -exponent
	if s.length() <= places:
		s = "0".repeat(places - s.length() + 1) + s
	return sign + s.left(s.length() - places) + "." + s.right(places)
