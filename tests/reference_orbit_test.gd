extends "res://tests/test_case.gd"
## ReferenceOrbit: the camera's own orbit in 64-bit and the per-iteration record
## the perturbed shader reads. Its distance is the CPU estimator's, exactly (the
## loop is duplicated so the record can be taken beside it; this keeps it
## honest), its magnification never falls, and the folds it cannot perturb say so.


func run() -> void:
	for v in SurfaceFixture.variants():
		var name: String = v[0]
		var params: FractalParams = v[1]
		var s := SurfaceFixture.surface_from(params, v[2])
		for back in [1e-1, 1e-3, 1e-6]:
			var e := SurfaceFixture.backed(s, back)
			var o := ReferenceOrbit.build(params, e[0], e[1], e[2])
			check_eq(o.distance, DistanceEstimator.estimate_at(e[0], e[1], e[2], params),
				"%s, %s back: distance is the estimator's, exactly" % [name, back])
		var o0 := ReferenceOrbit.build(params, s[0], s[1], s[2])
		check_eq(o0.perturbable, v[3], "%s: perturbable is %s" % [name, v[3]])
		check(o0.mag.size() == 33 and o0.points.size() == 33 and o0.points64.size() == 132,
			"%s: 33 magnifications and points" % name)
		check(o0.a.size() == ReferenceOrbit.PERT_MAX and o0.d.size() == ReferenceOrbit.PERT_MAX
			and o0.rec64.size() == ReferenceOrbit.PERT_MAX * 16, "%s: PERT_MAX records" % name)
		check_eq(o0.eye, PackedFloat64Array([s[0], s[1], s[2]]), "%s: it remembers its 64-bit eye" % name)

	# the magnification never falls on the spec's fixtures (every factor is >= 1 there)
	for v in SurfaceFixture.variants():
		if not (v[0] in ["default box", "ice field", "terraces", "Menger", "Kleinian"]):
			continue
		var s := SurfaceFixture.surface_from(v[1], v[2])
		var o := ReferenceOrbit.build(v[1], s[0], s[1], s[2])
		var ok := o.mag[0] == 1.0
		for i in 32:
			ok = ok and o.mag[i + 1] >= o.mag[i]
		check(ok, "%s: mag starts at 1 and never falls (mag[32] %s)" % [v[0], o.mag[32]])

	# n: 32 for the Mandelbox, fewer for a KIFS eye whose orbit escapes
	var box := FractalParams.new()
	var e := CameraState.DEFAULT_EYE
	check_eq(ReferenceOrbit.build(box, e.x, e.y, e.z).n, 32, "the Mandelbox always runs 32 iterations")
	var kifs := FractalParams.new()
	kifs.shape = FractalParams.Shape.KIFS
	var ko := ReferenceOrbit.build(kifs, 3.2, 2.4, 1.9)
	check(ko.n < 32, "a KIFS eye outside the sponge escapes early (n %d)" % ko.n)
	check_eq(ko.mag[32], pow(3.0, 32), "and its mag is |scale|^i regardless of the escape")

	# record spot checks, default box at its surface (fold order 0, box fold)
	var s := SurfaceFixture.default_surface(box)
	var o := ReferenceOrbit.build(box, s[0], s[1], s[2])
	var x0 := [s[0], s[1], s[2], 0.0]
	check_eq(o.points[0], Vector4(s[0], s[1], s[2], 0.0), "X_0 is the eye (w 0)")
	check_eq(o.a[0], Vector4(-1.0 - x0[0], -1.0 - x0[1], -1.0 - x0[2], -1.0 - x0[3]), "a[0] is -L - X_0")
	check_eq(o.b[0], Vector4(1.0 - x0[0], 1.0 - x0[1], 1.0 - x0[2], 1.0 - x0[3]), "b[0] is L - X_0")
	var folded := x0.duplicate()
	DistanceEstimator._fold(folded, 1.0, 0, false, 0.0)
	check_eq(o.c[0], Vector4(folded[0], folded[1], folded[2], folded[3]), "c[0] is the sphere fold's input (post box fold)")
	check_eq(o.rec64[3 * 4 + 2] * absf(box.box_scale), o.mag[1], "mag[1] is the sphere factor d[0].z times |scale|")

	# KIFS: d[i] is X_{i+1}; Kleinian: d[i].y is the inversion factor and mag multiplies by it
	for i in mini(ko.n, ReferenceOrbit.PERT_MAX):
		check_eq(ko.d[i], ko.points[i + 1], "KIFS d[%d] is X_%d" % [i, i + 1])
	var kl := FractalParams.new()
	kl.shape = FractalParams.Shape.KLEINIAN
	var ls := SurfaceFixture.surface_from(kl, Vector3(2.5, 1.6, 1.2))
	var lo := ReferenceOrbit.build(kl, ls[0], ls[1], ls[2])
	var factors_ok := true
	for i in mini(ReferenceOrbit.PERT_MAX, lo.n):   # past a fixed point the record is empty
		factors_ok = factors_ok and is_equal_approx(lo.mag[i + 1], lo.mag[i] * lo.rec64[(i * 4 + 3) * 4 + 1])
	check(factors_ok, "Kleinian: mag[i+1] = mag[i] x d[i].y (the factor m)")
