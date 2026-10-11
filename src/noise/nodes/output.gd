extends NoiseNodeType
## Output: the end of the graph — what the field does to the picture. Fixed, one
## per graph. It has no emit(): the compiler reads its inputs, its parameters and
## its tint colour directly and writes the three region functions from them.
##
## Displace (a Float) is multiplied by Amplitude and ADDED to the distance
## estimate: a POSITIVE value pushes the surface IN (the ray stops short). Tint
## (a Float) drives a colour blend toward the Tint colour. Texture (a Vec3)
## recolours the surface and Bump (a Float) tilts its normal for a fake relief;
## their strengths are the Material tab's Texture and Bump rows, not Output's.

const TINT_COLOR_TOOLTIP := "The colour the surface is tinted toward where the Tint input is high. Pick something that reads against the colour mode you are using — a warm hue over the cool Ice Fractal palette shows the field clearly."


func _init() -> void:
	id = &"output"
	title = "Output"
	group = "Output"
	order = 999
	description = "Output: what the field does to the fractal. Displace adds to the distance estimate (positive pushes the surface in), scaled by Amplitude; while it is wired, the ray march steps are shortened by Step scale so the displaced surface is not stepped over. Tint blends the surface colour toward the Tint colour. Nothing wired means the fractal renders exactly as it would with no field at all."
	inputs = [
		port("Displace", NoisePort.Type.FLOAT,
			"Displace: added to the distance estimate (times Amplitude). Positive pushes the surface in, negative pulls it out. Unwired it is 0, so the shape is untouched.", 0.0),
		port("Tint", NoisePort.Type.FLOAT,
			"Tint: how far to blend the surface colour toward the Tint colour, clamped to 0..1 and scaled by Tint strength. Unwired it is 0, so the colour is untouched.", 0.0),
		port("Texture", NoisePort.Type.VEC3,
			"Texture: a colour the surface is multiplied by, each channel clamped to 0..1, scaled by the Material tab's Texture row. Unwired it is white, so the colour is untouched.", 0.0),
		port("Bump", NoisePort.Type.FLOAT,
			"Bump: a height in fractal units whose across-surface slope tilts the normal (a fake relief; the surface does not move), scaled by the Material tab's Bump row. Unwired it is flat.", 0.0),
	]


func params() -> Array[NoiseParamSpec]:
	var out: Array[NoiseParamSpec] = []
	out.append(NoiseParamSpec.make({
		"id": "amplitude", "label": "Amplitude",
		"type": NoiseParamSpec.Type.FLOAT, "default": 0.05,
		"min": 0.0, "max": 1.0, "step": 0.001, "hard_min": 0.0, "hard_max": 10.0,
		"tooltip": "Multiplies the Displace input before it is added to the distance.",
		"effects": "Small values (0.02–0.1) ripple the surface; large values carve deep into it and can detach pieces. 0 leaves the shape untouched however the Displace field is wired."}))
	out.append(NoiseParamSpec.make({
		"id": "step_scale", "label": "Step scale",
		"type": NoiseParamSpec.Type.FLOAT, "default": 0.5,
		"min": 0.1, "max": 1.0, "step": 0.01, "hard_min": 0.1, "hard_max": 1.0,
		"tooltip": "The fraction of each ray-march step taken while Displace is wired, so the march does not step over the displaced surface.",
		"effects": "1 is the normal step and fastest but can miss thin displaced detail, showing holes. 0.3–0.6 is the usual trade. Lower is safer and slower. It has no effect when Displace is unwired."}))
	out.append(NoiseParamSpec.make({
		"id": "tint_strength", "label": "Tint strength",
		"type": NoiseParamSpec.Type.FLOAT, "default": 1.0,
		"min": 0.0, "max": 1.0, "step": 0.01, "hard_min": 0.0, "hard_max": 1.0,
		"tooltip": "Scales the Tint input, so the colour blend is tint × strength.",
		"effects": "1 is full tint where Tint is 1; 0 disables tinting without unwiring it. Use it to dial a strong field back to a subtle wash."}))
	return out


## A four-float Array, not a Color: extras are written straight into the saved
## graph and Color is not JSON. Use to_color() / from_color() at the edges.
func extras_default() -> Dictionary:
	return {"tint_color": [1.0, 0.45, 0.2, 1.0]}


func build_extra_controls(state, container: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Tint colour"
	label.tooltip_text = TINT_COLOR_TOOLTIP
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(56.0, 0.0)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.edit_alpha = false
	picker.tooltip_text = TINT_COLOR_TOOLTIP
	picker.color = to_color(state.extras.get("tint_color", extras_default()["tint_color"]))
	picker.color_changed.connect(func(c: Color) -> void:
		state.extras["tint_color"] = from_color(c)
		if container.has_meta(&"notify_node_changed"):
			var cb: Callable = container.get_meta(&"notify_node_changed")
			if cb.is_valid():
				cb.call(state.id, &"tint_color"))
	row.add_child(picker)
	container.add_child(row)
