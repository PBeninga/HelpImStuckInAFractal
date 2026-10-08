extends "res://tests/test_case.gd"
## PaletteWindow (ported from Fractacular): twelve sliders over one Palette,
## the readouts under them, the curve plot and the gradient strip following the
## model, and Reset. Here also: the hint shows outside the Palette mode, and
## set_resolved moves the strip for a bound component.
##
## The window owns no colour of its own — every check here is "the slider and
## the palette say the same thing", in both directions.


func _walk_tooltips(node: Node, missing: Array) -> void:
	for c in node.get_children():
		if c is Label or c is Button or c is Slider:
			if String((c as Control).tooltip_text).strip_edges().is_empty():
				missing.append("%s (%s)" % [c.name, c.get_class()])
		_walk_tooltips(c, missing)


func run() -> void:
	var palette := Palette.new()
	var window := PaletteWindow.new()
	window.setup(palette)
	root.add_child(window)
	window.size = Vector2(440, 256)
	await frames(1)

	# --- twelve sliders, one per number, each on its vector's range ---
	var found := 0
	for vector in 4:
		for channel in 3:
			var slider := window.slider(vector, channel)
			if slider == null:
				continue
			found += 1
			var range_: Vector2 = Palette.RANGES[vector]
			check_approx(slider.min_value, range_.x, "%s.%s slider starts at its minimum" % [
				Palette.VECTOR_NAMES[vector], Palette.CHANNEL_NAMES[channel]])
			check_approx(slider.max_value, range_.y, "%s.%s slider ends at its maximum" % [
				Palette.VECTOR_NAMES[vector], Palette.CHANNEL_NAMES[channel]])
			check(not slider.scrollable, "%s.%s slider ignores the mouse wheel" % [
				Palette.VECTOR_NAMES[vector], Palette.CHANNEL_NAMES[channel]])
			check_approx(slider.step, Palette.STEP, "%s.%s slider steps by a hundredth" % [
				Palette.VECTOR_NAMES[vector], Palette.CHANNEL_NAMES[channel]])
			check_approx(slider.value, palette.get_component(vector, channel),
				"%s.%s slider opens on the palette's value" % [
					Palette.VECTOR_NAMES[vector], Palette.CHANNEL_NAMES[channel]])
	check_eq(found, 12, "twelve sliders: A, B, C and D over r, g and b")
	check_eq(window.letter_label(0).text, "A", "the first row is labelled A")
	check_eq(window.letter_label(3).text, "D", "and the last D")
	check(window.formula_label().text.contains("cos"), "the formula is written out: '%s'" % window.formula_label().text)

	# --- a slider writes its one component and nothing else ---
	window.slider(2, 1).value = 2.5
	check_approx(palette.get_component(2, 1), 2.5, "moving C.g writes C.g")
	check_approx(palette.get_component(2, 0), 1.0, "and leaves C.r alone")
	check_eq(palette.a, Palette.DEFAULT_A, "and A entirely alone")
	check(window.value_label(2, 1).text.contains("2.5"),
		"the readout under it follows: '%s'" % window.value_label(2, 1).text)

	# --- and the palette writes back to the slider, wherever the edit came from ---
	palette.set_component(0, 2, 0.25)
	await frames(1)
	check_approx(window.slider(0, 2).value, 0.25, "an edit from elsewhere moves the slider")
	check(window.value_label(0, 2).text.contains("0.25"), "and the readout")

	# --- the plot and the strip redraw whenever the palette moves ---
	var curve_draws := window.curves().redraw_count()
	var strip_draws := window.strip().redraw_count()
	palette.set_component(1, 0, 0.75)
	check(window.curves().redraw_count() > curve_draws, "the curve plot asks to redraw")
	check(window.strip().redraw_count() > strip_draws, "so does the gradient strip")
	var green := window.curves().channel_levels(1)
	check_eq(green.size(), PaletteCurves.SAMPLES, "the plot samples each curve end to end")
	check_approx(green[green.size() - 1], palette.color_at(1.0).g,
		"and its green curve ends on the palette's green at t = 1")
	check_eq(window.strip().color_at_fraction(0.0), palette.color_at(0.0),
		"and the strip's left edge is the palette at t = 0")
	check_eq(window.strip().color_at_fraction(1.0), palette.color_at(1.0),
		"and its right edge the palette at t = 1")

	# --- the hint shows until the Colour mode is Palette ---
	check(window.hint_label().visible, "outside the Palette mode the hint says how to use it")
	palette.table().set_default(&"color_mode", Palette.MODE_ID)
	await frames(1)
	check(not window.hint_label().visible, "in the Palette mode it is gone")

	# --- a bound component: the strip follows the driven value ---
	var bnd := Binding.new()
	bnd.source = &"time"
	palette.table().set_binding(&"palette_a_g", bnd)
	strip_draws = window.strip().redraw_count()
	window.set_resolved({&"palette_a_g": 0.0, &"palette_b_g": 0.0})
	check(window.strip().redraw_count() > strip_draws, "a frame that moves a bound value redraws the strip")
	check_approx(window.strip().color_at_fraction(0.5).g, 0.0, "whose green is now the driven A.g + B.g cos = 0")
	palette.table().set_binding(&"palette_a_g", Binding.new())

	# --- Reset ---
	window.reset_button().pressed.emit()
	await frames(1)
	check_eq(palette.a, Palette.DEFAULT_A, "Reset restores A")
	check_eq(palette.c, Palette.DEFAULT_C, "Reset restores C")
	check_approx(window.slider(2, 1).value, 1.0, "and the sliders come back with it")
	check_approx(window.slider(0, 2).value, 0.5, "every one of them")

	# --- a window with no palette must not crash the app ---
	var lone := PaletteWindow.new()
	root.add_child(lone)
	await frames(1)
	check(lone.slider(0, 0) != null, "a window built without a palette still builds its sliders")
	lone.queue_free()

	# --- tooltips ---
	var missing: Array = []
	_walk_tooltips(window, missing)
	check(missing.is_empty(), "every control and label has a tooltip (missing: %s)" % [missing])
	check(String(window.curves().tooltip_text).strip_edges() != "", "the curve plot has a tooltip")
	check(String(window.strip().tooltip_text).strip_edges() != "", "the gradient strip has a tooltip")

	window.queue_free()
	await frames(2)
