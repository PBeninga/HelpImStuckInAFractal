extends "res://tests/test_case.gd"
## The KIFS CPU estimator: captured fixtures for each fold set and for the
## rotations and 4D knobs, and the geometric facts the defaults must honour —
## the Menger sponge's faces sit at +/-1, its first-level holes are empty, its
## solid corners are solid, and it has the cube's symmetry.


func _de(p: Vector3, params: ShapeParams, expected: float, label: String) -> void:
	var got := KifsEstimator.estimate_at(p.x, p.y, p.z, params)
	var tol := maxf(1e-9, 1e-5 * absf(expected))
	check(absf(got - expected) <= tol, "%s: expected %s got %s (tol %s)" % [label, expected, got, tol])


func _kifs() -> ShapeParams:
	var p := ShapeParams.new()
	p.shape = FractalParams.Shape.KIFS
	return p


func run() -> void:
	# --- the default: the Menger sponge (scale 3, coordinate fold, offset 1,1,1,0) ---
	var m := _kifs()
	check_approx(m.kifs_scale, 3.0, "scale defaults to 3")
	check_eq(m.kifs_fold, KifsEstimator.FoldSet.COORDINATE, "the coordinate fold by default")
	_de(Vector3(1.2, -0.3, 0.8), m, 0.20000004768371582, "menger (1.2,-0.3,0.8)")
	_de(Vector3(3, 0, 0), m, 2.0275875100994063, "menger (3,0,0)")
	_de(Vector3(0.1, 0.9, 1.5), m, 0.5, "menger (0.1,0.9,1.5)")
	check(KifsEstimator.estimate_at(0.5, 0.5, 0.5, m) < 1e-9, "a corner cell is solid")
	check_approx(KifsEstimator.estimate_at(1.5, 0.2, -0.4, m), 0.5, "the +x face is at x = 1", 1e-4)
	# The first-level holes: the middle third of two coordinates is drilled out.
	check(KifsEstimator.estimate_at(0.0, 0.0, 0.9, m) > 0.3, "the central tunnel along z is empty")
	check(KifsEstimator.estimate_at(0.0, 0.0, 0.0, m) > 0.3, "the centre is empty")
	for q in [Vector3(0.7, 0.2, 0.9), Vector3(1.2, -0.3, 0.8)]:
		var dq := KifsEstimator.estimate_at(q.x, q.y, q.z, m)
		check_approx(KifsEstimator.estimate_at(-q.x, q.y, q.z, m), dq, "mirror in x at %s" % q, 1e-9)
		check_approx(KifsEstimator.estimate_at(q.y, q.z, q.x, m), dq, "cube symmetry (cycle) at %s" % q, 1e-9)

	# --- the other fold sets ---
	var s := _kifs(); s.kifs_fold = KifsEstimator.FoldSet.DIAGONAL; s.kifs_scale = 2.0
	_de(Vector3(1.2, -0.3, 0.8), s, 0.7511259758577316, "sierpinski (1.2,-0.3,0.8)")
	_de(Vector3(0.5, 0.5, 0.5), s, 0.30638578479824147, "sierpinski (0.5,0.5,0.5)")
	check(KifsEstimator.estimate_at(1.0, 1.0, 1.0, s) < 1e-6, "the tetrahedron's (1,1,1) vertex is on it")
	check(KifsEstimator.estimate_at(-1.0, -1.0, -1.0, s) > 0.5, "the opposite corner is not")
	var poly := _kifs(); poly.kifs_fold = KifsEstimator.FoldSet.POLYFOLD; poly.kifs_scale = 2.0
	_de(Vector3(1.2, -0.3, 0.8), poly, 0.2001221448106634, "polyfold k5 (1.2,-0.3,0.8)")
	_de(Vector3(0.5, 0.5, 0.5), poly, 5.30759802182777e-3, "polyfold k5 (0.5,0.5,0.5)")
	var poly3 := _kifs(); poly3.kifs_fold = KifsEstimator.FoldSet.POLYFOLD; poly3.kifs_scale = 2.0; poly3.kifs_poly_k = 3.0
	check(absf(KifsEstimator.estimate_at(0.5, 0.5, 0.5, poly3) - KifsEstimator.estimate_at(0.5, 0.5, 0.5, poly)) > 1e-6,
		"the polyfold's k changes the distance")

	# --- rotations, twist, w and the fourth offset ---
	var r := _kifs()
	r.kifs_rot1_xy = 20.0; r.kifs_rot2_yz = 10.0; r.kifs_twist = 5.0; r.w = 0.1; r.kifs_offset_3 = 0.5
	_de(Vector3(1.2, -0.3, 0.8), r, 0.11067921857572048, "rotated (1.2,-0.3,0.8)")
	_de(Vector3(0.1, 0.9, 1.5), r, 0.36204328557047155, "rotated (0.1,0.9,1.5)")
	var base := KifsEstimator.estimate_at(0.6, 0.2, 0.9, m)
	for knob in [&"kifs_rot1_xz", &"kifs_rot2_xy", &"kifs_twist"]:
		var k := _kifs()
		k.set(knob, 15.0)
		check(absf(KifsEstimator.estimate_at(0.6, 0.2, 0.9, k) - base) > 1e-6, "'%s' changes the distance" % knob)
	var off := _kifs(); off.kifs_offset_0 = 0.8
	check(absf(KifsEstimator.estimate_at(0.6, 0.2, 0.9, off) - base) > 1e-6, "the offset changes the distance")

	# --- the bound the renderer marches in covers the sponge ---
	check_approx(m.bound_half(), 2.598076, "bound_half is 1.5 |offset| for the default", 1e-5)
	var small := _kifs(); small.kifs_offset_0 = 0.1; small.kifs_offset_1 = 0.1; small.kifs_offset_2 = 0.1
	check_approx(small.bound_half(), 2.0, "and never under 2")
