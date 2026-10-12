extends "res://tests/test_case.gd"
## The shader compiles headless and declares exactly the renderer uniforms plus
## the shape catalogue's shader ids (the per-shape ids without the Placement
## group, which the CPU turns into each shape's frame), each as an array of
## MAX_SHAPES, plus the scene (look) ids as scalars.
## (A shader that fails to compile yields an empty uniform list.) This is the
## project's version of Fractacular's technique_schema check: the shader's
## shape uniforms must equal the catalogue.
## Every uniform the shader gives a default (the colour, lighting and palette
## ones) defaults to its catalogue default, so a frame drawn before the first
## push already looks right; the dummy renderer cannot report defaults, so this
## reads them from the source.

const RENDERER_UNIFORMS := ["depth_scan", "eye", "cam_right", "cam_up", "cam_forward",
	"exit_radius", "exit_has_skybox", "exit_skybox", "exit_sky_alpha", "escape_fog_clear", "scan_y_offset", "scan_y_scale",
	"tan_half_fov", "aspect", "box_half", "detail_range", "detail_falloff", "near_dist",
	"fractal_iterations", "surface_detail", "coarse_steps", "coarse_iters", "nf_weight", "fine_steps", "fog_dist", "fog_color",
	"kifs_bailout_radius_squared", "mandelbulb_bailout_margin",
	"fog_clear", "probe_on", "probe_point", "probe_radius", "shadow_steps", "view_limit",
	"shape_count", "local_eye", "frame_x", "frame_y", "frame_z", "shape_size"]


func run() -> void:
	var sh: Shader = load("res://src/fractal/mandelbox.gdshader")
	check(sh != null, "the shader resource loads")
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	check(names.size() > 0, "shader compiles (uniform list non-empty)")

	var catalogue: Array = []
	for id in ShapeCatalogue.shader_ids():
		catalogue.append(String(id))
	for id in ShapeCatalogue.scene_ids():
		catalogue.append(String(id))
	for id in ShapeCatalogue.PLACEMENT_IDS:
		check(not names.has(String(id)), "the placement id '%s' is not a uniform (the CPU resolves it)" % id)

	var expected := RENDERER_UNIFORMS.duplicate()
	expected.append_array(catalogue)
	check_eq(names.size(), expected.size(), "exactly %d uniforms" % expected.size())
	for u in expected:
		check(names.has(u), "uniform '%s' is declared" % u)

	# the shape uniforms (everything that is not renderer-owned) equal the ids
	var shape_uniforms: Array = []
	for n in names:
		if not RENDERER_UNIFORMS.has(n):
			shape_uniforms.append(n)
	shape_uniforms.sort()
	var want := catalogue.duplicate()
	want.sort()
	check_eq(shape_uniforms, want, "the shader's shape uniforms equal ShapeCatalogue.shader_ids() + scene_ids()")
	# every per-shape uniform is an array of MAX_SHAPES entries (an int array
	# for the toggles and enums); the look uniforms stay scalars
	var hints := {}
	for u in sh.get_shader_uniform_list():
		hints[String(u["name"])] = u["type"]
	for id in ShapeCatalogue.shape_ids():
		if ShapeCatalogue.PLACEMENT_IDS.has(id):
			continue
		var t: int = hints[String(id)]
		check(t == TYPE_PACKED_FLOAT32_ARRAY or t == TYPE_PACKED_INT32_ARRAY,
			"per-shape uniform '%s' is an array (type %d)" % [id, t])
	for id in ShapeCatalogue.scene_ids():
		var t: int = hints[String(id)]
		check(t != TYPE_PACKED_FLOAT32_ARRAY and t != TYPE_PACKED_INT32_ARRAY, "look uniform '%s' is a scalar (type %d)" % [id, t])
	check_eq(hints["julia_all"], TYPE_PACKED_INT32_ARRAY, "the Julia toggles are int arrays")
	check_eq(hints["shape"], TYPE_PACKED_INT32_ARRAY, "so is the fractal choice")
	check_eq(hints["local_eye"], TYPE_PACKED_VECTOR3_ARRAY, "local_eye is a vec3 array")
	check_eq(hints["coarse_iters"], TYPE_PACKED_INT32_ARRAY, "coarse_iters is per shape")
	check(sh.code.contains("const int MAX_SHAPES = %d;" % FractalParams.MAX_SHAPES),
		"the shader's MAX_SHAPES matches FractalParams.MAX_SHAPES")

	var table := AttributeTable.new(ShapeCatalogue.specs())
	var re := RegEx.create_from_string("uniform (?:float|int) (\\w+) = (-?[0-9.]+);")
	var with_default := 0
	for m in re.search_all(sh.code):
		var id := StringName(m.get_string(1))
		if RENDERER_UNIFORMS.has(String(id)):
			continue   # a renderer uniform that happens to carry a default
		check(table.has(id), "the defaulted uniform '%s' is a catalogue id" % id)
		if table.has(id):
			check_approx(m.get_string(2).to_float(), float(table.get_default(id)),
				"uniform '%s' defaults to the catalogue's %s" % [id, table.get_default(id)], 1e-9)
		with_default += 1
	check_eq(with_default, FractalParams.LOOK_KEYS.size(), "every scalar look uniform declares its default")

	# every COLOR catalogue id is a vec3 uniform whose default is the colour's rgb
	var cre := RegEx.create_from_string("uniform vec3 (\\w+) = vec3\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*\\);")
	var colour_defaults := 0
	for m in cre.search_all(sh.code):
		var id := StringName(m.get_string(1))
		if not table.has(id):
			continue   # (there are no other defaulted vec3 uniforms today)
		check_eq(table.spec(id).type, AttributeSpec.Type.COLOR, "the defaulted vec3 '%s' is a COLOR id" % id)
		var c := table.get_default(id) as Color
		# Color components are float32; decimal literals parse as float64 here.
		check_approx(m.get_string(2).to_float(), c.r, "vec3 '%s' red matches the COLOR default" % id, 1e-7)
		check_approx(m.get_string(3).to_float(), c.g, "vec3 '%s' green" % id, 1e-7)
		check_approx(m.get_string(4).to_float(), c.b, "vec3 '%s' blue" % id, 1e-7)
		colour_defaults += 1
	check_eq(colour_defaults, FractalParams.COLOR_KEYS.size(), "all COLOR uniforms declare a vec3 default")

	# the specular exponent is floored at 0: a matte surface (roughness 1) under a
	# wide light (light_size > 0) gives r_eff2 > 1, so an unclamped 2/r_eff2 - 2
	# would go negative and pow(nl, e) blows up (pow(0, neg) is a NaN). The widest
	# lobe is a flat sheen (e = 0), never an inverted rim.
	check(sh.code.contains("max(0.0, 2.0 / max(r_eff2, 1e-9) - 2.0)"),
		"the specular exponent is clamped non-negative")

	# The shadow ray marches the scene through de_scene on offsets from the eye,
	# so every estimate is evaluated in its shape's local frame.
	check(sh.code.contains("de_scene(lift + ldir * t, true, which)"),
		"the shadow ray's estimates go through de_scene")
