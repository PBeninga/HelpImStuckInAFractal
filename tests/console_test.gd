extends "res://tests/test_case.gd"
## The console window builds both panes; a row edit lands in the table; the
## source dropdown lists the axes and updates on Keymap.changed; the readout
## follows set_resolved; the Movement pane shows and hides its zoom limit
## readout, and adds, rebinds and removes an axis through the API and the
## key-capture button; a Ctrl tap emits toggle_requested;
## the zoom steps, clamps, signals and follows the Cmd/Ctrl chords; the Shape
## tab's self-similarity line shows what it is given.


func _ctrl(pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_CTRL
	ev.pressed = pressed
	ev.echo = false
	return ev


## A Cmd (macOS) / Ctrl (elsewhere) chord key-down.
func _chord(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.meta_pressed = true
	ev.ctrl_pressed = true
	return ev


func run() -> void:
	var shapes := ShapeList.new()
	var table := shapes.table(0)
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	var km := Keymap.new()
	km.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	var clock := Clock.new()
	root.add_child(clock)
	var console := ConsoleWindow.new()
	console.setup(shapes, look, km, clock, ShapeCatalogue.group_tooltips(), func() -> float: return 1.0)
	root.add_child(console)
	console.open()
	await frames(1)

	var inspector := console.inspector()
	var movement := console.movement_pane()
	check(inspector != null, "the console has an inspector for the first shape")

	# --- sized through UiScale: embedded here, so 1:1 in logical units ---
	check_eq(console.size, UiScale.px(ConsoleWindow.DEFAULT_SIZE, console), "the console is sized by UiScale")
	check_approx(console.content_scale_factor, UiScale.factor_for(console), "and takes its content scale")
	check(console.position.y >= 0, "it opens inside the main window, title bar reachable")

	# --- the Shape, Light and Material tabs share the specs out: one row per spec in all ---
	var light := console.light_inspector()
	var material := console.material_inspector()
	check_eq(inspector.row_count() + light.row_count() + material.row_count(), ShapeCatalogue.specs().size(),
		"one row per catalogue spec across the three inspectors")
	check_eq(inspector.row_count(), table.specs.size(), "the shape's panel has a row per shape spec")
	check(inspector.row(&"pos_x") != null and inspector.row(&"size") != null, "the Placement rows are on the shape's panel")
	check(inspector.row(&"box_scale") != null and light.row(&"box_scale") == null and material.row(&"box_scale") == null,
		"Scale is on the Shape tab")
	check(light.row(&"light_color") != null and light.row(&"shadows") != null,
		"Light colour and Shadows are on the Light tab")
	check(material.row(&"color_mode") != null and material.row(&"roughness") != null and material.row(&"texture_strength") != null,
		"Colour mode, Roughness and Texture are on the Material tab")
	check(material.row(&"light_color") == null and light.row(&"color_mode") == null,
		"neither tab holds the other's rows")
	check(material.row(&"palette_a_r") != null, "the palette's twelve numbers are on the Material tab")
	check_eq(console.tabs().get_tab_count(), 4, "four tabs")
	check_eq(console.tabs().get_tab_title(0), "Shape", "the first is Shape")
	check_eq(console.tabs().get_tab_title(1), "Light", "the second Light")
	check_eq(console.tabs().get_tab_title(2), "Material", "the third Material")
	check_eq(console.tabs().get_tab_title(3), "View", "the fourth View")
	check(console.view_pane() != null and console.view_pane().get_parent() == console.tabs(), "which is the View pane")
	check(console.palette_window() != null and material.is_ancestor_of(console.palette_window()),
		"the palette window heads the Material tab's list")
	check(console.palette().table() == look, "and edits the scene's look table")

	# --- a COLOR row's value control is a ColorPickerButton; changing it writes the table ---
	var lc_row := light.row(&"light_color")
	var picker := lc_row.value_control() as ColorPickerButton
	check(picker != null, "the Light colour row's value control is a ColorPickerButton")
	picker.color = Color(0.2, 0.4, 0.6)
	picker.color_changed.emit(picker.color)
	check((look.get_default(&"light_color") as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)),
		"changing the picker writes the look table")

	# --- the self-similarity line: read-only, at the head of the Shape tab ---
	var ss := console.self_similarity_label()
	var pane := console.shape_pane()
	check(ss != null and pane.is_ancestor_of(ss), "the self-similarity line is on the Shape tab")
	check(ss != null and ss.get_parent() == pane.add_button().get_parent() and not pane.scroll_container().is_ancestor_of(ss),
		"beside the Add shape button, above the list of shapes")
	check(ss != null and ss.tooltip_text.contains("self-similar"), "with a tooltip saying what it means")
	console.show_self_similarity({"qualifies": true, "reason": "Julia: all four c fixed"})
	check_eq(ss.text, "Self-similar: yes (Julia: all four c fixed)", "a qualifying shape reads yes, with the reason")
	console.show_self_similarity({"qualifies": false, "reason": "c follows the point"})
	check_eq(ss.text, "Self-similar: no (c follows the point)", "a shape that does not reads no, with the reason")

	# --- a row edit lands in the table ---
	inspector.row(&"box_scale").spin_box().value = 1.0
	check_approx(table.get_default(&"box_scale"), 1.0, "a spin edit writes the table")

	# --- the source dropdown lists None, Time, Axis A ---
	var src := inspector.row(&"box_scale").source_option()
	check_eq(src.item_count, 3, "source has None, Time, Axis A")
	check_eq(src.get_item_text(0), "None", "first is None")
	check_eq(src.get_item_text(1), "Time", "second is Time")
	check_eq(src.get_item_text(2), "Axis A", "third is Axis A")

	# --- adding an axis updates the dropdown (console refreshes on changed) ---
	km.add_axis(&"b", "Axis B", 1.0, KEY_NONE, KEY_NONE)
	await frames(1)
	check_eq(src.item_count, 4, "a new axis appears in the dropdown")
	check_eq(src.get_item_text(3), "Axis B", "named Axis B")

	# --- selecting a source writes the binding; the readout follows set_resolved ---
	src.select(2)                       # Axis A
	src.item_selected.emit(2)
	check_eq(table.binding(&"box_scale").source, &"a", "selecting a source writes the binding")
	console.set_resolved([{&"box_scale": -1.59}])
	await frames(1)
	check(inspector.row(&"box_scale").readout().visible, "an active binding shows a readout")
	check(inspector.row(&"box_scale").readout().text.contains("-1.59"), "the readout shows the resolved value")
	var lb := Binding.new(); lb.source = &"a"; lb.gain = 1.0
	look.set_binding(&"exposure", lb)
	console.set_resolved([{&"box_scale": -1.59}], {&"exposure": 1.7})
	await frames(1)
	check(light.row(&"exposure").readout().visible and light.row(&"exposure").readout().text.contains("1.7"),
		"the look's readouts follow the look values")
	look.set_binding(&"exposure", Binding.new())

	# --- the Shape pane: one entry per shape; Add shape appends, selects and
	# expands; the arrow collapses; ✕ removes (never the last); a relabel
	# reaches the list; a load rebuilds the entries ---
	check_eq(pane.entry_count(), 1, "one entry for one shape")
	check(pane.is_expanded(0), "the first entry starts expanded")
	check(pane.entry_widgets(0)["remove"].disabled, "its ✕ is disabled while it is the only shape")
	pane.add_button().pressed.emit()
	await frames(1)
	check_eq(shapes.count(), 2, "Add shape adds a shape to the list")
	check_eq(pane.entry_count(), 2, "and an entry")
	check_eq(pane.selected(), 1, "the new shape is selected")
	check(pane.is_expanded(1), "and expanded")
	check(console.inspector() == pane.inspector(1), "inspector() is the selected shape's panel")
	check_eq(console.inspector().row_count(), table.specs.size(), "with a row per spec")
	check(not pane.entry_widgets(0)["remove"].disabled, "both ✕ are enabled now")
	var chosen := [-1]
	pane.selected_changed.connect(func(i: int): chosen[0] = i)
	pane.entry_widgets(1)["arrow"].pressed.emit()
	check(not pane.is_expanded(1), "the arrow collapses the entry")
	check(not pane.inspector(1).visible, "hiding its panel")
	pane.entry_widgets(1)["arrow"].pressed.emit()
	check(pane.is_expanded(1) and pane.inspector(1).visible, "and expands it again")
	pane.select(0)
	check_eq(chosen[0], 0, "select() emits selected_changed")
	check(console.inspector() == pane.inspector(0), "and inspector() follows")
	(pane.entry_widgets(1)["label"] as LineEdit).text = "Inner"
	(pane.entry_widgets(1)["label"] as LineEdit).text_submitted.emit("Inner")
	await frames(1)
	check_eq(shapes.label(1), "Inner", "typing a label and Enter renames the shape")
	check_eq((pane.entry_widgets(1)["label"] as LineEdit).text, "Inner", "and the entry shows it")
	var panel_before := pane.inspector(1)
	shapes.set_label(1, "Core")
	check_eq((pane.entry_widgets(1)["label"] as LineEdit).text, "Core", "a relabel from the list reaches the entry")
	check(pane.inspector(1) == panel_before and is_instance_valid(panel_before), "without rebuilding the panels")
	console.set_resolved([{&"box_scale": -1.59}, {&"box_scale": 0.4}])
	pane.entry_widgets(1)["remove"].pressed.emit()
	await frames(1)
	check_eq(shapes.count(), 1, "✕ removes the shape")
	check_eq(pane.entry_count(), 1, "and its entry")
	check(pane.entry_widgets(0)["remove"].disabled, "the last ✕ is disabled again")
	shapes.apply_dict([{"label": "A", "defaults": {}, "bindings": {}}, {"label": "B", "defaults": {"size": 0.1}, "bindings": {}}, {"label": "C", "defaults": {}, "bindings": {}}])
	await frames(1)
	check_eq(pane.entry_count(), 3, "a loaded list rebuilds the entries")
	check_eq((pane.entry_widgets(2)["label"] as LineEdit).text, "C", "with their labels")
	check_approx(pane.inspector(1).row(&"size").spin_box().value, 0.1, "and their values", 1e-9)
	check_eq(pane.inspector(1).row(&"box_scale").source_option().item_count, km.axes().list().size() + 2,
		"every panel lists the sources (None, Time, the axes)")
	shapes.apply_dict([{"label": "Only", "defaults": {}, "bindings": {}}])
	await frames(1)
	check_eq(pane.entry_count(), 1, "and shrinks back on a one-shape load")
	inspector = console.inspector()   # the panels were rebuilt by the loads
	src = inspector.row(&"box_scale").source_option()
	table = shapes.table(0)

	# --- Movement pane: the zoom limit readout shows while set, hidden otherwise ---
	check(movement.zoom_label != null and not movement.zoom_label.visible, "the zoom limit readout starts hidden")
	console.show_zoom_limit(true)
	check(movement.zoom_label.visible and movement.zoom_label.text == "zoom limit",
		"show_zoom_limit(true) shows 'zoom limit' in the Movement pane")
	console.show_zoom_limit(false)
	check(not movement.zoom_label.visible, "and false hides it again")

	# --- Movement pane: the keymap-file strip is gone (keys travel in the level) ---
	check_eq(movement.get_node_or_null("KeymapFiles"), null, "the Movement pane has no keymap file panel")
	check(not (&"save_button" in movement), "and no Save keymap button")

	# --- Movement pane: Add axis grows the keymap ---
	var before := km.axes().list().size()
	movement.add_button().pressed.emit()
	await frames(1)
	check_eq(km.axes().list().size(), before + 1, "Add axis adds an axis to the keymap")

	# --- a key-capture button rebinds through the API ---
	var line := movement.axis_line(&"b")
	check(not line.is_empty(), "Axis B has a line")
	var pos_btn: KeyCaptureButton = line["pos"]
	pos_btn.pressed.emit()                 # begin capture
	pos_btn._capture(KEY_T)                 # press T
	await frames(1)
	check_eq(km.positive_key(&"b"), KEY_T, "the key-capture button rebinds the positive key")
	check(InputMap.action_get_events(&"axis_b_pos").size() == 1, "and the InputMap action followed")

	# --- the remove button drops the axis ---
	movement.axis_line(&"b")["remove"].pressed.emit()
	await frames(1)
	check(not km.axes().has(&"b"), "the remove button drops the axis")
	await frames(1)
	var texts: Array = []
	for i in src.item_count:
		texts.append(src.get_item_text(i))
	check(not texts.has("Axis B"), "and the dropdown drops it too (items: %s)" % [texts])

	# --- a Ctrl tap in the console emits toggle_requested ---
	var toggled := [false]
	console.toggle_requested.connect(func(): toggled[0] = true)
	console.feed_ctrl(_ctrl(true))
	console.feed_ctrl(_ctrl(false))
	check(toggled[0], "a Ctrl tap in the console emits toggle_requested")

	# --- zoom: steps through ZOOM_STEPS, clamps at the ends, signals ---
	var zooms: Array = []
	console.zoom_changed.connect(func(z: float): zooms.append(z))
	var base := UiScale.factor_for(console)
	console.step_zoom(1)
	check_approx(console.zoom, 1.1, "step_zoom(1) goes to the next level")
	check_approx(console.content_scale_factor, base * 1.1, "and scales the window's content")
	console.step_zoom(-1)
	console.step_zoom(-1)
	check_approx(console.zoom, 0.9, "step_zoom(-1) goes back down")
	console.set_zoom(1.6)
	console.step_zoom(1)
	check_approx(console.zoom, 1.75, "a level between steps steps to the next one up")
	for i in 20:
		console.step_zoom(1)
	check_approx(console.zoom, ConsoleWindow.ZOOM_STEPS[-1], "zooming in stops at the largest level")
	console.set_zoom(0.1)
	check_approx(console.zoom, ConsoleWindow.ZOOM_STEPS[0], "set_zoom clamps to the smallest level")
	check_eq(zooms.size(), 7, "each change emits zoom_changed once (%s)" % [zooms])
	console.set_zoom(0.5)
	check_eq(zooms.size(), 7, "setting the same level does not")

	# --- the chords: Cmd/Ctrl with =, +, -, 0 (keypad too); not bare or Alt ---
	console.set_zoom(1.0)
	check(console.zoom_key(_chord(KEY_EQUAL)) and is_equal_approx(console.zoom, 1.1), "Cmd+= zooms in")
	check(console.zoom_key(_chord(KEY_KP_ADD)) and is_equal_approx(console.zoom, 1.25), "Cmd+keypad + zooms in")
	check(console.zoom_key(_chord(KEY_MINUS)) and is_equal_approx(console.zoom, 1.1), "Cmd+- zooms out")
	check(console.zoom_key(_chord(KEY_0)) and is_equal_approx(console.zoom, 1.0), "Cmd+0 resets")
	var bare := _chord(KEY_EQUAL)
	bare.meta_pressed = false
	bare.ctrl_pressed = false
	check(not console.zoom_key(bare), "a bare = is not a zoom chord")
	var alt := _chord(KEY_EQUAL)
	alt.alt_pressed = true
	check(not console.zoom_key(alt), "nor is Cmd+Alt+=")
	check(not console.zoom_key(_chord(KEY_S)), "nor Cmd+S, which goes on to Main")
	check_approx(console.zoom, 1.0, "none of those changed the zoom")

	# clean up the runtime InputMap actions this test created
	# --- each shape's groups show only while it is drawn, headings included ---
	check(inspector.heading("Box").visible, "the Box heading shows on the Mandelbox")
	check(not inspector.heading("KIFS").visible, "the KIFS heading hides on the Mandelbox")
	check(not inspector.heading("Kleinian").visible, "and so does the Kleinian's")
	check(inspector.heading("Fractal").visible and inspector.heading("Render").visible, "the shared headings show")
	table.set_default(&"shape", FractalParams.Shape.KIFS)
	await frames(1)
	check(not inspector.heading("Box").visible and not inspector.heading("Julia").visible,
		"choosing the KIFS hides the Mandelbox's headings")
	check(inspector.heading("KIFS").visible and inspector.heading("KIFS rotation").visible, "and shows the KIFS's")
	check(inspector.row(&"kifs_scale").visible and not inspector.row(&"box_scale").visible, "rows follow too")
	check(not inspector.row(&"kifs_poly_k").visible, "Polyfold k waits for the Polyfold")
	table.set_default(&"kifs_fold", KifsEstimator.FoldSet.POLYFOLD)
	check(inspector.row(&"kifs_poly_k").visible, "and shows with it")
	table.set_default(&"shape", FractalParams.Shape.KLEINIAN)
	check(inspector.heading("Kleinian").visible and not inspector.heading("KIFS").visible, "the Kleinian's turn")
	table.set_default(&"shape", FractalParams.Shape.MANDELBULB)
	await frames(1)
	check(inspector.heading("Mandelbulb").visible and not inspector.heading("Kleinian").visible, "the Mandelbulb's turn")
	check(not inspector.row(&"w").visible, "W hides on the Mandelbulb, which is 3D")
	check(not inspector.row(&"mandelbulb_c_0").visible, "its constant waits for Julia")
	table.set_default(&"mandelbulb_julia", true)
	check(inspector.row(&"mandelbulb_c_0").visible, "and shows with it")
	table.set_default(&"mandelbulb_julia", false)
	table.set_default(&"shape", FractalParams.Shape.MANDELBOX)
	table.set_default(&"kifs_fold", KifsEstimator.FoldSet.COORDINATE)

	for id in [&"a", &"ax1", &"ax2", &"ax3"]:
		if InputMap.has_action(StringName("axis_%s_pos" % id)):
			InputMap.erase_action(StringName("axis_%s_pos" % id))
		if InputMap.has_action(StringName("axis_%s_neg" % id)):
			InputMap.erase_action(StringName("axis_%s_neg" % id))
	console.queue_free()
	clock.queue_free()
	await frames(1)
