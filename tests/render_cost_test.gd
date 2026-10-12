extends "res://tests/test_case.gd"

# Regressions: stale colors after edits/bindings; reversed precision cost;
# tiny nonzero angles incorrectly priced by magnitude; inactive shadows red.
func run() -> void:
	var table := AttributeTable.new(ShapeCatalogue.shape_specs())
	var inspector := AttributeInspector.new()
	inspector.setup(table, ShapeCatalogue.group_tooltips())
	root.add_child(inspector)
	await frames(1)
	var rotation := inspector.row(&"iter_rot_xy").value_control()
	var cheap := rotation.modulate
	table.set_default(&"iter_rot_xy", 0.1)
	check(rotation.modulate != cheap, "enabling iteration rotation updates cost immediately")
	var active := rotation.modulate
	table.set_default(&"iter_rot_xy", 90.0)
	check_eq(rotation.modulate, active, "rotation work is independent of angle magnitude")
	table.set_default(&"iter_rot_xy", 0.0)
	check_eq(rotation.modulate, cheap, "disabling rotation restores cheap color")
	var values := table.defaults()
	values[&"iter_rot_xy"] = 12.0
	inspector.set_resolved(values)
	check(rotation.modulate != cheap, "resolved animated values update cost")
	inspector.set_sources([])
	inspector.set_resolved(values)
	check(rotation.modulate != cheap, "refreshing binding sources preserves unchanged live cost")
	values[&"iter_rot_xy"] = 0.0
	inspector.set_resolved(values)
	check_eq(rotation.modulate, cheap, "animated value returning to zero restores cheap color")
	table.set_default(&"iter_rot_xz", 20.0)
	check(rotation.modulate != cheap, "one active angle enables the entire six-plane rotation group")
	table.set_default(&"iter_rot_xz", 0.0)
	check_eq(rotation.modulate, cheap, "disabling the last angle skips the whole group")
	var precision := inspector.row(&"precision").value_control()
	table.set_default(&"precision", 1e-3)
	var coarse := precision.modulate
	table.set_default(&"precision", 1e-6)
	check(precision.modulate.r > coarse.r and precision.modulate.g < coarse.g,
		"smaller precision is redder, not greener")
	inspector.free()
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var light := AttributeInspector.new()
	light.setup(look, ShapeCatalogue.group_tooltips())
	root.add_child(light)
	var shadow := light.row(&"shadows").value_control()
	look.set_default(&"color_mode", 1)
	look.set_default(&"shadows", 1.0)
	var off := shadow.modulate
	look.set_default(&"light_yaw", 20.0)
	check(shadow.modulate != off, "shadow cost reacts to another setting enabling the ray")
	look.set_default(&"color_mode", 0)
	check_eq(shadow.modulate, off, "grayscale skips shadow work")
	look.set_default(&"scatter_density", 1.0)
	var glow := light.row(&"scatter_glow").value_control()
	var haze := glow.modulate
	look.set_default(&"scatter_glow", 0.8)
	check_eq(glow.modulate, haze, "glow amount does not change haze sample work")
	look.set_default(&"scatter_density", 0.0)
	check(glow.modulate != haze, "density disables haze work for every glow amount")
	light.free()
	var p := FractalParams.new()
	var options := RendererOptions.new()
	root.add_child(options)
	options.setup(p)
	await frames(1)
	var low := options.iterations_slider.modulate
	options.iterations_slider.value = 32
	check(options.iterations_slider.modulate != low, "iteration budget color updates on drag")
	options.reset_defaults()
	check_eq(options.iterations_slider.modulate, low, "reset restores cheap budget color")
	options.free()
