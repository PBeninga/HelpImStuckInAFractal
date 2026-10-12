extends "res://tests/test_case.gd"
## Startup reads the shared project setting and uses the ordinary level loader.

const SETTING := "application/run/default_level"
const SETTINGS := "user://default_level_test_settings.cfg"
const INVALID := "user://default_level_test_invalid.json"


func run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.config_path = SETTINGS
	var config := ConfigFile.new()
	check_eq(config.load("res://project.godot"), OK, "the shared config can be read")
	var opening: String = config.get_value("application", "run/default_level", "")
	check(opening.begins_with("res://") and FileAccess.file_exists(opening),
		"the shared default points to a bundled level with a portable path")
	ProjectSettings.set_setting(SETTING, opening)
	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	check_eq(main.workspace_files().current_path, opening, "startup loads the configured level")
	check_eq(main.shapes().count(), 3, "the opening level restores all three nested shapes")
	check_eq(main.params.active, 2, "the inner shape is selected")
	check_approx(main.camera.eye_x(), 1.48976235910998, "the saved camera x is restored", 1e-12)
	check_approx(main.camera.eye_y(), -0.0659666560822639, "the saved camera y is restored", 1e-12)
	check_approx(main.camera.eye_z(), -1.30366939645594, "the saved camera z is restored", 1e-12)
	check_eq(main.gameplay_pane().file_label.text, opening.get_file(), "Gameplay shows the opening file")
	main.queue_free()
	await frames(1)

	# A different pointer must load that level, including its noise graph.
	ProjectSettings.set_setting(SETTING, "res://saves/noiseRidges.json")
	main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	check_eq(main.workspace_files().current_path, "res://saves/noiseRidges.json",
		"changing the setting changes the opening level")
	check_eq(main.noise_window().to_dict().get("nodes", []).size(), 4,
		"startup restores the level's four noise nodes")
	main.queue_free()
	await frames(1)

	var invalid := FileAccess.open(INVALID, FileAccess.WRITE)
	invalid.store_string("not valid JSON")
	invalid.close()
	for path in ["res://saves/no_such_startup_level.json", INVALID, ""]:
		ProjectSettings.set_setting(SETTING, path)
		main = load("res://src/main.tscn").instantiate()
		root.add_child(main)
		await frames(2)
		check_eq(main.workspace_files().current_path, "", "unavailable or empty default leaves no current file")
		check_eq(main.shapes().count(), 1, "unavailable or empty default keeps the built-in scene")
		if path != "":
			check(main.gameplay_pane().status_label.text.begins_with("Load failed:"),
				"an unavailable default reports its load failure")
		main.queue_free()
		await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INVALID))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
