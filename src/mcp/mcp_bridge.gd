extends Node
## Lets an outside program drive the explorer: the MCP server in mcp/ connects
## here. Autoloaded as `McpBridge`, it listens on 127.0.0.1 (port 9077, or
## FRACTAL_MCP_PORT) for newline-delimited JSON requests
##
##   {"id": 1, "cmd": "move", "args": {"forward": 0.5}}
##
## and answers each with one line, {"id": 1, "ok": true, "result": {...}} or
## {"id": 1, "ok": false, "error": "..."}. handle() is the whole command set and
## can be called directly (the tests do). Vectors travel as [x, y, z] arrays in
## fractal coordinates; window pixels are logical units, as FractalView uses.
##
## It holds the pilot chat (ChatLog): the agent long-polls chat_wait for what
## the person says and answers with chat_say; a speech-to-text process can post
## through chat_post / chat_draft. It also owns the overlay the agent draws on (McpOverlay, on a canvas layer
## above every scene) and an optional trail of where the camera has been.
##
## The server is off in a web build, and in a headless run unless
## FRACTAL_MCP_PORT is set, so the test suite never holds the port. Run with
## `-- --play` to skip the title menu. It also parks the window for a Claude
## session launch (see SessionLaunch).
##
## Other layers add commands with register_command() (the call centre's ship
## tools, for one). `-- --call-center` (or FRACTAL_CALL_CENTER=1) starts the
## call centre (call_center/), `-- --call-center-demo` with its sample route.

const DEFAULT_PORT := 9077
const CALL_CENTER_SCRIPT := "res://call_center/call_center.gd"
const GAME_SCENE := "res://src/main.tscn"
const TRAIL_ID := "trail"
const TRAIL_MAX := 5000
## Seconds a screenshot waits at most for the governor's full-quality frame.
const SETTLE_TIMEOUT := 3.0

var port := 0
var overlay: McpOverlay
## The pilot chat (ChatPanel shows it in the view).
var chat := ChatLog.new()

var _server: TCPServer
var _peers: Array = []   # [{peer: StreamPeerTCP, buf: PackedByteArray}]
var _shapes: Array = []
var _next_id := 1
var _trail_on := false
var _trail: Array = []   # Vector3 eye positions
## Commands added by other layers: name -> Callable(args: Dictionary) -> Dictionary.
var _extensions := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	overlay = McpOverlay.new()
	overlay.shapes = _shapes
	layer.add_child(overlay)

	var env_port := OS.get_environment("FRACTAL_MCP_PORT")
	var headless := DisplayServer.get_name() == "headless"
	if not OS.has_feature("web") and (env_port != "" or not headless):
		port = int(env_port) if env_port != "" else DEFAULT_PORT
		_server = TCPServer.new()
		var err := _server.listen(port, "127.0.0.1")
		if err != OK:
			push_warning("McpBridge: could not listen on 127.0.0.1:%d (%s)" % [port, error_string(err)])
			_server = null
		else:
			print("McpBridge listening on 127.0.0.1:%d" % port)

	# A Claude-session launch stays out of the way (SessionLaunch). Deferred so
	# it lands after the first scene's UiScale.fit_main_window has moved the window.
	if SessionLaunch.is_requested():
		SessionLaunch.park_window.call_deferred()

	if "--play" in OS.get_cmdline_user_args():
		_start_game.call_deferred()

	_start_call_center()


## The call centre (call_center/) beside the game, when asked for. It adds its
## own commands here once it is up.
func _start_call_center() -> void:
	var user_args := OS.get_cmdline_user_args()
	var demo := "--call-center-demo" in user_args
	if not (demo or "--call-center" in user_args or OS.get_environment("FRACTAL_CALL_CENTER") == "1"):
		return
	if not ResourceLoader.exists(CALL_CENTER_SCRIPT) or get_node_or_null(^"/root/CallCenter") != null:
		return
	var cc: Node = load(CALL_CENTER_SCRIPT).new()
	cc.name = "CallCenter"
	cc.set("demo", demo)
	get_tree().root.add_child.call_deferred(cc)


## Add a command. `handler` takes the args Dictionary and returns a result
## Dictionary ({"error": "..."} to fail); it may await.
func register_command(cmd: String, handler: Callable) -> void:
	_extensions[cmd] = handler


func unregister_command(cmd: String) -> void:
	_extensions.erase(cmd)


func has_command(cmd: String) -> bool:
	return _extensions.has(cmd)


func _process(_delta: float) -> void:
	_poll_server()
	var main := _main()
	if main != null:
		overlay.view = main.view
		overlay.camera = main.camera
		if _trail_on:
			_record_trail(main)
	else:
		overlay.view = null
		overlay.camera = null
	overlay.queue_redraw()


# ------------------------------------------------------------- transport

func _poll_server() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buf": PackedByteArray()})
	for entry: Dictionary in _peers.duplicate():
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_peers.erase(entry)
			continue
		var avail := peer.get_available_bytes()
		if avail <= 0:
			continue
		var got: Array = peer.get_partial_data(avail)
		if got[0] != OK:
			continue
		var buf: PackedByteArray = entry["buf"]
		buf.append_array(got[1])
		var nl := buf.find(10)
		while nl != -1:
			var line := buf.slice(0, nl).get_string_from_utf8()
			buf = buf.slice(nl + 1)
			if not line.strip_edges().is_empty():
				_serve(peer, line)
			nl = buf.find(10)
		entry["buf"] = buf


func _serve(peer: StreamPeerTCP, line: String) -> void:
	var req: Variant = JSON.parse_string(line)
	if not req is Dictionary:
		_reply(peer, {"id": null, "ok": false, "error": "request is not a JSON object"})
		return
	var id: Variant = req.get("id")
	var args: Variant = req.get("args", {})
	var result: Dictionary = await handle(str(req.get("cmd", "")), args if args is Dictionary else {})
	if result.has("error"):
		_reply(peer, {"id": id, "ok": false, "error": result["error"]})
	else:
		_reply(peer, {"id": id, "ok": true, "result": result})


func _reply(peer: StreamPeerTCP, msg: Dictionary) -> void:
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


# ------------------------------------------------------------- commands

## Run one command. Returns its result, or {"error": "..."}. May await (camera
## animation, screenshots).
func handle(cmd: String, args: Dictionary) -> Dictionary:
	if _extensions.has(cmd):
		var handler: Callable = _extensions[cmd]
		if not handler.is_valid():
			_extensions.erase(cmd)
			return {"error": "'%s' is no longer available" % cmd}
		var r: Variant = await handler.call(args)
		return r if r is Dictionary else {"result": r}
	match cmd:
		"status": return _status()
		"start_game": return await _start_game()
		"draw": return _draw_shape(args)
		"clear_drawings": return _clear_drawings(args)
		"list_drawings": return {"drawings": _shapes.map(_shape_to_json)}
		"chat_wait": return await _chat_wait(args)
		"chat_say": return _chat_say(args)
		"chat_post": return _chat_post(args)
		"chat_draft":
			chat.set_draft(str(args.get("text", "")))
			return {}
		"chat_watch": return await _chat_watch(args)
		"chat_history": return {"messages": chat.recent(clampi(int(args.get("limit", 50)), 1, ChatLog.MAX_MESSAGES))}
		"chat_clear":
			chat.clear()
			return {}
	var main := _main()
	if main == null:
		return {"error": "no view is open (the title menu is showing); call start_game first"}
	match cmd:
		"get_camera": return _camera_json(main)
		"set_camera": return await _set_camera(main, args)
		"move": return await _move(main, args)
		"rotate": return await _rotate(main, args)
		"dive": return await _dive(main, args)
		"raycast": return _raycast(main, args)
		"probe": return _probe(main, args)
		"project": return _project(main, args)
		"get_shape": return _get_shape(main)
		"set_shape": return _set_shape(main, args)
		"list_views": return _list_views()
		"load_view": return _load_view(main, args)
		"save_view": return _save_view(main, args)
		"screenshot": return await _screenshot(main, args)
		"trail": return _trail_cmd(args)
	return {"error": "unknown command '%s'" % cmd}


func _main() -> Main:
	return get_tree().current_scene as Main


func _status() -> Dictionary:
	var main := _main()
	var out := {
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
		"in_game": main != null,
		"paused": get_tree().paused,
		"window_size": _v2(get_viewport().get_visible_rect().size),
		"drawings": _shapes.size(),
		"trail": {"on": _trail_on, "points": _trail.size()},
		"extensions": _extensions.keys(),
	}
	if main != null:
		out["camera"] = _camera_json(main)
		out["view_size"] = _v2(main.view.size)
		out["camera_mode"] = "orbit" if main.params.camera_mode == FractalParams.CameraMode.ORBIT else "fly"
	return out


func _start_game() -> Dictionary:
	if _main() == null:
		get_tree().paused = false
		get_tree().change_scene_to_file(GAME_SCENE)
		for i in 10:
			await get_tree().process_frame
			if _main() != null and _main().is_node_ready():
				break
	var main := _main()
	if main == null:
		return {"error": "the game scene did not load"}
	get_tree().paused = false
	return _status()


# ------------------------------------------------------------- camera

func _camera_json(main: Main) -> Dictionary:
	var cam := main.camera
	return {
		"eye": _v3(cam.eye()),
		"forward": _v3(cam.forward()),
		"up": _v3(cam.up()),
		"right": _v3(cam.right()),
		"speed_factor": cam.speed_factor,
		"surface_distance": DistanceEstimator.estimate(cam.eye(), main.params),
	}


## eye / look_at / forward / up, any subset; duration > 0 animates there.
func _set_camera(main: Main, args: Dictionary) -> Dictionary:
	var cam := main.camera
	var eye := _arg_v3(args, "eye", cam.eye())
	var fwd := cam.forward()
	if args.has("look_at"):
		fwd = _arg_v3(args, "look_at", Vector3.ZERO) - eye
	elif args.has("forward"):
		fwd = _arg_v3(args, "forward", fwd)
	if fwd.length_squared() == 0.0:
		return {"error": "the camera cannot look at its own position"}
	var up := _arg_v3(args, "up", Vector3(0, 0, 1))
	if args.has("speed_factor"):
		cam.speed_factor = clampf(float(args["speed_factor"]), 0.01, 100.0)
	await _go(main, _look(eye, fwd, up), float(args.get("duration", 0.0)))
	return _camera_json(main)


## Move in the camera's frame. Distances are multiples of the distance to the
## nearest surface by default (units="surface"), which keeps one step meaningful
## at every zoom depth; units="world" takes them literally. With safe (default),
## the move stops short of any surface in its way.
func _move(main: Main, args: Dictionary) -> Dictionary:
	var cam := main.camera
	var local := Vector3(float(args.get("right", 0.0)), float(args.get("up", 0.0)), float(args.get("forward", 0.0)))
	var delta := cam.right() * local.x + cam.up() * local.y + cam.forward() * local.z
	var unit := 1.0
	if str(args.get("units", "surface")) == "surface":
		unit = DistanceEstimator.estimate(cam.eye(), main.params)
	delta *= unit
	var clamped := false
	if bool(args.get("safe", true)) and delta.length_squared() > 0.0:
		var hit: Variant = FractalProbe.march(cam.eye(), delta.normalized(), main.params)
		if hit != null and hit["distance"] * 0.8 < delta.length():
			delta = delta.normalized() * hit["distance"] * 0.8
			clamped = true
	var t := cam.transform
	t.origin += delta
	await _go(main, t, float(args.get("duration", 0.0)))
	var out := _camera_json(main)
	out["moved"] = delta.length()
	out["clamped"] = clamped
	return out


## Yaw about world +Z (as the fly camera's mouse-look does), then pitch about
## the camera's right and roll about its forward. Degrees.
func _rotate(main: Main, args: Dictionary) -> Dictionary:
	var t := main.camera.transform
	var b := t.basis
	b = Basis(Vector3(0, 0, 1), deg_to_rad(float(args.get("yaw", 0.0)))) * b
	b = Basis(b.x.normalized(), deg_to_rad(float(args.get("pitch", 0.0)))) * b
	b = Basis(-b.z.normalized(), deg_to_rad(-float(args.get("roll", 0.0)))) * b
	t.basis = b.orthonormalized()
	await _go(main, t, float(args.get("duration", 0.0)))
	return _camera_json(main)


## Fly toward the surface under a window pixel (default: the centre), covering
## `fraction` of the way and turning to face the hit point.
func _dive(main: Main, args: Dictionary) -> Dictionary:
	var hit: Variant = _hit_at(main, args)
	if hit == null:
		return {"error": "nothing under that pixel"}
	var fraction := clampf(float(args.get("fraction", 0.5)), 0.0, 0.99)
	var eye := main.camera.eye()
	var target: Vector3 = hit["point"]
	var new_eye := eye.lerp(target, fraction)
	await _go(main, _look(new_eye, target - new_eye, main.camera.up()), float(args.get("duration", 0.0)))
	var out := _camera_json(main)
	out["target"] = _v3(target)
	return out


## Snap or animate the camera to `to`. Linear in position, slerp in rotation,
## eased. In orbit mode the orbit centre is re-derived afterwards.
func _go(main: Main, to: Transform3D, duration: float) -> void:
	var cam := main.camera
	if duration > 0.0:
		var from := cam.transform
		var q0 := from.basis.get_rotation_quaternion()
		var q1 := to.basis.get_rotation_quaternion()
		var elapsed := 0.0
		while elapsed < duration:
			await get_tree().process_frame
			if not is_instance_valid(main):
				return
			elapsed += get_process_delta_time()
			var k := smoothstep(0.0, 1.0, minf(elapsed / duration, 1.0))
			cam.transform = Transform3D(Basis(q0.slerp(q1, k)), from.origin.lerp(to.origin, k))
	cam.transform = to
	var orbit := main.get_node_or_null("OrbitCamera") as OrbitCamera
	if orbit != null and main.params.camera_mode == FractalParams.CameraMode.ORBIT:
		orbit.enter()


func _look(eye: Vector3, fwd: Vector3, up: Vector3) -> Transform3D:
	fwd = fwd.normalized()
	if absf(fwd.dot(up.normalized())) > 0.999:
		up = Vector3(0, 1, 0) if absf(fwd.y) < 0.9 else Vector3(1, 0, 0)
	return Transform3D(Basis.IDENTITY, eye).looking_at(eye + fwd, up)


# ------------------------------------------------------------- queries

func _hit_at(main: Main, args: Dictionary) -> Variant:
	var size := main.view.size
	var px := Vector2(float(args.get("x", size.x * 0.5)), float(args.get("y", size.y * 0.5)))
	var dir := main.view.unproject(px, 1.0) - main.camera.eye()
	return FractalProbe.march(main.camera.eye(), dir, main.params)


## The surface under a window pixel (default: the centre).
func _raycast(main: Main, args: Dictionary) -> Dictionary:
	var hit: Variant = _hit_at(main, args)
	if hit == null:
		return {"hit": false}
	return {
		"hit": true,
		"point": _v3(hit["point"]),
		"distance": hit["distance"],
		"normal": _v3(hit["normal"]),
		"steps": hit["steps"],
	}


## The distance estimate at a world point.
func _probe(main: Main, args: Dictionary) -> Dictionary:
	if not args.has("point"):
		return {"error": "probe needs a point"}
	var p := _arg_v3(args, "point", Vector3.ZERO)
	return {"point": _v3(p), "distance": DistanceEstimator.estimate(p, main.params)}


## The window pixel of a world point.
func _project(main: Main, args: Dictionary) -> Dictionary:
	var px: Variant = main.view.project(_arg_v3(args, "point", Vector3.ZERO))
	return {"visible": px != null, "pixel": _v2(px) if px != null else null}


# ------------------------------------------------------------- shape / views

## The knobs a set_shape can reach: the active shape's table, then the look
## table (light, material, colour).
func _shape_tables(main: Main) -> Array[AttributeTable]:
	return [main.table(), main.look_table()]


func _get_shape(main: Main) -> Dictionary:
	var out: Array = []
	for table in _shape_tables(main):
		_list_rows(table, out)
	return {"params": out}


func _list_rows(table: AttributeTable, out: Array) -> void:
	for s: AttributeSpec in table.specs:
		var row := {
			"id": String(s.id), "label": s.label, "group": s.group,
			"type": AttributeSpec.Type.keys()[s.type].to_lower(),
			"value": table.get_default(s.id), "description": s.tooltip,
		}
		if s.type == AttributeSpec.Type.FLOAT:
			row["min"] = s.min_value
			row["max"] = s.max_value
		elif s.type == AttributeSpec.Type.ENUM:
			row["options"] = {}
			for i in s.enum_values.size():
				row["options"][str(s.enum_values[i])] = s.enum_labels[i]
		out.append(row)


func _set_shape(main: Main, args: Dictionary) -> Dictionary:
	var values: Variant = args.get("values", {})
	if not values is Dictionary or values.is_empty():
		return {"error": "set_shape needs a non-empty values object"}
	var tables := _shape_tables(main)
	var owner := {}
	var unknown: Array = []
	for id in values:
		for table: AttributeTable in tables:
			if table.has(StringName(id)):
				owner[id] = table
				break
		if owner.has(id):
			(owner[id] as AttributeTable).set_default(StringName(id), values[id])
		else:
			unknown.append(id)
	main._resolve_once()
	var applied := {}
	for id in owner:
		applied[id] = (owner[id] as AttributeTable).get_default(StringName(id))
	var out := {"applied": applied}
	if not unknown.is_empty():
		out["unknown"] = unknown
	return out


func _list_views() -> Dictionary:
	var dir := WorkspaceFiles.directory()
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json") and f != "keymap.json":
			names.append(f.get_basename())
	return {"directory": dir, "views": names}


func _view_path(args: Dictionary) -> String:
	var name := str(args.get("name", "")).get_file().get_basename()
	if name.is_empty():
		return ""
	return WorkspaceFiles.directory().path_join(name + ".json")


func _load_view(main: Main, args: Dictionary) -> Dictionary:
	var path := _view_path(args)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"error": "no such view: %s" % args.get("name", "")}
	main.load_level_from(path)
	return _camera_json(main)


func _save_view(main: Main, args: Dictionary) -> Dictionary:
	var path := _view_path(args)
	if path.is_empty():
		return {"error": "save_view needs a name"}
	main.save_level_to(path)
	return {"path": path}


## A PNG (or JPEG) of the window, base64. Waits for the governor's
## full-resolution still frame first. overlay=false captures the bare fractal
## without the drawings or any UI.
func _screenshot(main: Main, args: Dictionary) -> Dictionary:
	var waited := 0.0
	while waited < SETTLE_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not is_instance_valid(main):
			return {"error": "the view closed"}
		if main.governor.mode == ResolutionGovernor.Mode.IDLE and main.view.render_scale >= 1.0:
			break
	if not await _drawn_frame():
		return {"error": "the window is not drawing frames: it is covered, minimised or entirely off screen"}
	var img: Image = get_viewport().get_texture().get_image() if bool(args.get("overlay", true)) \
			else main.view.capture()
	if img == null or img.is_empty():
		return {"error": "no frame to capture (is the window headless?)"}
	var max_w := int(args.get("max_width", 1024))
	if max_w > 0 and img.get_width() > max_w:
		img.resize(max_w, int(round(img.get_height() * float(max_w) / img.get_width())), Image.INTERPOLATE_LANCZOS)
	var fmt := str(args.get("format", "png"))
	var bytes := img.save_jpg_to_buffer(0.85) if fmt == "jpeg" else img.save_png_to_buffer()
	return {
		"format": "jpeg" if fmt == "jpeg" else "png",
		"width": img.get_width(), "height": img.get_height(),
		"data": Marshalls.raw_to_base64(bytes),
	}


## Wait for the next drawn frame. A macOS window with nothing visible on screen
## draws none, and frame_post_draw would then never come.
func _drawn_frame() -> bool:
	var drawn := [false]
	var mark := func(): drawn[0] = true
	RenderingServer.frame_post_draw.connect(mark, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not drawn[0] and waited < SETTLE_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not drawn[0]:
		RenderingServer.frame_post_draw.disconnect(mark)
	return drawn[0]


# ------------------------------------------------------------- chat

## Wait up to `timeout` seconds for human messages the agent has not seen yet,
## and hand them over (the cursor advances). While waiting the panel shows the
## agent as listening; once messages are handed over, as working until it
## listens again.
func _chat_wait(args: Dictionary) -> Dictionary:
	var timeout := clampf(float(args.get("timeout", 25.0)), 0.0, 300.0)
	chat.busy = false
	chat.listeners += 1
	var waited := 0.0
	var fresh := chat.human_after(chat.agent_cursor)
	while fresh.is_empty() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
		fresh = chat.human_after(chat.agent_cursor)
	chat.listeners -= 1
	if not fresh.is_empty():
		chat.agent_cursor = fresh[fresh.size() - 1]["id"]
		chat.busy = true
	return {"messages": fresh, "timed_out": fresh.is_empty()}


## Every message (any role) after id `after`, waiting up to `timeout` seconds
## for one. For observers such as the phone link, which speaks the agent's
## replies on the call: unlike chat_wait it leaves the agent's cursor and state
## alone. Without `after` it answers at once with just the newest id.
func _chat_watch(args: Dictionary) -> Dictionary:
	var last_id: int = chat.messages[-1]["id"] if not chat.messages.is_empty() else 0
	if not args.has("after"):
		return {"messages": [], "last_id": last_id}
	var after := int(args["after"])
	var timeout := clampf(float(args.get("timeout", 25.0)), 0.0, 300.0)
	var since := func(): return chat.messages.filter(func(m): return m["id"] > after)
	var fresh: Array = since.call()
	var waited := 0.0
	while fresh.is_empty() and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
		fresh = since.call()
	if not chat.messages.is_empty():
		last_id = chat.messages[-1]["id"]
	return {"messages": fresh, "last_id": maxi(last_id, after)}


func _chat_say(args: Dictionary) -> Dictionary:
	var text := str(args.get("text", "")).strip_edges()
	if text.is_empty():
		return {"error": "say needs some text"}
	return chat.add("agent", text, str(args.get("source", "")))


## A message from outside the panel: a voice transcript ("human", source
## "voice") or a "system" notice.
func _chat_post(args: Dictionary) -> Dictionary:
	var text := str(args.get("text", "")).strip_edges()
	var role := str(args.get("role", "human"))
	if text.is_empty():
		return {"error": "chat_post needs some text"}
	if role != "human" and role != "system":
		return {"error": "role must be 'human' or 'system'"}
	chat.set_draft("")
	return chat.add(role, text, str(args.get("source", "voice" if role == "human" else "")))


# ------------------------------------------------------------- drawing

## Add one shape. type: line (points, 2+), polygon (points, closed), circle
## (center, radius px, filled), text (position, text, size), point (position, a
## filled dot with an optional label). space: "screen" (pixels) or "world"
## (fractal coordinates, stays on the fractal as the camera moves).
## Returns its id; passing an existing id replaces that shape.
func _draw_shape(args: Dictionary) -> Dictionary:
	var type := str(args.get("type", ""))
	var space := str(args.get("space", "screen"))
	if space != "screen" and space != "world":
		return {"error": "space must be 'screen' or 'world'"}
	var world := space == "world"
	var base := {
		"space": space,
		"color": _color(args.get("color", "white")),
		"width": float(args.get("width", 2.0)),
	}
	var made: Array = []
	match type:
		"line", "polygon":
			var pts: Array = []
			for p in args.get("points", []):
				var v: Variant = _point(p, world)
				if v == null:
					return {"error": "bad point %s" % [p]}
				pts.append(v)
			if pts.size() < 2:
				return {"error": "%s needs at least two points" % type}
			made.append(_with(base, {"type": "polyline", "points": pts, "closed": type == "polygon"}))
		"circle":
			var c: Variant = _point(args.get("center"), world)
			if c == null:
				return {"error": "circle needs a center"}
			made.append(_with(base, {"type": "circle", "center": c,
				"radius": float(args.get("radius", 10.0)), "filled": bool(args.get("filled", false))}))
		"text", "point":
			var p: Variant = _point(args.get("position"), world)
			if p == null:
				return {"error": "%s needs a position" % type}
			var label := str(args.get("text", ""))
			if type == "point":
				made.append(_with(base, {"type": "circle", "center": p,
					"radius": float(args.get("radius", 5.0)), "filled": true}))
			if not label.is_empty():
				var off := Vector2(8, -8) if type == "point" else Vector2.ZERO
				made.append(_with(base, {"type": "text", "position": p, "text": label,
					"size": int(args.get("size", 16)), "offset": off}))
		_:
			return {"error": "unknown shape type '%s' (line, polygon, circle, text, point)" % type}
	if made.is_empty():
		return {"error": "text needs some text"}
	var id := str(args.get("id", ""))
	if id.is_empty():
		id = "d%d" % _next_id
		_next_id += 1
	_remove(id)
	for s: Dictionary in made:
		s["id"] = id
		_shapes.append(s)
	return {"id": id}


func _clear_drawings(args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var before := _shapes.size()
	if id.is_empty():
		_shapes.clear()
		_trail.clear()
	else:
		_remove(id)
		if id == TRAIL_ID:
			_trail.clear()
	return {"removed": before - _shapes.size()}


func _remove(id: String) -> void:
	for i in range(_shapes.size() - 1, -1, -1):
		if _shapes[i]["id"] == id:
			_shapes.remove_at(i)


func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(extra, true)
	return d


func _shape_to_json(s: Dictionary) -> Dictionary:
	var out := {}
	for k in s:
		var v: Variant = s[k]
		match typeof(v):
			TYPE_VECTOR3: out[k] = _v3(v)
			TYPE_VECTOR2: out[k] = _v2(v)
			TYPE_COLOR: out[k] = "#" + (v as Color).to_html()
			TYPE_ARRAY:
				out[k] = (v as Array).map(func(p): return _v3(p) if p is Vector3 else _v2(p))
			_: out[k] = v
	return out


## trail {on: bool, color, width}: record the camera's path as a world line.
func _trail_cmd(args: Dictionary) -> Dictionary:
	if args.has("on"):
		_trail_on = bool(args["on"])
	if _trail_on and _find(TRAIL_ID) == null:
		_shapes.append({"id": TRAIL_ID, "type": "polyline", "space": "world", "points": _trail,
			"closed": false, "color": _color(args.get("color", "#ffcc33")),
			"width": float(args.get("width", 2.0))})
	return {"on": _trail_on, "points": _trail.size()}


func _find(id: String) -> Variant:
	for s: Dictionary in _shapes:
		if s["id"] == id:
			return s
	return null


func _record_trail(main: Main) -> void:
	var eye := main.camera.eye()
	if not _trail.is_empty():
		var last: Vector3 = _trail[_trail.size() - 1]
		var step := maxf(DistanceEstimator.estimate(eye, main.params) * 0.05, 1e-7)
		if last.distance_to(eye) < step:
			return
	_trail.append(eye)
	if _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)


# ------------------------------------------------------------- conversions

static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _v2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _arg_v3(args: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var a: Variant = args.get(key)
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _point(p: Variant, world: bool) -> Variant:
	if not p is Array or p.size() != (3 if world else 2):
		return null
	if world:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector2(float(p[0]), float(p[1]))


## "#rrggbb[aa]", a named colour ("red") or [r, g, b(, a)] in 0..1.
static func _color(c: Variant) -> Color:
	if c is Array and c.size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
	return Color.from_string(str(c), Color.WHITE)
