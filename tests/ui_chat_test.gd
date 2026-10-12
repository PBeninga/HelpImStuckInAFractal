extends "res://tests/test_case.gd"
## The pilot chat driven like a player, with the bridge's chat commands playing
## the agent: Enter focuses the input and silences WASD, typing and Enter posts
## a human message, chat_wait hands it to the agent and chat_say answers, the
## agent state line follows along, voice posts and drafts show up, Escape
## leaves the input without pausing, and a click on the log reaches the view.

var ui: UiDriver


func run() -> void:
	ui = UiDriver.new(self)
	await ui.setup()
	var bridge: Node = root.get_node("McpBridge")
	bridge.chat.clear()
	bridge.chat.agent_cursor = 0
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await ui.frames(3)

	# The console opens beside the main window at start; headless it is embedded
	# over the panel and holds the keyboard. Close it, as a player flying would.
	main.console().hide_console()
	main.get_window().grab_focus()
	await ui.frames(1)

	var chat: ChatPanel = main.chat()
	check(chat != null, "Main builds the pilot chat")
	check(chat._log == bridge.chat, "on the bridge's log, so it survives a scene change")
	var rect := ui.global_rect(chat)
	check_approx(rect.end.x, 1280.0 - ChatPanel.MARGIN, "it hugs the right edge", 1.0)
	check_approx(rect.size.x, ChatPanel.WIDTH, "at its fixed width", 1.0)
	check(rect.size.y > 700.0, "down the full height")
	check(chat._state.text.contains("no agent"), "with no agent listening yet")

	# Docked (fullscreen), the console takes the right-hand strip and the chat
	# moves beside it rather than under it.
	main.set_docked(true)
	await ui.frames(2)
	var dock := Rect2(main._dock_rect())
	check(ui.global_rect(chat).end.x <= dock.position.x, "docked, the chat sits left of the console")
	# Hidden first: headless the console is embedded and would take Enter (and
	# undocking an open console reopens it once the window settles).
	main.console().hide_console()
	main.set_docked(false)
	await ui.frames(2)
	check_approx(ui.global_rect(chat).end.x, 1280.0 - ChatPanel.MARGIN, "and undocked it hugs the edge again", 1.0)

	# Enter focuses; WASD falls silent while typing.
	await ui.tap(KEY_ENTER)
	check(chat.input.has_focus(), "Enter focuses the chat input")
	var eye: Vector3 = main.camera.eye()
	await ui.hold(KEY_W, 0.2)
	check(main.camera.eye() == eye, "W does not fly while typing")

	# Escape leaves the input without pausing.
	await ui.gui_key(KEY_ESCAPE, true)
	await ui.gui_key(KEY_ESCAPE, false)
	check(not chat.input.has_focus(), "Escape leaves the input")
	check(not get_root().get_tree().paused, "and does not pause")

	# Typing a request posts a human message.
	var before := chat.log_box.get_child_count()
	await ui.type_text(chat.input, "dive in")
	check(not chat.input.has_focus(), "Enter sends and leaves the input")
	check_eq(chat.input.text, "", "and clears it")
	await ui.frames(1)
	check_eq(chat.log_box.get_child_count(), before + 1, "the message appears in the log")
	var last: Dictionary = bridge.chat.messages[-1]
	check_eq([last["role"], last["text"], last["source"]], ["human", "dive in", "typed"],
		"as a typed human message")

	# The agent picks it up and answers.
	var r: Dictionary = await bridge.handle("chat_wait", {"timeout": 1.0})
	check_eq((r["messages"] as Array).size(), 1, "chat_wait hands the agent the new message")
	check_eq(r["messages"][0]["text"], "dive in", "with its text")
	check(chat._state.text.contains("working"), "the panel shows the agent working")
	r = await bridge.handle("chat_say", {"text": "Diving toward the centre."})
	check_eq(r.get("role"), "agent", "chat_say posts an agent message")
	await ui.frames(1)
	check_eq(chat.log_box.get_child_count(), before + 2, "which appears in the log")
	r = await bridge.handle("chat_say", {"text": "  "})
	check(r.has("error"), "an empty reply is refused")

	# Nothing new: the wait times out, and shows listening meanwhile.
	var waiting: Array = [null]
	var waiter := func(): waiting[0] = await bridge.handle("chat_wait", {"timeout": 0.3})
	waiter.call()
	await ui.frames(2)
	check(chat._state.text.contains("listening"), "a waiting agent shows as listening")
	await ui.wait(0.5)
	check(waiting[0] != null and waiting[0]["timed_out"], "a quiet wait times out")
	check(chat._state.text.contains("no agent"), "and the state falls back when it ends")

	# A message sent while the agent waits wakes it up.
	waiting[0] = null
	waiter = func(): waiting[0] = await bridge.handle("chat_wait", {"timeout": 5.0})
	waiter.call()
	await ui.frames(2)
	await ui.type_text(chat.input, "stop")
	await ui.frames(2)
	check(waiting[0] != null and waiting[0]["messages"][0]["text"] == "stop", "a waiting agent wakes on a new message")

	# Voice: a live draft fills the input, a post lands as a voice message.
	await bridge.handle("chat_draft", {"text": "turn le"})
	check_eq(chat.input.text, "turn le", "chat_draft shows the live transcript")
	r = await bridge.handle("chat_post", {"text": "turn left"})
	check_eq(r.get("source"), "voice", "chat_post is a voice message by default")
	check_eq(chat.input.text, "", "and clears the draft")
	await ui.frames(1)
	var bubble := chat.log_box.get_child(chat.log_box.get_child_count() - 1)
	var name_label: Label = bubble.get_child(0).get_child(0)
	check(name_label.text.contains("voice"), "the bubble is marked as voice")
	r = await bridge.handle("chat_history", {"limit": 2})
	check_eq((r["messages"] as Array).size(), 2, "chat_history returns the recent messages")

	# A click on the log (not the input) goes through to the view: in Fly mode
	# with the mouse free, it recaptures.
	main._free_requested = true
	main._update_mouse()
	check(not main.is_mouse_captured(), "the mouse is free")
	await ui.click_at(ui.global_point(chat, Vector2(0.5, 0.4)))
	check(main.is_mouse_captured(), "a click on the chat log reaches the view")

	# chat_watch: an observer (the phone link) sees every role, without moving
	# the agent's cursor.
	var cursor: int = bridge.chat.agent_cursor
	r = await bridge.handle("chat_watch", {})
	var newest: int = r["last_id"]
	check(r["messages"].is_empty() and newest == bridge.chat.messages[-1]["id"], "chat_watch without after reports the newest id")
	var watched: Array = [null]
	var watcher := func(): watched[0] = await bridge.handle("chat_watch", {"after": newest, "timeout": 5.0})
	watcher.call()
	await ui.frames(2)
	await bridge.handle("chat_say", {"text": "On my way."})
	await ui.frames(2)
	check(watched[0] != null and watched[0]["messages"][0]["role"] == "agent", "chat_watch wakes on an agent reply")
	check_eq(bridge.chat.agent_cursor, cursor, "and leaves the agent's cursor alone")

	# Docked (fullscreen), the console takes a strip on the right: the chat
	# moves to its left edge.
	main.set_docked(true)
	await ui.frames(2)
	var dock_left: float = main._dock_rect().position.x
	check_approx(ui.global_rect(chat).end.x, dock_left - ChatPanel.MARGIN, "docked, the chat keeps left of the console", 1.0)
	main.set_docked(false)
	await ui.frames(2)
	check_approx(ui.global_rect(chat).end.x, 1280.0 - ChatPanel.MARGIN, "and returns to the edge when undocked", 1.0)

	r = await bridge.handle("chat_clear", {})
	await ui.frames(2)
	check_eq(chat.log_box.get_child_count(), 0, "chat_clear empties the panel")

	main.queue_free()
	await ui.frames(1)
