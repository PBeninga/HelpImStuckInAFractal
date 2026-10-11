extends "res://call_center/tests/test_case.gd"
## The call centre attached to the unmodified game: it finds the game scene by
## itself, drives the ship only through the adapter, serves the ship's tools
## over MCP JSON-RPC (including ones the game registers at runtime), plays the
## crash report, follows the call (state, transcript, auto-highlights), and in
## demo mode flies the sample route to a locked exit, unlocks it with the
## pilot's answer and escapes. Leaving the game detaches it cleanly.
##
## The game scene is used untyped (main.gd names the Settings autoload, which a
## `-s` script cannot see when it is compiled).

const CallCenter := preload("res://call_center/call_center.gd")
const ExplorerAdapter := preload("res://call_center/adapter/explorer_adapter.gd")

var cc: CallCenter
var game: Node
var _rpc_id := 100


func run() -> void:
	game = load("res://src/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	cc = CallCenter.new()
	cc.name = "CallCenter"
	cc.link_enabled = false
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
	_begin_and_crash_report()
	_mcp_basics()
	_custom_tools()
	_call_and_transcript()
	_fly_the_route_and_escape()
	await _detaches()
	cc.queue_free()
	await frames(2)


func _attaches() -> void:
	check(cc.adapter is ExplorerAdapter, "the call centre found the game scene and picked the explorer adapter")
	var eye: Vector3 = cc.adapter.pose()["position"]
	check(eye.is_equal_approx(Vector3(1.5, 0, 0)), "the demo placed the ship at the sample start")
	check(cc.hud.visible, "the HUD shows over the game")
	check(not cc.hud.is_panel_visible("diagnostics_log"), "panels wait for begin()")
	check(cc.features.find("#2312").size() > 0 and cc.features.exit_id == "9001", "the demo registered the sample route")


func _begin_and_crash_report() -> void:
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
	check(_sent("ship/event").any(func(m): return m["params"]["kind"] == "stage" and m["params"].get("stage") == "awaiting_call"),
		"the relay hears the ship is waiting for a call")


func _mcp_basics() -> void:
	var init := _rpc("initialize", {"protocolVersion": "2025-06-18"})
	check_eq(init["result"]["capabilities"]["tools"]["listChanged"], true, "the MCP server announces list changes")
	var names := _tool_names()
	for n in ["get_ship_status", "scan_surroundings", "highlight", "turn_ship", "thrust", "fly_to_feature", "resolve_issue", "post_to_log", "set_visual_filter"]:
		check(names.has(n), "tools/list has %s" % n)
	var s := _call("get_ship_status")
	check(s["ok"] and s["in_flight"], "status: in flight")
	check_eq(s["next_waypoint"]["feature_id"], "#2312", "next waypoint #2312")
	check(s["clearance_m"] >= 70, "clearance in metres (%d)" % s["clearance_m"])
	check(not s["exit"]["path_clear"], "no straight path to the exit from the start")
	check(s["world"].get("type") == "Mandelbox", "world facts for the babble")
	var scan := _call("scan_surroundings")
	var by_id := {}
	for f in scan["features"]:
		by_id[f["feature_id"]] = f
	check(by_id.has("#1113") and by_id["#1113"]["on_screen"], "the Grand Inversion Sphere is on screen")
	check(by_id.has("#2312") and by_id["#2312"]["path_clear"] and by_id["#2312"]["bearing_deg"] < 0, "#2312 is clear and to the left")
	check(cc.hud.overlay.highlights.has("2312"), "a scan highlights what it found")
	check(_call("highlight", {"target": "#4096", "label": "LOOK"})["ok"] and cc.hud.overlay.highlights["4096"]["label"] == "LOOK", "highlight brackets a feature")
	check(_call("highlight", {"target": "diagnostics_log"})["ok"], "highlight flashes a HUD panel")
	check(not _call("highlight", {"target": "#0042"})["ok"], "an unknown target is refused")
	_call("post_to_log", {"message": "Identified Mandelbrought characteristic #2312, drawing attention and configuring flight path."})
	check_eq(cc.issues.entries[-1]["style"], "agent", "post_to_log writes an AGENT line")
	check(_call("set_visual_filter", {"palette": "Gold"})["ok"], "set_visual_filter goes through the adapter")
	game._resolve_once()
	check_eq(game.params.color_mode, 14, "and reaches the game's shape table")
	_call("set_visual_filter", {"palette": "Ice Fractal"})
	game._resolve_once()
	var t := _call("turn_ship", {"yaw_degrees": 90})
	check(t["ok"], "turn_ship")
	var h0: float = rad_to_deg(atan2(game.camera.forward().y, game.camera.forward().x))
	_run_ship()
	var h1: float = rad_to_deg(atan2(game.camera.forward().y, game.camera.forward().x))
	check_approx(wrapf(h1 - h0, -180.0, 180.0), -90.0, "a right turn is clockwise from above", 1.0)
	_call("turn_ship", {"yaw_degrees": -90})
	_run_ship()
	var th := _call("thrust", {"direction": "forward", "meters": 2000})
	check(th["ok"] and th["obstructed"] and th["moving_m"] > 100, "a long thrust at the sphere stops short (%d m)" % th["moving_m"])
	_run_ship()
	cc.adapter.set_pose(Vector3(1.5, 0, 0), Vector3(0.8781, 0, 0))
	check_eq(_rpc("tools/call", {"name": "warp_drive", "arguments": {}})["error"]["code"], -32602, "an unknown tool is invalid params")
	check_eq(_rpc("resources/list", {})["error"]["code"], -32601, "an unknown method is method-not-found")


func _custom_tools() -> void:
	cc.link.outbox.clear()
	var got := [{}]
	cc.register_tool("open_airlock", "Open the airlock (a game-provided tool).",
		{"type": "object", "properties": {"which": {"type": "string"}}, "required": ["which"]},
		func(args: Dictionary) -> Dictionary:
			got[0] = args
			return {"ok": true, "message": "Airlock %s open." % args.get("which", "?")})
	check(_tool_names().has("open_airlock"), "a game-registered tool appears in tools/list")
	check(_sent("notifications/tools/list_changed").size() == 1, "and the relay is told the list changed")
	var r := _call("open_airlock", {"which": "B"})
	check(r["ok"] and r["message"] == "Airlock B open." and got[0].get("which") == "B", "tools/call runs the game's handler")
	cc.unregister_tool("open_airlock")
	check(not _tool_names().has("open_airlock"), "unregister_tool removes it")


func _call_and_transcript() -> void:
	cc.link.handle_message('{"jsonrpc":"2.0","method":"ship/config","params":{"support_number":"+1 (555) 010-9001"}}')
	cc.hud.set_link_state(true)
	cc.hud._refresh_call()
	check(cc.hud.call_status.text.contains("555"), "ship/config puts the number on the call panel")
	var states: Array = []
	cc.call_state_changed.connect(func(s: String, _i: Dictionary): states.append(s))
	cc.link.handle_message('{"jsonrpc":"2.0","method":"ship/call","params":{"state":"connected","agent_name":"Gary"}}')
	check(states == ["connected"] and cc.hud.call_state() == "connected", "ship/call connected reaches the HUD and the game")
	check(cc.issues.agent_available, "pilot issues wait longer with an agent on the line")
	cc.hud.clear_highlights()
	cc.link.handle_message(JSON.stringify({"jsonrpc": "2.0", "method": "ship/transcript", "params": {
		"role": "agent", "item_id": "i1", "text": "Right, see the Lipschitz Narrows? That's characteristic #8128's neighbour.", "final": true}}))
	check(cc.hud.overlay.highlights.has("7071") and cc.hud.overlay.highlights.has("8128"), "names and ids in the agent's speech are highlighted")
	check(cc.hud.transcript_label.text.contains("Lipschitz"), "the transcript shows on the HUD")


func _fly_the_route_and_escape() -> void:
	var refused := _call("fly_to_feature", {"feature_id": "#9001"})
	check(not refused["ok"] and refused.get("suggested_waypoint") == "#2312", "no shortcut to the exit; it suggests #2312")
	for id in ["#2312", "#4096", "#7071", "#8128"]:
		var r := _call("fly_to_feature", {"feature_id": id})
		check(r["ok"], "autopilot to %s (%s)" % [id, r["message"]])
		_run_ship()
		cc._check_positions()
		cc.get_node("DemoMission")._process(0.0)
		check(cc.features.visited.has(id.trim_prefix("#")), "%s reached" % id)
	check(_sent("ship/event").any(func(m): return m["params"]["kind"] == "waypoint_reached" and m["params"]["notify_agent"]),
		"waypoints are reported to the agent")
	var demo: Node = cc.get_node("DemoMission")
	check(demo.waiver_id == "#99812" and cc.exit_lock_reason != "", "near the exit the demo raises the waiver and locks the exit")
	var hold := _call("fly_to_feature", {"feature_id": "#9001"})
	check(hold["ok"] and hold["message"].contains("locked"), "the autopilot holds short of a locked exit")
	_run_ship()
	cc._check_positions()
	check(not demo.escaped, "no escape while locked")
	var res := _call("resolve_issue", {"issue_id": "99812", "answer": "Ada Lovelace"})
	check(res["ok"] and res["message"].contains("Ada Lovelace"), "the waiver takes the pilot's answer")
	check(cc.exit_lock_reason == "", "and unlocks the exit")
	check(_call("fly_to_feature", {"feature_id": "#9001"})["ok"], "now the autopilot flies into the exit")
	_run_ship()
	cc._check_positions()
	check(demo.escaped, "the demo escapes at the unlocked exit")
	check(cc.hud.banner.visible, "with a banner")
	check(not cc.hud.is_panel_visible("diagnostics_log") and cc.hud.is_panel_visible("call_panel"),
		"the banner moves the log aside but keeps the call panel")
	check(_sent("ship/event").any(func(m): return m["params"]["kind"] == "escaped" and m["params"]["notify_agent"]), "and tells the agent")


func _detaches() -> void:
	var detached := [false]
	cc.game_detached.connect(func(): detached[0] = true)
	current_scene = null
	game.queue_free()
	await frames(3)
	check(detached[0] and cc.adapter == null, "leaving the game detaches the call centre")
	check(not cc.hud.visible, "and hides its HUD")
	var s := _call("get_ship_status")
	check(s["ok"] and not s["in_flight"], "the tools still answer: no flight in progress")
	check(not _call("thrust", {"direction": "forward", "meters": 10})["ok"], "and refuse to fly")


# ------------------------------------------------------------- helpers

func _rpc(method: String, params: Dictionary) -> Dictionary:
	_rpc_id += 1
	return cc.link.handle_message(JSON.stringify({"jsonrpc": "2.0", "id": _rpc_id, "method": method, "params": params}))


func _call(tool_name: String, args: Dictionary = {}) -> Dictionary:
	var r := _rpc("tools/call", {"name": tool_name, "arguments": args})
	if r.has("error"):
		return {"ok": false, "message": r["error"]["message"]}
	return JSON.parse_string(r["result"]["content"][0]["text"])


func _tool_names() -> Array:
	return _rpc("tools/list", {})["result"]["tools"].map(func(t): return t["name"])


func _sent(method: String) -> Array:
	return cc.link.outbox.filter(func(m): return m.get("method") == method)


func _run_ship() -> void:
	for i in 2000:
		if not cc.adapter.autopilot_state()["active"]:
			return
		cc.adapter.step(1.0 / 60.0)
