extends "res://tests/test_case.gd"
## McpBridge.handle(), the whole command set, driven directly (headless, so no
## TCP server and no pixels; screenshots are left to a windowed run).


func _near(a: Array, b: Vector3, eps := 1e-3) -> bool:
	return Vector3(a[0], a[1], a[2]).distance_to(b) <= eps


func run() -> void:
	await frames(1)   # _initialize runs before the root is in the tree
	var bridge: Node = root.get_node("McpBridge")
	check(bridge != null, "McpBridge is autoloaded")
	check(bridge.port == 0, "the server stays off in a headless run")

	var r: Dictionary = await bridge.handle("get_camera", {})
	check(r.has("error"), "camera commands need an open view")
	r = await bridge.handle("find_nearest_surface", {})
	check(r.has("error"), "surface recovery requires an open view")
	r = await bridge.handle("nonsense", {})
	check(r.has("error"), "an unknown command is an error")

	# Drawings work without a view.
	r = await bridge.handle("draw", {"type": "line", "points": [[0, 0], [100, 100]], "color": "red"})
	check_eq(r.get("id"), "d1", "draw returns a fresh id")
	r = await bridge.handle("draw", {"type": "circle", "center": [10, 10], "radius": 4, "id": "c"})
	check_eq(r.get("id"), "c", "draw keeps a given id")
	r = await bridge.handle("draw", {"type": "circle", "center": [20, 20], "id": "c"})
	r = await bridge.handle("list_drawings", {})
	check_eq((r["drawings"] as Array).size(), 2, "re-drawing an id replaces it")
	check_eq(r["drawings"][1]["center"], [20.0, 20.0], "with the new shape")
	r = await bridge.handle("draw", {"type": "line", "points": [[0, 0]]})
	check(r.has("error"), "a one-point line is refused")
	r = await bridge.handle("draw", {"type": "line", "space": "world", "points": [[0, 0], [1, 1]]})
	check(r.has("error"), "world points need three coordinates")
	r = await bridge.handle("clear_drawings", {})
	check_eq(r.get("removed"), 2, "clear_drawings removes everything")

	# Other layers (the call centre) add commands; they may await.
	bridge.register_command("echo_later", func(args: Dictionary) -> Dictionary:
		await process_frame
		return {"echo": args.get("x")})
	r = await bridge.handle("echo_later", {"x": 7})
	check_eq(r.get("echo"), 7, "a registered command runs, awaited")
	r = await bridge.handle("status", {})
	check((r["extensions"] as Array).has("echo_later"), "status lists registered commands")
	bridge.unregister_command("echo_later")
	r = await bridge.handle("echo_later", {})
	check(r.has("error"), "an unregistered command is unknown again")
	r = await bridge.handle("chat_say", {"text": "hello from the phone", "source": "phone"})
	check_eq(r.get("source"), "phone", "chat_say keeps an optional source")

	# Into the game.
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await frames(2)
	# These traversal fixtures use the Mandelbox independently of startup defaults.
	main.shapes().table(0).set_default(&"shape", FractalParams.Shape.MANDELBOX)
	main._resolve_once()

	r = await bridge.handle("status", {})
	check(r.get("in_game"), "status reports the open view")
	r = await bridge.handle("get_camera", {})
	check(_near(r["eye"], CameraState.DEFAULT_EYE), "get_camera reports the default eye")
	check(r["surface_distance"] > 0.0, "and a positive surface distance")
	check(_near(r["facing"], Vector3(r["forward"][0], r["forward"][1], r["forward"][2])),
		"get_camera includes the player's facing direction")
	check_eq(r["surrounding_geometry"]["ray_count"], main.params.gameplay.surrounding_ray_count,
		"get_camera includes the tunable multidirectional geometry estimate")
	main.params.gameplay.surrounding_ray_count = 20
	r = await bridge.handle("get_camera", {})
	check_eq(r["surrounding_geometry"]["ray_count"], 20, "geometry fidelity changes live with Gameplay settings")
	main.params.gameplay.surrounding_ray_count = 12

	# Recovery works when looking away and reports a miss without moving.
	var recovery_eye: PackedFloat64Array = main.camera.eye64()
	main.camera.set_basis(CameraState.facing_basis(-main.camera.forward()))
	r = await bridge.handle("find_nearest_surface", {})
	check(r.get("ok", false), "MCP can point a lost player toward the surface")
	check(main.view.center_ray().hit(), "MCP recovery actually faces a surface")
	check_eq(main.camera.eye64(), recovery_eye, "MCP recovery preserves the eye")
	check(r.get("distance", 0.0) > 0.0, "MCP reports the confirmed hit distance")
	var recovery_basis: Basis = main.camera.transform.basis
	main.params.gameplay.exit_radius = 0.000001
	main.shapes().table(0).set_default(&"pos_x", 100.0)
	main._resolve_once()
	r = await bridge.handle("find_nearest_surface", {})
	check(r.get("ok") == false and r.get("message", "").contains("No surface"),
		"MCP reports a miss honestly")
	check_eq(main.camera.transform.basis, recovery_basis, "MCP miss keeps the heading")
	main.params.gameplay.exit_radius = 20.0
	main.shapes().table(0).set_default(&"pos_x", 0.0)
	main._resolve_once()

	# set_camera: eye + look_at
	r = await bridge.handle("set_camera", {"eye": [6, 0, 0], "look_at": [0, 0, 0]})
	check(_near(r["eye"], Vector3(6, 0, 0)), "set_camera moves the eye")
	check(_near(r["forward"], Vector3(-1, 0, 0)), "and points it at look_at")

	# raycast straight ahead hits the box (it spans +/-~4 at the default shape)
	r = await bridge.handle("raycast", {})
	check(r.get("hit"), "the centre ray hits the Mandelbox")
	var hit_x: float = r["point"][0]
	check(hit_x > 0.0 and hit_x < 6.0, "between the eye and the origin (x = %s)" % hit_x)
	check(r["normal"][0] > 0.0, "with a normal facing the camera")

	# move: surface units, safe stops short of the wall
	var d0: float = (await bridge.handle("get_camera", {}))["surface_distance"]
	r = await bridge.handle("move", {"forward": 0.5})
	check_approx(r["moved"], d0 * 0.5, "move forward 0.5 covers half the surface distance", 1e-4)
	check(not r["clamped"], "a half-distance move is not clamped")
	r = await bridge.handle("move", {"forward": 1000.0})
	check(not r["clamped"] and r["moved"] > d0 * 499.0, "a move ignores raycast bounds by default")
	r = await bridge.handle("set_camera", {"eye": [6, 0, 0], "look_at": [0, 0, 0]})
	r = await bridge.handle("move", {"forward": 1000.0, "safe": true})
	check(r["clamped"], "safe movement remains available when explicitly requested")
	r = await bridge.handle("move", {"right": 1.0, "units": "world", "safe": false})
	check_approx(r["moved"], 1.0, "world units move literally")

	# rotate
	await bridge.handle("set_camera", {"eye": [6, 0, 0], "forward": [-1, 0, 0]})
	r = await bridge.handle("rotate", {"yaw": 90})
	check(_near(r["forward"], Vector3(0, -1, 0)), "yaw 90 turns left about +Z")
	r = await bridge.handle("rotate", {"pitch": 30})
	check_approx(r["forward"][2], 0.5, "pitch 30 tilts the view up")

	# dive
	await bridge.handle("set_camera", {"eye": [6, 0, 0], "look_at": [0, 0, 0]})
	r = await bridge.handle("dive", {"fraction": 0.5})
	check(not r.has("error"), "dive finds the surface")
	check_approx(r["eye"][0], (6.0 + hit_x) * 0.5, "and goes halfway to it", 1e-3)

	# animated set_camera arrives
	r = await bridge.handle("set_camera", {"eye": [7, 0, 0], "look_at": [0, 0, 0], "duration": 0.1})
	check(_near(r["eye"], Vector3(7, 0, 0)), "an animated set_camera ends at the target")

	# probe / project
	r = await bridge.handle("probe", {"point": [0, 0, 0]})
	check(r.has("distance"), "probe estimates the distance at a point")
	r = await bridge.handle("project", {"point": [0, 0, 0]})
	check(r["visible"], "the origin is in front of the camera")
	r = await bridge.handle("project", {"point": [9, 0, 0]})
	check(not r["visible"], "a point behind the camera is not")

	# shape
	r = await bridge.handle("get_shape", {})
	var ids: Array = (r["params"] as Array).map(func(p): return p["id"])
	check(ids.has("box_scale") and ids.has("color_mode"), "get_shape lists the catalogue")
	r = await bridge.handle("set_shape", {"values": {"box_scale": -1.5, "bogus": 1}})
	check_approx(r["applied"]["box_scale"], -1.5, "set_shape applies a value")
	check_eq(r.get("unknown"), ["bogus"], "and reports unknown ids")
	check_approx(main.params.active_shape().box_scale, -1.5, "straight into the active shape")
	r = await bridge.handle("set_shape", {"values": {"color_mode": 3}})
	check_eq(int(r["applied"]["color_mode"]), 3, "set_shape reaches the look table (colour mode)")

	# world drawing + trail
	r = await bridge.handle("draw", {"type": "point", "space": "world", "position": [0, 0, 0], "text": "origin"})
	r = await bridge.handle("list_drawings", {})
	check_eq((r["drawings"] as Array).size(), 2, "a labelled point is a dot and a label")
	r = await bridge.handle("trail", {"on": true})
	check(r["on"], "the trail turns on")
	await bridge.handle("move", {"forward": 0.2})
	await frames(1)
	await bridge.handle("move", {"forward": 0.2})
	await frames(1)
	r = await bridge.handle("trail", {"on": false})
	check(r["points"] >= 2, "the trail records the moves (%d points)" % r["points"])
	await bridge.handle("clear_drawings", {})

	# views
	r = await bridge.handle("list_views", {})
	check((r["views"] as Array).has("default"), "list_views finds default.json")
	r = await bridge.handle("load_view", {"name": "default"})
	check(_near(r["eye"], CameraState.DEFAULT_EYE, 1e-2), "load_view restores the saved camera")
	r = await bridge.handle("load_view", {"name": "nope"})
	check(r.has("error"), "a missing view is an error")

	main.queue_free()
	await frames(1)
