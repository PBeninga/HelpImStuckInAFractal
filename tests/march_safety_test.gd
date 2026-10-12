extends "res://tests/test_case.gd"
## Each shape and option is safe to sphere-trace: a ray marched with full
## steps never jumps over a surface that the same ray marched with quarter
## steps finds. (A distance estimate that overshoots shows up as a full step
## spanning the quarter-step hit.) Steps within ten hit thresholds of the hit
## are allowed: those graze the surface, they do not tunnel through it. Each
## configuration must also be hit at all, so no default is empty space.

const RAYS := 40
const HIT := 1e-4   # the hit threshold, x max(t, 1)


func _march(p: ShapeParams, ro: Vector3, rd: Vector3, frac: float, tmax: float) -> Array:
	var t := 0.0
	var steps := []
	for i in 3000:
		var x := ro + rd * t
		var d := DistanceEstimator.estimate_at(x.x, x.y, x.z, p)
		if d < HIT * maxf(t, 1.0):
			return [t, steps]
		steps.append([t, d * frac])
		t += d * frac
		if t > tmax:
			break
	return [INF, steps]


func _safe(label: String, p: ShapeParams, radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hits := 0
	var jumps := 0
	for i in RAYS:
		var ro := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * radius
		var target := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8
		var rd := (target - ro).normalized()
		var tq: float = _march(p, ro, rd, 0.25, 2.0 * radius)[0]
		if tq == INF:
			continue
		hits += 1
		var slack := 10.0 * HIT * maxf(tq, 1.0)
		for s in _march(p, ro, rd, 1.0, 2.0 * radius)[1]:
			if s[0] < tq - slack and s[0] + s[1] > tq + slack:
				jumps += 1
				break
	check(hits > 0, "%s: some rays hit (%d of %d)" % [label, hits, RAYS])
	check_eq(jumps, 0, "%s: no full step jumps a surface" % label)


func run() -> void:
	_safe("Mandelbox", ShapeParams.new(), 4.0)
	var p := ShapeParams.new(); p.fold_shape = MandelboxShape.FoldShape.CYLINDER
	_safe("cylinder fold", p, 4.0)
	p = ShapeParams.new(); p.fold_shape = MandelboxShape.FoldShape.OCTAHEDRAL
	_safe("octahedral fold", p, 4.0)
	for c in [[1, 0.5], [2, 0.75], [3, 1.0]]:
		p = ShapeParams.new(); p.hybrid_every = c[0]; p.hybrid_mix = c[1]
		_safe("hybrid every %d mix %s" % c, p, 4.0)
	p = ShapeParams.new(); p.scale_drift = 0.03
	_safe("scale drift", p, 4.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.KIFS
	_safe("Menger", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.KIFS; p.kifs_fold = KifsEstimator.FoldSet.DIAGONAL; p.kifs_scale = 2.0
	_safe("Sierpinski", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.KIFS; p.kifs_fold = KifsEstimator.FoldSet.POLYFOLD
	_safe("polyfold", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.KIFS
	p.kifs_rot1_xy = 20.0; p.kifs_rot2_yz = 10.0; p.kifs_twist = 5.0
	_safe("rotated Menger", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.KLEINIAN
	_safe("Kleinian", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.MANDELBULB
	_safe("Mandelbulb", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.MANDELBULB; p.mandelbulb_power = 3.0
	_safe("Mandelbulb power 3", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.MANDELBULB; p.mandelbulb_power = 16.0
	_safe("Mandelbulb power 16", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.MANDELBULB
	p.mandelbulb_phase_theta = 40.0; p.mandelbulb_phase_phi = 30.0
	_safe("phased Mandelbulb", p, 3.0)
	p = ShapeParams.new(); p.shape = FractalParams.Shape.MANDELBULB; p.mandelbulb_julia = true
	_safe("Julia Mandelbulb", p, 3.0)
