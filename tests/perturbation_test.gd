extends "res://tests/test_case.gd"
## The keystone of the perturbation work (spec:
## docs/superpowers/specs/2026-10-09-perturbation-deep-zoom-design.md). The GPU
## works in 32-bit floats, which near the fractal sit on a grid about 1e-7 apart:
## a camera 1e-6 from the surface sees a view only a few grid steps wide.
## Perturbation iterates only each pixel's small offset from the camera's own
## orbit (computed in 64-bit on the CPU), so the offset keeps its precision.
##
## Three layers, all against PerturbationPort (a line-for-line port of the shader):
## 1. each step kind's difference formula, case by case, against the direct
##    difference (64-bit);
## 2. whole orbits in 64-bit: the perturbed offset is the direct orbit's
##    difference, iteration by iteration, for every shape variant, over random
##    offsets big enough to cross every kind of crease;
## 3. the march in emulated float32, the spec's table: the direct float32 march
##    gets under 30% of rays right at 1e-6 (today's failure), the perturbed one
##    (per-ray handoff at PERT_HANDOFF) at least 90% at every depth. Prints the
##    table (lines start with MEASURED) for the viz's Measured tab;
## 4. where the 64-bit reference march itself stops hitting, per fixture, down to
##    1e-12 (lines start with REFERENCE FLOOR): data for the iteration-floor follow-up.

const DEPTHS := [1e-5, 1e-6, 1e-7]
## The march budget: the shader's default 96 + 32, every step at 32 iterations.
const STEPS := 128
## Two hits agree when their distances differ by under 0.1% (about one pixel's
## depth footprint in an 800-pixel-high 40° view).
const AGREE_T := 1e-3
## Random offsets per shape variant in the algebra check.
const SAMPLES := 48


func run() -> void:
	_check_emulation()
	_check_cases()
	_check_algebra()
	_check_agreement()
	_print_reference_floor()


# ------------------------------------------------------------- 0. the emulation itself

func _check_emulation() -> void:
	var p := PerturbationPort.new(FractalParams.new(), PackedFloat64Array([0.0, 0.0, 0.0]), true)
	check_eq(p.r(1.0 + 1e-8), 1.0, "r() drops what a 32-bit float cannot hold (1 + 1e-8 is 1)")
	check_eq(p.r(0.1), 0.10000000149011612, "and rounds 0.1 to its 32-bit value")
	check_eq(p.r(0.1), float(Vector4(0.1, 0.0, 0.0, 0.0).x), "the value a Vector4 (the record's type) holds")
	p.f32 = false
	check_eq(p.r(1.0 + 1e-8), 1.0 + 1e-8, "f32 = false leaves 64-bit values alone")


# ------------------------------------------------------------- 1. each crossing case

func _check_cases() -> void:
	var p := PerturbationPort.new(FractalParams.new(), PackedFloat64Array([0.0, 0.0, 0.0]), false)

	# clamp folds: all nine side pairs of X and P against [-1, 1]
	for x in [-1.5, 0.2, 1.5]:
		for q in [-1.25, 0.5, 1.75]:
			var want: float = (2.0 * clampf(q, -1.0, 1.0) - q) - (2.0 * clampf(x, -1.0, 1.0) - x)
			check_approx(p.pert_clamp1(q - x, -1.0 - x, 1.0 - x, "clamp"), want,
				"clamp fold, X %s -> P %s" % [x, q], 1e-12)

	# the KIFS abs fold (crease at 0, nothing above)
	for x in [-0.7, 0.4]:
		for q in [-0.3, 0.9]:
			var got: float = p.pert_abs([q - x, 0.0, 0.0, 0.0], [-x, 0.0, 0.0, 0.0])[0]
			check_approx(got, absf(q) - absf(x), "abs fold, X %s -> P %s" % [x, q], 1e-12)

	# sort compare-and-swap: neither, both, only the pixel, only the reference
	for pair in [[[2.0, 1.0], [2.5, 0.5]], [[1.0, 2.0], [0.5, 2.5]],
			[[2.0, 1.9], [1.8, 2.1]], [[1.9, 2.0], [2.1, 1.8]]]:
		var x: Array = pair[0]
		var q: Array = pair[1]
		var got := p.pert_swap(q[0] - x[0], q[1] - x[1], x[0] - x[1])
		var sx := [maxf(x[0], x[1]), minf(x[0], x[1])]
		var sq := [maxf(q[0], q[1]), minf(q[0], q[1])]
		check(absf(got[0] - (sq[0] - sx[0])) < 1e-12 and absf(got[1] - (sq[1] - sx[1])) < 1e-12,
			"sort swap, X %s -> P %s (got %s)" % [x, q, got])

	# diagonal reflection: neither, both, only the pixel, only the reference
	for pair in [[[1.0, 0.5], [1.2, 0.1]], [[-1.0, -0.5], [-1.2, -0.1]],
			[[0.3, -0.2], [0.1, -0.4]], [[-0.3, 0.2], [-0.1, 0.4]]]:
		var x: Array = pair[0]
		var q: Array = pair[1]
		var got := p.pert_flip(q[0] - x[0], q[1] - x[1], x[0] + x[1])
		var fx := _flip(x)
		var fq := _flip(q)
		check(absf(got[0] - (fq[0] - fx[0])) < 1e-12 and absf(got[1] - (fq[1] - fx[1])) < 1e-12,
			"diagonal fold, X %s -> P %s (got %s)" % [x, q, got])

	# Menger correction, t = 2: z < -1 gains 2
	for xz in [-1.5, 0.5]:
		for qz in [-1.2, 0.2]:
			var want: float = (qz + (2.0 if qz < -1.0 else 0.0)) - (xz + (2.0 if xz < -1.0 else 0.0))
			check_approx(p.pert_menger(qz - xz, xz + 1.0, 2.0), want,
				"Menger correction, X_z %s -> P_z %s" % [xz, qz], 1e-12)

	# sphere fold, min_radius 0.7, fixed_radius 1: all nine regime pairs
	var mr2 := 0.49
	var fr2 := 1.0
	for xa in [0.5, 0.85, 1.3]:
		for qa in [0.5, 0.85, 1.3]:
			var x := [xa, 0.03, 0.0, 0.0]
			var q := [qa, 0.04, 0.01, 0.0]
			var x2: float = xa * xa + 0.0009
			var q2: float = qa * qa + 0.0016 + 0.0001
			var mx := _sphere_factor(x2, mr2, fr2)
			var mq := _sphere_factor(q2, mr2, fr2)
			var dl := [q[0] - x[0], q[1] - x[1], q[2] - x[2], 0.0]
			var got := p.pert_sphere(dl, 1.0, x, x2 - mr2, x2 - fr2, mr2, fr2, "sphere")
			var err := 0.0
			for j in 4:
				err = maxf(err, absf(got[0][j] - (mq * q[j] - mx * x[j])))
			check(err < 1e-12, "sphere fold, |X| %s -> |P| %s (error %s)" % [xa, qa, err])
			check_approx(got[1], mq, "and the pixel's dz takes its own factor", 1e-12)

	# cylinder fold (L = 1, the default fold_limit): xy radius inside/outside pairs
	for xr in [0.6, 1.4]:
		for qr in [0.7, 1.3]:
			var x0: float = 0.8 * xr
			var x1: float = 0.6 * xr
			var q0: float = 0.79 * qr
			var q1: float = 0.613 * qr
			var rx := sqrt(x0 * x0 + x1 * x1)
			var rq := sqrt(q0 * q0 + q1 * q1)
			var fx := (2.0 - rx) / rx if rx > 1.0 else 1.0
			var fq := (2.0 - rq) / rq if rq > 1.0 else 1.0
			var got := p.pert_cylinder(q0 - x0, q1 - x1, x0, x1, rx - 1.0)
			check(absf(got[0] - (fq * q0 - fx * x0)) < 1e-12 and absf(got[1] - (fq * q1 - fx * x1)) < 1e-12,
				"cylinder fold, r %s -> %s (got %s)" % [xr, qr, got])


func _flip(v: Array) -> Array:
	return [-v[1], -v[0]] if v[0] + v[1] < 0.0 else [v[0], v[1]]


func _sphere_factor(r2: float, mr2: float, fr2: float) -> float:
	if r2 < mr2:
		return fr2 / mr2
	if r2 < fr2:
		return fr2 / r2
	return 1.0
# ------------------------------------------------------------- 2. whole orbits, 64-bit

## For every perturbable variant: an eye 1e-3 short of its surface, the reference
## orbit X there, and SAMPLES random offsets of 1e-7 to 1e-1 (big enough to cross
## every kind of crease). In 64-bit the perturbed offset after each iteration must
## be P_i - X_i, where P is the direct orbit of eye + off; the tolerance allows
## rounding (about 1e-16 x the magnification) but not a wrong formula (off by
## about the offset itself). Then every crossing kind must have happened.
func _check_algebra() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var by_shape := {}
	for v in SurfaceFixture.variants():
		if not v[3]:
			continue
		var name: String = v[0]
		var params: FractalParams = v[1]
		var s := SurfaceFixture.surface_from(params, v[2])
		var e := SurfaceFixture.backed(s, 1e-3)
		var X := ReferenceOrbitDraft.build(params, e[0], e[1], e[2])
		var k := mini(ReferenceOrbitDraft.PERT_MAX, X.n)
		var port := PerturbationPort.new(params, e, false)
		port.handoff = INF   # perturb all k iterations however large the offset grows
		var worst := 0.0
		var worst_de := 0.0
		for _j in SAMPLES:
			var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var size := pow(10.0, rng.randf_range(-7.0, -1.0))
			var off := [dir.x * size, dir.y * size, dir.z * size]
			var P := ReferenceOrbitDraft.build(params, e[0] + off[0], e[1] + off[1], e[2] + off[2])
			port.trace = []
			port.tracing = true
			var dp := port.de_pert(X, k, off, 32)
			for i in port.trace.size():
				if i + 1 > P.n:
					break
				var dl: Array = port.trace[i]
				var err := 0.0
				var dmax := 0.0
				var xmax := 1.0
				for c in 4:
					var xv: float = X.points64[(i + 1) * 4 + c]
					var pv: float = P.points64[(i + 1) * 4 + c]
					err = maxf(err, absf(dl[c] - (pv - xv)))
					dmax = maxf(dmax, absf(pv - xv))
					xmax = maxf(xmax, maxf(absf(xv), absf(pv)))
				var tol := 1e-12 * X.mag[i + 1] * xmax + 1e-9 * dmax
				worst = maxf(worst, err / tol)
			worst_de = maxf(worst_de, absf(dp - P.distance) / maxf(absf(P.distance), 1e-300))
		check(worst <= 1.0, "%s: the 64-bit perturbed offset is the direct orbit's, iteration by iteration (worst %s of tolerance)" % [name, worst])
		# after the handoff both orbits run on in 64-bit through up to 32 - k more
		# iterations, which amplify round-off chaotically (measured up to 7e-5), so the
		# bar here is the march's own agreement, 0.1%
		check(worst_de <= AGREE_T, "%s: and the estimate after the handoff is the direct one within 0.1%% (worst relative difference %s)" % [name, worst_de])
		var merged: Dictionary = by_shape.get(params.shape, {})
		for kind in port.crossings:
			merged[kind] = int(merged.get(kind, 0)) + int(port.crossings[kind])
		by_shape[params.shape] = merged
	print("crossings by shape: ", by_shape)
	var want := {
		FractalParams.Shape.MANDELBOX: ["clamp", "sphere", "cylinder"],
		FractalParams.Shape.KIFS: ["abs", "sort_p", "sort_r", "menger", "diag_p", "diag_r"],
		FractalParams.Shape.KLEINIAN: ["clamp", "inversion"],
	}
	for shape in want:
		for kind in want[shape]:
			check(int(by_shape.get(shape, {}).get(kind, 0)) > 0,
				"shape %d: the sample crossed a '%s' crease somewhere (coverage)" % [shape, kind])
# ------------------------------------------------------------- 3. the march in float32

## The spec's fixtures: the default box, the ice-field and terraces saves (Julia
## mode), a KIFS (Menger) and a Kleinian. [name, params, surface point].
func _fixtures() -> Array:
	var box := FractalParams.new()
	var out := [["default box", box, SurfaceFixture.default_surface(box)]]
	for v in SurfaceFixture.variants():
		if v[0] in ["ice field", "terraces", "Menger", "Kleinian"]:
			out.append([v[0], v[1], SurfaceFixture.surface_from(v[1], v[2])])
	return out


## 27 directions within the 40° field of view around forward f: a 3 × 3 grid of
## screen offsets at three field fractions (the whole view, its middle third, its
## middle ninth), nudged off-centre so no two coincide. 32-bit, as the GPU's are.
func _fan(f: Vector3) -> Array:
	var right := f.cross(Vector3(0, 0, 1)).normalized()
	var up := right.cross(f).normalized()
	var out := []
	for frac in [1.0, 1.0 / 3.0, 1.0 / 9.0]:
		for ia in [-1, 0, 1]:
			for ib in [-1, 0, 1]:
				var du: float = (ia + 0.37) * 0.5 * frac * FractalView.TAN_HALF_FOV
				var dv: float = (ib + 0.21) * 0.5 * frac * FractalView.TAN_HALF_FOV
				var dir := (f + right * du + up * dv).normalized()
				out.append([dir.x, dir.y, dir.z])
	return out


## [class, t]: class 0 a hit (estimate under eps × t), 1 beyond (t past 10 d),
## 2 out of steps. The 64-bit reference: DistanceEstimator at o + dir t in doubles.
func _march_ref(o: PackedFloat64Array, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := params.precision / params.detail
	var t := 0.0
	for _i in STEPS:
		var de := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if de < eps * t:
			return [0, t]
		t += de
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


## Today's shader in float32: the position eye + dir t formed in 32 bits.
func _march_direct(port: PerturbationPort, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := port.u(params.precision / params.detail)
	var t := 0.0
	for _i in STEPS:
		var pos := [port.r(port.eye[0] + port.r(dir[0] * t)), port.r(port.eye[1] + port.r(dir[1] * t)),
			port.r(port.eye[2] + port.r(dir[2] * t))]
		var de := port.de_direct(pos, 32)
		if de < port.r(eps * t):
			return [0, t]
		t = port.r(t + de)
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


## The perturbed shader in float32: only the offset dir t is formed.
func _march_pert(port: PerturbationPort, orbit, k: int, dir: Array, params: FractalParams, d: float) -> Array:
	var eps := port.u(params.precision / params.detail)
	var t := 0.0
	for _i in STEPS:
		var off := [port.r(dir[0] * t), port.r(dir[1] * t), port.r(dir[2] * t)]
		var de := port.de_pert(orbit, k, off, 32)
		if de < port.r(eps * t):
			return [0, t]
		t = port.r(t + de)
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


func _agree(got: Array, want: Array) -> bool:
	return got[0] == want[0] and (got[0] != 0 or absf(got[1] - want[1]) <= AGREE_T * want[1])


## Task 4 replaces these two with FractalParams.pert_iters / floor_pert.
func _records(orbit) -> int:
	return mini(ReferenceOrbitDraft.PERT_MAX, orbit.n)


func _floor_pert(orbit, params: FractalParams) -> float:
	var eps := params.precision / params.detail
	var kk := mini(ReferenceOrbitDraft.PERT_MAX, orbit.n)
	var x: Vector4 = orbit.points[kk]
	var m := maxf(maxf(absf(x.x), absf(x.y)), maxf(absf(x.z), absf(x.w)))
	return FractalParams.ulp32(m) / (FractalParams.ZOOM_FLOOR_DIVISOR * eps * orbit.mag[kk])


## The perturbed march must agree on at least 90% at every cell. The direct one's
## "under 30%" is checked at 1e-6 where the reference hits on at least half the
## rays: below a fixture's 32-iteration floor (the terraces at 1e-6) every ray of
## every march runs out of steps, and the direct march "agrees" on that trivially.
func _check_agreement() -> void:
	print("MEASURED | fixture | d | near | records | floor_pert | reference hit/beyond/none | direct agrees | perturbed agrees")
	for fx in _fixtures():
		var name: String = fx[0]
		var params: FractalParams = fx[1]
		var s: Array = fx[2]
		var fan := _fan(Vector3(s[3], s[4], s[5]))
		for dd in DEPTHS:
			var d: float = dd
			var e := SurfaceFixture.backed(s, d)
			var orbit := ReferenceOrbitDraft.build(params, e[0], e[1], e[2])
			var near := orbit.distance
			var k := _records(orbit)
			var fp := _floor_pert(orbit, params)
			var port := PerturbationPort.new(params, e, true)
			var classes := [0, 0, 0]
			var direct := 0
			var pert := 0
			for dir in fan:
				var want := _march_ref(e, dir, params, d)
				classes[want[0]] += 1
				if _agree(_march_direct(port, dir, params, d), want):
					direct += 1
				if _agree(_march_pert(port, orbit, k, dir, params, d), want):
					pert += 1
			print("MEASURED | %s | %s | %s | %d | %s | %d/%d/%d | %d%% | %d%%" % [name, d, near, k, fp,
				classes[0], classes[1], classes[2], direct * 100 / fan.size(), pert * 100 / fan.size()])
			# exact comparison: is_equal_approx's tolerance never falls below 1e-5, so it
			# would call 1e-5, 1e-6 and 1e-7 all equal
			if d == 1e-6 and classes[0] * 2 >= fan.size():
				check(direct * 10 < fan.size() * 3,
					"%s at 1e-6: today's float32 march gets under 30%% right (%d of %d)" % [name, direct, fan.size()])
			check(pert * 10 >= fan.size() * 9,
				"%s at %s: the perturbed float32 march gets at least 90%% right (%d of %d)" % [name, d, pert, fan.size()])


# ------------------------------------------------------------- 4. where the reference stops hitting

## A 64-bit march: [class, t] as _march_ref, with a step budget of its own.
func _march_budget(o: PackedFloat64Array, dir: Array, params: FractalParams, d: float, steps: int) -> Array:
	var eps := params.precision / params.detail
	var t := 0.0
	for _i in steps:
		var de := DistanceEstimator.estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if de < eps * t:
			return [0, t]
		t += de
		if t > 10.0 * d:
			return [1, t]
	return [2, t]


## Where 32 iterations stop resolving, measured rather than guarded (the spec's
## part 5). Everything here is the 64-bit CPU estimator: no float32, no
## perturbation. Hit test estimate < eps × t, eps = precision / detail (the
## fixtures have detail 1 and no falloff, so `near` plays no part and nothing is
## clamped); 32 iterations every step; a step budget of 128 (the shader's
## default) and of 2000 (to tell "out of budget" from "never converges"). Two
## views of it, because the floor depends on where the camera is:
##   FAN: each fixture's surface point (refined along its ray until the estimate
##     is under 1e-13, or as low as round-off lets it go), the 27-ray fan from a
##     camera d back: hits within 128 / within 2000 steps.
##   VIEW9: the default box, 9 rays near the middle of the default view (a 3 × 3
##     grid at 0.1 and at 0.3 of the half field of view), each backed off d from
##     its own hit: the deepest d (down from 1e-4) at which that ray still hits
##     within 10% of d.
func _print_reference_floor() -> void:
	var depths := [1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11, 1e-12]
	print("REFERENCE FLOOR | 64-bit march, hit when estimate < eps*t (eps = precision/detail), 32 iterations, near unused (detail falloff 0), budgets 128 / 2000 steps")
	for fx in _fixtures():
		var params: FractalParams = fx[1]
		var s0: Array = fx[2]
		var s := SurfaceFixture.along(params, SurfaceFixture.backed(s0, 1e-3), Vector3(s0[3], s0[4], s0[5]), 1e-13)
		var e0 := PackedFloat64Array([s[0], s[1], s[2]])
		var line := "REFERENCE FLOOR | FAN %s (surface estimate %s, eps %s) |" % [fx[0],
			DistanceEstimator.estimate_at(s[0], s[1], s[2], params), params.precision / params.detail]
		var fan := _fan(Vector3(s[3], s[4], s[5]))
		for dd in depths:
			var d: float = dd
			var e := SurfaceFixture.backed(s, d)
			var h128 := 0
			var h2000 := 0
			for dir in fan:
				if _march_budget(e, dir, params, d, 128)[0] == 0:
					h128 += 1
				if _march_budget(e, dir, params, d, 2000)[0] == 0:
					h2000 += 1
			line += " %s: %d / %d |" % [d, h128, h2000]
		print(line)
	var box := FractalParams.new()
	var cam := CameraState.make_default()
	var ce := PackedFloat64Array([cam.eye().x, cam.eye().y, cam.eye().z])   # (eye64() arrives in Task 2)
	for spread in [0.1, 0.3]:
		var deepest := []
		for ia in [-1, 0, 1]:
			for ib in [-1, 0, 1]:
				var dir: Vector3 = (cam.forward() + cam.right() * (ia * spread * 1.6 * FractalView.TAN_HALF_FOV)
					+ cam.up() * (ib * spread * FractalView.TAN_HALF_FOV)).normalized()
				var sp := SurfaceFixture.along(box, ce, dir, 1e-13)
				var last := "none"
				for dd in depths:
					var d: float = dd
					var r := _march_budget(SurfaceFixture.backed(sp, d), [sp[3], sp[4], sp[5]], box, d, 128)
					if r[0] == 0 and absf(r[1] / d - 1.0) < 0.1:
						last = str(d)
					else:
						break
				deepest.append(last)
		print("REFERENCE FLOOR | VIEW9 default box, spread %s of the half field: deepest d that still hits within 10%%, per ray: %s" % [spread, deepest])
