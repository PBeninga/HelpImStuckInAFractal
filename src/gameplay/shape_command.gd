class_name ShapeCommand
extends RefCounted
## Small, validated command language over existing shape knobs; no new DE math.

static func parse(command: String, table: AttributeTable, values: Dictionary) -> Dictionary:
	var words := command.strip_edges().split(" ", false)
	if words.size() != 2 or not words[1].is_valid_float():
		return {"ok": false, "message": "Use '<attribute> <number>', for example 'inversion -0.5'."}
	var value := float(words[1])
	var id := StringName(words[0])
	if id == &"inversion":
		match int(values.get(&"shape", 0)):
			FractalParams.Shape.KLEINIAN: id = &"kleinian_radius"
			FractalParams.Shape.MANDELBOX: id = &"fixed_radius"
			_: return {"ok": false, "message": "Inversion commands require a Kleinian or Mandelbox shape."}
		value += float(values.get(id, table.get_default(id)))
	if not table.has(id):
		return {"ok": false, "message": "Unknown shape attribute: %s" % id}
	var spec := table.spec(id)
	if spec.type not in [AttributeSpec.Type.FLOAT, AttributeSpec.Type.INT] or not spec.is_shown(values):
		return {"ok": false, "message": "Command needs a numeric attribute supported by this fractal."}
	if not is_finite(value) or value < spec.hard_min or value > spec.hard_max \
			or (spec.type == AttributeSpec.Type.INT and value != floor(value)):
		return {"ok": false, "message": "Command is outside the attribute's valid range."}
	return {"ok": true, "id": id, "value": value}
