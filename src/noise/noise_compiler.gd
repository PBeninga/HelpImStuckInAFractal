class_name NoiseCompiler
extends RefCounted
## Turns a NoiseGraph into GLSL. Two jobs:
##
##   compile(graph)  -> {code, uniforms, errors}
##       The body of the mandelbox shader's NOISE region: the noise library, one
##       `uniform` per live (FLOAT) node parameter, and the three functions the
##       renderer calls — noise_displace(p), noise_step_scale() and
##       noise_tint(col, p). When nothing is wired to the Output, the three are
##       the inert stubs, so the picture and its cost are exactly as if there were
##       no editor at all.
##
##   compile_preview(graph, node_id, port) -> String
##       A self-contained canvas_item shader that evaluates the subgraph up to one
##       output port over an XY slice of fractal space, for a node's live preview.
##
## A FLOAT parameter is a `uniform n_<node_id>_<param>` pushed without a recompile
## (see live_values / is_live_param). An INT, BOOL or ENUM parameter is baked into
## the generated code — a loop bound, an op, a clamp — so editing one rebuilds.

const BEGIN_MARK := "// NOISE:BEGIN"
const END_MARK := "// NOISE:END"
const LIBRARY_PATH := "res://src/noise/noise_library.gdshaderinc"

## The inert region, byte-identical to the base shader's, so an unwired graph
## splices back to exactly the original source.
const STUB := """float noise_displace(vec3 p) { return 0.0; }
float noise_step_scale() { return 1.0; }
vec3 noise_tint(vec3 col, vec3 p) { return col; }
"""

static var _library_cache := ""


static func _library() -> String:
	if _library_cache == "":
		_library_cache = FileAccess.get_file_as_string(LIBRARY_PATH)
		if _library_cache == "":
			push_warning("NoiseCompiler: could not read %s" % LIBRARY_PATH)
	return _library_cache


# ------------------------------------------------------------------ public

## The NOISE region body and its uniform names. `errors` is empty on success.
static func compile(graph: NoiseGraph) -> Dictionary:
	var errors: Array = []
	var disp := graph.input_link(graph.output_id(), 0)
	var tint := graph.input_link(graph.output_id(), 1)
	var wired := not disp.is_empty() or not tint.is_empty()
	if not wired:
		return {"code": STUB, "uniforms": [], "errors": errors}

	# Every node used by either function, for the shared uniform block.
	var used: Dictionary = {}
	if not disp.is_empty():
		for id in _ancestors(graph, disp["from"]):
			used[id] = true
	if not tint.is_empty():
		for id in _ancestors(graph, tint["from"]):
			used[id] = true

	var names: Array = []
	var decls := _uniform_decls(graph, used, names, errors)
	# Output's own live uniforms.
	var out_state := graph.node(graph.output_id())
	decls += "uniform float n_output_0_amplitude = %s;\n" % _gf(out_state.table.get_value(&"amplitude"))
	decls += "uniform float n_output_0_step_scale = %s;\n" % _gf(out_state.table.get_value(&"step_scale"))
	decls += "uniform float n_output_0_tint_strength = %s;\n" % _gf(out_state.table.get_value(&"tint_strength"))
	var tc := NoiseNodeType.to_color(out_state.extras.get("tint_color", [1.0, 0.45, 0.2, 1.0]))
	decls += "uniform vec3 n_output_0_tint_color = vec3(%s, %s, %s);\n" % [_gf(tc.r), _gf(tc.g), _gf(tc.b)]
	names.append_array(["n_output_0_amplitude", "n_output_0_step_scale",
		"n_output_0_tint_strength", "n_output_0_tint_color"])

	var code := decls + "\n" + _library() + "\n"
	code += _displace_fn(graph, disp, errors)
	code += _step_scale_fn(not disp.is_empty())
	code += _tint_fn(graph, tint, errors)
	return {"code": code, "uniforms": names, "errors": errors}


## The base shader with its NOISE region replaced by `region`.
static func splice(base_code: String, region: String) -> String:
	var b := base_code.find(BEGIN_MARK)
	var e := base_code.find(END_MARK)
	if b == -1 or e == -1:
		push_warning("NoiseCompiler.splice: NOISE markers not found")
		return base_code
	var before := base_code.substr(0, b + BEGIN_MARK.length())
	var after := base_code.substr(e)
	return "%s\n%s%s" % [before, region, after]


## A full canvas_item shader evaluating the subgraph up to (node_id, port) over an
## XY slice of fractal space. "" for an unknown node or port.
static func compile_preview(graph: NoiseGraph, node_id: StringName, port: int) -> String:
	var state := graph.node(node_id)
	if state == null:
		return ""
	var type := NoiseNodeRegistry.type_by_id(state.type_id)
	if type == null or port < 0 or port >= type.outputs.size():
		return ""

	var used: Dictionary = {}
	for id in _ancestors(graph, node_id):
		used[id] = true
	var errors: Array = []
	var names: Array = []
	var decls := _uniform_decls(graph, used, names, errors)
	var body := _emit_nodes(graph, _ordered(graph, used), errors)
	var result := "v_%s_%d" % [node_id, port]

	var color_line := ""
	if type.outputs[port].type == NoisePort.Type.VEC3:
		color_line = "\tCOLOR = vec4(abs(%s) / max(preview_extent, 1e-6), 1.0);\n" % result
	else:
		color_line = "\tCOLOR = vec4(vec3((%s) * 0.5 + 0.5), 1.0);\n" % result

	return "shader_type canvas_item;\n\nuniform float preview_extent = 4.0;\n" \
		+ "uniform float preview_slice_z = 0.0;\n" + decls + "\n" + _library() + "\n" \
		+ "void fragment() {\n" \
		+ "\tvec3 p = vec3((UV - vec2(0.5)) * 2.0 * preview_extent, preview_slice_z);\n" \
		+ body + color_line + "}\n"


## Whether `graph` moves the fractal's surface: something is wired to the
## Output's Displace input and its Amplitude is not 0. A Tint-only graph
## colours the surface without moving it. Null is no graph.
static func displaces(graph: NoiseGraph) -> bool:
	if graph == null or graph.input_link(graph.output_id(), 0).is_empty():
		return false
	var out_state := graph.node(graph.output_id())
	return out_state != null and float(out_state.table.get_value(&"amplitude")) != 0.0


## {uniform name: value} for every live parameter in the graph, for pushing to a
## material without a recompile. Covers every FLOAT param of every node plus the
## Output's three floats and its tint colour; names the current shader does not
## declare are pushed harmlessly.
static func live_values(graph: NoiseGraph) -> Dictionary:
	var out: Dictionary = {}
	for id in graph.nodes:
		var state: NoiseGraph.NodeState = graph.nodes[id]
		var type := NoiseNodeRegistry.type_by_id(state.type_id)
		if type == null:
			continue
		for s in type.params():
			if s.type == NoiseParamSpec.Type.FLOAT:
				out["n_%s_%s" % [id, s.id]] = float(state.table.get_value(s.id))
		if id == graph.output_id():
			var tc := NoiseNodeType.to_color(state.extras.get("tint_color", [1.0, 0.45, 0.2, 1.0]))
			out["n_output_0_tint_color"] = Vector3(tc.r, tc.g, tc.b)
	return out


## True when editing (node_id, param_id) only needs a uniform push, not a rebuild.
static func is_live_param(graph: NoiseGraph, node_id: StringName, param_id: StringName) -> bool:
	if param_id == &"tint_color":
		return true
	if param_id == &"":
		return false
	var state := graph.node(node_id)
	if state == null:
		return false
	var type := NoiseNodeRegistry.type_by_id(state.type_id)
	if type == null:
		return false
	for s in type.params():
		if s.id == param_id:
			return s.type == NoiseParamSpec.Type.FLOAT
	return false


# ------------------------------------------------------------------ bodies

static func _displace_fn(graph: NoiseGraph, disp: Dictionary, errors: Array) -> String:
	if disp.is_empty():
		return "float noise_displace(vec3 p) { return 0.0; }\n"
	var used: Dictionary = {}
	for id in _ancestors(graph, disp["from"]):
		used[id] = true
	var body := _emit_nodes(graph, _ordered(graph, used), errors)
	var result := "v_%s_%d" % [disp["from"], disp["from_port"]]
	return "float noise_displace(vec3 p) {\n%s\treturn %s * n_output_0_amplitude;\n}\n" % [body, result]


static func _step_scale_fn(displace_wired: bool) -> String:
	if displace_wired:
		return "float noise_step_scale() { return n_output_0_step_scale; }\n"
	return "float noise_step_scale() { return 1.0; }\n"


static func _tint_fn(graph: NoiseGraph, tint: Dictionary, errors: Array) -> String:
	if tint.is_empty():
		return "vec3 noise_tint(vec3 col, vec3 p) { return col; }\n"
	var used: Dictionary = {}
	for id in _ancestors(graph, tint["from"]):
		used[id] = true
	var body := _emit_nodes(graph, _ordered(graph, used), errors)
	var result := "v_%s_%d" % [tint["from"], tint["from_port"]]
	return "vec3 noise_tint(vec3 col, vec3 p) {\n%s\tcol = mix(col, n_output_0_tint_color, clamp(%s, 0.0, 1.0) * n_output_0_tint_strength);\n\treturn col;\n}\n" % [body, result]


## GLSL statements for every node in `ordered`, each declaring its output locals.
static func _emit_nodes(graph: NoiseGraph, ordered: Array, errors: Array) -> String:
	var out := ""
	for id in ordered:
		var state: NoiseGraph.NodeState = graph.node(id)
		if state == null or state.type_id == NoiseGraph.OUTPUT_TYPE:
			continue
		var type := NoiseNodeRegistry.type_by_id(state.type_id)
		if type == null:
			errors.append("Unknown node type '%s'" % state.type_id)
			continue
		var exprs: Array = []
		for i in type.inputs.size():
			var link := graph.input_link(id, i)
			if not link.is_empty():
				exprs.append("v_%s_%d" % [link["from"], link["from_port"]])
			elif type.inputs[i].type == NoisePort.Type.VEC3:
				exprs.append("p")
			else:
				exprs.append(_gf(type.inputs[i].default))
		var outs: Array = []
		for j in type.outputs.size():
			outs.append("v_%s_%d" % [id, j])
		var uniforms: Dictionary = {}
		var values: Dictionary = {}
		for s in type.params():
			values[String(s.id)] = state.table.get_value(s.id)
			if s.type == NoiseParamSpec.Type.FLOAT:
				uniforms[String(s.id)] = "n_%s_%s" % [id, s.id]
		var fragment: String = type.emit(exprs, outs, uniforms, values)
		for line in fragment.split("\n"):
			if line.strip_edges() == "":
				continue
			out += "\t" + line + "\n"
	return out


# ------------------------------------------------------------------ helpers

## Node ids reachable backward from `root` through the links, inclusive.
static func _ancestors(graph: NoiseGraph, root: StringName) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: StringName = stack.pop_back()
		if seen.has(cur):
			continue
		seen[cur] = true
		for link in graph.links:
			if link["to"] == cur:
				stack.append(link["from"])
	return seen


## `graph.order()` filtered to the `used` set (keys), in topological order.
static func _ordered(graph: NoiseGraph, used: Dictionary) -> Array:
	var out: Array = []
	for id in graph.order():
		if used.has(id):
			out.append(id)
	return out


## `uniform float` declarations for every FLOAT param of every used node, in a
## stable order; appends the names to `names`.
static func _uniform_decls(graph: NoiseGraph, used: Dictionary, names: Array, errors: Array) -> String:
	var decls := ""
	for id in _ordered(graph, used):
		var state: NoiseGraph.NodeState = graph.node(id)
		if state == null or state.type_id == NoiseGraph.OUTPUT_TYPE:
			continue
		var type := NoiseNodeRegistry.type_by_id(state.type_id)
		if type == null:
			continue
		for s in type.params():
			if s.type != NoiseParamSpec.Type.FLOAT:
				continue
			var name := "n_%s_%s" % [id, s.id]
			decls += "uniform float %s = %s;\n" % [name, _gf(state.table.get_value(s.id))]
			names.append(name)
	return decls


## A float as a GLSL literal that always carries a decimal point.
static func _gf(x: Variant) -> String:
	var s := String.num(float(x), 6)
	if not s.contains(".") and not s.contains("e") and not s.contains("E"):
		s += ".0"
	return s
