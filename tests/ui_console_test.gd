extends "res://tests/test_case.gd"
## The console driven like a player, in a scaled headless root: the wheel over a
## row label, a slider and an unfocused spin box scrolls the Shape list without
## changing any value; a trackpad pan scrolls; a click on the Colour tab shows
## it, its Colour dropdown opens on a click and a click on "Blue" recolours; a Source dropdown binds Axis A; a
## click on a slider track and a drag of its grabber set the value; typing into
## a spin box and pressing Enter writes the table; and the Movement pane's Add
## axis, key capture, rename, zero and remove all work by clicks and keys; and
## W, A, S or D leaves the console for the game unless a free-text field is
## being typed into.
##
## At the console's default size the Shape inspector spans the full width above
## the Movement pane, so the sliders are wide enough to drag and every axis
## line, its ✕ included, lies inside the window; the slider and Movement checks
## run at that size.

var ui: UiDriver
var shapes: ShapeList
var table: AttributeTable
var look: AttributeTable
var km: Keymap
var console: ConsoleWindow
var scroll: ScrollContainer


func run() -> void:
	ui = UiDriver.new(self)
	await ui.setup()
	shapes = ShapeList.new()
	table = shapes.table(0)
	km = Keymap.new()
	km.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	var clock := Clock.new()
	root.add_child(clock)
	console = ConsoleWindow.new()
	look = AttributeTable.new(ShapeCatalogue.scene_specs())
	console.setup(shapes, look, km, clock, ShapeCatalogue.group_tooltips(), func() -> float: return 1.0)
	root.add_child(console)
	# Shorter than the list, so there is real scroll range.
	console.size = Vector2i(1000, 400)
	console.open()
	await ui.frames(3)
	scroll = console.shape_pane().scroll_container()

	await _opens_on_screen()
	await _wheel_scrolls_without_editing()
	await _pan_scrolls()
	await _colour_dropdown()
	await _source_dropdown()
	await _spin_typing()
	await _layout_at_default_size()
	await _slider_click_and_drag()
	await _shape_list()
	await _movement_pane()
	await _zoom_keys()
	await _wasd_leaves_for_game()

	for action in InputMap.get_actions():
		if String(action).begins_with("axis_"):
			InputMap.erase_action(action)
	console.queue_free()
	clock.queue_free()
	await ui.frames(1)


func _opens_on_screen() -> void:
	check(console.visible and console.is_embedded(), "the console opens as a window embedded in the root (headless has no native sub-windows)")
	var surface := root.get_visible_rect()
	var rect := Rect2(Vector2(console.position), Vector2(console.size))
	check(surface.encloses(rect), "it opens wholly inside the main window (%s in %s)" % [rect, surface])
	check(scroll != null, "the Shape pane is a ScrollContainer")
	var bar := scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page + 100.0,
		"the Shape list is taller than the window, so it can scroll (range %.0f, page %.0f)" % [bar.max_value, bar.page])
	var ss := console.self_similarity_label()
	check(ss != null and ss.is_visible_in_tree() and ui.global_rect(ss).end.y <= ui.global_rect(scroll).position.y + 1.0
		and ui.global_rect(console.shape_pane()).encloses(ui.global_rect(ss)),
		"the self-similarity line is on screen at the top of the Shape tab, above the list")
	check(ss != null and ss.text.begins_with("Self-similar: "), "and reads as one (%s)" % (ss.text if ss else "none"))


## The first row (in list order) of the given widget kind that is wholly inside
## the visible part of the list.
func _visible_widget(kind: String) -> Control:
	var view := ui.global_rect(scroll)
	for spec in table.specs:
		var row := console.inspector().row(spec.id)
		if row == null or not row.visible:
			continue
		var c: Control = null
		match kind:
			"label":
				c = row.get_child(0) as Control
			"slider":
				c = row.value_control() as HSlider
			"spin":
				c = row.spin_box()
		if c != null and c.is_visible_in_tree() and view.encloses(ui.global_rect(c)):
			return c
	return null


func _values() -> Dictionary:
	return table.defaults().duplicate()


func _wheel_scrolls_without_editing() -> void:
	check_eq(scroll.scroll_vertical, 0, "the list starts at the top")
	var before := _values()
	var label := _visible_widget("label")
	check(label is Label, "a row label is on screen")
	var at := scroll.scroll_vertical
	await ui.wheel(label, true, 2)
	check(scroll.scroll_vertical > at, "the wheel over a row label scrolls the list (%d -> %d)" % [at, scroll.scroll_vertical])

	var slider := _visible_widget("slider")
	check(slider is HSlider, "a slider is on screen")
	at = scroll.scroll_vertical
	await ui.wheel(slider, true, 2)
	check(scroll.scroll_vertical > at, "the wheel over a slider scrolls the list (%d -> %d)" % [at, scroll.scroll_vertical])

	var spin := _visible_widget("spin") as SpinBox
	check(spin != null, "a spin box is on screen")
	check(spin != null and not spin.get_line_edit().has_focus(), "…and it is not focused")
	at = scroll.scroll_vertical
	await ui.wheel(spin, true, 2)
	check(scroll.scroll_vertical > at, "the wheel over an unfocused spin box scrolls the list (%d -> %d)" % [at, scroll.scroll_vertical])
	check_eq(_values(), before, "and no wheel turn changed any value")

	at = scroll.scroll_vertical
	await ui.wheel(_visible_widget("label"), false, 1)
	check(scroll.scroll_vertical < at, "the wheel up scrolls back (%d -> %d)" % [at, scroll.scroll_vertical])


func _pan_scrolls() -> void:
	var at := scroll.scroll_vertical
	await ui.pan(_visible_widget("label"), Vector2(0, 1))
	check(scroll.scroll_vertical > at, "a trackpad pan down scrolls the list (%d -> %d)" % [at, scroll.scroll_vertical])
	at = scroll.scroll_vertical
	await ui.pan(_visible_widget("label"), Vector2(0, -1))
	check(scroll.scroll_vertical < at, "a pan up scrolls it back (%d -> %d)" % [at, scroll.scroll_vertical])


func _colour_dropdown() -> void:
	var tab_bar := console.tabs().get_tab_bar()
	await ui.click_at(ui.control_point(tab_bar, tab_bar.get_tab_rect(2).get_center()))
	await ui.frames(1)
	check_eq(console.tabs().current_tab, 2, "a click on the Material tab shows it")
	var colour_scroll := console.material_inspector().get_child(0) as ScrollContainer
	var option := console.material_inspector().row(&"color_mode").value_control() as OptionButton
	check(await ui.scroll_to(colour_scroll, option), "the wheel brings the Colour row into view")
	await ui.click(option)
	var popup := option.get_popup()
	check(popup.visible, "a click on the Colour dropdown opens its list")
	check_eq(popup.item_count, FractalParams.COLOR_MODE_NAMES.size(), "the list has every colour mode")
	var popup_rect := Rect2(ui.window_origin(popup), Vector2(popup.size))
	check(root.get_visible_rect().encloses(popup_rect),
		"the open list fits inside the main window (%s)" % popup_rect)
	check(popup.size.y > popup.item_count * 16.0, "…at full size, %d px tall for %d items" % [popup.size.y, popup.item_count])
	var clicked := await ui.select_popup_item(popup, "Blue")
	check(clicked, "the mouse finds and clicks Blue")
	await ui.frames(1)
	check_eq(int(look.get_default(&"color_mode")), 5, "clicking Blue sets color_mode to Blue (5) in the look table")
	check_eq(option.get_item_text(option.selected), "Blue", "the dropdown now shows Blue")
	check(not popup.visible, "and the list closed")
	console.show_tab(0)
	await ui.frames(1)


func _source_dropdown() -> void:
	var row := console.inspector().row(&"box_scale")
	var src := row.source_option()
	check(await ui.scroll_to(scroll, src), "the wheel brings the Scale row back into view")
	check(await ui.select_option(src, "Axis A"), "the Source dropdown opens and Axis A is clicked")
	await ui.frames(1)
	var b := table.binding(&"box_scale")
	check(b != null and b.source == &"a", "selecting Axis A binds Scale to it")
	km.axes().set_value(&"a", 0.5)
	console.set_resolved([BindingResolver.resolve(table, km.axes().values(), 0.0)])
	await ui.frames(1)
	check(row.readout().visible, "the row shows a readout of the value in use")
	check(row.readout().text.contains("-1.59"), "…default -2.09 plus gain 1 x 0.5 (%s)" % row.readout().text)
	km.axes().set_value(&"a", 0.0)


func _layout_at_default_size() -> void:
	console.size = ConsoleWindow.DEFAULT_SIZE
	console.open()   # re-centred over the main window at its new size
	await ui.frames(2)
	var win := Rect2(ui.window_origin(console), Vector2(console.size))
	check(root.get_visible_rect().encloses(win), "at its default size the console fits in the main window (%s)" % win)
	var inspector := console.shape_pane()
	var pane := console.movement_pane()
	check(ui.global_rect(inspector).size.x >= console.size.x - 20.0,
		"the Shape pane spans the console's width (%.0f of %d)" % [ui.global_rect(inspector).size.x, console.size.x])
	check(ui.global_rect(pane).position.y >= ui.global_rect(inspector).end.y,
		"the Movement pane sits below it")
	check(ui.global_rect(inspector).size.y > ui.global_rect(pane).size.y,
		"and the Shape pane gets most of the height (%.0f over %.0f)" % [ui.global_rect(inspector).size.y, ui.global_rect(pane).size.y])
	for id in [&"box_scale", &"fold_limit", &"size"]:
		var c := console.inspector().row(id).value_control()
		if c is HSlider:
			check(c.size.x >= 200.0, "the %s slider is wide enough to drag (%.0f px)" % [id, c.size.x])
	check(win.encloses(ui.global_rect(pane)),
		"the Movement pane lies wholly inside the window (%s in %s)" % [ui.global_rect(pane), win])
	pane.show_zoom_limit(true)
	await ui.frames(1)
	check(pane.zoom_label.is_visible_in_tree() and win.encloses(ui.global_rect(pane.zoom_label)),
		"the zoom limit readout, when shown, is inside the window (%s)" % ui.global_rect(pane.zoom_label))
	check(win.encloses(ui.global_rect(pane.reset_camera_button)),
		"and so is Reset camera beside it (%s)" % ui.global_rect(pane.reset_camera_button))
	pane.show_zoom_limit(false)
	await ui.frames(1)
	pane.show_zoom_limit(true)
	pane.show_deep(20)
	await ui.frames(1)
	check(pane.deep_label.is_visible_in_tree() and win.encloses(ui.global_rect(pane.deep_label)),
		"the deep readout, shown beside the zoom limit, is inside the window (%s)" % ui.global_rect(pane.deep_label))
	check(win.encloses(ui.global_rect(pane.reset_camera_button)),
		"and Reset camera still is (%s)" % ui.global_rect(pane.reset_camera_button))
	pane.show_deep(0)
	pane.show_zoom_limit(false)
	await ui.frames(1)
	for id in pane.line_ids():
		var line := pane.axis_line(id)
		for key in ["label", "zero", "pos", "neg", "remove"]:
			var w := line[key] as Control
			check(win.encloses(ui.global_rect(w)), "axis %s: its %s widget is inside the window (%s)" % [id, key, ui.global_rect(w)])


func _slider_click_and_drag() -> void:
	var row := console.inspector().row(&"fold_limit")
	var slider := row.value_control() as HSlider
	check(await ui.scroll_to(scroll, slider), "the Fold limit slider is in view")
	await ui.click_at(ui.global_point(slider, Vector2(0.75, 0.5)))
	var v := float(table.get_default(&"fold_limit"))
	check(v > 2.0 and v < 2.5, "a click three quarters along the slider sets Fold limit near 2.25 (%.3f)" % v)
	check_approx(row.spin_box().value, v, "the spin box follows the slider")
	var grab := ui.global_point(slider, Vector2(slider.value / slider.max_value, 0.5))
	await ui.drag(grab, ui.global_point(slider, Vector2(0.25, 0.5)))
	v = float(table.get_default(&"fold_limit"))
	check(v > 0.5 and v < 1.0, "dragging the grabber to a quarter sets it near 0.75 (%.3f)" % v)


func _spin_typing() -> void:
	var row := console.inspector().row(&"min_radius")
	var spin := row.spin_box()
	check(await ui.scroll_to(scroll, spin), "the Min radius spin box is in view")
	await ui.type_text(spin.get_line_edit(), "0.55")
	check_approx(float(table.get_default(&"min_radius")), 0.55, "typing 0.55 and Enter writes the table")
	check_approx((row.value_control() as HSlider).value, 0.55, "and the slider follows")
	spin.get_line_edit().release_focus()
	await ui.frames(1)


## The shape list by clicks: Add shape appends a second entry whose header sits
## above its own panel; clicking its arrow collapses it (the panel hides) and
## again expands it; clicking the first header selects the first shape; typing
## a label renames it; its ✕ removes it.
func _shape_list() -> void:
	var pane := console.shape_pane()
	await ui.click(pane.add_button())
	await ui.frames(2)
	check_eq(shapes.count(), 2, "a click on Add shape adds a shape")
	check_eq(pane.entry_count(), 2, "with its own entry")
	check_eq(pane.selected(), 1, "selected")
	var w := pane.entry_widgets(1)
	check(await ui.scroll_to(scroll, w["header"]), "the new entry's header scrolls into view")
	var header_rect := ui.global_rect(w["header"])
	var panel_rect := ui.global_rect(pane.inspector(1))
	check(panel_rect.position.y >= header_rect.end.y - 1.0, "its panel sits below its header")
	await ui.click(w["arrow"])
	check(not pane.is_expanded(1), "a click on the arrow collapses it")
	check(not pane.inspector(1).is_visible_in_tree(), "and its panel is hidden")
	await ui.click(w["arrow"])
	check(pane.is_expanded(1) and pane.inspector(1).is_visible_in_tree(), "another click expands it")
	var first := pane.entry_widgets(0)
	check(await ui.scroll_to(scroll, first["header"]), "the first header scrolls into view")
	await ui.click_at(ui.global_point(first["header"], Vector2(0.9, 0.5)))   # the empty part of the header
	check_eq(pane.selected(), 0, "a click on the first header selects the first shape")
	check(console.inspector() == pane.inspector(0), "and inspector() follows")
	check(await ui.scroll_to(scroll, w["label"]), "the second entry's label is in view")
	await ui.type_text(w["label"], "Inner")
	await ui.frames(1)
	check_eq(shapes.label(1), "Inner", "typing a label and Enter renames the shape")
	w = pane.entry_widgets(1)
	check(await ui.scroll_to(scroll, w["remove"]), "its ✕ is in view")
	await ui.click(w["remove"])
	await ui.frames(2)
	check_eq(shapes.count(), 1, "a click on ✕ removes the shape")
	check_eq(pane.entry_count(), 1, "and its entry")


func _movement_pane() -> void:
	var pane := console.movement_pane()
	var before := km.axes().list().size()
	await ui.click(pane.add_button())
	await ui.frames(2)
	check_eq(km.axes().list().size(), before + 1, "a click on Add axis adds an axis")
	var id: StringName = &""
	for axis in km.axes().list():
		if axis.id != &"a":
			id = axis.id
	var line := pane.axis_line(id)
	check(not line.is_empty(), "…with its own line in the pane (%s)" % id)
	if line.is_empty():
		return

	# key capture: click the positive key button, then press T
	var pos: KeyCaptureButton = line["pos"]
	await ui.click(pos)
	check(pos.is_capturing(), "a click on the key button starts a capture")
	await ui.tap(KEY_T)
	check(not pos.is_capturing(), "pressing a key ends it")
	check_eq(km.positive_key(id), KEY_T, "and binds T as the axis's positive key")
	var events := InputMap.action_get_events(StringName("axis_%s_pos" % id))
	check(events.size() == 1 and (events[0] as InputEventKey).physical_keycode == KEY_T,
		"the InputMap action follows")

	# rename by typing into the label field
	var src := console.inspector().row(&"box_scale").source_option()
	await ui.type_text(line["label"], "Warp")
	await ui.frames(1)
	check_eq(km.axes().label(id), "Warp", "typing a new label and Enter renames the axis")
	var texts: Array = []
	for i in src.item_count:
		texts.append(src.get_item_text(i))
	check(texts.has("Warp"), "and the Source dropdowns list the new name (%s)" % [texts])
	(line["label"] as LineEdit).release_focus()

	# the 0 button zeroes the axis
	km.axes().set_value(id, 3.0)
	await ui.click(line["zero"])
	check_approx(km.axes().value(id), 0.0, "a click on 0 zeroes the axis")

	# the remove button (inside the window at the default size) drops it, and
	# the dropdowns follow
	var win := Rect2(ui.window_origin(console), Vector2(console.size))
	check(win.encloses(ui.global_rect(line["remove"])), "the new line's ✕ is inside the window")
	await ui.click(line["remove"])
	await ui.frames(2)
	check(not km.axes().has(id), "a click on ✕ removes the axis at the default console size")
	texts.clear()
	for i in src.item_count:
		texts.append(src.get_item_text(i))
	check(not texts.has("Warp"), "and the Source dropdowns drop it (%s)" % [texts])


## A Cmd (or Ctrl) chord pushed through the root, to whatever has focus.
func _chord(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := ui.key_event(keycode, pressed)
		ev.meta_pressed = true
		ev.ctrl_pressed = true
		root.push_input(ev, true)
		await ui.frames(1)


## A control's height as drawn in the embedder: its logical height through the
## window's final transform, which carries the content scale.
func _drawn_height(control: Control) -> float:
	return control.size.y * console.get_final_transform().get_scale().y


func _zoom_keys() -> void:
	var base := UiScale.factor_for(console)
	var label := console.inspector().row(&"box_scale").get_child(0) as Control
	var before := _drawn_height(label)
	var width := console.inspector().size.x
	var spin := console.inspector().row(&"box_scale").spin_box()
	spin.get_line_edit().grab_focus()
	var value := spin.value
	await _chord(KEY_EQUAL)
	check_approx(console.zoom, 1.1, "Cmd+= zooms the console in a step, a spin box focused or not")
	check_approx(console.content_scale_factor, base * 1.1, "through its content scale")
	check(_drawn_height(label) > before * 1.05,
		"so its text draws bigger (%.1f -> %.1f px)" % [before, _drawn_height(label)])
	check(console.inspector().size.x < width,
		"and the panes reflow into the fewer logical units the window now holds")
	check_approx(spin.value, value, "and the focused spin box is untouched")
	spin.get_line_edit().release_focus()
	await _chord(KEY_MINUS)
	await _chord(KEY_MINUS)
	check_approx(console.zoom, 0.9, "Cmd+- zooms out a step at a time")
	await _chord(KEY_0)
	check_approx(console.zoom, 1.0, "Cmd+0 resets the zoom")
	check_approx(console.content_scale_factor, base, "and the content scale")


func _wasd_leaves_for_game() -> void:
	var asked := [0]
	console.game_focus_requested.connect(func(): asked[0] += 1)

	# mid-edit in a spin box: W commits what was typed, drops focus, types nothing
	var row := console.inspector().row(&"min_radius")
	var spin := row.spin_box()
	check(await ui.scroll_to(scroll, spin), "the Min radius spin box is in view")
	await ui.type_text(spin.get_line_edit(), "0.6", false)
	check(console.gui_get_focus_owner() == spin.get_line_edit(), "typing into a spin box focuses its field")
	await ui.gui_key(KEY_W, true)
	await ui.gui_key(KEY_W, false)
	check_eq(asked[0], 1, "W in a spin box asks for the game")
	check(console.gui_get_focus_owner() == null, "and the spin box lets go of focus")
	check_approx(float(table.get_default(&"min_radius")), 0.6, "committing what was typed")
	check(not spin.get_line_edit().text.contains("w"), "and the W is not typed (%s)" % spin.get_line_edit().text)

	# a slider holding focus: D leaves too
	var slider := row.value_control() as HSlider
	slider.grab_focus()
	await ui.gui_key(KEY_D, true)
	await ui.gui_key(KEY_D, false)
	check_eq(asked[0], 2, "D with a slider focused asks for the game")
	check(console.gui_get_focus_owner() == null, "and the slider lets go of focus")

	# a free-text field mid-edit keeps the letters; after Enter, S leaves
	var pane := console.movement_pane()
	var line := pane.axis_line(&"a")
	var label := line["label"] as LineEdit
	await ui.type_text(label, "wasd", false)
	check_eq(asked[0], 2, "typing WASD into an axis label is typing, not flying")
	check_eq(label.text, "wasd", "the letters land in the field")
	await ui.gui_key(KEY_ENTER, true)
	await ui.gui_key(KEY_ENTER, false)
	check(not label.is_editing(), "Enter ends the edit")
	await ui.gui_key(KEY_S, true)
	await ui.gui_key(KEY_S, false)
	check_eq(asked[0], 3, "after which S asks for the game")
	check_eq(label.text, "wasd", "without typing into the label")

	# Cmd+S is a save, not a move
	var cmd_s := ui.key_event(KEY_S, true)
	cmd_s.meta_pressed = true
	cmd_s.ctrl_pressed = OS.get_name() != "macOS"
	check(not TextFocus.is_game_key(cmd_s, console), "Cmd/Ctrl+S is not a game key")
