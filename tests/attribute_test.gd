extends "res://tests/test_case.gd"
## AttributeSpec, AttributeTable, Binding: make / sanitize, defaults, bindings,
## to_dict / apply_dict. Ported from Fractacular's attribute_test, with the
## Category dropped.

const F := AttributeSpec.Type.FLOAT


func _float(id: String, default: float, lo: float, hi: float, extra: Dictionary = {}) -> AttributeSpec:
	var d := {"id": id, "label": id, "type": F, "default": default,
		"min": lo, "max": hi, "tooltip": "tip", "effects": "fx"}
	d.merge(extra, true)
	return AttributeSpec.make(d)


func run() -> void:
	# --- make() and sanitize() ---
	var f := _float("f", 0.5, 0.0, 1.0)
	check_eq(f.id, &"f", "id becomes a StringName")
	check_eq(f.hard_min, 0.0, "hard_min defaults to min")
	check_eq(f.hard_max, 1.0, "hard_max defaults to max")
	check(f.bindable, "floats are bindable by default")
	check_eq(f.sanitize(7.0), 1.0, "float clamps to hard_max")
	var wide := _float("w", 0.0, -1.0, 1.0, {"hard_min": -10.0, "hard_max": 10.0})
	check_eq(wide.sanitize(5.0), 5.0, "typed value past the slider range but inside hard range survives")
	var ang := _float("a", 0.0, -180.0, 180.0, {"wrap": true})
	check_eq(ang.sanitize(190.0), -170.0, "wrap folds into [min, max)")

	var i := AttributeSpec.make({"id": "n", "label": "N",
		"type": AttributeSpec.Type.INT, "default": 4, "min": 1, "max": 8,
		"tooltip": "t", "effects": "e"})
	check_eq(i.sanitize(2.6), 3, "INT rounds")
	check_eq(i.sanitize(99), 8, "INT clamps")
	check_eq(i.step, 1.0, "INT step is 1")

	var b := AttributeSpec.make({"id": "b", "label": "B",
		"type": AttributeSpec.Type.BOOL, "default": true, "tooltip": "t", "effects": "e"})
	check(not b.bindable, "BOOL is never bindable")

	var e := AttributeSpec.make({"id": "e", "label": "E",
		"type": AttributeSpec.Type.ENUM, "default": 2, "enum_labels": ["A", "B", "C"],
		"enum_values": [0, 2, 5], "tooltip": "t", "effects": "e"})
	check(not e.bindable, "ENUM is never bindable")
	check_eq(e.sanitize(5), 5, "ENUM keeps a listed value")
	check_eq(e.sanitize(3), 2, "ENUM falls back to default for an unlisted value")
	var e2 := AttributeSpec.make({"id": "e2", "label": "E",
		"type": AttributeSpec.Type.ENUM, "default": 0, "enum_labels": ["X", "Y"],
		"tooltip": "t", "effects": "e"})
	check_eq(e2.enum_values, [0, 1], "enum_values default to indices")

	var hidden := _float("h", 0.0, 0.0, 1.0, {"show_when": func(v: Dictionary) -> bool: return v.get(&"e", 0) == 5})
	check(not hidden.is_shown({&"e": 0}), "show_when false hides")
	check(hidden.is_shown({&"e": 5}), "show_when true shows")
	check(f.is_shown({}), "no show_when means always shown")

	# --- AttributeTable ---
	var table := AttributeTable.new([f, wide, i, b, e])
	check_eq(table.specs.size(), 5, "table keeps every spec")
	check_eq(table.ids(), [&"f", &"w", &"n", &"b", &"e"], "ids() is ordered")
	var changes: Array = []
	table.changed.connect(func(id: StringName) -> void: changes.append(id))
	table.set_default(&"f", 9.0)
	check_eq(table.get_default(&"f"), 1.0, "set_default sanitizes")
	check_eq(changes, [&"f"], "set_default emits changed once")
	table.set_default(&"f", 1.0)
	check_eq(changes.size(), 1, "setting the same value does not emit")
	check(table.binding(&"f") != null, "bindable rows have a Binding")
	check(table.binding(&"b") == null, "non-bindable rows have no Binding")
	check(not table.has_active_binding(), "fresh table has no active binding")
	var bind := Binding.new()
	bind.source = &"time"
	table.set_binding(&"f", bind)
	check(table.has_active_binding(), "a time binding is active")

	# duplicate is independent
	var copy := table.duplicate()
	copy.set_default(&"w", 3.0)
	copy.binding(&"f").gain = 5.0
	check_eq(table.get_default(&"w"), 0.0, "duplicate does not share defaults")
	check_eq(table.binding(&"f").gain, 1.0, "duplicate does not share bindings")

	# --- Binding round trip ---
	var b0 := Binding.new()
	b0.source = &"axis_q"
	b0.gain = 0.5
	b0.waveform = Binding.Waveform.SINE
	b0.period = 2.0
	var b1 := Binding.from_dict(b0.to_dict())
	check_eq(b1.source, &"axis_q", "binding source round-trips as a string")
	check_approx(b1.gain, 0.5, "binding gain round-trips")
	check_eq(b1.waveform, Binding.Waveform.SINE, "binding waveform round-trips")
	check_approx(b1.period, 2.0, "binding period round-trips")

	# --- to_dict / apply_dict with an unknown id warned ---
	table.set_default(&"f", 0.25)
	var active := Binding.new(); active.source = &"axis_q"; active.gain = 2.0
	table.set_binding(&"f", active)
	var dict := table.to_dict()
	check(dict["defaults"].has("f"), "to_dict writes string keys")
	check(dict["bindings"].has("f"), "to_dict writes only active bindings")
	check(not dict["bindings"].has("w"), "an inactive binding is not written")
	var t2 := AttributeTable.new([f, wide, i, b, e])
	t2.set_default(&"b", false)   # a change the dict will not touch
	var warnings := t2.apply_dict({"defaults": {"f": 0.25, "ghost": 9.0}, "bindings": {"f": active.to_dict()}})
	check_approx(t2.get_default(&"f"), 0.25, "apply_dict restores a default")
	check_eq(t2.binding(&"f").source, &"axis_q", "apply_dict restores a binding")
	check_eq(warnings.size(), 1, "one warning for the unknown id")

	# --- COLOR: sanitize an Array to a Color, round-trip through JSON ---
	var col := AttributeSpec.make({"id": "lc", "label": "Light colour",
		"type": AttributeSpec.Type.COLOR, "default": Color(1, 1, 1),
		"tooltip": "t", "effects": "e"})
	check(not col.bindable, "a COLOR spec is not bindable")
	check(col.default_value is Color, "its default is a Color")
	check((col.sanitize([0.2, 0.4, 0.6]) as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"sanitize turns a 3-array into an opaque Color")
	check((col.sanitize([0.2, 0.4, 0.6, 0.3]) as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"a 4-array drops alpha to 1 (what JSON round-trips, alpha ignored)")
	check((col.sanitize(Color(0.1, 0.2, 0.3, 0.5)) as Color).is_equal_approx(Color(0.1, 0.2, 0.3, 1.0)),
		"a Color keeps its rgb with alpha forced to 1")

	var ctab := AttributeTable.new([col])
	ctab.set_default(&"lc", Color(0.3, 0.5, 0.7))
	var cdict := ctab.to_dict()
	check(cdict["defaults"]["lc"] is Array and (cdict["defaults"]["lc"] as Array).size() == 3,
		"to_dict writes a COLOR as a 3-element [r, g, b] array (Color is not JSON)")
	var round := AttributeTable.new([col])
	round.apply_dict(cdict)
	check((round.get_default(&"lc") as Color).is_equal_approx(Color(0.3, 0.5, 0.7, 1.0)),
		"apply_dict restores the COLOR through set_default/sanitize")
