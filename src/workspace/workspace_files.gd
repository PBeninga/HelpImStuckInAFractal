class_name WorkspaceFiles
extends Node
## Which file a view is saved to or loaded from, and which one is current.
##
## It owns the two file panels and the current file's path, and nothing
## else: it never reads a save, never writes one, and knows nothing about the
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
const DEFAULT_NAME := "view.json"
const FILTER := "*.json ; Saved views"

var current_path := ""

## An optional subdirectory under the saves directory, with a trailing slash, e.g.
## "noise/". The noise editor points a second instance at saves/noise/ this way.
var subdir := ""
## Whether this instance answers the Cmd/Ctrl+S quick-save action. The view's
## instance does; the noise editor's does not (it has only a Save… panel), so two
## instances never both fire on one key press.
var quick_save_enabled := true

## The file-dialog filter. On macOS the native panel takes the text after
## "*." as an extension, so it must be a plain "*.ext" pattern: "keymap*.json"
## became the extension "keymap*.json" and mangled every name typed.
var file_filter := FILTER
## What the panels call the file ("Save view", "Load view") and the name the
## save panel offers when no file is current. The Movement pane makes them
## "keymap", so its panel cannot pass for the view's.
var noun := "view"
var default_name := DEFAULT_NAME

var _save_dialog: FileDialog
var _load_dialog: FileDialog


static func directory_for(source_build: bool) -> String:
	return REPO_DIR if source_build else EXPORT_DIR


static func directory() -> String:
	return directory_for(OS.has_feature("editor"))


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
	_ensure_subdir()
	_save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save %s" % noun)
	_save_dialog.file_selected.connect(_on_save_selected)
	_load_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Load %s" % noun)
	_load_dialog.file_selected.connect(_on_load_selected)


func _unhandled_input(event: InputEvent) -> void:
	if quick_save_enabled and event.is_action_pressed(&"workspace_quick_save"):
		quick_save()
		get_viewport().set_input_as_handled()


## This instance's directory: the saves directory plus its subdir.
func _dir() -> String:
	return directory() + subdir


func _ensure_subdir() -> Error:
	var absolute := ProjectSettings.globalize_path(_dir())
	if DirAccess.dir_exists_absolute(absolute):
		return OK
	return DirAccess.make_dir_recursive_absolute(absolute)


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
	_ensure_subdir()
	dialog.current_dir = ProjectSettings.globalize_path(_dir())
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
