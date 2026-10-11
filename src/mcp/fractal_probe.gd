class_name FractalProbe
extends RefCounted
## CPU queries against the distance estimator for the MCP bridge: march a ray
## to the surface, estimate a surface normal. Same hit threshold and bounding
## box as OrbitCamera._march, with a larger step budget, since an agent asks
## once rather than every frame.

const MAX_STEPS := 600


## March from `ro` along `rd` (normalised). Returns {point, distance, steps,
## normal} on a hit, or null when the ray leaves the bounding box or runs out
## of steps.
static func march(ro: Vector3, rd: Vector3, params: FractalParams) -> Variant:
	rd = rd.normalized()
	var box_half := 20.0 if params.julia_enabled() else 2.0
	var tb := _box(ro, rd, box_half)
	if tb.y < maxf(tb.x, 0.0):
		return null
	var total := maxf(tb.x, 0.0)
	var near := DistanceEstimator.estimate(ro, params)
	for i in MAX_STEPS:
		var pos := ro + rd * total
		var d := DistanceEstimator.estimate(pos, params)
		var eps := params.hit_epsilon(total, near)
		if d < eps:
			return {
				"point": pos,
				"distance": total,
				"steps": i,
				"normal": normal(pos, params, maxf(eps, 1e-7)),
			}
		total += d
		if total > tb.y:
			return null
	return null


## Central-difference gradient of the distance estimate at `p`.
static func normal(p: Vector3, params: FractalParams, h: float) -> Vector3:
	var dx := DistanceEstimator.estimate_at(p.x + h, p.y, p.z, params) - DistanceEstimator.estimate_at(p.x - h, p.y, p.z, params)
	var dy := DistanceEstimator.estimate_at(p.x, p.y + h, p.z, params) - DistanceEstimator.estimate_at(p.x, p.y - h, p.z, params)
	var dz := DistanceEstimator.estimate_at(p.x, p.y, p.z + h, params) - DistanceEstimator.estimate_at(p.x, p.y, p.z - h, params)
	var n := Vector3(dx, dy, dz)
	return n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO


## Ray/AABB slab test against the cube of half-size `half_size`: (t_enter, t_exit).
static func _box(ro: Vector3, rd: Vector3, half_size: float) -> Vector2:
	var t0 := -INF
	var t1 := INF
	for a in 3:
		var d := rd[a]
		if absf(d) < 1e-12:
			if absf(ro[a]) > half_size:
				return Vector2(1.0, 0.0)
			continue
		var ta := (-half_size - ro[a]) / d
		var tb := (half_size - ro[a]) / d
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)
