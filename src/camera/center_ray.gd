class_name CenterRay
extends RefCounted
## The ray from the camera through the middle of the screen, sphere-traced on
## the CPU with DistanceEstimator: where it meets the fractal and how far away
## that is. The fly camera's speed follows the distance; the view paints a dot
## at the hit point when the probe is shown.
##
## The result is cached and only re-marched after the camera or the shape
## changes, so the fly camera and the view share one march per frame. The march
## mirrors the shader's: clipped to the same bounding cube, stopping below the
## same hit threshold (FractalParams.hit_epsilon). It does not see a noise
## field's displacement, which only the shader evaluates.

## Step budget. A grazing ray that runs out keeps the distance it reached: a
## lower bound on the hit, so the speed it gives errs slow.
const MAX_STEPS := 64

var _params: FractalParams
var _camera: CameraState
var _dirty := true
var _distance := INF
var _hit := false


func _init(params: FractalParams, camera: CameraState) -> void:
	_params = params
	_camera = camera
	params.changed.connect(_mark_dirty)
	camera.changed.connect(_mark_dirty)


## Distance along the camera's forward axis to the surface; INF when the ray
## leaves the bounding cube without hitting anything.
func distance() -> float:
	_update()
	return _distance


## Whether the ray met the surface (false for a miss, or a march that ran out
## of steps before converging).
func hit() -> bool:
	_update()
	return _hit


## The world point the ray hit. Only meaningful while hit() is true.
func point() -> Vector3:
	_update()
	return _camera.eye() + _camera.forward() * (_distance if _hit else 0.0)


func _mark_dirty() -> void:
	_dirty = true


func _update() -> void:
	if not _dirty:
		return
	_dirty = false
	var r := march(_camera.eye(), _camera.forward(), _params)
	_distance = r[0]
	_hit = r[1]


## Sphere-trace from `origin` along unit `dir`. Returns [distance, hit]:
## [t, true] on a hit, [INF, false] when the ray leaves the shape's cube (or
## passes the Kleinian's view distance), and
## [t_reached, false] when the step budget runs out first.
static func march(origin: Vector3, dir: Vector3, params: FractalParams) -> Array:
	var tb := _box_intersect(origin, dir, params.bound_half())
	if params.view_distance() > 0.0:
		tb.y = minf(tb.y, params.view_distance())   # the shader stops there too
	if tb.y < maxf(tb.x, 0.0):
		return [INF, false]
	var near := maxf(DistanceEstimator.estimate(origin, params), FractalParams.NEAR_FLOOR)
	var t := maxf(tb.x, 0.0)
	for _i in MAX_STEPS:
		var p := origin + dir * t
		var d := DistanceEstimator.estimate_at(p.x, p.y, p.z, params)
		if d < params.hit_epsilon(t, near):
			return [t, true]
		t += d
		if t > tb.y:
			return [INF, false]
	return [t, false]


## Ray vs the origin-centred cube of half-size `half`: (t_enter, t_exit); a miss
## has t_exit < max(t_enter, 0). Mirrors box_intersect() in the shader.
static func _box_intersect(ro: Vector3, rd: Vector3, half: float) -> Vector2:
	var t_enter := -INF
	var t_exit := INF
	for i in 3:
		var r := rd[i]
		if absf(r) < 1e-9:
			r = 1e-9 if r >= 0.0 else -1e-9
		var inv := 1.0 / r
		var t1 := (-ro[i] - half) * inv
		var t2 := (-ro[i] + half) * inv
		t_enter = maxf(t_enter, minf(t1, t2))
		t_exit = minf(t_exit, maxf(t1, t2))
	return Vector2(t_enter, t_exit)
