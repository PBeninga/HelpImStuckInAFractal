extends "res://tests/test_case.gd"
## Exercise elapsed-time fades, render gating, independent timing and resets.


func run() -> void:
	var params := FractalParams.new()
	var game := params.gameplay
	check(game.exit_skybox != null, "old and new levels have the bundled sky by default")
	var warnings := game.apply_dict({"escape_sky_duration": 2.0, "escape_fog_duration": 4.0})
	check_eq(warnings, [], "escape timing loads from a level")
	if not warnings.is_empty():
		return
	var restored := GameplaySettings.new()
	restored.apply_dict(game.to_dict())
	check_eq(restored.get("escape_sky_duration"), 2.0, "sky duration survives saving")
	check_eq(restored.get("escape_fog_duration"), 4.0, "fog duration survives saving independently")
	check_eq(restored.apply_dict({"escape_sky_duration": -1, "escape_fog_duration": INF}).size(), 2,
		"negative and nonfinite durations are rejected")
	check_eq(restored.apply_dict({"escape_sky_duration": 0, "escape_fog_duration": 0}), [],
		"zero durations are valid instant transitions")
	params.fog_distance = 60.0
	var camera := CameraState.make_default()
	camera.set_eye(0.0, 0.0, 0.0)
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	view.setup(params, camera)
	await frames(1)
	view.set_process(false)
	var mat := view._material
	check_eq(mat.get_shader_parameter("exit_has_skybox"), false, "sky sampling is off inside")
	camera.set_eye(21.0, 0.0, 0.0)
	check_eq(mat.get_shader_parameter("exit_has_skybox"), false, "sky sampling stays off at zero opacity")
	view._process(1.0)
	check_eq(mat.get_shader_parameter("exit_has_skybox"), true, "escape starts sky sampling")
	check_approx(mat.get_shader_parameter("exit_sky_alpha"), 0.5, "sky is halfway after half its duration")
	var partial_fog: float = mat.get_shader_parameter("escape_fog_clear")
	check(partial_fog > 0.0 and partial_fog < 0.5, "fog follows its separate, slower duration")
	camera.set_eye(22.0, 0.0, 0.0)
	view._process(1.0)
	check_approx(mat.get_shader_parameter("exit_sky_alpha"), 1.0, "moving outside does not restart the fade")
	check_approx(mat.get_shader_parameter("escape_fog_clear"), 0.5, "fog is halfway at two seconds")
	view.set_load_level(3)
	view._process(2.0)
	check_approx(mat.get_shader_parameter("fog_distance"), 0.0, "manual fog is fully disabled at completion")
	check_approx(mat.get_shader_parameter("fog_dist"), 0.0, "performance fog also clears on escape")
	check_eq(mat.get_shader_parameter("exit_has_skybox"), true, "sky remains visible after its fade")
	check_approx(params.fog_distance, 60.0, "animation preserves the saved fog setting")
	camera.set_eye(0.0, 0.0, 0.0)
	check_eq(mat.get_shader_parameter("exit_has_skybox"), false, "reentry stops sky sampling immediately")
	check_approx(mat.get_shader_parameter("fog_distance"), 60.0, "reentry restores the manual fog")
	check(float(mat.get_shader_parameter("fog_dist")) > 0.0, "reentry restores the load shedder fog")
	game.set("escape_sky_duration", 0.0)
	game.set("escape_fog_duration", 0.0)
	camera.set_eye(21.0, 0.0, 0.0)
	check_approx(mat.get_shader_parameter("exit_sky_alpha"), 1.0, "zero sky duration completes immediately")
	check_approx(mat.get_shader_parameter("fog_distance"), 0.0, "zero fog duration clears immediately")
	view.queue_free()
	await frames(1)
