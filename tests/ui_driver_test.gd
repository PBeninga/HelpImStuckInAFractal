extends "res://tests/test_case.gd"
## The headless UI driver delivers real input: a click reaches a Button under
## the root, one inside an embedded Window and one inside a zoomed one; the
## wheel scrolls a ScrollContainer; select_option opens an OptionButton's popup
## inside an embedded Window and picks an item; type_text fills a LineEdit and
## submits.


func _window(at: Vector2i, size: Vector2i) -> Window:
	var w := Window.new()
	w.title = "Driver test"
	w.wrap_controls = false
	w.size = size
	w.position = at
	root.add_child(w)
	w.visible = true
	return w


func _button(text: String, parent: Node, at: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = at
	b.size = Vector2(120, 32)
	parent.add_child(b)
	return b


func run() -> void:
	var ui := UiDriver.new(self)
	await ui.setup()
	check_eq(Vector2i(root.get_visible_rect().size), UiDriver.SURFACE, "setup gives the root a 1280x800 logical surface")

	# --- a Button under the root ---
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var root_button := _button("Root", holder, Vector2(40, 40))
	var hits := {"root": 0, "window": 0, "submitted": ""}
	root_button.pressed.connect(func() -> void: hits["root"] += 1)
	await ui.frames(1)
	await ui.click(root_button)
	check_eq(hits["root"], 1, "a click reaches a Button under the root")

	# --- a Button inside an embedded Window ---
	var w := _window(Vector2i(300, 120), Vector2i(500, 420))
	await ui.frames(1)
	check(w.is_embedded(), "headless sub-windows are embedded in the root")
	var win_button := _button("Window", w, Vector2(20, 20))
	win_button.pressed.connect(func() -> void: hits["window"] += 1)
	await ui.frames(1)
	check(ui.global_center(win_button).is_equal_approx(Vector2(300 + 20 + 60, 120 + 20 + 16)),
		"global coordinates add the embedded window's position (%s)" % ui.global_center(win_button))
	await ui.click(win_button)
	check_eq(hits["window"], 1, "a click reaches a Button inside an embedded Window")
	check_eq(hits["root"], 1, "…and not the one under the root")

	# --- the wheel scrolls a ScrollContainer ---
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 70)
	scroll.size = Vector2(200, 150)
	w.add_child(scroll)
	var tall := VBoxContainer.new()
	scroll.add_child(tall)
	for i in 40:
		var l := Label.new()
		l.text = "line %d" % i
		tall.add_child(l)
	await ui.frames(2)
	check_eq(scroll.scroll_vertical, 0, "the list starts at the top")
	await ui.wheel(scroll, true, 3)
	check(scroll.scroll_vertical > 0, "the wheel scrolls a ScrollContainer (%d)" % scroll.scroll_vertical)
	var after_wheel := scroll.scroll_vertical
	await ui.pan(scroll, Vector2(0, 1))
	check(scroll.scroll_vertical > after_wheel, "a pan gesture scrolls it further (%d)" % scroll.scroll_vertical)

	# --- select_option inside an embedded Window ---
	var option := OptionButton.new()
	for t in ["Red", "Green", "Blue", "Yellow"]:
		option.add_item(t)
	option.position = Vector2(260, 70)
	option.size = Vector2(140, 32)
	w.add_child(option)
	var chosen := [-1]
	option.item_selected.connect(func(i: int) -> void: chosen[0] = i)
	await ui.frames(1)
	var picked := await ui.select_option(option, "Blue")
	check(picked, "select_option found Blue in the open popup")
	check_eq(chosen[0], 2, "…clicking it emits item_selected(2)")
	check_eq(option.selected, 2, "…and the OptionButton shows it")
	await ui.frames(1)
	check(not option.get_popup().visible, "…and the popup closed")

	# --- type_text fills a LineEdit and submits ---
	var edit := LineEdit.new()
	edit.position = Vector2(260, 140)
	edit.size = Vector2(160, 32)
	edit.text = "old"
	w.add_child(edit)
	edit.text_submitted.connect(func(t: String) -> void: hits["submitted"] = t)
	await ui.frames(1)
	await ui.type_text(edit, "Ab1.5")
	check_eq(edit.text, "Ab1.5", "type_text replaces the LineEdit's text key by key")
	check_eq(hits["submitted"], "Ab1.5", "…and Enter submits it")

	# --- a Button inside a zoomed embedded Window (the console's Cmd+= zoom) ---
	var zoomed := _window(Vector2i(820, 120), Vector2i(400, 300))
	zoomed.content_scale_factor = 2.0
	var zoomed_button := _button("Zoomed", zoomed, Vector2(60, 50))
	var zoomed_hits := [0]
	zoomed_button.pressed.connect(func() -> void: zoomed_hits[0] += 1)
	await ui.frames(2)
	check(ui.global_center(zoomed_button).is_equal_approx(Vector2(820 + (60 + 60) * 2, 120 + (50 + 16) * 2)),
		"global coordinates follow the window's content scale (%s)" % ui.global_center(zoomed_button))
	await ui.click(zoomed_button)
	check_eq(zoomed_hits[0], 1, "a click reaches a Button inside a zoomed embedded Window")
	zoomed.queue_free()
	await ui.frames(1)

	# --- keys through Input reach actions ---
	InputMap.add_action(&"ui_driver_test_key")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	InputMap.action_add_event(&"ui_driver_test_key", ev)
	await ui.key(KEY_J, true)
	check(Input.is_action_pressed(&"ui_driver_test_key"), "a key down through Input presses its action")
	await ui.key(KEY_J, false)
	check(not Input.is_action_pressed(&"ui_driver_test_key"), "…and the key up releases it")
	InputMap.erase_action(&"ui_driver_test_key")

	w.queue_free()
	holder.queue_free()
	await ui.frames(1)
