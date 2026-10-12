extends "res://tests/test_case.gd"
## Radius comparisons, tunable movement, save compatibility and the real HUD.


func run() -> void:
	var params := FractalParams.new()
	var game: Variant = params.get("gameplay")
	check(game != null, "each level has gameplay settings")
	if game == null:
		return
	check_eq(game.spawn_x, 0.5, "spawn defaults to the safe position")
	check_eq(params.next_level_threshold, 20.0, "the exit sphere defaults to radius 20")
	check_eq(game.surrounding_ray_count, 12, "surrounding geometry defaults to a low-fidelity 12-ray sweep")
	var camera := CameraState.make_default()
	camera.set_eye(20.0, 0.0, 0.0)
	check(not params.is_escaped(camera), "on the boundary is still inside")
	camera.set_eye(20.0 + 1e-10, 0.0, 0.0)
	check(params.is_escaped(camera), "crossing the radius uses the 64-bit eye")
	camera.set_eye(-12.0, -16.0, 0.0)
	check(not params.is_escaped(camera), "the boundary is spherical in every direction")
	params.next_level_threshold = 19.0
	check(params.is_escaped(camera), "editing the radius updates escape detection")
	game.surrounding_ray_count = 24

	var fly := FlyCamera.new()
	fly.setup(params, camera)
	var initial := fly.base_speed()
	game.move_speed = 3.0
	check_approx(fly.base_speed(), initial * 3.0, "movement speed scales actual travel")
	fly.sprinting = true
	game.shift_multiplier = 4.0
	check_approx(fly.current_speed(), fly.base_speed() * 4.0, "Shift uses its editable multiplier")
	game.distance_scaling = false
	check_approx(fly.base_speed(), 3.0, "disabling distance scaling gives fixed speed")
	game.distance_scaling = true
	game.distance_power = 0.5
	check_approx(fly.base_speed(), sqrt(initial) * 3.0, "distance power tunes the camera-ray response")
	fly.free()

	game.spawn_x = 1.23456789012345
	game.spawn_y = -2.0
	game.spawn_z = 3.0
	var shapes := ShapeList.new()
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var keys := Keymap.new()
	var snapshot := Workspace.capture(shapes, look, keys, params, camera)
	check(snapshot.has("gameplay"), "level saves include gameplay")
	var restored := FractalParams.new()
	var warnings := Workspace.restore(snapshot, shapes, look, keys, restored, camera)
	check(warnings.is_empty(), "gameplay loads cleanly")
	check_eq(restored.get("gameplay").to_dict(), game.to_dict(), "all gameplay settings round-trip at full precision")
	snapshot.erase("gameplay")
	Workspace.restore(snapshot, shapes, look, keys, restored, camera)
	check_eq(restored.gameplay.spawn_x, 0.5, "older levels restore default gameplay rather than inheriting another level")
	var hidden := FractalParams.new()
	hidden.shape().pos_x = 30.0
	check(DistanceEstimator.scene_bounds(25.0, 0.0, 0.0, Vector3.RIGHT, hidden) == null,
		"CPU rays ignore geometry behind the exit sphere's background")
	check(not CenterRay.march(Vector3(25, 0, 0), Vector3.RIGHT, hidden)[1],
		"the camera ray cannot select an invisible shape beyond the sphere")
	var malformed: Array = game.apply_dict({"exit_radius": -2, "spawn_x": INF, "distance_power": {}, "distance_scaling": "yes", "surrounding_ray_count": 2})
	check_eq(malformed.size(), 4, "malformed gameplay fields are rejected individually")
	check(not game.to_dict().has("exit_radius"), "obsolete exit radius is not saved")

	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	var pane = main.gameplay_pane()
	check(not pane.controls.has(&"exit_radius"), "Gameplay has no separate exit radius control")
	check_eq(main.console().tabs().get_tab_title(4), "Gameplay", "Gameplay is a console tab")
	main.shapes().set_stage(0, 5.0, [])
	main.camera.set_eye(6.0, 0.0, 0.0)
	await frames(1)
	check(main.find_child("EscapeMessage", true, false) == null, "escaping no longer displays a text HUD")
	pane.return_button.pressed.emit()
	check_eq(main.camera.eye64(), PackedFloat64Array([0.5, 0.5, 0.5]), "Return to spawn uses the safe default")
	check_eq(main.view._material.get_shader_parameter("exit_has_skybox"), false, "returning to spawn disables sky sampling immediately")
	main.params.gameplay.spawn_x = 1.23456789012345
	main.params.gameplay.spawn_y = -2.0
	main.params.gameplay.spawn_z = 3.0
	pane.return_button.pressed.emit()
	check_eq(main.camera.eye_x(), 1.23456789012345, "Return to spawn keeps full precision")
	check_eq(main.camera.eye_y(), -2.0, "and the configured Y")
	check_eq(main.camera.eye_z(), 3.0, "and the configured Z")
	var path := "user://gameplay_test_level.json"
	main.save_level_to(path)
	main.params.gameplay.spawn_x = 99.0
	main.shapes().set_stage(0, 100.0, [])
	main.load_level_from(path)
	check_approx(main.params.gameplay.spawn_x, 1.23456789012345, "spawn round-trips through the real level file", 1e-14)
	check_eq(main.shapes().entry(0).next_level_distance, 5.0, "the real file restores the shape escape distance")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var mat: ShaderMaterial = main.view.get_node("SubViewport/ColorRect").material
	check_eq(mat.get_shader_parameter("exit_radius"), 20.0, "gameplay distance does not change the rendering sphere")
	var image := Image.create(2, 1, false, Image.FORMAT_RGB8)
	var sky := ImageTexture.create_from_image(image)
	main.params.gameplay.exit_skybox = sky
	check(mat.get_shader_parameter("exit_skybox") == sky, "an optional sky texture reaches the sphere material")
	check_eq(mat.get_shader_parameter("exit_has_skybox"), false, "assigning a texture inside the boundary does not enable sky sampling")
	main.queue_free()
	await frames(1)
