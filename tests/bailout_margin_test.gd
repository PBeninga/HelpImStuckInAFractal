extends "res://tests/test_case.gd"
## Catch disconnected renderer controls, unsquared KIFS radius margins,
## CPU/GPU settings drift, and old saves inheriting the previous view's margin.

func run() -> void:
	var p := FractalParams.new()
	check(p.get("kifs_bailout_margin") != null, "KIFS bailout margin exists")
	check(p.get("mandelbulb_bailout_margin") != null, "Mandelbulb bailout margin exists")
	if p.get("kifs_bailout_margin") == null or p.get("mandelbulb_bailout_margin") == null:
		return
	var ui := RendererOptions.new()
	root.add_child(ui)
	ui.setup(p)
	await frames(1)
	var kifs_slider: HSlider = ui.get("kifs_bailout_slider")
	var bulb_slider: HSlider = ui.get("mandelbulb_bailout_slider")
	check(kifs_slider != null and bulb_slider != null, "renderer exposes both margins")
	if kifs_slider == null or bulb_slider == null:
		ui.free()
		return
	kifs_slider.value = 16.0
	bulb_slider.value = 4.0
	await frames(1)
	check_eq(p.get("kifs_bailout_margin"), 16.0, "KIFS dial changes the saved margin")
	check_eq(p.get("mandelbulb_bailout_margin"), 4.0, "bulb dial changes the saved margin")
	check(kifs_slider.focus_mode == Control.FOCUS_NONE and bulb_slider.focus_mode == Control.FOCUS_NONE,
		"bailout dials preserve flight keyboard controls")
	var shapes := ShapeList.new()
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var keys := Keymap.new()
	var camera := CameraState.make_default()
	var saved := Workspace.capture(shapes, look, keys, p, camera)
	var restored := FractalParams.new()
	check(Workspace.restore(saved, shapes, look, keys, restored, camera).is_empty(), "margins load cleanly")
	check_eq(restored.get("kifs_bailout_margin"), 16.0, "KIFS margin survives save/load")
	check_eq(restored.get("mandelbulb_bailout_margin"), 4.0, "bulb margin survives save/load")
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	view.setup(restored, camera)
	check_eq(view._material.get_shader_parameter("kifs_bailout_radius_squared"), 256000000.0,
		"GPU receives the squared KIFS radius, including the squared margin")
	check_eq(view._material.get_shader_parameter("mandelbulb_bailout_margin"), 4.0,
		"GPU receives the bulb margin")
	restored.set("mandelbulb_bailout_margin", 8.0)
	check_eq(view._material.get_shader_parameter("mandelbulb_bailout_margin"), 8.0,
		"an edited margin reaches the live renderer")
	view.free()

	# Diagonal KIFS along (3,3,3): each component after n steps is
	# 1 + 2*3^n. Radius 1000 escapes at n=6; radius 16000 at n=8.
	p.active_shape().shape = FractalParams.Shape.KIFS
	p.active_shape().kifs_fold = KifsEstimator.FoldSet.DIAGONAL
	check_approx(DistanceEstimator.scene_estimate_at(3, 3, 3, p), 3.464365607030388,
		"16x KIFS margin retains two additional iterations", 1e-10)
	p.set("kifs_bailout_margin", 1.0)
	check_approx(DistanceEstimator.scene_estimate_at(3, 3, 3, p), 3.4664775421714564,
		"1x KIFS margin preserves the original bailout", 1e-10)
	p.set("kifs_bailout_margin", 16.0)
	check_approx(DistanceEstimator.scene_estimate_at(3, 3, 3, p, 1), sqrt(3.0) * 7.0 / 3.0,
		"the iteration budget still wins over a larger margin", 1e-10)
	p.active_shape().shape = FractalParams.Shape.MANDELBULB
	p.active_shape().mandelbulb_power = 2.0
	# At (3,0,0), 1x stops immediately. At 4x, one step gives
	# z=(3,0,-9), r=sqrt(90), dr=7, which crosses the new radius 8.
	check_approx(DistanceEstimator.scene_estimate_at(3, 0, 0, p), 1.5246050995173255,
		"bulb margin reaches CPU scene estimates", 1e-10)
	p.set("mandelbulb_bailout_margin", 1.0)
	check_approx(DistanceEstimator.scene_estimate_at(3, 0, 0, p), 1.5 * log(3.0),
		"1x bulb margin preserves the original bailout", 1e-10)
	var original_bound := p.active_shape().bound_half()
	p.set("mandelbulb_bailout_margin", 16.0)
	check_eq(p.active_shape().bound_half(), original_bound, "a larger orbit margin does not enlarge geometry bounds")
	var bulb := p.active_shape()
	bulb.mandelbulb_julia = true
	bulb.mandelbulb_c_0 = 0.0
	bulb.mandelbulb_c_1 = 0.0
	bulb.mandelbulb_c_2 = 0.0
	# With c=0 the exact radial DE is 0.5*r*ln(r), independently of power.
	# These orbits exercise the expanded threshold's large final power step.
	for power in [1.5, 2.0, 8.0, 16.0, 32.0]:
		bulb.mandelbulb_power = power
		for radius in [1.11, 3.0, 16.0]:
			check_approx(DistanceEstimator.scene_estimate_at(radius, 0, 0, p), 0.5 * radius * log(radius),
				"16x Julia remains finite at power %s, radius %s" % [power, radius], 1e-9)

	for key in ["kifs_bailout_margin", "mandelbulb_bailout_margin"]:
		p.set(key, 0.0)
		check_eq(p.get(key), 1.0, "%s cannot reduce the original threshold" % key)
		p.set(key, 100.0)
		check_eq(p.get(key), 16.0, "%s clamps to the supported maximum" % key)
		p.set(key, NAN)
		check_eq(p.get(key), 1.0, "%s rejects non-finite settings" % key)
		p.set(key, 8.0)
	ui.reset_defaults()
	check_eq(p.get("kifs_bailout_margin"), 1.0, "reset restores the KIFS threshold")
	check_eq(p.get("mandelbulb_bailout_margin"), 1.0, "reset restores the bulb threshold")
	ui.free()
	saved["fractal"].erase("kifs_bailout_margin")
	saved["fractal"].erase("mandelbulb_bailout_margin")
	Workspace.restore(saved, shapes, look, keys, restored, camera)
	check_eq(restored.get("kifs_bailout_margin"), 1.0, "old levels reset the previous KIFS margin")
	check_eq(restored.get("mandelbulb_bailout_margin"), 1.0, "old levels reset the previous bulb margin")
