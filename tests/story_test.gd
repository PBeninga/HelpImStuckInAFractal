extends "res://tests/test_case.gd"
## Story mode, headless: the intro lands the ship and plays the crash report;
## the ship's tools (as the support agent calls them, and through the MCP
## JSON-RPC layer) scan, highlight, turn, thrust and fly the whole route; the
## rift holds the ship until the egress waiver is answered, then lets it out.
##
## The story scene is used untyped: it instances main.tscn, whose script names
## the Settings autoload (see main_test.gd).

var story: Node
var tools: ShipTools


func run() -> void:
	story = load("res://src/story/story.tscn").instantiate()
	story.autostart = false
	root.add_child(story)
	await frames(2)
	tools = story.tools
	# the tests step the ship, mission and log by hand
	story.ship.set_physics_process(false)
	story.mission.set_physics_process(false)
	story.issue_log.set_process(false)
	story.link.enabled = false

	_start_state()
	await _intro()
	_status_and_scan()
	_highlight_and_log()
	await _turn_and_thrust()
	_manual_override()
	_fly_the_route()
	_mcp_layer()
	_transcript_highlights()

	story.queue_free()
	await frames(2)


func _start_state() -> void:
	var cam: CameraState = story.main.camera
	check(cam.eye().is_equal_approx(Route.START_EYE), "the ship starts in the chamber behind the great port")
	check(story.main.view.rift()["on"], "the view draws the exit rift")
	check(story.main.fly.input_locked, "flying is locked until the intro ends")
	check_eq(story.mission.stage, Mission.Stage.INTRO, "the mission starts in INTRO")
	var r := tools.call_tool("fly_to_feature", {"feature_id": "#2312"})
	check(not r["ok"], "the autopilot refuses during the intro")


func _intro() -> void:
	var intro: StoryIntro = story.intro
	intro.start()
	intro.advance(StoryIntro.WARP_END + 0.1)
	check(story.mission.stage == Mission.Stage.INTRO, "still in the intro during the warp")
	intro.skip()
	intro.advance(0.05)
	check_eq(story.mission.stage, Mission.Stage.STRANDED, "skipping lands the ship: STRANDED")
	check(story.hud.overlay.show_exit, "the HUD shows the exit marker after landing")
	check(story.issue_log.is_scripting(), "the crash report starts")
	for i in 40:
		story.issue_log.advance(0.5)
	var texts: Array = []
	for e in story.issue_log.entries:
		texts.append(e["text"])
	var joined := "\n".join(texts)
	check(joined.contains("punch jump not completed successfully"), "the crash report opens with the failed jump")
	check(joined.contains("animalifolds instead of manifolds"), "the animalifolds error is in the log")
	check(joined.contains("forced evfoldlution"), "and its fix")
	check(joined.contains("Stuck in fractal space"), "Error #33423 Stuck in fractal space")
	check(joined.contains("connecting to agent"), "and the hand-off to an agent")
	check(story.issue_log.auto_running, "after the script, issues stream in on their own")
	var before: int = story.issue_log.entries.size()
	for i in 30:
		story.issue_log.advance(1.0)
	check(story.issue_log.entries.size() > before + 3, "auto issues keep arriving (%d new)" % (story.issue_log.entries.size() - before))
	intro.advance(StoryIntro.GLITCH_END)
	check(not intro.running, "the intro finishes")
	check(not story.main.fly.input_locked, "and unlocks the controls")


func _status_and_scan() -> void:
	var s := tools.call_tool("get_ship_status", {})
	check(s["ok"], "get_ship_status ok")
	check_eq(s["stage"], "stranded", "status stage")
	check_eq(s["next_waypoint"]["feature_id"], "#2312", "the next waypoint is #2312")
	check(s["clearance_m"] >= 70, "clearance in metres (%d)" % s["clearance_m"])
	check(not s["exit"]["path_clear"], "the rift is not directly reachable from the start")
	check(s["fractal"]["scale"] < -2.0, "status carries the fractal parameters")
	var sc := tools.call_tool("scan_surroundings", {})
	check(sc["ok"] and sc["features"].size() >= 4, "a scan finds characteristics (%d)" % sc["features"].size())
	var by_id := {}
	for f in sc["features"]:
		by_id[f["feature_id"]] = f
	check(by_id.has("#1113") and by_id["#1113"]["on_screen"], "the Grand Inversion Sphere is on screen at the start")
	check(by_id.has("#2312") and by_id["#2312"]["path_clear"], "#2312 can be flown to")
	check(by_id["#2312"]["bearing_deg"] < 0, "#2312 is to the left (%d deg)" % by_id["#2312"]["bearing_deg"])
	check(sc["route_hint"].contains("#2312"), "the scan hints the way out")
	check(story.hud.overlay.highlights.has("2312"), "a scan highlights what it found")


func _highlight_and_log() -> void:
	story.hud.clear_highlights()
	var h := tools.call_tool("highlight", {"target": "#4096", "label": "LOOK HERE"})
	check(h["ok"] and story.hud.overlay.highlights.has("4096"), "highlight brackets a characteristic")
	check_eq(story.hud.overlay.highlights["4096"]["label"], "LOOK HERE", "with the caption")
	var p := tools.call_tool("highlight", {"target": "diagnostics_log"})
	check(p["ok"], "highlight can flash a HUD panel")
	check(not tools.call_tool("highlight", {"target": "#0042"})["ok"], "an unknown target is refused")
	var n: int = story.issue_log.entries.size()
	tools.call_tool("post_to_log", {"message": "Identified Mandelbrought characteristic #2312, drawing attention and configuring flight path."})
	check_eq(story.issue_log.entries[-1]["style"], "agent", "post_to_log writes an agent line")
	check(story.issue_log.entries.size() == n + 1, "exactly one line")
	var v := tools.call_tool("set_visual_filter", {"palette": "Gold"})
	check(v["ok"], "set_visual_filter accepts a palette name")
	story.main._resolve_once()
	check_eq(story.main.params.color_mode, 14, "Gold is colour mode 14, through the shape table")
	tools.call_tool("set_visual_filter", {"palette": "Ice Fractal"})
	story.main._resolve_once()
	check(not tools.call_tool("resolve_issue", {"issue_id": "#1", "answer": "x"})["ok"], "resolving a non-issue fails")
	check(not tools.call_tool("no_such_tool", {})["ok"], "an unknown tool fails cleanly")


func _turn_and_thrust() -> void:
	var cam: CameraState = story.main.camera
	var ship: ShipController = story.ship
	var h0 := rad_to_deg(atan2(cam.forward().y, cam.forward().x))
	var r := tools.call_tool("turn_ship", {"yaw_degrees": 90})
	check(r["ok"], "turn_ship ok")
	_run_ship()
	var h1 := rad_to_deg(atan2(cam.forward().y, cam.forward().x))
	check_approx(wrapf(h1 - h0, -180.0, 180.0), -90.0, "a 90 degree right turn turns clockwise from above", 1.0)
	tools.call_tool("turn_ship", {"yaw_degrees": -90})
	_run_ship()
	var start := cam.eye()
	var t := tools.call_tool("thrust", {"direction": "forward", "meters": 2000})
	check(t["ok"] and t["obstructed"], "a long thrust at the sphere is stopped short")
	check(t["moving_m"] < 2000 and t["moving_m"] > 100, "it still moves most of the way (%d m)" % t["moving_m"])
	_run_ship()
	var d := DistanceEstimator.estimate(cam.eye(), story.main.params)
	check(d >= ShipController.SAFE_CLEARANCE * 0.5, "and stops clear of the surface (%.4f)" % d)
	cam.transform = Route.start_transform()
	check(cam.eye().is_equal_approx(start), "back at the start")
	await frames(1)


func _manual_override() -> void:
	var ship: ShipController = story.ship
	var overridden := [false]
	ship.manual_override.connect(func(): overridden[0] = true, CONNECT_ONE_SHOT)
	tools.call_tool("fly_to_feature", {"feature_id": "#2312"})
	ship.step(0.1)
	Input.action_press("move_forward")
	ship.step(0.1)
	Input.action_release("move_forward")
	check(overridden[0] and not ship.busy(), "pressing W cancels the autopilot (manual override)")
	story.main.camera.transform = Route.start_transform()


func _fly_the_route() -> void:
	var cam: CameraState = story.main.camera
	var mission: Mission = story.mission
	var direct := tools.call_tool("fly_to_feature", {"feature_id": "#9001"})
	check(not direct["ok"], "no straight flight from the start to the rift")
	check_eq(direct.get("suggested_waypoint"), "#2312", "and the refusal suggests #2312")
	for id in ["#2312", "#4096", "#7071", "#8128"]:
		var r := tools.call_tool("fly_to_feature", {"feature_id": id})
		check(r["ok"], "autopilot to %s accepted (%s)" % [id, r["message"]])
		_run_ship()
		mission.step(0.0)
		check(mission.visited.has(id.trim_prefix("#")), "%s reached and marked" % id)
	var waiver := mission.waiver_issue_id
	check(waiver == "#99812", "nearing the rift raises the egress waiver (%s)" % waiver)
	var open: Array = tools.call_tool("get_ship_status", {})["open_issues"]
	var found := false
	for o in open:
		if o["issue_id"] == waiver and o["blocks_exit"]:
			found = true
	check(found, "the waiver is an open issue that blocks the exit")
	var hold := tools.call_tool("fly_to_feature", {"feature_id": "#9001"})
	check(hold["ok"] and hold["message"].contains("waiver"), "the autopilot holds short of the rift while unsigned")
	_run_ship()
	mission.step(0.0)
	check(mission.stage != Mission.Stage.EGRESS, "no egress without the waiver")
	check_approx(cam.eye().distance_to(Route.RIFT_POS), Route.RIFT_HOLD, "holding at RIFT_HOLD", 0.002)
	var res := tools.call_tool("resolve_issue", {"issue_id": "99812", "answer": "Ada Lovelace"})
	check(res["ok"] and res["message"].contains("Ada Lovelace"), "the waiver takes the pilot's answer")
	check(mission.waiver_signed, "and is signed")
	var go := tools.call_tool("fly_to_feature", {"feature_id": "#9001"})
	check(go["ok"], "now the autopilot flies into the rift")
	_run_ship()
	mission.step(0.0)
	check_eq(mission.stage, Mission.Stage.EGRESS, "inside the signed rift: EGRESS")
	check(story.outro.running, "the outro runs")
	story._after_egress()
	check_eq(mission.stage, Mission.Stage.ESCAPED, "behind the outro's white-out: ESCAPED")
	check(not story.hud.is_panel_visible("diagnostics_log") and story.hud.is_panel_visible("call_panel"),
		"the end card hides the log but keeps the call panel")
	check(not story.main.view.rift()["on"], "the rift is gone from the view")
	check(not tools.call_tool("thrust", {"direction": "forward", "meters": 10})["ok"], "the ship can no longer be flown")


func _mcp_layer() -> void:
	var link: ShipLink = story.link
	var init: Dictionary = link.handle_message(JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "initialize",
		"params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}}))
	check_eq(init["id"], 1, "initialize answers with the request id")
	check_eq(init["result"]["protocolVersion"], "2025-06-18", "and the protocol version")
	check(init["result"]["capabilities"].has("tools"), "advertising tools")
	var listed: Dictionary = link.handle_message('{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
	var names: Array = []
	for t in listed["result"]["tools"]:
		names.append(t["name"])
		check(t.has("inputSchema") and t["inputSchema"]["type"] == "object", "tool %s has an object inputSchema" % t["name"])
	check(names.has("fly_to_feature") and names.has("resolve_issue") and names.has("highlight"), "tools/list has the ship's controls")
	var called: Dictionary = link.handle_message('{"jsonrpc":"2.0","id":"abc","method":"tools/call","params":{"name":"get_ship_status","arguments":{}}}')
	check_eq(called["id"], "abc", "string ids round-trip")
	var parsed: Variant = JSON.parse_string(called["result"]["content"][0]["text"])
	check(parsed is Dictionary and parsed["ok"], "tools/call returns the result as JSON text")
	check(not called["result"]["isError"], "isError false on success")
	var bad: Dictionary = link.handle_message('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"warp_drive","arguments":{}}}')
	check_eq(bad["error"]["code"], -32602, "an unknown tool is invalid params")
	var nomethod: Dictionary = link.handle_message('{"jsonrpc":"2.0","id":4,"method":"resources/list"}')
	check_eq(nomethod["error"]["code"], -32601, "an unknown method is method-not-found")
	var junk: Dictionary = link.handle_message("not json")
	check_eq(junk["error"]["code"], -32700, "junk is a parse error")
	check(link.handle_message('{"jsonrpc":"2.0","method":"notifications/initialized"}') == null, "notifications get no reply")
	link.handle_message('{"jsonrpc":"2.0","method":"ship/config","params":{"support_number":"+1 555 010 9001"}}')
	check(story.hud.call_status.text.contains("555") or not story.hud._link_up, "ship/config sets the support number")
	link.handle_message('{"jsonrpc":"2.0","method":"ship/call","params":{"state":"connected","agent_name":"Gary"}}')
	check_eq(story.hud.call_state(), "connected", "ship/call connected reaches the HUD")
	check(story.issue_log.agent_available, "with an agent on the line, pilot issues wait longer")


func _transcript_highlights() -> void:
	story.hud.clear_highlights()
	story.link.handle_message(JSON.stringify({"jsonrpc": "2.0", "method": "ship/transcript",
		"params": {"role": "agent", "item_id": "it1", "text": "Right, I've identified Mandelbrought characteristic #4096, the Box-Fold Bypass.", "final": false}}))
	check(story.hud.overlay.highlights.has("4096"), "an id in the agent's speech is highlighted automatically")
	check(story.hud.transcript_label.text.contains("characteristic"), "the transcript shows on the HUD")
	var m: Array = story.mentioned_features("Head for the Lipschitz Narrows, then 8128, not 12345")
	check(m.has("7071") and m.has("8128") and m.size() == 2, "names and bare ids are recognised (%s)" % [m])


## Run the current manoeuvre to completion in fixed steps.
func _run_ship() -> void:
	var ship: ShipController = story.ship
	for i in 2000:
		if not ship.busy():
			return
		ship.step(1.0 / 60.0)
