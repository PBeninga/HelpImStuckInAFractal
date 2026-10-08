class_name ConsoleWindow
extends Window
## The console ("Fractacular embedded") for the one Mandelbox shape being flown
## through in the main window: three tabs stacked above the Movement pane in a
## VSplit. The Shape tab is the inspector for the Box, Julia, Iteration rotation
## and Render groups; the Colour tab is Fractacular's Colour window (the cosine
## palette's sliders, curves and strip) above the Colour, Lighting and Palette
## rows, in one scrolling list; the View tab is Save / Load view, the camera
## mode, the mouse sensitivity, the Noise editor button, the Renderer options
## and Back to Menu. Stacked, the tabs get the full width, so the sliders have
## room (side by side, the panes' minimum widths overflowed the
## window); the Movement pane keeps its natural height (a line per axis and a
## few readouts) and the tabs take the rest.
##
## It is a separate, native OS window (force_native, though the project embeds
## its other sub-windows): it can be dragged anywhere, onto another monitor too.
## Headless and the web have no native sub-windows, so there it falls back to a
## window embedded in the main one. A native window overlapping the main window
## corrupts the main window's picture on macOS, so open() places it beside the
## main window, never over it. A Ctrl tap in this window forwards
## `toggle_requested`; other keys go to `unhandled_key`.
##
## Cmd+= / Cmd+- (Ctrl on other platforms) zoom everything in the window, text
## and controls alike, through its content scale, as a browser zooms a page;
## Cmd+0 resets. The window keeps its size and the panes reflow. `zoom_changed`
## lets Main keep the level in Settings.

signal toggle_requested
## A key this window's controls left unhandled (Escape, N, Cmd+S…). Showing the
## window gives it keyboard focus, and a focused window keeps keys from the main
## window, so Main runs these through its own dispatch.
signal unhandled_key(event: InputEventKey)
## The zoom level changed (by a key or set_zoom()).
signal zoom_changed(zoom: float)
## The Movement pane's Reset camera button was pressed.
signal reset_camera_requested

## In points (logical units); UiScale.px turns them into window pixels.
const DEFAULT_SIZE := Vector2i(1000, 700)
const MIN_SIZE := Vector2i(700, 400)
## The zoom levels Cmd+= and Cmd+- step through, browser style.
const ZOOM_STEPS: Array[float] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

## Multiplies UiScale's factor for this window; 1 is the default size.
var zoom := 1.0

var _tabs: TabContainer
var _inspector: AttributeInspector
var _colour_inspector: AttributeInspector
var _palette: Palette
var _palette_window: PaletteWindow
var _movement: MovementPane
var _view: ViewPane
var _keymap: Keymap
var _ctrl := CtrlTap.new()


func setup(table: AttributeTable, keymap: Keymap, clock: Clock, group_tooltips: Dictionary, speed_source: Callable = Callable()) -> void:
	_keymap = keymap
	title = "Console"
	visible = false   # force_native cannot change while a window is shown
	force_native = true
	UiScale.apply(self)
	_apply_zoom()
	size = UiScale.px(DEFAULT_SIZE, self)
	min_size = UiScale.px(MIN_SIZE, self)
	unresizable = false
	wrap_controls = false
	close_requested.connect(hide_console)

	var split := VSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	split.add_child(_tabs)

	_inspector = AttributeInspector.new()
	_inspector.name = "Shape"
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_inspector)
	_inspector.setup(table, group_tooltips, MandelboxShape.SHAPE_GROUPS)

	_palette = Palette.new(table)
	_palette_window = PaletteWindow.new()
	_palette_window.setup(_palette)
	_palette_window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colour_inspector = AttributeInspector.new()
	_colour_inspector.name = "Colour"
	_colour_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colour_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_colour_inspector)
	_colour_inspector.setup(table, group_tooltips, MandelboxShape.COLOUR_GROUPS, _palette_window)

	_view = ViewPane.new()
	_tabs.add_child(_view)

	_movement = MovementPane.new()
	_movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_movement.size_flags_vertical = Control.SIZE_FILL
	_movement.setup(keymap, clock, speed_source)
	_movement.reset_camera_requested.connect(reset_camera_requested.emit)
	split.add_child(_movement)

	_ctrl.typing_guard = func() -> bool: return TextFocus.any([self])
	if keymap != null:
		keymap.changed.connect(_refresh_sources)
	_refresh_sources()


## The Shape tab's inspector (Box, Julia, Iteration rotation, Render).
func inspector() -> AttributeInspector:
	return _inspector


## The Colour tab's inspector (Colour, Lighting, Palette), under the palette window.
func colour_inspector() -> AttributeInspector:
	return _colour_inspector


func palette_window() -> PaletteWindow:
	return _palette_window


func palette() -> Palette:
	return _palette


func tabs() -> TabContainer:
	return _tabs


## The View tab: files, camera mode, noise editor, renderer, Back to Menu.
func view_pane() -> ViewPane:
	return _view


## Bring the Shape (0), Colour (1) or View (2) tab to the front.
func show_tab(index: int) -> void:
	_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func movement_pane() -> MovementPane:
	return _movement


## The governor's load-shed level, shown in the Movement pane.
func show_shed_level(level: int) -> void:
	_movement.show_shed_level(level)


## Whether the fly camera is held at the zoom floor, shown in the Movement pane.
func show_zoom_limit(on: bool) -> void:
	_movement.show_zoom_limit(on)


## Feed one frame of resolved values to both tabs' readouts and the palette's
## curves and strip.
func set_resolved(values: Dictionary) -> void:
	if _inspector != null:
		_inspector.set_resolved(values)
	if _colour_inspector != null:
		_colour_inspector.set_resolved(values)
	if _palette_window != null:
		_palette_window.set_resolved(values)


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


## Set the zoom, clamped to ZOOM_STEPS' range.
func set_zoom(value: float) -> void:
	value = clampf(value, ZOOM_STEPS[0], ZOOM_STEPS[-1])
	if is_equal_approx(value, zoom):
		return
	zoom = value
	_apply_zoom()
	zoom_changed.emit(zoom)


## Step to the next larger (direction 1) or smaller (-1) level in ZOOM_STEPS.
func step_zoom(direction: int) -> void:
	if direction > 0:
		for z in ZOOM_STEPS:
			if z > zoom + 0.001:
				set_zoom(z)
				return
	else:
		for i in range(ZOOM_STEPS.size() - 1, -1, -1):
			if ZOOM_STEPS[i] < zoom - 0.001:
				set_zoom(ZOOM_STEPS[i])
				return


## Act on a zoom chord (Cmd/Ctrl with =, +, - or 0, keypad too). Returns true
## when `event` was one, so the caller consumes it.
func zoom_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or not k.is_command_or_control_pressed() or k.alt_pressed:
		return false
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	match code:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			step_zoom(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			step_zoom(-1)
		KEY_0, KEY_KP_0:
			set_zoom(1.0)
		_:
			return false
	return true


## Feed a key event to the Ctrl-tap detector (also used directly by tests).
## Returns true when a tap fired.
func feed_ctrl(event: InputEvent) -> bool:
	if _ctrl.feed(event):
		toggle_requested.emit()
		return true
	return false


# Zoom chords are caught before the GUI, so a focused spin box or slider cannot
# swallow them.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if zoom_key(event):
		_ctrl.feed(event)   # a Ctrl+= is a chord, not a Ctrl tap
		set_input_as_handled()


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
	_colour_inspector.set_sources(axis_list)


func _apply_zoom() -> void:
	content_scale_factor = UiScale.factor_for(self) * zoom


## The window this one opens beside (the main window), or null before it is added.
func _parent_window() -> Window:
	var parent := get_parent()
	return parent.get_window() if parent != null else null
