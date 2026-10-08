class_name ConsoleWindow
extends Window
## The console ("Fractacular embedded") for the one Mandelbox shape being flown
## through in the main window: the Shape inspector stacked above the Movement
## pane in a VSplit. Stacked, the inspector gets the full width, so its sliders
## have room (side by side, the two panes' minimum widths overflowed the
## window); the Movement pane keeps its natural height (a line per axis and a
## few readouts) and the inspector takes the rest.
##
## It is a separate, native OS window (force_native, though the project embeds
## its other sub-windows): it can be dragged anywhere, onto another monitor too.
## Headless and the web have no native sub-windows, so there it falls back to a
## window embedded in the main one. A native window overlapping the main window
## corrupts the main window's picture on macOS, so open() places it beside the
## main window, never over it. A Ctrl tap in this window forwards
## `toggle_requested`; other keys go to `unhandled_key`.

signal toggle_requested
## A key this window's controls left unhandled (Escape, N, Cmd+S…). Showing the
## window gives it keyboard focus, and a focused window keeps keys from the main
## window, so Main runs these through its own dispatch.
signal unhandled_key(event: InputEventKey)

## In points (logical units); UiScale.px turns them into window pixels.
const DEFAULT_SIZE := Vector2i(1000, 700)
const MIN_SIZE := Vector2i(700, 400)

var _inspector: AttributeInspector
var _movement: MovementPane
var _keymap: Keymap
var _ctrl := CtrlTap.new()


func setup(table: AttributeTable, keymap: Keymap, clock: Clock, group_tooltips: Dictionary, speed_source: Callable = Callable()) -> void:
	_keymap = keymap
	title = "Console"
	visible = false   # force_native cannot change while a window is shown
	force_native = true
	UiScale.apply(self)
	size = UiScale.px(DEFAULT_SIZE, self)
	min_size = UiScale.px(MIN_SIZE, self)
	unresizable = false
	wrap_controls = false
	close_requested.connect(hide_console)

	var split := VSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	_inspector = AttributeInspector.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_inspector)
	_inspector.setup(table, group_tooltips)

	_movement = MovementPane.new()
	_movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_movement.size_flags_vertical = Control.SIZE_FILL
	_movement.setup(keymap, clock, speed_source)
	split.add_child(_movement)

	_ctrl.typing_guard = func() -> bool: return TextFocus.any([self])
	if keymap != null:
		keymap.changed.connect(_refresh_sources)
	_refresh_sources()


func inspector() -> AttributeInspector:
	return _inspector


func movement_pane() -> MovementPane:
	return _movement


## Feed one frame of resolved values to the Shape rows' readouts.
## The governor's load-shed level, shown in the Movement pane.
func show_shed_level(level: int) -> void:
	_movement.show_shed_level(level)


func set_resolved(values: Dictionary) -> void:
	if _inspector != null:
		_inspector.set_resolved(values)


func open() -> void:
	UiScale.place_beside(self, _parent_window())
	visible = true


func hide_console() -> void:
	visible = false


func toggle() -> void:
	if visible:
		hide_console()
	else:
		open()


## Feed a key event to the Ctrl-tap detector (also used directly by tests).
## Returns true when a tap fired.
func feed_ctrl(event: InputEvent) -> bool:
	if _ctrl.feed(event):
		toggle_requested.emit()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if feed_ctrl(event):
		set_input_as_handled()
		return
	# Ctrl itself stays here: this window's own detector owns the tap.
	if event is InputEventKey and (event as InputEventKey).physical_keycode != KEY_CTRL:
		unhandled_key.emit(event)


func _refresh_sources() -> void:
	if _inspector == null or _keymap == null:
		return
	var axis_list: Array = []
	for axis in _keymap.axes().list():
		axis_list.append({"id": axis.id, "label": axis.label})
	_inspector.set_sources(axis_list)


## The window this one opens beside (the main window), or null before it is added.
func _parent_window() -> Window:
	var parent := get_parent()
	return parent.get_window() if parent != null else null
