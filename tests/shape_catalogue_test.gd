extends "res://tests/test_case.gd"
## The shape catalogue: every spec has tooltip and effects, defaults in range,
## ids unique, every group has a heading, and the id set is the expected 83
## catalogue ids; the lighting defaults are the site's constants; the Palette
## mode's rows show only in that mode; each shape's rows show only while that
## shape is drawn; the console's two tabs between them show every group
## exactly once.

const EXPECTED_IDS := [
	&"shape", &"w", &"box_scale", &"fold_limit", &"min_radius", &"fixed_radius", &"fold_order",
	&"fold_shape", &"hybrid_mix", &"hybrid_every", &"scale_drift", &"julia_all", &"julia_0",
	&"julia_1", &"julia_2", &"julia_3", &"c_0", &"c_1", &"c_2", &"c_3", &"iter_rot_xy",
	&"iter_rot_xz", &"iter_rot_xw", &"iter_rot_yz", &"iter_rot_yw", &"iter_rot_zw", &"kifs_scale",
	&"kifs_fold", &"kifs_poly_k", &"kifs_twist", &"kifs_offset_0", &"kifs_offset_1",
	&"kifs_offset_2", &"kifs_offset_3", &"kifs_rot1_xy", &"kifs_rot1_xz", &"kifs_rot1_xw",
	&"kifs_rot1_yz", &"kifs_rot1_yw", &"kifs_rot1_zw", &"kifs_rot2_xy", &"kifs_rot2_xz",
	&"kifs_rot2_xw", &"kifs_rot2_yz", &"kifs_rot2_yw", &"kifs_rot2_zw", &"kleinian_box_0",
	&"kleinian_box_1", &"kleinian_box_2", &"kleinian_box_3", &"kleinian_radius",
	&"kleinian_shift_0", &"kleinian_shift_1", &"kleinian_shift_2", &"kleinian_shift_3",
	&"kleinian_thickness", &"kleinian_view_distance", &"precision", &"color_mode",
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_ambient", &"light_diffuse", &"light_specular", &"light_shininess", &"light_yaw",
	&"light_pitch", &"exposure", &"saturation", &"palette_a_r", &"palette_a_g", &"palette_a_b",
	&"palette_b_r", &"palette_b_g", &"palette_b_b", &"palette_c_r", &"palette_c_g",
	&"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]


func run() -> void:
	var specs := ShapeCatalogue.specs()
	var tips := ShapeCatalogue.group_tooltips()

	check_eq(ShapeCatalogue.catalogue_ids(), EXPECTED_IDS, "the catalogue ids are the expected 83, in order")

	var seen := {}
	for s in specs:
		check(not seen.has(s.id), "id '%s' is unique" % s.id)
		seen[s.id] = true
		check(s.tooltip.strip_edges() != "", "'%s' has a tooltip" % s.id)
		check(s.effects.strip_edges() != "", "'%s' has effects text" % s.id)
		check(s.group != "", "'%s' has a group" % s.id)
		check(tips.has(s.group), "group '%s' has a heading tooltip" % s.group)
		if s.type == AttributeSpec.Type.FLOAT or s.type == AttributeSpec.Type.INT:
			var d := float(s.default_value)
			check(d >= s.hard_min - 1e-9 and d <= s.hard_max + 1e-9,
				"'%s' default %s is within [%s, %s]" % [s.id, d, s.hard_min, s.hard_max])

	# build a table and check specific specs
	var table := AttributeTable.new(specs)
	check_eq(table.get_default(&"box_scale"), -2.09, "box_scale default")
	var box_scale := table.spec(&"box_scale")
	check_eq(box_scale.hard_min, -6.0, "box_scale hard_min is -6")
	check_eq(box_scale.hard_max, 6.0, "box_scale hard_max is +6")
	check(box_scale.bindable, "box_scale is bindable")

	var color := table.spec(&"color_mode")
	check_eq(color.type, AttributeSpec.Type.ENUM, "color_mode is an enum")
	check(not color.bindable, "color_mode is not bindable")
	check_eq(color.enum_values, FractalParams.COLOR_MODE_IDS, "color_mode enum_values are the site ids")
	check_eq(table.get_default(&"color_mode"), 1, "color_mode default is Ice Fractal")

	# --- the console's tabs split the groups between them ---
	for s in specs:
		var on_shape := ShapeCatalogue.SHAPE_GROUPS.has(s.group)
		var on_colour := ShapeCatalogue.COLOUR_GROUPS.has(s.group)
		check(on_shape != on_colour, "'%s' (group %s) is on exactly one console tab" % [s.id, s.group])

	# --- lighting: the defaults are the site's constants, so the picture is unchanged ---
	check_approx(table.get_default(&"light_ambient"), 0.1, "ambient defaults to the site's 0.1")
	check_approx(table.get_default(&"light_diffuse"), 0.5, "diffuse to 0.5")
	check_approx(table.get_default(&"light_specular"), 1.0, "specular to 1")
	check_approx(table.get_default(&"light_shininess"), 160.0, "shininess to 160")
	check_approx(table.get_default(&"light_yaw"), 0.0, "yaw 0: the headlight")
	check_approx(table.get_default(&"light_pitch"), 0.0, "pitch 0")
	check_approx(table.get_default(&"exposure"), 1.0, "exposure 1")
	check_approx(table.get_default(&"saturation"), 1.0, "saturation 1")
	check(table.spec(&"light_shininess").log_scale, "shininess is logarithmic")
	check(table.spec(&"light_yaw").wrap, "yaw wraps")
	for id in [&"light_ambient", &"light_specular", &"light_yaw", &"exposure"]:
		check(table.spec(id).bindable, "'%s' is bindable" % id)

	# --- the Palette mode and its rows ---
	check(color.enum_values.has(Palette.MODE_ID), "Palette is a colour mode")
	var palette_mode := {&"color_mode": Palette.MODE_ID}
	var ice_mode := {&"color_mode": 1}
	for id in [&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion", &"palette_a_r", &"palette_d_b"]:
		check(table.spec(id).is_shown(palette_mode), "'%s' shows in the Palette mode" % id)
		check(not table.spec(id).is_shown(ice_mode), "'%s' hides in the others" % id)
	check(not table.spec(&"palette_source").bindable, "palette_source is not bindable")
	check(table.spec(&"palette_offset").wrap, "palette_offset wraps")
	for v in 4:
		for ch in 3:
			var pid := Palette.id(v, ch)
			check(table.has(pid), "'%s' is in the catalogue" % pid)
			check_approx(table.get_default(pid), Palette.DEFAULTS[v][ch], "'%s' defaults to IQ's rainbow" % pid)
			check(table.spec(pid).bindable, "'%s' is bindable, so a channel can have its own wave" % pid)
	check(table.spec(&"palette_d_g").wrap, "the D phases wrap")
	check(not table.spec(&"palette_a_g").wrap, "the A levels clamp")

	var prec := table.spec(&"precision")
	check(prec.log_scale, "precision is logarithmic")

	var rot := table.spec(&"iter_rot_xy")
	check(rot.wrap, "iter_rot_xy wraps")

	var fold := table.spec(&"fold_order")
	check(not fold.bindable, "fold_order is not bindable")

	# the c_i rows are shown only when their toggle or julia_all is on
	var c0 := table.spec(&"c_0")
	check(not c0.is_shown({&"julia_all": false, &"julia_0": false}), "c_0 hidden with no Julia on")
	check(c0.is_shown({&"julia_all": false, &"julia_0": true}), "c_0 shown when julia_0 is on")
	check(c0.is_shown({&"julia_all": true, &"julia_0": false}), "c_0 shown when julia_all is on")

	# --- the shape switch: each shape's rows show only while it is drawn ---
	var shape := table.spec(&"shape")
	check_eq(shape.type, AttributeSpec.Type.ENUM, "shape is an enum")
	check_eq(table.get_default(&"shape"), FractalParams.Shape.MANDELBOX, "the Mandelbox by default")
	check_eq(shape.enum_labels, ["Mandelbox", "KIFS", "Kleinian"], "the three shapes")
	var as_mb := {&"shape": FractalParams.Shape.MANDELBOX}
	var as_kifs := {&"shape": FractalParams.Shape.KIFS}
	var as_kl := {&"shape": FractalParams.Shape.KLEINIAN}
	var own := {
		"Box": as_mb, "Julia": as_mb, "Iteration rotation": as_mb,
		"KIFS": as_kifs, "KIFS rotation": as_kifs, "Kleinian": as_kl,
	}
	for s in specs:
		if own.has(s.group):
			var mine: Dictionary = own[s.group]
			for other in [as_mb, as_kifs, as_kl]:
				if other != mine:
					check(not s.is_shown(other), "'%s' hides off its shape (%s)" % [s.id, other[&"shape"]])
		else:
			for any_shape in [as_mb, as_kifs, as_kl]:
				var v: Dictionary = any_shape.duplicate()
				v[&"color_mode"] = Palette.MODE_ID
				check(s.is_shown(v), "shared row '%s' shows on shape %s" % [s.id, any_shape[&"shape"]])
	check(table.spec(&"box_scale").is_shown(as_mb), "box_scale shows on the Mandelbox")
	check(table.spec(&"kifs_scale").is_shown(as_kifs), "kifs_scale shows on the KIFS")
	check(table.spec(&"kleinian_view_distance").is_shown(as_kl), "the view distance shows on the Kleinian")
	# Julia constants keep their own condition on top of the shape's.
	check(not c0.is_shown({&"shape": 0, &"julia_all": false, &"julia_0": false}), "c_0 still needs its toggle")
	check(c0.is_shown({&"shape": 0, &"julia_0": true}), "c_0 shows with its toggle on the Mandelbox")
	check(not c0.is_shown({&"shape": 1, &"julia_0": true}), "c_0 hides on the KIFS whatever the toggle")
	var k := table.spec(&"kifs_poly_k")
	check(not k.is_shown({&"shape": 1, &"kifs_fold": KifsEstimator.FoldSet.COORDINATE}), "Polyfold k hides for the coordinate fold")
	check(k.is_shown({&"shape": 1, &"kifs_fold": KifsEstimator.FoldSet.POLYFOLD}), "and shows for the Polyfold")

	for id in [&"shape", &"fold_shape", &"hybrid_every", &"kifs_fold"]:
		check(not table.spec(id).bindable, "'%s' is not bindable" % id)
	for id in [&"hybrid_mix", &"scale_drift", &"kifs_scale", &"kifs_poly_k", &"kifs_rot1_xy", &"kleinian_radius", &"kleinian_view_distance"]:
		check(table.spec(id).bindable, "'%s' is bindable" % id)
	check(table.spec(&"kifs_rot2_zw").wrap, "the KIFS rotations wrap")
	check(table.spec(&"kleinian_view_distance").log_scale, "the view distance is logarithmic")
	check(table.spec(&"kifs_scale").hard_min > 1.0, "the KIFS scale stays above 1")
	check_eq(ShapeCatalogue.SHAPE_GROUPS[0], "Fractal", "the Shape tab opens on the Fractal group")
