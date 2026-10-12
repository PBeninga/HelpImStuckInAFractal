extends "res://tests/test_case.gd"
const CallCenter := preload("res://call_center/call_center.gd")
var bridge: Node

func tool(name: String, args: Dictionary = {}) -> Dictionary:
	return await bridge.handle("ship_tool", {"name": name, "arguments": args})

func run() -> void:
	await frames(1)
	bridge = root.get_node("McpBridge")
	var game: Node = load("res://src/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var cc := CallCenter.new()
	cc.name = "CallCenter"
	cc.auto_begin = false
	root.add_child(cc)
	await frames(3)
	var definitions: Dictionary = await bridge.handle("ship_tools", {})
	for name in ["get_console_controls", "set_console_controls", "console_action"]:
		check(definitions.tools.any(func(t): return t.name == name), "voice discovers " + name)
	var action_tool: Dictionary = definitions.tools.filter(func(t): return t.name == "console_action")[0]
	check(action_tool.inputSchema.properties.action.enum.has("find_nearest_surface"),
		"the agent discovers surface recovery in the MCP schema")
	var eye: PackedFloat64Array = game.camera.eye64()
	game.camera.set_basis(CameraState.facing_basis(-game.camera.forward()))
	await tool("turn_ship", {"yaw_degrees": 90})
	var recovery := await tool("console_action", {"action": "find_nearest_surface"})
	check(recovery.get("ok", false) and game.view.center_ray().hit(), "the support agent points the player at a real surface")
	check_eq(game.camera.eye64(), eye, "the support agent recovery keeps position")
	check(not cc.adapter.autopilot_state().active, "recovery cancels a turn that would overwrite its heading")
	game.params.render_escape_radius = 0.000001
	game.shapes().table(0).set_default(&"pos_x", 100.0)
	recovery = await tool("console_action", {"action": "find_nearest_surface"})
	check(recovery.get("ok") == false, "the support agent receives failure when no surface is found")
	game.params.render_escape_radius = 20.0
	game.shapes().table(0).set_default(&"pos_x", 0.0)
	for section in ["overview", "shape", "look", "view", "gameplay", "axes", "noise"]:
		var info := await tool("get_console_controls", {"section": section})
		check(info.get("ok", false), "inspect " + section)
		check(JSON.parse_string(JSON.stringify(info)) is Dictionary, section + " is JSON serializable")
	var res := await tool("console_action", {"action": "add_shape"})
	check(res.ok and game.shapes().count() == 2, "agent can add shapes")
	res = await tool("console_action", {"action": "rename_shape", "shape_index": 1, "name": "Agent shape"})
	check_eq(game.shapes().label(1), "Agent shape", "agent can rename shapes")
	var first: Variant = game.shapes().table(0).get_default(&"box_scale")
	res = await tool("set_console_controls", {"section": "shape", "shape_index": 1, "values": {"defaults": {"box_scale": -1.7}, "bindings": {"box_scale": {"source": "time", "gain": 0.1}}}})
	check(res.ok, "agent can edit indexed shape and binding")
	check_eq(game.shapes().table(0).get_default(&"box_scale"), first, "other shape unchanged")
	check_eq(game.shapes().table(1).binding(&"box_scale").source, &"time", "binding reaches console model")
	res = await tool("set_console_controls", {"section": "look", "values": {"defaults": {"palette_a_r": 0.25}}})
	check_eq(game.look_table().get_default(&"palette_a_r"), 0.25, "palette reaches shared look model")
	res = await tool("set_console_controls", {"section": "view", "values": {"detail": 1.5, "camera_mode": "orbit"}})
	check(res.ok and game.params.camera_mode == 1, "agent edits renderer and camera mode")
	res = await tool("set_console_controls", {"section": "view", "values": {"camera_mode": "fly"}})
	var spawn: float = game.params.gameplay.spawn_x
	res = await tool("set_console_controls", {"section": "gameplay", "values": {"move_speed": 3.0}})
	check_eq(game.params.gameplay.move_speed, 3.0, "agent edits gameplay")
	check_eq(game.params.gameplay.spawn_x, spawn, "partial gameplay edit preserves spawn")
	res = await tool("set_console_controls", {"section": "axes", "values": {"entries": [{"id": "agent", "label": "Agent axis", "speed": 2.0, "positive": "E", "negative": "Q", "value": 4.0}]}})
	check(res.ok and game.keymap().axes().has(&"agent"), "agent adds and rebinds axes")
	var graph: Dictionary = game.noise_window().to_dict()
	graph.nodes.append({"id": "constant_0", "type": "constant", "position": [200, 100], "params": {"value": 0.4}})
	res = await tool("set_console_controls", {"section": "noise", "values": graph})
	check(res.ok and game.noise_window().graph().node(&"constant_0") != null, "agent adds a noise node")
	res = await tool("set_console_controls", {"section": "shape", "shape_index": -1, "values": {"defaults": {}}})
	check(not res.ok, "invalid shape rejected")
	res = await tool("set_console_controls", {"section": "view", "values": {"script": "bad"}})
	check(not res.ok, "arbitrary properties rejected")
	res = await tool("set_console_controls", {"section": "noise", "values": {}})
	check(not res.ok, "malformed noise edit rejected")
	res = await tool("console_action", {"action": "pause"})
	check(paused, "agent can pause")
	res = await tool("console_action", {"action": "resume"})
	check(not paused, "agent can resume while paused")
	for action in ["return_to_spawn", "reset_renderer", "reset_palette", "reset_axes", "list_levels"]:
		res = await tool("console_action", {"action": action})
		check(res.ok, "action " + action)
	res = await tool("console_action", {"action": "remove_shape", "shape_index": 1})
	check(res.ok and game.shapes().count() == 1, "agent removes shape")
	cc.begin()
	cc.issues.advance(60.0)
	cc._process(10000.0)
	check(cc.issues.pending().is_empty(), "no automatic pilot questions")
	res = await tool("console_action", {"action": "back_to_menu"})
	await frames(4)
	check(not (await bridge.handle("status", {})).in_game, "agent returns to menu")
	res = await tool("console_action", {"action": "start_game"})
	await frames(5)
	check((await bridge.handle("status", {})).in_game, "agent starts the game from menu")
	cc.queue_free()
	if current_scene != null:
		current_scene.queue_free()
	current_scene = null
	await frames(2)
