extends "res://tests/test_case.gd"
## Catch shared look state, multiple open editors, stale palette targets and
## save/load losing the look belonging to a shape.


func run() -> void:
	var shapes := ShapeList.new(2)
	var console := ConsoleWindow.new()
	console.setup(shapes, AttributeTable.new(ShapeCatalogue.scene_specs()), Keymap.new(), null, ShapeCatalogue.group_tooltips())
	root.add_child(console)
	await frames(1)
	var pane := console.shape_pane()
	var first := console.material_inspector().table()
	console.material_inspector().row(&"roughness").spin_box().value = 0.23
	console.light_inspector().row(&"light_yaw").spin_box().value = 31.0
	pane.set_expanded(1, true)
	check(not pane.is_expanded(0) and pane.is_expanded(1), "opening shape 2 closes shape 1")
	var second := console.material_inspector().table()
	check(first != second, "each shape has an independent look table")
	check(console.light_inspector().table() == second, "lighting edits the same expanded shape as material")
	check(console.palette().table() == second, "palette sliders follow the expanded shape")
	console.material_inspector().row(&"roughness").spin_box().value = 0.72
	console.light_inspector().row(&"light_yaw").spin_box().value = -42.0
	console.palette_window().slider(0, 0).value = 0.19
	check_approx(first.get_default(&"roughness"), 0.23, "editing shape 2 preserves shape 1 material")
	check_approx(first.get_default(&"light_yaw"), 31.0, "editing shape 2 preserves shape 1 lighting")
	check_approx(second.get_default(&"palette_a_r"), 0.19, "palette writes shape 2")
	pane.set_expanded(1, false)
	check(not console.material_inspector().visible and not console.light_inspector().visible,
		"closing every shape hides both editors")
	pane.set_expanded(0, true)
	check(console.material_inspector().table() == first, "reopening shape 1 restores its target")
	check_approx(console.material_inspector().row(&"roughness").spin_box().value, 0.23, "reopening restores its material values")
	var saved := shapes.to_dict()
	check(saved[0].has("look") and saved[1].has("look"), "shape records save their own look")
	console.queue_free()
	await frames(1)
