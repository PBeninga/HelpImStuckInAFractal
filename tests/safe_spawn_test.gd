extends "res://tests/test_case.gd"
## Prevent the Kleinian origin trap across camera writes, old saves and stages.

var safe := PackedFloat64Array([0.5, 0.5, 0.5])

func run() -> void:
	var camera := CameraState.new()
	check_eq(camera.eye64(), safe, "a new camera never starts at the singular origin")
	check_eq(CameraState.make_default().eye64(), safe, "the default view starts at the safe position")
	camera.set_eye(1.0, 2.0, 3.0)
	camera.set_eye(0.0, 0.0, 0.0)
	check_eq(camera.eye64(), safe, "explicit zero camera positions use the safe default")
	camera.transform = Transform3D.IDENTITY
	check_eq(camera.eye64(), safe, "transform assignments cannot bypass the origin guard")
	camera.set_eye(1e-14, 0.0, 0.0)
	check_eq(camera.eye_x(), 1e-14, "nonzero deep-zoom positions retain full precision")
	camera.set_eye(1.0, 0.0, 0.0)
	camera.move_by(Vector3(-1, 0, 0))
	check_eq(camera.eye64(), safe, "moving onto the exact origin uses the safe default")

	var params := FractalParams.new()
	params.gameplay.return_to_spawn(camera)
	check_eq(camera.eye64(), safe, "default Return to spawn is safe")
	var shapes := ShapeList.new(2)
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var keys := Keymap.new()
	var snapshot := Workspace.capture(shapes, look, keys, params, camera)
	snapshot["gameplay"] = {"spawn_x": 0.0, "spawn_y": 0.0, "spawn_z": 0.0}
	snapshot["camera"] = {"eye": [0.0, 0.0, 0.0], "forward": [1, 0, 0], "up": [0, 0, 1]}
	check_eq(Workspace.restore(snapshot, shapes, look, keys, params, camera), [], "legacy zero spawn loads cleanly")
	params.gameplay.return_to_spawn(camera)
	check_eq(camera.eye64(), safe, "legacy zero spawn cannot restore the trap")
	var saved := params.gameplay.to_dict()
	check_eq([saved.spawn_x, saved.spawn_y, saved.spawn_z], [0.5, 0.5, 0.5], "resaving persists the safe spawn")
	# Direct edits must keep the run's boundary and its return position aligned.
	params.gameplay.spawn_x = 0.0
	params.gameplay.spawn_y = 0.0
	params.gameplay.spawn_z = 0.0
	var run := ShapeRun.new(shapes, params, camera)
	run.reset()
	check_eq(params.run_origin, [0.5, 0.5, 0.5], "the run uses the safe origin even after zero spawn edits")
	camera.set_eye(30.0, 0.5, 0.5)
	run.check_position()
	run.step(1.0)
	check_eq(params.gameplay_active, 1, "crossing the boundary advances the stage")
	check_eq(camera.eye64(), safe, "stage transitions return to the safe origin")

	# The user-visible regression: WASD can leave the default Kleinian spawn.
	params.gameplay_active = 0
	params.shape(0).shape = FractalParams.Shape.KLEINIAN
	camera.set_basis(CameraState.make_default().transform.basis)
	var fly := FlyCamera.new()
	fly.setup(params, camera)
	fly.enabled = true
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		params.gameplay.return_to_spawn(camera)
		var before := camera.eye64()
		check(fly.current_speed() > 0.001, "default spawn has usable flight speed")
		Input.action_press(action)
		fly._step_movement(1.0 / 60.0)
		Input.action_release(action)
		check(camera.eye64() != before and not fly.at_zoom_limit, action + " moves from the default spawn")
	fly.free()
