extends RefCounted
## Voice/MCP access to the same models and actions as the game's console.
## No arbitrary property writes or script execution.
const SECTIONS := ["overview", "shape", "look", "view", "gameplay", "axes", "noise"]
const ACTIONS := ["start_game", "pause", "resume", "add_shape", "remove_shape", "select_shape", "rename_shape", "return_to_spawn", "find_nearest_surface", "reset_renderer", "reset_palette", "reset_axes", "toggle_fullscreen", "reset_window", "show_console", "hide_console", "show_noise", "hide_noise", "back_to_menu", "list_levels", "save_level", "load_level"]
var bridge: Node

func _init(p_bridge: Node) -> void:
	bridge = p_bridge

func register(cc: Node) -> void:
	var section := {"type": "string", "enum": SECTIONS}
	var index := {"type": "integer", "description": "Zero-based shape index; defaults to the active shape."}
	cc.register_tool("get_console_controls", "Inspect any console section before editing it. Overview lists shapes and available sections/actions. Shape and look include attribute ids, types, limits, options and bindings. Look covers lighting, material and palette. View covers camera and renderer. Axes lists all keys, labels, speeds and values. Noise includes the graph and available node types.",
		{"type": "object", "properties": {"section": section, "shape_index": index}, "additionalProperties": false}, inspect)
	cc.register_tool("set_console_controls", "Edit console settings. Read the section first. Shape/look values use {defaults: {attribute_id: value}, bindings: {attribute_id: {source, gain, waveform, period}}}; source empty clears a binding, time or an axis id drives it. View/gameplay values are a partial field map. Axes uses {entries: [...]} replacing the complete list. Noise uses the complete graph returned by inspection. Other settings stay unchanged. Results include actual applied values and warnings.",
		{"type": "object", "properties": {"section": section, "shape_index": index, "values": {"type": "object"}}, "required": ["section", "values"], "additionalProperties": false}, edit)
	cc.register_tool("console_action", "Run a console button/action, start the game, or pause/resume. find_nearest_surface helps a lost pilot: cast rays in all directions and turn toward the closest hit without moving or changing speed; cancels any active manoeuvre on success and reports if nothing was found. Shape actions take shape_index; rename takes name. Save/load use a level name within the game's saves directory; list_levels lists them. Saving overwrites that named level; back_to_menu discards unsaved changes. Only do these when requested by the pilot.",
		{"type": "object", "properties": {"action": {"type": "string", "enum": ACTIONS}, "shape_index": index, "name": {"type": "string"}}, "required": ["action"], "additionalProperties": false}, act)

func _main() -> Node:
	return bridge._main()

func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

func inspect(args: Dictionary) -> Dictionary:
	var main := _main()
	if main == null:
		return _fail("No console is open. Use console_action start_game to enter the cockpit.")
	var section := str(args.get("section", "overview"))
	var index := int(args.get("shape_index", main.params.active))
	var data: Variant
	match section:
		"overview":
			var shapes: Array = []
			for i in main.shapes().count():
				shapes.append({"index": i, "label": main.shapes().label(i)})
			data = {"sections": SECTIONS, "actions": ACTIONS, "shapes": shapes, "selected_shape": main.params.active, "active": main.params.active, "shape_run": main.shape_run.briefing() if main.shape_run != null else {}, "paused": main.get_tree().paused}
		"shape", "look":
			if section == "shape" and (index < 0 or index >= main.shapes().count()):
				return _fail("Shape index is out of range.")
			var table: AttributeTable = main.shapes().table(index) if section == "shape" else main.look_table()
			data = table.to_dict()
			data["attributes"] = _attributes(table)
		"view":
			data = {}
			for key in Workspace.FRACTAL_KEYS:
				data[key] = main.params.get(key)
			data["camera_mode"] = Workspace.CAMERA_MODE_NAMES[main.params.camera_mode]
			data["camera_modes"] = Workspace.CAMERA_MODE_NAMES
		"gameplay": data = main.params.gameplay.to_dict()
		"axes": data = {"entries": main.keymap().to_list()}
		"noise":
			data = {"graph": main.noise_window().to_dict(), "node_types": []}
			for type in NoiseNodeRegistry.all():
				var ports := {"inputs": [], "outputs": []}
				for p in type.inputs:
					ports.inputs.append({"name": p.name, "type": p.type, "description": p.tooltip})
				for p in type.outputs:
					ports.outputs.append({"name": p.name, "type": p.type, "description": p.tooltip})
				data.node_types.append({"id": str(type.id), "description": type.description, "ports": ports, "defaults": type.new_table().to_dict(), "parameters": _noise_attributes(type), "extras": type.extras_default()})
		_: return _fail("Unknown console section.")
	return {"ok": true, "section": section, "shape_index": index, "data": data}

func _noise_attributes(type: NoiseNodeType) -> Array:
	var out: Array = []
	for s in type.params():
		out.append({"id": str(s.id), "type": NoiseParamSpec.Type.keys()[s.type], "description": s.tooltip,
			"min": s.hard_min, "max": s.hard_max, "options": s.enum_labels, "option_values": s.enum_values})
	return out

func _attributes(table: AttributeTable) -> Array:
	var out: Array = []
	for s in table.specs:
		out.append({"id": str(s.id), "label": s.label, "type": AttributeSpec.Type.keys()[s.type], "description": s.tooltip, "effects": s.effects,
			"min": s.hard_min, "max": s.hard_max, "options": s.enum_labels, "option_values": s.enum_values, "bindable": s.bindable})
	return out

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func edit(args: Dictionary) -> Dictionary:
	var main := _main()
	if main == null:
		return _fail("No console is open. Start the game first.")
	if not args.get("values") is Dictionary:
		return _fail("values must be an object.")
	var values: Dictionary = args.values
	var section := str(args.get("section", ""))
	var warnings: Array = []
	match section:
		"shape", "look":
			var index := int(args.get("shape_index", main.params.active))
			if section == "shape" and (index < 0 or index >= main.shapes().count()):
				return _fail("Shape index is out of range.")
			for key in values:
				if key not in ["defaults", "bindings"] or not values[key] is Dictionary:
					return _fail("Use defaults and bindings objects for shape/look edits.")
			for binding in values.get("bindings", {}).values():
				if not binding is Dictionary:
					return _fail("Each binding must be an object.")
			var table: AttributeTable = main.shapes().table(index) if section == "shape" else main.look_table()
			for key in values.get("defaults", {}):
				if not table.has(StringName(key)):
					return _fail("Unknown attribute: " + str(key))
				var spec := table.spec(StringName(key))
				var value: Variant = values.defaults[key]
				if spec.type in [AttributeSpec.Type.FLOAT, AttributeSpec.Type.INT, AttributeSpec.Type.ENUM] and not _number(value):
					return _fail("Expected a finite number for " + str(key))
				if spec.type == AttributeSpec.Type.BOOL and not value is bool:
					return _fail("Expected a boolean for " + str(key))
				if spec.type == AttributeSpec.Type.COLOR and (not value is Array or value.size() < 3 or not value.all(_number)):
					return _fail("Expected RGB numbers for " + str(key))
			for key in values.get("bindings", {}):
				if table.binding(StringName(key)) == null:
					return _fail("Attribute cannot be bound: " + str(key))
				var binding: Dictionary = values.bindings[key]
				for field in ["gain", "period"]:
					if binding.has(field) and not _number(binding[field]):
						return _fail("Binding " + field + " must be a finite number.")
			warnings = table.apply_dict(values)
		"view":
			var parsed := {}
			for key in values:
				if not Workspace.FRACTAL_KEYS.has(key):
					return _fail("Unknown view control: " + str(key))
				var v: Variant = Workspace._parse_fractal(key, values[key])
				if v == null:
					return _fail("Invalid view value: " + str(key))
				parsed[key] = v
			for key in parsed:
				main.params.set(key, parsed[key])
			if parsed.has("mouse_sensitivity"):
				main.get_node("/root/Settings").mouse_sensitivity = main.params.mouse_sensitivity
		"gameplay":
			var merged: Dictionary = main.params.gameplay.to_dict()
			merged.merge(values, true)
			warnings = main.params.gameplay.apply_dict(merged)
		"axes":
			if not values.get("entries") is Array:
				return _fail("Axes values need an entries array; read the current list before replacing it.")
			warnings = main.keymap().apply_list(values.entries)
		"noise":
			if not values.get("nodes") is Array or not values.get("links") is Array:
				return _fail("Noise values must be a complete graph with nodes and links arrays.")
			warnings = main.noise_window().apply_dict(values)
		_: return _fail("Unknown or read-only console section.")
	main._resolve_once()
	var result := inspect(args)
	result["warnings"] = warnings
	result["message"] = "Console updated." if warnings.is_empty() else "Console updated with warnings; inspect the returned values."
	return result

func act(args: Dictionary) -> Dictionary:
	var action := str(args.get("action", ""))
	if not ACTIONS.has(action):
		return _fail("Unknown console action.")
	var main := _main()
	if action == "start_game":
		if main == null:
			bridge._start_game.call_deferred()
		return {"ok": true, "message": "Game start requested. Check get_ship_status shortly."}
	if main == null:
		return _fail("No console is open. Start the game first.")
	if action in ["show_console", "show_noise"] and main.view.is_escaped():
		return _fail("Gameplay panels stay hidden after escape. Return to spawn to start another flight.")
	var index := int(args.get("shape_index", main.params.active))
	if action in ["remove_shape", "select_shape", "rename_shape"] and (index < 0 or index >= main.shapes().count()):
		return _fail("Shape index is out of range.")
	match action:
		"pause": main.get_tree().paused = true
		"resume": main.get_tree().paused = false
		"add_shape":
			if main.add_shape() < 0:
				return _fail("The shape limit has been reached.")
		"remove_shape":
			if main.shapes().count() <= 1:
				return _fail("Keep at least one shape.")
			main.console().shape_pane().remove_shape(index)
		"select_shape": main.console().shape_pane().select(index)
		"rename_shape":
			if str(args.get("name", "")).strip_edges().is_empty():
				return _fail("A non-empty shape name is required.")
			main.shapes().set_label(index, str(args.name))
		"return_to_spawn": main.return_to_spawn()
		"find_nearest_surface":
			main._resolve_once()
			return bridge._find_nearest_surface(main)
		"reset_renderer": main.view_pane().renderer.reset_defaults()
		"reset_palette": main.console().palette().reset()
		"reset_axes": main.keymap().reset_to_default()
		"toggle_fullscreen": main.toggle_fullscreen()
		"reset_window": main.reset_window()
		"show_console": main.console().open()
		"hide_console": main.console().hide_console()
		"show_noise": main.noise_window().open()
		"hide_noise": main.noise_window().close()
		"back_to_menu": main.back_to_menu.call_deferred()
		"list_levels": return {"ok": true, "data": bridge._list_views()}
		"save_level", "load_level":
			var path: String = bridge._view_path(args)
			if path.is_empty():
				return _fail("A level name is required.")
			if action == "save_level":
				var err := Workspace.save_file(path, main.shapes(), main.look_table(), main.keymap(), main.params, main.camera, main.noise_window().to_dict())
				if err != OK:
					return _fail("Save failed: error %d" % err)
				main.workspace_files().note_saved(path)
			else:
				var file := FileAccess.open(path, FileAccess.READ)
				if file == null:
					return _fail("Level could not be opened.")
				var data: Variant = JSON.parse_string(file.get_as_text())
				if not data is Dictionary or Workspace.kind_of(data) != "level":
					return _fail("Not a valid level file.")
				main.load_level_from(path)
	main._resolve_once()
	return {"ok": true, "message": "Console action completed: " + action}
