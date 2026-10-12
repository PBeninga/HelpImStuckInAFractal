extends "res://tests/test_case.gd"
## The centre ray: a march that lands on the surface the distance estimator
## sees, a miss outside the cube, a cache that follows the camera and the
## shape; the view's probe dot uniforms; and Main's R toggle, kept in Settings.


func run() -> void:
	var params := FractalParams.new()
	var cam := CameraState.make_default()   # looking at the origin, from outside the cube

	# --- a hit lands on the surface: tiny DE there, and nothing closer on the way ---
	var r := CenterRay.march(cam.eye(), cam.forward(), params)
	check(r[1], "the default view's centre ray hits the fractal")
	var t: float = r[0]
	var hit_point := cam.eye() + cam.forward() * t
	var near := DistanceEstimator.estimate(cam.eye(), params)
	check(DistanceEstimator.estimate(hit_point, params) < params.hit_epsilon(t, near),
		"the hit point is within the hit threshold of the surface")
	check(t >= near - 1e-9, "the hit is no nearer than the nearest surface (t %s, near %s)" % [t, near])

	# --- looking away from the cube misses ---
	var away := CenterRay.march(cam.eye(), -cam.forward(), params)
	check(not away[1] and is_inf(away[0]), "a ray that never meets the cube is a miss at INF")

	# --- the other fractals: their own bound, and the Kleinian's view distance ---
	var kifs := FractalParams.new(); kifs.shape().shape = FractalParams.Shape.KIFS
	var kcam := CameraState.new()
	kcam.transform = Transform3D(Basis.IDENTITY, Vector3(3.2, 2.4, 1.9)).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	check(CenterRay.march(kcam.eye(), kcam.forward(), kifs)[1], "the centre ray hits the Menger sponge")
	var kl := FractalParams.new(); kl.shape().shape = FractalParams.Shape.KLEINIAN
	var lcam := CameraState.new()
	lcam.transform = Transform3D(Basis.IDENTITY, Vector3(2.5, 1.6, 1.2)).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	var kr := CenterRay.march(lcam.eye(), lcam.forward(), kl)
	check(kr[1] and kr[0] < kl.view_distance(), "and the Kleinian, inside its view distance")
	kl.shape().kleinian_view_distance = 1e-3
	check(not CenterRay.march(lcam.eye(), lcam.forward(), kl)[1], "nothing past the view distance is hit")
	var bulb := FractalParams.new(); bulb.shape().shape = FractalParams.Shape.MANDELBULB
	var bcam := CameraState.new()
	bcam.transform = Transform3D(Basis.IDENTITY, Vector3(2.2, 1.6, 1.2)).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	var br := CenterRay.march(bcam.eye(), bcam.forward(), bulb)
	check(br[1] and br[0] < bcam.eye().length() - 0.5, "the centre ray hits the Mandelbulb, short of its middle")

	# --- the cached ray follows the camera and the shape ---
	var ray := CenterRay.new(params, cam)
	check_approx(ray.distance(), t, "the cached ray matches march()", 1e-9)
	check(ray.point().is_equal_approx(hit_point), "point() is the hit point")
	var turned := cam.transform
	turned.basis = turned.basis.rotated(Vector3(0, 0, 1), PI)   # face away from the fractal
	cam.transform = turned
	check(not ray.hit() and is_inf(ray.distance()), "turning away re-marches: now a miss")
	cam.transform = CameraState.make_default().transform
	check_approx(ray.distance(), t, "turning back hits again", 1e-9)
	params.shape().box_scale = -1.5
	var reshaped := CenterRay.march(cam.eye(), cam.forward(), params)
	check_approx(ray.distance(), reshaped[0], "a shape change re-marches", 1e-9)
	params.shape().box_scale = ShapeParams.new().box_scale

	# --- a second, small shape well away from the first: the ray from the
	# default view shrunk into it hits it at a hundredth of the distance, in
	# its own frame ---
	var nested := FractalParams.new()
	var small := nested.add_shape()
	small.pos_x = 10.0; small.pos_y = 10.0; small.pos_z = 10.0
	small.size = 0.01
	var inner_cam := CameraState.new()
	var inner_eye := small.to_world_v(CameraState.DEFAULT_EYE)   # the default view, shrunk into the small shape
	inner_cam.set_basis(cam.transform.basis)
	inner_cam.set_eye(inner_eye.x, inner_eye.y, inner_eye.z)
	var nr := CenterRay.march(inner_cam.eye(), inner_cam.forward(), nested)
	check(nr[1] and absf(nr[0] - t * 0.01) < 1e-3 * t, "inside the small shape the centre ray hits it at a hundredth of the default distance (%s vs %s)" % [nr[0], t * 0.01])

	# --- the fly speed follows the ray, capped by NEAR_CAP x the nearest surface ---
	var fly := FlyCamera.new()
	root.add_child(fly)
	fly.setup(params, cam, ray)
	var want := minf(ray.distance(), near * FlyCamera.NEAR_CAP)
	check_approx(fly.base_speed(), clampf(want, 1e-6, 20.0) * cam.speed_factor,
		"base speed is min(ray, NEAR_CAP x near) x factor", 1e-9)
	cam.transform = turned   # a miss: the cap alone
	var near_turned := DistanceEstimator.estimate(cam.eye(), params)
	check_approx(fly.base_speed(), clampf(near_turned * FlyCamera.NEAR_CAP, 1e-6, 20.0) * cam.speed_factor,
		"a miss takes the NEAR_CAP x near speed", 1e-9)
	cam.transform = CameraState.make_default().transform
	fly.queue_free()

	# --- the view paints the dot only while shown and hitting ---
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 800)
	view.setup(params, cam)
	await frames(1)
	var mat: ShaderMaterial = view._material
	check(view.center_ray() != null, "the view owns a centre ray after setup")
	check(not bool(mat.get_shader_parameter("probe_on")), "the dot starts hidden")
	view.show_probe = true
	check(bool(mat.get_shader_parameter("probe_on")), "showing the probe turns the dot on")
	var vt := view.center_ray().distance()
	check(Vector3(mat.get_shader_parameter("probe_point")).is_equal_approx(cam.eye() + cam.forward() * vt),
		"the dot sits at the centre ray's hit")
	check_approx(float(mat.get_shader_parameter("probe_radius")), vt * FractalView.PROBE_ANGULAR_RADIUS,
		"its radius scales with the distance", 1e-9)
	var step := cam.transform
	step.origin += cam.forward() * vt * 0.5   # halfway to the surface
	cam.transform = step
	check_approx(float(mat.get_shader_parameter("probe_radius")),
		view.center_ray().distance() * FractalView.PROBE_ANGULAR_RADIUS,
		"a camera move refreshes the dot (no stale cache)", 1e-9)
	check(view.center_ray().distance() < vt, "and the hit is nearer after moving in")
	cam.transform = turned
	check(not bool(mat.get_shader_parameter("probe_on")), "a miss hides the dot")
	cam.transform = CameraState.make_default().transform
	view.show_probe = false
	check(not bool(mat.get_shader_parameter("probe_on")), "hiding the probe turns it off")
	view.queue_free()
	await frames(1)

	# --- the 64-bit march: march() is march_at() on the same origin, and from
	# 1e-8 short of the Kleinian's surface (which resolves far below that) only a
	# 64-bit origin hits (measured while planning: t/back 1.011 from the 64-bit
	# origin; a 32-bit origin there is about 1e-7 off, ten times the distance) ---
	var e := CameraState.make_default().eye()
	var f0 := CameraState.make_default().forward()
	check_eq(CenterRay.march_at(e.x, e.y, e.z, f0, params), CenterRay.march(e, f0, params),
		"march() is march_at() on the same origin")
	var klp := FractalParams.new()
	klp.shape().shape = FractalParams.Shape.KLEINIAN
	var sf := SurfaceFixture.surface_from(klp, Vector3(2.5, 1.6, 1.2))
	var sdir := Vector3(sf[3], sf[4], sf[5])
	var o := SurfaceFixture.backed(sf, 1e-8)
	var r64 := CenterRay.march_at(o[0], o[1], o[2], sdir, klp)
	check(r64[1] and absf(r64[0] / 1e-8 - 1.0) < 0.05,
		"from 1e-8 the 64-bit origin hits at about 1e-8 (hit %s, t/back %s)" % [r64[1], r64[0] / 1e-8])
	var r32 := CenterRay.march(Vector3(o[0], o[1], o[2]), sdir, klp)
	check(not r32[1] or absf(r32[0] / 1e-8 - 1.0) > 0.05,
		"the same ray from the 32-bit-rounded origin does not (hit %s, t/back %s)" % [r32[1], r32[0] / 1e-8])
	var deep_cam := CameraState.new()
	deep_cam.transform = Transform3D(Basis.IDENTITY, Vector3(o[0], o[1], o[2])).looking_at(Vector3(o[0], o[1], o[2]) + sdir, Vector3(0, 0, 1))
	deep_cam.set_eye64(o[0], o[1], o[2])
	var cached := CenterRay.new(klp, deep_cam).distance()
	check(absf(cached / r64[0] - 1.0) < 0.01, "the cached ray marches from the 64-bit eye (%s against %s)" % [cached, r64[0]])

	# --- Main: R toggles the dot, kept in Settings ---
	var settings: Node = root.get_node("Settings")
	var original_path: String = settings.config_path
	var original_probe: bool = settings.show_center_ray
	settings.config_path = "user://center_ray_test_settings.cfg"
	settings.show_center_ray = false
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	# The console opens at startup; headless it is embedded and would take R.
	main.console().hide_console()
	var mfly: FlyCamera = main.get_node("FlyCamera")
	check(mfly._ray == main.view.center_ray(), "Main's fly camera shares the view's centre ray")
	check(not main.view.show_probe, "the dot starts hidden")
	await press_action("toggle_center_ray")
	check(settings.show_center_ray, "R turns the probe on in Settings")
	check(main.view.show_probe, "and the view shows the dot")
	await press_action("toggle_center_ray")
	check(not settings.show_center_ray and not main.view.show_probe, "R again hides it")
	for action in [&"axis_a_pos", &"axis_a_neg"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	main.queue_free()
	await frames(1)
	settings.show_center_ray = original_probe
	await frames(1)
	settings.config_path = original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://center_ray_test_settings.cfg"))
