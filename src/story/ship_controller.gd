class_name ShipController
extends Node
## Flies the ship (the shared CameraState) for the support agent: smooth turns,
## short thrusts that stop before the fractal, and an autopilot that turns to a
## point and cruises to it along a straight leg it has checked is clear. One
## manoeuvre at a time; a new one replaces the old. Any WASD input cancels it
## (manual override), and a paused tree freezes it.

signal maneuver_started(kind: String, info: Dictionary)
## `info.completed` is false when it was cancelled; `info.reason` says why.
signal maneuver_finished(kind: String, info: Dictionary)
signal manual_override

const WORLD_UP := Vector3(0, 0, 1)
## Thrust stops this far from the surface (5 m).
const SAFE_CLEARANCE := 0.005
const MAX_PITCH_DEG := 85.0
## Turn speed and cruise speed for the autopilot.
const TURN_DEG_PER_S := 110.0
const CRUISE_M_PER_S := 120.0
const DIRECTIONS := ["forward", "back", "left", "right", "up", "down"]

var _params: FractalParams
var _camera: CameraState
var _fly: FlyCamera
## The active manoeuvre: {kind, phase, t, duration, ...}; empty when idle.
var _m: Dictionary = {}


func setup(params: FractalParams, camera: CameraState, fly: FlyCamera = null) -> void:
	_params = params
	_camera = camera
	_fly = fly


func busy() -> bool:
	return not _m.is_empty()


## What the ship is doing: {active, kind, target_id, seconds_left}.
func state() -> Dictionary:
	if _m.is_empty():
		return {"active": false, "kind": "idle"}
	var left: float = _m["duration"] - _m["t"]
	if _m["kind"] == "fly" and _m["phase"] == "turn":
		left += _m["cruise_duration"]
	return {"active": true, "kind": _m["kind"], "target_id": _m.get("target_id", ""),
		"seconds_left": snappedf(maxf(left, 0.0), 0.1)}


# ------------------------------------------------------------- commands

## Turn by `yaw_deg` (positive = right) and `pitch_deg` (positive = up).
func turn_by(yaw_deg: float, pitch_deg: float) -> Dictionary:
	var fwd := _camera.forward().rotated(WORLD_UP, deg_to_rad(-yaw_deg))
	var pitch := clampf(rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0))) + pitch_deg, -MAX_PITCH_DEG, MAX_PITCH_DEG)
	var horiz := Vector3(fwd.x, fwd.y, 0.0)
	if horiz.length() < 1e-6:
		horiz = Vector3(_camera.right().y, -_camera.right().x, 0.0)
	horiz = horiz.normalized()
	var target := horiz * cos(deg_to_rad(pitch)) + WORLD_UP * sin(deg_to_rad(pitch))
	return _begin_turn(target, "turn", {})


## Turn to look at `point`.
func face(point: Vector3, info: Dictionary = {}) -> Dictionary:
	var dir := point - _camera.eye()
	if dir.length() < 1e-9:
		return {"ok": false, "reason": "already there"}
	return _begin_turn(_clamped_forward(dir.normalized()), "face", info)


## Move `meters` along a camera-relative direction ("forward", "left", ...),
## stopping SAFE_CLEARANCE short of the fractal.
func thrust(direction: String, meters: float) -> Dictionary:
	if not DIRECTIONS.has(direction):
		return {"ok": false, "reason": "unknown direction '%s'" % direction}
	var dir := _direction_vector(direction)
	var want := clampf(meters, 0.0, 5000.0) / Route.METERS_PER_UNIT
	var allowed := free_distance(_camera.eye(), dir, want)
	var obstructed := allowed < want - 1e-6
	if allowed < 0.0005:
		return {"ok": false, "reason": "obstructed", "moved_m": 0,
			"clearance_m": Route.meters(DistanceEstimator.estimate(_camera.eye(), _params))}
	_stop_quietly()
	_m = {"kind": "thrust", "phase": "move", "t": 0.0,
		"duration": clampf(0.8 + allowed * Route.METERS_PER_UNIT / CRUISE_M_PER_S, 0.8, 10.0),
		"from": _camera.eye(), "to": _camera.eye() + dir * allowed,
		"direction": direction, "obstructed": obstructed}
	maneuver_started.emit("thrust", {"direction": direction})
	return {"ok": true, "moving_m": Route.meters(allowed), "requested_m": int(round(meters)),
		"obstructed": obstructed, "seconds": snappedf(_m["duration"], 0.1)}


## Autopilot to `point`: stop `standoff` short of it. Refuses when the straight
## leg comes within Route.LOS_CLEARANCE of the fractal.
func fly_to(point: Vector3, standoff := 0.0, info: Dictionary = {}) -> Dictionary:
	var eye := _camera.eye()
	var to := point
	var rel := point - eye
	if standoff > 0.0 and rel.length() > standoff:
		to = point - rel.normalized() * standoff
	var leg := to - eye
	if leg.length() < 0.002:
		return {"ok": true, "already_there": true, "distance_m": Route.meters(leg.length())}
	if not Route.path_clear(eye, to, _params):
		return {"ok": false, "reason": "obstructed",
			"distance_m": Route.meters(leg.length())}
	var target_fwd := _clamped_forward(leg.normalized())
	var turn_angle := rad_to_deg(_camera.forward().angle_to(target_fwd))
	_stop_quietly()
	var turn_s := clampf(turn_angle / TURN_DEG_PER_S, 0.3, 1.8)
	var cruise_s := clampf(1.5 + leg.length() * Route.METERS_PER_UNIT / CRUISE_M_PER_S, 2.0, 12.0)
	_m = {"kind": "fly", "phase": "turn", "t": 0.0, "duration": turn_s,
		"q_from": _camera.transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(target_fwd).get_rotation_quaternion(),
		"cruise_duration": cruise_s, "from": eye, "to": to}
	_m.merge(info)
	maneuver_started.emit("fly", info)
	return {"ok": true, "distance_m": Route.meters(leg.length()),
		"seconds": snappedf(turn_s + cruise_s, 0.1)}


## Cancel whatever is running. Returns whether anything was.
func stop(reason := "stopped") -> bool:
	if _m.is_empty():
		return false
	var m := _m
	_m = {}
	maneuver_finished.emit(m["kind"], _finish_info(m, false, reason))
	return true


# ------------------------------------------------------------- queries

## How far the ship can move from `from` along unit `dir` (up to `limit`)
## before coming within SAFE_CLEARANCE of the surface. Sphere-traced as in
## Route.path_clear.
func free_distance(from: Vector3, dir: Vector3, limit: float) -> float:
	var t := 0.0
	while t < limit:
		var d := DistanceEstimator.estimate(from + dir * t, _params)
		if d < SAFE_CLEARANCE:
			return maxf(0.0, t - SAFE_CLEARANCE * 0.5)
		t += maxf(d - SAFE_CLEARANCE, SAFE_CLEARANCE * 0.25)
	return limit


## Where `point` is relative to the ship: range, bearing (degrees, positive =
## right), elevation (positive = up), and a plain-words direction.
static func relative(camera: CameraState, point: Vector3) -> Dictionary:
	var rel := point - camera.eye()
	var f := rel.dot(camera.forward())
	var r := rel.dot(camera.right())
	var u := rel.dot(camera.up())
	var bearing := rad_to_deg(atan2(r, f))
	var elevation := rad_to_deg(atan2(u, sqrt(f * f + r * r)))
	return {"range_m": Route.meters(rel.length()), "bearing_deg": int(round(bearing)),
		"elevation_deg": int(round(elevation)), "direction": describe(bearing, elevation)}


## "ahead", "behind-left", "right, above" ...
static func describe(bearing: float, elevation: float) -> String:
	var a := absf(bearing)
	var side := "right" if bearing > 0.0 else "left"
	var horiz := ""
	if a <= 12.0:
		horiz = "dead ahead"
	elif a <= 40.0:
		horiz = "ahead, slightly %s" % side
	elif a <= 70.0:
		horiz = "ahead-%s" % side
	elif a <= 110.0:
		horiz = "to the %s" % side
	elif a <= 160.0:
		horiz = "behind-%s" % side
	else:
		horiz = "directly behind"
	if elevation > 25.0:
		horiz += ", well above"
	elif elevation > 8.0:
		horiz += ", slightly above"
	elif elevation < -25.0:
		horiz += ", well below"
	elif elevation < -8.0:
		horiz += ", slightly below"
	return horiz


# ------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	step(delta)


## Advance the manoeuvre by `delta` seconds (the tests call this directly).
func step(delta: float) -> void:
	if _m.is_empty():
		return
	if _fly != null and not _fly.input_locked and _fly.move_direction() != Vector3.ZERO:
		stop("manual override")
		manual_override.emit()
		return
	_m["t"] = minf(_m["t"] + delta, _m["duration"])
	var s := _ease(_m["t"] / maxf(_m["duration"], 1e-6))
	if _m["phase"] == "turn":
		var q: Quaternion = (_m["q_from"] as Quaternion).slerp(_m["q_to"], s)
		_camera.transform = Transform3D(Basis(q), _camera.eye())
	else:
		var t := _camera.transform
		t.origin = (_m["from"] as Vector3).lerp(_m["to"], s)
		_camera.transform = t
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
	var angle := rad_to_deg(_camera.forward().angle_to(target_fwd))
	_stop_quietly()
	_m = {"kind": kind, "phase": "turn", "t": 0.0,
		"duration": clampf(angle / TURN_DEG_PER_S, 0.3, 2.0),
		"q_from": _camera.transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(target_fwd).get_rotation_quaternion()}
	_m.merge(info)
	maneuver_started.emit(kind, info)
	return {"ok": true, "turning_deg": int(round(angle)), "seconds": snappedf(_m["duration"], 0.1)}


func _stop_quietly() -> void:
	if not _m.is_empty():
		stop("replaced by a new command")


func _finish_info(m: Dictionary, completed: bool, reason: String) -> Dictionary:
	var info := {"completed": completed, "reason": reason}
	for k in ["target_id", "direction", "obstructed"]:
		if m.has(k):
			info[k] = m[k]
	return info


func _direction_vector(direction: String) -> Vector3:
	match direction:
		"forward": return _camera.forward()
		"back": return -_camera.forward()
		"left": return -_camera.right()
		"right": return _camera.right()
		"up": return _camera.up()
		_: return -_camera.up()


## `dir` with its pitch held inside +/-MAX_PITCH_DEG, so looking_at never sees
## a forward parallel to world up.
func _clamped_forward(dir: Vector3) -> Vector3:
	var pitch := clampf(rad_to_deg(asin(clampf(dir.z, -1.0, 1.0))), -MAX_PITCH_DEG, MAX_PITCH_DEG)
	var horiz := Vector3(dir.x, dir.y, 0.0)
	if horiz.length() < 1e-6:
		horiz = _camera.forward() * Vector3(1, 1, 0)
	horiz = horiz.normalized()
	return horiz * cos(deg_to_rad(pitch)) + WORLD_UP * sin(deg_to_rad(pitch))


func _basis_for(fwd: Vector3) -> Basis:
	return Transform3D(Basis.IDENTITY, Vector3.ZERO).looking_at(fwd, WORLD_UP).basis


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
