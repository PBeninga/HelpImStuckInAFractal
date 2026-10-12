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
	var binding := Binding.new()
	binding.source = &"time"
	binding.gain = 2.0
	second.set_binding(&"exposure", binding)
	console.set_resolved([{}, {}], {&"exposure": 3.4}, 0)
	check(console.light_inspector().row(&"exposure").readout().text.contains("1"), "inactive binding preview shows its own default")
	check(not console.light_inspector().row(&"exposure").readout().text.contains("3.4"), "inactive preview never borrows rendered shape's values")
	console.set_resolved([{}, {}], {&"exposure": 2.8}, 1)
	check(console.light_inspector().row(&"exposure").readout().text.contains("2.8"), "rendered shape shows live binding values")
	check(first != second, "each shape has an independent look table")
	check(console.light_inspector().table() == second, "lighting edits the same expanded shape as material")
	check(console.palette().table() == second, "palette sliders follow the expanded shape")
	console.material_inspector().row(&"roughness").spin_box().value = 0.72
	console.light_inspector().row(&"light_yaw").spin_box().value = -42.0
	console.palette_window().slider(0, 0).value = 0.19
	check_approx(first.get_default(&"roughness"), 0.23, "editing shape 2 preserves shape 1 material")
	check_approx(first.get_default(&"light_yaw"), 31.0, "editing shape 2 preserves shape 1 lighting")
	check_approx(second.get_default(&"palette_a_r"), 0.19, "palette writes shape 2")
	second.set_binding(&"palette_a_r", binding)
	console.set_resolved([{}, {}], {&"palette_a_r": 0.83}, 1)
	check_approx(console.palette().color_at(0.25).r, 0.83, "rendered palette previews its resolved binding")
	console.set_resolved([{}, {}], {&"palette_a_r": 0.64}, 0)
	check_approx(console.palette().color_at(0.25).r, 0.19, "inactive palette previews its own default")
	pane.set_expanded(1, false)
	check(not console.material_inspector().visible and not console.light_inspector().visible,
		"closing every shape hides both editors")
	check_eq(console.material_inspector().row_count(), 0, "collapsed editors have no editable rows")
	pane.set_expanded(0, true)
	check(console.material_inspector().table() == first, "reopening shape 1 restores its target")
	check_approx(console.material_inspector().row(&"roughness").spin_box().value, 0.23, "reopening restores its material values")
	var saved := shapes.to_dict()
	check(saved[0].has("look") and saved[1].has("look"), "shape records save their own look")
	var restored := ShapeList.new()
	check_eq(restored.apply_dict(saved), [], "per-shape look round trip has no warnings")
	check_approx(restored.look_table(0).get_default(&"roughness"), 0.23, "shape 1 material survives saving")
	check_approx(restored.look_table(1).get_default(&"light_yaw"), -42.0, "shape 2 lighting survives saving")
	check_eq(restored.look_table(1).binding(&"exposure").source, &"time", "shape 2 look binding survives saving")
	check_approx(restored.look_table(1).binding(&"exposure").gain, 2.0, "shape 2 binding gain survives saving")
	check(not restored.look_table(0).binding(&"exposure").is_active(), "shape 2 binding does not leak into shape 1")
	pane.set_expanded(1, true)
	for tab_index in [1, 2]:
		check(console.tabs().get_tab_control(tab_index).get_node("EditingShape").text.contains("2"), "look tab identifies list position 2")
	pane.remove_shape(0)
	check(pane.is_expanded(0), "removing an earlier shape keeps the same shape expanded")
	check(console.material_inspector().table() == second, "removing an earlier shape keeps the editing target")
	for tab_index in [1, 2]:
		check(console.tabs().get_tab_control(tab_index).get_node("EditingShape").text.contains("1"), "look tab renumbers the remaining shape")
	console.queue_free()
	await frames(1)
	_test_migration()
	await _test_rendered_look()


func _test_migration() -> void:
	var shapes := ShapeList.new()
	var warnings := Workspace.restore({"version": 4, "shapes": [{}, {}],
		"look": {"defaults": {"roughness": 0.37, "light_yaw": 24.0},
			"bindings": {"light_yaw": {"source": "time", "gain": 0.5}}}},
		shapes, AttributeTable.new(ShapeCatalogue.scene_specs()), Keymap.new(), FractalParams.new(), CameraState.make_default())
	check_eq(warnings, [], "shared-look save migrates without warnings")
	for i in 2:
		check_approx(shapes.look_table(i).get_default(&"roughness"), 0.37, "legacy material copied to shape %d" % i)
		check_approx(shapes.look_table(i).get_default(&"light_yaw"), 24.0, "legacy lighting copied to shape %d" % i)
		check_eq(shapes.look_table(i).binding(&"light_yaw").source, &"time", "legacy lighting binding copied")
	shapes.look_table(1).set_default(&"roughness", 0.81)
	check_approx(shapes.look_table(0).get_default(&"roughness"), 0.37, "migrated looks are independent")


func _test_rendered_look() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	main.set_process(false)
	main.shapes().add()
	main.shapes().set_stage(0, 2.0, [])
	main.shapes().set_stage(1, 4.0, [])
	main.shapes().look_table(0).set_default(&"roughness", 0.21)
	main.shapes().look_table(0).set_default(&"light_yaw", 17.0)
	main.shapes().look_table(1).set_default(&"roughness", 0.69)
	main.shapes().look_table(1).set_default(&"light_yaw", -53.0)
	var yaw_binding := Binding.new()
	yaw_binding.source = &"a"
	yaw_binding.gain = 4.0
	main.shapes().look_table(1).set_binding(&"light_yaw", yaw_binding)
	main.keymap().axes().set_value(&"a", 2.0)
	main.params.active = 1
	main._resolve_once()
	var mat: ShaderMaterial = main.view._material
	check_approx(mat.get_shader_parameter("roughness"), 0.21, "rendering uses gameplay shape material regardless of editor selection")
	check_approx(mat.get_shader_parameter("light_yaw"), 17.0, "rendering uses gameplay shape lighting")
	check(main.look_table() == main.shapes().look_table(1), "programmatic look edits target the selected shape")
	main.camera.set_eye(2.1, 0.0, 0.0)
	main.shape_run.step(1.0)
	check_eq(main.params.gameplay_active, 1, "the test advances to shape 2")
	check_approx(mat.get_shader_parameter("roughness"), 0.69, "stage transition switches material")
	check_approx(mat.get_shader_parameter("light_yaw"), -45.0, "stage transition resolves the new shape's lighting binding")
	main.return_to_spawn()
	check_approx(mat.get_shader_parameter("roughness"), 0.21, "restarting restores the first material")
	main.console().shape_pane().select(1)
	var snapshot := Workspace.capture(main.shapes(), main.look_table(), main.keymap(), main.params, main.camera)
	main.console().shape_pane().select(0)
	var path := "user://per_shape_look_test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	main.load_level_from(path)
	check_eq(main.console().shape_pane().expanded_index(), 1, "loading restores the saved editing shape")
	check(main.console().material_inspector().table() == main.shapes().look_table(1), "loaded editor targets the restored look table")
	main.console().shape_pane().set_expanded(1, false)
	main.console().shape_pane().remove_shape(1)
	main.look_table().set_default(&"palette_a_r", 0.12)
	current_scene = main
	var actions: RefCounted = load("res://call_center/mcp/console_tools.gd").new(root.get_node("McpBridge"))
	var result: Dictionary = await actions.act({"action": "reset_palette"})
	check(result.get("ok", false), "palette reset succeeds with all shape panels closed")
	check_approx(main.look_table().get_default(&"palette_a_r"), 0.5, "palette reset targets a current shape after closed-shape removal")
	main.add_shape()
	main.console().open()
	var editing: AttributeTable = main.look_table()
	main.shapes().remove(0)
	check(main.console().material_inspector().table() == editing, "removing an earlier shape while console is open keeps the editor target")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.queue_free()
	await frames(1)
