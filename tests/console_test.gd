extends "res://tests/test_case.gd"
## The console window builds both panes; a row edit lands in the table; the
## source dropdown lists the axes and updates on Keymap.changed; the readout
## follows set_resolved; the Movement pane adds, rebinds and removes an axis
## through the API and the key-capture button; a Ctrl tap emits toggle_requested;
## the zoom steps, clamps, signals and follows the Cmd/Ctrl chords.


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
	var table := AttributeTable.new(ShapeCatalogue.specs())
	var km := Keymap.new()
	km.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	var clock := Clock.new()
	root.add_child(clock)
	var console := ConsoleWindow.new()
	console.setup(table, km, clock, ShapeCatalogue.group_tooltips(), func() -> float: return 1.0)
	root.add_child(console)
	console.open()
	await frames(1)

	var inspector := console.inspector()
	var movement := console.movement_pane()

	# --- sized through UiScale: embedded here, so 1:1 in logical units ---
	check_eq(console.size, UiScale.px(ConsoleWindow.DEFAULT_SIZE, console), "the console is sized by UiScale")
	check_approx(console.content_scale_factor, UiScale.factor_for(console), "and takes its content scale")
	check(console.position.y >= 0, "it opens inside the main window, title bar reachable")

	# --- the Shape and Colour tabs share the specs out: one row per spec in all ---
	var colour := console.colour_inspector()
	check_eq(inspector.row_count() + colour.row_count(), table.specs.size(), "one row per spec across the two tabs")
	check(inspector.row(&"box_scale") != null and colour.row(&"box_scale") == null, "Scale is on the Shape tab")
	check(colour.row(&"color_mode") != null and inspector.row(&"color_mode") == null, "Colour is on the Colour tab")
	check(colour.row(&"light_specular") != null, "so is the lighting")
	check(colour.row(&"palette_a_r") != null, "and the palette's twelve numbers")
	check_eq(console.tabs().get_tab_count(), 3, "three tabs")
	check_eq(console.tabs().get_tab_title(0), "Shape", "the first is Shape")
	check_eq(console.tabs().get_tab_title(1), "Colour", "the second Colour")
	check_eq(console.tabs().get_tab_title(2), "View", "the third View")
	check(console.view_pane() != null and console.view_pane().get_parent() == console.tabs(), "which is the View pane")
	check(console.palette_window() != null and console.palette_window().get_parent() != null
		and colour.is_ancestor_of(console.palette_window()), "the palette window heads the Colour tab's list")
	check(console.palette().table() == table, "and edits the console's own table")

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
	console.set_resolved({&"box_scale": -1.59})
	await frames(1)
	check(inspector.row(&"box_scale").readout().visible, "an active binding shows a readout")
	check(inspector.row(&"box_scale").readout().text.contains("-1.59"), "the readout shows the resolved value")

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
