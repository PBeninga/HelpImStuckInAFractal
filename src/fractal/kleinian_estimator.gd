class_name KleinianEstimator
extends RefCounted
## CPU copy of kleinian.gdshaderinc's kleinian_de at N = 32, in 64-bit scalars
## (see DistanceEstimator for why). Knighty's pseudo-Kleinian, in 4D: fold
## each component back inside its own box, push points inside the inversion
## sphere out through it (never pull outside points in), shift, repeat, with a
## running scale dr. The distance is to Knighty's "thingy" — the thickened
## sheets |r_xy z| = thickness — whose images under the folds make the limit
## set, halved because the thingy's own field is steeper than 1, then divided
## by dr. The loop stops early once a step leaves the point unchanged.

const ITERATIONS := 32


## `iters` is clamped to [0, ITERATIONS], as DistanceEstimator's.
static func estimate_at(px: float, py: float, pz: float, params: FractalParams,
		iters: int = ITERATIONS) -> float:
	var b := [params.kleinian_box_0, params.kleinian_box_1, params.kleinian_box_2, params.kleinian_box_3]
	var shift := [params.kleinian_shift_0, params.kleinian_shift_1, params.kleinian_shift_2, params.kleinian_shift_3]
	var k := params.kleinian_radius * params.kleinian_radius
	var p := [px, py, pz, params.w]
	var dr := 1.0
	for _i in clampi(iters, 0, ITERATIONS):
		var before := [p[0], p[1], p[2], p[3]]
		for c in 4:
			p[c] = clampf(p[c], -b[c], b[c]) * 2.0 - p[c]
		var r2: float = p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3]
		var m := maxf(k / maxf(r2, 1e-12), 1.0)
		for c in 4:
			p[c] = p[c] * m + shift[c]
		dr *= m
		if p == before:
			break
	return thingy(p, params.kleinian_thickness) / dr


## Half Knighty's thingy field at the orbit's end point, unsigned.
static func thingy(p: Array, thickness: float) -> float:
	var rxy := sqrt(p[0] * p[0] + p[1] * p[1])
	var len2: float = p[0] * p[0] + p[1] * p[1] + p[2] * p[2] + p[3] * p[3]
	return absf(0.5 * (absf(rxy * p[2]) - thickness) / sqrt(len2 + absf(thickness)))
