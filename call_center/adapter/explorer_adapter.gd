extends "res://call_center/adapter/ship_adapter.gd"
## The ship adapter for today's explorer: the only file in call_center/ that
## knows the game's classes. It reads and writes the game scene's public state
## (Main's `camera` CameraState, `params` FractalParams, `view` FractalView,
## `fly` FlyCamera, `table()`) and uses DistanceEstimator for clearance; it
## changes no game file. If those names change, this file is what to update.
##
## Controls: smooth turns, short thrusts that stop SAFE_CLEARANCE short of the
## fractal, and an autopilot that turns to a point and cruises to it along a
## straight leg it has checked is clear. One manoeuvre at a time; a new one
## replaces the old; WASD cancels it (manual override); a paused tree freezes
## it (this node is PAUSABLE even under the always-on CallCenter).

const WORLD_UP := Vector3(0, 0, 1)
const METERS_PER_UNIT := 1000.0
## A straight flight is allowed when the fractal stays this far away along it (7 m).
const LOS_CLEARANCE := 0.007
## Thrust stops this far from the surface (5 m).
const SAFE_CLEARANCE := 0.005
const MAX_PITCH_DEG := 85.0
const TURN_DEG_PER_S := 110.0
const CRUISE_M_PER_S := 120.0
const DIRECTIONS := ["forward", "back", "left", "right", "up", "down"]

## The game scene (duck-typed: camera, params, view, fly, table()).
var game: Node

## The active manoeuvre: {kind, phase, t, duration, ...}; empty when idle.
var _m: Dictionary = {}


func _init(p_game: Node = null) -> void:
	game = p_game
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Whether `node` looks like the explorer's Main.
static func fits(node: Node) -> bool:
	return node != null and node.get("camera") is CameraState and node.get("params") is FractalParams \
		and node.get("view") is FractalView


func _camera() -> CameraState:
	return game.camera


func _params() -> FractalParams:
	return game.params


# ------------------------------------------------------------- reading

func meters_per_unit() -> float:
	return METERS_PER_UNIT


func pose() -> Dictionary:
	var c := _camera()
	return {"position": c.eye(), "forward": c.forward(), "right": c.right(), "up": c.up()}


func set_pose(position: Vector3, look_at: Vector3) -> bool:
	_m = {}
	_camera().transform = Transform3D(Basis.IDENTITY, position).looking_at(look_at, WORLD_UP)
	return true


func clearance() -> float:
	return DistanceEstimator.estimate(_camera().eye(), _params())


func project(point: Vector3) -> Variant:
	return game.view.project(point)


func path_clear(a: Vector3, b: Vector3) -> bool:
	return trace_clear(a, b, LOS_CLEARANCE)


func visible_from_camera(point: Vector3) -> bool:
	var eye := _camera().eye()
	var rel := point - eye
	if rel.length() < 0.02:
		return true
	# traced to just short of the point, so a landmark on the surface does not hide itself
	return trace_clear(eye, point - rel.normalized() * 0.015, 0.0006)


## Sphere-traced: the estimate d at a point bounds the clearance of every point
## within s of it by d - s, so stepping d - margin never skips a pinch.
func trace_clear(a: Vector3, b: Vector3, margin: float) -> bool:
	var length := a.distance_to(b)
	if length < 1e-9:
		return DistanceEstimator.estimate(a, _params()) >= margin
	var dir := (b - a) / length
	var t := 0.0
	while true:
		var d := DistanceEstimator.estimate(a + dir * minf(t, length), _params())
		if d < margin:
			return false
		if t >= length:
			return true
		t += maxf(d - margin, margin * 0.25)
	return true


func world_info() -> Dictionary:
	# The active shape's knobs (the scene can hold several shapes).
	var p: Variant = _params().active_shape() if _params().has_method("active_shape") else _params()
	return {"type": "Mandelbox", "scale": p.box_scale, "fold_limit": p.fold_limit,
		"min_radius": p.min_radius, "fixed_radius": p.fixed_radius,
		"iterations": DistanceEstimator.ITERATIONS, "surface_hausdorff_dimension_estimate": 2.8}


func palettes() -> Array:
	return Array(FractalParams.COLOR_MODE_NAMES)


func set_palette(name: String) -> Dictionary:
	var i := FractalParams.COLOR_MODE_NAMES.find(name)
	if i < 0:
		return {"ok": false, "message": "Unknown palette '%s'." % name}
	# The colour mode is the scene's look (light and material), not a shape's.
	var table: AttributeTable = game.look_table() if game.has_method("look_table") else game.table()
	table.set_default(&"color_mode", FractalParams.COLOR_MODE_IDS[i])
	return {"ok": true}


# ------------------------------------------------------------- controls

func turn(yaw_deg: float, pitch_deg: float) -> Dictionary:
	var c := _camera()
	var fwd := c.forward().rotated(WORLD_UP, deg_to_rad(-yaw_deg))
	var pitch := clampf(rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0))) + pitch_deg, -MAX_PITCH_DEG, MAX_PITCH_DEG)
	var horiz := Vector3(fwd.x, fwd.y, 0.0)
	if horiz.length() < 1e-6:
		horiz = Vector3(c.right().y, -c.right().x, 0.0)
	horiz = horiz.normalized()
	return _begin_turn(horiz * cos(deg_to_rad(pitch)) + WORLD_UP * sin(deg_to_rad(pitch)), "turn", {})


func face(point: Vector3, info: Dictionary = {}) -> Dictionary:
	var dir := point - _camera().eye()
	if dir.length() < 1e-9:
		return {"ok": false, "message": "Already there."}
	return _begin_turn(_clamped_forward(dir.normalized()), "face", info)


func thrust(direction: String, meters_wanted: float) -> Dictionary:
	if not DIRECTIONS.has(direction):
		return {"ok": false, "message": "Unknown direction '%s'." % direction}
	var dir := _direction_vector(direction)
	var want := clampf(meters_wanted, 0.0, 5000.0) / METERS_PER_UNIT
	var allowed := free_distance(_camera().eye(), dir, want)
	if allowed < 0.0005:
		return {"ok": false, "reason": "obstructed", "moving_m": 0, "clearance_m": meters(clearance())}
	_stop_quietly()
	var eye := _camera().eye()
	_m = {"kind": "thrust", "phase": "move", "t": 0.0,
		"duration": clampf(0.8 + allowed * METERS_PER_UNIT / CRUISE_M_PER_S, 0.8, 10.0),
		"from": eye, "to": eye + dir * allowed, "direction": direction}
	maneuver_started.emit("thrust", {"direction": direction})
	return {"ok": true, "moving_m": meters(allowed), "requested_m": int(round(meters_wanted)),
		"obstructed": allowed < want - 1e-6, "seconds": snappedf(_m["duration"], 0.1)}


func fly_to(point: Vector3, standoff: float, info: Dictionary = {}) -> Dictionary:
	var eye := _camera().eye()
	var to := point
	var rel := point - eye
	if standoff > 0.0 and rel.length() > standoff:
		to = point - rel.normalized() * standoff
	var leg := to - eye
	if leg.length() < 0.002:
		return {"ok": true, "already_there": true, "distance_m": meters(leg.length())}
	if not path_clear(eye, to):
		return {"ok": false, "reason": "obstructed", "distance_m": meters(leg.length())}
	var target_fwd := _clamped_forward(leg.normalized())
	var turn_angle := rad_to_deg(_camera().forward().angle_to(target_fwd))
	_stop_quietly()
	var turn_s := clampf(turn_angle / TURN_DEG_PER_S, 0.3, 1.8)
	var cruise_s := clampf(1.5 + leg.length() * METERS_PER_UNIT / CRUISE_M_PER_S, 2.0, 12.0)
	_m = {"kind": "fly", "phase": "turn", "t": 0.0, "duration": turn_s,
		"q_from": _camera().transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(target_fwd).get_rotation_quaternion(),
		"cruise_duration": cruise_s, "from": eye, "to": to}
	_m.merge(info)
	maneuver_started.emit("fly", info)
	return {"ok": true, "distance_m": meters(leg.length()), "seconds": snappedf(turn_s + cruise_s, 0.1)}


func stop(reason := "stopped") -> bool:
	if _m.is_empty():
		return false
	var m := _m
	_m = {}
	maneuver_finished.emit(m["kind"], _finish_info(m, false, reason))
	return true


func autopilot_state() -> Dictionary:
	if _m.is_empty():
		return {"active": false, "kind": "idle"}
	var left: float = _m["duration"] - _m["t"]
	if _m["kind"] == "fly" and _m["phase"] == "turn":
		left += _m["cruise_duration"]
	return {"active": true, "kind": _m["kind"], "target_id": _m.get("target_id", ""),
		"seconds_left": snappedf(maxf(left, 0.0), 0.1)}


## How far the ship can move from `from` along unit `dir` (up to `limit`)
## before coming within SAFE_CLEARANCE of the surface.
func free_distance(from: Vector3, dir: Vector3, limit: float) -> float:
	var t := 0.0
	while t < limit:
		var d := DistanceEstimator.estimate(from + dir * t, _params())
		if d < SAFE_CLEARANCE:
			return maxf(0.0, t - SAFE_CLEARANCE * 0.5)
		t += maxf(d - SAFE_CLEARANCE, SAFE_CLEARANCE * 0.25)
	return limit


# ------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	step(delta)


## Advance the manoeuvre by `delta` seconds (the tests call this directly).
func step(delta: float) -> void:
	if _m.is_empty() or game == null or not is_instance_valid(game):
		return
	var fly: Variant = game.get("fly")
	if fly != null and fly.has_method("move_direction") and fly.move_direction() != Vector3.ZERO:
		stop("manual override")
		manual_override.emit()
		return
	var cam := _camera()
	_m["t"] = minf(_m["t"] + delta, _m["duration"])
	var s := _ease(_m["t"] / maxf(_m["duration"], 1e-6))
	if _m["phase"] == "turn":
		var q: Quaternion = (_m["q_from"] as Quaternion).slerp(_m["q_to"], s)
		cam.transform = Transform3D(Basis(q), cam.eye())
	else:
		var t := cam.transform
		t.origin = (_m["from"] as Vector3).lerp(_m["to"], s)
		cam.transform = t
	if _m["t"] < _m["duration"]:
		return
	if _m["kind"] == "fly" and _m["phase"] == "turn":
		_m["phase"] = "move"
		_m["t"] = 0.0
		_m["duration"] = _m["cruise_duration"]
		return
	var m := _m
	_m = {}
	maneuver_finished.emit(m["kind"], _finish_info(m, true, "arrived" if m["kind"] == "fly" else "done"))


# ------------------------------------------------------------- helpers

func _begin_turn(target_fwd: Vector3, kind: String, info: Dictionary) -> Dictionary:
	var angle := rad_to_deg(_camera().forward().angle_to(target_fwd))
	_stop_quietly()
	_m = {"kind": kind, "phase": "turn", "t": 0.0,
		"duration": clampf(angle / TURN_DEG_PER_S, 0.3, 2.0),
		"q_from": _camera().transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(target_fwd).get_rotation_quaternion()}
	_m.merge(info)
	maneuver_started.emit(kind, info)
	return {"ok": true, "turning_deg": int(round(angle)), "seconds": snappedf(_m["duration"], 0.1)}


func _stop_quietly() -> void:
	if not _m.is_empty():
		stop("replaced by a new command")


func _finish_info(m: Dictionary, completed: bool, reason: String) -> Dictionary:
	var info := {"completed": completed, "reason": reason}
	for k in ["target_id", "direction"]:
		if m.has(k):
			info[k] = m[k]
	return info


func _direction_vector(direction: String) -> Vector3:
	var c := _camera()
	match direction:
		"forward": return c.forward()
		"back": return -c.forward()
		"left": return -c.right()
		"right": return c.right()
		"up": return c.up()
		_: return -c.up()


## `dir` with its pitch held inside +/-MAX_PITCH_DEG, so looking_at never sees
## a forward parallel to world up.
func _clamped_forward(dir: Vector3) -> Vector3:
	var pitch := clampf(rad_to_deg(asin(clampf(dir.z, -1.0, 1.0))), -MAX_PITCH_DEG, MAX_PITCH_DEG)
	var horiz := Vector3(dir.x, dir.y, 0.0)
	if horiz.length() < 1e-6:
		horiz = _camera().forward() * Vector3(1, 1, 0)
	horiz = horiz.normalized()
	return horiz * cos(deg_to_rad(pitch)) + WORLD_UP * sin(deg_to_rad(pitch))


func _basis_for(fwd: Vector3) -> Basis:
	return Transform3D(Basis.IDENTITY, Vector3.ZERO).looking_at(fwd, WORLD_UP).basis


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
