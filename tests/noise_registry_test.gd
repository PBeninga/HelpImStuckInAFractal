extends "res://tests/test_case.gd"
## The node catalogue: the registry's preloaded list matches src/noise/nodes
## exactly (an exported build cannot scan the directory, so the list is what
## ships), every type satisfies the shared schema, and the fifteen v1 types are
## present and shaped correctly.


const V1_IDS := [
	&"position", &"value_noise", &"gradient_noise", &"cellular", &"transform",
	&"warp", &"combine_xyz", &"split_xyz", &"constant", &"math", &"remap",
	&"clamp", &"mix", &"length", &"output"]


func run() -> void:
	# ------------------------------------------------------------ NoisePort
	check_eq(NoisePort.NAMES.size(), 2, "there are two port types")
	check_eq(NoisePort.COLORS.size(), 2, "each has a slot colour")
	check_eq(NoisePort.TOOLTIPS.size(), 2, "and a tooltip")
	for i in 2:
		check(NoisePort.TOOLTIPS[i].length() > 20, "the %s tooltip explains what it carries" % NoisePort.NAMES[i])
	check_eq(NoisePort.glsl_type(NoisePort.Type.FLOAT), "float", "FLOAT maps to the GLSL float")
	check_eq(NoisePort.glsl_type(NoisePort.Type.VEC3), "vec3", "VEC3 maps to the GLSL vec3")
	check_eq(int(NoisePort.Type.FLOAT), 0, "FLOAT is 0 (saved graphs store these by index)")
	check_eq(int(NoisePort.Type.VEC3), 1, "VEC3 is 1")

	# ------------------------------------- the list matches the directory
	# DirAccess works here because tests run from source; the registry itself
	# must not depend on it, so a node file missing from the list fails here.
	var listed: Array[String] = []
	for script in NoiseNodeRegistry.NODE_SCRIPTS:
		listed.append(script.resource_path)
	var on_disk: Array[String] = []
	for file_name in DirAccess.get_files_at(NoiseNodeRegistry.NODE_DIR):
		if file_name.ends_with(".gd"):
			on_disk.append("%s/%s" % [NoiseNodeRegistry.NODE_DIR, file_name])
	on_disk.sort()
	var missing := on_disk.filter(func(path: String) -> bool: return not listed.has(path))
	var extra := listed.filter(func(path: String) -> bool: return not on_disk.has(path))
	check(missing.is_empty() and extra.is_empty() and listed.size() == on_disk.size(),
		"NODE_SCRIPTS lists exactly the %d .gd files in %s (missing %s, extra %s)"
		% [on_disk.size(), NoiseNodeRegistry.NODE_DIR, missing, extra])
	var listed_sorted := listed.duplicate()
	listed_sorted.sort()
	check(listed == listed_sorted, "NODE_SCRIPTS is kept in file-name order")
	check_eq(NoiseNodeRegistry.all().size(), on_disk.size(), "all() instances one type per node file")
	check(not FileAccess.get_file_as_string("res://src/noise/noise_node_registry.gd").contains("DirAccess."),
		"the registry does not scan the directory (a .pck holds .gdc files)")

	# ---------------------------------------------------------- the registry
	var types := NoiseNodeRegistry.all()
	var ids := NoiseNodeRegistry.ids()
	for id in V1_IDS:
		check(ids.has(id), "the registry knows '%s'" % id)
		check(NoiseNodeRegistry.has_type(id), "has_type('%s') agrees" % id)
		check(NoiseNodeRegistry.type_by_id(id) != null, "type_by_id('%s') returns a type" % id)
	check_eq(types.size(), V1_IDS.size(), "the catalogue has exactly the fifteen v1 types")
	check(NoiseNodeRegistry.type_by_id(&"not_a_node") == null, "an unknown id gives null")
	check(not NoiseNodeRegistry.has_type(&"not_a_node"), "and has_type says no")
	check(NoiseNodeRegistry.type_by_id(&"value_noise") != NoiseNodeRegistry.type_by_id(&"value_noise"),
		"each call returns a FRESH instance")
	check(NoiseNodeRegistry.groups().size() > 0, "the registry lists add-menu groups")
	for g in NoiseNodeRegistry.groups():
		check(g != "", "no group is the empty string")

	# sorted by order
	var previous := -1
	var sorted_ok := true
	for t in types:
		if t.order < previous:
			sorted_ok = false
		previous = t.order
	check(sorted_ok, "all() is sorted by order, so the add menu is stable")

	# every type satisfies the shared schema
	var seen := {}
	for t in types:
		check(not seen.has(t.id), "type id '%s' is unique across the directory" % t.id)
		seen[t.id] = true
		NoiseNodeChecks.check_type(self, t)

	# ------------------------------------------------------ the fixed types
	var pos := NoiseNodeRegistry.type_by_id(&"position")
	check_eq(pos.inputs.size(), 0, "Position has no inputs")
	check_eq(pos.outputs.size(), 1, "Position has one output")
	check_eq(pos.outputs[0].type, NoisePort.Type.VEC3, "…a Vec3")
	check_eq(pos.group, "Source", "Position is in the Source group")

	var output := NoiseNodeRegistry.type_by_id(&"output")
	check_eq(output.inputs.size(), 4, "Output takes Displace, Tint, Texture and Bump")
	check_eq(output.inputs[0].type, NoisePort.Type.FLOAT, "Displace is a Float")
	check_eq(output.inputs[1].type, NoisePort.Type.FLOAT, "Tint is a Float")
	check_eq(output.inputs[2].type, NoisePort.Type.VEC3, "Texture is a Vec3")
	check_eq(output.inputs[3].type, NoisePort.Type.FLOAT, "Bump is a Float")
	check_eq(output.outputs.size(), 0, "Output has no outputs: it IS the field's effect")
	for id in [&"amplitude", &"step_scale", &"tint_strength"]:
		check(output.new_table().has(id), "Output has a '%s' row" % id)
	check(output.extras_default().has("tint_color"), "Output's tint colour is an extra")
	var tc: Variant = output.extras_default()["tint_color"]
	check(tc is Array and (tc as Array).size() == 4, "…a four-float Array, so extras stay JSON-native")
	# Displacement sign is documented as the spec requires.
	check(output.description.to_lower().contains("push") and output.description.to_lower().contains("in"),
		"Output's description says a positive Displace pushes the surface in")

	# the two fixed types are what NoiseGraph calls Source and Output
	check_eq(NoiseGraph.SOURCE_TYPE, pos.id, "NoiseGraph's Source is the Position node")
	check_eq(NoiseGraph.OUTPUT_TYPE, output.id, "NoiseGraph's Output is the Output node")

	# Output's extra control really appears
	var container := VBoxContainer.new()
	root.add_child(container)
	var state := NoiseGraph.NodeState.new()
	state.id = &"output_0"
	state.type_id = &"output"
	state.extras = output.extras_default().duplicate(true)
	output.build_extra_controls(state, container)
	await frames(1)
	var picker := _find_color_picker(container)
	check(picker != null, "Output builds a ColorPickerButton for its tint colour")
	check(picker != null and picker.tooltip_text.length() > 20, "…and it says what the colour is for")
	container.queue_free()
	await frames(1)

	# Math and Transform carry their baked enums
	var math := NoiseNodeRegistry.type_by_id(&"math")
	check(math.new_table().has(&"op"), "Math has an Op enum")
	check_eq(math.new_table().spec(&"op").type, NoiseParamSpec.Type.ENUM, "…really an enum")
	var transform := NoiseNodeRegistry.type_by_id(&"transform")
	check(transform.new_table().has(&"axis"), "Transform has an Axis enum")
	check(transform.new_table().has(&"angle"), "…and an Angle")


func _find_color_picker(node: Node) -> ColorPickerButton:
	for child in node.get_children():
		if child is ColorPickerButton:
			return child
		var deeper := _find_color_picker(child)
		if deeper != null:
			return deeper
	return null
