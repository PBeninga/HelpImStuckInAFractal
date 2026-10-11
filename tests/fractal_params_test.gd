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
	var shape_table := AttributeTable.new(ShapeCatalogue.specs())
	check_eq(FractalParams.RESOLVED_KEYS, ShapeCatalogue.catalogue_ids(), "RESOLVED_KEYS are the catalogue ids, in order")
	for k in FractalParams.RESOLVED_KEYS:
		var want: Variant = shape_table.get_default(k)
		if want is float:
			check_approx(float(p.get(k)), want, "field '%s' opens on the catalogue default" % k, 1e-9)
		else:
			check_eq(p.get(k), want, "field '%s' opens on the catalogue default" % k)
	for k in FractalParams.LOOK_KEYS:
		check(FractalParams.RESOLVED_KEYS.has(k), "look key '%s' is resolved" % k)
	check(not FractalParams.LOOK_KEYS.has(&"color_mode"), "color_mode is pushed on its own, not as a look key")
	check_eq(FractalParams.LOOK_KEYS.size() + FractalParams.COLOR_KEYS.size()
		+ FractalParams.RESOLVED_KEYS.find(&"color_mode") + 1,
		FractalParams.RESOLVED_KEYS.size(),
		"look keys + colour keys are everything after color_mode")
	for k in FractalParams.COLOR_KEYS:
		check(FractalParams.RESOLVED_KEYS.has(k), "colour key '%s' is resolved" % k)
		check(not FractalParams.LOOK_KEYS.has(k), "a colour key is not a scalar look key")
		check(p.get(k) is Color, "field '%s' is a Color" % k)
	check(not FractalParams.RESOLVED_KEYS.has(&"light_shininess"), "light_shininess is gone")
	check_eq(FractalParams.SHADOW_STEPS, 48, "the full shadow march is 48 steps")

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

	# coarse_iters: the march's coarse pass takes enough iterations that its
	# smoother surface sits within its own hit threshold of the real one
	var ci := FractalParams.new()
	check_eq(ci.coarse_iters(6.5655845), 16, "the default view (near ~6.57) keeps the site's 16")
	check_eq(ci.coarse_iters(1000.0), 16, "far away never drops below 16")
	check_eq(ci.coarse_iters(1e-3), 24, "1e-3 from the surface takes 24")
	check_eq(ci.coarse_iters(1e-6), 32, "1e-6 takes all 32")
	check_eq(ci.coarse_iters(0.0), 32, "a camera on the surface stays at 32")
	var ci_fine := FractalParams.new()
	ci_fine.detail = 10.0
	check(ci_fine.coarse_iters(1e-2) > ci.coarse_iters(1e-2),
		"Detail 10 raises the count at a given distance (%d over %d)" % [ci_fine.coarse_iters(1e-2), ci.coarse_iters(1e-2)])
	ci.box_scale = 1.0
	check_eq(ci.coarse_iters(6.5), 32, "|box_scale| = 1 has no shrinking detail: 32")
	ci.box_scale = -0.8
	check_eq(ci.coarse_iters(6.5), 32, "nor does a scale inside 1: 32")

	# nf_weight: the Ice Fractal shading crossfades to the true normal up close
	check_eq(FractalParams.nf_weight(6.5655845), 1.0, "the default view lights with the Ice Fractal probe alone (exactly 1)")
	check_eq(FractalParams.nf_weight(FractalParams.NF_FADE_FAR), 1.0, "the band's far end is 1")
	check_eq(FractalParams.nf_weight(FractalParams.NF_FADE_NEAR), 0.0, "its near end is 0")
	check_eq(FractalParams.nf_weight(1e-4), 0.0, "closer still is the true normal alone")
	var mid := FractalParams.nf_weight(1.05)
	check(mid > 0.0 and mid < 1.0, "inside the band it blends (%s)" % mid)
	check(FractalParams.nf_weight(0.5) < FractalParams.nf_weight(1.5), "rising with the distance")

	# ulp32: the gap between neighbouring 32-bit floats near x
	check_eq(FractalParams.ulp32(1.0), pow(2.0, -23.0), "ulp32(1) is 2^-23")
	check_eq(FractalParams.ulp32(1.96), pow(2.0, -23.0), "and the same through [1, 2)")
	check_eq(FractalParams.ulp32(2.0), pow(2.0, -22.0), "doubling at exactly 2")
	check_eq(FractalParams.ulp32(4.0), pow(2.0, -21.0), "and at exactly 4")
	check_eq(FractalParams.ulp32(8.18), pow(2.0, -20.0), "2^-20 at the default eye's x")
	check_eq(FractalParams.ulp32(0.3), pow(2.0, -25.0), "2^-25 at 0.3")
	check(FractalParams.ulp32(0.0) > 0.0 and is_finite(FractalParams.ulp32(0.0)), "zero stays finite and positive")

	# floor32: today's 32-bit floor (the guard for shapes that are not perturbed)
	var zf := FractalParams.new()
	var near_box := PackedFloat64Array([1.96, 0.914, 0.787])   # the default view's surface point
	check(absf(zf.floor32(near_box) - 1e-4) <= 0.2e-4,
		"near the box at the default precision the 32-bit floor is about 1e-4 (%s)" % zf.floor32(near_box))
	check_eq(zf.floor32(PackedFloat64Array([-1.96, -0.914, -0.787])), zf.floor32(near_box), "it uses the largest |coordinate|")
	var zf10 := FractalParams.new()
	zf10.detail = 10.0
	check_approx(zf10.floor32(near_box) / zf.floor32(near_box), 10.0,
		"it scales with Detail: a finer hit threshold needs more room above the float grid", 1e-9)
	check(zf.floor32(PackedFloat64Array([8.18, 3.81, 3.28])) > zf.floor32(near_box),
		"larger coordinates have a coarser grid, so a further floor")
	check(is_finite(zf.floor32(PackedFloat64Array([0.0, 0.0, 0.0]))), "the origin stays finite")
	check_eq(FractalParams.NEAR_FLOOR, 1e-14, "near is clamped only against a zero (1e-14), not at 1e-6")
	_perturbation()


## pert_iters and the zoom floor (ReferenceOrbit at a camera on the default
## view's line of sight, backed off its surface point).
func _perturbation() -> void:
	# pert_iters: off at the default view and above PERT_ON x floor32; below it,
	# every record the orbit has (each ray picks its own handoff on the GPU)
	var pp := FractalParams.new()
	var de := CameraState.DEFAULT_EYE
	var home := ReferenceOrbit.build(pp, de.x, de.y, de.z)
	check_eq(pp.pert_iters(home, home.distance), 0, "the default view does not perturb")
	var sp := SurfaceFixture.default_surface(pp)
	var switch_at := FractalParams.PERT_ON * pp.floor32(PackedFloat64Array([sp[0], sp[1], sp[2]]))
	for cs in [[2.0, false], [0.5, true]]:
		var eb := SurfaceFixture.backed(sp, SurfaceFixture.back_for_distance(pp, sp, cs[0] * switch_at))
		var ob := ReferenceOrbit.build(pp, eb[0], eb[1], eb[2])
		check(absf(ob.distance / (cs[0] * switch_at) - 1.0) < 0.1, "placed at %s x the switch (near %s)" % [cs[0], ob.distance])
		check_eq(pp.pert_iters(ob, ob.distance) > 0, cs[1], "%s x the switch distance: perturbing is %s" % [cs[0], cs[1]])
	var e5 := SurfaceFixture.backed(sp, 1e-5)
	var o5 := ReferenceOrbit.build(pp, e5[0], e5[1], e5[2])
	check_eq(pp.pert_iters(o5, o5.distance), mini(ReferenceOrbit.PERT_MAX, o5.n), "1e-5 from the surface: every record, min(PERT_MAX, n) = %d" % mini(ReferenceOrbit.PERT_MAX, o5.n))
	var kifs := FractalParams.new()
	kifs.shape = FractalParams.Shape.KIFS
	var ko := ReferenceOrbit.build(kifs, 3.2, 2.4, 1.9)
	check(ko.n < ReferenceOrbit.PERT_MAX, "precondition: a KIFS eye outside the sponge escapes early (n %d)" % ko.n)
	check_eq(kifs.pert_iters(ko, 1e-9), ko.n, "and then it gets only the n records its orbit has")
	for v in SurfaceFixture.variants():
		if v[3]:
			continue
		var vs := SurfaceFixture.surface_from(v[1], v[2])
		for back in [1e-3, 1e-5, 1e-7]:
			var vb := SurfaceFixture.backed(vs, back)
			var vo := ReferenceOrbit.build(v[1], vb[0], vb[1], vb[2])
			check_eq(v[1].pert_iters(vo, vo.distance), 0, "%s at %s: never perturbed" % [v[0], back])
		var v5 := SurfaceFixture.backed(vs, 1e-5)
		check_eq(v[1].zoom_floor(v5), v[1].floor32(v5), "%s keeps today's 32-bit floor" % v[0])

	# the zoom floor: floor_pert alone for a perturbable shape. On the default box
	# it is far below 1e-9 (measured while planning: 3.0e-10 at 1e-5 back,
	# 1.5e-10 at 1e-6), against today's 9.5e-5
	check(pp.zoom_floor(e5) > 0.0 and pp.zoom_floor(e5) < 1e-9,
		"the default box's zoom floor is below 1e-9 (%s; the 32-bit one is %s)" % [pp.zoom_floor(e5), pp.floor32(e5)])
	check_eq(pp.zoom_floor(e5), pp.floor_pert(o5), "and it is floor_pert")
