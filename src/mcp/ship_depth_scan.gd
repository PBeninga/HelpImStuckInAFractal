extends RefCounted
## Explicit, expensive spherical CPU scan. One service per flight is shared by
## the direct MCP endpoint and voice tools, so neither can bypass its cooldown.
const DEFAULT_RAYS := 96
const MAX_RAYS := 256
const COOLDOWN_MS := 5000
const BUDGET_MS := 8000
const BATCH_SIZE := 4
var _busy := false
var _last_finished_ms := -COOLDOWN_MS

func scan(game: Node, args: Dictionary = {}) -> Dictionary:
	var raw_count: Variant = args.get("ray_count", DEFAULT_RAYS)
	if not _number(raw_count) or float(raw_count) != floor(float(raw_count)) or raw_count < 24 or raw_count > MAX_RAYS:
		return {"ok": false, "message": "ray_count must be an integer from 24 to 256."}
	var raw_range: Variant = args.get("max_distance", game.params.gameplay.exit_radius * 2.0)
	if not _number(raw_range) or float(raw_range) <= 0:
		return {"ok": false, "message": "max_distance must be a positive finite distance in world units."}
	if _busy:
		return {"ok": false, "busy": true, "message": "A full-ship depth scan is already running; wait for its result."}
	var now := Time.get_ticks_msec()
	if now - _last_finished_ms < COOLDOWN_MS:
		return {"ok": false, "throttled": true, "retry_after_ms": COOLDOWN_MS - (now - _last_finished_ms),
			"message": "Expensive scan cooldown; reuse the previous result."}
	_busy = true
	var started := Time.get_ticks_msec()
	# Runtime shape/gameplay fields must be copied explicitly as well as exports.
	var params := game.params.duplicate(true) as FractalParams
	params.gameplay.apply_dict(game.params.gameplay.to_dict())
	params.set_shape_count(game.params.shapes.size())
	for i in game.params.shapes.size():
		params.shapes[i].copy_from(game.params.shapes[i])
	var source: FractalParams = game.params
	var changed := [false]
	var mark_changed := func(): changed[0] = true
	source.changed.connect(mark_changed)
	var eye := Array(game.camera.eye64())
	var forward: Vector3 = game.camera.forward()
	var right: Vector3 = game.camera.right()
	var up: Vector3 = game.camera.up()
	var frame := Engine.get_process_frames()
	var tree: SceneTree = game.get_tree()
	var count := int(raw_count)
	var directions: Array[Vector3] = [forward, -forward, right, -right, up, -up]
	for i in count - 6:
		# Alternate hemispheres so even a budget-limited scan samples both sides.
		var index := i / 2 if i % 2 == 0 else count - 7 - i / 2
		var z := 1.0 - 2.0 * (float(index) + 0.5) / float(count - 6)
		var r := sqrt(maxf(0.0, 1.0 - z * z))
		var angle := FractalProbe.GOLDEN_ANGLE * float(index)
		directions.append((right * (r * cos(angle)) + up * (r * sin(angle)) + forward * z).normalized())
	var near := DistanceEstimator.scene_estimate_at(eye[0], eye[1], eye[2], params)
	var rays: Array = []
	for i in count:
		var ray := _depth(eye, directions[i], params, near, float(raw_range))
		ray["direction"] = _vector(directions[i])
		rays.append(ray)
		if Time.get_ticks_msec() - started >= BUDGET_MS:
			break
		if (i + 1) % BATCH_SIZE == 0 and i + 1 < count:
			await tree.process_frame
			if not is_instance_valid(game) or not game.is_inside_tree():
				source.changed.disconnect(mark_changed)
				_finish()
				return {"ok": false, "message": "Flight ended during the depth scan."}
	source.changed.disconnect(mark_changed)
	var stale: bool = changed[0] or source != game.params or eye != Array(game.camera.eye64()) or not forward.is_equal_approx(game.camera.forward()) or not up.is_equal_approx(game.camera.up())
	var result := {"ok": true, "expensive": true, "units": "world", "coverage": "full sphere around the ship",
		"requested_rays": count, "ray_count": rays.size(), "coverage_complete": rays.size() == count,
		"max_distance": float(raw_range), "max_steps_per_ray": FractalProbe.MAX_STEPS,
		"captured_at_ms": started, "frame_id": frame, "elapsed_ms": Time.get_ticks_msec() - started,
		"position": eye, "facing": _vector(forward), "right": _vector(right), "up": _vector(up),
		"scene_or_pose_changed": stale, "rays": rays, "recommended_directions": _recommend(rays, eye),
		"status_legend": {"surface": "approximate surface depth", "exit_background": "no surface found before exit sphere",
			"range_limit": "scan range or scene horizon reached; further depth unknown", "step_limit": "ray exhausted its steps; distance unknown",
			"unknown": "invalid estimate or no forward exit-sphere intersection"},
		"note": "CPU geometry estimate, including off-screen directions; excludes shader-only noise displacement. Sample gaps may hide obstacles. Recommendations rank broad distant regions, not travel time. look_at points are for turning, not flight destinations. No data is pushed automatically."}
	_finish()
	return result

func _finish() -> void:
	_busy = false
	_last_finished_ms = Time.get_ticks_msec()

## Unlike FractalProbe.march's picking API, preserve the reason a ray ended.
## No normals are computed: this call only needs depth.
static func _depth(eye: Array, dir: Vector3, params: FractalParams, near: float, max_distance: float) -> Dictionary:
	var b: float = eye[0] * dir.x + eye[1] * dir.y + eye[2] * dir.z
	var radial_squared: float = eye[0] * eye[0] + eye[1] * eye[1] + eye[2] * eye[2]
	var discriminant := b * b - radial_squared + params.gameplay.exit_radius * params.gameplay.exit_radius
	if not is_finite(discriminant) or discriminant < 0:
		return {"distance": null, "status": "unknown", "steps": 0}
	var sphere_end := -b + sqrt(discriminant)
	if sphere_end <= 0:
		return {"distance": null, "status": "unknown", "steps": 0}
	var far := minf(max_distance, sphere_end)
	var horizon := params.scene_view_distance()
	if horizon > 0:
		far = minf(far, horizon)
	var end_status := "exit_background" if far >= sphere_end else "range_limit"
	var bounds: Variant = DistanceEstimator.scene_bounds(eye[0], eye[1], eye[2], dir, params)
	if bounds == null or float(bounds[0]) >= far:
		return {"distance": far, "status": end_status, "steps": 0}
	var total: float = bounds[0]
	var end := minf(float(bounds[1]), far)
	for step in FractalProbe.MAX_STEPS:
		var n := DistanceEstimator.nearest_at(eye[0] + dir.x * total, eye[1] + dir.y * total, eye[2] + dir.z * total, params)
		var d: float = n.distance
		if not is_finite(d):
			return {"distance": null, "status": "unknown", "steps": step + 1}
		if d < params.hit_epsilon(total, near, params.shapes[n.index].precision):
			return {"distance": total, "status": "surface", "steps": step + 1}
		var next := total + d
		if next > end:
			return {"distance": far, "status": end_status, "steps": step + 1}
		if next <= total:
			break
		total = next
	return {"distance": null, "traced_distance": total, "status": "step_limit", "steps": FractalProbe.MAX_STEPS}

## Rank each ray with its four nearest angular neighbours. Reject incomplete
## rays, so an isolated long ray or an exhausted march is not an open corridor.
static func _recommend(rays: Array, eye: Array) -> Array:
	var candidates: Array = []
	for i in rays.size():
		var center: Array = rays[i].direction
		var neighbours: Array = []
		for j in rays.size():
			var other: Array = rays[j].direction
			neighbours.append({"index": j, "alignment": center[0] * other[0] + center[1] * other[1] + center[2] * other[2]})
		neighbours.sort_custom(func(a, b): return a.alignment > b.alignment)
		var depth := INF
		var valid := neighbours.size() >= 5
		for neighbour in neighbours.slice(0, 5):
			var ray: Dictionary = rays[neighbour.index]
			if ray.status != "surface" and ray.status != "exit_background":
				valid = false
				break
			depth = minf(depth, float(ray.distance))
		if valid and depth > 0:
			candidates.append({"ray_index": i, "direction": center, "neighbour_min_depth": depth,
				"supporting_rays": 5, "look_at": [eye[0] + center[0], eye[1] + center[1], eye[2] + center[2]]})
	candidates.sort_custom(func(a, b): return a.neighbour_min_depth > b.neighbour_min_depth)
	var best: Array = []
	for candidate in candidates:
		var dir: Array = candidate.direction
		if best.any(func(p): return dir[0] * p.direction[0] + dir[1] * p.direction[1] + dir[2] * p.direction[2] > 0.9):
			continue
		best.append(candidate)
		if best.size() == 6:
			break
	return best

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
