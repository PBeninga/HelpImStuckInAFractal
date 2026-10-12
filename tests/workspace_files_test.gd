extends "res://tests/test_case.gd"
## WorkspaceFiles: which file a view is saved to, and which one is current.
##
## The native panels themselves cannot be driven headlessly, so the tests act
## on what a panel reports — its `file_selected` signal — and never call
## `popup()`.


func run() -> void:
	# --- where saves live ---
	check_eq(WorkspaceFiles.directory_for(true), "res://saves/",
		"a source build saves into the repo")
	check_eq(WorkspaceFiles.directory_for(false), "user://saves/",
		"an exported build falls back to user:// (res:// is read-only there)")
	check_eq(WorkspaceFiles.directory(), WorkspaceFiles.directory_for(OS.has_feature("editor")),
		"and the live directory follows the build kind")

	var files := WorkspaceFiles.new()
	root.add_child(files)
	await frames(1)

	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(WorkspaceFiles.directory())),
		"the saves directory is created if it is missing")

	# --- two panels, configured for JSON in the saves directory ---
	var save_dialog := files.save_dialog()
	var load_dialog := files.load_dialog()
	check_eq(save_dialog.file_mode, FileDialog.FILE_MODE_SAVE_FILE, "one panel saves")
	check_eq(load_dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE, "the other opens")
	# should anything open them with the tree paused, Godot's own panel must still
	# take keys and clicks then
	paused = true
	check(save_dialog.can_process() and load_dialog.can_process(),
		"both panels keep processing while the tree is paused")
	paused = false
	check(save_dialog.use_native_dialog and load_dialog.use_native_dialog,
		"both ask for the native panel")
	check_eq(save_dialog.access, FileDialog.ACCESS_FILESYSTEM,
		"which needs filesystem access")
	check_eq(load_dialog.access, FileDialog.ACCESS_FILESYSTEM,
		"on both panels")
	check(save_dialog.filters.size() == 1 and String(save_dialog.filters[0]).begins_with("*.json"),
		"the save panel filters to JSON: %s" % [save_dialog.filters])
	check(load_dialog.filters.size() == 1 and String(load_dialog.filters[0]).begins_with("*.json"),
		"and so does the open panel")

	# --- nothing is current before the first save ---
	check_eq(files.current_path, "", "no file is current at startup")
	check_eq(files.display_name(), "", "so there is no name to show")

	var saved: Array = []
	files.save_to.connect(func(p: String) -> void: saved.append(p))
	var loaded: Array = []
	files.load_from.connect(func(p: String) -> void: loaded.append(p))
	var announced: Array = []
	files.current_changed.connect(func(n: String) -> void: announced.append(n))

	# --- picking a file asks for the save; it is not current until it works ---
	save_dialog.file_selected.emit("/tmp/ice-slice.json")
	check_eq(saved, ["/tmp/ice-slice.json"], "picking a file asks to save to it")
	check_eq(files.current_path, "", "but a pick alone does not make it current")
	check_eq(announced, [], "and announces nothing")

	files.note_saved("/tmp/ice-slice.json")
	check_eq(files.current_path, "/tmp/ice-slice.json", "a save that worked makes it current")
	check_eq(files.display_name(), "ice-slice.json", "shown by name, not by path")
	check_eq(announced, ["ice-slice.json"], "and announced once")

	# --- a name typed without an extension still saves a .json ---
	save_dialog.file_selected.emit("/tmp/no-extension")
	check_eq(saved[1], "/tmp/no-extension.json", "a name with no extension gets .json")

	# --- quick save reuses the current file, with no panel ---
	check(files.quick_save(), "quick save reports that it saved")
	check_eq(saved.size(), 3, "quick save asks for one more save")
	check_eq(saved[2], "/tmp/ice-slice.json", "to the file that is current")

	check(InputMap.has_action(&"workspace_quick_save"), "the quick-save action exists")
	await press_action(&"workspace_quick_save")
	check_eq(saved.size(), 4, "and the key does the same")

	# --- loading ---
	load_dialog.file_selected.emit("/tmp/other.json")
	check_eq(loaded, ["/tmp/other.json"], "picking a file asks to load it")
	check_eq(files.current_path, "/tmp/ice-slice.json", "a pick alone does not change the current file")
	files.note_loaded("/tmp/other.json")
	check_eq(files.display_name(), "other.json", "a load that worked makes it current")
	check_eq(announced.size(), 2, "announced once more")

	# --- quick save with nothing current opens the panel instead ---
	var fresh := WorkspaceFiles.new()
	root.add_child(fresh)
	await frames(1)
	var fresh_saves: Array = []
	fresh.save_to.connect(func(p: String) -> void: fresh_saves.append(p))
	var prompts: Array = []
	fresh.prompting.connect(func() -> void: prompts.append(true))
	check(not fresh.quick_save(), "quick save with nothing current does not guess a name")
	check_eq(fresh_saves, [], "it saves nothing")
	check_eq(prompts.size(), 1, "it opens the panel, announcing it so Main can free the mouse")

	files.queue_free()
	fresh.queue_free()
	await frames(2)
