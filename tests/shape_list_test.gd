extends "res://tests/test_case.gd"
## ShapeList: one default shape to start; add (with defaults, up to MAX_SHAPES)
## and remove (never the last); labels; the structure and entry signals;
## per-shape resolution; to_dict / apply_dict round trip with warnings for
## what it cannot read.


func run() -> void:
	var shapes := ShapeList.new()
	check_eq(shapes.count(), 1, "a new list holds one shape")
	check_eq(shapes.label(0), "Shape 1", "named Shape 1")
	check_eq(shapes.table(0).specs.size(), ShapeCatalogue.shape_specs().size(), "over the per-shape catalogue (Placement included)")
	check_approx(float(shapes.table(0).get_default(&"size")), 1.0, "at size 1")
	check(not shapes.table(0).has(&"light_yaw"), "the look knobs are not per shape")

	var structure := [0]
	var relabels := []
	var edits := []
	shapes.changed.connect(func(): structure[0] += 1)
	shapes.relabelled.connect(func(i: int): relabels.append(i))
	shapes.entry_changed.connect(func(i: int, id: StringName): edits.append([i, id]))

	# add with defaults
	var i := shapes.add({&"pos_x": 2.5, &"size": 0.1, &"bogus": 1.0}, "")
	check_eq(i, 1, "add returns the new index")
	check_eq(shapes.count(), 2, "and the list grew")
	check_eq(structure[0], 1, "add emits changed")
	check_eq(shapes.label(1), "Shape 2", "the next number names it")
	check_approx(float(shapes.table(1).get_default(&"pos_x")), 2.5, "the defaults were applied")
	check_approx(float(shapes.table(1).get_default(&"size")), 0.1, "size too", 1e-12)
	check(not shapes.table(1).has(&"bogus"), "an unknown default is ignored")
	check_approx(float(shapes.table(0).get_default(&"pos_x")), 0.0, "the first shape is untouched")

	# an edit on a table is relayed with its index
	shapes.table(1).set_default(&"box_scale", 2.0)
	check_eq(edits, [[1, &"box_scale"]], "entry_changed names the entry and the id")

	# labels
	shapes.set_label(1, "  Inner ")
	check_eq(shapes.label(1), "Inner", "set_label trims and stores")
	check_eq(relabels, [1], "and emits relabelled with the index")
	check_eq(structure[0], 1, "not changed (the structure is the same)")
	shapes.set_label(1, "")
	check_eq(shapes.label(1), "Inner", "an empty label is ignored")
	shapes.set_label(1, "Inner")
	check_eq(relabels, [1], "the same label emits nothing")

	# resolve: one dictionary per shape, bindings applied per table
	var b := Binding.new(); b.source = &"a"; b.gain = 1.0
	shapes.table(1).set_binding(&"pos_x", b)
	check(shapes.has_active_binding(), "a bound placement knob counts as an active binding")
	var all := shapes.resolve({&"a": 0.5}, 0.0)
	check_eq(all.size(), 2, "resolve gives one dict per shape")
	check_approx(float(all[1][&"pos_x"]), 3.0, "with the binding applied (2.5 + 0.5)")
	check_approx(float(all[0][&"pos_x"]), 0.0, "and the other shape's own values")

	# to_dict / apply_dict
	var saved := shapes.to_dict()
	check_eq(saved.size(), 2, "to_dict has one entry per shape")
	check_eq(saved[1]["label"], "Inner", "with the label")
	check(saved[1]["bindings"].has("pos_x"), "and the active binding")
	var other := ShapeList.new()
	var warnings := other.apply_dict(saved)
	check_eq(warnings, [], "apply_dict reads it back with no warnings")
	check_eq(other.count(), 2, "both shapes")
	check_eq(other.label(1), "Inner", "labels")
	check_approx(float(other.table(1).get_default(&"box_scale")), 2.0, "values")
	check(other.table(1).binding(&"pos_x").source == &"a", "bindings")
	var relayed := []
	other.entry_changed.connect(func(i2: int, id: StringName): relayed.append(i2))
	other.table(1).set_default(&"w", 0.3)
	check_eq(relayed, [1], "a loaded table's edits are relayed")
	var w2 := other.apply_dict([{"defaults": {"ghost": 1}, "bindings": {}}, "nope"])
	check_eq(other.count(), 1, "a malformed entry is skipped")
	check_eq(w2.size(), 2, "with a warning each: %s" % [w2])
	check_eq(other.label(0), "Shape 1", "a missing label gets a number")
	var w3 := other.apply_dict({})
	check_eq(w3.size(), 1, "a non-list warns")
	check_eq(other.count(), 1, "and leaves the list alone")
	var w4 := other.apply_dict([])
	check_eq(other.count(), 1, "an empty list keeps one default shape")
	check_eq(w4.size(), 1, "with a warning")

	# remove: never the last; the removed table stops relaying
	var gone := shapes.table(1)
	check(shapes.remove(1), "remove drops a shape")
	check_eq(shapes.count(), 1, "back to one")
	edits.clear()
	gone.set_default(&"w", 1.0)
	check_eq(edits, [], "the removed table no longer relays")
	check(not shapes.remove(0), "the last shape cannot be removed")
	check(not shapes.remove(3), "nor an index out of range")

	# the cap
	for n in FractalParams.MAX_SHAPES:
		shapes.add()
	check_eq(shapes.count(), FractalParams.MAX_SHAPES, "add stops at MAX_SHAPES")
	check_eq(shapes.add(), -1, "and returns -1 past it")
