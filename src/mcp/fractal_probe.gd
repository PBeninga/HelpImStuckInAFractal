class_name FractalProbe
extends RefCounted
## CPU queries against the scene for the MCP bridge: march a ray to the nearest
## surface of any shape, estimate a surface normal. Built on the scene
## functions in DistanceEstimator (the union of every shape, each in its own
## frame) with the same hit threshold as DistanceEstimator.march, and a larger
## step budget, since an agent asks once rather than every frame. The eye is
## taken in 64-bit components, as CameraState keeps it.

const MAX_STEPS := 600
const GOLDEN_ANGLE := 2.399963229728653


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


## Approximate nearby geometry with an even distribution of rays over the
## sphere. Each ray direction is expressed in world space; misses are explicit.
static func sample_surroundings(ex: float, ey: float, ez: float, forward: Vector3, right: Vector3,
		up: Vector3, params: FractalParams, ray_count: int) -> Array:
	var rays: Array = []
	var count := clampi(ray_count, 4, 64)
	for i in count:
		var z := 1.0 - 2.0 * (float(i) + 0.5) / float(count)
		var radius := sqrt(maxf(0.0, 1.0 - z * z))
		var angle := GOLDEN_ANGLE * float(i)
		var local := Vector3(radius * cos(angle), radius * sin(angle), z)
		var direction := (right * local.x + up * local.y + forward * local.z).normalized()
		var hit: Variant = march(ex, ey, ez, direction, params)
		rays.append({
			"direction": [direction.x, direction.y, direction.z],
			"hit": hit != null,
			"distance": hit["distance"] if hit != null else null,
		})
	return rays


## Central-difference gradient of the scene distance at a 64-bit point.
static func normal(px: float, py: float, pz: float, params: FractalParams, h: float) -> Vector3:
	var dx := DistanceEstimator.scene_estimate_at(px + h, py, pz, params) - DistanceEstimator.scene_estimate_at(px - h, py, pz, params)
	var dy := DistanceEstimator.scene_estimate_at(px, py + h, pz, params) - DistanceEstimator.scene_estimate_at(px, py - h, pz, params)
	var dz := DistanceEstimator.scene_estimate_at(px, py, pz + h, params) - DistanceEstimator.scene_estimate_at(px, py, pz - h, params)
	var n := Vector3(dx, dy, dz)
	return n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO
