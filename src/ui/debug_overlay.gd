class_name DebugOverlay
extends CanvasLayer
## Shared global shortcut and panel behavior for diagnostic overlays.

var shortcut_key: Key = KEY_F3
var shortcut_name := "PerformanceShortcut"

var panel: PanelContainer
var readout: Label


func _ready() -> void:
	layer = 1023
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	panel = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.065, 1.0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	readout = Label.new()
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	readout.add_theme_font_size_override("font_size", 16)
	panel.add_child(readout)
	visibility_changed.connect(_visibility_changed)
	_watch_windows(get_tree().root)
	get_tree().node_added.connect(_watch_window)


func _watch_windows(node: Node) -> void:
	_watch_window(node)
	for child in node.get_children():
		_watch_windows(child)


func _watch_window(node: Node) -> void:
	if node is Window:
		# A transient popup may be freed before this deferred call gets its turn.
		_add_shortcut.call_deferred(node.get_instance_id())


func _add_shortcut(window_id: int) -> void:
	var window := instance_from_id(window_id) as Window
	if window == null or not window.is_inside_tree():
		return
	var shortcut := preload("res://src/ui/window_shortcut.gd").new()
	shortcut.name = shortcut_name
	shortcut.shortcut_key = shortcut_key
	shortcut.process_mode = Node.PROCESS_MODE_ALWAYS
	shortcut.toggle = func() -> void: visible = not visible
	window.add_child(shortcut)


func _visibility_changed() -> void:
	set_process(visible)
