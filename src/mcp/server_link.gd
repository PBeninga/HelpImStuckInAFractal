class_name ServerLink
extends Node
## The game's own line to the phone server: on launch it dials out to the
## server's /game/link over a WebSocket and keeps it open, so calls reach the
## game wherever it runs (behind NAT, no port to open, no second process).
## It speaks the same protocol as server/link/link.mjs, which it replaces:
##
##   server -> game   {type: "event", event}            call activity: config, call_ringing,
##                                                     call_started, utterance, agent_said, call_ended
##                    {type: "rpc", id, cmd, args}      any McpBridge command
##   game -> server   {type: "hello", game}             once on connect (McpBridge status)
##                    {type: "rpc_result", id, ok, result | error}
##                    {type: "say", text}               an agent's line in the pilot chat, to speak
##                    {type: "chat", text}              what the pilot typed, for a voice agent
##                    {type: "ship_event", event}       the call centre's news for the agent
##
## When the server's agent is the OpenAI voice agent, it starts the call centre
## (call_center/) if the game was launched without it: its tools are the ship.
##
## McpBridge starts it when it finds a server: FRACTAL_SERVER_URL and
## GAME_LINK_TOKEN in the environment, or in server/.env (not in a headless
## run, so the tests never link). `-- --no-link` or FRACTAL_LINK=0 turns it off.
## The web build can't send the token header, so it does not link.

const ENV_FILE := "res://server/.env"
const BACKOFF_MIN := 1.0
const BACKOFF_MAX := 30.0
## Close code the server uses when a newer link takes over.
const CLOSE_REPLACED := 4000

## off, connecting, linked, retrying (waiting to reconnect), replaced (a newer link took over)
var state := "off"
var url := ""
var token := ""
var bridge: Node

var _ws: WebSocketPeer
var _gen := 0          # bumps per connection; stale loops stop
var _backoff := BACKOFF_MIN
var _retry_in := -1.0
var _was_open := false


## {url, token, from} for the server to link to, or {} when there is none.
## In a headless run only the environment counts (never server/.env).
static func find_config(headless: bool) -> Dictionary:
	var u := OS.get_environment("FRACTAL_SERVER_URL")
	var t := OS.get_environment("GAME_LINK_TOKEN")
	var from := "environment"
	if (u == "" or t == "") and not headless:
		var env := read_env_file(ENV_FILE)
		u = u if u != "" else str(env.get("FRACTAL_SERVER_URL", ""))
		t = t if t != "" else str(env.get("GAME_LINK_TOKEN", ""))
		from = "server/.env"
	if u == "" or t == "":
		return {}
	return {"url": link_url(u), "token": t, "from": from}


## https://host -> wss://host/game/link (http -> ws), as the node link does.
static func link_url(server_url: String) -> String:
	var u := server_url.strip_edges().trim_suffix("/")
	if u.begins_with("http"):
		u = "ws" + u.substr(4)
	return u + "/game/link"


## KEY=VALUE lines; # comments, blank lines and surrounding quotes ignored.
static func read_env_file(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	for raw in f.get_as_text().split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or not "=" in line:
			continue
		var key := line.get_slice("=", 0).strip_edges().trim_prefix("export ")
		var value := line.substr(line.find("=") + 1).strip_edges()
		if value.length() >= 2 and value[0] == value[-1] and (value[0] == "\"" or value[0] == "'"):
			value = value.substr(1, value.length() - 2)
		elif " #" in value:
			value = value.get_slice(" #", 0).strip_edges()
		out[key] = value
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var chat: Object = bridge.get("chat") if bridge != null else null
	if chat != null:
		chat.message_added.connect(_on_chat_message)
	_connect()


func _exit_tree() -> void:
	_gen += 1
	if _ws != null:
		_ws.close()


func describe() -> Dictionary:
	return {"state": state, "url": url}


func _connect() -> void:
	_gen += 1
	_was_open = false
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer %s" % token])
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.outbound_buffer_size = 32 * 1024 * 1024   # screenshots go back as rpc results
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_warning("ServerLink: can't dial %s (%s)" % [url, error_string(err)])
		_retry()
		return
	state = "connecting"


func _process(delta: float) -> void:
	if _retry_in >= 0.0:
		_retry_in -= delta
		if _retry_in < 0.0:
			_connect()
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_on_open()
			while _ws.get_available_packet_count() > 0:
				var msg: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_on_message(msg)
		WebSocketPeer.STATE_CLOSED:
			_on_closed(_ws.get_close_code())


func _on_open() -> void:
	_was_open = true
	_backoff = BACKOFF_MIN
	state = "linked"
	print("ServerLink: linked to %s" % url)
	_call_center({"link_up": true})
	var status: Dictionary = await bridge.handle("status", {})
	_send({"type": "hello", "game": status})
	_watch_ship_events(_gen)


func _on_closed(code: int) -> void:
	var was_open := _was_open
	_ws = null
	_was_open = false
	_gen += 1
	if was_open:
		_call_center({"link_up": false})
	if code == CLOSE_REPLACED:
		state = "replaced"
		print("ServerLink: another link took over; this game stays unlinked")
		return
	if was_open:
		print("ServerLink: lost the link (%d); reconnecting" % code)
	else:
		push_warning("ServerLink: could not link to %s (refused or unreachable); retrying in %d s" % [url, int(_backoff)])
	_retry()


func _retry() -> void:
	state = "retrying"
	_retry_in = _backoff
	_backoff = minf(_backoff * 2.0, BACKOFF_MAX)


func _send(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"rpc":
			_on_rpc(msg)
		"event":
			var e: Variant = msg.get("event")
			if e is Dictionary:
				_on_event(e)


func _on_rpc(msg: Dictionary) -> void:
	var args: Variant = msg.get("args", {})
	var gen := _gen
	var r: Dictionary = await bridge.handle(str(msg.get("cmd", "")), args if args is Dictionary else {})
	if gen != _gen:
		return   # the link dropped meanwhile; the server already gave up on it
	if r.has("error"):
		_send({"type": "rpc_result", "id": msg.get("id"), "ok": false, "error": str(r["error"])})
	else:
		_send({"type": "rpc_result", "id": msg.get("id"), "ok": true, "result": r})


## Call activity from the server: the call centre's line state, and the
## conversation into the pilot chat.
func _on_event(e: Dictionary) -> void:
	var text := str(e.get("text", ""))
	match str(e.get("type", "")):
		"config":
			# The voice agent flies the ship with the call centre's tools: start it
			# if the game was launched without it.
			if str(e.get("voice_agent", "")) == "openai" and not bridge.has_command("call_center") \
					and bridge.has_method("start_call_center") and bridge.start_call_center():
				print("ServerLink: the phone server's voice agent needs the call centre; starting it")
				await get_tree().process_frame
				await get_tree().process_frame
			_call_center({"support_number": str(e.get("support_number", "")), "link_up": true})
		"call_ringing":
			_call_center({"call_state": "ringing"})
		"call_started":
			await _call_center({"call_state": "connected", "agent_name": str(e.get("agent_name", ""))})
			bridge.handle("chat_post", {"role": "system", "text": "Phone call connected (%s)" % str(e.get("from", ""))})
		"agent_said":
			# said on the call already; "phone" keeps it from being spoken twice
			bridge.handle("chat_say", {"text": text, "source": "phone"})
		"utterance":
			if e.get("final", false):
				bridge.handle("chat_post", {"text": text, "source": "voice"})
			else:
				bridge.handle("chat_draft", {"text": text})
		"call_ended":
			await _call_center({"call_state": "ended"})
			bridge.handle("chat_draft", {"text": ""})
			bridge.handle("chat_post", {"role": "system", "text": "Phone call ended"})


## Tell the call centre (when the game runs one) about the line and the call.
func _call_center(args: Dictionary) -> void:
	if bridge != null and bridge.has_command("call_center"):
		await bridge.handle("call_center", args)


## The pilot chat, as it happens: an agent's replies go to the server to be
## spoken (not the phone agent's own lines), what the pilot types goes to a
## voice agent on a call.
func _on_chat_message(m: Dictionary) -> void:
	var role := str(m.get("role", ""))
	var source := str(m.get("source", ""))
	if role == "agent" and source != "phone":
		_send({"type": "say", "text": m["text"]})
	elif role == "human" and source == "typed":
		_send({"type": "chat", "text": m["text"]})


## Follow the call centre's ship events (waypoints, questions for the pilot,
## the escape) for the server's voice agent, while this connection lasts.
func _watch_ship_events(gen: int) -> void:
	var after: Variant = null
	while gen == _gen and is_inside_tree():
		if not bridge.has_command("ship_events"):
			await get_tree().create_timer(3.0, true).timeout   # no call centre (yet)
			continue
		if after == null:
			after = (await bridge.handle("ship_events", {})).get("last_id", 0)
			continue
		var r: Dictionary = await bridge.handle("ship_events", {"after": after, "timeout": 20})
		if gen != _gen:
			return
		if r.has("error"):
			after = null
			await get_tree().create_timer(3.0, true).timeout
			continue
		after = r["last_id"]
		for ev in r["events"]:
			_send({"type": "ship_event", "event": ev})
