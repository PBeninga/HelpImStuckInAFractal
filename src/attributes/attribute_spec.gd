class_name AttributeSpec
extends RefCounted
## Describes one scalar knob of the shape inspector: its id (also the shader
## uniform name), its type and range, whether it can be driven by a binding, and
## the plain-language tooltip and "what different values do" text every row
## shows. Ported from Fractacular's AttributeSpec, with the Category dropped:
## there is one table here (the Mandelbox shape), so a knob needs no category.
##
## Vector quantities are several specs sharing a `group`, so the inspector has
## exactly one row shape.

enum Type { FLOAT, INT, BOOL, ENUM, COLOR }

const REQUIRED_KEYS := ["id", "label", "type", "default", "tooltip", "effects"]

## Stable key and shader uniform name, e.g. `box_scale`.
var id: StringName
## Human name shown in the inspector.
var label: String
var type: Type
var default_value: Variant
## Slider range. Spin boxes may type past it up to the hard range.
var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.01
## Absolute limits for typed and driven values. Default to min/max.
var hard_min: float = 0.0
var hard_max: float = 1.0
## Slider is logarithmic; the inspector shows "(log)" and real tick values.
var log_scale: bool = false
## Driven/typed values wrap into [min, max) instead of clamping (angles).
var wrap: bool = false
## False for BOOL and ENUM, which have no meaningful additive drive.
var bindable: bool = true
## What this is, in plain language.
var tooltip: String = ""
## What different values do, e.g. "s = 2 classic box; |s| < 1 dust".
var effects: String = ""
## Optional heading so vectors cluster visually. Must have a glossary entry.
var group: String = ""
var enum_labels: Array[String] = []
## Value stored for each label. Defaults to the label indices.
var enum_values: Array[int] = []
## Optional `Callable(values: Dictionary) -> bool`; false collapses the row.
var show_when: Callable = Callable()
## Optional `Callable(values: Dictionary) -> bool`; false disables the row.
var enabled_when: Callable = Callable()


## Build a spec from a dictionary. Keys: the REQUIRED_KEYS plus optional
## `min`, `max`, `step`, `hard_min`, `hard_max`, `log`, `wrap`, `bindable`,
## `group`, `enum_labels`, `enum_values`, `show_when`, `enabled_when`.
static func make(d: Dictionary) -> AttributeSpec:
	for key in REQUIRED_KEYS:
		if not d.has(key):
			push_error("AttributeSpec.make: missing '%s' in %s" % [key, d])
			return null
	var s := AttributeSpec.new()
	s.id = StringName(d["id"])
	s.label = String(d["label"])
	s.type = d["type"] as Type
	s.tooltip = String(d["tooltip"])
	s.effects = String(d["effects"])
	s.group = String(d.get("group", ""))
	s.log_scale = bool(d.get("log", false))
	s.wrap = bool(d.get("wrap", false))
	match s.type:
		Type.FLOAT:
			s.min_value = float(d.get("min", 0.0))
			s.max_value = float(d.get("max", 1.0))
			s.step = float(d.get("step", 0.01))
			s.default_value = float(d["default"])
		Type.INT:
			s.min_value = float(d.get("min", 0))
			s.max_value = float(d.get("max", 1))
			s.step = 1.0
			s.default_value = int(d["default"])
		Type.BOOL:
			s.default_value = bool(d["default"])
			s.bindable = false
		Type.ENUM:
			s.enum_labels.assign(d.get("enum_labels", []))
			if d.has("enum_values"):
				s.enum_values.assign(d["enum_values"])
			else:
				for i in s.enum_labels.size():
					s.enum_values.append(i)
			s.min_value = 0.0
			s.max_value = float(maxi(s.enum_labels.size() - 1, 0))
			s.step = 1.0
			s.default_value = int(d["default"])
			s.bindable = false
		Type.COLOR:
			s.default_value = sanitize_color(d["default"])
			s.bindable = false
	s.hard_min = float(d.get("hard_min", s.min_value))
	s.hard_max = float(d.get("hard_max", s.max_value))
	if d.has("bindable"):
		s.bindable = bool(d["bindable"]) and s.type != Type.BOOL and s.type != Type.ENUM and s.type != Type.COLOR
	if d.has("show_when"):
		s.show_when = d["show_when"]
	if d.has("enabled_when"):
		s.enabled_when = d["enabled_when"]
	return s


func is_shown(values: Dictionary) -> bool:
	return not show_when.is_valid() or bool(show_when.call(values))


func is_enabled(values: Dictionary) -> bool:
	return not enabled_when.is_valid() or bool(enabled_when.call(values))


## Bring any candidate value into this spec's legal domain.
func sanitize(value: Variant) -> Variant:
	match type:
		Type.FLOAT:
			var v := float(value)
			if wrap:
				return wrapf(v, min_value, max_value)
			return clampf(v, hard_min, hard_max)
		Type.INT:
			return int(roundf(clampf(float(value), hard_min, hard_max)))
		Type.BOOL:
			return bool(value)
		Type.ENUM:
			var iv := int(value)
			return iv if enum_values.has(iv) else default_value
		Type.COLOR:
			return sanitize_color(value)
	return value


## A candidate colour as an opaque Color: a Color (alpha forced to 1), or the
## 3- or 4-element Array that JSON round-trips (alpha, element 4, is ignored).
static func sanitize_color(value: Variant) -> Color:
	if value is Color:
		var c: Color = value
		return Color(c.r, c.g, c.b, 1.0)
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	return Color.WHITE
