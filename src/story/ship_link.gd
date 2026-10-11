class_name ShipLink
extends Node
## The ship's MCP server. The game dials out to the support-line relay
## (server/) over a WebSocket and then answers MCP JSON-RPC on it: `initialize`,
## `ping`, `tools/list` and `tools/call` (ShipTools). Dialling out means the
## game needs no open port, and a web build on https can reach a wss:// relay.
##
## Besides MCP, the relay sends notifications the HUD shows: `ship/config`
## (the support number), `ship/call` (ringing / connected / ended) and
## `ship/transcript` (what the agent and the caller say). The game sends
## `ship/event` notifications back: waypoints, pilot-input issues, escape.
##
## The relay's address: `--ship-server=<url>` after `--` on the command line,
## else SHIP_SERVER_URL, else (web) the page's ?ship_server= query, else
## DEFAULT_URL. A token (`--ship-token=`, SHIP_LINK_TOKEN, ?ship_token=) is
## appended as ?token= when set.

signal connection_changed(connected: bool)
signal call_state_changed(state: String, info: Dictionary)
signal transcript_received(role: String, item_id: String, text: String, final: bool)
signal config_received(config: Dictionary)

const DEFAULT_URL := "ws://127.0.0.1:8787/game"
const PROTOCOL_VERSION := "2025-06-18"
const SUPPORTED_VERSIONS := ["2025-06-18", "2025-03-26", "2024-11-05"]
const RETRY_SECONDS := 3.0
const INSTRUCTIONS := "Controls for the starship Icebox, stranded inside a Mandelbox after a failed hyperspace punch jump. Read telemetry with get_ship_status and scan_surroundings; fly with turn_ship, thrust, face_feature and fly_to_feature; point things out with highlight; answer pilot-input issues with resolve_issue."

var tools: ShipTools
var url := ""
var connected := false
## Off in tests: no socket is opened.
var enabled := true

var _ws: WebSocketPeer
var _retry := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the line stays up while paused


func start(p_url: String = "") -> void:
	url = p_url if p_url != "" else resolve_url()
	_retry = 0.0


static func resolve_url() -> String:
	var server := _setting("--ship-server=", "SHIP_SERVER_URL", "ship_server")
	if server == "":
		server = DEFAULT_URL
	var token := _setting("--ship-token=", "SHIP_LINK_TOKEN", "ship_token")
	if token != "":
		server += ("&" if server.contains("?") else "?") + "token=" + token.uri_encode()
	return server


static func _setting(arg_prefix: String, env: String, query: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(arg_prefix):
			return a.trim_prefix(arg_prefix)
	var e := OS.get_environment(env)
	if e != "":
		return e
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('%s') || ''" % query, true)
		if v is String:
			return v
	return ""


func _process(delta: float) -> void:
	if not enabled or url == "":
		return
	if _ws == null:
		_retry -= delta
		if _retry <= 0.0:
			_ws = WebSocketPeer.new()
			if _ws.connect_to_url(url) != OK:
				_ws = null
				_retry = RETRY_SECONDS
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				connection_changed.emit(true)
			while _ws.get_available_packet_count() > 0:
				var reply: Variant = handle_message(_ws.get_packet().get_string_from_utf8())
				if reply != null:
					_send(reply)
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_retry = RETRY_SECONDS
			if connected:
				connected = false
				connection_changed.emit(false)


## Tell the relay something happened. `summary` is a sentence for the support
## agent; with `notify_agent` the relay puts it into the call.
func send_event(kind: String, summary: String, data: Dictionary = {}, notify_agent := true) -> void:
	var params := data.duplicate()
	params["kind"] = kind
	params["summary"] = summary
	params["notify_agent"] = notify_agent
	_send({"jsonrpc": "2.0", "method": "ship/event", "params": params})


func _send(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


## One JSON-RPC message in; the response to send back, or null for a
## notification. Public so it can be tested without a socket.
func handle_message(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _error(null, -32700, "Parse error")
	var msg: Variant = json.data
	if not (msg is Dictionary):
		return _error(null, -32700, "Parse error")
	if not msg.has("method"):
		return null   # a response to something we sent; we send no requests
	var method: String = str(msg["method"])
	var params: Dictionary = msg.get("params", {}) if msg.get("params", {}) is Dictionary else {}
	if not msg.has("id") or msg["id"] == null:
		_handle_notification(method, params)
		return null
	var id: Variant = msg["id"]
	if id is float and is_equal_approx(id, roundf(id)):
		id = int(id)
	match method:
		"initialize":
			var asked := str(params.get("protocolVersion", PROTOCOL_VERSION))
			return _result(id, {
				"protocolVersion": asked if SUPPORTED_VERSIONS.has(asked) else PROTOCOL_VERSION,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": "icebox-ship", "title": "Starship Icebox", "version": "1.0.0"},
				"instructions": INSTRUCTIONS,
			})
		"ping":
			return _result(id, {})
		"tools/list":
			return _result(id, {"tools": ShipTools.definitions()})
		"tools/call":
			if tools == null:
				return _error(id, -32603, "Ship systems offline")
			var name := str(params.get("name", ""))
			var known := false
			for d in ShipTools.definitions():
				if d["name"] == name:
					known = true
			if not known:
				return _error(id, -32602, "Unknown tool: %s" % name)
			var r: Dictionary = tools.call_tool(name, params.get("arguments", {}))
			return _result(id, {
				"content": [{"type": "text", "text": JSON.stringify(r)}],
				"structuredContent": r,
				"isError": not r.get("ok", false),
			})
	return _error(id, -32601, "Method not found: %s" % method)


func _handle_notification(method: String, params: Dictionary) -> void:
	match method:
		"ship/config":
			config_received.emit(params)
		"ship/call":
			call_state_changed.emit(str(params.get("state", "")), params)
		"ship/transcript":
			transcript_received.emit(str(params.get("role", "")), str(params.get("item_id", "")),
				str(params.get("text", "")), bool(params.get("final", false)))


static func _result(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


static func _error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
