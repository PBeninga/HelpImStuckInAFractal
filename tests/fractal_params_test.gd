extends "res://tests/test_case.gd"


func run() -> void:
	var p := FractalParams.new()

	# defaults (the site's defaults, now by catalogue id)
	check_approx(p.box_scale, -2.09, "box_scale default")
	check_approx(p.min_radius, 0.7, "min_radius default")
	check_approx(p.fold_limit, 1.0, "fold_limit default")
	check_approx(p.fixed_radius, 1.0, "fixed_radius default")
	check_eq(p.fold_order, 0, "fold_order default is Box -> Sphere")
	check_approx(p.w, 0.0, "w default is 0 (today's 3D box)")
	check_eq(p.julia_all, false, "julia_all off by default")
	check_eq(p.julia_0, false, "julia_0 off")
	check_approx(p.c_0, -0.23, "c_0 default")
	check_approx(p.c_1, 1.512, "c_1 default")
	check_approx(p.c_2, 1.892, "c_2 default")
	check_approx(p.c_3, 0.0, "c_3 default")
	check_approx(p.iter_rot_xy, 0.0, "iter_rot_xy default")
	check_approx(p.iter_rot_zw, 0.0, "iter_rot_zw default")
	check_eq(p.color_mode, 1, "color_mode default is Ice Fractal")
	check_approx(p.precision, 0.000025, "precision default", 1e-9)
	check_eq(p.fast_controls, true, "fast_controls on by default")
	check_eq(p.camera_mode, FractalParams.CameraMode.FLY, "camera starts in fly mode")
	check_approx(p.mouse_sensitivity, 0.1, "mouse_sensitivity default")
	check_approx(p.detail, 1.0, "detail default")
	check_approx(p.detail_range, 10.0, "detail_range default")
	check_approx(p.detail_falloff, 0.0, "detail falloff is off by default")
	check_approx(p.min_render_scale, 0.25, "min_render_scale default")
	check_eq(p.max_steps, 128, "max_steps default")
	check_eq([p.coarse_steps(), p.fine_steps()], [96, 32], "the default budget is the original 96 + 32")

	# the helpers
	check(p.julia_point().is_equal_approx(Vector3(-0.23, 1.512, 1.892)), "julia_point() is (c_0, c_1, c_2)")
	check_eq(p.julia_enabled(), false, "julia_enabled() follows julia_all")
	p.julia_all = true
	check_eq(p.julia_enabled(), true, "julia_enabled() true when julia_all is on")
	p.julia_all = false

	# the site's thirteen colour ids in dropdown order, then Palette
	check_eq(p.COLOR_MODE_IDS, [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14, 20], "colour id order")
	check_eq(p.COLOR_MODE_NAMES.size(), 14, "fourteen colour names")
	check_eq(p.COLOR_MODE_NAMES[-1], "Palette", "the last is Palette")
	check_eq(p.COLOR_MODE_IDS[-1], Palette.MODE_ID, "with the Palette's mode id")

	# every resolved key is a catalogue id, and its field opens on the catalogue default
	var shape_table := AttributeTable.new(MandelboxShape.specs())
	check_eq(FractalParams.RESOLVED_KEYS, MandelboxShape.catalogue_ids(), "RESOLVED_KEYS are the catalogue ids, in order")
	for k in FractalParams.RESOLVED_KEYS:
		var want: Variant = shape_table.get_default(k)
		if want is float:
			check_approx(float(p.get(k)), want, "field '%s' opens on the catalogue default" % k, 1e-9)
		else:
			check_eq(p.get(k), want, "field '%s' opens on the catalogue default" % k)
	for k in FractalParams.LOOK_KEYS:
		check(FractalParams.RESOLVED_KEYS.has(k), "look key '%s' is resolved" % k)
	check(not FractalParams.LOOK_KEYS.has(&"color_mode"), "color_mode is pushed on its own, not as a look key")
	check_eq(FractalParams.LOOK_KEYS.size() + FractalParams.RESOLVED_KEYS.find(&"color_mode") + 1,
		FractalParams.RESOLVED_KEYS.size(), "the look keys are everything after color_mode")

	# --- apply_resolved emits once, only on a difference ---
	var fires := [0]
	var cb := func(): fires[0] += 1
	p.changed.connect(cb)

	p.apply_resolved({&"box_scale": -1.5, &"fold_limit": 2.0, &"color_mode": 2})
	check_eq(fires[0], 1, "apply_resolved emits once for a batch of changes")
	check_approx(p.box_scale, -1.5, "and wrote box_scale")
	check_approx(p.fold_limit, 2.0, "and fold_limit")
	check_eq(p.color_mode, 2, "and color_mode")

	fires[0] = 0
	p.apply_resolved({&"box_scale": -1.5, &"fold_limit": 2.0, &"color_mode": 2})
	check_eq(fires[0], 0, "re-applying the same values emits nothing")

	fires[0] = 0
	p.apply_resolved({&"w": 0.5})
	check_eq(fires[0], 1, "a partial dict that changes one field emits once")
	check_approx(p.w, 0.5, "and wrote only w")
	check_approx(p.fold_limit, 2.0, "leaving the rest alone")

	p.changed.disconnect(cb)

	# every preference setter still emits `changed`
	for setter in [
		func(): p.fast_controls = false,
		func(): p.camera_mode = FractalParams.CameraMode.ORBIT,
		func(): p.mouse_sensitivity = 0.2,
		func(): p.detail = 2.0,
		func(): p.detail_range = 50.0,
		func(): p.detail_falloff = 1.0,
		func(): p.min_render_scale = 0.5,
		func(): p.max_steps = 256,
	]:
		var fired := [false]
		var one := func(): fired[0] = true
		p.changed.connect(one)
		setter.call()
		p.changed.disconnect(one)
		check(fired[0], "a preference setter emitted changed")

	# the renderer options clamp to their ranges
	var q := FractalParams.new()
	q.detail = 100.0
	check_approx(q.detail, FractalParams.DETAIL_MAX, "detail clamps high")
	q.detail_falloff = -1.0
	check_approx(q.detail_falloff, 0.0, "falloff clamps at 0")
	q.min_render_scale = 0.0
	check_approx(q.min_render_scale, FractalParams.RENDER_SCALE_FLOOR, "min render scale clamps low")
	q.max_steps = 100000
	check_eq(q.max_steps, FractalParams.MAX_STEPS_MAX, "max steps clamps high")
	q.max_steps = 200
	check_eq(q.coarse_steps() + q.fine_steps(), 200, "the budget splits without losing a step")

	# hit_epsilon: the plain cone by default, coarsened past the range
	var e := FractalParams.new()
	check_approx(e.hit_epsilon(4.0, 0.5), 0.000025 * 4.0, "defaults give precision * t", 1e-12)
	e.detail = 2.0
	check_approx(e.hit_epsilon(4.0, 0.5), 0.000025 * 2.0, "detail 2 halves it", 1e-12)
	e.detail = 1.0
	e.detail_falloff = 2.0
	e.detail_range = 4.0          # start = 4 * 0.5 = 2
	check_approx(e.hit_epsilon(1.5, 0.5), 0.000025 * 1.5, "inside the range: unchanged", 1e-12)
	check_approx(e.hit_epsilon(6.0, 0.5), 0.000025 * 6.0 * 9.0, "past it: x (t / start)^falloff", 1e-12)
	check(e.hit_epsilon(6.0, 0.0) > 0.0 and is_finite(e.hit_epsilon(6.0, 0.0)),
		"a camera on the surface stays finite")

	# the step split works on a shed budget too
	var b := FractalParams.new()
	check_eq([b.coarse_steps(64), b.fine_steps(64)], [48, 16], "a 64-step budget splits 48 + 16")

	# every colour mode has a fog tint; the white-background modes get a light one
	for id in FractalParams.COLOR_MODE_IDS:
		b.color_mode = id
		var c := b.fog_color()
		var lum := (c.x + c.y + c.z) / 3.0
		if id == 5 or id == 6:
			check(lum > 0.6, "mode %d (white background) has a light fog (%s)" % [id, c])
		else:
			check(lum < 0.4, "mode %d has a dark fog (%s)" % [id, c])
