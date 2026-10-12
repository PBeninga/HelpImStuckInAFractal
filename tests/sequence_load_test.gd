extends "res://tests/test_case.gd"
## End-screen saves describe a fresh sequence, never a live player checkpoint.

const SAVE := "user://sequence_load_test.json"

func run() -> void:
	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	main.params.gameplay.spawn_x = 1.2345678901234
	main.params.gameplay.spawn_y = -2.0
	main.params.gameplay.spawn_z = 3.0
	main.params.gameplay.distance_scaling = false
	main.params.gameplay.move_speed = 2.0
	main.add_shape()
	main.shapes().set_stage(0, 1.0, ["size 2"])
	main.shapes().set_stage(1, 2.0, [])
	main.save_level_to(SAVE)
	main.camera.set_eye(100.0, 0.0, 0.0)
	main.shape_run.check_position()
	main.shape_run.step(1.0)
	main.shape_run.step(0.0)
	main.shape_run.step(1.0)
	main.camera.set_eye(100.0, 0.0, 0.0)
	main.shape_run.check_position()
	check(main.view.is_escaped(), "the final shape reaches the end screen")
	main.camera.speed_factor = 7.0
	main.params.camera_mode = FractalParams.CameraMode.ORBIT
	main.shapes().table(0).set_default(&"fold_limit", 0.73)
	var save := InputEventKey.new()
	save.keycode = KEY_S
	save.physical_keycode = KEY_S
	save.meta_pressed = true
	save.pressed = true
	root.push_input(save)
	await frames(1)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check_eq(data.shapes[0].defaults.fold_limit, 0.73, "Cmd+S writes edits from the end screen")
	check(not data.has("camera"), "the file contains no live camera position, facing or speed")
	check(main.view.is_escaped(), "saving leaves the end screen active")
	main.load_level_from(SAVE)
	_check_start(main)
	# Older saves' checkpoint fields must also be ignored, including orbit mode.
	data["version"] = 5
	data["camera"] = {"eye": [100, 200, 300], "forward": [1, 0, 0], "up": [0, 0, 1], "speed_factor": 99}
	data["fractal"]["camera_mode"] = "orbit"
	data["active"] = 1
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", false, true))
	file.close()
	main.queue_free()
	await frames(1)
	main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	_check_start(main)
	main.queue_free()
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

func _check_start(main: Node) -> void:
	check_eq(main.params.gameplay_active, 0, "loading begins at the first gameplay shape")
	check_eq(main.params.active, 0, "the editor also selects the first shape")
	check_eq(main.camera.eye64(), PackedFloat64Array([1.2345678901234, -2.0, 3.0]), "loading uses the authored spawn at full precision")
	check_eq(main.camera.speed_factor, 1.0, "loading resets the wheel speed")
	check_eq(main.params.camera_mode, FractalParams.CameraMode.FLY, "loading starts in fly mode")
	check(main.camera.transform.basis.is_equal_approx(CameraState.make_default().transform.basis), "loading restores the starting facing")
	check_eq(main.params.gameplay.move_speed, 2.0, "authored flight tuning survives")
	check(not main.view.is_escaped() and not main.shape_run.transitioning(), "loading clears completion and transition state")
	check(not main.fly.movement_locked, "loading unlocks travel")
	check(main._axis_controller.is_processing(), "loading restores shape controls")
