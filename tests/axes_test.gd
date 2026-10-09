extends "res://tests/test_case.gd"
## Axes, Keymap (JSON round trip + InputMap actions) and AxisController.

const TMP := "user://axes_test_keymap.json"


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

	# --- JSON round trip by key name ---
	km.axes().set_value(&"a", 4.0)   # values are not saved; only id/label/speed/keys
	check_eq(km.save_file(TMP), OK, "the keymap saves")
	var km2 := Keymap.new()
	var result := km2.load_file(TMP)
	check(result["ok"], "it loads")
	check(km2.axes().has(&"a"), "the axis is back")
	check_eq(km2.axes().label(&"a"), "Axis A", "label round-trips")
	check_approx(km2.axes().speed(&"a"), 1.0, "speed round-trips")
	check_eq(km2.positive_key(&"a"), KEY_E, "the positive key round-trips by name")
	check_eq(km2.negative_key(&"a"), KEY_Q, "the negative key round-trips by name")

	# --- a missing file yields the shipped default (one axis on Q/E) ---
	var km3 := Keymap.new()
	var miss := km3.load_file("user://no_such_keymap.json")
	check(not miss["ok"], "a missing file fails")
	check(miss["warnings"].size() >= 1, "and warns")
	check(km3.axes().has(&"a"), "the default has Axis A")
	check_eq(km3.positive_key(&"a"), KEY_E, "on E")
	check_eq(km3.negative_key(&"a"), KEY_Q, "and Q")

	# --- a saved view is refused by name, and the keymap in hand is kept ---
	# (Views and keymaps share saves/, and the View tab's panel can be handed
	# either; a view must not wipe the keys back to the default.)
	var view_file := "user://axes_test_view.json"
	var vf := FileAccess.open(view_file, FileAccess.WRITE)
	vf.store_string(JSON.stringify({"version": 2, "shape": {"defaults": {}, "bindings": {}}, "axes": {}, "fractal": {}, "camera": {}}))
	vf.close()
	var km4 := Keymap.new()
	km4.add_axis(&"b", "Axis B", 2.0, KEY_T, KEY_G)
	var wrong := km4.load_file(view_file)
	check(not wrong["ok"], "a view file does not load as a keymap")
	check(wrong["warnings"].size() == 1 and String(wrong["warnings"][0]).contains("view") and String(wrong["warnings"][0]).contains("View tab"),
		"and the message says it is a view and where to load it: %s" % [wrong["warnings"]])
	check(km4.axes().has(&"b") and not km4.axes().has(&"a"), "the keymap in hand is left alone")
	check_eq(km4.positive_key(&"b"), KEY_T, "keys and all")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(view_file))

	# --- AxisController moves an axis under a held action, not while typing ---
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
