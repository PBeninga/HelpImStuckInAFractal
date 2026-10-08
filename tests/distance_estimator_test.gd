extends "res://tests/test_case.gd"
## Pins the CPU estimator to the site's own numbers (24 fixtures), plus the
## spec's non-default fixtures (positive scale, Sphere -> Box, one iteration
## rotation, a non-zero w, a per-component Julia mix) and the symmetry /
## sensitivity invariants. The fixtures pin the 64-bit scalar core
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

	# ======================= the fold options =======================
	# Captured from estimate_at once; the defaults above pin that each option
	# at its default changes nothing.
	var cyl := FractalParams.new(); cyl.fold_shape = MandelboxShape.FoldShape.CYLINDER
	_de(1.2, -0.3, 0.8, cyl, 5.257641803377495e-3, "cylinder (1.2,-0.3,0.8)")
	_de(0.1, 0.9, 1.5, cyl, 2.4790616547414094e-3, "cylinder (0.1,0.9,1.5)")
	var oct := FractalParams.new(); oct.fold_shape = MandelboxShape.FoldShape.OCTAHEDRAL
	_de(1.2, -0.3, 0.8, oct, 0.1732051220721598, "octahedral (1.2,-0.3,0.8)")
	_de(0.5, 0.5, 0.5, oct, 4.1206878808877995e-2, "octahedral (0.5,0.5,0.5)")
	var hyb := FractalParams.new(); hyb.hybrid_mix = 0.5
	_de(0.1, 0.9, 1.5, hyb, 2.2852681154811514e-5, "hybrid 0.5 every 2nd (0.1,0.9,1.5)")
	_de(1.2, -0.3, 0.8, hyb, 3.7600167376069028e-3, "hybrid 0.5 every 2nd (1.2,-0.3,0.8)")
	# The hybrid fold is a fold all the way: far from the centre points still
	# escape (blending the box and abs folds' results cancelled there instead,
	# and filled all of space).
	for m in [0.25, 0.5, 0.75]:
		var hm := FractalParams.new(); hm.hybrid_mix = m
		check(DistanceEstimator.estimate_at(30.0, 4.0, -7.0, hm) > 1.0, "hybrid mix %s leaves the far field empty" % m)
		check(hm.bound_half() > 1.0 + 0.75 * (1.0 + m) / (1.0 - m), "and its bound grows with the mix (%s)" % hm.bound_half())
	check_eq(FractalParams.new().bound_half(), 2.0, "no hybrid: the site's cube of half-side 2")
	var hfull := FractalParams.new(); hfull.hybrid_mix = 1.0
	check_eq(hfull.bound_half(), 20.0, "the bound is capped at 20")
	var drift := FractalParams.new(); drift.scale_drift = 0.02
	_de(0.1, 0.9, 1.5, drift, 1.279908397497517e-4, "scale drift 0.02 (0.1,0.9,1.5)")
	_de(3, 0, 0, drift, 1.0000000119298762, "scale drift 0.02 (3,0,0)")
	for pair in [[cyl, "cylinder fold"], [oct, "octahedral fold"], [hyb, "hybrid mix"], [drift, "scale drift"]]:
		check(absf(DistanceEstimator.estimate(Vector3(0.1, 0.9, 1.5), pair[0])
				- DistanceEstimator.estimate(Vector3(0.1, 0.9, 1.5), d)) > 1e-7,
			"the %s changes the distance" % pair[1])
	# the hybrid's period only matters while the mix is on
	var every3 := FractalParams.new(); every3.hybrid_every = 3
	check_eq(DistanceEstimator.estimate(Vector3(1.2, -0.3, 0.8), every3), base,
		"Hybrid every alone (mix 0) changes nothing")
	# the folds keep the box fold's symmetry D(p) == D(-p)
	for q in [Vector3(0.7, 0.3, 0.9), Vector3(1.2, -0.3, 0.8)]:
		for f in [cyl, oct]:
			check_approx(DistanceEstimator.estimate(q, f), DistanceEstimator.estimate(-q, f),
				"fold %d: D(p) == D(-p) at %s" % [f.fold_shape, q], 1e-9)

	# --- dispatch: the shape row picks the estimator ---
	var as_kifs := FractalParams.new(); as_kifs.shape = FractalParams.Shape.KIFS
	check_eq(DistanceEstimator.estimate_at(1.2, -0.3, 0.8, as_kifs),
		KifsEstimator.estimate_at(1.2, -0.3, 0.8, as_kifs), "shape KIFS dispatches to KifsEstimator")
	var as_kl := FractalParams.new(); as_kl.shape = FractalParams.Shape.KLEINIAN
	check_eq(DistanceEstimator.estimate_at(1.2, -0.3, 0.8, as_kl),
		KleinianEstimator.estimate_at(1.2, -0.3, 0.8, as_kl), "shape Kleinian dispatches to KleinianEstimator")
	check_eq(DistanceEstimator.mandelbox_at(1.2, -0.3, 0.8, as_kifs), DistanceEstimator.estimate_at(1.2, -0.3, 0.8, d),
		"mandelbox_at ignores the shape row")
