class_name ReferenceOrbit
extends RefCounted
## The camera's own orbit, iterated in 64-bit on the CPU from the 64-bit eye, and
## the per-iteration record the shader's perturbed march reads
## (src/fractal/perturbation.gdshaderinc). The record holds, for each of the first
## PERT_MAX iterations, the gaps between the reference point X and each fold's
## creases (crease minus X, worked out in 64-bit). A gap is small exactly when
## precision matters, and a 32-bit float holds a small number to the same
## relative precision as a large one, so the GPU can tell which side of a crease
## a pixel lands on without forming the pixel's point.
##
##   var orbit := ReferenceOrbit.build(params, ex, ey, ez)
##   orbit.distance   # == DistanceEstimator.estimate_at(ex, ey, ez, params), exactly
##   orbit.n          # iterations run before a KIFS bailout or a Kleinian fixed point (32 otherwise)
##   orbit.mag        # λ_0 .. λ_32 (λ_0 = 1): how much the orbit has magnified after i iterations
##   orbit.points     # X_0 .. X_32 as 32-bit Vector4s (the first PERT_MAX + 1 are pushed as
##                    # pert_x: the point a ray hands off to after i perturbed iterations)
##   orbit.a, .b, .c, .d   # the record, PERT_MAX Vector4s each (layout: see the shader's header)
##   orbit.perturbable     # false for the octahedral fold, the polyfold and the Mandelbulb
##
## Built by FractalView._push_near() (the record it pushes), FlyCamera.move_allowed() and FractalParams.zoom_floor() (the floors).
##
## The shader reads 32-bit copies; points64 and rec64 keep the 64-bit values for
## the algebra check (tests/perturbation_test.gd). rec64 index: (i * 4 + slot) * 4
## + component, slot 0..3 = a..d.

const ITERATIONS := 32
## The uniform arrays' length: at most this many iterations are perturbed.
const PERT_MAX := 20
const PLANES := DistanceEstimator.PLANES

var eye := PackedFloat64Array([0.0, 0.0, 0.0])
var distance := 0.0
var n := ITERATIONS
var perturbable := false
var mag := PackedFloat64Array()
var points := PackedVector4Array()
var points64 := PackedFloat64Array()
var a := PackedVector4Array()
var b := PackedVector4Array()
var c := PackedVector4Array()
var d := PackedVector4Array()
var rec64 := PackedFloat64Array()


static func build(params: FractalParams, ex: float, ey: float, ez: float) -> ReferenceOrbit:
	var o := ReferenceOrbit.new()
	o.eye = PackedFloat64Array([ex, ey, ez])
	o.mag.resize(ITERATIONS + 1)
	o.mag.fill(1.0)
	o.points64.resize((ITERATIONS + 1) * 4)
	o.points64.fill(0.0)
	o.rec64.resize(PERT_MAX * 16)
	o.rec64.fill(0.0)
	match params.shape:
		FractalParams.Shape.KIFS:
			o._kifs(params, ex, ey, ez)
		FractalParams.Shape.KLEINIAN:
			o._kleinian(params, ex, ey, ez)
		FractalParams.Shape.MANDELBULB:
			o._mandelbulb(params, ex, ey, ez)
		_:
			o._mandelbox(params, ex, ey, ez)
	o._pack()
	return o


# ------------------------------------------------------------- Mandelbox

func _mandelbox(params: FractalParams, px: float, py: float, pz: float) -> void:
	var scale := params.box_scale
	var drift := params.scale_drift
	var fold_shape := params.fold_shape
	var mix := params.hybrid_mix
	var every := maxi(params.hybrid_every, 1)
	var mr2 := params.min_radius * params.min_radius
	var fr2 := params.fixed_radius * params.fixed_radius
	var fold := params.fold_limit
	var fold_order := params.fold_order
	perturbable = fold_shape != MandelboxShape.FoldShape.OCTAHEDRAL

	var z0 := [px, py, pz, params.w]
	var cst := [
		params.c_0 if (params.julia_all or params.julia_0) else z0[0],
		params.c_1 if (params.julia_all or params.julia_1) else z0[1],
		params.c_2 if (params.julia_all or params.julia_2) else z0[2],
		params.c_3 if (params.julia_all or params.julia_3) else z0[3],
	]
	var angles := [params.iter_rot_xy, params.iter_rot_xz, params.iter_rot_xw,
		params.iter_rot_yz, params.iter_rot_yw, params.iter_rot_zw]
	var rotating := false
	for ang in angles:
		if absf(ang) > 1e-6:
			rotating = true
			break
	var cosv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var sinv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if rotating:
		for j in 6:
			var rad := deg_to_rad(angles[j])
			cosv[j] = cos(rad)
			sinv[j] = sin(rad)

	var z := [z0[0], z0[1], z0[2], z0[3]]
	var dz := 1.0
	var lam := 1.0
	_set_point(0, z)
	for i in ITERATIONS:
		var hybrid := mix > 0.0 and i % every == every - 1
		var keep := i < PERT_MAX
		if fold_order == 0:
			if keep:
				_fold_record(i, z, fold, fold_shape, hybrid, mix)
			DistanceEstimator._fold(z, fold, fold_shape, hybrid, mix)
			lam *= _sphere_record(i, z, mr2, fr2, keep)
			dz = DistanceEstimator._sphere_fold(z, dz, mr2, fr2)
		else:
			lam *= _sphere_record(i, z, mr2, fr2, keep)
			dz = DistanceEstimator._sphere_fold(z, dz, mr2, fr2)
			if keep:
				_fold_record(i, z, fold, fold_shape, hybrid, mix)
			DistanceEstimator._fold(z, fold, fold_shape, hybrid, mix)
		if rotating:
			for j in 6:
				DistanceEstimator._rot_plane(z, PLANES[j][0], PLANES[j][1], cosv[j], sinv[j])
		var s := scale + drift * i
		z[0] = s * z[0] + cst[0]
		z[1] = s * z[1] + cst[1]
		z[2] = s * z[2] + cst[2]
		z[3] = s * z[3] + cst[3]
		dz = dz * absf(s) + 1.0
		lam *= absf(s)
		mag[i + 1] = lam
		_set_point(i + 1, z)
	n = ITERATIONS
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	distance = sqrt(r2) / absf(dz)


## The fold's gaps for iteration i, from the fold's input point z (see the
## record table in the shader's header).
func _fold_record(i: int, z: Array, fold: float, fold_shape: int, hybrid: bool, mix: float) -> void:
	if hybrid:
		var lo := -fold * (1.0 - mix)
		var hi := (fold + mix) / maxf(1.0 - mix, 1e-6)
		_rec(i, 0, lo - z[0], lo - z[1], lo - z[2], lo - z[3])
		_rec(i, 1, hi - z[0], hi - z[1], hi - z[2], hi - z[3])
	elif fold_shape == MandelboxShape.FoldShape.CYLINDER:
		# a.xy carries the reference's own xy: the radial step needs X, not a gap
		_rec(i, 0, z[0], z[1], -fold - z[2], -fold - z[3])
		_rec(i, 1, 0.0, 0.0, fold - z[2], fold - z[3])
		_rec1(i, 3, 3, sqrt(z[0] * z[0] + z[1] * z[1]) - fold)
	else:
		_rec(i, 0, -fold - z[0], -fold - z[1], -fold - z[2], -fold - z[3])
		_rec(i, 1, fold - z[0], fold - z[1], fold - z[2], fold - z[3])


## The sphere fold's factor at z (the rule DistanceEstimator._sphere_fold
## applies) and, for a recorded iteration, its input point (c) and its gaps and
## factor (d.x, d.y, d.z).
func _sphere_record(i: int, z: Array, mr2: float, fr2: float, keep: bool) -> float:
	var mr := maxf(mr2, 1e-12)
	var fr := maxf(fr2, 1e-12)
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	var f := 1.0
	if r2 < mr:
		f = fr / mr
	elif r2 < fr:
		f = fr / maxf(r2, 1e-12)
	if keep:
		_rec(i, 2, z[0], z[1], z[2], z[3])
		_rec1(i, 3, 0, r2 - mr)
		_rec1(i, 3, 1, r2 - fr)
		_rec1(i, 3, 2, f)
	return f


# ------------------------------------------------------------- KIFS

func _kifs(params: FractalParams, px: float, py: float, pz: float) -> void:
	var s := params.kifs_scale
	var fold_set := params.kifs_fold
	var sector := TAU / float(maxi(int(floor(params.kifs_poly_k + 0.5)), 2))
	var twist := deg_to_rad(params.kifs_twist)
	var o := [params.kifs_offset_0, params.kifs_offset_1, params.kifs_offset_2, params.kifs_offset_3]
	var r1 := KifsEstimator._angles(params, 0)
	var r2 := KifsEstimator._angles(params, 1)
	perturbable = fold_set != KifsEstimator.FoldSet.POLYFOLD

	var p := [px, py, pz, params.w]
	_set_point(0, p)
	n = 0
	var escaped := false
	for i in ITERATIONS:
		# |s|^i whatever the bailout: mag says what i iterations magnify, not when this orbit escaped
		mag[i + 1] = pow(absf(s), i + 1)
		if escaped:
			_set_point(i + 1, p)
			continue
		var keep := i < PERT_MAX
		if not r1.is_empty():
			KifsEstimator._rotate(p, r1)
		if fold_set == KifsEstimator.FoldSet.COORDINATE:
			# DistanceEstimator.menger_fold, with the gap taken at each comparison
			if keep:
				_rec(i, 0, -p[0], -p[1], -p[2], -p[3])
			for j in 4:
				p[j] = absf(p[j])
			var g01: float = p[0] - p[1]
			if p[0] < p[1]:
				var t: float = p[0]; p[0] = p[1]; p[1] = t
			var g02: float = p[0] - p[2]
			if p[0] < p[2]:
				var t: float = p[0]; p[0] = p[2]; p[2] = t
			var g12: float = p[1] - p[2]
			if p[1] < p[2]:
				var t: float = p[1]; p[1] = p[2]; p[2] = t
			if keep:
				_rec(i, 1, g01, g02, g12, 0.0)
		elif fold_set == KifsEstimator.FoldSet.DIAGONAL:
			# KifsEstimator._diagonal_fold, with the gap taken at each comparison
			var g := [0.0, 0.0, 0.0, 0.0]
			var pairs := [[0, 1], [0, 2], [1, 2], [0, 3]]
			for j in 4:
				var ia: int = pairs[j][0]
				var ib: int = pairs[j][1]
				g[j] = p[ia] + p[ib]
				if p[ia] + p[ib] < 0.0:
					var t: float = p[ia]
					p[ia] = -p[ib]
					p[ib] = -t
			if keep:
				_rec(i, 1, g[0], g[1], g[2], g[3])
		else:
			KifsEstimator._poly_fold(p, sector)
			DistanceEstimator.menger_fold(p)
		if not r2.is_empty():
			KifsEstimator._rotate(p, r2)
		if twist != 0.0:
			var ang := twist * i
			var cs := cos(ang)
			var sn := sin(ang)
			var x: float = p[0]
			var y: float = p[1]
			p[0] = x * cs - y * sn
			p[1] = x * sn + y * cs
		for j in 4:
			p[j] = s * p[j] - (s - 1.0) * o[j]
		if fold_set == KifsEstimator.FoldSet.COORDINATE:
			var t: float = o[2] * (s - 1.0)
			if keep:
				_rec1(i, 2, 0, p[2] + 0.5 * t)
			if p[2] < -0.5 * t:
				p[2] += t
		if keep:
			_rec(i, 3, p[0], p[1], p[2], p[3])
		_set_point(i + 1, p)
		n = i + 1
		if p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3] > KifsEstimator.BAILOUT2:
			escaped = true
	var dist := 0.0
	if fold_set == KifsEstimator.FoldSet.COORDINATE:
		dist = KifsEstimator._box_distance(p)
	else:
		dist = sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
	distance = dist * pow(s, -float(n))


# ------------------------------------------------------------- Kleinian

func _kleinian(params: FractalParams, px: float, py: float, pz: float) -> void:
	var bx := [params.kleinian_box_0, params.kleinian_box_1, params.kleinian_box_2, params.kleinian_box_3]
	var shift := [params.kleinian_shift_0, params.kleinian_shift_1, params.kleinian_shift_2, params.kleinian_shift_3]
	var k := params.kleinian_radius * params.kleinian_radius
	perturbable = true
	var p := [px, py, pz, params.w]
	var dr := 1.0
	_set_point(0, p)
	n = ITERATIONS
	var settled := false
	for i in ITERATIONS:
		if settled:
			mag[i + 1] = dr
			_set_point(i + 1, p)
			continue
		var keep := i < PERT_MAX
		var before := [p[0], p[1], p[2], p[3]]
		if keep:
			_rec(i, 0, -bx[0] - p[0], -bx[1] - p[1], -bx[2] - p[2], -bx[3] - p[3])
			_rec(i, 1, bx[0] - p[0], bx[1] - p[1], bx[2] - p[2], bx[3] - p[3])
		for j in 4:
			p[j] = clampf(p[j], -bx[j], bx[j]) * 2.0 - p[j]
		var r2: float = p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3]
		var m := maxf(k / maxf(r2, 1e-12), 1.0)
		if keep:
			_rec(i, 2, p[0], p[1], p[2], p[3])
			_rec(i, 3, r2 - k, m, 0.0, 0.0)
		for j in 4:
			p[j] = p[j] * m + shift[j]
		dr *= m
		mag[i + 1] = dr
		_set_point(i + 1, p)
		if p == before:
			n = i + 1
			settled = true
	distance = KleinianEstimator.thingy(p, params.kleinian_thickness) / dr


# ------------------------------------------------------------- Mandelbulb (not perturbed)

func _mandelbulb(params: FractalParams, px: float, py: float, pz: float) -> void:
	perturbable = false
	n = ITERATIONS
	distance = MandelbulbEstimator.estimate_at(px, py, pz, params)
	for i in ITERATIONS + 1:
		_set_point(i, [px, py, pz, 0.0])


# ------------------------------------------------------------- storage

func _set_point(i: int, z: Array) -> void:
	for j in 4:
		points64[i * 4 + j] = z[j]


func _rec(i: int, slot: int, v0: float, v1: float, v2: float, v3: float) -> void:
	var base := (i * 4 + slot) * 4
	rec64[base] = v0
	rec64[base + 1] = v1
	rec64[base + 2] = v2
	rec64[base + 3] = v3


func _rec1(i: int, slot: int, comp: int, v: float) -> void:
	rec64[(i * 4 + slot) * 4 + comp] = v


func _vec(i: int, slot: int) -> Vector4:
	var base := (i * 4 + slot) * 4
	return Vector4(rec64[base], rec64[base + 1], rec64[base + 2], rec64[base + 3])


## The 32-bit copies the shader reads.
func _pack() -> void:
	points.resize(ITERATIONS + 1)
	for i in ITERATIONS + 1:
		points[i] = Vector4(points64[i * 4], points64[i * 4 + 1], points64[i * 4 + 2], points64[i * 4 + 3])
	a.resize(PERT_MAX)
	b.resize(PERT_MAX)
	c.resize(PERT_MAX)
	d.resize(PERT_MAX)
	for i in PERT_MAX:
		a[i] = _vec(i, 0)
		b[i] = _vec(i, 1)
		c[i] = _vec(i, 2)
		d[i] = _vec(i, 3)
