extends RefCounted
## The ship's controls as MCP tools: definitions() is the `tools/list` result
## and call_tool() runs one `tools/call`. Built-in tools work through the ship
## adapter, the feature registry and the diagnostics log; the game can add its
## own with CallCenter.register_tool(). Every result is a Dictionary with `ok`
## and a short `message` the support agent can paraphrase, plus data.
## Distances are metres, angles degrees; bearings positive to the pilot's
## right, elevations positive up.

const Features := preload("res://call_center/features.gd")

const HUD_ELEMENTS := ["diagnostics_log", "ship_status", "call_panel", "exit_marker", "reticle"]
const DIRECTIONS := ["forward", "back", "left", "right", "up", "down"]
## Features further than this are not reported by a scan (metres).
const SCAN_RANGE_M := 1600.0
## A landmark on a surface is approached to this distance (metres).
const LANDMARK_STANDOFF_M := 30.0
## Held this far short of a locked exit (metres).
const EXIT_HOLD_M := 140.0

## The CallCenter (call_center.gd): adapter, features, issues, hud,
## exit_lock_reason, custom_tools.
var cc: Node


func _init(p_cc: Node = null) -> void:
	cc = p_cc


func definitions() -> Array:
	var feature_id := {"type": "string", "description": "A Mandelbrought characteristic id such as \"#2312\" (from scan_surroundings or get_ship_status)."}
	var out := [
		{"name": "get_ship_status",
			"description": "Read the ship's telemetry: whether a flight is in progress, clearance to the nearest surface, heading, autopilot state, the next waypoint on the way out and the exit (range, bearing, whether a straight flight is clear, whether it is locked), open diagnostics issues that need the pilot, and facts about the world (useful for technical explanations). Call this first and whenever you are unsure where the ship is.",
			"inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}},
		{"name": "scan_surroundings",
			"description": "Sweep the ship's sensors for nearby Mandelbrought characteristics (named landmarks, waypoints and the exit). Returns each one's id, name, a one-line description, range, bearing, elevation, a plain-words direction, whether it is on the pilot's screen and whether a straight flight to it is clear. Briefly highlights them all on the pilot's HUD.",
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
			"description": "Move the ship a set distance relative to where it faces. Stops automatically short of obstacles and reports if it was obstructed. Good for small manual adjustments the pilot asks for.",
			"inputSchema": {"type": "object", "properties": {
				"direction": {"type": "string", "enum": DIRECTIONS},
				"meters": {"type": "number", "description": "How far to move, in metres (1..2000)."}},
				"required": ["direction", "meters"], "additionalProperties": false}},
		{"name": "fly_to_feature",
			"description": "Engage the autopilot: turn toward a characteristic and fly to it in a straight line (a few seconds). Refuses if something blocks the straight path; then route via the next waypoint instead. You will be told when the ship arrives.",
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
	]
	var adapter: Node = cc.adapter if cc != null else null
	var palettes: Array = adapter.palettes() if adapter != null else []
	if not palettes.is_empty():
		out.append({"name": "set_visual_filter",
			"description": "Recalibrate the ship's optical sensors to a different colour palette (purely cosmetic).",
			"inputSchema": {"type": "object", "properties": {"palette": {"type": "string", "enum": palettes}},
				"required": ["palette"], "additionalProperties": false}})
	if cc != null:
		for name in cc.custom_tools:
			out.append(cc.custom_tools[name]["definition"])
	return out


func has_tool(tool_name: String) -> bool:
	for d in definitions():
		if d["name"] == tool_name:
			return true
	return false


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
	if cc != null and cc.custom_tools.has(tool_name):
		var r: Variant = cc.custom_tools[tool_name]["handler"].call(a)
		if r is Dictionary:
			if not r.has("ok"):
				r["ok"] = true
			return r
		return {"ok": true, "message": str(r)}
	return {"ok": false, "message": "Unknown tool '%s'." % tool_name}


# ------------------------------------------------------------- read

func status() -> Dictionary:
	var adapter: Node = cc.adapter
	var out := {"ok": true, "in_flight": adapter != null, "open_issues": cc.issues.pending()}
	if adapter == null:
		out["message"] = "No flight in progress: the game is not in the cockpit (title menu or loading)."
		return out
	var pose: Dictionary = adapter.pose()
	var fwd: Vector3 = pose["forward"]
	var c: float = adapter.clearance()
	out["paused"] = adapter.is_paused()
	out["clearance_m"] = -1 if is_inf(c) else adapter.meters(c)
	out["heading_deg"] = int(round(fposmod(rad_to_deg(atan2(fwd.y, fwd.x)), 360.0)))
	out["pitch_deg"] = int(round(rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0)))))
	out["autopilot"] = adapter.autopilot_state()
	out["waypoints_passed"] = cc.features.visited.keys().filter(func(k): return cc.features.route.has(k))
	out["waypoints_total"] = cc.features.route.size()
	out["world"] = adapter.world_info()
	var ex: Dictionary = cc.features.exit()
	if not ex.is_empty():
		out["exit"] = _feature_report(ex)
		out["exit"]["locked"] = cc.exit_lock_reason != ""
		if cc.exit_lock_reason != "":
			out["exit"]["lock_reason"] = cc.exit_lock_reason
	var nxt: Dictionary = cc.features.next_waypoint()
	if not nxt.is_empty():
		out["next_waypoint"] = _feature_report(nxt)
	var line := "Clearance %s." % ("unknown" if out["clearance_m"] < 0 else "%d m" % out["clearance_m"])
	if out.has("next_waypoint"):
		var n: Dictionary = out["next_waypoint"]
		line += " Next waypoint %s %s, %d m %s." % [n["feature_id"], n["name"], n["range_m"], n["direction"]]
	if out["paused"]:
		line += " The game is paused: ask the pilot to press Escape to resume."
	out["message"] = line
	return out


func scan() -> Dictionary:
	var adapter: Node = cc.adapter
	if adapter == null:
		return _no_flight()
	var found: Array = []
	var here: Vector3 = adapter.pose()["position"]
	for f in cc.features.all():
		if here.distance_to(f["pos"]) * adapter.meters_per_unit() <= SCAN_RANGE_M:
			found.append(_feature_report(f))
	found.sort_custom(func(x, y): return x["range_m"] < y["range_m"])
	var ids: Array = found.map(func(f): return f["feature_id"])
	if cc.hud != null:
		cc.hud.scan_pulse(ids)
	cc.issues.add("Sensor sweep: %d Mandelbrought characteristics in range" % found.size(), "info")
	var nxt: Dictionary = cc.features.next_waypoint()
	return {"ok": true, "features": found,
		"route_hint": "" if nxt.is_empty() else "The way out continues at #%s (%s)." % [nxt["id"], nxt["name"]],
		"message": "%d characteristics in range." % found.size()}


func _feature_report(f: Dictionary) -> Dictionary:
	var adapter: Node = cc.adapter
	var pose: Dictionary = adapter.pose()
	var report := {
		"feature_id": "#" + f["id"], "name": f["name"], "kind": f["kind"],
		"description": f["blurb"], "visited": cc.features.visited.has(f["id"]),
		"on_screen": _on_screen(f["pos"]),
		"path_clear": adapter.path_clear(pose["position"], _approach_point(f)),
	}
	report.merge(Features.relative(pose, f["pos"], adapter.meters_per_unit()))
	return report


# ------------------------------------------------------------- act

func _highlight(a: Dictionary) -> Dictionary:
	var target := str(a.get("target", "")).strip_edges()
	var label := str(a.get("label", ""))
	if HUD_ELEMENTS.has(target):
		if cc.hud != null:
			cc.hud.flash(target, label)
		return {"ok": true, "message": "Flashing the %s on the pilot's HUD." % target.replace("_", " ")}
	var f: Dictionary = cc.features.find(target)
	if f.is_empty():
		return {"ok": false, "message": "No characteristic or HUD element called '%s'." % target}
	if cc.hud != null:
		cc.hud.highlight_feature(f["id"], label, 20.0)
	if cc.adapter == null:
		return {"ok": true, "message": "Highlighted #%s %s." % [f["id"], f["name"]]}
	var rel := Features.relative(cc.adapter.pose(), f["pos"], cc.adapter.meters_per_unit())
	return {"ok": true, "message": "Highlighted #%s %s; it is %s, %d m away%s." % [
		f["id"], f["name"], rel["direction"], rel["range_m"],
		"" if _on_screen(f["pos"]) else " (off screen: an arrow points to it)"]}


func _clear_highlights() -> Dictionary:
	if cc.hud != null:
		cc.hud.clear_highlights()
	return {"ok": true, "message": "Highlights cleared."}


func _turn(a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var r: Dictionary = cc.adapter.turn(float(a.get("yaw_degrees", 0.0)), float(a.get("pitch_degrees", 0.0)))
	if r.get("ok", false):
		r["message"] = "Turning %d degrees." % r.get("turning_deg", 0)
	return _with_pause_note(r)


func _face(a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var f: Dictionary = cc.features.find(a.get("feature_id", ""))
	if f.is_empty():
		return {"ok": false, "message": "No characteristic '%s'." % a.get("feature_id", "")}
	var r: Dictionary = cc.adapter.face(f["pos"], {"target_id": f["id"]})
	if cc.hud != null:
		cc.hud.highlight_feature(f["id"], "", 12.0)
	if r.get("ok", false):
		r["message"] = "Turning to face #%s %s." % [f["id"], f["name"]]
	return _with_pause_note(r)


func _thrust(a: Dictionary) -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var dir := str(a.get("direction", ""))
	var r: Dictionary = cc.adapter.thrust(dir, float(a.get("meters", 0.0)))
	if not r.get("ok", false):
		if not r.has("message"):
			r["message"] = "Cannot move %s: %s." % [dir, r.get("reason", "blocked")]
	elif r.get("obstructed", false):
		r["message"] = "Moving %s %d m; an obstacle stops us short of the %d m asked." % [dir, r["moving_m"], r["requested_m"]]
	else:
		r["message"] = "Moving %s %d m." % [dir, r.get("moving_m", 0)]
	return _with_pause_note(r)


func _fly_to(a: Dictionary) -> Dictionary:
	var adapter: Node = cc.adapter
	if adapter == null:
		return _no_flight()
	var f: Dictionary = cc.features.find(a.get("feature_id", ""))
	if f.is_empty():
		return {"ok": false, "message": "No characteristic '%s'." % a.get("feature_id", "")}
	var standoff := 0.0
	var note := ""
	if f["kind"] == "landmark":
		standoff = LANDMARK_STANDOFF_M / adapter.meters_per_unit()
	elif f["kind"] == "exit" and cc.exit_lock_reason != "":
		standoff = EXIT_HOLD_M / adapter.meters_per_unit()
		note = " The exit is locked (%s); holding just outside it." % cc.exit_lock_reason
	var r: Dictionary = adapter.fly_to(f["pos"], standoff, {"target_id": f["id"]})
	if r.get("already_there", false):
		r["message"] = "Already at #%s %s.%s" % [f["id"], f["name"], note]
		return r
	if not r.get("ok", false):
		if r.get("reason", "") != "obstructed":
			return r
		var nxt: Dictionary = cc.features.next_waypoint()
		r["message"] = "Autopilot refused: something blocks a straight flight to #%s (%d m away)." % [f["id"], r.get("distance_m", 0)]
		if not nxt.is_empty() and nxt["id"] != f["id"]:
			r["message"] += " Try routing via #%s %s first." % [nxt["id"], nxt["name"]]
		r["suggested_waypoint"] = "" if nxt.is_empty() else "#" + nxt["id"]
		cc.issues.add("Autopilot: no clear path to #%s" % f["id"], "fail")
		return r
	if cc.hud != null:
		cc.hud.highlight_feature(f["id"], "COURSE LAID IN", r.get("seconds", 5.0) + 3.0)
	cc.issues.add("Autopilot engaged: course laid in for #%s %s (%d m)" % [f["id"], f["name"], r.get("distance_m", 0)], "info")
	r["message"] = "Autopilot engaged to #%s %s: %d m, about %d seconds.%s" % [
		f["id"], f["name"], r.get("distance_m", 0), int(ceil(r.get("seconds", 0.0))), note]
	return _with_pause_note(r)


func _full_stop() -> Dictionary:
	if cc.adapter == null:
		return _no_flight()
	var was: bool = cc.adapter.stop("full stop")
	return {"ok": true, "message": "All stop. Holding position." if was else "Already holding position."}


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


# ------------------------------------------------------------- helpers

func _no_flight() -> Dictionary:
	return {"ok": false, "message": "No flight in progress: the game is not in the cockpit right now (title menu or loading)."}


func _with_pause_note(r: Dictionary) -> Dictionary:
	if cc.adapter != null and cc.adapter.is_paused():
		r["message"] = str(r.get("message", "")) + " (The game is paused, so nothing will move until the pilot presses Escape to resume.)"
	return r


## Where the autopilot would stop for `f`: a landmark on a surface is
## approached to a standoff, so its path is checked to there.
func _approach_point(f: Dictionary) -> Vector3:
	var here: Vector3 = cc.adapter.pose()["position"]
	var rel: Vector3 = f["pos"] - here
	var standoff: float = LANDMARK_STANDOFF_M / cc.adapter.meters_per_unit()
	if f["kind"] != "landmark" or rel.length() <= standoff:
		return f["pos"] if f["kind"] != "landmark" else here
	return f["pos"] - rel.normalized() * standoff


func _on_screen(p: Vector3) -> bool:
	if cc.adapter == null:
		return false
	var sp: Variant = cc.adapter.project(p)
	if sp == null:
		return false
	var size: Vector2 = cc.hud.overlay.size if cc.hud != null and cc.hud.overlay.size != Vector2.ZERO else Vector2(1280, 800)
	return Rect2(Vector2.ZERO, size).has_point(sp)
