extends "res://tests/test_case.gd"
## Palette (ported from Fractacular with its expected values): the cosine
## formula itself, component addressing with its slider ranges, the `changed`
## signal the window and the strip live on, and reset. Then what is new here:
## the twelve numbers live in the shape table (so they save with the view and
## can each be bound), and color_at() follows a bound component's driven value.
##
## The expected colors below were computed outside this project, so the test
## pins the formula rather than restating the implementation.


func run() -> void:
	var p := Palette.new()

	# --- the defaults are IQ's rainbow ---
	check_eq(p.a, Vector3(0.5, 0.5, 0.5), "A defaults to the mid grey level")
	check_eq(p.b, Vector3(0.5, 0.5, 0.5), "B defaults to full contrast")
	check_eq(p.c, Vector3(1.0, 1.0, 1.0), "C defaults to one cycle per channel")
	check_eq(p.d, Vector3(0.0, 0.33, 0.67), "D defaults to thirds, which is the rainbow")

	# --- color_at is a + b cos(2π(c t + d)), component-wise ---
	var c0 := p.color_at(0.0)
	check_approx(c0.r, 1.000000, "t=0 red")
	check_approx(c0.g, 0.259123, "t=0 green")
	check_approx(c0.b, 0.259123, "t=0 blue")
	var c25 := p.color_at(0.25)
	check_approx(c25.r, 0.500000, "t=0.25 red")
	check_approx(c25.g, 0.061847, "t=0.25 green")
	check_approx(c25.b, 0.938153, "t=0.25 blue")
	var c5 := p.color_at(0.5)
	check_approx(c5.r, 0.000000, "t=0.5 red")
	check_approx(c5.g, 0.740877, "t=0.5 green")
	check_approx(c5.b, 0.740877, "t=0.5 blue")
	check_eq(p.color_at(1.0), c0, "the default palette closes the loop at t=1")
	check_approx(p.color_at(0.0).a, 1.0, "colors are opaque")

	# --- a non-default palette, the one the shader test also uses ---
	var q := Palette.new()
	q.a = Vector3(0.8, 0.5, 0.4)
	q.b = Vector3(0.2, 0.4, 0.2)
	q.c = Vector3(1.0, 1.0, 0.5)
	q.d = Vector3(0.0, 0.25, 0.25)
	var q0 := q.color_at(0.0)
	check_approx(q0.r, 1.000000, "non-default t=0 red (clamped at the top)")
	check_approx(q0.g, 0.500000, "non-default t=0 green")
	check_approx(q0.b, 0.400000, "non-default t=0 blue")
	var q3 := q.color_at(0.3)
	check_approx(q3.r, 0.738197, "non-default t=0.3 red")
	check_approx(q3.g, 0.119577, "non-default t=0.3 green")
	check_approx(q3.b, 0.238197, "non-default t=0.3 blue")
	var q77 := q.color_at(0.77)
	check_approx(q77.r, 0.825067, "non-default t=0.77 red")
	check_approx(q77.g, 0.896846, "non-default t=0.77 green")
	check_approx(q77.b, 0.267738, "non-default t=0.77 blue")

	# --- the result is clamped to [0, 1]: a+b can reach 2, a-b can reach -1 ---
	var hot := Palette.new()
	hot.a = Vector3.ONE
	hot.b = Vector3.ONE
	hot.d = Vector3.ZERO
	check_eq(hot.color_at(0.0), Color(1, 1, 1), "over-bright components clamp to 1")
	var cold := Palette.new()
	cold.a = Vector3.ZERO
	cold.b = Vector3.ONE
	cold.d = Vector3(0.5, 0.5, 0.5)
	check_eq(cold.color_at(0.0), Color(0, 0, 0), "negative components clamp to 0")

	# --- components are addressed as (vector 0..3 = A..D, channel 0..2 = rgb) ---
	var r := Palette.new()
	check_approx(r.get_component(0, 0), 0.5, "A.r")
	check_approx(r.get_component(3, 2), 0.67, "D.b")
	r.set_component(2, 1, 2.5)
	check_approx(r.c.y, 2.5, "set_component writes through to the vector")
	check_approx(r.get_component(2, 1), 2.5, "and reads back")
	check_eq(r.a, Vector3(0.5, 0.5, 0.5), "and leaves the other vectors alone")

	# --- the slider ranges are the model's ranges, not the window's ---
	check_eq(Palette.RANGES.size(), 4, "one range per vector")
	check_approx(Palette.RANGES[0].y, 1.0, "A tops out at 1")
	check_approx(Palette.RANGES[2].y, 4.0, "C's slider goes to 4 cycles")
	check_approx(Palette.STEP, 0.01, "sliders step by a hundredth")
	r.set_component(0, 0, 5.0)
	check_approx(r.get_component(0, 0), 1.0, "A clamps to its maximum")
	r.set_component(0, 0, -3.0)
	check_approx(r.get_component(0, 0), 0.0, "and to its minimum")
	r.set_component(2, 0, 9.0)
	check_approx(r.get_component(2, 0), 9.0, "C can be typed past its slider")
	r.set_component(2, 0, 99.0)
	check_approx(r.get_component(2, 0), 16.0, "up to its hard limit of 16")
	r.a = Vector3(9.0, -9.0, 0.25)
	check_eq(r.a, Vector3(1.0, 0.0, 0.25), "assigning the whole vector clamps too")

	# --- changed fires once per real edit, and not for a no-op ---
	var s := Palette.new()
	var beats := [0]
	s.changed.connect(func() -> void: beats[0] += 1)
	s.set_component(1, 2, 0.25)
	check_eq(beats[0], 1, "set_component emits changed")
	s.set_component(1, 2, 0.25)
	check_eq(beats[0], 1, "writing the same value again emits nothing")
	s.d = Vector3(0.1, 0.2, 0.3)
	check_eq(beats[0], 2, "assigning a vector emits changed")
	s.d = Vector3(0.1, 0.2, 0.3)
	check_eq(beats[0], 2, "and the same vector again does not")

	# --- reset ---
	s.reset()
	check_eq(s.a, Vector3(0.5, 0.5, 0.5), "reset restores A")
	check_eq(s.b, Vector3(0.5, 0.5, 0.5), "reset restores B")
	check_eq(s.c, Vector3(1.0, 1.0, 1.0), "reset restores C")
	check_eq(s.d, Vector3(0.0, 0.33, 0.67), "reset restores D")
	check_eq(beats[0], 3, "and emits changed once, not four times")

	# --- the numbers live in the shape table, so they save with the view ---
	var table := AttributeTable.new(ShapeCatalogue.specs())
	var t := Palette.new(table)
	check(t.table() == table, "a palette works over the table it is given")
	t.c = Vector3(2.0, 3.0, 0.5)
	check_approx(float(table.get_default(&"palette_c_g")), 3.0, "assigning C writes the palette_c_* ids")
	table.set_default(&"palette_a_b", 0.2)
	check_approx(t.a.z, 0.2, "and a table edit (a Palette row) reads back as A.b")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(table.to_dict()))
	var reloaded := AttributeTable.new(ShapeCatalogue.specs())
	reloaded.apply_dict(saved)
	var t2 := Palette.new(reloaded)
	check_eq(t2.c, t.c, "C round-trips through the table's JSON")
	check_eq(t2.color_at(0.42), t.color_at(0.42), "so the colours match")
	check_eq(Palette.ids().size(), 12, "twelve ids")
	for pid in Palette.ids():
		check(ShapeCatalogue.catalogue_ids().has(pid), "'%s' is a catalogue id (so a shader uniform)" % pid)

	# --- in_use follows the Colour mode ---
	check(not t.in_use(), "the palette is not in use in the default Ice Fractal mode")
	var mode_beats := [0]
	t.changed.connect(func() -> void: mode_beats[0] += 1)
	table.set_default(&"color_mode", Palette.MODE_ID)
	check(t.in_use(), "it is in the Palette mode")
	check_eq(mode_beats[0], 1, "and switching mode tells the window (for its hint)")
	table.set_default(&"box_scale", 1.5)
	check_eq(mode_beats[0], 1, "but a shape edit does not")

	# --- a bound component previews its driven value ---
	var plain := t.color_at(0.3)
	t.set_live({&"palette_b_r": 0.0})
	check_eq(t.color_at(0.3), plain, "an unbound component ignores the live value")
	check_eq(mode_beats[0], 1, "and the frame emits nothing")
	var bnd := Binding.new()
	bnd.source = &"time"
	bnd.waveform = Binding.Waveform.SINE
	table.set_binding(&"palette_b_r", bnd)
	check_eq(mode_beats[0], 2, "binding a component is a change")
	check_approx(t.color_at(0.3).r, clampf(t.a.x, 0.0, 1.0), "bound and driven to B.r = 0, red sits at A.r")
	check_approx(t.b.x, 0.5, "while B.r as set stays 0.5")
	t.set_live({&"palette_b_r": 0.25})
	check_eq(mode_beats[0], 3, "a driven value that moved is a change")
	t.set_live({&"palette_b_r": 0.25})
	check_eq(mode_beats[0], 3, "one that did not is not")
