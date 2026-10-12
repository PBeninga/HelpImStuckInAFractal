extends RefCounted
## Agent navigation uses measured geometry and world coordinates. Large sensor
## payloads are opt-in tool results, never attached to status or events.
const HUD_ELEMENTS := ["diagnostics_log", "ship_status", "call_panel", "reticle"]
const DIRECTIONS := ["forward", "back", "left", "right", "up", "down"]
var cc: Node
var _planning := false
var _plan_generation := 0

func _init(p_cc: Node = null) -> void:
	cc = p_cc
	if cc != null:
		cc.game_detached.connect(_reset_planning)

func definitions() -> Array:
	var point := {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3,
		"description": "World coordinates [x,y,z], in world units (1000 metres per world unit)."}
	var out := [
		_tool("get_ship_status", "Compact telemetry: position, player facing, Gameplay speed, autopilot and real exit-sphere boundary. No depth grid or scripted landmarks."),
		_tool("scan_surroundings", "Request a low-fidelity multidirectional raycast around the player. Fidelity is tunable in Gameplay. Includes world directions and measured distances; misses are unknown, not proof of open space."),
		_tool("get_depth_scan", "Read the latest locally cached screen depth scan. Returns a small summary and broad far-distance patches by default. Set include_grid=true only when the 2D array is needed. Refreshes locally every few frames; nothing is pushed to you. Requests are throttled for two seconds. Use after_frame to suppress duplicates. Censored range/step limits are NOT open space; inspect the captured pose and age.", {
			"include_grid": {"type": "boolean", "default": false},
			"after_frame": {"type": "integer", "minimum": 0},
			"max_columns": {"type": "integer", "minimum": 8, "maximum": 64, "default": 32}}),
		_tool("plan_escape", "Estimate the fastest sampled path outside the actual exit sphere, integrating player Gameplay speed and turn time. Uses nearby geometry and locally cached far-depth patches without returning the grid. Returns points in world units; execute one leg, wait for completion, then replan. Approximate, not a global shortest-time guarantee."),
		_tool("face_point", "Turn to face world coordinates. Wait for instruction_completed or instruction_cancelled.", {"point": point}, ["point"]),
		_tool("fly_to_point", "Turn and fly directly to world coordinates at the SAME speed as player Gameplay movement, including distance slowdown, wheel and current Shift state. Ignores collision and movement bounds. Speed varies along the path; wait for instruction_completed or instruction_cancelled.", {"point": point}, ["point"]),
		_tool("turn_ship", "Turn in place. Positive yaw is right, positive pitch is up. Completion is reported with the resulting facing direction.", {
			"yaw_degrees": {"type": "number", "minimum": -180, "maximum": 180},
			"pitch_degrees": {"type": "number", "minimum": -85, "maximum": 85}}, ["yaw_degrees"]),
		_tool("thrust", "Move relative to the player's facing at Gameplay speed, ignoring collision and movement bounds. Completion/cancellation is reported.", {
			"direction": {"type": "string", "enum": DIRECTIONS},
			"meters": {"type": "number", "exclusiveMinimum": 0, "maximum": 2000}}, ["direction", "meters"]),
		_tool("full_stop", "Cancel the active instruction and hold position. Cancellation is reported."),
		_tool("point_direction", "Show a turning arrow toward a world point for the pilot. Does not move the ship.", {
			"point": point, "label": {"type": "string"}, "seconds": {"type": "number", "minimum": 1, "maximum": 300}}, ["point"]),
		_tool("clear_direction", "Clear the turning arrow."),
		_tool("highlight", "Flash a HUD panel.", {"target": {"type": "string", "enum": HUD_ELEMENTS}, "label": {"type": "string"}}, ["target"]),
		_tool("clear_highlights", "Clear HUD highlights."),
		_tool("resolve_issue", "Resolve a diagnostics issue using the pilot's answer; never invent an answer.", {"issue_id": {"type": "string"}, "answer": {"type": "string"}}, ["issue_id", "answer"]),
		_tool("post_to_log", "Post a short navigation status line to the diagnostics log.", {"message": {"type": "string"}}, ["message"]),
	]
	var adapter: Node = cc.adapter if cc != null else null
	var palettes: Array = adapter.palettes() if adapter != null else []
	if not palettes.is_empty():
		out.append(_tool("set_visual_filter", "Set the cosmetic colour palette.", {"palette": {"type": "string", "enum": palettes}}, ["palette"]))
	if cc != null:
		for tool_name in cc.custom_tools:
			out.append(cc.custom_tools[tool_name]["definition"])
	return out

static func _tool(tool_name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary:
	return {"name": tool_name, "description": description,
		"inputSchema": {"type": "object", "properties": properties, "required": required, "additionalProperties": false}}

func has_tool(tool_name: String) -> bool:
	return definitions().any(func(d): return d.name == tool_name)

func call_tool(tool_name: String, args: Variant) -> Dictionary:
	var a: Dictionary = args if args is Dictionary else {}
	match tool_name:
		"get_ship_status": return status()
		"scan_surroundings": return scan()
		"get_depth_scan": return cc.adapter.depth_scan(a) if cc.adapter != null else _no_flight()
		"plan_escape":
			if cc.adapter == null:
				return _no_flight()
			if _planning:
				return {"ok": false, "message": "A route estimate is already in progress."}
			_planning = true
			var generation := _plan_generation
			var result: Dictionary = await cc.adapter.plan_escape()
			if generation != _plan_generation:
				return _no_flight()
			_planning = false
			return result
		"face_point", "fly_to_point": return _navigate(tool_name, a)
		"turn_ship":
			if cc.adapter == null:
				return _no_flight()
			if not _number(a.get("yaw_degrees")) or not _number(a.get("pitch_degrees", 0)):
				return {"ok": false, "message": "Angles must be finite numbers."}
			return _with_pause_note(cc.adapter.turn(clampf(a.yaw_degrees, -180, 180), clampf(a.get("pitch_degrees", 0), -85, 85)))
		"thrust":
			if cc.adapter == null:
				return _no_flight()
			if not _number(a.get("meters")) or float(a.meters) <= 0 or float(a.meters) > 2000:
				return {"ok": false, "message": "meters must be positive and at most 2000."}
			return _with_pause_note(cc.adapter.thrust(str(a.get("direction", "")), float(a.meters)))
		"full_stop":
			if cc.adapter == null:
				return _no_flight()
			var was: bool = cc.adapter.stop("full stop")
			return {"ok": true, "message": "Instruction cancelled; holding position." if was else "Already holding position."}
		"point_direction": return _point_direction(a)
		"clear_direction":
			if cc.hud != null:
				cc.hud.overlay.clear_direction()
			return {"ok": true}
		"highlight":
			if not HUD_ELEMENTS.has(a.get("target", "")):
				return {"ok": false, "message": "Unknown HUD element."}
			if cc.hud != null:
				cc.hud.flash(a.target, str(a.get("label", "")))
			return {"ok": true}
		"clear_highlights":
			if cc.hud != null:
				cc.hud.clear_highlights()
			return {"ok": true}
		"resolve_issue": return _resolve(a)
		"post_to_log": return _post(a)
		"set_visual_filter": return _filter(a)
	if cc != null and cc.custom_tools.has(tool_name):
		var r: Variant = await cc.custom_tools[tool_name]["handler"].call(a)
		if r is Dictionary:
			if not r.has("ok"):
				r["ok"] = true
			return r
		return {"ok": true, "message": str(r)}
	return {"ok": false, "message": "Unknown tool '%s'." % tool_name}

func status() -> Dictionary:
	var adapter: Node = cc.adapter
	var out := {"ok": true, "in_flight": adapter != null, "open_issues": cc.issues.pending()}
	if adapter == null:
		out["message"] = "No flight in progress."
		return out
	out.merge(adapter.navigation_pose())
	out.merge({"paused": adapter.is_paused(), "autopilot": adapter.autopilot_state(),
		"speed_world_per_second": adapter.travel_speed(), "escape": adapter.escape_state(),
		"world": adapter.world_info(), "message": "Use plan_escape for estimated travel times; request scans only when needed."})
	return out

func scan() -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var out: Dictionary = cc.adapter.navigation_pose()
	out.merge({"ok": true, "surrounding_geometry": cc.adapter.surrounding_geometry() if cc.adapter.has_method("surrounding_geometry") else {"rays": []}})
	if cc.hud != null:
		cc.hud.scan_pulse([])
	return out

func _navigate(tool_name: String, a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	if not _point(a.get("point")):
		return {"ok": false, "message": "point must contain three finite world coordinates."}
	var result: Dictionary
	if tool_name == "face_point":
		result = cc.adapter.face_point(a.point)
	else:
		result = cc.adapter.fly_to_point(a.point)
	return _with_pause_note(result)

func _point_direction(a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	if not _point(a.get("point")) or not _number(a.get("seconds", 30)):
		return {"ok": false, "message": "Supply a finite world point and duration."}
	if cc.hud == null:
		return {"ok": false, "message": "The HUD is not available."}
	var p: Array = a.point
	cc.hud.overlay.point_direction(Vector3(p[0], p[1], p[2]), str(a.get("label", "Agent target")), clampf(a.get("seconds", 30), 1, 300))
	return {"ok": true, "target": p, "message": "Direction arrow set."}

static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _point(v: Variant) -> bool:
	return v is Array and v.size() == 3 and v.all(_number)

func _no_flight() -> Dictionary:
	return {"ok": false, "message": "No flight in progress."}

func _with_pause_note(result: Dictionary) -> Dictionary:
	if cc.adapter != null and cc.adapter.is_paused():
		result["paused"] = true
		result["message"] = str(result.get("message", "")) + " The game is paused; resume to execute the instruction."
	return result

func _resolve(a: Dictionary) -> Dictionary:
	var id := str(a.get("issue_id", ""))
	var outcome: String = cc.issues.resolve(id, str(a.get("answer", "")), "pilot")
	if outcome == "":
		var open: Array = cc.issues.pending().map(func(p): return p["issue_id"])
		return {"ok": false, "open_issues": open,
			"message": "No open issue %s. Open issues: %s." % [id, ", ".join(open) if not open.is_empty() else "none"]}
	return {"ok": true, "message": outcome}


func _post(a: Dictionary) -> Dictionary:
	var msg := str(a.get("message", "")).strip_edges()
	if msg.is_empty():
		return {"ok": false, "message": "Nothing to post."}
	cc.issues.add(msg.left(160), "agent")
	return {"ok": true, "message": "Posted to the diagnostics log."}


func _filter(a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var name := str(a.get("palette", ""))
	var r: Dictionary = cc.adapter.set_palette(name)
	if r.get("ok", false):
		cc.issues.add("Optical sensors recalibrated: %s" % name, "info")
		r["message"] = "Optical sensors now on %s." % name
	return r


func _reset_planning() -> void:
	_plan_generation += 1
	_planning = false
