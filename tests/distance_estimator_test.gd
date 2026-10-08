extends "res://tests/test_case.gd"
## Pins the CPU estimator to the site's own numbers (24 fixtures), plus the
## spec's non-default fixtures (positive scale, Sphere -> Box, one iteration
## rotation, a non-zero w, a per-component Julia mix) and the symmetry /
## sensitivity invariants, and the optional iteration count. The fixtures pin the 64-bit scalar core
## `estimate_at`, so every row holds the spec's tolerance: relative 1e-5, or
## absolute 1e-9 below 1e-6.


func _de(px: float, py: float, pz: float, params: FractalParams, expected: float, label: String) -> void:
	var got := DistanceEstimator.estimate_at(px, py, pz, params)
	var tol := maxf(1e-9, 1e-5 * absf(expected))
	check(absf(got - expected) <= tol,
		"%s: expected %s got %s (tol %s)" % [label, expected, got, tol])


func run() -> void:
	# --- defaults: box_scale -2.09, min 0.7, fold 1, fixed 1, no Julia, w 0 ---
	var d := FractalParams.new()
	_de(0, 0, 0, d, 0.0, "def (0,0,0)")
	_de(0.5, 0.5, 0.5, d, 1.67e-15, "def (0.5,0.5,0.5)")
	_de(1.2, -0.3, 0.8, d, 4.536385e-5, "def (1.2,-0.3,0.8)")
	_de(2, 2, 2, d, 1.84e-20, "def (2,2,2)")
	_de(3, 0, 0, d, 1.0000000, "def (3,0,0)")
	_de(8.18, 3.81, 3.28, d, 6.5655845, "def (8.18,3.81,3.28)")
	_de(0.1, 0.9, 1.5, d, 1.2707534e-5, "def (0.1,0.9,1.5)")
	_de(-1.5, 1.5, -1.5, d, 7.2696999e-3, "def (-1.5,1.5,-1.5)")

	# --- alternative shape: box_scale -3, min 0.5, fold 0.8, fixed 0.9 ---
	var a := FractalParams.new()
	a.box_scale = -3.0; a.min_radius = 0.5; a.fold_limit = 0.8; a.fixed_radius = 0.9
	_de(0, 0, 0, a, 0.0, "alt (0,0,0)")
	_de(0.5, 0.5, 0.5, a, 3.9589733e-3, "alt (0.5,0.5,0.5)")
	_de(1.2, -0.3, 0.8, a, 7.3684211e-2, "alt (1.2,-0.3,0.8)")
	_de(2, 2, 2, a, 0.69282032, "alt (2,2,2)")
	_de(3, 0, 0, a, 1.4000000, "alt (3,0,0)")
	_de(8.18, 3.81, 3.28, a, 7.1416315, "alt (8.18,3.81,3.28)")
	_de(0.1, 0.9, 1.5, a, 1.2998357e-2, "alt (0.1,0.9,1.5)")
	_de(-1.5, 1.5, -1.5, a, 3.5649260e-3, "alt (-1.5,1.5,-1.5)")

	# --- defaults with Julia (all) on, constant (-0.23, 1.512, 1.892, 0) ---
	var j := FractalParams.new()
	j.julia_all = true
	_de(0, 0, 0, j, 4.9979908e-3, "jul (0,0,0)")
	_de(0.5, 0.5, 0.5, j, 1.0887837e-2, "jul (0.5,0.5,0.5)")
	_de(1.2, -0.3, 0.8, j, 4.5308936e-3, "jul (1.2,-0.3,0.8)")
	_de(2, 2, 2, j, 4.9979908e-3, "jul (2,2,2)")
	_de(3, 0, 0, j, 8.0696204e-3, "jul (3,0,0)")
	_de(8.18, 3.81, 3.28, j, 2.3521820, "jul (8.18,3.81,3.28)")
	_de(0.1, 0.9, 1.5, j, 3.6647735e-3, "jul (0.1,0.9,1.5)")
	_de(-1.5, 1.5, -1.5, j, 0.25217396, "jul (-1.5,1.5,-1.5)")

	# --- symmetry: D(p) == D(-p) in non-Julia mode, w 0 ---
	for p in [Vector3(0.7, 0.3, 0.9), Vector3(1.2, -0.3, 0.8), Vector3(3, 0, 0),
			Vector3(8.18, 3.81, 3.28)]:
		check_approx(DistanceEstimator.estimate(p, d), DistanceEstimator.estimate(-p, d),
			"D(p) == D(-p) at %s" % p, 1e-9)

	# --- the Julia (all) constant changes the result ---
	check(absf(DistanceEstimator.estimate(Vector3(3, 0, 0), d)
			- DistanceEstimator.estimate(Vector3(3, 0, 0), j)) > 0.5,
		"turning Julia on changes the distance")

	# --- the public Vector3 API delegates to the core ---
	check_approx(DistanceEstimator.estimate(Vector3(3, 0, 0), d),
		DistanceEstimator.estimate_at(3.0, 0.0, 0.0, d), "estimate() == estimate_at()", 1e-6)

	# ============================= new fixtures =============================
	# These pin the non-default knobs. Each value was captured from estimate_at
	# once; the shape of the mb_step is cross-checked against the shader by
	# shader_test (same uniforms) and by the structural invariants below.

	# positive scale (box_scale 2)
	var ps := FractalParams.new(); ps.box_scale = 2.0
	_de(1.2, -0.3, 0.8, ps, 2.5e-13, "pos scale (1.2,-0.3,0.8)")
	_de(0.5, 0.5, 0.5, ps, 1.0e-14, "pos scale (0.5,0.5,0.5)")
	# Sphere -> Box
	var sb := FractalParams.new(); sb.fold_order = 1
	_de(1.2, -0.3, 0.8, sb, 1.280467e-8, "sphere->box (1.2,-0.3,0.8)")
	# one iteration rotation (xy 30 deg)
	var rot := FractalParams.new(); rot.iter_rot_xy = 30.0
	_de(1.2, -0.3, 0.8, rot, 2.062593788e-4, "iter rot xy 30 (1.2,-0.3,0.8)")
	# a non-zero w
	var wp := FractalParams.new(); wp.w = 0.5
	_de(1.2, -0.3, 0.8, wp, 6.280428097e-5, "w=0.5 (1.2,-0.3,0.8)")
	# a per-component Julia mix (x and z constant, y and w from the point)
	var mix := FractalParams.new(); mix.julia_0 = true; mix.julia_2 = true
	_de(1.2, -0.3, 0.8, mix, 2.02335288439e-3, "julia mix 0,2 (1.2,-0.3,0.8)")

	# --- structural invariants: each non-default knob changes the picture ---
	var base := DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), d)
	check(absf(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), sb) - base) > 1e-6,
		"fold order changes the distance")
	check(absf(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), wp) - base) > 1e-6,
		"a non-zero w changes the distance")
	check(absf(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), ps) - base) > 1e-6,
		"a positive scale changes the distance")
	# an iteration rotation changes the distance (vs no rotation)
	check(absf(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), rot) - base) > 1e-6,
		"an iteration rotation changes the distance")
	# a per-component Julia mix changes the distance
	check(absf(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), mix) - base) > 1e-6,
		"a per-component Julia mix changes the distance")

	# --- an optional iteration count (the shader's coarse pass uses fewer) ---
	var full := DistanceEstimator.estimate_at(1.2, -0.3, 0.8, d)
	check_eq(DistanceEstimator.estimate_at(1.2, -0.3, 0.8, d, 32), full, "iters 32 is the default, exactly")
	var d16 := DistanceEstimator.estimate_at(1.2, -0.3, 0.8, d, 16)
	check(d16 > 0.0 and is_finite(d16) and absf(d16 - full) > 1e-9,
		"16 iterations describe a slightly different surface (%s vs %s)" % [d16, full])
	check_eq(DistanceEstimator.estimate_at(1.2, -0.3, 0.8, d, 99), full, "a count past 32 is clamped to 32")
