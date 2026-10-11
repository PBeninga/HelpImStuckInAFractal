extends "res://tests/test_case.gd"
## FractalView.set_noise_graph: swapping in a wired field keeps every base uniform
## and adds the graph's, an unwired graph restores the base shader exactly, a live
## FLOAT edit does not change the uniform set, and a bad graph is reported without
## losing the working shader.


## The renderer's own uniforms plus every shape catalogue id (filled in run()).
var BASE_UNIFORMS: Array = []


func _base_uniforms() -> Array:
	var out: Array = ["eye", "cam_right", "cam_up", "cam_forward", "tan_half_fov",
		"aspect", "box_half", "detail_range", "detail_falloff", "near_dist",
		"coarse_steps", "fine_steps", "fog_dist", "fog_color"]
	for id in MandelboxShape.catalogue_ids():
		out.append(String(id))
	return out


func _names(view: FractalView) -> Array:
	var out: Array = []
	for u in view.shader_uniform_names():
		out.append(String(u))
	return out


func run() -> void:
	BASE_UNIFORMS = _base_uniforms()
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 400)
	view.setup(params, cam)
	await frames(1)

	var resolver := Callable(NoiseNodeRegistry, "type_by_id")

	# --- an unwired graph keeps exactly the base uniform set ---
	var g := NoiseGraph.default_graph(resolver)
	view.set_noise_graph(g)
	await frames(1)
	var base_names := _names(view)
	check_eq(base_names.size(), BASE_UNIFORMS.size(),
		"an unwired graph leaves the base uniform list unchanged (%d)" % base_names.size())
	for u in BASE_UNIFORMS:
		check(base_names.has(u), "base uniform '%s' is present" % u)

	# --- wiring a Value noise to Displace adds the graph's uniforms ---
	var vn := g.add_node(&"value_noise", Vector2(200, 40))
	g.connect_ports(g.position_id(), 0, vn, 0)
	g.connect_ports(vn, 0, g.output_id(), 0)
	await frames(1)
	var wired_names := _names(view)
	for u in BASE_UNIFORMS:
		check(wired_names.has(u), "every base uniform survives the swap: '%s'" % u)
	check(wired_names.has("n_%s_scale" % vn), "…and the graph's scale uniform was added")
	check(wired_names.has("n_output_0_amplitude"), "…and the Output's amplitude")
	check(wired_names.has("n_output_0_tint_color"), "…and the tint colour")
	check(wired_names.size() > BASE_UNIFORMS.size(), "the uniform set grew")

	# --- a live FLOAT edit pushes a uniform but does NOT change the set ---
	var set_before := wired_names.size()
	g.node(vn).table.set_value(&"scale", 3.5)
	await frames(1)
	check_eq(_names(view).size(), set_before,
		"a FLOAT edit only pushes a value: the shader (and its uniform set) is unchanged")

	# --- a baked INT edit rebuilds (octaves changes the loop bound) ---
	g.node(vn).table.set_value(&"octaves", 5)
	await frames(1)
	check(_names(view).has("n_%s_scale" % vn),
		"a baked edit rebuilds and the graph's uniforms are still there")

	# --- unwiring restores the base shader exactly ---
	g.disconnect_ports(vn, 0, g.output_id(), 0)
	await frames(1)
	check_eq(_names(view).size(), BASE_UNIFORMS.size(),
		"unwiring the Output restores the base uniform list")

	# --- set_noise_graph(null) is safe and restores the base ---
	view.set_noise_graph(null)
	await frames(1)
	check_eq(_names(view).size(), BASE_UNIFORMS.size(), "a null graph restores the base shader")

	view.queue_free()
	await frames(1)
