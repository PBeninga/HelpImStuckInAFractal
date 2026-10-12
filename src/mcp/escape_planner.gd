extends RefCounted
## Bounded, receding-horizon route search. Costs integrate the player's speed;
## this is the fastest sampled route, never a guarantee of a global optimum.
const SAMPLES := 12
const TURN_SPEED := 110.0
var _params: FractalParams
var _speed_factor := 1.0
var _speed_limit := 1.0
var _sprint := false

func plan(game: Node) -> Dictionary:
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
	var radius := _params.escape_radius()
	var origin := _params.escape_origin()
	if _params.is_escaped(game.camera):
		return {"ok": true, "escaped": true, "points": [], "estimated_seconds": 0.0}
	var radial := Vector3(start[0] - origin[0], start[1] - origin[1], start[2] - origin[2]).normalized()
	if radial == Vector3.ZERO:
		radial = forward
	var directions: Array = [radial, forward]
	var scan: Dictionary = game.view.depth_scan()
	if scan.get("available", false) and not scan.get("scene_or_pose_changed", true):
		for patch in scan.get("open_patches", []):
			directions.append(Vector3(patch.direction[0], patch.direction[1], patch.direction[2]))
	# Spread the rest of the search around the player, including behind them.
	for i in 8:
		var z := 1.0 - 2.0 * (float(i) + 0.5) / 8.0
		var r := sqrt(1.0 - z * z)
		var angle := float(i) * 2.399963229728653
		directions.append(Vector3(cos(angle) * r, sin(angle) * r, z))
	var candidates: Array = []
	var near := DistanceEstimator.scene_estimate_at(start[0], start[1], start[2], _params)
	for direction in directions:
		var dir: Vector3 = direction
		var end := _exit_point(start, dir, radius, origin)
		candidates.append(_route(start, forward, [end]))
		# A short first leg can leave a slow pocket before turning outward.
		var distance := _distance(start, end)
		var step := minf(distance * 0.35, maxf(near * 4.0, radius * 0.001))
		var via := _along(start, dir, step)
		var outward := Vector3(via[0] - origin[0], via[1] - origin[1], via[2] - origin[2]).normalized()
		if outward == Vector3.ZERO:
			outward = dir
		candidates.append(_route(start, forward, [via, _exit_point(via, outward, radius, origin)]))
		# Let rendering/input continue between candidates; never flood the agent.
		await game.get_tree().process_frame
		if not is_instance_valid(game) or not game.is_inside_tree():
			return {"ok": false, "message": "Flight ended during route estimation."}
	candidates.sort_custom(func(a, b): return a.estimated_seconds < b.estimated_seconds)
	var best: Dictionary = candidates[0].duplicate(true)
	best.merge({"ok": true, "start": start, "facing": [forward.x, forward.y, forward.z],
		"units": "world", "candidate_count": candidates.size(), "approximate": true,
		"sprint": _sprint, "speed_factor": _speed_factor, "speed_limit": _speed_limit,
		"scene_or_pose_changed": start != Array(game.camera.eye64()) or not forward.is_equal_approx(game.camera.forward()) or not _matches_scene(game.params) or _speed_factor != game.camera.speed_factor or _speed_limit != game.fly.speed_limit or _sprint != game.fly.sprinting,
		"speed_model": "Player Gameplay speed, including CPU center ray; shader-only noise displacement does not affect player speed.",
		"message": "Fastest sampled route by estimated travel time. Fly one leg, wait for completion, then replan. Samples may miss narrow slow regions; this is not a global optimum."})
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
	if _params.gameplay_active != params.gameplay_active or _params.run_radius != params.run_radius or _params.run_origin != params.run_origin:
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
