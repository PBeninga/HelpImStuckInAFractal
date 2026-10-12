extends "res://tests/test_case.gd"

func run() -> void:
	var p := FractalParams.new()
	check(p.get("perturbation_enabled") != null, "View exposes a perturbation toggle")
	if p.get("perturbation_enabled") == null:
		return
	check(not p.perturbation_enabled, "perturbation defaults to off")
	p.perturbation_enabled = true
	p.set("fractal_iterations", 8)
	p.set("perturbation_iterations", 3)
	check(p.coarse_iters(1e-12) == 8, "coarse work respects the iteration budget")
	var o := ReferenceOrbit.build(p, 0.1, 0.2, 0.3)
	check(o.n <= 8, "CPU reference orbit respects the iteration budget")
	check(p.pert_iters(o, 0.0) == 3, "perturbation work respects its budget")
	p.set("perturbation_enabled", false)
	check(p.pert_iters(o, 0.0) == 0, "disabled perturbation never runs")
	check(p.zoom_floor_for(o) == p.floor32(o.world_eye), "disabled perturbation uses the direct precision floor")
	var ui := RendererOptions.new()
	root.add_child(ui)
	ui.setup(p)
	ui.perturbation_check.button_pressed = true
	check(p.perturbation_enabled, "View checkbox enables perturbation")
	await frames(1)
	ui.iterations_slider.value = 12
	await frames(1)
	ui.perturbation_slider.value = 5
	await frames(1)
	check(p.fractal_iterations == 12 and p.perturbation_iterations == 5, "View dials change work budgets (%d, %d; sliders %s, %s)" % [p.fractal_iterations, p.perturbation_iterations, ui.iterations_slider.value, ui.perturbation_slider.value])
	var shapes := ShapeList.new()
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var keys := Keymap.new()
	var camera := CameraState.make_default()
	var saved := Workspace.capture(shapes, look, keys, p, camera)
	var restored := FractalParams.new()
	Workspace.restore(saved, shapes, look, keys, restored, camera)
	check(restored.fractal_iterations == 12 and restored.perturbation_iterations == 5 and restored.perturbation_enabled, "work budgets survive save/load")
	p.perturbation_enabled = false
	var direct := ReferenceOrbit.build(p, 0.1, 0.2, 0.3)
	check(direct.points.is_empty() and direct.rec64.is_empty(), "disabled mode skips reference-orbit construction")
	for kind in 4:
		p.active_shape().shape = kind
		p.perturbation_enabled = true
		var budget_orbit := ReferenceOrbit.build(p, 0.1, 0.2, 0.3)
		check_approx(budget_orbit.distance, DistanceEstimator.scene_estimate_at(0.1, 0.2, 0.3, p), "CPU orbit agrees with budgeted scene estimate for shape %d" % kind)
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	p.fractal_iterations = 12
	p.perturbation_enabled = false
	view.setup(p, camera)
	check_eq(int(view._material.get_shader_parameter("fractal_iterations")), 12, "GPU receives the fractal work budget")
	check_eq(view.pert_iters(), 0, "GPU uses the direct march when disabled")
	view.free()
	ui.reset_defaults()
	check(p.get("perturbation_enabled") == false and p.get("fractal_iterations") == 32 and p.get("perturbation_iterations") == 20, "reset leaves perturbation off")
	ui.free()
