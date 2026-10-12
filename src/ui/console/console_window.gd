class_name ConsoleWindow
extends Window
## The console ("Fractacular embedded") for the scene of shapes being flown
## through in the main window: six tabs stacked above the Movement pane in a
## VSplit. The Shape tab is the ShapeListPane: Add shape and a read-only line
## saying whether the selected shape is self-similar
## (ShapeCatalogue.self_similarity, fed by Main) over one collapsible panel per
## shape (its Placement, Fractal, Box, Julia, Iteration rotation, KIFS,
## Kleinian, Mandelbulb and Render groups); the Light tab is
## the lamp, its scattering and the picture's exposure and saturation; the
## Material tab is Fractacular's Colour window (the cosine palette's sliders,
## curves and strip) above the Colour, Surface, Texture and Palette rows, in one
## scrolling list (the Light and Material tabs edit the expanded shape's look
## table); Gameplay holds Save / Load, spawn and flight tuning; View holds camera
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
## main window, never over it — or back where the player last left it
## (`remembered_rect`, which Main fills from Settings). A Ctrl tap in this
## window forwards `toggle_requested`; other keys go to `unhandled_key`.
##
## Docked (Main's fullscreen layout, dock()), it is no longer a separate OS
## window: it becomes a borderless window embedded in the right-hand strip of
## the main window, the view on its left, so the two share one fullscreen
## window (on macOS, one desktop of its own). Its content scale then cancels
## the main window's fitted scale, so it keeps its point size (times its zoom)
## however big the screen. undock() makes it a native window again.
##
## Cmd+= / Cmd+- (Ctrl on other platforms) zoom everything in the window, text
## and controls alike, through its content scale, as a browser zooms a page;
## Cmd+0 resets. The window keeps its size and the panes reflow. `zoom_changed`
## lets Main keep the level in Settings.
##
## W, A, S or D pressed in the console leaves it for the game
## (`game_focus_requested`): a spin box drops focus (committing what was typed
## into it) and the key is not typed. A free-text field being typed into (an
## axis label) keeps the letter; once Enter ends the edit, WASD leaves too.

signal toggle_requested
## A key this window's controls left unhandled (Escape, N, Cmd+S…). Showing the
## window gives it keyboard focus, and a focused window keeps keys from the main
## window, so Main runs these through its own dispatch.
signal unhandled_key(event: InputEventKey)
## W, A, S or D was pressed here outside a text edit: the player wants to fly,
## so Main hands keyboard focus (and the mouse) back to the game.
signal game_focus_requested
## The zoom level changed (by a key or set_zoom()).
signal zoom_changed(zoom: float)

## In points (logical units); UiScale.px turns them into window pixels.
const DEFAULT_SIZE := Vector2i(1000, 700)
const MIN_SIZE := Vector2i(700, 400)
## The zoom levels Cmd+= and Cmd+- step through, browser style.
const ZOOM_STEPS: Array[float] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

const SELF_SIMILAR_TOOLTIP := "Whether this shape is exactly self-similar: every deep region is a magnified copy of a shallower region of the same shape, so a deep zoom could be rendered from the shallower copy. On the Mandelbox only Julia mode with c fixed in x, y and z, an iteration that magnifies, no scale drift and no noise displacement qualify; the KIFS qualifies without a twist, the Kleinian always (both without noise); the Mandelbulb never (its power map stretches unevenly). Read-only; nothing renders differently. See docs/reference/self-similar-substitution.md."

## Multiplies UiScale's factor for this window; 1 is the default size.
var zoom := 1.0
## Where the native console last sat (screen pixels); open() puts it back there
## while that is still on a screen. Empty: open beside the main window.
var remembered_rect := Rect2i()

var _tabs: TabContainer
var _shape_pane: ShapeListPane
var _light_inspector: AttributeInspector
var _material_inspector: AttributeInspector
var _light_shape_label: Label
var _material_shape_label: Label
var _rendered_shape := -1
var _palette: Palette
var _palette_window: PaletteWindow
var _self_similar: Label
var _movement: MovementPane
var _view: ViewPane
var _gameplay: GameplayPane
var _escape_animation: EscapeAnimationPane
var _keymap: Keymap
var _ctrl := CtrlTap.new()
var _docked := false
## The strip of the main window's canvas the docked console fills.
var _dock_rect := Rect2i()


## `shapes` owns geometry and look tables per entry. `_look` is retained for
## compatibility with older callers; both look tabs use the expanded entry.
func setup(shapes: ShapeList, _look: AttributeTable, keymap: Keymap, clock: Clock, group_tooltips: Dictionary, speed_source: Callable = Callable()) -> void:
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

	_self_similar = Label.new()
	_self_similar.name = "SelfSimilar"
	_self_similar.mouse_filter = Control.MOUSE_FILTER_STOP   # so its tooltip shows
	_self_similar.tooltip_text = SELF_SIMILAR_TOOLTIP
	show_self_similarity(ShapeCatalogue.self_similarity(shapes.table(0).defaults()))
	_shape_pane = ShapeListPane.new()
	_shape_pane.name = "Shape"
	_shape_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shape_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_shape_pane)
	_shape_pane.setup(shapes, group_tooltips, _self_similar)

	var look := shapes.look_table(0)
	_palette = Palette.new(look)
	_palette_window = PaletteWindow.new()
	_palette_window.setup(_palette)
	_palette_window.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_light_inspector = AttributeInspector.new()
	_light_inspector.name = "Light"
	_light_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_light_shape_label = _add_look_tab("Light", _light_inspector)
	_light_inspector.setup(look, group_tooltips, ShapeCatalogue.LIGHT_GROUPS)

	_material_inspector = AttributeInspector.new()
	_material_inspector.name = "Material"
	_material_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_material_shape_label = _add_look_tab("Material", _material_inspector)
	_material_inspector.setup(look, group_tooltips, ShapeCatalogue.MATERIAL_GROUPS, _palette_window)
	_shape_pane.expanded_changed.connect(_edit_shape_look)
	_edit_shape_look(_shape_pane.expanded_index())

	_view = ViewPane.new()
	_tabs.add_child(_view)
	_gameplay = GameplayPane.new()
	_tabs.add_child(_gameplay)
	_escape_animation = EscapeAnimationPane.new()
	_tabs.add_child(_escape_animation)

	_movement = MovementPane.new()
	_movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_movement.size_flags_vertical = Control.SIZE_FILL
	_movement.setup(keymap, clock, speed_source)
	split.add_child(_movement)

	_ctrl.typing_guard = func() -> bool: return TextFocus.any([self])
	if keymap != null:
		keymap.changed.connect(_refresh_sources)
	_refresh_sources()


## The Shape tab: one collapsible panel per shape.
func shape_pane() -> ShapeListPane:
	return _shape_pane


## The selected (active) shape's panel on the Shape tab (Placement, Fractal,
## Box, Julia, Iteration rotation, KIFS, Kleinian, Mandelbulb, Render).
func inspector() -> AttributeInspector:
	return _shape_pane.active_inspector()


## The Light tab's inspector (Light, Scattering, Picture).
func light_inspector() -> AttributeInspector:
	return _light_inspector


## The Material tab's inspector (Colour, Surface, Texture, Palette), under the palette window.
func material_inspector() -> AttributeInspector:
	return _material_inspector


func _add_look_tab(tab_name: String, inspector: AttributeInspector) -> Label:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	_tabs.add_child(tab)
	var label := Label.new()
	label.name = "EditingShape"
	label.add_theme_font_size_override("font_size", 16)
	tab.add_child(label)
	tab.add_child(inspector)
	return label


func _edit_shape_look(index: int) -> void:
	var table: AttributeTable = _shape_pane.shapes().look_table(index) if index >= 0 else null
	_light_inspector.set_table(table)
	_material_inspector.set_table(table)
	_light_inspector.visible = index >= 0
	_material_inspector.visible = index >= 0
	if table != null:
		_palette.set_table(table)
		_refresh_sources()
	_update_look_labels()


func _update_look_labels() -> void:
	var index := _shape_pane.expanded_index()
	var text := "Expand a shape in the Shape tab to edit it."
	if index >= 0:
		text = "Editing shape %d" % (index + 1)
		if _rendered_shape >= 0 and index != _rendered_shape:
			text += " · Inactive — showing defaults"
	_light_shape_label.text = text
	_material_shape_label.text = text


func palette_window() -> PaletteWindow:
	return _palette_window


func palette() -> Palette:
	return _palette


func tabs() -> TabContainer:
	return _tabs


## The View tab: camera mode, noise editor, renderer, Back to Menu.
func view_pane() -> ViewPane:
	return _view


func gameplay_pane() -> GameplayPane:
	return _gameplay


func escape_animation_pane() -> EscapeAnimationPane:
	return _escape_animation


## Bring a console tab to the front.
func show_tab(index: int) -> void:
	_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func movement_pane() -> MovementPane:
	return _movement


## The Shape tab's read-only self-similarity line.
func self_similarity_label() -> Label:
	return _self_similar


## Show a ShapeCatalogue.self_similarity() result on the Shape tab's line.
func show_self_similarity(result: Dictionary) -> void:
	if _self_similar == null:
		return
	var text := "Self-similar: %s (%s)" % ["yes" if result.get("qualifies", false) else "no", result.get("reason", "")]
	if _self_similar.text != text:
		_self_similar.text = text


## The governor's load-shed level, shown in the Movement pane.
func show_shed_level(level: int) -> void:
	_movement.show_shed_level(level)


## Whether the fly camera is held at the zoom floor, shown in the Movement pane.
func show_zoom_limit(on: bool) -> void:
	_movement.show_zoom_limit(on)


## Feed one frame of resolved values — one Dictionary per shape, and the
## scene's look — to the panels' readouts and the palette's curves and strip.
func set_resolved(shape_values: Array, look_values: Dictionary = {}, rendered_shape: int = -1) -> void:
	if _shape_pane != null:
		_shape_pane.set_resolved(shape_values)
	if _rendered_shape != rendered_shape:
		_rendered_shape = rendered_shape
		_update_look_labels()
	var index := _shape_pane.expanded_index()
	# Main may resolve during a list-change signal before the pane rebuilds.
	if index < 0 or index >= _shape_pane.shapes().count():
		return
	if rendered_shape >= 0 and index != rendered_shape:
		look_values = _shape_pane.shapes().look_table(index).defaults()
	if _light_inspector != null:
		_light_inspector.set_resolved(look_values)
	if _material_inspector != null:
		_material_inspector.set_resolved(look_values)
	_palette_window.set_resolved(look_values)


func open() -> void:
	if _docked:
		position = _dock_rect.position
		size = _dock_rect.size
	elif not is_embedded() and WindowGeometry.restorable_now(remembered_rect):
		size = remembered_rect.size
		position = remembered_rect.position
	else:
		UiScale.place_beside(self, _parent_window())
	visible = true


func hide_console() -> void:
	_remember_place()
	visible = false


## Forget where the player left the console and, if it is open, put it back
## beside the main window.
func reset_place() -> void:
	remembered_rect = Rect2i()
	if visible and not _docked:
		size = UiScale.px(DEFAULT_SIZE, self)
		UiScale.place_beside(self, _parent_window())


func is_docked() -> bool:
	return _docked


## Become (or, already docked, move to) a borderless window embedded in `rect`
## of the main window's canvas. Leaves it hidden; open() shows it there.
func dock(rect: Rect2i) -> void:
	_dock_rect = rect
	if not _docked:
		_remember_place()
		visible = false   # force_native cannot change while a window is shown
		force_native = false
		borderless = true
		unresizable = true
		min_size = Vector2i.ZERO
		_docked = true
	_apply_zoom()
	if visible:
		position = rect.position
		size = rect.size


## Become a native window again, at its remembered size or the default. Leaves
## it hidden; open() puts it back where it was, or beside the main window.
func undock() -> void:
	if not _docked:
		return
	visible = false
	_docked = false
	force_native = true
	borderless = false
	unresizable = false
	_apply_zoom()
	min_size = UiScale.px(MIN_SIZE, self)
	size = remembered_rect.size if remembered_rect.has_area() else UiScale.px(DEFAULT_SIZE, self)


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


# Zoom chords and WASD are caught before the GUI, so a focused spin box or
# slider cannot swallow them. (A key-capture button's own _input runs first.)
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if zoom_key(event):
		_ctrl.feed(event)   # a Ctrl+= is a chord, not a Ctrl tap
		set_input_as_handled()
		return
	if TextFocus.is_game_key(event, self):
		gui_release_focus()   # a spin box applies its text as it loses focus
		set_input_as_handled()
		game_focus_requested.emit()


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
	if _shape_pane == null or _keymap == null:
		return
	var axis_list: Array = []
	for axis in _keymap.axes().list():
		axis_list.append({"id": axis.id, "label": axis.label})
	_shape_pane.set_sources(axis_list)
	_light_inspector.set_sources(axis_list)
	_material_inspector.set_sources(axis_list)


func _apply_zoom() -> void:
	var parent := _parent_window()
	if _docked and parent != null:
		# Drawn in the main window's canvas, which follow_size() may have
		# grown: divide that growth back out.
		content_scale_factor = zoom / UiScale.points_per_unit(parent)
	else:
		content_scale_factor = UiScale.factor_for(self) * zoom


## Keep the native console's place for the next open() (and, through
## Settings, the next launch).
func _remember_place() -> void:
	if visible and not _docked and not is_embedded() and mode == Window.MODE_WINDOWED:
		remembered_rect = Rect2i(position, size)


## The window this one opens beside (the main window), or null before it is added.
func _parent_window() -> Window:
	var parent := get_parent()
	return parent.get_window() if parent != null else null
