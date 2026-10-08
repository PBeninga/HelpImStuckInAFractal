class_name KifsEstimator
extends RefCounted
## CPU copy of kifs.gdshaderinc's kifs_de at N = 32, in 64-bit scalars (see
## DistanceEstimator for why). Ported from Fractacular's kifs.gdshader: rotate
## (R1), apply the fold set, rotate (R2), twist, scale toward the offset, repeat
## until the orbit leaves BAILOUT. The distance is the orbit's distance to the
## base cell, shrunk by the scale once per iteration: the box [-1, 1]^4 for the
## coordinate fold (crisp Menger edges), the origin otherwise.
##
## Two changes from Fractacular. The diagonal fold runs on the point itself:
## Fractacular folded into the positive orthant first, where x + y < 0 never
## holds, so its Sierpinski fold never fired. And the polyfold reflects into a
## half-wedge (a triangle wave in the angle) instead of rotating into a wedge,
## so the field is continuous across the wedge edges, which a ray march needs;
## the Menger fold follows it.

const ITERATIONS := 32
## The orbit escapes once |p|^2 passes this (|p| > 1000).
const BAILOUT2 := 1.0e6
const PLANES := DistanceEstimator.PLANES

enum FoldSet { COORDINATE, DIAGONAL, POLYFOLD }

## The FractalParams fields of R1 and R2, in PLANES order.
const ROT_IDS := [
	[&"kifs_rot1_xy", &"kifs_rot1_xz", &"kifs_rot1_xw", &"kifs_rot1_yz", &"kifs_rot1_yw", &"kifs_rot1_zw"],
	[&"kifs_rot2_xy", &"kifs_rot2_xz", &"kifs_rot2_xw", &"kifs_rot2_yz", &"kifs_rot2_yw", &"kifs_rot2_zw"],
]


static func estimate_at(px: float, py: float, pz: float, params: FractalParams) -> float:
	var s := params.kifs_scale
	var fold_set := params.kifs_fold
	var sector := TAU / float(maxi(int(floor(params.kifs_poly_k + 0.5)), 2))
	var twist := deg_to_rad(params.kifs_twist)
	var o := [params.kifs_offset_0, params.kifs_offset_1, params.kifs_offset_2, params.kifs_offset_3]
	var r1 := _angles(params, 0)
	var r2 := _angles(params, 1)

	var p := [px, py, pz, params.w]
	var n := 0
	for i in ITERATIONS:
		if not r1.is_empty():
			_rotate(p, r1)
		if fold_set == FoldSet.COORDINATE:
			DistanceEstimator.menger_fold(p)
		elif fold_set == FoldSet.DIAGONAL:
			_diagonal_fold(p)
		else:
			_poly_fold(p, sector)
			DistanceEstimator.menger_fold(p)
		if not r2.is_empty():
			_rotate(p, r2)
		if twist != 0.0:
			var a := twist * i
			var c := cos(a)
			var sn := sin(a)
			var x: float = p[0]
			var y: float = p[1]
			p[0] = x * c - y * sn
			p[1] = x * sn + y * c
		for k in 4:
			p[k] = s * p[k] - (s - 1.0) * o[k]
		if fold_set == FoldSet.COORDINATE:
			# The Menger correction: reflect the far z layer back.
			var t: float = o[2] * (s - 1.0)
			if p[2] < -0.5 * t:
				p[2] += t
		n = i + 1
		if p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3] > BAILOUT2:
			break
	var d := 0.0
	if fold_set == FoldSet.COORDINATE:
		d = _box_distance(p)
	else:
		d = sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
	return d * pow(s, -float(n))


## The six angles of rotation `which` (0 for R1, 1 for R2) as [cos, sin]
## pairs in PLANES order, or [] when every angle is 0 (the rotation is skipped).
## The fly camera's centre ray calls this every estimate, so the field names
## are prebuilt rather than formatted each time.
static func _angles(params: FractalParams, which: int) -> Array:
	var ids: Array = ROT_IDS[which]
	var out := []
	var any := false
	for id in ids:
		var a: float = params.get(id)
		if absf(a) > 1e-6:
			any = true
		var r := deg_to_rad(a)
		out.append([cos(r), sin(r)])
	return out if any else []


static func _rotate(p: Array, cs: Array) -> void:
	for i in 6:
		var a: int = PLANES[i][0]
		var b: int = PLANES[i][1]
		var c: float = cs[i][0]
		var s: float = cs[i][1]
		var pa: float = p[a]
		var pb: float = p[b]
		p[a] = pa * c - pb * s
		p[b] = pa * s + pb * c


## Reflect across the diagonal planes x = -y, x = -z, y = -z, x = -w: the
## Sierpinski fold.
static func _diagonal_fold(p: Array) -> void:
	for pair in [[0, 1], [0, 2], [1, 2], [0, 3]]:
		var a: int = pair[0]
		var b: int = pair[1]
		if p[a] + p[b] < 0.0:
			var t: float = p[a]
			p[a] = -p[b]
			p[b] = -t


## Fold the xy angle into [0, sector / 2] by reflection: k-fold mirror
## symmetry. (The caller then applies the Menger fold, which keeps the
## attractor solid enough to hit; the polyfold alone leaves sparse dust.)
static func _poly_fold(p: Array, sector: float) -> void:
	var r := sqrt(p[0] * p[0] + p[1] * p[1])
	var a := absf(fposmod(atan2(p[1], p[0]) + 0.5 * sector, sector) - 0.5 * sector)
	p[0] = r * cos(a)
	p[1] = r * sin(a)


## Signed distance from p to the box [-1, 1]^4.
static func _box_distance(p: Array) -> float:
	var outside := 0.0
	var inside := -1.0e30
	for k in 4:
		var q := absf(p[k]) - 1.0
		outside += maxf(q, 0.0) * maxf(q, 0.0)
		inside = maxf(inside, q)
	return sqrt(outside) + minf(inside, 0.0)
