extends "res://tests/test_case.gd"
## The shader compiles headless and declares exactly the renderer uniforms plus
## the shape catalogue ids. (A shader that fails to compile yields an empty
## uniform list.) This is the project's version of Fractacular's
## technique_schema check: the shader's shape uniforms must equal the catalogue.

const RENDERER_UNIFORMS := ["eye", "cam_right", "cam_up", "cam_forward",
	"tan_half_fov", "aspect", "box_half", "detail_range", "detail_falloff", "near_dist",
	"coarse_steps", "fine_steps", "fog_dist", "fog_color"]


func run() -> void:
	var sh: Shader = load("res://src/fractal/mandelbox.gdshader")
	check(sh != null, "the shader resource loads")
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	check(names.size() > 0, "shader compiles (uniform list non-empty)")

	var catalogue: Array = []
	for id in MandelboxShape.catalogue_ids():
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
	check_eq(shape_uniforms, want, "the shader's shape uniforms equal MandelboxShape.catalogue_ids()")
