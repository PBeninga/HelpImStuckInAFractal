class_name NoiseWindow
extends Window
## The embedded window that hosts the NoiseEditor. It owns the one NoiseGraph,
## hands it to the editor and to the FractalView, and turns the editor's toolbar
## signals into graph edits and graph-only saves/loads in saves/noise/.
##
## Unlike the console it is embedded in the main window (dragged by its title
## bar, closed with its ✕, drawn above the view). Main owns it: it opens and closes it
## (the N key and the console View tab's Noise editor… button), and reads its graph
## for a view save.
##
## W, A, S or D pressed here (outside a text edit; see TextFocus.is_game_key)
## asks for the game (`game_focus_requested`): Main closes the window and
## recaptures the mouse, as a click in the view does. A spin box commits what
## was typed into it and the letter is not typed.

## In points (logical units); UiScale.px turns them into window pixels.
const DEFAULT_SIZE := Vector2i(1100, 700)
const MIN_SIZE := Vector2i(500, 360)

## A key this window left unhandled (a Ctrl tap, Cmd+S…). Showing an embedded
## window gives it keyboard focus, and a focused window keeps keys from the main
## window, so Main runs these through its own dispatch.
signal unhandled_key(event: InputEventKey)
## W, A, S or D was pressed here outside a text edit: back to the game.
signal game_focus_requested

var _view: FractalView
var _editor: NoiseEditor
var _files: WorkspaceFiles
var _graph: NoiseGraph


static func _resolver() -> Callable:
	return Callable(NoiseNodeRegistry, "type_by_id")


func setup(view: FractalView) -> void:
	_view = view
	title = "Noise field"
	unresizable = false
	UiScale.apply(self)
	size = UiScale.px(DEFAULT_SIZE, self)
	min_size = UiScale.px(MIN_SIZE, self)
	visible = false
	wrap_controls = false
	close_requested.connect(close)

	_editor = NoiseEditor.new()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)

	_files = WorkspaceFiles.new()
	_files.name = "NoiseFiles"
	_files.subdir = "noise/"
	_files.quick_save_enabled = false
	add_child(_files)
	_files.save_to.connect(_save_graph_to)
	_files.load_from.connect(_load_graph_from)

	_editor.add_node_requested.connect(_on_add_node_requested)
	_editor.new_requested.connect(_on_new_requested)
	_editor.save_requested.connect(_files.prompt_save)
	_editor.load_requested.connect(_files.prompt_load)

	if not _view.noise_status.is_connected(_on_view_status):
		_view.noise_status.connect(_on_view_status)

	_apply_graph(NoiseGraph.default_graph(_resolver()))


func editor() -> NoiseEditor:
	return _editor


func graph() -> NoiseGraph:
	return _graph


func workspace_files() -> WorkspaceFiles:
	return _files


## This graph as a dict, for embedding under a view save's "noise" key.
func to_dict() -> Dictionary:
	return _graph.to_dict() if _graph != null else {}


## Replace the graph from a dict (a view's "noise" section). Returns warnings.
func apply_dict(d: Dictionary) -> Array:
	var warnings: Array = []
	var g := NoiseGraph.from_dict(d, warnings, _resolver())
	_apply_graph(g)
	return warnings


func open() -> void:
	UiScale.center_over(self, _parent_window())
	visible = true
	# No grab_focus(): showing an embedded window focuses it already. While it
	# holds focus, N and Escape close it (_unhandled_input below) and every other
	# key reaches Main through unhandled_key. A click on the view takes focus back.


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


# WASD is caught before the GUI, so a focused spin box cannot type it.
func _input(event: InputEvent) -> void:
	if visible and TextFocus.is_game_key(event, self):
		gui_release_focus()   # a spin box applies its text as it loses focus
		set_input_as_handled()
		game_focus_requested.emit()


## While this window holds keyboard focus, N and Escape close it
## (close_requested is emitted so Main recaptures the mouse); any other key it
## did not use goes on to Main.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"toggle_noise_editor") or event.is_action_pressed(&"cancel"):
		close_requested.emit()
		set_input_as_handled()
	elif event is InputEventKey:
		unhandled_key.emit(event)


## The window this one opens over (the main window), or null before it is added.
func _parent_window() -> Window:
	var parent := get_parent()
	return parent.get_window() if parent != null else null


# --------------------------------------------------------------- wiring

func _apply_graph(g: NoiseGraph) -> void:
	_graph = g
	_editor.show_graph(_graph)
	if _view != null:
		_view.set_noise_graph(_graph)


func _on_add_node_requested(type_id: StringName, at: Vector2) -> void:
	if _graph != null:
		_graph.add_node(type_id, at)


func _on_new_requested() -> void:
	_apply_graph(NoiseGraph.default_graph(_resolver()))
	_editor.set_status("New field")


func _on_view_status(text: String) -> void:
	if text != "":
		_editor.set_status(text)


func _save_graph_to(path: String) -> void:
	var err := Workspace.save_noise_file(path, _graph.to_dict())
	if err != OK:
		_editor.set_status("Save failed (error %d)" % err)
		return
	_files.note_saved(path)
	_editor.set_status("Saved %s" % path.get_file())


func _load_graph_from(path: String) -> void:
	var result := Workspace.load_noise_file(path)
	if not result["ok"]:
		_editor.set_status("Load failed: %s" % result["warnings"][0])
		return
	var warnings := apply_dict(result["noise"])
	_files.note_loaded(path)
	if warnings.is_empty():
		_editor.set_status("Loaded %s" % path.get_file())
	else:
		_editor.set_status("Loaded %s with %d warning(s)" % [path.get_file(), warnings.size()])
