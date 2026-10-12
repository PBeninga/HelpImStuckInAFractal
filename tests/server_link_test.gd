extends "res://tests/test_case.gd"
## ServerLink against a stand-in phone server (TCPServer + WebSocketPeer, as
## the real one on Railway speaks): it dials out with the token, retries,
## says hello, runs the server's commands, carries the call into the pilot
## chat and the pilot chat out, forwards ship events, reconnects, and steps
## aside for a newer link.

const TOKEN := "t0k3n"

var bridge: Node
var server := TCPServer.new()
var ws: WebSocketPeer
var inbox: Array = []
var cc_calls: Array = []
var ship_events: Array = []


func run() -> void:
	await frames(1)
	bridge = root.get_node("McpBridge")
	check(bridge.link == null, "no phone server configured (and never from server/.env in a headless run): no link")
	_config()

	# Stand-ins for the call centre's commands, so the link has someone to tell.
	bridge.register_command("call_center", func(a: Dictionary) -> Dictionary:
		cc_calls.append(a)
		return {})
	bridge.register_command("ship_events", _fake_ship_events)

	check(server.listen(0, "127.0.0.1") == OK, "stand-in server listening")
	var link := ServerLink.new()
	link.bridge = bridge
	link.url = "ws://127.0.0.1:%d/game/link" % server.get_local_port()
	link.token = TOKEN
	bridge.add_child(link)

	# 1. The first dial: check the handshake carries the token, then hang up.
	var raw: StreamPeerTCP = await _take_connection()
	var request := await _read_request(raw)
	check(request.begins_with("GET /game/link "), "it dials /game/link")
	check(request.contains("Authorization: Bearer %s" % TOKEN), "with the token as a Bearer header")
	raw.disconnect_from_host()
	check(await _until(func(): return link.state == "retrying"), "a refused dial is retried (state %s)" % link.state)

	# 2. The retry: a real WebSocket this time.
	check(await _accept(), "it dials again after the backoff")
	var hello := await _expect("hello")
	check(hello.get("game", {}).has("extensions"), "hello carries the game's status")
	check(await _until(func(): return link.state == "linked"), "linked")
	check(cc_calls.has({"link_up": true}), "the call centre hears the line is up")
	check_eq(ws.get_requested_url().get_slice("?", 0).ends_with("/game/link"), true, "on the server's link path")

	# The server's commands.
	_send({"type": "rpc", "id": 7, "cmd": "status", "args": {}})
	var res := await _expect("rpc_result")
	check(res.get("ok") == true and int(res.get("id")) == 7, "an rpc runs and answers with its id")
	check_eq(res.get("result", {}).get("server_link", {}).get("state", ""), "off", "(the bridge's own link slot is unused here)")
	_send({"type": "rpc", "id": 8, "cmd": "no_such_command"})
	res = await _expect("rpc_result")
	check(res.get("ok") == false and str(res.get("error", "")) != "", "a failing command answers ok: false with the error")

	# The call, into the call centre and the pilot chat.
	var drafts: Array = []
	bridge.chat.draft_changed.connect(func(t: String): drafts.append(t))
	_send({"type": "event", "event": {"type": "config", "support_number": "+1 555 0100"}})
	_send({"type": "event", "event": {"type": "call_ringing"}})
	_send({"type": "event", "event": {"type": "call_started", "from": "+15550001234", "agent_name": "Gary"}})
	_send({"type": "event", "event": {"type": "utterance", "text": "Hel", "final": false}})
	_send({"type": "event", "event": {"type": "utterance", "text": "Hello, I'm stuck", "final": true}})
	_send({"type": "event", "event": {"type": "agent_said", "text": "Thanks for calling. See #2312?"}})
	check(await _until(func(): return _last_chat().get("text", "") == "Thanks for calling. See #2312?"), "the agent's line lands in the pilot chat")
	check(cc_calls.has({"support_number": "+1 555 0100", "link_up": true}), "config: the support number")
	check(cc_calls.has({"call_state": "ringing"}), "call_ringing")
	check(cc_calls.has({"call_state": "connected", "agent_name": "Gary"}), "call_started: connected, with the agent's name")
	check(_chat_has("system", "Phone call connected (+15550001234)"), "a system line for the call")
	check(drafts.has("Hel"), "a partial transcript is a draft")
	check(_chat_has("human", "Hello, I'm stuck", "voice"), "a final transcript is the pilot's voice message")
	check_eq(_last_chat().get("source"), "phone", "the agent's line is marked as said on the phone")
	await _drain(10)
	check(not inbox.any(func(m): return m["type"] == "say"), "and is not sent back to be spoken again")

	# The pilot chat, out.
	bridge.chat.add("human", "left or right?", "typed")
	var chat := await _expect("chat")
	check_eq(chat.get("text"), "left or right?", "what the pilot types goes to the server")
	await bridge.handle("chat_say", {"text": "Claude here, turning left."})
	var say := await _expect("say")
	check_eq(say.get("text"), "Claude here, turning left.", "another agent's chat reply goes to the server to be spoken")

	# Ship events, as they come.
	ship_events.append({"id": 1, "kind": "waypoint_reached", "summary": "Reached #2312", "notify_agent": true})
	var se := await _expect("ship_event")
	check_eq(se.get("event", {}).get("kind"), "waypoint_reached", "a ship event is forwarded to the server")

	_send({"type": "event", "event": {"type": "call_ended"}})
	check(await _until(func(): return cc_calls.has({"call_state": "ended"})), "call_ended reaches the call centre")
	check(await _until(func(): return _chat_has("system", "Phone call ended")), "with a system line")
	check(drafts.back() == "", "and clears the draft")

	# A dropped connection is redialled.
	ws.close(1001, "deploy")
	check(await _until(func(): return link.state == "retrying"), "a dropped link retries")
	check(cc_calls.back() == {"link_up": false}, "and tells the call centre the line is down")
	check(await _accept(), "and reconnects")
	await _expect("hello")
	check(await _until(func(): return link.state == "linked"), "linked again")

	# Launched without its call centre: a voice-agent server starts it.
	bridge.unregister_command("call_center")
	_send({"type": "event", "event": {"type": "config", "support_number": "+1 555 0100", "voice_agent": "openai"}})
	check(await _until(func(): return root.get_node_or_null(^"CallCenter") != null and bridge.has_command("call_center")),
		"a voice-agent server starts the call centre")
	var cc: Node = root.get_node_or_null(^"CallCenter")
	check(cc != null and await _until(func(): return cc.link_up), "and tells it the line is up")
	check(cc != null and str(cc.hud._support_number).contains("555"), "with the number to call")
	_send({"type": "event", "event": {"type": "config", "voice_agent": "openai"}})
	await _wait_ms(200)
	check(root.get_children().filter(func(n): return n.name.begins_with("CallCenter")).size() == 1, "only once")
	if cc != null:
		cc.queue_free()
		await frames(2)
	bridge.register_command("ship_events", _fake_ship_events)

	# A newer link takes over: this one steps aside for good.
	ws.close(ServerLink.CLOSE_REPLACED, "replaced by a newer link")
	check(await _until(func(): return link.state == "replaced"), "replaced by a newer link")
	await _wait_ms(1500)
	check(not server.is_connection_available(), "and does not dial again")

	link.queue_free()
	bridge.unregister_command("call_center")
	bridge.unregister_command("ship_events")
	server.stop()


func _config() -> void:
	check_eq(ServerLink.link_url("https://fractal.up.railway.app/"), "wss://fractal.up.railway.app/game/link", "https -> wss://…/game/link")
	check_eq(ServerLink.link_url("http://127.0.0.1:3000"), "ws://127.0.0.1:3000/game/link", "http -> ws://…/game/link")
	var path := "user://server_link_test.env"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("# the link\nFRACTAL_SERVER_URL=https://x.example.app\nGAME_LINK_TOKEN=\"abc 123\"\nexport OTHER='y'\nNOTE=value # a comment\n\nEMPTY=\n")
	f.close()
	var env := ServerLink.read_env_file(path)
	check_eq(env.get("FRACTAL_SERVER_URL"), "https://x.example.app", ".env: a plain value")
	check_eq(env.get("GAME_LINK_TOKEN"), "abc 123", ".env: a quoted value")
	check_eq(env.get("OTHER"), "y", ".env: export and single quotes")
	check_eq(env.get("NOTE"), "value", ".env: a trailing comment")
	check_eq(env.get("EMPTY"), "", ".env: an empty value")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(ServerLink.find_config(true).is_empty(), "headless, nothing in the environment: no server")
	OS.set_environment("FRACTAL_SERVER_URL", "https://y.example.app")
	OS.set_environment("GAME_LINK_TOKEN", "zzz")
	var cfg := ServerLink.find_config(true)
	check(cfg.get("url") == "wss://y.example.app/game/link" and cfg.get("token") == "zzz" and cfg.get("from") == "environment",
		"the environment configures it, even headless")
	OS.unset_environment("FRACTAL_SERVER_URL")
	OS.unset_environment("GAME_LINK_TOKEN")


# ------------------------------------------------------------- the stand-in server

func _fake_ship_events(args: Dictionary) -> Dictionary:
	var last: int = ship_events.back()["id"] if not ship_events.is_empty() else 0
	if not args.has("after"):
		return {"events": [], "last_id": last}
	var after := int(args["after"])
	for i in 30:
		var fresh := ship_events.filter(func(e): return e["id"] > after)
		if not fresh.is_empty():
			return {"events": fresh, "last_id": fresh.back()["id"]}
		await process_frame
	return {"events": [], "last_id": after}


func _take_connection() -> StreamPeerTCP:
	for i in 600:
		if server.is_connection_available():
			return server.take_connection()
		await _wait_ms(10)
	return null


func _read_request(peer: StreamPeerTCP) -> String:
	var text := ""
	for i in 300:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			text += (peer.get_data(n)[1] as PackedByteArray).get_string_from_utf8()
			if text.contains("\r\n\r\n"):
				break
		await _wait_ms(10)
	return text


func _accept() -> bool:
	var conn: StreamPeerTCP = await _take_connection()
	if conn == null:
		return false
	ws = WebSocketPeer.new()
	ws.accept_stream(conn)
	inbox.clear()
	for i in 300:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		await _wait_ms(10)
	return false


func _send(msg: Dictionary) -> void:
	ws.send_text(JSON.stringify(msg))


func _drain(n: int) -> void:
	for i in n:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				inbox.append(m)
		await _wait_ms(10)


## The first message of `type` the link sent (waits up to ~3 s), taken from the inbox.
func _expect(type: String) -> Dictionary:
	for i in 300:
		await _drain(1)
		for m: Dictionary in inbox:
			if m["type"] == type:
				inbox.erase(m)
				return m
	check(false, "the link sent a '%s'" % type)
	return {}


func _until(cond: Callable, ms := 4000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		if ws != null:
			ws.poll()
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame


func _last_chat() -> Dictionary:
	return bridge.chat.messages.back() if not bridge.chat.messages.is_empty() else {}


func _chat_has(role: String, text: String, source := "") -> bool:
	return bridge.chat.messages.any(func(m): return m["role"] == role and m["text"] == text and (source == "" or m["source"] == source))
