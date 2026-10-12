extends "res://tests/test_case.gd"
## Successful saves choose the next startup file; ordinary loads do not.

const POINTER_SETTING := "application/run/last_saved_pointer"
const SETTINGS := "user://default_level_test_settings.cfg"
const SAVED := "user://default_level_test_saved.json"
const SECOND := "user://default_level_test_second.json"
const INVALID := "user://default_level_test_invalid.json"


func run() -> void:
	root.get_node("Settings").config_path = SETTINGS
	var pointer: String = ProjectSettings.get_setting(POINTER_SETTING)
	check_eq(WorkspaceFiles.remember_saved(ProjectSettings.globalize_path("res://saves/noiseRidges.json")), OK,
		"an absolute path from the file dialog can be remembered")
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), "res://saves/noiseRidges.json",
		"a save inside the project is recorded as a portable resource path")
	_write(pointer, "res://saves/noiseRidges.json\n")
	var main = await _start()
	check_eq(main.workspace_files().current_path, "res://saves/noiseRidges.json",
		"startup follows the pointer file")
	check_eq(main.noise_window().to_dict().get("nodes", []).size(), 4,
		"startup restores the pointed-to level's noise graph")

	main.params.max_steps = 137
	main.save_level_to(SAVED)
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), SAVED,
		"a successful save updates the persistent pointer")
	main.load_level_from("res://saves/default.json")
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), SAVED,
		"loading another file does not replace the most recently saved file")
	main.save_level_to("user://missing_startup_test_dir/cannot_save.json")
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), SAVED,
		"a failed save leaves the pointer alone")
	main.queue_free()
	await frames(1)

	main = await _start()
	check_eq(main.workspace_files().current_path, SAVED, "a new session reopens the most recent save")
	check_eq(main.params.max_steps, 137, "the reopened file restores the saved content")
	main.save_level_to(SECOND)
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), SECOND,
		"saving a second file replaces the previous pointer")
	main.load_level_from(SAVED)
	main.workspace_files().quick_save()
	check_eq(FileAccess.get_file_as_string(pointer).strip_edges(), SAVED,
		"quick-saving an older file makes it the latest save")

	# A pointer write failure must not claim that saving the level failed.
	ProjectSettings.set_setting(POINTER_SETTING, "user://missing_startup_test_dir/last_saved.txt")
	main.save_level_to(SECOND)
	check_eq(main.workspace_files().current_path, SECOND, "the level still saves if the pointer cannot be written")
	check(main.gameplay_pane().status_label.text.contains("startup pointer"),
		"a pointer write failure is reported separately")
	ProjectSettings.set_setting(POINTER_SETTING, pointer)
	main.queue_free()
	await frames(1)

	_write(INVALID, "not valid JSON")
	for path in ["res://saves/no_such_startup_level.json", INVALID, ""]:
		_write(pointer, path + "\n")
		main = await _start()
		check_eq(main.workspace_files().current_path, "", "unavailable or empty pointer target leaves no current file")
		check_eq(main.shapes().count(), 1, "unavailable or empty pointer target keeps the built-in scene")
		if path != "":
			check(main.gameplay_pane().status_label.text.begins_with("Load failed:"),
				"an unavailable target reports its load failure")
		main.queue_free()
		await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pointer))
	main = await _start()
	check_eq(main.workspace_files().current_path, "", "a missing pointer starts an unsaved scene")
	main.queue_free()
	await frames(1)
	for path in [INVALID, SAVED, SECOND, SETTINGS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _start() -> Node:
	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	return main


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
