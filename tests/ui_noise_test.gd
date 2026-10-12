extends "res://tests/test_case.gd"
## The noise window driven like a player, in a scaled headless root: a
## right-click on the empty canvas opens the add menu and a click on "Value
## noise" adds that node, with a preview, where the click was; wiring it to
## Displace gives the view's shader the noise uniforms; a click on the node's
## Scale slider pushes a new uniform value without rebuilding the shader; the
## Extent spin box changes the previews; the wire menu disconnects; the toolbar's
## New resets the field (the graph has no file of its own — it is saved inside
## the level); and W in the Extent spin box commits it and asks for the game.

const TMP := "user://ui_noise_test.json"
## The canvas a new Value noise node needs to its right and below (its title,
## slot and first rows), so the click that adds it lands on bare canvas.
const NEW_NODE_ROOM := Vector2(310, 280)

var ui: UiDriver
var view: FractalView
var window: NoiseWindow
var editor: NoiseEditor
var vn: StringName = &""


func run() -> void:
	ui = UiDriver.new(self)
	await ui.setup()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	view = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await ui.frames(1)
	view.setup(params, cam)
	window = NoiseWindow.new()
	root.add_child(window)
	window.setup(view)
	window.open()
	await ui.frames(3)
	editor = window.editor()

	var surface := root.get_visible_rect()
	check(window.visible and window.is_embedded(), "the noise window opens embedded in the root")
	check(surface.encloses(Rect2(Vector2(window.position), Vector2(window.size))),
		"it opens wholly inside the main window (%s)" % Rect2(Vector2(window.position), Vector2(window.size)))

	await _add_by_menu()
	if vn == &"":
		check(false, "a Value noise node was added; the rest of the suite needs it")
	else:
		await _wire_to_displace()
		await _scale_slider_is_live()
		await _extent_changes_previews()
		await _wire_menu_disconnects()
		await _new_resets_the_field()
		await _wasd_leaves_for_game()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	window.queue_free()
	view.queue_free()
	await ui.frames(1)


func _material() -> ShaderMaterial:
	return view.get_node("SubViewport/ColorRect").material as ShaderMaterial


func _uniforms() -> Array:
	var names: Array = []
	for u in view.shader_uniform_names():
		names.append(String(u))
	return names


## A point of the GraphEdit canvas with room below and to the right of it for
## a new node (so it lands on bare canvas, not on top of another node).
func _empty_canvas_point() -> Vector2:
	var ge := editor.graph_edit()
	var canvas := ui.global_rect(ge)
	for fraction in [Vector2(0.2, 0.5), Vector2(0.3, 0.55), Vector2(0.1, 0.6), Vector2(0.5, 0.6)]:
		var p: Vector2 = canvas.position + canvas.size * fraction
		var room := Rect2(p, NEW_NODE_ROOM)
		var free := canvas.encloses(Rect2(p, Vector2(NEW_NODE_ROOM.x, 10)))
		for id in window.graph().nodes:
			var w := editor.node_widget(id)
			if w != null and ui.global_rect(w).grow(10.0).intersects(room):
				free = false
		if free:
			return p
	return canvas.get_center()


func _add_by_menu() -> void:
	var ge := editor.graph_edit()
	var before := window.graph().nodes.size()
	var at := _empty_canvas_point()
	await ui.right_click(at)
	var menu := editor.add_menu()
	check(menu.visible, "a right-click on the empty canvas opens the add menu")
	if not menu.visible:
		return
	var menu_rect := Rect2(ui.window_origin(menu), Vector2(menu.size))
	check(root.get_visible_rect().encloses(menu_rect), "the add menu fits inside the main window (%s)" % menu_rect)
	# A tall menu is shifted up to fit, so "at the pointer" means its left edge
	# is at the click and the click is level with some part of it.
	check(absf(menu_rect.position.x - at.x) < 2.0 and at.y >= menu_rect.position.y and at.y <= menu_rect.end.y,
		"…and opens at the pointer (menu %s, click at %s)" % [menu_rect, at])
	check(await ui.select_popup_item(menu, "Value noise"), "the mouse finds and clicks Value noise")
	await ui.frames(2)
	check_eq(window.graph().nodes.size(), before + 1, "clicking it adds one node to the graph")
	for id in window.graph().nodes:
		if window.graph().node(id).type_id == &"value_noise":
			vn = id
	if vn == &"":
		return
	var widget := editor.node_widget(vn)
	check(widget != null, "the editor shows the new node")
	var local: Vector2 = (at - ui.global_rect(ge).position + ge.scroll_offset) / ge.zoom
	check(window.graph().node(vn).position.distance_to(local) < 2.0,
		"the node sits where the canvas was clicked (%s, clicked %s)" % [window.graph().node(vn).position, local])
	var previews := 0
	for child in widget.get_children():
		if child is ColorRect and (child as ColorRect).material is ShaderMaterial:
			previews += 1
	check_eq(previews, 1, "the new node carries a live preview")


func _wire_to_displace() -> void:
	var g := window.graph()
	var ge := editor.graph_edit()
	check(not _uniforms().has("n_%s_scale" % vn), "before wiring, the view's shader has no noise uniforms")
	ge.connection_request.emit(String(g.position_id()), 0, String(vn), 0)
	ge.connection_request.emit(String(vn), 0, String(g.output_id()), 0)
	await ui.frames(2)
	check_eq(g.links.size(), 2, "the two connection requests wire Position -> Value noise -> Displace")
	check(_uniforms().has("n_%s_scale" % vn), "the view's shader gains the node's uniforms (%d uniforms)" % _uniforms().size())
	check(ge.get_connection_list().size() == 2, "the GraphEdit draws the two wires")


func _scale_slider_is_live() -> void:
	var row := editor.row(vn, &"scale")
	check(row != null, "the node has a Scale row")
	if row == null:
		return
	var slider := row.value_control() as HSlider
	var visible := Rect2(ui.window_origin(window), Vector2(window.size)).encloses(ui.global_rect(slider))
	check(visible, "the Scale slider is inside the window (%s)" % ui.global_rect(slider))
	check(slider.size.x >= 80.0, "the Scale slider is wide enough to click along (%.0f px)" % slider.size.x)
	var material := _material()
	var shader_before := material.shader
	var uniform := "n_%s_scale" % vn
	var before := float(material.get_shader_parameter(uniform))
	await ui.click_at(ui.global_point(slider, Vector2(0.75, 0.5)))
	var value := float(window.graph().node(vn).table.get_value(&"scale"))
	check(absf(value - before) > 1.0, "a click along the Scale slider changes the value (%.2f -> %.2f)" % [before, value])
	check_approx(float(material.get_shader_parameter(uniform)), value, "the view's uniform follows", 1e-3)
	check(material.shader == shader_before, "…as a live push, without rebuilding the shader")


func _preview_material() -> ShaderMaterial:
	for child in editor.node_widget(vn).get_children():
		if child is ColorRect and (child as ColorRect).material is ShaderMaterial:
			return (child as ColorRect).material
	return null


func _extent_changes_previews() -> void:
	var spin := editor.extent_spin()
	check(Rect2(ui.window_origin(window), Vector2(window.size)).encloses(ui.global_rect(spin)), "the Extent spin box is in view")
	await ui.type_text(spin.get_line_edit(), "8")
	await ui.frames(1)
	check_approx(spin.value, 8.0, "typing 8 and Enter into Extent sets it")
	var preview := _preview_material()
	check(preview != null and is_equal_approx(float(preview.get_shader_parameter("preview_extent")), 8.0),
		"and every preview's extent uniform follows")
	spin.get_line_edit().release_focus()
	await ui.frames(1)


func _wire_mid(from_id: StringName, to_id: StringName) -> Vector2:
	var from := editor.node_widget(from_id)
	var to := editor.node_widget(to_id)
	var ge := editor.graph_edit()
	var a := ui.global_rect(from).position + from.get_output_port_position(0) * ge.zoom
	var b := ui.global_rect(to).position + to.get_input_port_position(0) * ge.zoom
	return (a + b) * 0.5


func _wire_menu_disconnects() -> void:
	var g := window.graph()
	var links := g.links.size()
	var mid := _wire_mid(vn, g.output_id())
	var bare := true
	for id in g.nodes:
		if ui.global_rect(editor.node_widget(id)).has_point(mid):
			bare = false
	check(bare, "the middle of the Value noise -> Displace wire is on bare canvas (%s)" % mid)
	await ui.right_click(mid)
	var menu := editor.wire_menu()
	check(menu.visible, "a right-click on a wire opens the wire menu")
	if not menu.visible:
		return
	check(await ui.select_popup_item(menu, "Disconnect"), "the mouse clicks Disconnect")
	await ui.frames(2)
	check_eq(g.links.size(), links - 1, "Disconnect removes that wire")
	check(not _uniforms().has("n_%s_scale" % vn), "and with Displace unwired the view's shader drops the noise")
	# wire it back for the save
	editor.graph_edit().connection_request.emit(String(vn), 0, String(g.output_id()), 0)
	await ui.frames(2)


func _new_resets_the_field() -> void:
	# The three-node graph is wired up here (Position → Value noise → Output).
	check(_uniforms().has("n_%s_scale" % vn), "the view's shader has the noise before New")
	await ui.click(editor.new_button)
	await ui.frames(2)
	check_eq(window.graph().nodes.size(), 2, "a click on New resets to Position and Output")
	check(not _uniforms().has("n_%s_scale" % vn), "and the view's shader drops the noise")
	check(view.noise_graph() == window.graph(), "the view follows the new graph")


func _wasd_leaves_for_game() -> void:
	var asked := [0]
	window.game_focus_requested.connect(func(): asked[0] += 1)
	var spin := editor.extent_spin()
	await ui.type_text(spin.get_line_edit(), "6", false)
	check(window.gui_get_focus_owner() == spin.get_line_edit(), "typing into Extent focuses its field")
	await ui.gui_key(KEY_W, true)
	await ui.gui_key(KEY_W, false)
	check_eq(asked[0], 1, "W in the Extent spin box asks for the game")
	check(window.gui_get_focus_owner() == null, "and the spin box lets go of focus")
	check_approx(spin.value, 6.0, "committing what was typed")
	check(not spin.get_line_edit().text.contains("w"), "and the W is not typed (%s)" % spin.get_line_edit().text)
