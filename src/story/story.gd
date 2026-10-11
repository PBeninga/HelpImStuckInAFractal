class_name Story
extends Node
## Story mode: "Help, I'm stuck in a fractal". Wraps the explorer (Main, a
## child scene) with the failed hyperspace jump, the ship's diagnostics log,
## the HUD, the autopilot, and the ship's MCP link to the support-line relay
## (server/), where an AI support agent on a phone call flies the ship by
## calling ShipTools.
##
##   intro (StoryIntro) -> landed: HUD in, crash report plays
##   -> "connecting to agent": the support number shows; issues stream by
##   -> the pilot calls; the agent scans, highlights and flies waypoints
##   -> near the rift the egress waiver needs the pilot's answer
##   -> into the rift: StoryOutro, then Back to Menu or Keep Exploring.

const MENU_SCENE := "res://src/ui/main_menu.tscn"
## Seconds from stranding to the first random pilot-input issue, between later
## ones, and how many there are at most (the waiver is extra).
const FIRST_PILOT_ISSUE := 45.0
const PILOT_ISSUE_GAP := Vector2(80.0, 130.0)
const MAX_PILOT_ISSUES := 3
const FEATURE_ID_PATTERN := "#?\\b(\\d{4})\\b"

@onready var main: Node = $Main

var issue_log: IssueLog
var ship: ShipController
var mission: Mission
var hud: StoryHud
var intro: StoryIntro
var outro: StoryOutro
var link: ShipLink
var tools: ShipTools
## Off in tests so the intro can be stepped by hand.
var autostart := true

var _pilot_issue_wait := FIRST_PILOT_ISSUE
var _pilot_issues_raised := 0
var _id_regex := RegEx.new()
var _mentioned := {}             # transcript item_id -> ids already highlighted


func _ready() -> void:
	_id_regex.compile(FEATURE_ID_PATTERN)
	var camera: CameraState = main.camera
	var params: FractalParams = main.params
	camera.transform = Route.start_transform()
	main.view.set_rift(true, Route.RIFT_POS, Route.RIFT_NORMAL, Route.RIFT_RADIUS)
	main.fly.input_locked = true

	issue_log = IssueLog.new()
	issue_log.name = "IssueLog"
	add_child(issue_log)

	ship = ShipController.new()
	ship.name = "ShipController"
	add_child(ship)
	ship.setup(params, camera, main.fly)

	mission = Mission.new()
	mission.name = "Mission"
	add_child(mission)
	mission.setup(params, camera, issue_log)

	hud = StoryHud.new()
	hud.name = "StoryHud"
	add_child(hud)
	hud.setup(main.view, camera, params, mission, ship, issue_log)

	intro = StoryIntro.new()
	intro.name = "StoryIntro"
	add_child(intro)
	outro = StoryOutro.new()
	outro.name = "StoryOutro"
	add_child(outro)

	tools = ShipTools.new()
	tools.setup(ship, mission, issue_log, params, camera)
	tools.hud = hud
	tools.is_paused = func() -> bool: return get_tree().paused
	tools.set_color_mode = _set_color_mode

	link = ShipLink.new()
	link.name = "ShipLink"
	link.tools = tools
	add_child(link)

	intro.landed.connect(_on_landed)
	intro.finished.connect(func(): main.fly.input_locked = false)
	issue_log.intro_script_finished.connect(_on_crash_report_done)
	issue_log.pilot_input_required.connect(_on_pilot_input_required)
	mission.waypoint_reached.connect(_on_waypoint_reached)
	mission.rift_refused.connect(_on_rift_refused)
	mission.egress_started.connect(_on_egress)
	ship.maneuver_finished.connect(_on_maneuver_finished)
	ship.manual_override.connect(_on_manual_override)
	link.connection_changed.connect(_on_link_changed)
	link.config_received.connect(_on_config)
	link.call_state_changed.connect(_on_call_state)
	link.transcript_received.connect(_on_transcript)
	outro.back_to_menu_requested.connect(func(): main.back_to_menu())
	outro.keep_exploring_requested.connect(_keep_exploring)

	if autostart:
		intro.start()
		link.start()


func _process(delta: float) -> void:
	if mission.stage == Mission.Stage.STRANDED or mission.stage == Mission.Stage.ESCAPING:
		if _pilot_issues_raised < MAX_PILOT_ISSUES and not issue_log.is_scripting():
			_pilot_issue_wait -= delta
			if _pilot_issue_wait <= 0.0:
				_pilot_issue_wait = randf_range(PILOT_ISSUE_GAP.x, PILOT_ISSUE_GAP.y)
				_pilot_issues_raised += 1
				issue_log.raise_pilot_issue()


# ------------------------------------------------------------- stages

func _on_landed() -> void:
	mission.set_stage(Mission.Stage.STRANDED)
	hud.reveal()
	issue_log.play_intro_script()
	link.send_event("stage", "The ship has landed in fractal space after the failed punch jump.", {"stage": "stranded"}, false)


func _on_crash_report_done() -> void:
	issue_log.auto_running = true
	link.send_event("stage", "The crash report is done; the ship is waiting for the pilot to call support.", {"stage": "awaiting_call"}, false)
	if link.connected:
		issue_log.add("Support line open. Awaiting pilot's call.", "system")
	else:
		issue_log.add("Support relay unreachable at %s. Retrying..." % link.url, "system")
	hud.flash("call_panel")


func _on_egress() -> void:
	ship.stop("egress")
	main.fly.input_locked = true
	issue_log.auto_running = false
	issue_log.add("Rift handshake accepted. Punch jump resuming.", "ok")
	var secs := int(mission.stranded_seconds)
	var stats := [
		"Time stuck in fractal space: %d min %02d s" % [secs / 60, secs % 60],
		"Waypoints navigated: %d of %d" % [mission.visited.size(), Route.waypoints().size() - 1],
		"Issues auto-resolved: %d" % issue_log.resolved_count,
		"Questions answered by the pilot: %d" % issue_log.pilot_answers,
	]
	link.send_event("escaped", "The ship has flown into the egress rift and left fractal space. The pilot is safe. Congratulate them, ask them to rate the call from 1 to 5 fractal dimensions, and sign off.",
		{"stranded_seconds": secs})
	outro.start(stats)
	var tw := create_tween()
	tw.tween_interval(StoryOutro.WARP_END)
	tw.tween_callback(_after_egress)


## Behind the outro's last white-out: put the ship outside the cube, looking
## back at it, so the end card sits over the whole Mandelbox.
func _after_egress() -> void:
	mission.set_stage(Mission.Stage.ESCAPED)
	main.view.set_rift(false)
	main.camera.transform = CameraState.make_default().transform
	hud.overlay.show_exit = false
	hud.clear_highlights()
	# the end card owns the middle; the call panel stays for the sign-off
	hud.set_panel_visible("diagnostics_log", false)
	hud.set_panel_visible("ship_status", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _keep_exploring() -> void:
	outro.hide_card()
	main.fly.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if main.is_mouse_captured() else Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------- ship events

func _on_waypoint_reached(f: Dictionary) -> void:
	issue_log.add("Waypoint #%s %s reached" % [f["id"], f["name"]], "ok")
	var nxt := mission.next_waypoint()
	var summary := "The ship has reached waypoint #%s %s." % [f["id"], f["name"]]
	if not nxt.is_empty():
		var rel := ShipController.relative(main.camera, nxt["pos"])
		summary += " Next on the way out: #%s %s, %d m %s." % [nxt["id"], nxt["name"], rel["range_m"], rel["direction"]]
	link.send_event("waypoint_reached", summary, {"feature_id": "#" + f["id"],
		"next_feature_id": "" if nxt.is_empty() else "#" + nxt["id"]})


func _on_maneuver_finished(kind: String, info: Dictionary) -> void:
	if kind != "fly":
		return
	var f := Route.feature(info.get("target_id", ""))
	if f.is_empty() or f["kind"] == "route":
		return   # route waypoints report through waypoint_reached
	if info["completed"]:
		var summary := "Autopilot arrived at #%s %s." % [f["id"], f["name"]]
		if f["kind"] == "exit" and not mission.waiver_signed:
			summary += " The ship is holding at the rift: it will not open until the egress waiver %s is signed." % mission.waiver_issue_id
		link.send_event("arrived", summary, {"feature_id": "#" + f["id"]})


func _on_manual_override() -> void:
	issue_log.add("Manual override: autopilot disengaged", "info")
	link.send_event("manual_override", "The pilot took manual control with the flight keys; the autopilot has disengaged.")


func _on_pilot_input_required(issue: Dictionary) -> void:
	var summary := "Diagnostics issue %s needs the pilot: %s. Ask the pilot: %s Then call resolve_issue with their answer." % [
		issue["issue_id"], issue["problem"], issue["question"]]
	if issue["blocks_exit"]:
		summary += " The exit rift will not open until this is resolved."
	link.send_event("pilot_input_required", summary, issue)
	hud.flash("diagnostics_log")


func _on_rift_refused(issue_id: String) -> void:
	link.send_event("rift_refused", "The ship is at the rift but it refused to open: egress waiver %s is unsigned. Get the pilot's answer and call resolve_issue." % issue_id,
		{"issue_id": issue_id})


# ------------------------------------------------------------- the line

func _on_link_changed(up: bool) -> void:
	hud.set_link_state(up)
	if mission.stage != Mission.Stage.INTRO:
		issue_log.add("Support relay %s" % ("connected" if up else "lost; retrying"), "system")
	if up:
		link.send_event("stage", "Ship link up. Mission stage: %s." % mission.stage_name(), {"stage": mission.stage_name()}, false)


func _on_config(config: Dictionary) -> void:
	hud.set_support_number(str(config.get("support_number", "")))


func _on_call_state(state: String, info: Dictionary) -> void:
	hud.set_call_state(state, info)
	match state:
		"ringing":
			issue_log.add("Incoming support connection", "system")
		"connected":
			issue_log.add("Agent %s connected" % info.get("agent_name", ""), "system")
			issue_log.set_agent_available(true)
			if mission.stage == Mission.Stage.STRANDED:
				mission.set_stage(Mission.Stage.ESCAPING)
			_pilot_issue_wait = minf(_pilot_issue_wait, FIRST_PILOT_ISSUE)
			hud.flash("call_panel")
		"ended":
			issue_log.add("Support call ended", "system")
			issue_log.set_agent_available(false)


## Show the line and highlight any characteristic it names ("#2312", "2312"
## or its name), once per transcript item.
func _on_transcript(role: String, item_id: String, text: String, final: bool) -> void:
	hud.show_transcript(role, item_id, text, final)
	if role != "agent":
		return
	var seen: Dictionary = _mentioned.get(item_id, {})
	for id in mentioned_features(text):
		if not seen.has(id):
			seen[id] = true
			hud.highlight_feature(id, "", 12.0)
	_mentioned[item_id] = seen
	if text.to_lower().contains("diagnostic") and not seen.has("log"):
		seen["log"] = true
		hud.flash("diagnostics_log")


## The feature ids a line of speech refers to, by number or by name.
func mentioned_features(text: String) -> Array:
	var out: Array = []
	for m in _id_regex.search_all(text):
		var f := Route.feature(m.get_string(1))
		if not f.is_empty() and not out.has(f["id"]):
			out.append(f["id"])
	var lower := text.to_lower()
	for f in Route.FEATURES:
		var name: String = String(f["name"]).to_lower().trim_prefix("the ")
		if lower.contains(name) and not out.has(f["id"]):
			out.append(f["id"])
	return out


func _set_color_mode(id: int) -> void:
	main.table().set_default(&"color_mode", id)
