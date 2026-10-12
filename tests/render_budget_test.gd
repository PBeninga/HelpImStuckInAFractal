extends "res://tests/test_case.gd"

func run() -> void:
	var p := FractalParams.new()
	p.fractal_iterations = 8
	check(p.coarse_iters(1e-12) == 8, "coarse work respects the iteration budget")
	var ui := RendererOptions.new()
	root.add_child(ui)
	ui.setup(p)
	await frames(1)
	ui.iterations_slider.value = 12
	await frames(1)
	check_eq(p.fractal_iterations, 12, "View dial changes the fractal work budget")
	var shapes := ShapeList.new()
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var keys := Keymap.new()
	var camera := CameraState.make_default()
	var saved := Workspace.capture(shapes, look, keys, p, camera)
	check(not saved["fractal"].has("perturbation_enabled") and not saved["fractal"].has("perturbation_iterations"),
		"new saves omit the removed perturbation settings")
	# A legacy save must not reactivate deep zoom or carry the retired work budget forward.
	saved["fractal"]["perturbation_enabled"] = true
	saved["fractal"]["perturbation_iterations"] = 20
	var restored := FractalParams.new()
	var result := Workspace.restore(saved, shapes, look, keys, restored, camera)
	check(result.is_empty(), "legacy perturbation settings do not prevent loading")
	check_eq(restored.fractal_iterations, 12, "fractal work budget survives save/load")
	var eye := [1.96, 0.914, 0.787]
	check_approx(restored.zoom_floor(eye), 9.5367431640625e-5,
		"legacy save keeps the direct 32-bit zoom floor", 1e-12)
	var recaptured := Workspace.capture(shapes, look, keys, restored, camera)
	check(not recaptured["fractal"].has("perturbation_enabled") and not recaptured["fractal"].has("perturbation_iterations"),
		"loading an old save does not persist removed settings")
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	view.setup(restored, camera)
	check_eq(int(view._material.get_shader_parameter("fractal_iterations")), 12, "GPU receives the fractal work budget")
	var perturbation_uniforms := view.shader_uniform_names().filter(func(u): return String(u).begins_with("pert_"))
	check(perturbation_uniforms.is_empty(), "shader has no perturbation uniforms")
	view.free()
	ui.reset_defaults()
	check_eq(p.fractal_iterations, 32, "reset restores the full fractal work budget")
	ui.free()
