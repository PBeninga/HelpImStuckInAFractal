class_name SurfaceFinder
extends RefCounted
## One-shot recovery using the same CPU surface and visibility limits as the
## centre ray (shader-only noise displacement is not included). The nearest
## confirmed sampled hit wins; this is not an exact closest-point solver.

const RAY_COUNT := 256
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))


## Return {direction, distance} or an empty dictionary on a miss. Keep the
## direction and scalar distance: subtracting rounded world-space hit points
## would lose the direction at deep zoom.
static func find(params: FractalParams, camera: CameraState) -> Dictionary:
	var directions: Array[Vector3] = [camera.forward(), Vector3.RIGHT, Vector3.LEFT,
		Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	# Explicit shape-centre rays can find a tiny distant shape between the
	# uniform samples. Subtract in 64-bit before constructing a Vector3.
	for shape in params.shapes:
		var delta := Vector3(shape.pos_x - camera.eye_x(), shape.pos_y - camera.eye_y(),
			shape.pos_z - camera.eye_z())
		if delta.length_squared() > 0.0:
			directions.append(delta.normalized())
	# Fibonacci sphere: even coverage of both hemispheres without pole clumps.
	for i in RAY_COUNT:
		var z := 1.0 - 2.0 * (i + 0.5) / RAY_COUNT
		var radius := sqrt(1.0 - z * z)
		var angle := GOLDEN_ANGLE * i
		directions.append(Vector3(radius * cos(angle), radius * sin(angle), z).normalized())
	var best := {}
	for direction in directions:
		_consider(direction, params, camera, best)
	# Refine around the winning ray so the view aims near the closest part of
	# a surface rather than stopping at the spacing of the spherical samples.
	var spread := 0.15
	for level in 3:
		if best.is_empty():
			break
		var forward: Vector3 = best.direction
		var basis := CameraState.facing_basis(forward)
		for i in 8:
			var angle := TAU * i / 8.0
			var direction := (forward + spread * (basis.x * cos(angle) + basis.y * sin(angle))).normalized()
			_consider(direction, params, camera, best)
		spread *= 0.25
	return best


static func _consider(direction: Vector3, params: FractalParams, camera: CameraState, best: Dictionary) -> void:
	var hit := CenterRay.march_at(camera.eye_x(), camera.eye_y(), camera.eye_z(), direction, params)
	# Exhausting a march budget is not a hit. A zero-distance hit at the eye
	# has no meaningful facing direction, so leave it alone as well.
	if hit[1] and is_finite(hit[0]) and hit[0] > 0.0 and hit[0] < best.get("distance", INF):
		best["direction"] = direction
		best["distance"] = hit[0]
