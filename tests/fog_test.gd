extends "res://tests/test_case.gd"
## The persistent fog wall is editable on Light, travels with the level and
## remains in the shader at full quality and during a load-shed restore.


func run() -> void:
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	for id in [&"fog_distance", &"fog_start", &"fog_tint"]:
		check(look.has(id), "the scene has '%s'" % id)
	if not look.has(&"fog_distance"):
		return
	check_eq(look.get_default(&"fog_distance"), 0.0, "fog is off in a fresh scene")
	check_approx(look.spec(&"fog_distance").sanitize(-10.0), 0.0, "negative distance disables fog")
	check(float(look.spec(&"fog_start").sanitize(1.0)) < 1.0,
		"fade start cannot collapse the fade interval")

	var shapes := ShapeList.new()
	var km := Keymap.new()
	var clock := Clock.new()
	root.add_child(clock)
	var console := ConsoleWindow.new()
	console.setup(shapes, look, km, clock, ShapeCatalogue.group_tooltips(), func() -> float: return 1.0)
	root.add_child(console)
	await frames(1)
	var light := console.light_inspector()
	for id in [&"fog_distance", &"fog_start", &"fog_tint"]:
		check(light.row(id) != null, "'%s' is editable on Light" % id)
	light.row(&"fog_distance").spin_box().value = 60.0
	light.row(&"fog_start").spin_box().value = 0.5
	var picker := light.row(&"fog_tint").value_control() as ColorPickerButton
	picker.color = Color(0.15, 0.25, 0.35)
	picker.color_changed.emit(picker.color)
	check_approx(look.get_default(&"fog_distance"), 60.0, "editing distance writes the look table")
	check_approx(look.get_default(&"fog_start"), 0.5, "editing fade start writes the look table")

	var params := FractalParams.new()
	var camera := CameraState.make_default()
	params.apply_resolved(look.defaults())
	var snapshot := Workspace.capture(shapes, look, km, params, camera)
	var restored := AttributeTable.new(ShapeCatalogue.scene_specs())
	var warnings := Workspace.restore(snapshot, ShapeList.new(), restored, Keymap.new(), FractalParams.new(), CameraState.make_default())
	check_eq(warnings, [], "a level containing fog restores with no warnings")
	for id in [&"fog_distance", &"fog_start", &"fog_tint"]:
		check_eq(restored.get_default(id), look.get_default(id), "'%s' survives saving" % id)

	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	view.setup(params, camera)
	await frames(1)
	var mat := view._material
	check_approx(mat.get_shader_parameter("fog_distance"), 60.0, "distance reaches the shader")
	check_approx(mat.get_shader_parameter("fog_start"), 0.5, "fade start reaches the shader")
	check(Vector3(mat.get_shader_parameter("fog_tint")).is_equal_approx(Vector3(0.15, 0.25, 0.35)),
		"fog colour reaches the shader as RGB")
	view.set_load_level(3)
	view.set_load_level(0)
	check(view.restoring(), "the performance fog is clearing")
	check_approx(mat.get_shader_parameter("fog_distance"), 60.0, "the manual wall persists during clearing")
	await frames(FractalView.RESTORE_FRAMES)
	check_eq(float(mat.get_shader_parameter("fog_dist")), 0.0, "the performance fog is gone")
	check_approx(mat.get_shader_parameter("fog_distance"), 60.0, "the manual wall persists at full quality")
	params.apply_resolved({&"fog_distance": 0.0})
	check_eq(float(mat.get_shader_parameter("fog_distance")), 0.0, "setting zero disables the manual wall")
	view.queue_free()
	console.queue_free()
	clock.queue_free()
	await frames(1)
