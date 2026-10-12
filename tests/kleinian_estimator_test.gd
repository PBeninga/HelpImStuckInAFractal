extends "res://tests/test_case.gd"
## The pseudo-Kleinian CPU estimator: captured fixtures, the knobs each
## matter, the box fold's mirror symmetry at the defaults (no shift), and the
## view distance that ends its rays.


func _de(p: Vector3, params: ShapeParams, expected: float, label: String) -> void:
	var got := KleinianEstimator.estimate_at(p.x, p.y, p.z, params)
	var tol := maxf(1e-9, 1e-5 * absf(expected))
	check(absf(got - expected) <= tol, "%s: expected %s got %s (tol %s)" % [label, expected, got, tol])


func _kl() -> ShapeParams:
	var p := ShapeParams.new()
	p.shape = FractalParams.Shape.KLEINIAN
	return p


func run() -> void:
	var k := _kl()
	_de(Vector3(1.2, -0.3, 0.8), k, 0.26070721005920766, "default (1.2,-0.3,0.8)")
	_de(Vector3(0.5, 0.5, 0.5), k, 0.20012747383496637, "default (0.5,0.5,0.5)")
	_de(Vector3(0.1, 0.9, 1.5), k, 0.1502586040758134, "default (0.1,0.9,1.5)")
	var k2 := _kl(); k2.kleinian_shift_0 = 0.1; k2.kleinian_radius = 1.2; k2.w = 0.2
	_de(Vector3(1.2, -0.3, 0.8), k2, 0.27111422070432895, "shifted (1.2,-0.3,0.8)")
	_de(Vector3(0.1, 0.9, 1.5), k2, 0.0867598083840418, "shifted (0.1,0.9,1.5)")

	for q in [Vector3(0.7, 0.3, 0.9), Vector3(1.2, -0.3, 0.8)]:
		var dq := KleinianEstimator.estimate_at(q.x, q.y, q.z, k)
		check_approx(KleinianEstimator.estimate_at(-q.x, -q.y, -q.z, k), dq, "D(p) == D(-p) at %s" % q, 1e-9)
		check(dq >= 0.0, "the distance is unsigned at %s" % q)

	var base := KleinianEstimator.estimate_at(0.6, 0.2, 0.9, k)
	for knob in [[&"kleinian_box_0", 0.4], [&"kleinian_radius", 1.3], [&"kleinian_shift_2", 0.2],
			[&"kleinian_thickness", 0.1]]:
		var c := _kl()
		c.set(knob[0], knob[1])
		check(absf(KleinianEstimator.estimate_at(0.6, 0.2, 0.9, c) - base) > 1e-6, "'%s' changes the distance" % knob[0])

	# --- the view distance: only the Kleinian has one ---
	check_approx(k.view_distance(), 10.0, "the Kleinian's rays stop at 10 by default")
	check_approx(ShapeParams.new().view_distance(), 0.0, "the Mandelbox's do not stop early")
	check_eq(k.bound_half(), FractalParams.KLEINIAN_BOUND, "the Kleinian has no real bounding cube")
	check(not k.julia_enabled(), "no Julia marker off the Mandelbox")
	k.julia_all = true
	check(not k.julia_enabled(), "not even with Julia (all) left on")
