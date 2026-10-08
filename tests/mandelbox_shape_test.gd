extends "res://tests/test_case.gd"
## The Mandelbox shape catalogue: every spec has tooltip and effects, defaults
## in range, ids unique, every group has a heading, and the id set is the
## expected 47 catalogue ids; the lighting defaults are the site's constants;
## the Palette mode's rows show only in that mode; the console's two tabs
## between them show every group exactly once.

const EXPECTED_IDS := [
	&"box_scale", &"fold_limit", &"min_radius", &"fixed_radius", &"fold_order", &"w",
	&"julia_all", &"julia_0", &"julia_1", &"julia_2", &"julia_3",
	&"c_0", &"c_1", &"c_2", &"c_3",
	&"iter_rot_xy", &"iter_rot_xz", &"iter_rot_xw", &"iter_rot_yz", &"iter_rot_yw", &"iter_rot_zw",
	&"precision",
	&"color_mode", &"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_ambient", &"light_diffuse", &"light_specular", &"light_shininess",
	&"light_yaw", &"light_pitch", &"exposure", &"saturation",
	&"palette_a_r", &"palette_a_g", &"palette_a_b", &"palette_b_r", &"palette_b_g", &"palette_b_b",
	&"palette_c_r", &"palette_c_g", &"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]


func run() -> void:
	var specs := MandelboxShape.specs()
	var tips := MandelboxShape.group_tooltips()

	check_eq(MandelboxShape.catalogue_ids(), EXPECTED_IDS, "the catalogue ids are the expected 47, in order")

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
		var on_shape := MandelboxShape.SHAPE_GROUPS.has(s.group)
		var on_colour := MandelboxShape.COLOUR_GROUPS.has(s.group)
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
