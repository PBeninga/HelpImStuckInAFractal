class_name NoiseEditor
extends Control
## The noise-field editor: a GraphEdit over one NoiseGraph, Godot-editor style,
## with a toolbar above it. A port of Fractacular's IsolationEditor.
##
## Each graph node is a GraphNode carrying typed slots (one colour per port type),
## a compact NoiseParamRow per parameter, whatever extra controls its type builds
## (Output's tint picker), and a live preview: a ColorRect whose ShaderMaterial is
## compiled by NoiseCompiler.compile_preview, drawing the subgraph up to that
## output over an XY slice of fractal space. No SubViewport — the shader draws
## straight into the node.
##
## Two things it deliberately does NOT do:
##   - add a node. Choosing one from the add menu emits `add_node_requested`; the
##     window owns the graph.
##   - validate a connection itself. Every request goes through
##     NoiseGraph.can_connect, the authority on types, cycles and one-link-per-input.
##
## The toolbar's New emits a signal too (the graph is saved inside the level, so
## there is no graph-only Save/Load here); the Extent and Slice Z spin boxes are
## the editor's own, shared by every preview.

const EMPTY_TEXT := "No noise field.\n\nThis should not happen: the window always holds a graph."
const CONTROLS_TOOLTIP := "Show or hide this node's parameter rows. The node shrinks when they are hidden, and its ports stay connectable either way. Remembered when the graph is saved."
const PREVIEW_TOOLTIP := "Show or hide this node's live preview — the field it produces over a flat XY slice of fractal space, at the Extent and Slice Z set in the toolbar. A Float shows as greyscale (black -1, white +1), a Vec3 as its absolute value in RGB. Remembered when the graph is saved."
const DISCONNECT_TOOLTIP := "Remove this wire. Two other ways do the same: press Delete (or Backspace) while the wire is highlighted under the cursor, or drag the wire off the input port it ends at."
const BROKEN_SHADER_TOOLTIP := "This node's preview shader did not compile, so its preview is blank. The compiler's message is in the console, tagged SHADER ERROR."
const EXTENT_TOOLTIP := "The half-width of fractal space each preview shows, centred on the origin. Larger zooms the previews out."
const SLICE_TOOLTIP := "The z plane each preview is sliced at. The field is 3D; this picks which flat slice of it the previews draw."

const CONTROLS_GLYPH := "≡"
const PREVIEW_GLYPH := "◉"
const NODE_WIDTH := 300.0
const PREVIEW_WIDTH := 160.0
const PREVIEW_HEIGHT := 120.0
const SLOT_ROW_HEIGHT := 22.0
const BROKEN_SHADER_COLOR := Color(1.0, 0.45, 0.45)

signal add_node_requested(type_id: StringName, position: Vector2)
signal new_requested

var _graph: NoiseGraph
var _graph_edit: GraphEdit
var _empty: Label
var _add_menu: PopupMenu
var _wire_menu: PopupMenu
var _wire_target: Dictionary = {}
var _status: Label
var _extent_spin: SpinBox
var _slice_spin: SpinBox
var new_button: Button

var _cursor := Vector2.ZERO
var _cursor_inside := false
var _widgets: Dictionary = {}        # StringName -> GraphNode
var _rows: Dictionary = {}           # StringName -> { StringName -> NoiseParamRow }
var _previews: Array = []            # [{id, port, rect: ColorRect, material: ShaderMaterial}]
var _add_ids: Array[StringName] = []
var _add_position := Vector2.ZERO
var _rebuild_queued := false


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)

	box.add_child(_build_toolbar())

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.right_disconnects = true
	_graph_edit.show_grid = true
	for t in NoisePort.Type.values():
		_graph_edit.add_valid_connection_type(t, t)
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.end_node_move.connect(_on_end_node_move)
	_graph_edit.popup_request.connect(_on_popup_request)
	_graph_edit.gui_input.connect(_on_graph_edit_gui_input)
	_graph_edit.mouse_exited.connect(func() -> void: _cursor_inside = false)
	box.add_child(_graph_edit)

	_empty = Label.new()
	_empty.text = EMPTY_TEXT
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_empty)

	_add_menu = PopupMenu.new()
	_add_menu.id_pressed.connect(_on_add_menu_id_pressed)
	add_child(_add_menu)
	_build_add_menu()

	_wire_menu = PopupMenu.new()
	_wire_menu.add_item("Disconnect", 0)
	_wire_menu.set_item_tooltip(0, DISCONNECT_TOOLTIP)
	_wire_menu.id_pressed.connect(_on_wire_menu_id_pressed)
	add_child(_wire_menu)

	_rebuild()


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	new_button = Button.new()
	new_button.text = "New"
	new_button.tooltip_text = "Discard this field and start from the default empty graph (Position and Output). The field is saved inside the level (the View tab's Save level…)."
	new_button.pressed.connect(func() -> void: new_requested.emit())
	bar.add_child(new_button)

	bar.add_child(VSeparator.new())
	var extent_label := Label.new()
	extent_label.text = "Extent"
	extent_label.tooltip_text = EXTENT_TOOLTIP
	bar.add_child(extent_label)
	_extent_spin = SpinBox.new()
	_extent_spin.min_value = 0.1
	_extent_spin.max_value = 100.0
	_extent_spin.step = 0.1
	_extent_spin.value = 4.0
	_extent_spin.tooltip_text = EXTENT_TOOLTIP
	_extent_spin.value_changed.connect(func(_v: float) -> void: _push_preview_uniforms())
	bar.add_child(_extent_spin)
	var slice_label := Label.new()
	slice_label.text = "Slice Z"
	slice_label.tooltip_text = SLICE_TOOLTIP
	bar.add_child(slice_label)
	_slice_spin = SpinBox.new()
	_slice_spin.min_value = -100.0
	_slice_spin.max_value = 100.0
	_slice_spin.step = 0.1
	_slice_spin.value = 0.0
	_slice_spin.tooltip_text = SLICE_TOOLTIP
	_slice_spin.value_changed.connect(func(_v: float) -> void: _push_preview_uniforms())
	bar.add_child(_slice_spin)

	bar.add_child(VSeparator.new())
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bar.add_child(_status)
	return bar


## Show a graph. Nulls are allowed (though the window always passes a real one).
func show_graph(graph: NoiseGraph) -> void:
	if _graph != null:
		if _graph.changed.is_connected(_on_graph_changed):
			_graph.changed.disconnect(_on_graph_changed)
		if _graph.node_changed.is_connected(_on_node_changed):
			_graph.node_changed.disconnect(_on_node_changed)
	_graph = graph
	if _graph != null:
		_graph.changed.connect(_on_graph_changed)
		_graph.node_changed.connect(_on_node_changed)
	_rebuild()


func graph_edit() -> GraphEdit:
	return _graph_edit


func node_widget(id: StringName) -> GraphNode:
	return _widgets.get(id)


func node_count() -> int:
	return _widgets.size()


func row(node_id: StringName, param_id: StringName) -> NoiseParamRow:
	var by_param: Dictionary = _rows.get(node_id, {})
	return by_param.get(param_id)


func add_menu() -> PopupMenu:
	return _add_menu


func wire_menu() -> PopupMenu:
	return _wire_menu


func extent_spin() -> SpinBox:
	return _extent_spin


func slice_spin() -> SpinBox:
	return _slice_spin


func status_label() -> Label:
	return _status


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func is_empty() -> bool:
	return _graph == null or _widgets.is_empty()


func preview_count() -> int:
	return _previews.size()


# --------------------------------------------------------------- building

func _on_graph_changed() -> void:
	_queue_rebuild()


func _on_node_changed(id: StringName, param_id: StringName) -> void:
	# A live FLOAT (or the tint colour) only pushes a value to the previews; a
	# baked INT/BOOL/ENUM changes the generated GLSL, so the preview shaders are
	# recompiled. Neither touches the widgets.
	if _graph != null and NoiseCompiler.is_live_param(_graph, id, param_id):
		_push_preview_uniforms()
	else:
		_recompile_previews()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if _graph_edit == null:
		return
	_graph_edit.clear_connections()
	for id in _widgets:
		var widget: GraphNode = _widgets[id]
		_graph_edit.remove_child(widget)
		widget.queue_free()
	_widgets.clear()
	_rows.clear()
	_previews.clear()

	if _graph == null:
		_empty.visible = true
		_graph_edit.visible = false
		return
	_empty.visible = false
	_graph_edit.visible = true

	for id in _graph.order():
		var state: NoiseGraph.NodeState = _graph.node(id)
		if state != null:
			_build_node(state)
	for link in _graph.links:
		if _widgets.has(link["from"]) and _widgets.has(link["to"]):
			_graph_edit.connect_node(
				StringName(String(link["from"])), int(link["from_port"]),
				StringName(String(link["to"])), int(link["to_port"]))
	_push_preview_uniforms()


func _build_node(state: NoiseGraph.NodeState) -> void:
	var type := NoiseNodeRegistry.type_by_id(state.type_id)
	var widget := GraphNode.new()
	widget.name = String(state.id)
	widget.title = type.title if type != null else String(state.type_id)
	widget.tooltip_text = type.description if type != null else ""
	widget.position_offset = state.position
	widget.resizable = false
	widget.draggable = true
	widget.selectable = true
	widget.custom_minimum_size = Vector2(NODE_WIDTH, 0)
	_graph_edit.add_child(widget)
	_widgets[state.id] = widget
	_rows[state.id] = {}

	_add_title_toggles(widget, state)
	_add_slots(widget, type)
	if state.controls_open:
		_add_rows(widget, state, type)
		_add_extras(widget, state, type)
	if state.preview_open:
		_add_preview(widget, state, type)
	widget.reset_size()


func _add_title_toggles(widget: GraphNode, state: NoiseGraph.NodeState) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(filler)
	header.add_child(_make_toggle(CONTROLS_GLYPH, CONTROLS_TOOLTIP, state.controls_open,
		func(on: bool) -> void:
			state.controls_open = on
			_queue_rebuild()))
	header.add_child(_make_toggle(PREVIEW_GLYPH, PREVIEW_TOOLTIP, state.preview_open,
		func(on: bool) -> void:
			state.preview_open = on
			_queue_rebuild()))
	widget.add_child(header)


func _make_toggle(glyph: String, tooltip: String, pressed: bool, on_toggled: Callable) -> Button:
	var button := Button.new()
	button.text = glyph
	button.toggle_mode = true
	button.button_pressed = pressed
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(26.0, 0.0)
	button.toggled.connect(on_toggled)
	return button


## Slots. GraphNode pairs inputs with outputs by slot ROW. The header row above is
## child 0, so slot rows start at child 1, and nothing before a slot row may be
## hidden. Because each side's enabled slots are contiguous, port index i on either
## side is slot row i + 1, so the connection handlers need no translation.
func _add_slots(widget: GraphNode, type: NoiseNodeType) -> void:
	if type == null:
		return
	var rows := maxi(type.inputs.size(), type.outputs.size())
	for port in rows:
		var has_in := port < type.inputs.size()
		var has_out := port < type.outputs.size()

		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(0.0, SLOT_ROW_HEIGHT)
		var left := Label.new()
		left.text = type.inputs[port].name if has_in else ""
		left.add_theme_font_size_override("font_size", 11)
		line.add_child(left)
		var filler := Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(filler)
		var right := Label.new()
		right.text = type.outputs[port].name if has_out else ""
		right.add_theme_font_size_override("font_size", 11)
		line.add_child(right)
		widget.add_child(line)

		var slot := widget.get_child_count() - 1
		var in_type: int = type.inputs[port].type if has_in else 0
		var out_type: int = type.outputs[port].type if has_out else 0
		widget.set_slot(slot,
			has_in, in_type, NoisePort.COLORS[in_type],
			has_out, out_type, NoisePort.COLORS[out_type])

		var parts: Array[String] = []
		if has_in:
			var in_tip := "← %s — %s\n\n%s" % [
				type.inputs[port].name, type.inputs[port].tooltip, NoisePort.TOOLTIPS[in_type]]
			left.tooltip_text = in_tip
			left.mouse_filter = Control.MOUSE_FILTER_STOP
			parts.append(in_tip)
		if has_out:
			var out_tip := "%s → — %s\n\n%s" % [
				type.outputs[port].name, type.outputs[port].tooltip, NoisePort.TOOLTIPS[out_type]]
			right.tooltip_text = out_tip
			right.mouse_filter = Control.MOUSE_FILTER_STOP
			parts.append(out_tip)
		line.tooltip_text = "\n\n".join(parts)
		line.mouse_filter = Control.MOUSE_FILTER_STOP


func _add_rows(widget: GraphNode, state: NoiseGraph.NodeState, type: NoiseNodeType) -> void:
	if type == null or state.table == null:
		return
	for spec in type.params():
		if not state.table.has(spec.id):
			continue
		var param_row := NoiseParamRow.new()
		param_row.setup(spec, state.table)
		widget.add_child(param_row)
		(_rows[state.id] as Dictionary)[spec.id] = param_row


## The node type's extra controls (Output's tint picker). The container carries a
## `notify_node_changed` meta Callable so a control's edit reaches the graph.
func _add_extras(widget: GraphNode, state: NoiseGraph.NodeState, type: NoiseNodeType) -> void:
	if type == null:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	widget.add_child(box)
	box.set_meta(&"notify_node_changed",
		Callable(_graph, "notify_node_changed") if _graph != null else Callable())
	type.build_extra_controls(state, box)
	if box.get_child_count() == 0:
		widget.remove_child(box)
		box.queue_free()


## One preview per output port: a ColorRect whose ShaderMaterial draws the
## subgraph up to that port. A node whose preview shader fails to compile gets a
## red banner and the editor keeps running.
func _add_preview(widget: GraphNode, state: NoiseGraph.NodeState, type: NoiseNodeType) -> void:
	if type == null:
		return
	for port in type.outputs.size():
		var port_spec: NoiseNodeType.PortSpec = type.outputs[port]
		var code := NoiseCompiler.compile_preview(_graph, state.id, port)
		var shader := Shader.new()
		shader.code = code
		if shader.get_shader_uniform_list().is_empty():
			var banner := Label.new()
			banner.text = "⚠ preview failed: %s" % port_spec.name
			banner.tooltip_text = BROKEN_SHADER_TOOLTIP
			banner.mouse_filter = Control.MOUSE_FILTER_STOP
			banner.add_theme_color_override("font_color", BROKEN_SHADER_COLOR)
			widget.add_child(banner)
			continue
		var material := ShaderMaterial.new()
		material.shader = shader
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(PREVIEW_WIDTH, PREVIEW_HEIGHT)
		rect.material = material
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.tooltip_text = "%s\n\n%s\n\n%s" % [port_spec.name, port_spec.tooltip, NoisePort.TOOLTIPS[port_spec.type]]
		widget.add_child(rect)
		_previews.append({"id": state.id, "port": port, "rect": rect, "material": material})


## Recompile every preview's shader (after a baked edit changed the GLSL).
func _recompile_previews() -> void:
	if _graph == null:
		return
	for entry in _previews:
		var code := NoiseCompiler.compile_preview(_graph, entry["id"], entry["port"])
		var shader := Shader.new()
		shader.code = code
		(entry["material"] as ShaderMaterial).shader = shader
	_push_preview_uniforms()


## Push the shared Extent and Slice Z plus every live value to every preview.
func _push_preview_uniforms() -> void:
	if _graph == null:
		return
	var extent := _extent_spin.value if _extent_spin != null else 4.0
	var slice := _slice_spin.value if _slice_spin != null else 0.0
	var values := NoiseCompiler.live_values(_graph)
	for entry in _previews:
		var material: ShaderMaterial = entry["material"]
		material.set_shader_parameter("preview_extent", extent)
		material.set_shader_parameter("preview_slice_z", slice)
		for name in values:
			material.set_shader_parameter(name, values[name])


# ------------------------------------------------------------- the add menu

func _build_add_menu() -> void:
	_add_menu.clear()
	_add_ids.clear()
	var types := NoiseNodeRegistry.all()
	var placed: Dictionary = {}
	for group in NoiseNodeRegistry.groups():
		_add_menu.add_separator(group)
		for type in types:
			if type.group != group:
				continue
			placed[type.id] = true
			_add_menu_entry(type)
	var ungrouped: Array[NoiseNodeType] = []
	for type in types:
		if not placed.has(type.id):
			ungrouped.append(type)
	if not ungrouped.is_empty():
		_add_menu.add_separator("Other")
		for type in ungrouped:
			_add_menu_entry(type)


func _add_menu_entry(type: NoiseNodeType) -> void:
	var id := _add_ids.size()
	_add_ids.append(type.id)
	_add_menu.add_item(type.title, id)
	var item := _add_menu.item_count - 1
	var tip := type.description
	if type.id == NoiseGraph.SOURCE_TYPE or type.id == NoiseGraph.OUTPUT_TYPE:
		_add_menu.set_item_disabled(item, true)
		tip += "\n\nEvery graph has exactly one of these already, so there is nothing to add."
	_add_menu.set_item_tooltip(item, tip)


func _on_popup_request(at: Vector2) -> void:
	var wire := _graph_edit.get_closest_connection_at_point(at)
	if not wire.is_empty():
		_wire_target = wire
		_wire_menu.reset_size()
		_wire_menu.position = Vector2i(_graph_edit.get_screen_transform() * at)
		_wire_menu.popup()
		return
	_add_position = (_graph_edit.scroll_offset + at) / maxf(_graph_edit.zoom, 0.001)
	_add_menu.reset_size()
	_add_menu.position = Vector2i(_graph_edit.get_screen_transform() * at)
	_add_menu.popup()


func _on_add_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= _add_ids.size():
		return
	add_node_requested.emit(_add_ids[id], _add_position)


func _on_wire_menu_id_pressed(_id: int) -> void:
	_disconnect_wire(_wire_target)
	_wire_target = {}


# --------------------------------------------------- deleting a wire by key

func _unhandled_key_input(event: InputEvent) -> void:
	if _delete_wire_under_cursor(event):
		get_viewport().set_input_as_handled()


func _on_graph_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_cursor = (event as InputEventMouseMotion).position
		_cursor_inside = true
	elif _delete_wire_under_cursor(event):
		_graph_edit.accept_event()


func _is_delete_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.is_action(&"ui_graph_delete") or key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE


func _delete_wire_under_cursor(event: InputEvent) -> bool:
	if _graph == null or not _graph_edit.visible or not _is_delete_key(event):
		return false
	if not _cursor_inside:
		return false
	var wire := _graph_edit.get_closest_connection_at_point(_cursor)
	if wire.is_empty():
		return false
	_disconnect_wire(wire)
	return true


func _disconnect_wire(wire: Dictionary) -> void:
	if _graph == null or wire.is_empty():
		return
	_graph.disconnect_ports(StringName(wire["from_node"]), int(wire["from_port"]),
		StringName(wire["to_node"]), int(wire["to_port"]))


# ------------------------------------------------------- graph edit handlers

func _on_connection_request(from: Variant, from_port: int, to: Variant, to_port: int) -> void:
	if _graph == null:
		return
	_graph.connect_ports(StringName(from), from_port, StringName(to), to_port)


func _on_disconnection_request(from: Variant, from_port: int, to: Variant, to_port: int) -> void:
	if _graph == null:
		return
	_graph.disconnect_ports(StringName(from), from_port, StringName(to), to_port)


func _on_delete_nodes_request(ids: Array) -> void:
	if _graph == null:
		return
	for id in ids:
		_graph.remove_node(StringName(id))


func _on_end_node_move() -> void:
	if _graph == null:
		return
	for id in _widgets:
		var state: NoiseGraph.NodeState = _graph.node(id)
		if state != null:
			state.position = (_widgets[id] as GraphNode).position_offset
