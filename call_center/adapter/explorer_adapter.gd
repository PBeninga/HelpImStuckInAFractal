extends "res://call_center/adapter/ship_adapter.gd"
## The ship adapter for today's explorer: the only file in call_center/ that
## knows the game's classes. It reads and writes the game scene's public state
## (Main's `camera` CameraState, `params` FractalParams, `view` FractalView,
## `fly` FlyCamera, `table()`) and uses DistanceEstimator for clearance; it
## changes no game file. If those names change, this file is what to update.
##
## Controls: smooth turns, direct thrusts and an autopilot that turns to a
## point and cruises there without collision bounds. One manoeuvre at a time;
## a new one replaces the old; WASD cancels it (manual override); a paused tree
## freezes it (this node is PAUSABLE even under the always-on CallCenter).

const WORLD_UP := Vector3(0, 0, 1)
const METERS_PER_UNIT := 1000.0
## Margin for legacy visibility queries only; never gates agent movement.
const LOS_CLEARANCE := 0.007
const MAX_PITCH_DEG := 85.0
const TURN_DEG_PER_S := 110.0
const EscapePlanner := preload("res://src/mcp/escape_planner.gd")
const DIRECTIONS := ["forward", "back", "left", "right", "up", "down"]

## The game scene (duck-typed: camera, params, view, fly, table()).
var game: Node

## The active manoeuvre: {kind, phase, t, duration, ...}; empty when idle.
var _m: Dictionary = {}
var _next_instruction_id := 1


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


## A low-fidelity, multidirectional estimate of nearby surfaces for the agent.
func surrounding_geometry() -> Dictionary:
	var c := _camera()
	var gameplay: GameplaySettings = _params().gameplay
	var rays := FractalProbe.sample_surroundings(c.eye_x(), c.eye_y(), c.eye_z(),
		c.forward(), c.right(), c.up(), _params(), gameplay.surrounding_ray_count)
	for ray in rays:
		if ray["hit"]:
			ray["distance_m"] = float(ray["distance"]) * METERS_PER_UNIT
		else:
			ray["distance_m"] = null
	return {"ray_count": rays.size(), "units": "world (distance), metres (distance_m)", "rays": rays}


func set_pose(position: Vector3, look_at: Vector3) -> bool:
	stop("position reset")
	_camera().transform = Transform3D(Basis.IDENTITY, position).looking_at(look_at, WORLD_UP)
	return true


func clearance() -> float:
	return DistanceEstimator.scene_estimate_at(_camera().eye_x(), _camera().eye_y(), _camera().eye_z(), _params())


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
	var p := _params().active_shape()
	var shape_name: String = ["Mandelbox", "KIFS", "Kleinian", "Mandelbulb"][clampi(p.shape, 0, 3)]
	return {"type": shape_name, "scale": p.box_scale, "fold_limit": p.fold_limit,
		"min_radius": p.min_radius, "fixed_radius": p.fixed_radius,
		"iterations": DistanceEstimator.ITERATIONS}


func palettes() -> Array:
	return Array(FractalParams.COLOR_MODE_NAMES)


func set_palette(name: String) -> Dictionary:
	var i := FractalParams.COLOR_MODE_NAMES.find(name)
	if i < 0:
		return {"ok": false, "message": "Unknown palette '%s'." % name}
	game.look_table().set_default(&"color_mode", FractalParams.COLOR_MODE_IDS[i])
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
	if not DIRECTIONS.has(direction) or not is_finite(meters_wanted) or meters_wanted <= 0:
		return {"ok": false, "message": "Supply a direction and a positive finite distance."}
	var dir := _direction_vector(direction)
	var distance := meters_wanted / METERS_PER_UNIT
	var eye := Array(_camera().eye64())
	var target := [eye[0] + dir.x * distance, eye[1] + dir.y * distance, eye[2] + dir.z * distance]
	_stop_quietly()
	_m = {"kind": "thrust", "phase": "move", "target": target, "direction": direction}
	return _start_instruction()


func fly_to(point: Vector3, standoff: float, info: Dictionary = {}) -> Dictionary:
	var eye := _camera().eye()
	var target := point
	if standoff > 0 and eye.distance_to(point) > standoff:
		target -= (point - eye).normalized() * standoff
	return fly_to_point([target.x, target.y, target.z], info)


## Preserve doubles for nested fractals. No collision or zoom-floor gate.
func fly_to_point(point: Array, info: Dictionary = {}) -> Dictionary:
	var leg := _leg(point)
	_stop_quietly()
	var fwd: Vector3 = leg.direction if leg.distance > 0 else _camera().forward()
	_m = {"kind": "fly", "phase": "turn", "t": 0.0,
		"duration": rad_to_deg(_camera().forward().angle_to(fwd)) / TURN_DEG_PER_S,
		"q_from": _camera().transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(fwd).get_rotation_quaternion(), "target": point.duplicate()}
	_m.merge(info)
	return _start_instruction()


func face_point(point: Array) -> Dictionary:
	var leg := _leg(point)
	return _begin_turn(leg.direction if leg.distance > 0 else _camera().forward(), "face", {"target": point.duplicate()})


func navigation_pose() -> Dictionary:
	var c := _camera()
	return {"position": Array(c.eye64()), "facing": _vector(c.forward()),
		"right": _vector(c.right()), "up": _vector(c.up())}


func travel_speed() -> float:
	# Exactly the player's current Gameplay speed (including Shift and wheel).
	return game.fly.current_speed()


func escape_state() -> Dictionary:
	var c := _camera()
	var radius := _params().gameplay.exit_radius
	var radial := sqrt(c.eye_x() * c.eye_x() + c.eye_y() * c.eye_y() + c.eye_z() * c.eye_z())
	return {"escaped": _params().gameplay.is_outside(c), "center": [0, 0, 0],
		"radius": radius, "distance_to_boundary": maxf(radius - radial, 0.0), "units": "world"}


func depth_scan(args: Dictionary = {}) -> Dictionary:
	return game.view.request_depth_scan(args)


func plan_escape() -> Dictionary:
	return await EscapePlanner.new().plan(game)


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
	var out := {"active": true, "kind": _m.kind, "instruction_id": _m.instruction_id, "phase": _m.phase}
	var left := maxf(float(_m.get("duration", 0.0)) - float(_m.get("t", 0.0)), 0.0) if _m.phase == "turn" else 0.0
	if _m.has("target") and _m.kind != "face":
		out["target"] = _m.target
		var distance: float = _leg(_m.target).distance
		out["distance_remaining"] = distance
		left += distance / maxf(travel_speed(), 1e-30)
	out["seconds_left"] = left
	out["estimate_only"] = true
	return out


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if _m.is_empty() or game == null or not is_instance_valid(game):
		return
	if game.fly.move_direction() != Vector3.ZERO:
		stop("manual override")
		manual_override.emit()
		return
	if Array(_camera().eye64()) != _m.last_eye or _camera().transform.basis != _m.last_basis:
		stop("manual override or external camera change")
		manual_override.emit()
		return
	if _m.phase == "turn":
		var used := minf(delta, maxf(_m.duration - _m.t, 0.0))
		_m.t += used
		delta -= used
		var fraction := clampf(_m.t / maxf(_m.duration, 1e-12), 0.0, 1.0) if _m.duration > 0 else 1.0
		_camera().set_basis(Basis((_m.q_from as Quaternion).slerp(_m.q_to, fraction)))
		_m.last_basis = _camera().transform.basis
		if _m.t < _m.duration:
			return
		if _m.kind != "fly":
			_complete()
			return
		_m.phase = "move"
	if _m.phase == "move":
		var leg := _leg(_m.target)
		var distance := minf(travel_speed() * maxf(delta, 0.0), leg.distance)
		if distance >= leg.distance:
			_camera().set_eye(_m.target[0], _m.target[1], _m.target[2])
			_complete()
			return
		var c := _camera()
		var f: float = distance / leg.distance
		c.set_eye(c.eye_x() + leg.dx * f, c.eye_y() + leg.dy * f, c.eye_z() + leg.dz * f)
		_m.last_eye = Array(c.eye64())


func _complete() -> void:
	var m := _m
	_m = {}
	maneuver_finished.emit(m.kind, _finish_info(m, true, "arrived" if m.kind == "fly" else "done"))


# ------------------------------------------------------------- helpers

func _begin_turn(target_fwd: Vector3, kind: String, info: Dictionary) -> Dictionary:
	var angle := rad_to_deg(_camera().forward().angle_to(target_fwd))
	_stop_quietly()
	_m = {"kind": kind, "phase": "turn", "t": 0.0,
		"duration": angle / TURN_DEG_PER_S,
		"q_from": _camera().transform.basis.get_rotation_quaternion(),
		"q_to": _basis_for(target_fwd).get_rotation_quaternion()}
	_m.merge(info)
	var result := _start_instruction()
	result["turning_deg"] = angle
	return result


func _start_instruction() -> Dictionary:
	_m["last_eye"] = Array(_camera().eye64())
	_m["last_basis"] = _camera().transform.basis
	_m["instruction_id"] = _next_instruction_id
	_next_instruction_id += 1
	maneuver_started.emit(_m.kind, _m.duplicate(true))
	var state := autopilot_state()
	return {"ok": true, "instruction_id": _m.instruction_id, "seconds": state.seconds_left,
		"estimate_only": true, "message": "Instruction accepted; wait for instruction_completed or instruction_cancelled."}


func _leg(target: Array) -> Dictionary:
	var c := _camera()
	var dx: float = target[0] - c.eye_x()
	var dy: float = target[1] - c.eye_y()
	var dz: float = target[2] - c.eye_z()
	var distance := sqrt(dx * dx + dy * dy + dz * dz)
	return {"dx": dx, "dy": dy, "dz": dz, "distance": distance,
		"direction": Vector3(dx / distance, dy / distance, dz / distance) if distance > 0 else c.forward()}


static func _vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _stop_quietly() -> void:
	if not _m.is_empty():
		stop("replaced by a new command")


func _finish_info(m: Dictionary, completed: bool, reason: String) -> Dictionary:
	var info := {"completed": completed, "reason": reason, "instruction_id": m.instruction_id,
		"instruction_kind": m.kind}
	if is_instance_valid(game):
		info.merge(navigation_pose())
	else:
		var basis: Basis = m.last_basis
		info.merge({"position": m.last_eye, "facing": _vector(-basis.z)})
	for k in ["target", "direction"]:
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
	return Basis.looking_at(fwd, Vector3.UP if absf(fwd.dot(WORLD_UP)) > 0.999 else WORLD_UP)
