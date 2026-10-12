extends "res://tests/test_case.gd"
## project/unproject round-trip, render-scale sizing, and that the view's shader
## material carries the compiled shader. A resize requests a frame (it used to
## leave the view black), and the SubViewport is sized in physical pixels: the
## logical size times the window's content scale.


func run() -> void:
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)                                    # let _ready wire the SubViewport
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)   # stop filling the window so size sticks
	view.size = Vector2(1280, 800)                     # projection uses the Control's own size
	view.setup(params, cam)
	await frames(1)

	# the shader material is wired and compiled
	var names: Array = []
	for u in view.shader_uniform_names():
		names.append(String(u))
	check(names.has("local_eye") and names.has("box_half") and names.has("shape_count"), "view's shader declares the uniforms")

	# project then unproject round-trips a point in front of the camera
	var p := Vector3(0.5, 0.2, 0.1)   # near the origin, in view
	var px: Variant = view.project(p)
	check(px != null, "a point in front projects to a pixel")
	if px != null:
		var rel: Vector3 = p - cam.eye()
		var depth: float = rel.dot(cam.forward())
		var back: Vector3 = view.unproject(px, depth)
		check(back.is_equal_approx(p), "unproject(project(p)) == p (got %s)" % back)

	# a point behind the camera projects to null
	var behind: Vector3 = cam.eye() + cam.forward() * -5.0
	check(view.project(behind) == null, "a point behind the camera projects to null")

	# render scale sets the SubViewport size (rounded to whole pixels)
	view.set_render_scale(0.5)
	await frames(1)
	check_eq(view.viewport_size(), Vector2i(640, 400), "render_scale 0.5 halves the viewport")
	view.set_render_scale(2.0)   # clamps to 1.0
	await frames(1)
	check_eq(view.viewport_size(), Vector2i(1280, 800), "render_scale clamps to 1.0")

	# a resize after the frame was drawn requests a new one (the black-view bug)
	await frames(2)
	var sub: SubViewport = view._viewport
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED   # the frame was consumed
	view.size = Vector2(1000, 700)
	check_eq(view.viewport_size(), Vector2i(1000, 700), "the SubViewport follows the resize")
	check_eq(sub.render_target_update_mode, SubViewport.UPDATE_ONCE, "a resize requests a frame")
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.size = Vector2(1000, 700)
	check_eq(sub.render_target_update_mode, SubViewport.UPDATE_DISABLED, "the same size does not")
	view.size = Vector2(1280, 800)
	await frames(1)

	# the load-shed level pushes fog, cheaper detail and a smaller step budget;
	# level 0 pushes exactly the view's own values
	var mat := view._material
	check_eq(view.load_level, 0, "the view starts at full quality")
	check_eq(float(mat.get_shader_parameter("fog_dist")), 0.0, "no fog at level 0")
	var base_prec: float = _slot0(mat, "precision")
	var base_coarse: int = mat.get_shader_parameter("coarse_steps")

	# the shadow march's budget sheds with the ladder: 48, 24, 0
	check_eq(int(mat.get_shader_parameter("shadow_steps")), FractalParams.SHADOW_STEPS,
		"level 0 pushes the full 48-step shadow march")
	view.set_load_level(1)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), 24, "level 1 halves the shadow march to 24")
	view.set_load_level(2)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), 0, "level 2 skips the shadow march")
	view.set_load_level(0)
	check_eq(int(mat.get_shader_parameter("shadow_steps")), FractalParams.SHADOW_STEPS, "and back to 48 at level 0")

	view.set_load_level(3)
	var l3 := LoadShedder.settings(3)
	check_approx(mat.get_shader_parameter("fog_dist"), l3["fog"], "level 3 pushes its fog distance")
	check_approx(_slot0(mat, "precision"), base_prec / l3["detail"],
		"level 3 coarsens the precision by its detail factor", 1e-10)
	check(int(mat.get_shader_parameter("coarse_steps")) < base_coarse, "level 3 shrinks the step budget")
	check(Vector3(mat.get_shader_parameter("fog_color")).is_equal_approx(params.fog_color()),
		"the fog takes the colour mode's tint")
	params.color_mode = 14
	check(Vector3(mat.get_shader_parameter("fog_color")).is_equal_approx(params.fog_color()),
		"and follows the colour mode")
	params.max_steps = FractalParams.MAX_STEPS_MIN
	check_eq(int(mat.get_shader_parameter("coarse_steps")) + int(mat.get_shader_parameter("fine_steps")),
		FractalParams.MAX_STEPS_MIN, "the shed budget never drops below MAX_STEPS_MIN")
	params.max_steps = 128
	# a level drop eases in over RESTORE_FRAMES frames: the fog recedes (and when
	# it is leaving entirely it thins as it goes) while the detail and step
	# budget climb back
	var l3_prec: float = _slot0(mat, "precision")
	var l3_coarse: int = mat.get_shader_parameter("coarse_steps")
	view.set_load_level(2)
	var l2 := LoadShedder.settings(2)
	var mid := float(mat.get_shader_parameter("fog_dist"))
	check(mid > l3["fog"] and mid < l2["fog"], "a drop to level 2 starts the fog receding (%s)" % mid)
	check_eq(float(mat.get_shader_parameter("fog_clear")), 0.0, "a fog that stays does not thin")
	var mid_prec := float(_slot0(mat, "precision"))
	var l2_prec: float = base_prec / l2["detail"]
	check(mid_prec < l3_prec and mid_prec > l2_prec, "and the detail starts climbing (%s)" % mid_prec)
	check(view.restoring(), "and the view is still easing it")
	await frames(FractalView.RESTORE_FRAMES / 2 + 1)
	check(int(mat.get_shader_parameter("coarse_steps")) > l3_coarse, "half way the step budget has grown")
	check(float(_slot0(mat, "precision")) < mid_prec, "and the detail climbed further")
	await frames(FractalView.RESTORE_FRAMES)
	check_approx(mat.get_shader_parameter("fog_dist"), l2["fog"], "it lands on level 2's fog")
	check_approx(_slot0(mat, "precision"), l2_prec, "and level 2's detail", 1e-12)
	var l2_budget: int = maxi(FractalParams.MAX_STEPS_MIN, int(round(params.max_steps * l2["steps"])))
	check_eq(int(mat.get_shader_parameter("coarse_steps")), params.coarse_steps(l2_budget),
		"and level 2's step budget")
	check(not view.restoring(), "and stops easing")
	view.set_load_level(0)
	var first := float(mat.get_shader_parameter("fog_dist"))
	var clear := float(mat.get_shader_parameter("fog_clear"))
	check(first > l2["fog"], "back to level 0 the fog first recedes (%s)" % first)
	check(clear > 0.0 and clear < 1.0, "and thins (%s)" % clear)
	await frames(2)   # process_frame fires before the view's _process steps the fog
	check(float(mat.get_shader_parameter("fog_dist")) > first, "a frame later it is further out")
	check(float(mat.get_shader_parameter("fog_clear")) > clear, "and thinner")
	view.set_load_level(3)
	check_approx(mat.get_shader_parameter("fog_dist"), l3["fog"], "a shed mid-ease snaps the fog straight in")
	check_eq(float(mat.get_shader_parameter("fog_clear")), 0.0, "at full strength")
	check_approx(_slot0(mat, "precision"), l3_prec, "and the detail straight down", 1e-12)
	check(not view.restoring(), "with no easing")
	view.set_load_level(0)
	await frames(FractalView.RESTORE_FRAMES)
	check_eq(float(mat.get_shader_parameter("fog_dist")), 0.0, "back to level 0: no fog")
	check_eq(float(mat.get_shader_parameter("fog_clear")), 0.0, "and nothing left to thin")
	check_approx(_slot0(mat, "precision"), base_prec, "and the original precision", 1e-12)
	check_eq(int(mat.get_shader_parameter("coarse_steps")), base_coarse, "and the original budget")

	# the colour, lighting and palette values reach their uniforms
	for key in FractalParams.LOOK_KEYS:
		check_approx(float(mat.get_shader_parameter(key)), float(params.get(key)),
			"the view pushes '%s'" % key, 1e-9)
	# the two COLOR keys are pushed as Vector3 (the shader's vec3 uniforms)
	params.light_color = Color(0.2, 0.4, 0.6)
	params.surface_color = Color(0.7, 0.5, 0.3)
	check(Vector3(mat.get_shader_parameter("light_color")).is_equal_approx(Vector3(0.2, 0.4, 0.6)),
		"light_color pushes as a Vector3")
	check(Vector3(mat.get_shader_parameter("surface_color")).is_equal_approx(Vector3(0.7, 0.5, 0.3)),
		"surface_color pushes as a Vector3")
	params.light_color = Color(1, 1, 1)
	params.surface_color = Color(1, 1, 1)
	params.apply_resolved({&"light_specular": 2.5, &"palette_d_b": 0.1, &"palette_source": 2})
	check_approx(float(mat.get_shader_parameter("light_specular")), 2.5, "a resolved Specular reaches the shader")
	check_approx(float(mat.get_shader_parameter("palette_d_b")), 0.1, "so does a palette component")
	check_eq(int(mat.get_shader_parameter("palette_source")), 2, "and the palette input")

	# the camera's distance to the surface sets the coarse pass's iteration
	# count (the site's 16 at the default view, more up close, and a Detail
	# change re-pushes it) and the shading crossfade (1 far, 0 up close)
	check_eq(int(_slot0(mat, "coarse_iters")), 16, "the default view's coarse pass keeps 16 iterations")
	check_eq(float(mat.get_shader_parameter("nf_weight")), 1.0, "and lights with the Ice Fractal probe alone")
	var home := cam.transform
	var close := home
	close.origin = cam.eye() + cam.forward() * (view.center_ray().distance() - 1e-3)
	cam.transform = close
	var close_near := maxf(DistanceEstimator.estimate(cam.eye(), params), FractalParams.NEAR_FLOOR)
	check_eq(int(_slot0(mat, "coarse_iters")), params.coarse_iters(close_near),
		"a camera 1e-3 short of the surface pushes its own count")
	check(int(_slot0(mat, "coarse_iters")) > 16, "which is above 16 (%s)" % _slot0(mat, "coarse_iters"))
	check_eq(float(mat.get_shader_parameter("nf_weight")), 0.0, "and the true normal alone lights it")
	params.detail = 10.0
	check_eq(int(_slot0(mat, "coarse_iters")), params.coarse_iters(close_near), "a Detail change re-pushes it")
	params.detail = 1.0
	cam.transform = home
	check_eq(int(_slot0(mat, "coarse_iters")), 16, "and moving back restores 16")
	check_eq(float(mat.get_shader_parameter("nf_weight")), 1.0, "and the probe's lighting")

	# the shape uniforms are arrays of MAX_SHAPES entries; a second shape fills
	# its slot, its frame is the eye mapped into it, and the camera's nearest
	# shape sets the near distance and the coarse pass
	var scales: PackedFloat32Array = mat.get_shader_parameter("box_scale")
	check_eq(scales.size(), FractalParams.MAX_SHAPES, "box_scale is an array of MAX_SHAPES")
	check_approx(scales[0], -2.09, "slot 0 holds the first shape's scale")
	check_eq(int(mat.get_shader_parameter("shape_count")), 1, "shape_count is 1")
	var eyes: PackedVector3Array = mat.get_shader_parameter("local_eye")
	check(eyes[0].is_equal_approx(cam.eye()), "at the identity placement the local eye is the eye")
	var second := params.add_shape()
	second.pos_x = -4.0
	second.pos_y = -4.0
	second.pos_z = -4.0
	second.rot_z = 90.0
	second.size = 0.5
	second.box_scale = 2.0
	second.precision = 1e-4
	await frames(1)
	check_eq(int(mat.get_shader_parameter("shape_count")), 2, "a second shape raises shape_count")
	scales = mat.get_shader_parameter("box_scale")
	check_approx(scales[1], 2.0, "slot 1 holds its scale")
	var sizes: PackedFloat32Array = mat.get_shader_parameter("shape_size")
	check_approx(sizes[1], 0.5, "and its size")
	var precs: PackedFloat32Array = mat.get_shader_parameter("precision")
	check_approx(precs[1], 1e-4, "and its precision", 1e-10)
	eyes = mat.get_shader_parameter("local_eye")
	var expect_local := second.to_local_v(cam.eye())
	check(eyes[1].is_equal_approx(expect_local), "its local eye is Rᵀ(eye − pos) / size (%s)" % eyes[1])
	var fx: PackedVector3Array = mat.get_shader_parameter("frame_x")
	check(fx[1].is_equal_approx(Vector3(0, 1, 0)), "rot_z 90 turns its local x axis to world +y (%s)" % fx[1])
	var toggles: PackedInt32Array = mat.get_shader_parameter("julia_all")
	check_eq(toggles.size(), FractalParams.MAX_SHAPES, "the toggles travel as int arrays")
	# the camera (9.6 from the origin, 6.6 from the first shape) is far from the
	# second shape's cube, which sits at (-4, -4, -4)
	check_eq(view.nearest_shape(), 0, "the camera is nearest the first shape")
	var far_near := float(mat.get_shader_parameter("near_dist"))
	cam.set_eye(-4.0, -4.0, -3.4)   # inside the second shape's cube
	await frames(1)
	check_eq(view.nearest_shape(), 1, "moving into the second shape makes it the nearest")
	check(float(mat.get_shader_parameter("near_dist")) < far_near, "and the near distance is to it (%s)" % mat.get_shader_parameter("near_dist"))
	var iters: PackedInt32Array = mat.get_shader_parameter("coarse_iters")
	check(iters[1] >= 16 and iters[0] >= 16, "each shape has its own coarse pass (%s, %s)" % [iters[0], iters[1]])
	cam.transform = CameraState.make_default().transform
	params.remove_shape(1)
	await frames(1)
	check_eq(int(mat.get_shader_parameter("shape_count")), 1, "removing it drops shape_count")

	# near_dist follows the camera below 1e-6: measured from the 64-bit eye, clamped only at 1e-14
	var snear := SurfaceFixture.default_surface(params)
	var enear := SurfaceFixture.backed(snear, 1e-8)
	cam.set_eye64(enear[0], enear[1], enear[2])
	await frames(1)
	var dnear := DistanceEstimator.scene_estimate_at(enear[0], enear[1], enear[2], params)
	check_eq(float(mat.get_shader_parameter("near_dist")), maxf(dnear, FractalParams.NEAR_FLOOR),
		"a camera 1e-8 short of the surface pushes its own distance (%s)" % dnear)
	check(float(mat.get_shader_parameter("near_dist")) < 1e-7, "not the old 1e-6 clamp")
	cam.transform = home   # back from the 1e-8 camera

	# the shape switch reaches the shader, and the bounding cube follows the shape
	check_approx(float(_slot0(mat, "box_half")), 2.0, "the Mandelbox marches in its cube of half-side 2")
	params.shape().apply_resolved({&"shape": FractalParams.Shape.KIFS, &"kifs_scale": 2.5, &"kifs_rot2_yz": 12.0})
	check_eq(int(_slot0(mat, "shape")), FractalParams.Shape.KIFS, "the shape reaches the shader")
	check_approx(float(_slot0(mat, "kifs_scale")), 2.5, "a KIFS knob reaches its uniform")
	check_approx(float(_slot0(mat, "kifs_rot2_yz")), 12.0, "so does a KIFS rotation")
	check_approx(float(_slot0(mat, "box_half")), params.bound_half(), "the KIFS's bound is pushed")
	params.shape().apply_resolved({&"shape": FractalParams.Shape.KLEINIAN, &"kleinian_view_distance": 7.0})
	check_approx(float(_slot0(mat, "kleinian_view_distance")), 7.0, "the view distance reaches the shader")
	check_approx(float(_slot0(mat, "box_half")), FractalParams.KLEINIAN_BOUND, "the Kleinian has no real cube")
	check_eq(int(_slot0(mat, "coarse_iters")), DistanceEstimator.ITERATIONS,
		"and no steady magnification, so its coarse pass runs all 32 iterations")
	params.shape().apply_resolved({&"shape": FractalParams.Shape.MANDELBULB, &"mandelbulb_power": 5.0, &"mandelbulb_julia": true})
	check_eq(int(_slot0(mat, "shape")), FractalParams.Shape.MANDELBULB, "the Mandelbulb reaches the shader")
	check_approx(float(_slot0(mat, "mandelbulb_power")), 5.0, "and its power")
	check(bool(_slot0(mat, "mandelbulb_julia")), "and its Julia switch")
	check_approx(float(_slot0(mat, "box_half")), 2.0, "the Mandelbulb marches in the cube of half-side 2")
	params.shape().apply_resolved({&"shape": FractalParams.Shape.MANDELBOX, &"fold_shape": MandelboxShape.FoldShape.OCTAHEDRAL})
	check_eq(int(_slot0(mat, "fold_shape")), MandelboxShape.FoldShape.OCTAHEDRAL, "a fold option reaches the shader")
	params.apply_resolved({&"fold_shape": MandelboxShape.FoldShape.BOX})

	view.queue_free()
	await frames(1)

	# in a window with content scale 2 the SubViewport renders physical pixels;
	# project/unproject stay in the view's logical units
	var win := Window.new()
	win.size = Vector2i(1600, 1200)
	win.content_scale_factor = 2.0
	root.add_child(win)
	var hi: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	win.add_child(hi)
	await frames(1)
	hi.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hi.size = Vector2(400, 300)
	hi.setup(params, cam)
	await frames(1)
	check_eq(hi.viewport_size(), Vector2i(800, 600), "at content scale 2 the viewport is twice the logical size")
	hi.set_render_scale(0.5)
	check_eq(hi.viewport_size(), Vector2i(400, 300), "and render scale is still a fraction of that")
	hi.set_render_scale(1.0)
	var hpx: Variant = hi.project(Vector3(0.5, 0.2, 0.1))
	check(hpx != null and Rect2(Vector2.ZERO, hi.size).has_point(hpx), "project() answers in logical units")
	var hsub: SubViewport = hi._viewport
	hsub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	win.content_scale_factor = 3.0
	await frames(1)
	check_eq(hi.viewport_size(), Vector2i(1200, 900), "a content scale change resizes the viewport")
	check_eq(hsub.render_target_update_mode, SubViewport.UPDATE_ONCE, "and requests a frame")
	win.queue_free()
	await frames(1)


## A per-shape uniform's first slot.
func _slot0(mat: ShaderMaterial, name: String) -> Variant:
	var v: Variant = mat.get_shader_parameter(name)
	if v is PackedFloat32Array or v is PackedInt32Array or v is PackedVector3Array:
		return v[0]
	return v
