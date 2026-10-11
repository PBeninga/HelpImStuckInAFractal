extends Node
## The call centre: Sub-Dimensional Support, the AI help line a stranded pilot
## phones. One node, normally at /root/CallCenter (see boot.gd), that sits
## beside the game rather than inside it:
##
## - finds the game scene by itself (the current scene, or a node in it, that
##   offers `call_center_adapter()` or looks like the explorer's Main) and
##   flies the ship only through a ship adapter (adapter/ship_adapter.gd);
## - shows its own HUD: the diagnostics log, the call panel and transcript,
##   brackets on what the agent talks about;
## - serves the ship's MCP tools to the support-line relay (mcp/), which
##   connects the phone call (Twilio) to the voice agent (OpenAI Realtime).
##
## The game never has to know it is here. When it wants to, it talks to
## /root/CallCenter through the API below (all optional), e.g.
##
##   var cc := get_node_or_null(^"/root/CallCenter")
##   if cc:
##       cc.register_feature("2312", "The Recursive Cul-de-sac", pos, "route", "A dead end ...")
##       cc.set_route(["2312", "4096"]); cc.set_exit("9001")
##       cc.notify_agent("escaped", "The pilot flew into the rift and is home.")

signal game_attached(scene: Node)
signal game_detached
signal call_state_changed(state: String, info: Dictionary)
signal agent_said(text: String)
signal pilot_said(text: String)
signal pilot_issue_resolved(issue_id: String, answer: String, by: String)
## The ship came within ARRIVE_RADIUS_M of a route waypoint.
signal arrived(feature_id: String)
## The ship came within EXIT_RADIUS_M of the exit (again after leaving it).
signal exit_reached(feature_id: String)

const Features := preload("res://call_center/features.gd")
const IssueLog := preload("res://call_center/log/issue_log.gd")
const IssueCatalogue := preload("res://call_center/log/issue_catalogue.gd")
const Hud := preload("res://call_center/hud/hud.gd")
const ShipTools := preload("res://call_center/mcp/ship_tools.gd")
const ShipLink := preload("res://call_center/mcp/ship_link.gd")
const ExplorerAdapter := preload("res://call_center/adapter/explorer_adapter.gd")
const DemoMission := preload("res://call_center/demo/demo_mission.gd")

const ARRIVE_RADIUS_M := 30.0
const EXIT_RADIUS_M := 60.0
## Seconds from begin() to the first random pilot-input issue, between later
## ones, and how many there are at most.
const FIRST_PILOT_ISSUE := 45.0
const PILOT_ISSUE_GAP := Vector2(80.0, 130.0)
const FEATURE_ID_PATTERN := "#?\\b(\\d{4})\\b"

## Begin (HUD in, crash report) by itself this long after a game appears. A
## game with its own intro sets auto_begin = false and calls begin() itself.
@export var auto_begin := true
@export var begin_delay := 1.5
@export var max_random_pilot_issues := 3
## Off in tests: the ship link opens no socket.
@export var link_enabled := true
## Load the sample escape route and its rules (demo/).
@export var demo := false

var features := Features.new()
var issues: IssueLog
var hud: Hud
var tools: ShipTools
var link: ShipLink
## The ship adapter while a game is up, else null.
var adapter: Node
## Set by the game (lock_exit) while the way out is closed; the autopilot
## holds short of a locked exit and tells the agent why.
var exit_lock_reason := ""
## name -> {definition, handler}; see register_tool().
var custom_tools := {}

var _game: Node
var _owns_adapter := false
var _begun := false
var _begin_wait := -1.0
var _pilot_issue_wait := FIRST_PILOT_ISSUE
var _pilot_issues_raised := 0
var _at_exit := false
var _id_regex := RegEx.new()
var _mentioned := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_id_regex.compile(FEATURE_ID_PATTERN)
	issues = IssueLog.new()
	issues.name = "IssueLog"
	add_child(issues)
	hud = Hud.new()
	hud.name = "CallCenterHud"
	add_child(hud)
	hud.setup(features, issues)
	hud.set_adapter(null)
	tools = ShipTools.new(self)
	link = ShipLink.new()
	link.name = "ShipLink"
	link.tools = tools
	link.enabled = link_enabled
	add_child(link)
	issues.intro_script_finished.connect(_on_crash_report_done)
	issues.pilot_input_required.connect(_on_pilot_input_required)
	issues.issue_resolved.connect(func(issue: Dictionary, answer: String, by: String):
		pilot_issue_resolved.emit(issue["issue_id"], answer, by))
	link.connection_changed.connect(_on_link_changed)
	link.config_received.connect(func(c: Dictionary): hud.set_support_number(str(c.get("support_number", ""))))
	link.call_state_changed.connect(_on_call_state)
	link.transcript_received.connect(_on_transcript)
	if demo:
		var d := DemoMission.new()
		d.name = "DemoMission"
		add_child(d)
		d.setup(self)
	if link_enabled:
		link.start()


# ------------------------------------------------------------- the game API

## Start the show: HUD in, crash report, issues streaming. Called by itself
## (auto_begin) or by a game whose intro has finished.
func begin() -> void:
	if _begun:
		return
	_begun = true
	_begin_wait = -1.0
	hud.reveal()
	issues.play_intro_script()
	link.send_event("stage", "The ship has landed in fractal space after the failed punch jump.", {"stage": "stranded"}, false)


func has_begun() -> bool:
	return _begun


func register_feature(id: Variant, name: String, pos: Vector3, kind := "landmark", blurb := "") -> void:
	features.add(id, name, pos, kind, blurb)


func set_route(ids: Array) -> void:
	features.set_route(ids)


func set_exit(id: Variant) -> void:
	features.set_exit(id)


func clear_features() -> void:
	features.clear()


func load_features_json(path: String) -> Dictionary:
	return features.load_json(path)


## Close the way out (the autopilot holds short and tells the agent why).
func lock_exit(reason: String) -> void:
	exit_lock_reason = reason


func unlock_exit() -> void:
	exit_lock_reason = ""


## Put something into the call: the agent hears `summary` as a SHIP EVENT and
## reacts. notify = false only informs the relay (no reaction).
func notify_agent(kind: String, summary: String, data: Dictionary = {}, notify := true) -> void:
	link.send_event(kind, summary, data, notify)


## Ask the pilot something through the agent. `outcome` formats their answer
## into the log ("%s"). Returns the issue id; pilot_issue_resolved follows.
func raise_pilot_issue(problem: String, question: String, default_answer: String,
		outcome := "Pilot says '%s'.", blocks_exit := false) -> String:
	return raise_pilot_issue_from({"problem": problem, "question": question,
		"default": default_answer, "outcome": outcome, "gating": blocks_exit})


## The same from a template such as IssueCatalogue.EGRESS_WAIVER.
func raise_pilot_issue_from(template: Dictionary) -> String:
	return issues.raise_pilot_issue(template)["issue_id"]


func log_line(text: String, style := "info") -> void:
	issues.add(text, style)


func highlight(id: Variant, label := "", seconds := 12.0) -> void:
	hud.highlight_feature(str(id), label, seconds)


## Give the agent a new tool. `input_schema` is a JSON Schema object;
## `handler` takes the arguments Dictionary and returns {ok, message, ...}.
func register_tool(tool_name: String, description: String, input_schema: Dictionary, handler: Callable) -> void:
	custom_tools[tool_name] = {"handler": handler, "definition": {
		"name": tool_name, "description": description, "inputSchema": input_schema}}
	link.notify_tools_changed()


func unregister_tool(tool_name: String) -> void:
	if custom_tools.erase(tool_name):
		link.notify_tools_changed()


# ------------------------------------------------------------- finding the game

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _game:
		_detach()
		if scene != null:
			_attach(scene)
	if adapter == null or not _begun and _begin_wait < 0.0:
		return
	if get_tree().paused:
		return
	if not _begun:
		_begin_wait -= delta
		if _begin_wait <= 0.0:
			begin()
		return
	_check_positions()
	if _pilot_issues_raised < max_random_pilot_issues and not issues.is_scripting():
		_pilot_issue_wait -= delta
		if _pilot_issue_wait <= 0.0:
			_pilot_issue_wait = randf_range(PILOT_ISSUE_GAP.x, PILOT_ISSUE_GAP.y)
			_pilot_issues_raised += 1
			issues.raise_pilot_issue()


func _attach(scene: Node) -> void:
	_game = scene
	var found := _find_adapter(scene, 3)
	if found == null:
		return   # not a flight (the title menu): stay out of the way
	adapter = found
	if adapter.get_parent() == null:
		add_child(adapter)
		_owns_adapter = true
	adapter.maneuver_finished.connect(_on_maneuver_finished)
	adapter.manual_override.connect(_on_manual_override)
	features.visited.clear()
	_at_exit = false
	hud.set_adapter(adapter)
	game_attached.emit(scene)
	if auto_begin and not _begun:
		_begin_wait = begin_delay


func _detach() -> void:
	_game = null
	if adapter == null:
		return
	if is_instance_valid(adapter):
		adapter.stop("the flight ended")
		adapter.maneuver_finished.disconnect(_on_maneuver_finished)
		adapter.manual_override.disconnect(_on_manual_override)
		if _owns_adapter:
			adapter.queue_free()
	adapter = null
	_owns_adapter = false
	_begin_wait = -1.0
	hud.set_adapter(null)
	game_detached.emit()


## The game's own adapter (call_center_adapter()), or the explorer adapter for
## a Main-like node, searching `depth` levels into the scene.
func _find_adapter(node: Node, depth: int) -> Node:
	if node.has_method("call_center_adapter"):
		return node.call_center_adapter()
	if ExplorerAdapter.fits(node):
		return ExplorerAdapter.new(node)
	if depth > 0:
		for child in node.get_children():
			var a := _find_adapter(child, depth - 1)
			if a != null:
				return a
	return null


# ------------------------------------------------------------- ship events

func _check_positions() -> void:
	var here: Vector3 = adapter.pose()["position"]
	var m: float = adapter.meters_per_unit()
	for id in features.route:
		var f := features.find(id)
		if f.is_empty() or features.visited.has(id):
			continue
		if here.distance_to(f["pos"]) * m < ARRIVE_RADIUS_M:
			features.visited[id] = true
			issues.add("Waypoint #%s %s reached" % [id, f["name"]], "ok")
			var nxt := features.next_waypoint()
			var summary := "The ship has reached waypoint #%s %s." % [id, f["name"]]
			if not nxt.is_empty():
				var rel := Features.relative(adapter.pose(), nxt["pos"], m)
				summary += " Next on the way out: #%s %s, %d m %s." % [nxt["id"], nxt["name"], rel["range_m"], rel["direction"]]
			link.send_event("waypoint_reached", summary, {"feature_id": "#" + id,
				"next_feature_id": "" if nxt.is_empty() else "#" + nxt["id"]})
			arrived.emit(id)
	var ex := features.exit()
	if ex.is_empty():
		return
	var d: float = here.distance_to(ex["pos"]) * m
	if d < EXIT_RADIUS_M and not _at_exit:
		_at_exit = true
		exit_reached.emit(ex["id"])
	elif d > EXIT_RADIUS_M * 2.0:
		_at_exit = false


func _on_maneuver_finished(kind: String, info: Dictionary) -> void:
	if kind != "fly" or not info.get("completed", false):
		return
	var f := features.find(info.get("target_id", ""))
	if f.is_empty() or f["kind"] == "route":
		return   # route waypoints report through _check_positions
	var summary := "Autopilot arrived at #%s %s." % [f["id"], f["name"]]
	if f["kind"] == "exit" and exit_lock_reason != "":
		summary += " The ship is holding outside it: it is locked (%s)." % exit_lock_reason
	link.send_event("arrived", summary, {"feature_id": "#" + f["id"]})


func _on_manual_override() -> void:
	issues.add("Manual override: autopilot disengaged", "info")
	link.send_event("manual_override", "The pilot took manual control with the flight keys; the autopilot has disengaged.")


func _on_crash_report_done() -> void:
	issues.auto_running = true
	link.send_event("stage", "The crash report is done; the ship is waiting for the pilot to call support.", {"stage": "awaiting_call"}, false)
	if link.connected or not link.enabled:
		issues.add("Support line open. Awaiting pilot's call.", "system")
	else:
		issues.add("Support relay unreachable at %s. Retrying..." % link.url, "system")
	hud.flash("call_panel")


func _on_pilot_input_required(issue: Dictionary) -> void:
	var summary := "Diagnostics issue %s needs the pilot: %s. Ask the pilot: %s Then call resolve_issue with their answer." % [
		issue["issue_id"], issue["problem"], issue["question"]]
	if issue["blocks_exit"]:
		summary += " The exit will not open until this is resolved."
	link.send_event("pilot_input_required", summary, issue)
	hud.flash("diagnostics_log")


# ------------------------------------------------------------- the line

func _on_link_changed(up: bool) -> void:
	hud.set_link_state(up)
	if _begun:
		issues.add("Support relay %s" % ("connected" if up else "lost; retrying"), "system")


func _on_call_state(state: String, info: Dictionary) -> void:
	hud.set_call_state(state, info)
	match state:
		"ringing":
			issues.add("Incoming support connection", "system")
		"connected":
			issues.add("Agent %s connected" % info.get("agent_name", ""), "system")
			issues.set_agent_available(true)
			_pilot_issue_wait = minf(_pilot_issue_wait, FIRST_PILOT_ISSUE)
			hud.flash("call_panel")
		"ended":
			issues.add("Support call ended", "system")
			issues.set_agent_available(false)
	call_state_changed.emit(state, info)


## Show the line and highlight any feature it names ("#2312", "2312" or its
## name), once per transcript item.
func _on_transcript(role: String, item_id: String, text: String, final: bool) -> void:
	hud.show_transcript(role, item_id, text)
	if role != "agent":
		if final:
			pilot_said.emit(text)
		return
	if final:
		agent_said.emit(text)
	var seen: Dictionary = _mentioned.get(item_id, {})
	for id in mentioned_features(text):
		if not seen.has(id):
			seen[id] = true
			hud.highlight_feature(id, "", 12.0)
	if text.to_lower().contains("diagnostic") and not seen.has("log"):
		seen["log"] = true
		hud.flash("diagnostics_log")
	_mentioned[item_id] = seen


## The feature ids a line of speech refers to, by number or by name.
func mentioned_features(text: String) -> Array:
	var out: Array = []
	for m in _id_regex.search_all(text):
		var f := features.find(m.get_string(1))
		if not f.is_empty() and not out.has(f["id"]):
			out.append(f["id"])
	var lower := text.to_lower()
	for f in features.all():
		var name: String = String(f["name"]).to_lower().trim_prefix("the ")
		if name.length() > 3 and lower.contains(name) and not out.has(f["id"]):
			out.append(f["id"])
	return out
