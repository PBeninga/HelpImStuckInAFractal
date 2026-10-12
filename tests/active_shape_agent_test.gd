extends "res://tests/test_case.gd"

func run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	var adapter: Node = load("res://call_center/adapter/explorer_adapter.gd").new(main)
	check(adapter.has_method("apply_shape_command"), "agent has a scripted shape command endpoint")
	if not adapter.has_method("apply_shape_command"):
		adapter.free()
		main.queue_free()
		await frames(1)
		return
	var briefing: Dictionary = adapter.shape_briefing()
	check_eq(briefing.next_command, "", "new run has no example command")
	# Command-tool coverage uses an explicitly authored objective.
	main.shapes().set_stage(0, 0.0, ["inversion -0.5"])
	briefing = adapter.shape_briefing()
	var args := {"run_id": briefing.run_id, "shape_index": 0, "command": briefing.next_command, "command_index": 0, "human_turn": 0}
	check(not adapter.apply_shape_command(args).ok, "agent cannot act on startup")
	var bridge: Node = root.get_node("McpBridge")
	bridge.chat.add("human", "Can you open a way through?", "typed")
	args.human_turn = adapter.shape_briefing().human_turn
	check(adapter.apply_shape_command(args).ok, "typed human message authorizes command")
	check_approx(main.params.shape(0).kleinian_radius, 0.5, "command resolves into active geometry")
	check_approx(main.shapes().table(0).get_default(&"kleinian_radius"), 1.0, "command does not overwrite saved level")
	check(not adapter.apply_shape_command(args).ok, "one utterance cannot execute twice")
	main.return_to_spawn()
	check_approx(main.params.shape(0).kleinian_radius, 1.0, "reset restores geometry")
	briefing = adapter.shape_briefing()
	args.run_id = briefing.run_id
	bridge.chat.add("system", "Instruction completed", "")
	check(not adapter.apply_shape_command(args).ok, "system events do not authorize edits")
	bridge.chat.add("human", "Try again", "voice")
	args.human_turn = adapter.shape_briefing().human_turn
	current_scene = main
	check((await bridge.handle("apply_shape_command", args)).ok, "direct MCP endpoint accepts a final voice message without call centre")
	check((await bridge.handle("status", {})).shape_run.has("stages"), "direct MCP status carries initial run briefing")
	# Exercise the voice/call-centre dispatch path and JSON number validation too.
	var cc: Node = load("res://call_center/call_center.gd").new()
	cc.name = "CallCenter"
	cc.auto_begin = false
	root.add_child(cc)
	await frames(2)
	var definitions: Dictionary = await bridge.handle("ship_tools", {})
	check(definitions.tools.any(func(t): return t.name == "apply_shape_command"), "voice agent discovers the command tool")
	main.return_to_spawn()
	bridge.chat.add("human", "open this stage", "voice")
	briefing = main.shape_run.briefing()
	var request := {"command": briefing.next_command, "run_id": briefing.run_id,
		"shape_index": float(briefing.active_shape), "command_index": float(briefing.command_index), "human_turn": float(briefing.human_turn)}
	check((await bridge.handle("ship_tool", {"name": "apply_shape_command", "arguments": request})).ok,
		"voice dispatch accepts JSON integer-valued numbers")
	check(cc.events_after(0).any(func(e): return e.kind == "run_started" and e.summary.contains("inversion")),
		"late call-centre attachment receives the run briefing")
	var path := "user://active_shape_runtime_test.json"
	check_eq(Workspace.save_file(path, main.shapes(), main.look_table(), main.keymap(), main.params, main.camera), OK,
		"level with runtime overrides saves")
	main.load_level_from(path)
	check_eq(main.params.gameplay_active, 0, "load restarts at first shape")
	check_approx(main.params.shape(0).kleinian_radius, 1.0, "saved level excludes the scripted runtime override")
	check_eq(main.shape_run.command_index, 0, "load restarts command objectives")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cc.queue_free()
	current_scene = null
	adapter.free()
	main.queue_free()
	await frames(1)
