class_name DistanceEstimator
extends RefCounted
## CPU copy of the shader's Mandelbox distance estimator, N = 32 (the
## high-precision variant) unless a smaller iteration count is asked for, as the
## shader's coarse pass does (FractalParams.coarse_iters). Mirrors
## mandelbox.gdshader's mb_step in 64-bit scalars (zx, zy, zz, zw): box fold, sphere fold, optional 4D iteration
## rotation, scale and add, carrying the running derivative dz. Must give the
## same numbers as the shader's `de(p, iters)`.
##
## The orbit runs in scalar `float` locals (GDScript floats are 64-bit) rather
## than Vector math, because Vector components are 32-bit in a standard build
## and that lost input precision is amplified near the surface, throwing off the
## near-boundary fixtures.

const ITERATIONS := 32

# The six rotation planes, in the shader's fixed order, as (a, b) index pairs
# into (x, y, z, w) = (0, 1, 2, 3).
const PLANES := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]


static func estimate(p: Vector3, params: FractalParams) -> float:
	return estimate_at(p.x, p.y, p.z, params)


## `iters` is clamped to [0, ITERATIONS]; the default is the shader's `de(p, 32)`.
static func estimate_at(px: float, py: float, pz: float, params: FractalParams,
		iters: int = ITERATIONS) -> float:
	var scale := params.box_scale
	var mr2 := params.min_radius * params.min_radius
	var fr2 := params.fixed_radius * params.fixed_radius
	var fold := params.fold_limit
	var fold_order := params.fold_order

	var z0 := [px, py, pz, params.w]
	# Per component: the Julia constant where it is checked, else the point's own.
	var c := [
		params.c_0 if (params.julia_all or params.julia_0) else z0[0],
		params.c_1 if (params.julia_all or params.julia_1) else z0[1],
		params.c_2 if (params.julia_all or params.julia_2) else z0[2],
		params.c_3 if (params.julia_all or params.julia_3) else z0[3],
	]

	var angles := [params.iter_rot_xy, params.iter_rot_xz, params.iter_rot_xw,
		params.iter_rot_yz, params.iter_rot_yw, params.iter_rot_zw]
	var rotating := false
	for a in angles:
		if absf(a) > 1e-6:
			rotating = true
			break
	# Precompute cos/sin per plane once.
	var cosv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var sinv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if rotating:
		for i in 6:
			var r := deg_to_rad(angles[i])
			cosv[i] = cos(r)
			sinv[i] = sin(r)

	var z := [z0[0], z0[1], z0[2], z0[3]]
	var dz := 1.0
	for _i in clampi(iters, 0, ITERATIONS):
		if fold_order == 0:
			_box_fold(z, fold)
			dz = _sphere_fold(z, dz, mr2, fr2)
		else:
			dz = _sphere_fold(z, dz, mr2, fr2)
			_box_fold(z, fold)
		if rotating:
			for p in 6:
				_rot_plane(z, PLANES[p][0], PLANES[p][1], cosv[p], sinv[p])
		z[0] = scale * z[0] + c[0]
		z[1] = scale * z[1] + c[1]
		z[2] = scale * z[2] + c[2]
		z[3] = scale * z[3] + c[3]
		dz = dz * absf(scale) + 1.0
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	return sqrt(r2) / absf(dz)


static func _box_fold(z: Array, fold: float) -> void:
	z[0] = clampf(z[0], -fold, fold) * 2.0 - z[0]
	z[1] = clampf(z[1], -fold, fold) * 2.0 - z[1]
	z[2] = clampf(z[2], -fold, fold) * 2.0 - z[2]
	z[3] = clampf(z[3], -fold, fold) * 2.0 - z[3]


static func _sphere_fold(z: Array, dz: float, mr2: float, fr2: float) -> float:
	var mr := maxf(mr2, 1e-12)
	var fr := maxf(fr2, 1e-12)
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	var f := 1.0
	if r2 < mr:
		f = fr / mr
	elif r2 < fr:
		f = fr / maxf(r2, 1e-12)
	z[0] *= f
	z[1] *= f
	z[2] *= f
	z[3] *= f
	return dz * f


static func _rot_plane(z: Array, a: int, b: int, c: float, s: float) -> void:
	var za: float = z[a]
	var zb: float = z[b]
	z[a] = za * c - zb * s
	z[b] = za * s + zb * c
