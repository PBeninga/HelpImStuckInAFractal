extends Node
## The call centre: Sub-Dimensional Support, the AI help line a stranded pilot
## phones. One node at /root/CallCenter (McpBridge starts it with
## `-- --call-center`; see call_center/run.sh) that sits beside the game
## rather than inside it:
##
## - finds the game scene by itself (the current scene, or a node in it, that
##   offers `call_center_adapter()` or looks like the explorer's Main) and
##   flies the ship only through a ship adapter (adapter/ship_adapter.gd);
## - shows its own HUD: the diagnostics log, ship status, the support-line
##   panel and direction guidance (the conversation
##   itself is in McpBridge's pilot chat);
## - adds the ship's tools and events to McpBridge as commands, which the
##   phone link carries to the phone server's voice agent and mcp/server.mjs
##   offers to Claude:
##
##     ship_tools                 -> {tools: [{name, description, inputSchema}]}
##     ship_tool {name, arguments} -> the tool's result {ok, message, ...}
##     ship_events {after, timeout} -> {events: [{id, kind, summary, notify_agent, ...}], last_id}
##     call_center {support_number, call_state, agent_name, link_up} -> {status}
##
## The game never has to know it is here. When it wants to, it talks to
## /root/CallCenter through the API below (all optional), e.g.
##
##   var cc := get_node_or_null(^"/root/CallCenter")
##   if cc:
##       cc.log_line("Support connected.", "info")

signal game_attached(scene: Node)
signal game_detached
signal call_state_changed(state: String, info: Dictionary)
signal agent_said(text: String)
signal pilot_said(text: String)
signal pilot_issue_resolved(issue_id: String, answer: String, by: String)
## Legacy extension signal; live navigation reports instruction events.
signal arrived(feature_id: String)
## The ship crossed the Gameplay exit sphere; legacy argument is empty.
signal exit_reached(feature_id: String)

const Features := preload("res://call_center/features.gd")
const IssueLog := preload("res://call_center/log/issue_log.gd")
const IssueCatalogue := preload("res://call_center/log/issue_catalogue.gd")
const Hud := preload("res://call_center/hud/hud.gd")
const ConsoleTools := preload("res://call_center/mcp/console_tools.gd")
const ShipTools := preload("res://call_center/mcp/ship_tools.gd")
const ExplorerAdapter := preload("res://call_center/adapter/explorer_adapter.gd")

## Seconds from begin() to the first random pilot-input issue, between later
## ones, and how many there are at most.
const FIRST_PILOT_ISSUE := 45.0
const PILOT_ISSUE_GAP := Vector2(80.0, 130.0)
const FEATURE_ID_PATTERN := "#?\\b(\\d{4})\\b"
const MAX_EVENTS := 200
## The McpBridge commands this adds.
const COMMANDS := ["ship_tools", "ship_tool", "ship_events", "call_center"]

## Begin (HUD in, crash report) by itself this long after a game appears. A
## game with its own intro sets auto_begin = false and calls begin() itself.
@export var auto_begin := true
@export var begin_delay := 1.5
@export var max_random_pilot_issues := 0
## Legacy launch flag retained for compatibility; navigation uses live geometry.
@export var demo := false

var features := Features.new()
var issues: IssueLog
var hud: Hud
var tools: ShipTools
var console_tools: ConsoleTools
## The ship adapter while a game is up, else null.
var adapter: Node
## Legacy extension state; it does not gate live coordinate navigation.
var exit_lock_reason := ""
## name -> {definition, handler}; see register_tool().
var custom_tools := {}
## The support line as the phone link reports it (the call_center command).
var link_up := false
var call_state := "idle"

var _bridge: Node
var _chat_listener := false      # holding one of the pilot chat's listeners
var _events: Array = []          # {id, kind, summary, notify_agent, ...}
var _next_event_id := 1
var _game: Node
var _owns_adapter := false
var _begun := false
var _begin_wait := -1.0
var _pilot_issue_wait := FIRST_PILOT_ISSUE
var _pilot_issues_raised := 0
var _at_exit := false
var _id_regex := RegEx.new()


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
	issues.intro_script_finished.connect(_on_crash_report_done)
	issues.pilot_input_required.connect(_on_pilot_input_required)
	issues.issue_resolved.connect(func(issue: Dictionary, answer: String, by: String):
		pilot_issue_resolved.emit(issue["issue_id"], answer, by))
	_attach_bridge()


func _exit_tree() -> void:
	if _bridge != null and is_instance_valid(_bridge):
		_hold_chat_listener(false)
		for cmd in COMMANDS:
			_bridge.unregister_command(cmd)
		var chat: Object = _bridge.get("chat")
		if chat != null and chat.message_added.is_connected(_on_chat_message):
			chat.message_added.disconnect(_on_chat_message)


## Hook into McpBridge (the game's command socket and pilot chat), if present.
func _attach_bridge() -> void:
	_bridge = get_node_or_null(^"/root/McpBridge")
	if _bridge == null or not _bridge.has_method("register_command"):
		_bridge = null
		return
	_bridge.register_command("ship_tools", func(_a: Dictionary) -> Dictionary: return {"tools": tools.definitions()})
	_bridge.register_command("ship_tool", _cmd_ship_tool)
	_bridge.register_command("ship_events", _cmd_ship_events)
	_bridge.register_command("call_center", _cmd_call_center)
	console_tools = ConsoleTools.new(_bridge)
	console_tools.register(self)
	var chat: Object = _bridge.get("chat")
	if chat != null:
		chat.message_added.connect(_on_chat_message)


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
	notify_agent("stage", "The ship has landed in fractal space after the failed punch jump.", {"stage": "stranded"}, false)


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


## Legacy extension API; Gameplay exit-sphere navigation has no locks.
func lock_exit(reason: String) -> void:
	exit_lock_reason = reason


func unlock_exit() -> void:
	exit_lock_reason = ""


## Put something into the call: the voice agent hears `summary` as a SHIP
## EVENT and reacts. notify = false only informs the phone server.
func notify_agent(kind: String, summary: String, data: Dictionary = {}, notify := true) -> void:
	# Events may wake an agent, but must not authorize scripted shape edits.
	if kind in ["instruction_completed", "instruction_cancelled", "escaped", "active_shape_changed"] 			and adapter != null and adapter.get("game") != null and adapter.game.get("shape_run") != null:
		adapter.game.shape_run.invalidate_human_message()
	var ev := data.duplicate()
	ev["id"] = _next_event_id
	ev["kind"] = kind
	ev["summary"] = summary
	ev["notify_agent"] = notify
	_next_event_id += 1
	_events.append(ev)
	if _events.size() > MAX_EVENTS:
		_events.pop_front()


## Ship events after `after` (for the ship_events command).
func events_after(after: int) -> Array:
	return _events.filter(func(e): return e["id"] > after)


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
## The phone server hears "tools_changed" and updates a live call.
func register_tool(tool_name: String, description: String, input_schema: Dictionary, handler: Callable) -> void:
	custom_tools[tool_name] = {"handler": handler, "definition": {
		"name": tool_name, "description": description, "inputSchema": input_schema}}
	notify_agent("tools_changed", "The ship's tool list changed.", {}, false)


func unregister_tool(tool_name: String) -> void:
	if custom_tools.erase(tool_name):
		notify_agent("tools_changed", "The ship's tool list changed.", {}, false)


# ------------------------------------------------------------- bridge commands

func _cmd_ship_tool(args: Dictionary) -> Dictionary:
	var tool_name := str(args.get("name", ""))
	if not tools.has_tool(tool_name):
		return {"error": "unknown ship tool '%s'" % tool_name}
	var a: Variant = args.get("arguments", {})
	return await tools.call_tool(tool_name, a if a is Dictionary else {})


## Long-poll: events after `after`, waiting up to `timeout` seconds for one.
## Without `after` it answers at once with just the newest id.
func _cmd_ship_events(args: Dictionary) -> Dictionary:
	var last_id: int = _events[-1]["id"] if not _events.is_empty() else 0
	if not args.has("after"):
		return {"events": [], "last_id": last_id}
	var after := int(args["after"])
	var timeout := clampf(float(args.get("timeout", 20.0)), 0.0, 120.0)
	var fresh := events_after(after)
	var waited := 0.0
	while fresh.is_empty() and waited < timeout and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
		fresh = events_after(after)
	last_id = _events[-1]["id"] if not _events.is_empty() else 0
	return {"events": fresh, "last_id": maxi(last_id, after)}


## The phone side reports in: the number to show, the call, the link.
func _cmd_call_center(args: Dictionary) -> Dictionary:
	if args.has("support_number"):
		hud.set_support_number(str(args["support_number"]))
	if args.has("link_up"):
		_set_link_up(bool(args["link_up"]))
	if args.has("call_state"):
		_set_call_state(str(args["call_state"]), args)
	return status()


func status() -> Dictionary:
	return {"begun": _begun, "in_flight": adapter != null, "call_state": call_state,
		"link_up": link_up, "open_issues": issues.pending().size()}


# ------------------------------------------------------------- finding the game

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _game:
		_detach()
		if scene != null:
			_attach(scene)
	if adapter == null or (not _begun and _begin_wait < 0.0) or get_tree().paused:
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
	var briefing: Dictionary = adapter.shape_briefing()
	if not briefing.is_empty():
		notify_agent("run_started", "Active shape briefing: " + JSON.stringify(briefing))
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
	var state: Dictionary = adapter.escape_state()
	var outside: bool = state.get("escaped", false)
	if outside and not _at_exit:
		notify_agent("escaped", "The player crossed the fractal's exit sphere and escaped.", adapter.navigation_pose())
		exit_reached.emit("")
	_at_exit = outside


func _on_maneuver_finished(kind: String, info: Dictionary) -> void:
	var completed: bool = info.get("completed", false)
	var event := "instruction_completed" if completed else "instruction_cancelled"
	var summary := "Instruction %s (%s) %s: %s." % [str(info.get("instruction_id", "")), kind,
		"completed" if completed else "cancelled", str(info.get("reason", ""))]
	# One terminal event per accepted instruction. Never attach sensor arrays.
	notify_agent(event, summary, info)


func _on_manual_override() -> void:
	issues.add("Manual override: autopilot disengaged", "info")
	# The cancellation event already tells the agent about this override.


func _on_crash_report_done() -> void:
	issues.auto_running = true
	notify_agent("stage", "The crash report is done; the ship is waiting for the pilot to call support.", {"stage": "awaiting_call"}, false)
	if link_up:
		issues.add("Support line open. Awaiting pilot's call.", "system")
	else:
		issues.add("Support line not linked yet: set FRACTAL_SERVER_URL and GAME_LINK_TOKEN (server/.env).", "system")
	hud.flash("call_panel")


func _on_pilot_input_required(issue: Dictionary) -> void:
	var summary := "Diagnostics issue %s needs the pilot: %s. Ask the pilot: %s Then call resolve_issue with their answer." % [
		issue["issue_id"], issue["problem"], issue["question"]]
	if issue["blocks_exit"]:
		summary += " The exit will not open until this is resolved."
	notify_agent("pilot_input_required", summary, issue)
	hud.flash("diagnostics_log")


# ------------------------------------------------------------- the line

func _set_link_up(up: bool) -> void:
	if up == link_up:
		return
	link_up = up
	hud.set_link_state(up)
	if _begun:
		issues.add("Support line %s" % ("linked" if up else "lost; retrying"), "system")
	_hold_chat_listener(link_up and call_state == "connected")


func _set_call_state(state: String, info: Dictionary) -> void:
	if state == call_state and state != "connected":
		return
	call_state = state
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
	_hold_chat_listener(link_up and call_state == "connected")
	call_state_changed.emit(state, info)


## While a call is up, the phone agent hears what the pilot types (the link
## passes it on), so the pilot chat shows an agent listening.
func _hold_chat_listener(on: bool) -> void:
	if on == _chat_listener or _bridge == null or not is_instance_valid(_bridge):
		return
	var chat: Object = _bridge.get("chat")
	if chat == null:
		return
	_chat_listener = on
	chat.listeners += 1 if on else -1


## Forward chat signals and flash the diagnostics panel when mentioned.
func _on_chat_message(m: Dictionary) -> void:
	var text := str(m.get("text", ""))
	match str(m.get("role", "")):
		"agent":
			agent_said.emit(text)
			if text.to_lower().contains("diagnostic"):
				hud.flash("diagnostics_log")
		"human":
			pilot_said.emit(text)


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
