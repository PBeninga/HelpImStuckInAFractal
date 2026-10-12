extends ColorRect
## Screen-only guidance, drawn after the fractal and before cockpit UI.
const MAX_REGIONS := 8
var regions: Array = []
var seconds_left := 0.0
var _shader := ShaderMaterial.new()
var _suppressed := false

func _init() -> void:
	name = "ScreenTints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shader.shader = preload("res://src/ui/screen_tints.gdshader")
	material = _shader
	hide()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	_shader.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))

func set_tints(args: Dictionary) -> Dictionary:
	if _suppressed:
		return {"ok": false, "message": "Screen guidance is hidden after escape."}
	var items: Variant = args.get("regions")
	var duration: Variant = args.get("seconds", 5)
	if not items is Array or items.size() > MAX_REGIONS:
		return {"ok": false, "message": "regions must be an array of at most 8 screen regions."}
	if not _range(duration, 1.0, 30.0):
		return {"ok": false, "message": "seconds must be from 1 to 30."}
	# Validate the entire update before replacing any visible guidance.
	for region in items:
		if not region is Dictionary or not _vector(region.get("center"), 2) or not _vector(region.get("color"), 3):
			return {"ok": false, "message": "Each region needs center [u,v] and color [r,g,b], with components in 0..1."}
		if not _range(region.get("radius"), 0.005, 1.0) or not _range(region.get("strength", 0.45), 0.0, 1.0):
			return {"ok": false, "message": "radius must be 0.005..1 view heights and strength must be 0..1."}
	var circles := PackedVector3Array()
	var colors := PackedColorArray()
	circles.resize(MAX_REGIONS)
	colors.resize(MAX_REGIONS)
	for i in items.size():
		var r: Dictionary = items[i]
		circles[i] = Vector3(r.center[0], r.center[1], r.radius)
		colors[i] = Color(r.color[0], r.color[1], r.color[2], r.get("strength", 0.45))
	regions = items.duplicate(true)
	seconds_left = float(duration) if not regions.is_empty() else 0.0
	_shader.set_shader_parameter("region_count", regions.size())
	_shader.set_shader_parameter("circles", circles)
	_shader.set_shader_parameter("tints", colors)
	visible = not regions.is_empty()
	return {"ok": true, "region_count": regions.size(), "seconds": seconds_left, "coordinates": "screen UV; top-left origin"}

func clear() -> void:
	regions.clear()
	seconds_left = 0.0
	_shader.set_shader_parameter("region_count", 0)
	hide()

func set_suppressed(on: bool) -> void:
	_suppressed = on
	if on:
		clear()

func _process(delta: float) -> void:
	if seconds_left > 0.0:
		seconds_left = maxf(0.0, seconds_left - delta)
		if seconds_left == 0.0:
			clear()

static func _range(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _vector(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(v): return _range(v, 0.0, 1.0))
