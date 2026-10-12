class_name PerturbationPort
extends RefCounted
## A GDScript port of the shader's perturbed march (src/fractal/perturbation.gdshaderinc)
## and of its direct estimate (de() and the per-shape orbit loops in
## mandelbox.gdshader, kifs.gdshaderinc, kleinian.gdshaderinc), for
## tests/perturbation_test.gd. Each function mirrors the GLSL function of the same
## name; keep the two in step.
##
## f32 = true runs it as the GPU would: every arithmetic result is rounded to the
## nearest 32-bit float (r()) and every uniform is read as a 32-bit float (u()).
## A sum, difference, product, quotient or square root of two 32-bit floats worked
## out in 64-bit and rounded once is exactly the 32-bit IEEE result, so for those
## operations the emulation is exact (cos, sin and pow are the 64-bit results
## rounded, close to a GPU's but not bit-identical). f32 = false runs the same
## code in 64-bit: the algebra check.
##
## 4-vectors are Arrays of four floats. `orbit` is the reference orbit (its
## a, b, c, d, points, rec64, points64) and `k` its pert_iters (the records
## available, min(PERT_MAX, n)): together they stand for the pert_* uniforms
## (orbit.points[0 .. PERT_MAX] is pert_x). Octahedral folds and the polyfold are not
## ported (they are never perturbed).

const PLANES := DistanceEstimator.PLANES
## The shader's PERT_HANDOFF (perturbation.gdshaderinc): a ray hands off once |dl| reaches it.
const PERT_HANDOFF := 0.1

var f32 := true
var params: ShapeParams
## The handoff radius de_pert uses: PERT_HANDOFF, or INF for the algebra check
## (the formulas are exact at any size, and large offsets exercise every crossing).
var handoff := PERT_HANDOFF
## The shader's `eye` uniform: the 64-bit eye, rounded when f32.
var eye: Array = [0.0, 0.0, 0.0]
## How many times the pixel and the reference fell on different sides of a
## crease, by kind: "clamp", "abs", "sort_p", "sort_r", "diag_p", "diag_r",
## "menger", "sphere", "cylinder", "inversion". The algebra check's coverage.
var crossings := {}
## While true, each perturbed iteration appends a copy of the offset to `trace`.
var tracing := false
var trace: Array = []

var _buf := PackedFloat32Array([0.0])


## `p` is the scene; the port runs its first shape, at the identity placement.
func _init(p: FractalParams, eye64: PackedFloat64Array, use_f32: bool) -> void:
	params = p.shape()
	f32 = use_f32
	eye = [r(eye64[0]), r(eye64[1]), r(eye64[2])]


## One arithmetic result, rounded to the nearest 32-bit float when f32.
func r(x: float) -> float:
	if not f32:
		return x
	_buf[0] = x
	return _buf[0]


## A uniform's value as the shader holds it.
func u(x: float) -> float:
	return r(x)


func _count(kind: String) -> void:
	crossings[kind] = int(crossings.get(kind, 0)) + 1


# ------------------------------------------------------------- vectors, in GLSL's order

func add4(a: Array, b: Array) -> Array:
	return [r(a[0] + b[0]), r(a[1] + b[1]), r(a[2] + b[2]), r(a[3] + b[3])]


func scale4(s: float, a: Array) -> Array:
	return [r(s * a[0]), r(s * a[1]), r(s * a[2]), r(s * a[3])]


## dot(a, b) = ((a.x b.x + a.y b.y) + a.z b.z) + a.w b.w
func dot4(a: Array, b: Array) -> float:
	return r(r(r(r(a[0] * b[0]) + r(a[1] * b[1])) + r(a[2] * b[2])) + r(a[3] * b[3]))


func dot2(a0: float, a1: float, b0: float, b1: float) -> float:
	return r(r(a0 * b0) + r(a1 * b1))


func length4(a: Array) -> float:
	return r(sqrt(dot4(a, a)))


# ------------------------------------------------------------- the record as the shader reads it

## pert_a..d[i] (32-bit) when f32, the 64-bit copy otherwise. slot 0..3 = a..d.
func rec(orbit, i: int, slot: int) -> Array:
	if f32:
		var arrs := [orbit.a, orbit.b, orbit.c, orbit.d]
		var v: Vector4 = arrs[slot][i]
		return [v.x, v.y, v.z, v.w]
	var base := (i * 4 + slot) * 4
	return [orbit.rec64[base], orbit.rec64[base + 1], orbit.rec64[base + 2], orbit.rec64[base + 3]]


## X_i (pert_x[i]).
func point(orbit, i: int) -> Array:
	if f32:
		var v: Vector4 = orbit.points[i]
		return [v.x, v.y, v.z, v.w]
	return [orbit.points64[i * 4], orbit.points64[i * 4 + 1], orbit.points64[i * 4 + 2], orbit.points64[i * 4 + 3]]


# ------------------------------------------------------------- the direct estimate (today's shader)

## mb_rot_plane(p, a, b, deg): a' = a cos - b sin, b' = a sin + b cos.
func rot_plane(p: Array, ia: int, ib: int, deg: float) -> Array:
	var rad := r(u(deg) * r(PI / 180.0))
	var c := r(cos(rad))
	var s := r(sin(rad))
	var pa: float = p[ia]
	var pb: float = p[ib]
	var q := p.duplicate()
	q[ia] = r(r(pa * c) - r(pb * s))
	q[ib] = r(r(pa * s) + r(pb * c))
	return q


func mb_rotating() -> bool:
	return (absf(params.iter_rot_xy) + absf(params.iter_rot_xz) + absf(params.iter_rot_xw)
		+ absf(params.iter_rot_yz) + absf(params.iter_rot_yw) + absf(params.iter_rot_zw)) > 1e-6


func mb_iter_rotate(p: Array) -> Array:
	p = rot_plane(p, 0, 1, params.iter_rot_xy)
	p = rot_plane(p, 0, 2, params.iter_rot_xz)
	p = rot_plane(p, 0, 3, params.iter_rot_xw)
	p = rot_plane(p, 1, 2, params.iter_rot_yz)
	p = rot_plane(p, 1, 3, params.iter_rot_yw)
	p = rot_plane(p, 2, 3, params.iter_rot_zw)
	return p


## clamp(p, lo, hi) * 2.0 - p (the doubling is exact).
func _clamp_fold(p: Array, lo: float, hi: float) -> Array:
	return [r(clampf(p[0], lo, hi) * 2.0 - p[0]), r(clampf(p[1], lo, hi) * 2.0 - p[1]),
		r(clampf(p[2], lo, hi) * 2.0 - p[2]), r(clampf(p[3], lo, hi) * 2.0 - p[3])]


## mb_fold(p, i): the hybrid fold on a hybrid iteration, else the cylinder or box fold.
func mb_fold(p: Array, i: int) -> Array:
	var L := u(params.fold_limit)
	if params.hybrid_mix > 0.0:
		var every := maxi(params.hybrid_every, 1)
		if i % every == every - 1:
			var mix := u(params.hybrid_mix)
			var lo := r(-L * r(1.0 - mix))
			var hi := r(r(L + mix) / maxf(r(1.0 - mix), u(1e-6)))
			return _clamp_fold(p, lo, hi)
	if params.fold_shape == MandelboxShape.FoldShape.CYLINDER:
		var q := p.duplicate()
		var rr := r(sqrt(dot2(p[0], p[1], p[0], p[1])))
		if rr > L:
			var f := r(r(r(2.0 * L) - rr) / rr)
			q[0] = r(q[0] * f)
			q[1] = r(q[1] * f)
		q[2] = r(clampf(p[2], -L, L) * 2.0 - p[2])
		q[3] = r(clampf(p[3], -L, L) * 2.0 - p[3])
		return q
	assert(params.fold_shape == MandelboxShape.FoldShape.BOX, "the octahedral fold is not ported")
	return _clamp_fold(p, -L, L)


## mb_sphere_fold: returns [p, dz].
func mb_sphere_fold(p: Array, dz: float) -> Array:
	var r2 := dot4(p, p)
	var mr2 := maxf(r(u(params.min_radius) * u(params.min_radius)), u(1e-12))
	var fr2 := maxf(r(u(params.fixed_radius) * u(params.fixed_radius)), u(1e-12))
	if r2 < mr2:
		var f := r(fr2 / mr2)
		return [scale4(f, p), r(dz * f)]
	if r2 < fr2:
		var f := r(fr2 / maxf(r2, u(1e-12)))
		return [scale4(f, p), r(dz * f)]
	return [p, dz]


## mb_step: returns [z, dz].
func mb_step(z: Array, dz: float, c: Array, rotating: bool, i: int) -> Array:
	if params.fold_order == 0:
		z = mb_fold(z, i)
		var sf := mb_sphere_fold(z, dz)
		z = sf[0]
		dz = sf[1]
	else:
		var sf := mb_sphere_fold(z, dz)
		z = sf[0]
		dz = sf[1]
		z = mb_fold(z, i)
	if rotating:
		z = mb_iter_rotate(z)
	var s := r(u(params.box_scale) + r(u(params.scale_drift) * float(i)))
	z = add4(scale4(s, z), c)
	dz = r(r(dz * absf(s)) + 1.0)
	return [z, dz]


func mb_constant(z0: Array) -> Array:
	var j := params.julia_all
	return [u(params.c_0) if (j or params.julia_0) else z0[0], u(params.c_1) if (j or params.julia_1) else z0[1],
		u(params.c_2) if (j or params.julia_2) else z0[2], u(params.c_3) if (j or params.julia_3) else z0[3]]


## mb_orbit(z, dz, c, first, iters): iterations first..iters-1. Returns [z, dz].
func mb_orbit(z: Array, dz: float, c: Array, first: int, iters: int) -> Array:
	var rotating := mb_rotating()
	for i in range(first, 32):
		if i >= iters:
			break
		var st := mb_step(z, dz, c, rotating, i)
		z = st[0]
		dz = st[1]
	return [z, dz]


func kifs_rot_on(which: int) -> bool:
	var sum := 0.0
	for id in KifsEstimator.ROT_IDS[which]:
		sum += absf(float(params.get(id)))
	return sum > 1e-6


## kifs_rot1 (which 0) or kifs_rot2 (which 1).
func kifs_rot(p: Array, which: int) -> Array:
	var ids: Array = KifsEstimator.ROT_IDS[which]
	for j in 6:
		p = rot_plane(p, PLANES[j][0], PLANES[j][1], float(params.get(ids[j])))
	return p


func menger_fold(p: Array) -> Array:
	var q := [absf(p[0]), absf(p[1]), absf(p[2]), absf(p[3])]
	if q[0] < q[1]:
		var t: float = q[0]; q[0] = q[1]; q[1] = t
	if q[0] < q[2]:
		var t: float = q[0]; q[0] = q[2]; q[2] = t
	if q[1] < q[2]:
		var t: float = q[1]; q[1] = q[2]; q[2] = t
	return q


func kifs_diagonal_fold(p: Array) -> Array:
	var q := p.duplicate()
	for pair in [[0, 1], [0, 2], [1, 2], [0, 3]]:
		var ia: int = pair[0]
		var ib: int = pair[1]
		if r(q[ia] + q[ib]) < 0.0:
			var t: float = q[ia]
			q[ia] = -q[ib]
			q[ib] = -t
	return q


## kifs_orbit(p, n, first, iters): returns [p, n].
func kifs_orbit(p: Array, n: int, first: int, iters: int) -> Array:
	var s := u(params.kifs_scale)
	var o := [u(params.kifs_offset_0), u(params.kifs_offset_1), u(params.kifs_offset_2), u(params.kifs_offset_3)]
	var sm1 := r(s - 1.0)
	var rot1 := kifs_rot_on(0)
	var rot2 := kifs_rot_on(1)
	for i in range(first, 32):
		if i >= iters:
			break
		if rot1:
			p = kifs_rot(p, 0)
		if params.kifs_fold == KifsEstimator.FoldSet.DIAGONAL:
			p = kifs_diagonal_fold(p)
		else:
			assert(params.kifs_fold == KifsEstimator.FoldSet.COORDINATE, "the polyfold is not ported")
			p = menger_fold(p)
		if rot2:
			p = kifs_rot(p, 1)
		if params.kifs_twist != 0.0:
			p = rot_plane(p, 0, 1, r(u(params.kifs_twist) * float(i)))
		p = [r(r(s * p[0]) - r(sm1 * o[0])), r(r(s * p[1]) - r(sm1 * o[1])),
			r(r(s * p[2]) - r(sm1 * o[2])), r(r(s * p[3]) - r(sm1 * o[3]))]
		if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
			var t := r(o[2] * sm1)
			if p[2] < -0.5 * t:
				p[2] = r(p[2] + t)
		n = i + 1
		if dot4(p, p) > 1.0e6:
			break
	return [p, n]


func kifs_distance(p: Array, n: int) -> float:
	var d := 0.0
	if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
		var q := [r(absf(p[0]) - 1.0), r(absf(p[1]) - 1.0), r(absf(p[2]) - 1.0), r(absf(p[3]) - 1.0)]
		var outside := [maxf(q[0], 0.0), maxf(q[1], 0.0), maxf(q[2], 0.0), maxf(q[3], 0.0)]
		var inside := maxf(maxf(q[0], q[1]), maxf(q[2], q[3]))
		d = r(length4(outside) + minf(inside, 0.0))
	else:
		d = length4(p)
	return r(d * r(pow(u(params.kifs_scale), -float(n))))


## kleinian_orbit(p, dr, first, iters): returns [p, dr].
func kleinian_orbit(p: Array, dr: float, first: int, iters: int) -> Array:
	var b := [u(params.kleinian_box_0), u(params.kleinian_box_1), u(params.kleinian_box_2), u(params.kleinian_box_3)]
	var sh := [u(params.kleinian_shift_0), u(params.kleinian_shift_1), u(params.kleinian_shift_2), u(params.kleinian_shift_3)]
	var k := r(u(params.kleinian_radius) * u(params.kleinian_radius))
	for i in range(first, 32):
		if i >= iters:
			break
		var before := p.duplicate()
		var q := []
		for j in 4:
			q.append(r(clampf(p[j], -b[j], b[j]) * 2.0 - p[j]))
		var m := maxf(r(k / maxf(dot4(q, q), u(1e-12))), 1.0)
		p = [r(r(q[0] * m) + sh[0]), r(r(q[1] * m) + sh[1]), r(r(q[2] * m) + sh[2]), r(r(q[3] * m) + sh[3])]
		dr = r(dr * m)
		if p == before:
			break
	return [p, dr]


func kleinian_distance(p: Array, dr: float) -> float:
	var rxy := r(sqrt(dot2(p[0], p[1], p[0], p[1])))
	var t := u(params.kleinian_thickness)
	var num := r(0.5 * r(absf(r(rxy * p[2])) - t))
	return r(absf(r(num / r(sqrt(r(dot4(p, p) + absf(t)))))) / dr)


## de(pos, iters): today's direct estimate at a 32-bit point (no noise).
func de_direct(pos: Array, iters: int) -> float:
	var z0 := [pos[0], pos[1], pos[2], u(params.w)]
	if params.shape == FractalParams.Shape.KIFS:
		var kr := kifs_orbit(z0, 0, 0, iters)
		return kifs_distance(kr[0], kr[1])
	if params.shape == FractalParams.Shape.KLEINIAN:
		var lr := kleinian_orbit(z0, 1.0, 0, iters)
		return kleinian_distance(lr[0], lr[1])
	var mr := mb_orbit(z0.duplicate(), 1.0, mb_constant(z0), 0, iters)
	return r(length4(mr[0]) / absf(mr[1]))


# ------------------------------------------------------------- the perturbed steps

## -1 below [lo, hi], 0 inside, 1 above (for the crossing counts).
static func _side(v: float, lo: float, hi: float) -> int:
	return -1 if v < lo else (1 if v > hi else 0)


## pert_clamp, one component: 2 (clamp(d, glo, ghi) - clamp(0, glo, ghi)) - d.
func pert_clamp1(d: float, glo: float, ghi: float, kind: String) -> float:
	if _side(0.0, glo, ghi) != _side(d, glo, ghi):
		_count(kind)
	var t := r(clampf(d, glo, ghi) - clampf(0.0, glo, ghi))
	return r(2.0 * t - d)


func pert_clamp(dl: Array, glo: Array, ghi: Array, kind: String) -> Array:
	return [pert_clamp1(dl[0], glo[0], ghi[0], kind), pert_clamp1(dl[1], glo[1], ghi[1], kind),
		pert_clamp1(dl[2], glo[2], ghi[2], kind), pert_clamp1(dl[3], glo[3], ghi[3], kind)]


## pert_abs: 2 (max(d, g) - max(0, g)) - d, g = -X (the clamp with no upper crease).
func pert_abs(dl: Array, g: Array) -> Array:
	var out := []
	for j in 4:
		var d: float = dl[j]
		var gj: float = g[j]
		if (gj > 0.0) != (d < gj):
			_count("abs")
		var t := r(maxf(d, gj) - maxf(0.0, gj))
		out.append(r(2.0 * t - d))
	return out


## pert_swap: one compare-and-swap of the sort on (da, db), g = X_a - X_b. [da', db'].
func pert_swap(da: float, db: float, g: float) -> Array:
	var ps := r(da - db) < -g
	var rs := g < 0.0
	if ps and rs:
		return [db, da]
	if ps:
		_count("sort_p")
		return [r(db - g), r(da + g)]
	if rs:
		_count("sort_r")
		return [r(da + g), r(db - g)]
	return [da, db]


func pert_sort(dl: Array, g: Array) -> Array:
	var q := dl.duplicate()
	var s := pert_swap(q[0], q[1], g[0])
	q[0] = s[0]; q[1] = s[1]
	s = pert_swap(q[0], q[2], g[1])
	q[0] = s[0]; q[2] = s[1]
	s = pert_swap(q[1], q[2], g[2])
	q[1] = s[0]; q[2] = s[1]
	return q


## pert_flip: one diagonal reflection on (da, db), g = X_a + X_b. [da', db'].
func pert_flip(da: float, db: float, g: float) -> Array:
	var ps := r(da + db) < -g
	var rs := g < 0.0
	if ps and rs:
		return [-db, -da]
	if ps:
		_count("diag_p")
		return [r(-g - db), r(-g - da)]
	if rs:
		_count("diag_r")
		return [r(da + g), r(db + g)]
	return [da, db]


func pert_diagonal(dl: Array, g: Array) -> Array:
	var q := dl.duplicate()
	var s := pert_flip(q[0], q[1], g[0])
	q[0] = s[0]; q[1] = s[1]
	s = pert_flip(q[0], q[2], g[1])
	q[0] = s[0]; q[2] = s[1]
	s = pert_flip(q[1], q[2], g[2])
	q[1] = s[0]; q[2] = s[1]
	s = pert_flip(q[0], q[3], g[3])
	q[0] = s[0]; q[3] = s[1]
	return q


## pert_menger: dz + t ([dz < -g] - [g < 0]), g = X_z + t/2 after the scale.
func pert_menger(dz: float, g: float, t: float) -> float:
	var pc := dz < -g
	var rc := g < 0.0
	if pc != rc:
		_count("menger")
	return r(dz + r(t * ((1.0 if pc else 0.0) - (1.0 if rc else 0.0))))


## pert_sphere: returns [dl', dz']. See the regime table in the plan / shader.
func pert_sphere(dl: Array, dz: float, X: Array, gmin: float, gfix: float, mr2: float, fr2: float, kind: String) -> Array:
	var q := r(r(2.0 * dot4(X, dl)) + dot4(dl, dl))
	var x2 := dot4(X, X)
	var p2 := r(x2 + q)
	var gqmin := r(gmin + q)
	var gqfix := r(gfix + q)
	var rx := 0 if gmin < 0.0 else (1 if gfix < 0.0 else 2)
	var rp := 0 if gqmin < 0.0 else (1 if gqfix < 0.0 else 2)
	if rx != rp:
		_count(kind)
	var mp := 1.0
	if rp == 0:
		mp = r(fr2 / mr2)
	elif rp == 1:
		mp = r(fr2 / maxf(p2, u(1e-12)))
	var dm := 0.0
	if rx == 1 and rp == 1:
		dm = r(r(-fr2 * q) / r(p2 * x2))
	elif rx == 0 and rp == 1:
		dm = r(r(-fr2 * gqmin) / r(p2 * mr2))
	elif rx == 1 and rp == 0:
		dm = r(r(fr2 * gmin) / r(mr2 * x2))
	elif rx == 1 and rp == 2:
		dm = r(gfix / x2)
	elif rx == 2 and rp == 1:
		dm = r(-gqfix / p2)
	elif rx == 0 and rp == 2:
		dm = r(1.0 - r(fr2 / mr2))
	elif rx == 2 and rp == 0:
		dm = r(r(fr2 / mr2) - 1.0)
	return [add4(scale4(mp, dl), scale4(dm, X)), r(dz * mp)]


## pert_cylinder: the cylinder fold's xy pair. X = the reference's xy (record a.xy),
## g = r - L (record d.w). Returns [dx', dy'].
func pert_cylinder(d0: float, d1: float, X0: float, X1: float, g: float) -> Array:
	var L := u(params.fold_limit)
	var rr := r(L + g)
	var q := r(r(2.0 * dot2(X0, X1, d0, d1)) + dot2(d0, d1, d0, d1))
	var rp := r(sqrt(maxf(r(r(rr * rr) + q), 0.0)))
	var dr := r(q / maxf(r(rp + rr), u(1e-30)))
	var gdr := r(g + dr)
	var xo := g > 0.0
	var po := gdr > 0.0
	if xo != po:
		_count("cylinder")
	var mp := r(r(r(2.0 * L) - rp) / rp) if po else 1.0
	var dm := 0.0
	if xo and po:
		dm = r(r(r(-2.0 * L) * dr) / r(rr * rp))
	elif po:
		dm = r(r(-2.0 * gdr) / rp)
	elif xo:
		dm = r(r(2.0 * g) / rr)
	return [r(r(mp * d0) + r(X0 * dm)), r(r(mp * d1) + r(X1 * dm))]


## pert_mb_fold: the Mandelbox fold step on the offset.
func pert_mb_fold(dl: Array, ra: Array, rb: Array, gr: float, i: int) -> Array:
	var hybrid := false
	if params.hybrid_mix > 0.0:
		var every := maxi(params.hybrid_every, 1)
		hybrid = i % every == every - 1
	if params.fold_shape == MandelboxShape.FoldShape.CYLINDER and not hybrid:
		var xy := pert_cylinder(dl[0], dl[1], ra[0], ra[1], gr)
		return [xy[0], xy[1], pert_clamp1(dl[2], ra[2], rb[2], "clamp"), pert_clamp1(dl[3], ra[3], rb[3], "clamp")]
	return pert_clamp(dl, ra, rb, "clamp")


# ------------------------------------------------------------- de_pert

## de_pert(off, iters): the estimate at eye + off without forming that sum for the
## orbit. A ray runs the perturbed step while i < min(k, iters) and |dl|^2 <
## handoff^2; at the first i = h where either fails it hands off: z = X_h + dl
## (pert_x[h]) and the ordinary loop runs from h to iters. A far ray (|off| >=
## handoff) hands off at h = 0, where z = eye + off: today's expression. No noise
## (the tests have none).
func de_pert(orbit, k: int, off: Array, iters: int) -> float:
	var dl := [r(off[0]), r(off[1]), r(off[2]), 0.0]
	var p := [r(eye[0] + dl[0]), r(eye[1] + dl[1]), r(eye[2] + dl[2])]
	var lim := mini(k, iters)
	if params.shape == FractalParams.Shape.KIFS:
		return de_pert_kifs(orbit, lim, dl, iters)
	if params.shape == FractalParams.Shape.KLEINIAN:
		return de_pert_kleinian(orbit, lim, dl, iters)
	return de_pert_mandelbox(orbit, lim, dl, p, iters)


## The shader's loop test: stop perturbing once |dl|^2 reaches PERT_HANDOFF^2.
func _handed_off(dl: Array) -> bool:
	return dot4(dl, dl) >= r(u(handoff) * u(handoff))


func de_pert_mandelbox(orbit, lim: int, dl: Array, p: Array, iters: int) -> float:
	var j := params.julia_all
	var dc := [0.0 if (j or params.julia_0) else dl[0], 0.0 if (j or params.julia_1) else dl[1],
		0.0 if (j or params.julia_2) else dl[2], 0.0]
	var mr2 := maxf(r(u(params.min_radius) * u(params.min_radius)), u(1e-12))
	var fr2 := maxf(r(u(params.fixed_radius) * u(params.fixed_radius)), u(1e-12))
	var dz := 1.0
	var rotating := mb_rotating()
	var h := 0
	for i in lim:
		if _handed_off(dl):
			break
		var ra := rec(orbit, i, 0)
		var rb := rec(orbit, i, 1)
		var rc := rec(orbit, i, 2)
		var rd := rec(orbit, i, 3)
		if params.fold_order == 0:
			dl = pert_mb_fold(dl, ra, rb, rd[3], i)
			var sf := pert_sphere(dl, dz, rc, rd[0], rd[1], mr2, fr2, "sphere")
			dl = sf[0]
			dz = sf[1]
		else:
			var sf := pert_sphere(dl, dz, rc, rd[0], rd[1], mr2, fr2, "sphere")
			dl = sf[0]
			dz = sf[1]
			dl = pert_mb_fold(dl, ra, rb, rd[3], i)
		if rotating:
			dl = mb_iter_rotate(dl)
		var s := r(u(params.box_scale) + r(u(params.scale_drift) * float(i)))
		dl = add4(scale4(s, dl), dc)
		dz = r(r(dz * absf(s)) + 1.0)
		if tracing:
			trace.append(dl.duplicate())
		h = i + 1
	var z := add4(point(orbit, h), dl)
	var c := mb_constant([p[0], p[1], p[2], u(params.w)])
	var res := mb_orbit(z, dz, c, h, iters)
	return r(length4(res[0]) / absf(res[1]))


func de_pert_kifs(orbit, lim: int, dl: Array, iters: int) -> float:
	var s := u(params.kifs_scale)
	var oz := u(params.kifs_offset_2)
	var t := r(oz * r(s - 1.0))
	var rot1 := kifs_rot_on(0)
	var rot2 := kifs_rot_on(1)
	var n := 0
	var h := 0
	for i in lim:
		if _handed_off(dl):
			break
		if rot1:
			dl = kifs_rot(dl, 0)
		if params.kifs_fold == KifsEstimator.FoldSet.DIAGONAL:
			dl = pert_diagonal(dl, rec(orbit, i, 1))
		else:
			dl = pert_sort(pert_abs(dl, rec(orbit, i, 0)), rec(orbit, i, 1))
		if rot2:
			dl = kifs_rot(dl, 1)
		if params.kifs_twist != 0.0:
			dl = rot_plane(dl, 0, 1, r(u(params.kifs_twist) * float(i)))
		dl = scale4(s, dl)
		if params.kifs_fold == KifsEstimator.FoldSet.COORDINATE:
			dl[2] = pert_menger(dl[2], rec(orbit, i, 2)[0], t)
		if tracing:
			trace.append(dl.duplicate())
		n = i + 1
		h = i + 1
		var zi := add4(rec(orbit, i, 3), dl)
		if dot4(zi, zi) > 1.0e6:
			return kifs_distance(zi, n)
	var res := kifs_orbit(add4(point(orbit, h), dl), n, h, iters)
	return kifs_distance(res[0], res[1])


func de_pert_kleinian(orbit, lim: int, dl: Array, iters: int) -> float:
	var kk := r(u(params.kleinian_radius) * u(params.kleinian_radius))
	var dr := 1.0
	var h := 0
	for i in lim:
		if _handed_off(dl):
			break
		dl = pert_clamp(dl, rec(orbit, i, 0), rec(orbit, i, 1), "clamp")
		var sf := pert_sphere(dl, dr, rec(orbit, i, 2), 1.0e30, rec(orbit, i, 3)[0], kk, kk, "inversion")
		dl = sf[0]
		dr = sf[1]
		if tracing:
			trace.append(dl.duplicate())
		h = i + 1
	var res := kleinian_orbit(add4(point(orbit, h), dl), dr, h, iters)
	return kleinian_distance(res[0], res[1])
