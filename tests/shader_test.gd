extends "res://tests/test_case.gd"
## The shader compiles headless and declares exactly the renderer uniforms plus
## the shape catalogue ids. (A shader that fails to compile yields an empty
## uniform list.) This is the project's version of Fractacular's
## technique_schema check: the shader's shape uniforms must equal the catalogue.
## Every uniform the shader gives a default (the colour, lighting and palette
## ones) defaults to its catalogue default, so a frame drawn before the first
## push already looks right; the dummy renderer cannot report defaults, so this
## reads them from the source.

const RENDERER_UNIFORMS := ["eye", "cam_right", "cam_up", "cam_forward",
	"tan_half_fov", "aspect", "box_half", "detail_range", "detail_falloff", "near_dist",
	"coarse_steps", "coarse_iters", "nf_weight", "fine_steps", "fog_dist", "fog_color",
	"fog_clear", "probe_on", "probe_point", "probe_radius", "shadow_steps",
	"pert_iters", "pert_a", "pert_b", "pert_c", "pert_d", "pert_x"]


func run() -> void:
	var sh: Shader = load("res://src/fractal/mandelbox.gdshader")
	check(sh != null, "the shader resource loads")
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	check(names.size() > 0, "shader compiles (uniform list non-empty)")

	var catalogue: Array = []
	for id in ShapeCatalogue.catalogue_ids():
		catalogue.append(String(id))

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
	check_eq(shape_uniforms, want, "the shader's shape uniforms equal ShapeCatalogue.catalogue_ids()")

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
		check_approx(m.get_string(2).to_float(), c.r, "vec3 '%s' red matches the COLOR default" % id, 1e-9)
		check_approx(m.get_string(3).to_float(), c.g, "vec3 '%s' green" % id, 1e-9)
		check_approx(m.get_string(4).to_float(), c.b, "vec3 '%s' blue" % id, 1e-9)
		colour_defaults += 1
	check_eq(colour_defaults, FractalParams.COLOR_KEYS.size(), "both COLOR uniforms declare a vec3 default")

	# the specular exponent is floored at 0: a matte surface (roughness 1) under a
	# wide light (light_size > 0) gives r_eff2 > 1, so an unclamped 2/r_eff2 - 2
	# would go negative and pow(nl, e) blows up (pow(0, neg) is a NaN). The widest
	# lobe is a flat sheen (e = 0), never an inverted rim.
	check(sh.code.contains("max(0.0, 2.0 / max(r_eff2, 1e-9) - 2.0)"),
		"the specular exponent is clamped non-negative")

	# the shadow ray marches through march_de, so while the march is perturbed its
	# estimates keep their precision at depth (de from the 32-bit point would be noise)
	check(sh.code.contains("march_de(ro + ldir * t, oo + ldir * t, n_coarse)"),
		"the shadow ray's estimates go through march_de")
	check_eq(with_default, FractalParams.LOOK_KEYS.size(), "every look uniform declares its default")

	# the record arrays are as long as ReferenceOrbit's record, the handoff points
	# one longer, and the shader hands off where FractalParams says
	var inc := FileAccess.get_file_as_string("res://src/fractal/perturbation.gdshaderinc")
	for arr in ["pert_a", "pert_b", "pert_c", "pert_d", "pert_x"]:
		var m := RegEx.create_from_string("uniform vec4 %s\\[(\\d+)\\];" % arr).search(inc)
		var entries := ReferenceOrbit.PERT_MAX + (1 if arr == "pert_x" else 0)
		check(m != null and int(m.get_string(1)) == entries, "%s has %d entries" % [arr, entries])
	var h := RegEx.create_from_string("const float PERT_HANDOFF = ([0-9.]+);").search(inc)
	check(h != null and is_equal_approx(h.get_string(1).to_float(), FractalParams.PERT_HANDOFF),
		"the shader's PERT_HANDOFF is FractalParams.PERT_HANDOFF")
