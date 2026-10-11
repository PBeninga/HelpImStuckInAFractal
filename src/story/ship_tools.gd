class_name ShipTools
extends RefCounted
## The ship's controls as MCP tools: definitions() is the `tools/list` result
## and call_tool() runs one `tools/call`. Every result is a Dictionary with
## `ok` and a short `message` the support agent can paraphrase, plus data.
## Distances are metres (Route.METERS_PER_UNIT), angles degrees; bearings are
## positive to the pilot's right, elevations positive upward.

const HUD_ELEMENTS := ["diagnostics_log", "ship_status", "call_panel", "exit_marker", "reticle"]
## Features further than this are not reported by a scan (1.6 km).
const SCAN_RANGE := 1.6

var ship: ShipController
var mission: Mission
var issue_log: IssueLog
var params: FractalParams
var camera: CameraState
## May be null (tests): highlight_feature(id, label, seconds), flash(element),
## scan_pulse(ids), clear_highlights().
var hud: Object
## () -> bool: whether the game is paused.
var is_paused: Callable = func() -> bool: return false
## (id: int) -> void: set the colour mode through the shape table.
var set_color_mode: Callable = func(_id: int) -> void: pass


func setup(p_ship: ShipController, p_mission: Mission, p_log: IssueLog,
		p_params: FractalParams, p_camera: CameraState) -> void:
	ship = p_ship
	mission = p_mission
	issue_log = p_log
	params = p_params
	camera = p_camera


static func definitions() -> Array:
	var feature_id := {"type": "string", "description": "A Mandelbrought characteristic id such as \"#2312\" (from scan_surroundings or get_ship_status)."}
	return [
		{"name": "get_ship_status",
			"description": "Read the ship's telemetry: mission stage, clearance to the fractal, heading, autopilot state, the next waypoint on the way out and the exit rift (range, bearing, whether a straight flight is clear), open diagnostics issues that need the pilot, and the fractal parameters (useful for technical explanations). Call this first and whenever you are unsure where the ship is.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "scan_surroundings",
			"description": "Sweep the ship's sensors for nearby Mandelbrought characteristics (named landmarks, waypoints and the exit rift). Returns each one's id, name, a one-line description, range, bearing, elevation, a plain-words direction, whether it is on the pilot's screen and whether a straight flight to it is clear. Briefly highlights them all on the pilot's HUD.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "highlight",
			"description": "Draw the pilot's attention to something: a characteristic in the view (pass its id, e.g. \"#2312\") gets brackets and a label; a HUD panel (diagnostics_log, ship_status, call_panel, exit_marker, reticle) flashes. Use it whenever you mention something the pilot should look at.",
			"inputSchema": {"type": "object", "properties": {
				"target": {"type": "string", "description": "A characteristic id like \"#2312\", or a HUD element: diagnostics_log, ship_status, call_panel, exit_marker, reticle."},
				"label": {"type": "string", "description": "Optional short caption to show next to it."}},
				"required": ["target"], "additionalProperties": false}},
		{"name": "clear_highlights",
			"description": "Remove every highlight from the pilot's view.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "turn_ship",
			"description": "Rotate the ship in place. Positive yaw turns right, negative left; positive pitch tilts up, negative down. Takes about a second.",
			"inputSchema": {"type": "object", "properties": {
				"yaw_degrees": {"type": "number", "description": "Degrees to turn: positive right, negative left (-180..180)."},
				"pitch_degrees": {"type": "number", "description": "Degrees to tilt: positive up, negative down (-85..85). Default 0."}},
				"required": ["yaw_degrees"], "additionalProperties": false}},
		{"name": "face_feature",
			"description": "Turn the ship to look straight at a characteristic.",
			"inputSchema": {"type": "object", "properties": {"feature_id": feature_id},
				"required": ["feature_id"], "additionalProperties": false}},
		{"name": "thrust",
			"description": "Move the ship a set distance relative to where it faces. Stops automatically about 5 m short of the fractal and reports if it was obstructed. Good for small manual adjustments the pilot asks for.",
			"inputSchema": {"type": "object", "properties": {
				"direction": {"type": "string", "enum": ShipController.DIRECTIONS},
				"meters": {"type": "number", "description": "How far to move, in metres (1..2000). Tunnels here are 20-80 m wide."}},
				"required": ["direction", "meters"], "additionalProperties": false}},
		{"name": "fly_to_feature",
			"description": "Engage the autopilot: turn toward a characteristic and fly to it in a straight line (a few seconds). Refuses if fractal geometry blocks the straight path; then route via the next waypoint instead. Flying to the exit rift (#9001) completes the escape once the egress waiver is signed. You will be told when the ship arrives.",
			"inputSchema": {"type": "object", "properties": {"feature_id": feature_id},
				"required": ["feature_id"], "additionalProperties": false}},
		{"name": "full_stop",
			"description": "Cancel the autopilot or any manoeuvre in progress and hold position.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "resolve_issue",
			"description": "Answer a diagnostics issue that requires pilot input, using the pilot's own answer (ask them first; never invent it). The issue id looks like \"#48213\".",
			"inputSchema": {"type": "object", "properties": {
				"issue_id": {"type": "string"},
				"answer": {"type": "string", "description": "The pilot's answer, in their words."}},
				"required": ["issue_id", "answer"], "additionalProperties": false}},
		{"name": "post_to_log",
			"description": "Write a line into the ship's diagnostics log as the support agent, e.g. \"Identified Mandelbrought characteristic #2312, drawing attention and configuring flight path.\" Keep it short and in the log's terse technical voice.",
			"inputSchema": {"type": "object", "properties": {"message": {"type": "string"}},
				"required": ["message"], "additionalProperties": false}},
		{"name": "set_visual_filter",
			"description": "Recalibrate the ship's optical sensors to a different colour palette (purely cosmetic).",
			"inputSchema": {"type": "object", "properties": {
				"palette": {"type": "string", "enum": FractalParams.COLOR_MODE_NAMES}},
				"required": ["palette"], "additionalProperties": false}},
	]


## Run one tool. Unknown tools and bad arguments come back as ok = false.
func call_tool(tool_name: String, args: Variant) -> Dictionary:
	var a: Dictionary = args if args is Dictionary else {}
	match tool_name:
		"get_ship_status": return status()
		"scan_surroundings": return scan()
		"highlight": return _highlight(a)
		"clear_highlights": return _clear_highlights()
		"turn_ship": return _turn(a)
		"face_feature": return _face(a)
		"thrust": return _thrust(a)
		"fly_to_feature": return _fly_to(a)
		"full_stop": return _full_stop()
		"resolve_issue": return _resolve(a)
		"post_to_log": return _post(a)
		"set_visual_filter": return _filter(a)
	return {"ok": false, "message": "Unknown tool '%s'." % tool_name}


# ------------------------------------------------------------- read

func status() -> Dictionary:
	var fwd := camera.forward()
	var heading := fposmod(rad_to_deg(atan2(fwd.y, fwd.x)), 360.0)
	var out := {
		"ok": true,
		"stage": mission.stage_name(),
		"paused": is_paused.call(),
		"clearance_m": Route.meters(DistanceEstimator.estimate(camera.eye(), params)),
		"heading_deg": int(round(heading)),
		"pitch_deg": int(round(rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0))))),
		"autopilot": ship.state(),
		"waypoints_passed": mission.visited.keys(),
		"waypoints_total": Route.waypoints().size() - 1,
		"open_issues": issue_log.pending(),
		"exit": _exit_info(),
		"fractal": {
			"type": "Mandelbox",
			"scale": params.box_scale, "fold_limit": params.fold_limit,
			"min_radius": params.min_radius, "fixed_radius": params.fixed_radius,
			"iterations": DistanceEstimator.ITERATIONS,
			"surface_hausdorff_dimension_estimate": 2.8,
		},
	}
	var nxt := mission.next_waypoint()
	if not nxt.is_empty():
		out["next_waypoint"] = _feature_report(nxt)
	out["message"] = _status_line(out)
	return out


func scan() -> Dictionary:
	var found: Array = []
	for f in Route.FEATURES:
		if camera.eye().distance_to(f["pos"]) <= SCAN_RANGE:
			found.append(_feature_report(f))
	found.sort_custom(func(x, y): return x["range_m"] < y["range_m"])
	var ids: Array = []
	for f in found:
		ids.append(f["feature_id"])
	if hud != null:
		hud.scan_pulse(ids)
	issue_log.add("Sensor sweep: %d Mandelbrought characteristics in range" % found.size(), "info")
	var nxt := mission.next_waypoint()
	return {"ok": true, "features": found,
		"route_hint": "" if nxt.is_empty() else "The way out continues at #%s (%s)." % [nxt["id"], nxt["name"]],
		"message": "%d characteristics in range." % found.size()}


func _feature_report(f: Dictionary) -> Dictionary:
	var rel := ShipController.relative(camera, f["pos"])
	var target: Vector3 = f["pos"]
	if f["kind"] == "landmark":
		target = _standoff_point(f)
	var report := {
		"feature_id": "#" + f["id"], "name": f["name"], "kind": f["kind"],
		"description": f["blurb"], "visited": mission.visited.has(f["id"]),
		"on_screen": _on_screen(f["pos"]),
		"path_clear": Route.path_clear(camera.eye(), target, params),
	}
	report.merge(rel)
	return report


func _exit_info() -> Dictionary:
	var f := Route.feature(Route.EXIT_ID)
	var info := _feature_report(f)
	info["waiver_signed"] = mission.waiver_signed
	info["waiver_issue_id"] = mission.waiver_issue_id
	return info


func _status_line(s: Dictionary) -> String:
	var line := "Stage %s, clearance %d m." % [s["stage"], s["clearance_m"]]
	if s.has("next_waypoint"):
		var n: Dictionary = s["next_waypoint"]
		line += " Next waypoint %s %s, %d m %s." % [n["feature_id"], n["name"], n["range_m"], n["direction"]]
	if s["paused"]:
		line += " The game is paused: ask the pilot to press Escape to resume."
	return line


# ------------------------------------------------------------- act

func _highlight(a: Dictionary) -> Dictionary:
	var target := str(a.get("target", "")).strip_edges()
	var label := str(a.get("label", ""))
	if HUD_ELEMENTS.has(target):
		if hud != null:
			hud.flash(target, label)
		return {"ok": true, "message": "Flashing the %s on the pilot's HUD." % target.replace("_", " ")}
	var f := Route.feature(target)
	if f.is_empty():
		return {"ok": false, "message": "No characteristic or HUD element called '%s'." % target}
	if hud != null:
		hud.highlight_feature(f["id"], label, 20.0)
	var rel := ShipController.relative(camera, f["pos"])
	return {"ok": true, "message": "Highlighted #%s %s; it is %s, %d m away%s." % [
		f["id"], f["name"], rel["direction"], rel["range_m"],
		"" if _on_screen(f["pos"]) else " (off screen: an arrow points to it)"]}


func _clear_highlights() -> Dictionary:
	if hud != null:
		hud.clear_highlights()
	return {"ok": true, "message": "Highlights cleared."}


func _turn(a: Dictionary) -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	var r := ship.turn_by(float(a.get("yaw_degrees", 0.0)), float(a.get("pitch_degrees", 0.0)))
	r["message"] = "Turning %d degrees." % r.get("turning_deg", 0)
	return _with_pause_note(r)


func _face(a: Dictionary) -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	var f := Route.feature(a.get("feature_id", ""))
	if f.is_empty():
		return {"ok": false, "message": "No characteristic '%s'." % a.get("feature_id", "")}
	var r := ship.face(f["pos"], {"target_id": f["id"]})
	if hud != null:
		hud.highlight_feature(f["id"], "", 12.0)
	r["message"] = "Turning to face #%s %s." % [f["id"], f["name"]]
	return _with_pause_note(r)


func _thrust(a: Dictionary) -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	var dir := str(a.get("direction", ""))
	var r := ship.thrust(dir, float(a.get("meters", 0.0)))
	if not r["ok"]:
		r["message"] = "Cannot move %s: %s (clearance %s m)." % [dir, r.get("reason", "?"), r.get("clearance_m", "?")]
	elif r["obstructed"]:
		r["message"] = "Moving %s %d m; the fractal stops us short of the %d m asked." % [dir, r["moving_m"], r["requested_m"]]
	else:
		r["message"] = "Moving %s %d m." % [dir, r["moving_m"]]
	return _with_pause_note(r)


func _fly_to(a: Dictionary) -> Dictionary:
	var gate := _gate()
	if not gate.is_empty():
		return gate
	var f := Route.feature(a.get("feature_id", ""))
	if f.is_empty():
		return {"ok": false, "message": "No characteristic '%s'." % a.get("feature_id", "")}
	var standoff := 0.0
	var note := ""
	if f["kind"] == "landmark":
		standoff = 0.03
	elif f["kind"] == "exit" and not mission.waiver_signed:
		standoff = Route.RIFT_HOLD
		note = " The rift will not open until the egress waiver is signed; holding just outside it."
	var r := ship.fly_to(f["pos"], standoff, {"target_id": f["id"]})
	if r.get("already_there", false):
		r["message"] = "Already at #%s %s.%s" % [f["id"], f["name"], note]
		return r
	if not r["ok"]:
		var nxt := mission.next_waypoint()
		r["message"] = "Autopilot refused: fractal geometry blocks a straight flight to #%s (%d m away)." % [f["id"], r["distance_m"]]
		if not nxt.is_empty() and nxt["id"] != f["id"]:
			r["message"] += " Try routing via #%s %s first." % [nxt["id"], nxt["name"]]
		r["suggested_waypoint"] = "" if nxt.is_empty() else "#" + nxt["id"]
		issue_log.add("Autopilot: no clear path to #%s" % f["id"], "fail")
		return r
	if hud != null:
		hud.highlight_feature(f["id"], "COURSE LAID IN", r["seconds"] + 3.0)
	issue_log.add("Autopilot engaged: course laid in for #%s %s (%d m)" % [f["id"], f["name"], r["distance_m"]], "info")
	r["message"] = "Autopilot engaged to #%s %s: %d m, about %d seconds.%s" % [
		f["id"], f["name"], r["distance_m"], int(ceil(r["seconds"])), note]
	return _with_pause_note(r)


func _full_stop() -> Dictionary:
	var was := ship.stop("full stop")
	return {"ok": true, "message": "All stop. Holding position." if was else "Already holding position."}


func _resolve(a: Dictionary) -> Dictionary:
	var id := str(a.get("issue_id", ""))
	var answer := str(a.get("answer", ""))
	var outcome := issue_log.resolve(id, answer, "pilot")
	if outcome == "":
		var open: Array = []
		for p in issue_log.pending():
			open.append(p["issue_id"])
		return {"ok": false, "open_issues": open,
			"message": "No open issue %s. Open issues: %s." % [id, ", ".join(open) if not open.is_empty() else "none"]}
	return {"ok": true, "message": outcome}


func _post(a: Dictionary) -> Dictionary:
	var msg := str(a.get("message", "")).strip_edges()
	if msg.is_empty():
		return {"ok": false, "message": "Nothing to post."}
	issue_log.add(msg.left(160), "agent")
	return {"ok": true, "message": "Posted to the diagnostics log."}


func _filter(a: Dictionary) -> Dictionary:
	var name := str(a.get("palette", ""))
	var i := FractalParams.COLOR_MODE_NAMES.find(name)
	if i < 0:
		return {"ok": false, "message": "Unknown palette '%s'." % name}
	set_color_mode.call(FractalParams.COLOR_MODE_IDS[i])
	issue_log.add("Optical sensors recalibrated: %s" % name, "info")
	return {"ok": true, "message": "Optical sensors now on %s." % name}


# ------------------------------------------------------------- helpers

## A reason the ship cannot be flown right now, as a result; {} when it can.
func _gate() -> Dictionary:
	match mission.stage:
		Mission.Stage.INTRO:
			return {"ok": false, "message": "The ship is still materialising from the failed jump; give it a few seconds."}
		Mission.Stage.EGRESS, Mission.Stage.ESCAPED:
			return {"ok": false, "message": "The ship has already left fractal space."}
	return {}


func _with_pause_note(r: Dictionary) -> Dictionary:
	if is_paused.call():
		r["message"] = str(r.get("message", "")) + " (The game is paused, so nothing will move until the pilot presses Escape to resume.)"
	return r


func _standoff_point(f: Dictionary) -> Vector3:
	var rel: Vector3 = f["pos"] - camera.eye()
	if rel.length() <= 0.03:
		return camera.eye()
	return f["pos"] - rel.normalized() * 0.03


func _on_screen(p: Vector3) -> bool:
	var rel := ShipController.relative(camera, p)
	return absf(rel["bearing_deg"]) < 30.0 and absf(rel["elevation_deg"]) < 19.0
