class_name CenterRay
extends RefCounted
## The ray from the camera through the middle of the screen, sphere-traced on
## the CPU with DistanceEstimator: where it meets the fractal and how far away
## that is. The fly camera's speed follows the distance; the view paints a dot
## at the hit point when the probe is shown.
##
## The result is cached and only re-marched after the camera or a shape
## changes, so the fly camera and the view share one march per frame. The march
## mirrors the shader's: clipped to the union of the shapes' bounding cubes
## (each met in its own frame), stepping by the scene distance, stopping below
## the hit shape's threshold (FractalParams.hit_epsilon), from the camera's
## 64-bit eye. It does not see a noise field's displacement, which only the
## shader evaluates.

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
	var e := _camera.eye64()
	var f := _camera.forward()
	var t := _distance if _hit else 0.0
	return Vector3(e[0] + f.x * t, e[1] + f.y * t, e[2] + f.z * t)


func _mark_dirty() -> void:
	_dirty = true


func _update() -> void:
	if not _dirty:
		return
	_dirty = false
	var r := march_at(_camera.eye_x(), _camera.eye_y(), _camera.eye_z(), _camera.forward(), _params)
	_distance = r[0]
	_hit = r[1]


## Sphere-trace from `origin` along unit `dir`. Returns [distance, hit]:
## [t, true] on a hit, [INF, false] when the ray leaves every shape's cube (or
## passes a Kleinian's view distance), and
## [t_reached, false] when the step budget runs out first.
static func march(origin: Vector3, dir: Vector3, params: FractalParams) -> Array:
	return march_at(origin.x, origin.y, origin.z, dir, params)


## march() from a 64-bit origin.
static func march_at(ox: float, oy: float, oz: float, dir: Vector3, params: FractalParams) -> Array:
	var bounds: Variant = DistanceEstimator.scene_bounds(ox, oy, oz, dir, params)
	if bounds == null:
		return [INF, false]
	var t_exit: float = bounds[1]
	var near := maxf(DistanceEstimator.scene_estimate_at(ox, oy, oz, params), FractalParams.NEAR_FLOOR)
	var t: float = bounds[0]
	for _i in MAX_STEPS:
		var n := DistanceEstimator.nearest_at(ox + dir.x * t, oy + dir.y * t, oz + dir.z * t, params)
		var d: float = n["distance"]
		if d < params.hit_epsilon(t, near, params.shapes[n["index"]].precision):
			return [t, true]
		t += d
		if t > t_exit:
			return [INF, false]
	return [t, false]
