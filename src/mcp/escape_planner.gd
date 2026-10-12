extends RefCounted
## Choose a bounded flight leg from existing measured clearances. Favor the
## furthest observed corridor, then no-hit support and estimated travel time.
const SAMPLES := 12
const TURN_SPEED := 110.0
const DepthScan := preload("res://src/mcp/ship_depth_scan.gd")
var _params: FractalParams
var _speed_factor := 1.0
var _speed_limit := 1.0
var _sprint := false

func plan(game: Node, candidate_directions: Array = []) -> Dictionary:
	if candidate_directions.size() > 6:
		return {"ok": false, "message": "Supply at most six candidate_directions."}
	var extra: Array[Vector3] = []
	for candidate in candidate_directions:
		var direction := DepthScan.unit_direction(candidate)
		if direction == Vector3.ZERO:
			return {"ok": false, "message": "Each candidate direction must be three finite numbers forming a nonzero vector."}
		extra.append(direction)
	_params = game.params.duplicate(true) as FractalParams
	# Shapes and gameplay are runtime fields, not exported Resource properties.
	# Resource.duplicate alone would silently plan against the default scene.
	_params.gameplay.apply_dict(game.params.gameplay.to_dict())
	_params.copy_run_from(game.params)
	_params.set_shape_count(game.params.shapes.size())
	for i in game.params.shapes.size():
		_params.shapes[i].copy_from(game.params.shapes[i])
	_speed_factor = game.camera.speed_factor
	_speed_limit = game.fly.speed_limit
	_sprint = game.fly.sprinting
	var start := Array(game.camera.eye64())
	var forward: Vector3 = game.camera.forward()
	var radius := _params.gameplay_boundary_scene_distance()
	var origin := _params.run_origin
	if _params.is_escaped(game.camera):
		return {"ok": true, "escaped": true, "points": [], "estimated_seconds": 0.0}
	var observed: Array = []
	var scanner: Variant = game.get("ship_depth_scanner")
	if scanner != null:
		for recommendation in scanner.cached_recommendations(game):
			var candidate: Dictionary = recommendation.duplicate(true)
			candidate["clear_distance"] = candidate.neighbour_min_depth
			candidate["observation_source"] = "ship_depth_scan"
			observed.append(candidate)
	# A current deeper CPU scan takes precedence over display-depth samples.
	if observed.is_empty():
		var scan: Dictionary = game.view.depth_scan()
		if scan.get("available", false) and not scan.get("scene_or_pose_changed", true):
			for patch in scan.get("open_patches", []):
				var candidate: Dictionary = patch.duplicate(true)
				candidate["clear_distance"] = candidate.min_distance
				candidate["observation_source"] = "screen_depth_scan"
				observed.append(candidate)
	var candidates: Array = []
	for observation in observed:
		var dir := DepthScan.unit_direction(observation.direction)
		if dir == Vector3.ZERO:
			continue
		# Requested vectors restrict the measured candidates; they never create
		# an unobserved shortcut through the fractal or extend a measured ray.
		if not extra.is_empty() and not extra.any(func(d): return d.dot(dir) > 0.999999):
			continue
		var clear_distance := float(observation.clear_distance)
		if not is_finite(clear_distance) or clear_distance <= 0.0:
			continue
		var exit_clear := bool(observation.get("exit_clear", false))
		# Stop before the observed limit and look again. Only a whole patch
		# reaching the exit allows a final leg across the boundary.
		var end := _along(start, dir, clear_distance * 0.75)
		if exit_clear:
			var boundary_end := _exit_point(start, dir, radius, origin)
			# Scans measure to the rendering boundary. A speed-based gameplay
			# boundary may be farther away. Only the existing tiny crossing
			# margin may extend beyond measured clearance.
			exit_clear = _distance(start, boundary_end) <= clear_distance + radius * 0.0001
			if exit_clear:
				end = boundary_end
		var route := _route(start, forward, [end])
		route.merge({"direction": observation.direction, "clear_distance": clear_distance,
			"no_hit_fraction": observation.get("no_hit_fraction", 0.0), "exit_clear": exit_clear,
			"center_status": observation.get("center_status", "unknown"),
			"observation_source": observation.observation_source})
		candidates.append(route)
		await game.get_tree().process_frame
		if not is_instance_valid(game) or not game.is_inside_tree():
			return {"ok": false, "message": "Flight ended during route estimation."}
	if candidates.is_empty():
		return {"ok": false, "scan_required": true, "points": [],
			"message": "No current measured corridor matches. Request get_depth_scan or scan_ship_depth while stopped, then plan again. Do not fly toward an unmeasured exit point."}
	candidates.sort_custom(func(a, b):
		if not is_equal_approx(a.clear_distance, b.clear_distance):
			return a.clear_distance > b.clear_distance
		if not is_equal_approx(a.no_hit_fraction, b.no_hit_fraction):
			return a.no_hit_fraction > b.no_hit_fraction
		return a.estimated_seconds < b.estimated_seconds)
	var best: Dictionary = candidates[0].duplicate(true)
	best.merge({"ok": true, "start": start, "facing": [forward.x, forward.y, forward.z],
		"units": "world", "candidate_count": candidates.size(), "approximate": true,
		"extra_direction_count": candidate_directions.size(),
		"sprint": _sprint, "speed_factor": _speed_factor, "speed_limit": _speed_limit,
		"scene_or_pose_changed": start != Array(game.camera.eye64()) or not forward.is_equal_approx(game.camera.forward()) or not _matches_scene(game.params) or _speed_factor != game.camera.speed_factor or _speed_limit != game.fly.speed_limit or _sprint != game.fly.sprinting,
		"planning_mode": "observed_clearance", "replan_after_arrival": true,
		"speed_model": "Player Gameplay speed; autopilot additionally limits movement by collision clearance. Timing is approximate and covers this leg only.",
		"message": "One leg toward the furthest observed corridor, favoring no-hit rays on depth ties. Stops at 75% of observed clearance unless the patch reaches the exit. Fly this leg, wait for completion/collision cancellation, then observe and replan. No unobserved wall-crossing routes."})
	best["alternatives"] = candidates.slice(1, mini(4, candidates.size()))
	return best

func _route(start: Array, forward: Vector3, points: Array) -> Dictionary:
	var seconds := 0.0
	var distance := 0.0
	var here := start
	var facing := forward
	for point in points:
		var length := _distance(here, point)
		if length == 0:
			continue
		var dir := Vector3((point[0] - here[0]) / length, (point[1] - here[1]) / length, (point[2] - here[2]) / length)
		seconds += rad_to_deg(facing.angle_to(dir)) / TURN_SPEED
		if not _params.gameplay.distance_scaling:
			seconds += length / maxf(FlyCamera.speed_at(_params, here, dir, _speed_factor, _speed_limit, _sprint), 1e-30)
		else:
			# Denser samples close to the starting pocket. Trapezoidal integration
			# of inverse speed accounts for slow sections along the whole segment.
			var previous_t := 0.0
			var previous_inverse := 1.0 / maxf(FlyCamera.speed_at(_params, here, dir, _speed_factor, _speed_limit, _sprint), 1e-30)
			for i in range(1, SAMPLES + 1):
				var t := pow(float(i) / SAMPLES, 3.0)
				var at := _along(here, dir, length * t)
				var inverse := 1.0 / maxf(FlyCamera.speed_at(_params, at, dir, _speed_factor, _speed_limit, _sprint), 1e-30)
				seconds += length * (t - previous_t) * (previous_inverse + inverse) * 0.5
				previous_t = t
				previous_inverse = inverse
		distance += length
		here = point
		facing = dir
	return {"points": points, "estimated_seconds": seconds, "distance": distance}

static func _exit_point(eye: Array, dir: Vector3, radius: float, origin: Array = [0.0, 0.0, 0.0]) -> Array:
	var relative := [eye[0] - origin[0], eye[1] - origin[1], eye[2] - origin[2]]
	var b: float = relative[0] * dir.x + relative[1] * dir.y + relative[2] * dir.z
	var c: float = relative[0] * relative[0] + relative[1] * relative[1] + relative[2] * relative[2] - radius * radius
	var distance := maxf(-b + sqrt(maxf(b * b - c, 0.0)), 0.0) + radius * 0.0001
	return _along(eye, dir, distance)

static func _along(eye: Array, dir: Vector3, distance: float) -> Array:
	return [eye[0] + dir.x * distance, eye[1] + dir.y * distance, eye[2] + dir.z * distance]

static func _distance(a: Array, b: Array) -> float:
	var x: float = b[0] - a[0]
	var y: float = b[1] - a[1]
	var z: float = b[2] - a[2]
	return sqrt(x * x + y * y + z * z)


func _matches_scene(params: FractalParams) -> bool:
	if _params.gameplay_active != params.gameplay_active or _params.next_level_threshold != params.next_level_threshold or _params.world_unit_size != params.world_unit_size or _params.run_origin != params.run_origin:
		return false
	if _params.gameplay.to_dict() != params.gameplay.to_dict() or _params.shapes.size() != params.shapes.size():
		return false
	for i in _params.shapes.size():
		for key in ShapeParams.RESOLVED_KEYS:
			if _params.shapes[i].get(key) != params.shapes[i].get(key):
				return false
	for key in ["detail", "detail_range", "detail_falloff", "fractal_iterations",
			"kifs_bailout_margin", "mandelbulb_bailout_margin"]:
		if _params.get(key) != params.get(key):
			return false
	return true
