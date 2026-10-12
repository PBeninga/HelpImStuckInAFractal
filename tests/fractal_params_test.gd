extends "res://tests/test_case.gd"


func run() -> void:
	var p := FractalParams.new()
	var s := p.shape()

	# a new FractalParams holds one default shape at the identity placement
	check_eq(p.shape_count(), 1, "one shape by default")
	check_eq(p.active, 0, "and it is the active one")
	check(p.active_shape() == s, "active_shape() is shape(0)")
	check_approx(s.pos_x, 0.0, "pos_x default")
	check_approx(s.rot_z, 0.0, "rot_z default")
	check_approx(s.size, 1.0, "size default")
	check_approx(s.bound_half(), 2.0, "bound_half is 2 outside Julia mode")

	# defaults (the site's defaults, by catalogue id): the shape's on the shape,
	# the look's on the params
	check_approx(s.box_scale, -2.09, "box_scale default")
	check_approx(s.min_radius, 0.7, "min_radius default")
	check_approx(s.fold_limit, 1.0, "fold_limit default")
	check_approx(s.fixed_radius, 1.0, "fixed_radius default")
	check_eq(s.fold_order, 0, "fold_order default is Box -> Sphere")
	check_approx(s.w, 0.0, "w default is 0 (today's 3D box)")
	check_eq(s.julia_all, false, "julia_all off by default")
	check_eq(s.julia_0, false, "julia_0 off")
	check_approx(s.c_0, -0.23, "c_0 default")
	check_approx(s.c_1, 1.512, "c_1 default")
	check_approx(s.c_2, 1.892, "c_2 default")
	check_approx(s.c_3, 0.0, "c_3 default")
	check_approx(s.iter_rot_xy, 0.0, "iter_rot_xy default")
	check_approx(s.iter_rot_zw, 0.0, "iter_rot_zw default")
	check_eq(p.color_mode, 1, "color_mode default is Ice Fractal")
	check_approx(s.precision, 0.000025, "precision default", 1e-9)
	check_eq(p.fast_controls, true, "fast_controls on by default")
	check_eq(p.camera_mode, FractalParams.CameraMode.FLY, "camera starts in fly mode")
	check_approx(p.mouse_sensitivity, 0.1, "mouse_sensitivity default")
	check_approx(p.detail, 1.0, "detail default")
	check_approx(p.detail_range, 10.0, "detail_range default")
	check_approx(p.detail_falloff, 0.0, "detail falloff is off by default")
	check_approx(p.min_render_scale, 0.1, "min_render_scale default")
	check_eq(p.max_steps, 96, "max_steps default")
	check_eq([p.coarse_steps(), p.fine_steps()], [72, 24], "the performance budget splits 72 + 24")

	# the helpers (the params' answer for the active shape)
	check(s.julia_point().is_equal_approx(Vector3(-0.23, 1.512, 1.892)), "julia_point() is (c_0, c_1, c_2)")
	check(p.julia_point().is_equal_approx(s.julia_point()), "the params' julia_point() is the active shape's")
	check_eq(s.julia_enabled(), false, "julia_enabled() follows julia_all")
	s.julia_all = true
	check_eq(s.julia_enabled(), true, "julia_enabled() true when julia_all is on")
	check_eq(p.julia_enabled(), true, "through the params too")
	check_approx(s.bound_half(), 20.0, "bound_half is 20 in Julia mode")
	s.julia_all = false

	# the site's thirteen colour ids in dropdown order, then Palette
	check_eq(p.COLOR_MODE_IDS, [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14, 20], "colour id order")
	check_eq(p.COLOR_MODE_NAMES.size(), 14, "fourteen colour names")
	check_eq(p.COLOR_MODE_NAMES[-1], "Palette", "the last is Palette")
	check_eq(p.COLOR_MODE_IDS[-1], Palette.MODE_ID, "with the Palette's mode id")

	# every resolved key is a catalogue id, and its field opens on the catalogue
	# default: the look keys on the params, the shape keys on the shape
	var shape_table := AttributeTable.new(ShapeCatalogue.specs())
	check_eq(FractalParams.RESOLVED_KEYS, ShapeCatalogue.scene_ids(), "RESOLVED_KEYS are the scene (look) ids, in order")
	check_eq(ShapeParams.RESOLVED_KEYS, ShapeCatalogue.shape_ids(), "ShapeParams.RESOLVED_KEYS are the shape ids, in order")
	for k in FractalParams.RESOLVED_KEYS:
		var want: Variant = shape_table.get_default(k)
		if want is float:
			check_approx(float(p.get(k)), want, "field '%s' opens on the catalogue default" % k, 1e-9)
		else:
			check_eq(p.get(k), want, "field '%s' opens on the catalogue default" % k)
	for k in ShapeParams.RESOLVED_KEYS:
		var want: Variant = shape_table.get_default(k)
		if want is float:
			check_approx(float(s.get(k)), want, "shape field '%s' opens on the catalogue default" % k, 1e-9)
		else:
			check_eq(s.get(k), want, "shape field '%s' opens on the catalogue default" % k)
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

	# --- apply_resolved emits once, only on a difference, and a shape's
	# changed is relayed as the params' ---
	var fires := [0]
	var cb := func(): fires[0] += 1
	p.changed.connect(cb)

	s.apply_resolved({&"box_scale": -1.5, &"fold_limit": 2.0, &"size": 0.5})
	check_eq(fires[0], 1, "a shape's apply_resolved emits once for a batch of changes (relayed by params)")
	check_approx(s.box_scale, -1.5, "and wrote box_scale")
	check_approx(s.fold_limit, 2.0, "and fold_limit")
	check_approx(s.size, 0.5, "and size")
	fires[0] = 0
	p.apply_resolved({&"color_mode": 2, &"exposure": 1.5})
	check_eq(fires[0], 1, "the params' apply_resolved emits once for the look")
	check_eq(p.color_mode, 2, "and wrote color_mode")
	check_approx(p.exposure, 1.5, "and exposure")

	fires[0] = 0
	s.apply_resolved({&"box_scale": -1.5, &"fold_limit": 2.0, &"size": 0.5})
	p.apply_resolved({&"color_mode": 2, &"exposure": 1.5})
	check_eq(fires[0], 0, "re-applying the same values emits nothing")

	fires[0] = 0
	s.apply_resolved({&"w": 0.5})
	check_eq(fires[0], 1, "a partial dict that changes one field emits once")
	check_approx(s.w, 0.5, "and wrote only w")
	check_approx(s.fold_limit, 2.0, "leaving the rest alone")

	# --- the list: add, active, remove, the floor of one ---
	fires[0] = 0
	var second := p.add_shape()
	check(second != null and p.shape_count() == 2, "add_shape appends a second shape")
	check_eq(fires[0], 1, "and emits changed")
	fires[0] = 0
	second.pos_x = 3.0
	check_eq(fires[0], 1, "an edit on the second shape is relayed too")
	p.active = 1
	check(p.active_shape() == second, "active picks the second")
	check(p.shape(1) == second, "and shape(1) is it")
	check_eq(fires[0], 2, "setting active emits")
	p.active = 7
	check_eq(p.active, 1, "active clamps to the list")
	check(not p.remove_shape(5), "removing an index out of range does nothing")
	check(p.remove_shape(1), "remove_shape drops the second")
	check_eq(p.shape_count(), 1, "back to one")
	check_eq(p.active, 0, "and active falls back")
	fires[0] = 0
	second.pos_x = 4.0
	check_eq(fires[0], 0, "a removed shape no longer relays")
	check(not p.remove_shape(0), "the last shape cannot be removed")
	p.set_shape_count(3)
	check_eq(p.shape_count(), 3, "set_shape_count grows the list")
	p.set_shape_count(1)
	check_eq(p.shape_count(), 1, "and shrinks it")
	var full := FractalParams.new()
	full.set_shape_count(FractalParams.MAX_SHAPES)
	check(full.add_shape() == null, "add_shape refuses past MAX_SHAPES")
	s.size = 0.0
	check(s.size > 0.0, "size never reaches 0 (%s)" % s.size)
	s.size = 1.0

	# --- copy_from takes every resolved field ---
	var copy := ShapeParams.new()
	copy.copy_from(s)
	check_approx(copy.box_scale, -1.5, "copy_from copies the Mandelbox knobs")
	check_approx(copy.w, 0.5, "all of them")
	check_eq(copy.shape, s.shape, "including the enums")

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

	# hit_epsilon: the plain cone by default, coarsened past the range; the
	# precision is the hit shape's (the active one's unless given)
	var e := FractalParams.new()
	check_approx(e.hit_epsilon(4.0, 0.5), 0.000025 * 4.0, "defaults give precision * t", 1e-12)
	check_approx(e.hit_epsilon(1.0, 0.5, 1e-4), 1e-4, "another shape's precision is used as given", 1e-12)
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
	ci.fractal_iterations = 32
	check_eq(ci.coarse_iters(6.5655845), 16, "the default view (near ~6.57) keeps the site's 16")
	check_eq(ci.coarse_iters(1000.0), 16, "far away never drops below 16")
	check_eq(ci.coarse_iters(1e-3), 24, "1e-3 from the surface takes 24")
	check_eq(ci.coarse_iters(1e-6), 32, "1e-6 takes all 32")
	check_eq(ci.coarse_iters(0.0), 32, "a camera on the surface stays at 32")
	var ci_fine := FractalParams.new()
	ci_fine.fractal_iterations = 32
	ci_fine.detail = 10.0
	check(ci_fine.coarse_iters(1e-2) > ci.coarse_iters(1e-2),
		"Detail 10 raises the count at a given distance (%d over %d)" % [ci_fine.coarse_iters(1e-2), ci.coarse_iters(1e-2)])
	var full_count := ci.coarse_iters(1e-3)
	ci.shape().box_scale = 1.0
	check_eq(ci.coarse_iters(6.5), 32, "|box_scale| = 1 has no shrinking detail: 32")
	ci.shape().box_scale = -0.8
	check_eq(ci.coarse_iters(6.5), 32, "nor does a scale inside 1: 32")
	# a smaller shape reaches the same count at a proportionally smaller distance
	var small := FractalParams.new()
	small.fractal_iterations = 32
	small.shape().size = 0.01
	check_eq(small.coarse_iters(1e-5), full_count,
		"a shape a hundredth the size takes at 1e-5 what the unit one takes at 1e-3")

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

	# floor32: the direct march's 32-bit precision floor
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
	check(is_finite(zf.zoom_floor(Vector3.ZERO)) and zf.zoom_floor(Vector3.ZERO) >= 0.0, "the origin stays finite")
	# the floor is the nearest shape's, in its own frame: a small shape far from
	# the origin lets the camera come proportionally closer than its world
	# coordinates would, because its local eye is small
	var zs := FractalParams.new()
	var tiny := zs.shape()
	tiny.pos_x = 8.0; tiny.pos_y = 3.0; tiny.pos_z = 3.0
	tiny.size = 0.001
	var at := tiny.to_world_v(Vector3(near_box[0], near_box[1], near_box[2]))
	var at64 := [at.x, at.y, at.z]
	check(zs.floor32(at64) < zf.floor32(near_box) * 0.002,
		"a thousandth-size shape has about a thousandth of the 32-bit floor (%s vs %s)" % [zs.floor32(at64), zf.floor32(near_box)])
	check_approx(zs.floor32(at64), tiny.zoom_floor(at.x, at.y, at.z), "which is the shape's own zoom_floor at that eye", 1e-15)
	var deep_at := tiny.to_world_v(Vector3(near_box[0], near_box[1], near_box[2]) * 0.999)
	check(zs.zoom_floor(deep_at) < zf.zoom_floor(Vector3(near_box[0], near_box[1], near_box[2]) * 0.999) * 0.002,
		"and the zoom guard uses the same floor in the shape's own frame (%s)" % zs.zoom_floor(deep_at))
	check_eq(FractalParams.NEAR_FLOOR, 1e-14, "near is clamped only against a zero (1e-14), not at 1e-6")
