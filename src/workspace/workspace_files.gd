class_name WorkspaceFiles
extends Node
## Which file a level is saved to or loaded from, and which one is current.
##
## It owns the two file panels, the current file's path and the startup
## pointer: it never reads a save, never writes one, and knows nothing about the
## fractal, the camera or the JSON format. Picking a file emits `save_to` or
## `load_from`; whoever does the work calls `note_saved` or `note_loaded` if it
## worked, so a failed save never becomes the current file.

signal save_to(path: String)
signal load_from(path: String)
signal current_changed(display_name: String)
## A panel is about to open, so whoever owns the mouse can release it.
signal prompting

## Saves live in the repo so they can be committed. An exported build cannot
## write there — res:// is inside the read-only PCK — so it uses user://.
const REPO_DIR := "res://saves/"
const EXPORT_DIR := "user://saves/"
const DEFAULT_NAME := "level.json"
const FILTER := "*.json ; Levels"

var current_path := ""

## Whether this instance answers the Cmd/Ctrl+S quick-save action. Left on for
## the one level instance; a build that ever ran two instances turned the extra
## one off so they would not both fire on one key press.
var quick_save_enabled := true

## The file-dialog filter. On macOS the native panel takes the text after
## "*." as an extension, so it must be a plain "*.ext" pattern.
var file_filter := FILTER
## What the panels call the file ("Save level", "Load level") and the name the
## save panel offers when no file is current.
var noun := "level"
var default_name := DEFAULT_NAME

var _save_dialog: FileDialog
var _load_dialog: FileDialog


static func directory_for(source_build: bool) -> String:
	return REPO_DIR if source_build else EXPORT_DIR


static func directory() -> String:
	return directory_for(OS.has_feature("editor"))


## Source runs keep the pointer in the project root; exports need writable storage.
static func startup_pointer_path() -> String:
	var default_path := "res://last_saved.txt" if OS.has_feature("editor") else "user://last_saved.txt"
	return ProjectSettings.get_setting("application/run/last_saved_pointer", default_path)


static func last_saved_file() -> String:
	var pointer := startup_pointer_path()
	if not FileAccess.file_exists(pointer):
		return ""
	return FileAccess.get_file_as_string(pointer).strip_edges()


## Replace the pointer only after its complete contents have reached disk.
## Local paths inside the project stay portable when the checkout moves.
static func remember_saved(path: String) -> Error:
	var pointer := startup_pointer_path()
	var temporary := pointer + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(ProjectSettings.localize_path(path) + "\n")
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(pointer))
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return err


## Create the saves directory if it is missing. Returns OK when it is there.
static func ensure_directory() -> Error:
	var absolute := ProjectSettings.globalize_path(directory())
	if DirAccess.dir_exists_absolute(absolute):
		return OK
	return DirAccess.make_dir_recursive_absolute(absolute)


## Should anything open these panels while the tree is paused, Godot's own
## panel (embedded, and on the web) is a child of this node, so it must keep
## processing or it ignores every key and click.
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	ensure_directory()
	_save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save %s" % noun)
	_save_dialog.file_selected.connect(_on_save_selected)
	_load_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Load %s" % noun)
	_load_dialog.file_selected.connect(_on_load_selected)


func _unhandled_input(event: InputEvent) -> void:
	if quick_save_enabled and event.is_action_pressed(&"workspace_quick_save"):
		quick_save()
		get_viewport().set_input_as_handled()


func save_dialog() -> FileDialog:
	return _save_dialog


func load_dialog() -> FileDialog:
	return _load_dialog


## The current file's name without its directory, or "" when none is current.
func display_name() -> String:
	return current_path.get_file() if current_path != "" else ""


func prompt_save() -> void:
	_open(_save_dialog, display_name() if current_path != "" else default_name)


func prompt_load() -> void:
	_open(_load_dialog, "")


## Save over the current file with no panel. Returns false, having done
## nothing, when there is no current file to overwrite.
func quick_save() -> bool:
	if current_path == "":
		prompt_save()
		return false
	save_to.emit(current_path)
	return true


func note_saved(path: String) -> void:
	_set_current(path)


func note_loaded(path: String) -> void:
	_set_current(path)


func _make_dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	# Setting the mode replaces the title ("Open a File") unless told not to.
	dialog.mode_overrides_title = false
	dialog.title = title
	# The native panel is only used with filesystem access; the other access
	# modes fall back to Godot's own dialog.
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([file_filter])
	add_child(dialog)
	return dialog


func _open(dialog: FileDialog, file_name: String) -> void:
	ensure_directory()
	dialog.current_dir = ProjectSettings.globalize_path(directory())
	dialog.current_file = file_name
	prompting.emit()
	dialog.popup_centered_ratio(0.6)


func _on_save_selected(path: String) -> void:
	save_to.emit(_as_json_path(path))


func _on_load_selected(path: String) -> void:
	load_from.emit(path)


func _set_current(path: String) -> void:
	if path == current_path:
		return
	current_path = path
	current_changed.emit(display_name())


## A name typed into the save panel without an extension still names a save.
static func _as_json_path(path: String) -> String:
	return path if path.get_extension() != "" else path + ".json"
