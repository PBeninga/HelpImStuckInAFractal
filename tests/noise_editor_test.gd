extends "res://tests/test_case.gd"
## NoiseEditor: a GraphNode per graph node, typed slots, compact rows, the two
## collapse toggles, ColorRect previews, the add menu, and connections validated
## through NoiseGraph.can_connect. A port of Fractacular's isolation_editor_test.


func _graph() -> NoiseGraph:
	return NoiseGraph.default_graph(Callable(NoiseNodeRegistry, "type_by_id"))


func _count_of_type(node: Node, type_name: String) -> int:
	var total := 0
	for child in node.get_children():
		if child.is_class(type_name):
			total += 1
		total += _count_of_type(child, type_name)
	return total


func _find_color_picker(node: Node) -> ColorPickerButton:
	for child in node.get_children():
		if child is ColorPickerButton:
			return child
		var deeper := _find_color_picker(child)
		if deeper != null:
			return deeper
	return null


func run() -> void:
	var editor := NoiseEditor.new()
	root.add_child(editor)
	editor.size = Vector2(900, 650)
	await frames(2)

	# ------------------------------------------------------------- a real graph
	var graph := _graph()
	editor.show_graph(graph)
	await frames(3)
	check(not editor.is_empty(), "with a graph, the editor is not empty")
	check(editor.graph_edit() is GraphEdit, "it holds a GraphEdit")
	check_eq(editor.node_count(), graph.nodes.size(), "one GraphNode per graph node (%d)" % graph.nodes.size())
	check(editor.node_widget(&"position_0") != null, "there is a widget for the Position")
	check(editor.node_widget(&"output_0") != null, "and for the Output")
	check(editor.node_widget(&"nothing_9") == null, "an unknown id gives null")

	# toolbar
	check(editor.extent_spin() != null and editor.extent_spin().value == 4.0, "the Extent spin defaults to 4")
	check(editor.slice_spin() != null and editor.slice_spin().value == 0.0, "the Slice Z spin defaults to 0")
	check(editor.new_button != null, "the toolbar has New")

	# titles and positions
	var pos_type := NoiseNodeRegistry.type_by_id(&"position")
	check_eq(editor.node_widget(&"position_0").title, pos_type.title, "the widget's title is the type's title")
	check(editor.node_widget(&"position_0").position_offset.is_equal_approx(graph.node(&"position_0").position),
		"…and it sits where the graph says")

	# ----------------------------------------------------------- typed slots
	var ge := editor.graph_edit()
	for t in NoisePort.Type.values():
		check(ge.is_valid_connection_type(t, t), "%s connects to %s" % [NoisePort.NAMES[t], NoisePort.NAMES[t]])
	check(not ge.is_valid_connection_type(NoisePort.Type.VEC3, NoisePort.Type.FLOAT),
		"a Vec3 cannot be dragged into a Float port")

	var pos_widget := editor.node_widget(&"position_0")
	check_eq(pos_widget.get_output_port_count(), 1, "Position shows one output port")
	check_eq(pos_widget.get_input_port_count(), 0, "…and no inputs")
	check_eq(pos_widget.get_output_port_type(0), NoisePort.Type.VEC3, "…a Vec3")
	var out_widget := editor.node_widget(&"output_0")
	check_eq(out_widget.get_input_port_count(), 4, "Output shows Displace, Tint, Texture and Bump inputs")
	check_eq(out_widget.get_output_port_count(), 0, "…and no outputs")
	check_eq(out_widget.get_input_port_type(0), NoisePort.Type.FLOAT, "Displace is a Float slot")
	check_eq(out_widget.get_input_port_type(1), NoisePort.Type.FLOAT, "Tint is a Float slot")
	check_eq(out_widget.get_input_port_type(2), NoisePort.Type.VEC3, "Texture is a Vec3 slot")
	check_eq(out_widget.get_input_port_type(3), NoisePort.Type.FLOAT, "Bump is a Float slot")

	# --------------------------------------------- a node with rows and preview
	var vn := graph.add_node(&"value_noise", Vector2(260, 40))
	editor.show_graph(graph)
	await frames(3)
	var vn_widget := editor.node_widget(vn)
	check(vn_widget != null, "the Value noise node got a widget")
	check_eq(vn_widget.get_input_port_count(), 1, "it has its P input")
	check_eq(vn_widget.get_output_port_count(), 1, "and its Float output")
	check_eq(vn_widget.get_output_port_type(0), NoisePort.Type.FLOAT, "…a Float slot")

	var scale_row := editor.row(vn, &"scale")
	check(scale_row != null and scale_row is NoiseParamRow, "there is a NoiseParamRow for scale")
	check(editor.row(vn, &"octaves") != null, "…and one for octaves")
	check(editor.row(vn, &"no_such") == null, "an unknown param gives null")
	# editing a row writes the graph's table
	scale_row.spin_box().value = 3.25
	await frames(1)
	check_approx(float(graph.node(vn).table.get_value(&"scale")), 3.25,
		"editing a row writes the graph's own table", 0.02)   # the spin snaps to its step grid

	# previews are ColorRects with a ShaderMaterial
	check(_count_of_type(vn_widget, "ColorRect") >= 1, "the Value noise preview is a ColorRect")
	check(editor.preview_count() > 0, "the editor tracks its previews")
	var preview_rect: ColorRect = null
	for child in vn_widget.get_children():
		if child is ColorRect:
			preview_rect = child
	check(preview_rect != null and preview_rect.material is ShaderMaterial,
		"the preview carries a ShaderMaterial")
	check(preview_rect != null and (preview_rect.material as ShaderMaterial).shader != null
			and not (preview_rect.material as ShaderMaterial).shader.get_shader_uniform_list().is_empty(),
		"…whose compiled preview shader is valid")
	check(preview_rect != null and preview_rect.custom_minimum_size.x >= 120.0,
		"…wide enough to read")

	# ------------------------------------------------ the two collapse toggles
	var state := graph.node(vn)
	var toggles: Array[Button] = []
	for child in vn_widget.get_children():
		for grandchild in child.get_children():
			if grandchild is Button and (grandchild as Button).toggle_mode:
				toggles.append(grandchild)
	check(toggles.size() >= 2, "the node has a controls toggle and a preview toggle (found %d)" % toggles.size())
	var height_before := vn_widget.size.y
	state.controls_open = false
	editor.show_graph(graph)
	await frames(3)
	check(editor.row(vn, &"scale") == null or not editor.row(vn, &"scale").visible,
		"with controls closed the rows are gone")
	check_eq(editor.node_widget(vn).get_input_port_count(), 1, "…and the slots stay connectable")
	check(editor.node_widget(vn).size.y <= height_before + 1.0, "…and the node shrank")
	state.controls_open = true
	state.preview_open = false
	editor.show_graph(graph)
	await frames(3)
	check(editor.row(vn, &"scale") != null, "reopening the controls brings the rows back")
	check(_count_of_type(editor.node_widget(vn), "ColorRect") == 0, "…and with the preview closed there is no ColorRect")
	state.preview_open = true
	editor.show_graph(graph)
	await frames(3)
	check(_count_of_type(editor.node_widget(vn), "ColorRect") > 0, "reopening the preview brings a ColorRect back")

	# ------------------------------------------------------------ the add menu
	var menu := editor.add_menu()
	check(menu is PopupMenu, "there is an add-node menu")
	var listed := 0
	for i in menu.item_count:
		if not menu.is_item_separator(i):
			listed += 1
	check_eq(listed, NoiseNodeRegistry.all().size(), "it lists every type (%d)" % NoiseNodeRegistry.all().size())
	var separators := 0
	for i in menu.item_count:
		if menu.is_item_separator(i):
			separators += 1
	check(separators >= NoiseNodeRegistry.groups().size() - 1, "…grouped by group (%d separators)" % separators)
	var tooltipped := 0
	for i in menu.item_count:
		if not menu.is_item_separator(i) and menu.get_item_tooltip(i).length() > 20:
			tooltipped += 1
	check_eq(tooltipped, listed, "…and every entry carries its description as a tooltip")

	# choosing one emits a request; the editor does NOT add the node itself
	var requests: Array = []
	editor.add_node_requested.connect(func(type_id: StringName, at: Vector2) -> void: requests.append([type_id, at]))
	var nodes_before := graph.nodes.size()
	for i in menu.item_count:
		if not menu.is_item_separator(i) and not menu.is_item_disabled(i):
			menu.id_pressed.emit(menu.get_item_id(i))
			break
	await frames(1)
	check_eq(requests.size(), 1, "choosing an entry emits add_node_requested once")
	check_eq(graph.nodes.size(), nodes_before, "…and does NOT add the node itself")
	check(requests.size() == 1 and NoiseNodeRegistry.has_type(requests[0][0]), "…with a real type id")

	# --------------------------------------- connections go through can_connect
	var tr := graph.add_node(&"transform", Vector2(120, 300))
	editor.show_graph(graph)
	await frames(3)
	var links_before := graph.links.size()
	ge.connection_request.emit(String(&"position_0"), 0, String(tr), 0)   # Vec3 -> Vec3: legal
	await frames(1)
	check_eq(graph.links.size(), links_before + 1, "a legal connection reaches graph.connect_ports")
	ge.connection_request.emit(String(&"position_0"), 0, String(&"output_0"), 0)  # Vec3 -> Float: illegal
	await frames(1)
	check_eq(graph.links.size(), links_before + 1, "an illegal connection is refused at connection time")
	ge.disconnection_request.emit(String(&"position_0"), 0, String(tr), 0)
	await frames(1)
	check_eq(graph.links.size(), links_before, "a disconnection reaches graph.disconnect_ports")

	# ------------------------------------- deleting a wire you can point at
	graph.connect_ports(&"position_0", 0, tr, 0)
	await frames(3)
	var wp: GraphNode = editor.node_widget(&"position_0")
	var wt: GraphNode = editor.node_widget(tr)
	var wire_mid: Vector2 = (wp.position_offset + wp.get_output_port_position(0)
		+ wt.position_offset + wt.get_input_port_position(0)) / 2.0
	var wire_menu := editor.wire_menu()
	ge.popup_request.emit(wire_mid)
	await frames(1)
	check(wire_menu.visible, "right-clicking a wire opens the wire menu")
	check(wire_menu.get_item_text(0).contains("Disconnect"), "…with a Disconnect entry")
	wire_menu.id_pressed.emit(wire_menu.get_item_id(0))
	wire_menu.hide()
	await frames(2)
	check_eq(graph.links.size(), links_before, "choosing Disconnect removes the link")

	# Delete over the highlighted wire. The headless viewport is clamped to a tiny
	# window, so a pushed off-screen mouse motion never routes to the GraphEdit;
	# drive its gui_input directly to hover the wire, then press Delete.
	graph.node(tr).position = Vector2(700, 520)
	graph.connect_ports(&"position_0", 0, tr, 0)
	editor.show_graph(graph)
	await frames(3)
	wp = editor.node_widget(&"position_0")
	wt = editor.node_widget(tr)
	wire_mid = (wp.position_offset + wp.get_output_port_position(0)
		+ wt.position_offset + wt.get_input_port_position(0)) / 2.0
	var motion := InputEventMouseMotion.new()
	motion.position = wire_mid
	ge.gui_input.emit(motion)
	var keydown := InputEventKey.new()
	keydown.keycode = KEY_DELETE
	keydown.physical_keycode = KEY_DELETE
	keydown.pressed = true
	ge.gui_input.emit(keydown)
	await frames(1)
	check_eq(graph.links.size(), links_before, "Delete over a wire removes it")
	# Backspace works too.
	graph.connect_ports(&"position_0", 0, tr, 0)
	await frames(1)
	ge.gui_input.emit(motion)
	var backspace := InputEventKey.new()
	backspace.keycode = KEY_BACKSPACE
	backspace.physical_keycode = KEY_BACKSPACE
	backspace.pressed = true
	ge.gui_input.emit(backspace)
	await frames(1)
	check_eq(graph.links.size(), links_before, "Backspace over a wire removes it too")

	# ------------------------------------------------------------ deletion
	var deletable := graph.add_node(&"constant", Vector2(500, 400))
	editor.show_graph(graph)
	await frames(3)
	var count_before := graph.nodes.size()
	ge.delete_nodes_request.emit([String(deletable)])
	await frames(2)
	check_eq(graph.nodes.size(), count_before - 1, "a delete request removes the node")
	ge.delete_nodes_request.emit([String(graph.position_id()), String(graph.output_id())])
	await frames(2)
	check(graph.node(graph.position_id()) != null, "Position cannot be deleted")
	check(graph.node(graph.output_id()) != null, "…nor Output")

	# ------------------------------------------- Output's extra control + hook
	var out_w := editor.node_widget(graph.output_id())
	check(_count_of_type(out_w, "ColorPickerButton") == 1, "Output's tint picker is built into its node")
	var heard: Array = []
	graph.node_changed.connect(func(id: StringName, _p: StringName) -> void: heard.append(id))
	var picker := _find_color_picker(out_w)
	check(picker != null, "the tint picker is reachable")
	if picker != null:
		picker.color_changed.emit(Color(0.2, 0.4, 0.6, 1.0))
	await frames(1)
	check(heard.has(graph.output_id()), "a tint edit reaches notify_node_changed through the container meta")
	var tc: Variant = graph.node(graph.output_id()).extras.get("tint_color", [])
	check(tc is Array and (tc as Array).size() == 4, "…and stored a four-float Array, not a Color")

	# --------------------------------------------- moving a node writes the graph
	var moved := editor.node_widget(vn)
	moved.position_offset = Vector2(321, 123)
	ge.end_node_move.emit()
	await frames(1)
	check(graph.node(vn).position.is_equal_approx(Vector2(321, 123)),
		"dragging a node writes its position back, so a save keeps the layout")

	# --------------------------------------------- changing the Extent is safe
	editor.extent_spin().value = 8.0
	await frames(1)
	check(not editor.is_empty(), "changing the preview Extent does not break the editor")

	editor.queue_free()
	await frames(2)
