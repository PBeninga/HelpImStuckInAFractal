class_name ShapeListPane
extends VBoxContainer
## The console's Shape tab for a scene of shapes: an Add shape button and the
## selected shape's self-similarity line over one scrolling list with an entry
## per shape. An entry is a header line (a ▾/▸ arrow that expands or collapses
## it, its editable label, and a ✕ that removes it) above that shape's full
## AttributeInspector over the per-shape groups (Placement, Fractal, Box, …).
## Clicking anywhere on a header selects the shape: the selected one is the
## console's "active" shape (the Julia marker follows it, a new shape is
## placed relative to it, the self-similarity line is its). The pane rebuilds
## its entries whenever the ShapeList's structure changes (a load, an add, a
## remove), keeping the expanded and selected entries by table identity; a relabel only
## updates the one label.

## The selected (active) shape changed.
signal selected_changed(index: int)
## The only expanded shape, or -1 when all panels are closed.
signal expanded_changed(index: int)

const SCROLLBAR_ALLOWANCE := 16.0
const SELECTED_COLOR := Color(0.72, 0.82, 1.0)
const PLAIN_COLOR := Color(0.85, 0.85, 0.85)

const ADD_TOOLTIP := "Add a shape: a copy of the selected shape's knobs at a tenth of its size, centred in front of the camera, with no bindings. Shapes are played in list order; only the gameplay-active shape is visible."
const ARROW_TOOLTIP := "Expand or collapse this shape's control panel."
const LABEL_TOOLTIP := "The shape's name, saved with the level. Click a header to select the shape for editing: the Julia marker, Add shape and the self-similarity line work on it."
const REMOVE_TOOLTIP := "Remove this shape from the scene. The last shape cannot be removed."

var _shapes: ShapeList
var _group_tooltips: Dictionary = {}
## Returns the id -> value defaults for a new shape (Main computes a placement
## in front of the camera). Unset: the catalogue defaults.
var _placement_source: Callable = Callable()
var _add_button: Button
var _header_line: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array = []   # [{header, arrow, label, remove, inspector}]
var _expanded: Array[bool] = []
var _selected := 0
var _gameplay_active := -1
var _axis_list: Array = []
var _rebuilding := false


## `header_line` (the console's self-similarity label) sits beside the Add
## button; `placement_source` gives the defaults for a new shape.
func setup(shapes: ShapeList, group_tooltips: Dictionary, placement_source: Callable = Callable(), header_line: Control = null) -> void:
	_shapes = shapes
	_group_tooltips = group_tooltips
	_placement_source = placement_source
	_header_line = header_line
	_build()
	_shapes.changed.connect(_rebuild)
	_shapes.relabelled.connect(_on_relabelled)
	_shapes.stage_changed.connect(_refresh_stage_distances)
	_shapes.next_level_distance_changed.connect(_refresh_stage_distances)
	_rebuild()


func _build() -> void:
	add_theme_constant_override("separation", 4)
	custom_minimum_size.x = AttributeRow.WIDE_ROW_MIN_WIDTH + SCROLLBAR_ALLOWANCE

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	_add_button = Button.new()
	_add_button.text = "Add shape"
	_add_button.tooltip_text = ADD_TOOLTIP
	_add_button.pressed.connect(add_shape)
	bar.add_child(_add_button)
	if _header_line != null:
		_header_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(_header_line)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)


# ------------------------------------------------------------------ queries

func shapes() -> ShapeList:
	return _shapes


func scroll_container() -> ScrollContainer:
	return _scroll


func add_button() -> Button:
	return _add_button


func entry_count() -> int:
	return _entries.size()


func selected() -> int:
	return _selected


## The i-th shape's panel.
func inspector(i: int) -> AttributeInspector:
	if i < 0 or i >= _entries.size():
		return null
	return _entries[i]["inspector"]


## The selected shape's panel.
func active_inspector() -> AttributeInspector:
	return inspector(_selected)


## The i-th entry's header widgets: {header, arrow, label, remove}.
func entry_widgets(i: int) -> Dictionary:
	if i < 0 or i >= _entries.size():
		return {}
	var e: Dictionary = _entries[i]
	return {"arrow": e["arrow"], "label": e["label"], "remove": e["remove"], "header": e["header"]}


func is_expanded(i: int) -> bool:
	return i >= 0 and i < _expanded.size() and _expanded[i]


func expanded_index() -> int:
	return _expanded.find(true)


# ------------------------------------------------------------------ actions

## Append a shape (through the placement source when one is set), select it
## and expand it.
func add_shape() -> void:
	var defaults: Dictionary = {}
	if _placement_source.is_valid():
		defaults = _placement_source.call()
	var i := _shapes.add(defaults, "", _shapes.look_table(_selected).defaults())
	if i < 0:
		return
	# _rebuild ran on `changed`; now pick the new one
	_set_expanded(i, true)
	select(i)


func remove_shape(i: int) -> void:
	_shapes.remove(i)


func select(i: int, force := false) -> void:
	i = clampi(i, 0, maxi(_entries.size() - 1, 0))
	if i == _selected and is_expanded(i) and not force:
		return
	_selected = i
	_set_expanded(i, true)
	selected_changed.emit(_selected)


func set_expanded(i: int, on: bool) -> void:
	_set_expanded(i, on)


## The axes available as binding sources, for every panel: Array of {id, label}.
func set_sources(axis_list: Array) -> void:
	_axis_list = axis_list
	for e in _entries:
		(e["inspector"] as AttributeInspector).set_sources(axis_list)


## Feed one frame of resolved values, one Dictionary per shape, to the panels.
func set_resolved(values: Array) -> void:
	for i in mini(values.size(), _entries.size()):
		(_entries[i]["inspector"] as AttributeInspector).set_resolved(values[i])


# ------------------------------------------------------------------ building

func _rebuild() -> void:
	if _rebuilding or _shapes == null:
		return
	_rebuilding = true
	var open_index := expanded_index()
	var open_table: AttributeTable = inspector(open_index).table() if inspector(open_index) != null else null
	var selected_table: AttributeTable = active_inspector().table() if active_inspector() != null else null
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_entries.clear()
	var count := _shapes.count()
	var tables := _shapes.tables()
	_selected = tables.find(selected_table) if tables.has(selected_table) else clampi(_selected, 0, count - 1)
	if open_table != null:
		open_index = tables.find(open_table) if tables.has(open_table) else clampi(open_index, 0, count - 1)
	elif _expanded.is_empty():
		open_index = 0
	_expanded.resize(count)
	for i in count:
		_expanded[i] = i == open_index
	for i in count:
		_entries.append(_make_entry(i))
	_selected = clampi(_selected, 0, count - 1)
	_restyle()
	_rebuilding = false
	selected_changed.emit(_selected)
	expanded_changed.emit(expanded_index())


func _make_entry(i: int) -> Dictionary:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input.bind(i))
	_list.add_child(header)

	var arrow := Button.new()
	arrow.flat = true
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.tooltip_text = ARROW_TOOLTIP
	arrow.custom_minimum_size = Vector2(28, 0)
	arrow.pressed.connect(_on_arrow_pressed.bind(i))
	header.add_child(arrow)

	var label := LineEdit.new()
	label.text = _shapes.label(i)
	label.tooltip_text = LABEL_TOOLTIP
	label.custom_minimum_size = Vector2(180, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.text_submitted.connect(_on_label_submitted.bind(i))
	label.focus_exited.connect(_on_label_focus_exited.bind(i))
	label.gui_input.connect(_on_header_input.bind(i))
	header.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(spacer)

	var remove := Button.new()
	remove.text = "✕"
	remove.tooltip_text = REMOVE_TOOLTIP
	remove.focus_mode = Control.FOCUS_NONE
	remove.disabled = _shapes.count() <= 1
	remove.pressed.connect(_on_remove_pressed.bind(i))
	header.add_child(remove)

	var stage := VBoxContainer.new()
	_list.add_child(stage)
	var distance_row := HBoxContainer.new()
	stage.add_child(distance_row)
	var status := Label.new()
	status.text = "Active shape" if i == _gameplay_active else "Stage %d" % (i + 1)
	header.add_child(status)
	var stage_button := Button.new()
	stage_button.text = "Level settings"
	stage_button.toggle_mode = true
	stage_button.focus_mode = Control.FOCUS_NONE
	header.add_child(stage_button)
	stage_button.toggled.connect(func(on):
		select(i)
		if on:
			_set_expanded(i, true)
		if i < _entries.size():
			_entries[i]["stage_open"] = on
			_restyle())
	var distance_label := Label.new()
	distance_label.text = "Next level distance"
	distance_row.add_child(distance_label)
	var distance := SpinBox.new()
	distance.min_value = 0.0
	distance.max_value = 1e6
	distance.allow_greater = true
	distance.step = 0.0
	distance.value = _shapes.entry(i).next_level_distance
	distance.tooltip_text = "Absolute distance in world units from the run origin (spawn) for this shape. 0 uses 20. Crossing this distance advances regardless of scripted commands and returns you to origin under a screen fade; does not affect rendering."
	distance_row.add_child(distance)
	var threshold := Label.new()
	threshold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threshold.text = _threshold_text(i)
	threshold.add_theme_font_size_override("font_size", 13)
	threshold.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	stage.add_child(threshold)
	var commands := LineEdit.new()
	commands.text = "; ".join(_shapes.entry(i).commands)
	commands.placeholder_text = "Commands separated by ; — Enter to save (empty = none)"
	commands.tooltip_text = "Example: inversion -0.5; kleinian_thickness 0.005. Inversion adjusts the radius; other commands set numeric attributes. Applied only by the agent after a human speaks."
	stage.add_child(commands)
	var error := Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	stage.add_child(error)
	var save_stage := func():
		if i >= _shapes.count():
			return
		var steps: Array = []
		for step in commands.text.split(";", false):
			if not step.strip_edges().is_empty():
				steps.append(step.strip_edges())
		var message := ShapeList.validate_commands(_shapes.table(i), steps)
		error.text = message
		if message == "" and (_shapes.entry(i).next_level_distance != distance.value or Array(_shapes.entry(i).commands) != steps):
			_shapes.set_stage(i, distance.value, steps)
	distance.value_changed.connect(func(_value): save_stage.call())
	commands.text_submitted.connect(func(_text): save_stage.call())

	var inspector := AttributeInspector.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.setup(_shapes.table(i), _group_tooltips, ShapeCatalogue.SHAPE_GROUPS, null, false)
	inspector.set_sources(_axis_list)
	inspector.visible = _expanded[i]
	_list.add_child(inspector)

	return {"header": header, "arrow": arrow, "label": label, "remove": remove, "inspector": inspector, "stage": stage, "status": status, "stage_open": false, "distance": distance, "threshold": threshold}


func _restyle() -> void:
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		(e["arrow"] as Button).text = "▾" if _expanded[i] else "▸"
		(e["inspector"] as AttributeInspector).visible = _expanded[i]
		(e["stage"] as Control).visible = _expanded[i] and e["stage_open"]
		var color := SELECTED_COLOR if i == _selected else PLAIN_COLOR
		(e["label"] as LineEdit).add_theme_color_override("font_color", color)
		(e["arrow"] as Button).add_theme_color_override("font_color", color)


func _set_expanded(i: int, on: bool) -> void:
	if i < 0 or i >= _expanded.size():
		return
	if on:
		for j in _expanded.size():
			_expanded[j] = j == i
		if _selected != i:
			_selected = i
			selected_changed.emit(i)
	else:
		_expanded[i] = false
	_restyle()
	expanded_changed.emit(expanded_index())


# ------------------------------------------------------------------ handlers

func _on_arrow_pressed(i: int) -> void:
	_set_expanded(i, not _expanded[i])


func _on_remove_pressed(i: int) -> void:
	remove_shape(i)


func _on_header_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select(i)


func _on_label_submitted(text: String, i: int) -> void:
	if i < _shapes.count():
		_shapes.set_label(i, text)   # a change comes back through relabelled


func _on_label_focus_exited(i: int) -> void:
	# A label freed by a rebuild (the shape was removed) loses focus too.
	if i < _entries.size() and i < _shapes.count() and is_instance_valid(_entries[i]["label"]):
		_on_label_submitted((_entries[i]["label"] as LineEdit).text, i)


func _on_relabelled(i: int) -> void:
	if i < _entries.size():
		var edit := _entries[i]["label"] as LineEdit
		if edit.text != _shapes.label(i):
			edit.text = _shapes.label(i)


func set_gameplay_active(index: int) -> void:
	_gameplay_active = index
	for i in _entries.size():
		_entries[i].status.text = "Active shape" if i == index else "Stage %d" % (i + 1)


func _threshold_text(i: int) -> String:
	return "Advances beyond %s world units from run origin (spawn)." % _shapes.next_level_threshold(i)


func _refresh_stage_distances(_index: int) -> void:
	for i in _entries.size():
		(_entries[i]["distance"] as SpinBox).set_value_no_signal(_shapes.entry(i).next_level_distance)
		(_entries[i]["threshold"] as Label).text = _threshold_text(i)
