extends "res://call_center/tests/test_case.gd"
## The call centre beside the game, driven the way the phone link drives it:
## through McpBridge commands. It finds the game scene by itself, flies the ship
## only through the adapter, serves its tools (ship_tools / ship_tool, including
## ones the game registers at runtime), queues ship events for the link
## (ship_events), takes the call state from it (call_center), highlights what
## the agent says in the pilot chat, and in demo mode flies the sample route to
## a locked exit, unlocks it with the pilot's answer and escapes. Leaving the
## game detaches it cleanly.
##
## The game scene and McpBridge are used untyped (their scripts name autoloads,
## which a `-s` script cannot see when it is compiled).

const CallCenter := preload("res://call_center/call_center.gd")
const ExplorerAdapter := preload("res://call_center/adapter/explorer_adapter.gd")

var cc: CallCenter
var game: Node
var bridge: Node


func run() -> void:
	bridge = root.get_node_or_null("McpBridge")
	check(bridge != null and bridge.has_method("register_command"), "McpBridge is up and takes extra commands")
	if bridge == null:
		return
	game = load("res://src/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	cc = CallCenter.new()
	cc.name = "CallCenter"
	cc.auto_begin = false
	cc.demo = true
	root.add_child(cc)
	await frames(3)

	_attaches()
	if cc.adapter == null:
		check(false, "the rest needs the adapter")
		return
	cc.adapter.set_physics_process(false)   # the test steps the ship
	cc.issues.set_process(false)
	await _begin_and_crash_report()
	await _tools()
	await _custom_tools()
	await _call_and_chat()
	await _fly_the_route_and_escape()
	await _detaches()
	cc.queue_free()
	await frames(2)
	check(not bridge.has_command("ship_tool"), "a freed call centre takes its commands with it")


func _attaches() -> void:
	for c in CallCenter.COMMANDS:
		check(bridge.has_command(c), "the call centre added '%s' to McpBridge" % c)
	check(cc.adapter is ExplorerAdapter, "it found the game scene and picked the explorer adapter")
	var eye: Vector3 = cc.adapter.pose()["position"]
	check(eye.is_equal_approx(Vector3(1.5, 0, 0)), "the demo placed the ship at the sample start")
	check(cc.hud.visible, "the HUD shows over the game")
	check(not cc.hud.is_panel_visible("diagnostics_log"), "panels wait for begin()")
	check(cc.features.find("#2312").size() > 0 and cc.features.exit_id == "9001", "the demo registered the sample route")
	var chat_panel: Node = game.chat() if game.has_method("chat") else null
	var log_rect: Rect2 = cc.hud._panels["diagnostics_log"].get_global_rect()
	if chat_panel != null:
		check(not log_rect.intersects(chat_panel.get_global_rect()), "the diagnostics log stays clear of the pilot chat")


func _begin_and_crash_report() -> void:
	var before: Dictionary = await bridge.handle("ship_events", {})
	cc.begin()
	check(cc.hud.is_panel_visible("diagnostics_log") and cc.hud.is_panel_visible("call_panel"), "begin() reveals the HUD")
	check(cc.issues.is_scripting(), "and plays the crash report")
	for i in 40:
		cc.issues.advance(0.5)
	var joined := "\n".join(cc.issues.entries.map(func(e): return e["text"]))
	check(joined.contains("animalifolds instead of manifolds"), "the crash report has the animalifolds")
	check(joined.contains("forced evfoldlution"), "and the evfoldlution")
	check(joined.contains("connecting to agent"), "and hands off to an agent")
	check(cc.issues.auto_running, "then issues stream in on their own")
	var evs: Dictionary = await bridge.handle("ship_events", {"after": before["last_id"], "timeout": 0})
	var stages: Array = evs["events"].filter(func(e): return e["kind"] == "stage").map(func(e): return e["stage"])
	check(stages == ["stranded", "awaiting_call"], "ship_events carries the stages for the phone server (%s)" % [stages])
	check(evs["last_id"] >= 2, "with a cursor")
	var t0 := Time.get_ticks_msec()
	var none: Dictionary = await bridge.handle("ship_events", {"after": evs["last_id"], "timeout": 0.3})
	check(none["events"].is_empty() and Time.get_ticks_msec() - t0 >= 250, "ship_events long-polls when there is nothing new")


func _tools() -> void:
	var listed: Dictionary = await bridge.handle("ship_tools", {})
	var names: Array = listed["tools"].map(func(t): return t["name"])
	for n in ["get_ship_status", "scan_surroundings", "highlight", "turn_ship", "thrust", "fly_to_feature", "resolve_issue", "post_to_log", "set_visual_filter"]:
		check(names.has(n), "ship_tools has %s" % n)
	check(listed["tools"].all(func(t): return t["inputSchema"]["type"] == "object"), "every tool has an object inputSchema")
	var s := await _call("get_ship_status")
	check(s["ok"] and s["in_flight"], "status: in flight")
	check_eq(s["next_waypoint"]["feature_id"], "#2312", "next waypoint #2312")
	check(s["clearance_m"] >= 70, "clearance in metres (%d)" % s["clearance_m"])
	check(not s["exit"]["path_clear"], "no straight path to the exit from the start")
	check(s["world"].get("type") == "Mandelbox", "world facts for the babble")
	var scan := await _call("scan_surroundings")
	var by_id := {}
	for f in scan["features"]:
		by_id[f["feature_id"]] = f
	check(by_id.has("#1113") and by_id["#1113"]["on_screen"], "the Grand Inversion Sphere is on screen")
	check(by_id.has("#2312") and by_id["#2312"]["path_clear"] and by_id["#2312"]["bearing_deg"] < 0, "#2312 is clear and to the left")
	check(cc.hud.overlay.highlights.has("2312"), "a scan highlights what it found")
	var hl := await _call("highlight", {"target": "#4096", "label": "LOOK"})
	check(hl["ok"] and cc.hud.overlay.highlights["4096"]["label"] == "LOOK", "highlight brackets a feature")
	check((await _call("highlight", {"target": "diagnostics_log"}))["ok"], "highlight flashes a HUD panel")
	check(not (await _call("highlight", {"target": "#0042"}))["ok"], "an unknown target is refused")
	await _call("post_to_log", {"message": "Identified Mandelbrought characteristic #2312, drawing attention and configuring flight path."})
	check_eq(cc.issues.entries[-1]["style"], "agent", "post_to_log writes an AGENT line")
	check((await _call("set_visual_filter", {"palette": "Gold"}))["ok"], "set_visual_filter goes through the adapter")
	game._resolve_once()
	check_eq(game.params.color_mode, 14, "and reaches the game's shape table")
	await _call("set_visual_filter", {"palette": "Ice Fractal"})
	game._resolve_once()
	var h0: float = rad_to_deg(atan2(game.camera.forward().y, game.camera.forward().x))
	check((await _call("turn_ship", {"yaw_degrees": 90}))["ok"], "turn_ship")
	_run_ship()
	var h1: float = rad_to_deg(atan2(game.camera.forward().y, game.camera.forward().x))
	check_approx(wrapf(h1 - h0, -180.0, 180.0), -90.0, "a right turn is clockwise from above", 1.0)
	await _call("turn_ship", {"yaw_degrees": -90})
	_run_ship()
	var th := await _call("thrust", {"direction": "forward", "meters": 2000})
	check(th["ok"] and th["obstructed"] and th["moving_m"] > 100, "a long thrust at the sphere stops short (%d m)" % th["moving_m"])
	_run_ship()
	cc.adapter.set_pose(Vector3(1.5, 0, 0), Vector3(0.8781, 0, 0))
	var bad: Dictionary = await bridge.handle("ship_tool", {"name": "warp_drive", "arguments": {}})
	check(bad.has("error"), "an unknown ship tool is a bridge error")


func _custom_tools() -> void:
	var cursor: int = (await bridge.handle("ship_events", {}))["last_id"]
	var got := [{}]
	cc.register_tool("open_airlock", "Open the airlock (a game-provided tool).",
		{"type": "object", "properties": {"which": {"type": "string"}}, "required": ["which"]},
		func(args: Dictionary) -> Dictionary:
			got[0] = args
			return {"ok": true, "message": "Airlock %s open." % args.get("which", "?")})
	var names: Array = (await bridge.handle("ship_tools", {}))["tools"].map(func(t): return t["name"])
	check(names.has("open_airlock"), "a game-registered tool appears in ship_tools")
	var evs: Array = (await bridge.handle("ship_events", {"after": cursor, "timeout": 0}))["events"]
	check(evs.any(func(e): return e["kind"] == "tools_changed" and not e["notify_agent"]), "and the phone server is told the list changed")
	var r := await _call("open_airlock", {"which": "B"})
	check(r["ok"] and r["message"] == "Airlock B open." and got[0].get("which") == "B", "ship_tool runs the game's handler")
	cc.unregister_tool("open_airlock")
	names = (await bridge.handle("ship_tools", {}))["tools"].map(func(t): return t["name"])
	check(not names.has("open_airlock"), "unregister_tool removes it")


func _call_and_chat() -> void:
	var st: Dictionary = await bridge.handle("call_center", {"support_number": "+1 (555) 010-9001", "link_up": true})
	check(st["link_up"], "call_center: the link is up")
	cc.hud._refresh_call()
	check(cc.hud.call_status.text.contains("555"), "the support panel shows the number to call")
	var states: Array = []
	cc.call_state_changed.connect(func(s: String, _i: Dictionary): states.append(s))
	var listeners: int = bridge.chat.listeners
	await bridge.handle("call_center", {"call_state": "connected", "agent_name": "Gary"})
	check(states == ["connected"] and cc.hud.call_state() == "connected", "call_center connected reaches the HUD and the game")
	check_eq(bridge.chat.listeners, listeners + 1, "on a call the pilot chat shows an agent listening")
	await bridge.handle("call_center", {"call_state": "connected", "agent_name": "Gary"})
	check_eq(bridge.chat.listeners, listeners + 1, "…once, however often the call reports in")
	await bridge.handle("call_center", {"link_up": false})
	check_eq(bridge.chat.listeners, listeners, "not while the link is down")
	await bridge.handle("call_center", {"link_up": true})
	check_eq(bridge.chat.listeners, listeners + 1, "and again once it is back")
	cc.hud._refresh_call()
	check(cc.hud.call_status.text.contains("Gary"), "the support panel says who is on the line")
	check(cc.issues.agent_available, "pilot issues wait longer with an agent on the line")
	cc.hud.clear_highlights()
	var said: Array = []
	cc.agent_said.connect(func(t: String): said.append(t))
	await bridge.handle("chat_say", {"text": "Right, see the Lipschitz Narrows? That's #8128's neighbour.", "source": "phone"})
	check(cc.hud.overlay.highlights.has("7071") and cc.hud.overlay.highlights.has("8128"), "names and ids in the agent's chat lines are highlighted")
	check(said.size() == 1, "agent_said fires")
	var last: Dictionary = bridge.chat.messages[-1]
	check(last["role"] == "agent" and last["source"] == "phone", "chat_say keeps the phone source for the panel's label")


func _fly_the_route_and_escape() -> void:
	var refused := await _call("fly_to_feature", {"feature_id": "#9001"})
	check(not refused["ok"] and refused.get("suggested_waypoint") == "#2312", "no shortcut to the exit; it suggests #2312")
	var cursor: int = (await bridge.handle("ship_events", {}))["last_id"]
	for id in ["#2312", "#4096", "#7071", "#8128"]:
		var r := await _call("fly_to_feature", {"feature_id": id})
		check(r["ok"], "autopilot to %s (%s)" % [id, r["message"]])
		_run_ship()
		cc._check_positions()
		cc.get_node("DemoMission")._process(0.0)
		check(cc.features.visited.has(id.trim_prefix("#")), "%s reached" % id)
	var evs: Array = (await bridge.handle("ship_events", {"after": cursor, "timeout": 0}))["events"]
	check(evs.filter(func(e): return e["kind"] == "waypoint_reached" and e["notify_agent"]).size() == 4, "each waypoint is an event for the agent")
	check(evs.any(func(e): return e["kind"] == "pilot_input_required" and e["blocks_exit"]), "so is the exit-blocking waiver")
	var demo: Node = cc.get_node("DemoMission")
	check(demo.waiver_id == "#99812" and cc.exit_lock_reason != "", "near the exit the demo raises the waiver and locks the exit")
	var hold := await _call("fly_to_feature", {"feature_id": "#9001"})
	check(hold["ok"] and hold["message"].contains("locked"), "the autopilot holds short of a locked exit")
	_run_ship()
	cc._check_positions()
	check(not demo.escaped, "no escape while locked")
	var res := await _call("resolve_issue", {"issue_id": "99812", "answer": "Ada Lovelace"})
	check(res["ok"] and res["message"].contains("Ada Lovelace"), "the waiver takes the pilot's answer")
	check(cc.exit_lock_reason == "", "and unlocks the exit")
	check((await _call("fly_to_feature", {"feature_id": "#9001"}))["ok"], "now the autopilot flies into the exit")
	_run_ship()
	cc._check_positions()
	check(demo.escaped, "the demo escapes at the unlocked exit")
	check(cc.hud.banner.visible, "with a banner")
	check(not cc.hud.is_panel_visible("diagnostics_log") and cc.hud.is_panel_visible("call_panel"),
		"the banner moves the log aside but keeps the support panel")
	evs = (await bridge.handle("ship_events", {"after": cursor, "timeout": 0}))["events"]
	check(evs.any(func(e): return e["kind"] == "escaped" and e["notify_agent"]), "and tells the agent")
	var listeners: int = bridge.chat.listeners
	await bridge.handle("call_center", {"call_state": "ended"})
	check_eq(bridge.chat.listeners, listeners - 1, "hanging up frees the pilot chat's listener")


func _detaches() -> void:
	var detached := [false]
	cc.game_detached.connect(func(): detached[0] = true)
	current_scene = null
	game.queue_free()
	await frames(3)
	check(detached[0] and cc.adapter == null, "leaving the game detaches the call centre")
	check(not cc.hud.visible, "and hides its HUD")
	var s := await _call("get_ship_status")
	check(s["ok"] and not s["in_flight"], "the tools still answer: no flight in progress")
	check(not (await _call("thrust", {"direction": "forward", "meters": 10}))["ok"], "and refuse to fly")


# ------------------------------------------------------------- helpers

func _call(tool_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary = await bridge.handle("ship_tool", {"name": tool_name, "arguments": args})
	if r.has("error"):
		return {"ok": false, "message": r["error"]}
	return r


func _run_ship() -> void:
	for i in 2000:
		if not cc.adapter.autopilot_state()["active"]:
			return
		cc.adapter.step(1.0 / 60.0)
