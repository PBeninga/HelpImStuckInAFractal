extends "res://tests/test_case.gd"
## Axes, Keymap (to_list / apply_list + InputMap actions) and AxisController.
## The keymap has no file of its own: the keys and axes travel inside the level
## save (see workspace_test), read and written through to_list / apply_list.


func run() -> void:
	# --- Axes: step, set_value, values ---
	var axes := Axes.new()
	axes.add(&"a", "Axis A", 1.0)
	axes.step(&"a", 1.0, 0.5)
	check_approx(axes.value(&"a"), 0.5, "step adds direction * speed * delta")
	axes.step(&"a", -1.0, 0.25)
	check_approx(axes.value(&"a"), 0.25, "a negative direction pushes back")
	axes.set_value(&"a", 3.0)
	check_approx(axes.value(&"a"), 3.0, "set_value sets it directly")
	axes.add(&"b", "Axis B", 2.0)
	check_eq(axes.values(), {&"a": 3.0, &"b": 0.0}, "values() is every axis by id")
	check_eq(axes.ids(), [&"a", &"b"], "ids() keeps order")

	# --- Keymap: add_axis registers InputMap actions equal to the pair ---
	var km := Keymap.new()
	km.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	check(InputMap.has_action(&"axis_a_pos"), "add_axis registers the pos action")
	check(InputMap.has_action(&"axis_a_neg"), "add_axis registers the neg action")
	var pos_events := InputMap.action_get_events(&"axis_a_pos")
	check_eq(pos_events.size(), 1, "the pos action has one event")
	check_eq((pos_events[0] as InputEventKey).physical_keycode, KEY_E, "and it is the positive key E")

	# --- bind repoints the events ---
	km.bind(&"a", KEY_W, KEY_S)
	check_eq((InputMap.action_get_events(&"axis_a_pos")[0] as InputEventKey).physical_keycode, KEY_W,
		"bind repoints the pos action to W")
	km.bind(&"a", KEY_E, KEY_Q)   # back to default for later steps

	# --- set_speed ---
	km.set_speed(&"a", 2.5)
	check_approx(km.axes().speed(&"a"), 2.5, "set_speed changes the push speed")
	km.set_speed(&"a", 1.0)

	# --- remove_axis erases the actions; a binding to it goes inert ---
	km.add_axis(&"z", "Axis Z", 1.0, KEY_Z, KEY_X)
	km.remove_axis(&"z")
	check(not InputMap.has_action(&"axis_z_pos"), "remove_axis erases the pos action")
	check(not km.axes().has(&"z"), "and drops the axis")
	var spec := AttributeSpec.make({"id": "k", "label": "k", "type": AttributeSpec.Type.FLOAT,
		"default": 5.0, "min": -100.0, "max": 100.0, "tooltip": "t", "effects": "e"})
	var table := AttributeTable.new([spec])
	var b := Binding.new(); b.source = &"z"; b.gain = 10.0
	table.set_binding(&"k", b)
	check_approx(BindingResolver.resolve(table, km.axes().values(), 0.0)[&"k"], 5.0,
		"a binding to a removed axis resolves to the default")

	# --- to_list / apply_list: the axes travel as a list of entries ---
	km.axes().set_value(&"a", 4.0)   # the value travels too, inside the level
	var entries := km.to_list()
	check_eq(entries.size(), 1, "to_list has one entry per axis")
	check_eq(entries[0]["id"], "a", "the id is written")
	check_eq(entries[0]["label"], "Axis A", "the label is written")
	check_approx(entries[0]["speed"], 1.0, "the speed is written")
	check_eq(entries[0]["positive"], "E", "the positive key is written by name")
	check_eq(entries[0]["negative"], "Q", "the negative key by name")
	check_approx(entries[0]["value"], 4.0, "and the current value")

	var km2 := Keymap.new()
	km2.reset_to_default()               # a different starting keymap
	var warns := km2.apply_list(entries)
	check_eq(warns, [], "apply_list restores with no warnings")
	check(km2.axes().has(&"a"), "the axis is back")
	check_eq(km2.axes().label(&"a"), "Axis A", "label round-trips")
	check_approx(km2.axes().speed(&"a"), 1.0, "speed round-trips")
	check_approx(km2.axes().value(&"a"), 4.0, "value round-trips")
	check_eq(km2.positive_key(&"a"), KEY_E, "the positive key round-trips by name")
	check_eq(km2.negative_key(&"a"), KEY_Q, "the negative key round-trips by name")
	check(InputMap.action_get_events(&"axis_a_pos").size() == 1
		and (InputMap.action_get_events(&"axis_a_pos")[0] as InputEventKey).physical_keycode == KEY_E,
		"and the InputMap action follows the restored key")

	# --- apply_list replaces whatever was in hand, keys and all ---
	var km4 := Keymap.new()
	km4.add_axis(&"b", "Axis B", 2.0, KEY_T, KEY_G)
	km4.apply_list(entries)
	check(km4.axes().has(&"a") and not km4.axes().has(&"b"), "apply_list replaces the old axes")
	check(not InputMap.has_action(&"axis_b_pos"), "and erases the old axis's InputMap action")
	km4.remove_axis(&"a")

	# --- a malformed entry is skipped with a warning; the rest still apply ---
	var km5 := Keymap.new()
	var w5 := km5.apply_list([{"id": "", "label": "no id"}, 42, {"id": "c", "label": "C", "speed": 3.0, "positive": "W", "negative": "S", "value": 1.0}])
	check_eq(w5.size(), 2, "one warning each for the two bad entries: %s" % [w5])
	check(km5.axes().has(&"c") and not km5.axes().has(&""), "the good entry still applied")
	km5.remove_axis(&"c")

	# --- reset_to_default is the shipped keymap (one axis on E / Q) ---
	var km6 := Keymap.new()
	km6.add_axis(&"x", "X", 1.0, KEY_J, KEY_K)
	km6.reset_to_default()
	check(km6.axes().has(&"a") and not km6.axes().has(&"x"), "reset_to_default has Axis A only")
	check(km6.positive_key(&"a") == KEY_E and km6.negative_key(&"a") == KEY_Q, "on E / Q")
	km6.remove_axis(&"a")

	# --- AxisController moves an axis under a held action, not while typing ---
	# (InputMap actions are global; the apply_list/remove blocks above erased and
	# re-added axis_a_*, so re-register km2's before driving it.)
	km2.bind(&"a", KEY_E, KEY_Q)
	var controller := AxisController.new()
	var le := LineEdit.new()
	root.add_child(le)
	controller.setup(km2, [root])
	root.add_child(controller)
	await frames(1)
	km2.axes().set_value(&"a", 0.0)
	await hold(&"axis_a_pos", 0.3)
	check(km2.axes().value(&"a") > 0.0, "a held pos action pushes the axis")

	km2.axes().set_value(&"a", 0.0)
	le.grab_focus()
	await frames(1)
	await hold(&"axis_a_pos", 0.3)
	check_approx(km2.axes().value(&"a"), 0.0, "a focused text field silences the axis keys")

	controller.queue_free()
	le.queue_free()
	await frames(1)
	km.remove_axis(&"a")
	km2.remove_axis(&"a")
