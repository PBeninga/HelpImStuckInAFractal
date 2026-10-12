class_name FractalProbe
extends RefCounted
## CPU queries against the scene for the MCP bridge: march a ray to the nearest
## surface of any shape, estimate a surface normal. Built on the scene
## functions in DistanceEstimator (the union of every shape, each in its own
## frame) with the same hit threshold as DistanceEstimator.march, and a larger
## step budget, since an agent asks once rather than every frame. The eye is
## taken in 64-bit components, as CameraState keeps it.

const MAX_STEPS := 600


## March from the 64-bit point (ex, ey, ez) along `rd`. Returns {point (a
## Vector3), point64 ([x, y, z] floats), distance, steps, normal, shape (the hit
## shape's index)} on a hit, or null when the ray leaves every shape's cube or
## runs out of steps.
static func march(ex: float, ey: float, ez: float, rd: Vector3, params: FractalParams) -> Variant:
	rd = rd.normalized()
	var bounds: Variant = DistanceEstimator.scene_bounds(ex, ey, ez, rd, params)
	if bounds == null:
		return null
	var total: float = bounds[0]
	var t_exit: float = bounds[1]
	var near := DistanceEstimator.scene_estimate_at(ex, ey, ez, params)
	for i in MAX_STEPS:
		var px := ex + rd.x * total
		var py := ey + rd.y * total
		var pz := ez + rd.z * total
		var n := DistanceEstimator.nearest_at(px, py, pz, params)
		var d: float = n["distance"]
		var eps := params.hit_epsilon(total, near, params.shapes[n["index"]].precision)
		if d < eps:
			return {
				"point": Vector3(px, py, pz),
				"point64": [px, py, pz],
				"distance": total,
				"steps": i,
				"normal": normal(px, py, pz, params, maxf(eps, 1e-12)),
				"shape": n["index"],
			}
		total += d
		if total > t_exit:
			return null
	return null


## Central-difference gradient of the scene distance at a 64-bit point.
static func normal(px: float, py: float, pz: float, params: FractalParams, h: float) -> Vector3:
	var dx := DistanceEstimator.scene_estimate_at(px + h, py, pz, params) - DistanceEstimator.scene_estimate_at(px - h, py, pz, params)
	var dy := DistanceEstimator.scene_estimate_at(px, py + h, pz, params) - DistanceEstimator.scene_estimate_at(px, py - h, pz, params)
	var dz := DistanceEstimator.scene_estimate_at(px, py, pz + h, params) - DistanceEstimator.scene_estimate_at(px, py, pz - h, params)
	var n := Vector3(dx, dy, dz)
	return n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO
