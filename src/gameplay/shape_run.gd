class_name ShapeRun
extends RefCounted
## Transient objectives/overrides. Authoring data is never modified by an agent.
signal changed
signal units_changed
signal fog_changed(alpha: float)
signal stage_activated(index: int)
const FADE_SECONDS := 0.7
const HUMAN_WINDOW_MS := 60000
var escaped := false
var fog_alpha := 0.0
var command_index := 0
var human_turn := 0
var _serial := 0
var _units_captured := false
var _session_id := Crypto.new().generate_random_bytes(16).hex_encode()
var _phase := 0 # idle, covering, opaque hold, revealing
var _elapsed := 0.0
var _human_at := -HUMAN_WINDOW_MS - 1
var _overrides: Dictionary = {}
var _shapes: ShapeList
var _params: FractalParams
var _camera: CameraState

func _init(shapes: ShapeList, params: FractalParams, camera: CameraState) -> void:
	_shapes = shapes
	_params = params
	_camera = camera

func run_id() -> String:
	return "%s:%s" % [_session_id, _serial]

func reset() -> void:
	_serial += 1
	_units_captured = false
	_params.world_unit_size = 1.0
	_overrides.clear()
	escaped = false
	_phase = 0
	_elapsed = 0.0
	fog_alpha = 0.0
	_params.run_origin = _params.gameplay.spawn_position()
	_activate(0)
	fog_changed.emit(0.0)

func _activate(index: int) -> void:
	_params.gameplay_active = index
	command_index = 0
	invalidate_human_message()
	_sync_boundary()
	stage_activated.emit(index)
	changed.emit()

func _sync_boundary() -> void:
	var i := clampi(_params.gameplay_active, 0, _shapes.count() - 1)
	_params.next_level_threshold = _shapes.next_level_threshold(i)
	_params.run_escaped = escaped

func refresh_boundary() -> void:
	_sync_boundary()
	_params.emit_changed()

func transitioning() -> bool:
	return _phase != 0

func overrides(index: int) -> Dictionary:
	return _overrides.get(index, {})

func note_human_message(text: String) -> void:
	if not text.strip_edges().is_empty() and not escaped and not transitioning():
		_human_at = Time.get_ticks_msec()
		human_turn += 1

func invalidate_human_message() -> void:
	_human_at = -HUMAN_WINDOW_MS - 1

func apply_command(command: String, expected_run: String, expected_stage: int, expected_command_index: int, expected_human_turn: int) -> Dictionary:
	var i := _params.gameplay_active
	if expected_run != run_id() or expected_stage != i or expected_command_index != command_index or expected_human_turn != human_turn:
		return {"ok": false, "message": "Stale run or inactive shape. Read get_ship_status."}
	if escaped or transitioning() or Time.get_ticks_msec() - _human_at > HUMAN_WINDOW_MS:
		return {"ok": false, "message": "A new human utterance is required; never change shapes unprompted or during a transition."}
	var commands := _shapes.entry(i).commands
	if command_index >= commands.size() or command != commands[command_index]:
		return {"ok": false, "message": "Command does not match the active shape's next scripted step."}
	var values := {}
	for key in ShapeParams.RESOLVED_KEYS:
		values[key] = _params.shapes[i].get(key)
	var result := ShapeCommand.parse(command, _shapes.table(i), values)
	if not result.ok:
		return result
	if not _overrides.has(i):
		_overrides[i] = {}
	_overrides[i][result.id] = result.value
	command_index += 1
	invalidate_human_message()
	changed.emit()
	return {"ok": true, "shape_index": i, "command": command, "attribute": result.id, "value": result.value}

## All gameplay distances share the starting flight speed's fixed one-second unit.
func distance_from_origin() -> float:
	var origin := _params.run_origin
	var unit := _params.world_unit_size
	var x: float = (_camera.eye_x() - origin[0]) / unit
	var y: float = (_camera.eye_y() - origin[1]) / unit
	var z: float = (_camera.eye_z() - origin[2]) / unit
	return sqrt(x * x + y * y + z * z)

## Capture once after resolving the starting geometry and placing the camera.
func capture_start_speed(speed: float) -> void:
	if _units_captured or not is_finite(speed) or speed <= 0.0:
		return
	_units_captured = true
	_params.world_unit_size = speed
	units_changed.emit()

func check_position() -> void:
	if escaped or transitioning() or _params.gameplay_active < 0:
		return
	var i := _params.gameplay_active
	if distance_from_origin() <= _params.next_level_threshold:
		return
	invalidate_human_message()
	if i + 1 == _shapes.count():
		escaped = true
		_params.run_escaped = true
		changed.emit()
	else:
		_phase = 1
		_elapsed = 0.0
		changed.emit()

func step(delta: float) -> void:
	if _phase == 0:
		return
	if _phase == 2:
		# Keep an opaque frame after replacing geometry, including low FPS.
		_phase = 3
		_elapsed = 0.0
		return
	_elapsed = minf(_elapsed + delta, FADE_SECONDS)
	var t := smoothstep(0.0, FADE_SECONDS, _elapsed)
	fog_alpha = t if _phase == 1 else 1.0 - t
	fog_changed.emit(fog_alpha)
	if _elapsed < FADE_SECONDS:
		return
	if _phase == 1:
		_phase = 2
		# Hide the return to origin under opaque fog before revealing the next shape.
		_camera.set_eye(_params.run_origin[0], _params.run_origin[1], _params.run_origin[2])
		_activate(_params.gameplay_active + 1)
	else:
		_phase = 0
		changed.emit()

func briefing() -> Dictionary:
	var stages: Array = []
	for i in _shapes.count():
		var e := _shapes.entry(i)
		stages.append({"shape_index": i, "label": e.label,
			"next_level_distance": _shapes.next_level_distance(i),
			"next_level_threshold": _shapes.next_level_threshold(i),
			"commands": Array(e.commands)})
	var index := _params.gameplay_active
	var commands := _shapes.entry(index).commands
	return {"run_id": run_id(), "active_shape": index, "stages": stages,
		"command_index": command_index, "human_turn": human_turn, "next_command": commands[command_index] if command_index < commands.size() else "",
		"origin": _params.run_origin.duplicate(), "transitioning": transitioning(), "escaped": escaped,
		"instructions": "Scripted commands are optional shape changes and never block level advancement. Use apply_shape_command only in response to a new human utterance, one command per utterance. Never apply shape commands on startup, timers, stage changes or movement completion. Commands affect only the active shape. One gameplay world unit is one second of travel at the starting player speed; its scene-coordinate size stays fixed for the whole run. next_level_threshold uses these units; camera coordinates and route distances remain in scene coordinates. Flying beyond the active shape's next_level_threshold from the run origin (spawn) advances automatically, regardless of commands. Advancing returns the player to origin under a screen fade before revealing the next shape. Inversion is a delta to the existing inversion radius. Other commands set a numeric attribute."}


func apply_request(args: Dictionary) -> Dictionary:
	if not args.get("command") is String or not args.get("run_id") is String \
			or not (args.get("shape_index") is int or args.get("shape_index") is float):
		return {"ok": false, "message": "Supply command, run_id and integer shape_index from fresh status."}
	if not is_finite(float(args.shape_index)) or float(args.shape_index) != floor(float(args.shape_index)):
		return {"ok": false, "message": "shape_index must be an integer."}
	for field in ["command_index", "human_turn"]:
		var value: Variant = args.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)):
			return {"ok": false, "message": "Read command_index and human_turn from fresh status."}
	return apply_command(args.command, args.run_id, int(args.shape_index), int(args.command_index), int(args.human_turn))
