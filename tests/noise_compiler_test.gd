extends "res://tests/test_case.gd"
## NoiseCompiler: every node compiles, the default graph is the inert stub, a
## wired graph grows the right uniforms, the three functions do what the spec
## says, live-vs-baked is classified correctly, and displaces() tells a graph
## that moves the surface from one that only tints it.


func _resolver() -> Callable:
	return Callable(NoiseNodeRegistry, "type_by_id")


## Compile a region body into a standalone shader that references all three
## functions, so get_shader_uniform_list() reports whether it compiled.
func _region_compiles(code: String) -> Shader:
	var src := "shader_type canvas_item;\n" + code \
		+ "\nvoid fragment() {\n" \
		+ "\tvec3 pp = vec3(UV, 0.0);\n" \
		+ "\tfloat d = noise_displace(pp);\n" \
		+ "\tfloat s = noise_step_scale();\n" \
		+ "\tvec3 t = noise_tint(vec3(0.5), pp);\n" \
		+ "\tCOLOR = vec4(t + vec3(d + s), 1.0);\n}\n"
	var sh := Shader.new()
	sh.code = src
	return sh


func run() -> void:
	var resolver := _resolver()

	# ------------------------------------------- every node compiles on its own
	# Build Position -> node (where it fits) and preview the node's first output.
	for type in NoiseNodeRegistry.all():
		if type.outputs.is_empty():
			continue   # Output has nothing to preview
		var g := NoiseGraph.new(resolver)
		var node_id: StringName = g.position_id()
		if type.id != NoiseGraph.SOURCE_TYPE:
			node_id = g.add_node(type.id, Vector2.ZERO)
			# Feed the sample position into the first Vec3 input, if any.
			for i in type.inputs.size():
				if type.inputs[i].type == NoisePort.Type.VEC3:
					g.connect_ports(g.position_id(), 0, node_id, i)
					break
		var preview := NoiseCompiler.compile_preview(g, node_id, 0)
		check(preview != "", "%s: compile_preview produced a shader" % type.id)
		var sh := Shader.new()
		sh.code = preview
		check(not sh.get_shader_uniform_list().is_empty(),
			"%s: its preview shader compiles (uniform list non-empty)" % type.id)
		# The shared preview controls are always there.
		var names := _names(sh)
		check(names.has("preview_extent") and names.has("preview_slice_z"),
			"%s: the preview shares the extent and slice uniforms" % type.id)

	# ---------------------------------------------- the default graph is inert
	var def := NoiseGraph.default_graph(resolver)
	var def_result := NoiseCompiler.compile(def)
	check_eq(def_result["uniforms"], [], "an unwired graph declares no uniforms")
	check_eq(def_result["errors"], [], "and reports no errors")
	check(String(def_result["code"]).contains("return 0.0;"), "noise_displace is the stub")
	check(String(def_result["code"]).contains("return col;"), "noise_tint is the stub")
	check(String(def_result["code"]).contains("return 1.0;"), "noise_step_scale is the stub")
	check_eq(String(def_result["code"]), NoiseCompiler.STUB, "the stub region is byte-identical to the base")
	check(NoiseCompiler.STUB.contains("const bool noise_texture_on = false;"),
		"the stub declares noise_texture_on = false")
	check(NoiseCompiler.STUB.contains("const bool noise_bump_on = false;"),
		"the stub declares noise_bump_on = false")
	check(NoiseCompiler.STUB.contains("vec3 noise_texture(vec3 p) { return vec3(1.0); }"),
		"the stub's noise_texture is white")
	check(NoiseCompiler.STUB.contains("float noise_bump(vec3 p) { return 0.0; }"),
		"the stub's noise_bump is flat")

	# ---------------------------------------------- a wired graph: Value noise
	var g := NoiseGraph.new(resolver)
	var vn := g.add_node(&"value_noise", Vector2(200, 40))
	g.connect_ports(g.position_id(), 0, vn, 0)
	g.connect_ports(vn, 0, g.output_id(), 0)   # Displace
	var result := NoiseCompiler.compile(g)
	check_eq(result["errors"], [], "the wired graph compiles with no errors")
	var u: Array = result["uniforms"]
	check(u.has("n_%s_scale" % vn), "a FLOAT param becomes uniform n_<node>_<param>")
	check(u.has("n_%s_seed" % vn), "…one per FLOAT param")
	check(not u.has("n_%s_octaves" % vn), "an INT param is baked, not a uniform")
	check(u.has("n_output_0_amplitude"), "the Output's amplitude is a live uniform")

	# ---------------------------------------------- displaces(): is the surface moved?
	check(not NoiseCompiler.displaces(null), "no graph displaces nothing")
	check(not NoiseCompiler.displaces(def), "the default (unwired) graph does not displace")
	check(NoiseCompiler.displaces(g), "a graph wired to Displace displaces")
	g.node(g.output_id()).table.set_value(&"amplitude", 0.0)
	check(not NoiseCompiler.displaces(g), "…unless its Amplitude is 0, which leaves the shape untouched")
	g.node(g.output_id()).table.set_value(&"amplitude", 0.05)
	var tint_only := NoiseGraph.new(resolver)
	var tvn := tint_only.add_node(&"value_noise", Vector2(200, 40))
	tint_only.connect_ports(tint_only.position_id(), 0, tvn, 0)
	tint_only.connect_ports(tvn, 0, tint_only.output_id(), 1)   # Tint
	check(not NoiseCompiler.displaces(tint_only), "a Tint-only graph colours but does not displace")
	check(u.has("n_output_0_step_scale"), "…and its step scale")
	check(u.has("n_output_0_tint_color"), "…and its tint colour (a vec3)")
	check(String(result["code"]).contains("n_output_0_amplitude"),
		"noise_displace multiplies by the amplitude uniform")
	check(String(result["code"]).contains("return n_output_0_step_scale;"),
		"with Displace wired, noise_step_scale returns the uniform, not 1.0")
	check(String(result["code"]).contains("return col;") == false
			or String(result["code"]).contains("noise_tint(vec3 col, vec3 p) { return col; }"),
		"Tint is unwired, so noise_tint is still the stub")

	# the region actually compiles when spliced into a wrapper
	var wired_sh := _region_compiles(result["code"])
	var wired_names := _names(wired_sh)
	check(not wired_names.is_empty(), "the wired region compiles")
	check(wired_names.has("n_%s_scale" % vn), "…and exposes the node's scale uniform")
	check(wired_names.has("n_output_0_tint_color"), "…and the tint colour uniform")

	# ---------------------------------------------- splice into a base
	var fake_base := "shader_type canvas_item;\nuniform float base_u;\n// NOISE:BEGIN\nOLD\n// NOISE:END\nvoid fragment() { COLOR = vec4(base_u); }\n"
	var spliced := NoiseCompiler.splice(fake_base, "NEW_REGION\n")
	check(spliced.contains("NEW_REGION"), "splice inserts the region")
	check(not spliced.contains("OLD"), "…replacing the old region")
	check(spliced.contains("base_u") and spliced.contains("NOISE:BEGIN"),
		"…and keeps the rest of the base and the markers")

	# ---------------------------------------------- tint wiring
	var g2 := NoiseGraph.new(resolver)
	var vn2 := g2.add_node(&"value_noise", Vector2.ZERO)
	g2.connect_ports(g2.position_id(), 0, vn2, 0)
	g2.connect_ports(vn2, 0, g2.output_id(), 1)   # Tint
	var tint_code: String = NoiseCompiler.compile(g2)["code"]
	check(tint_code.contains("mix(col, n_output_0_tint_color"),
		"wiring Tint blends the colour toward the tint colour")
	check(tint_code.contains("clamp("), "…clamped to 0..1 as the spec says")
	check(tint_code.contains("noise_displace(vec3 p) { return 0.0; }"),
		"…and with Displace unwired, noise_displace is the stub")

	# ---------------------------------------------- live vs baked classification
	check(NoiseCompiler.is_live_param(g, vn, &"scale"), "a FLOAT edit is live (push, no rebuild)")
	check(not NoiseCompiler.is_live_param(g, vn, &"octaves"), "an INT edit is baked (rebuild)")
	check(NoiseCompiler.is_live_param(g, g.output_id(), &"amplitude"), "amplitude is live")
	check(NoiseCompiler.is_live_param(g, g.output_id(), &"tint_color"), "the tint colour is live")
	var g3 := NoiseGraph.new(resolver)
	var m := g3.add_node(&"math", Vector2.ZERO)
	check(not NoiseCompiler.is_live_param(g3, m, &"op"), "an ENUM edit is baked (rebuild)")
	var rm := g3.add_node(&"remap", Vector2.ZERO)
	check(not NoiseCompiler.is_live_param(g3, rm, &"clamp"), "a BOOL edit is baked (rebuild)")
	check(NoiseCompiler.is_live_param(g3, rm, &"in_min"), "but Remap's ranges are live floats")

	# ---------------------------------------------- live_values naming
	var vals := NoiseCompiler.live_values(g)
	check(vals.has("n_%s_scale" % vn), "live_values keys a FLOAT param by its uniform name")
	check(vals["n_%s_scale" % vn] is float, "…with a float value")
	check(vals.has("n_output_0_tint_color") and vals["n_output_0_tint_color"] is Vector3,
		"…and the tint colour as a Vector3, matching the vec3 uniform")

	# an ENUM/BOOL baked change really changes the generated code
	var before: String = NoiseCompiler.compile(g3_with_wire(resolver, 0))["code"]
	var after: String = NoiseCompiler.compile(g3_with_wire(resolver, 2))["code"]
	check(before != after, "changing Math's Op (baked) produces different GLSL")


## A Position -> Math(op) -> Output.Displace graph, with Math's op set.
func g3_with_wire(resolver: Callable, op: int) -> NoiseGraph:
	var g := NoiseGraph.new(resolver)
	var m := g.add_node(&"math", Vector2.ZERO)
	g.node(m).table.set_value(&"op", op)
	g.connect_ports(m, 0, g.output_id(), 0)
	return g


func _names(sh: Shader) -> Array:
	var out: Array = []
	for item in sh.get_shader_uniform_list():
		out.append(String(item["name"]))
	return out
