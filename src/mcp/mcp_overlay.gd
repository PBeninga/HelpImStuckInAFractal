class_name McpOverlay
extends Control
## Draws the MCP bridge's shapes over the whole window. A shape is a Dictionary
## (see McpBridge.draw) in one of two spaces:
##
## - "screen": points are window pixels in logical units, the same space as
##   FractalView.project().
## - "world": points are fractal coordinates, projected through the camera every
##   frame so the drawing stays put on the fractal while you fly. A segment that
##   crosses behind the camera is clipped at the near plane.
##
## World drawings are drawn on top of the fractal (no occlusion), and only while
## a view is open.

const NEAR := 1e-6

## The shapes to draw, in order; shared with the bridge by reference.
var shapes: Array = []
## The open view, or null (title menu): world shapes are skipped.
var view: FractalView
var camera: CameraState


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	for s: Dictionary in shapes:
		var world: bool = s.get("space", "screen") == "world"
		if world and (view == null or camera == null or not is_instance_valid(view)):
			continue
		var color: Color = s.get("color", Color.WHITE)
		var width: float = s.get("width", 2.0)
		match s["type"]:
			"polyline":
				_draw_polyline(s["points"], world, bool(s.get("closed", false)), color, width)
			"circle":
				var c: Variant = _to_screen(s["center"], world)
				if c != null:
					if s.get("filled", false):
						draw_circle(c, s["radius"], color)
					else:
						draw_arc(c, s["radius"], 0.0, TAU, 48, color, width, true)
			"text":
				var p: Variant = _to_screen(s["position"], world)
				if p != null:
					p += s.get("offset", Vector2.ZERO)   # pixels, after projection
					var font := ThemeDB.fallback_font
					var size: int = s.get("size", 16)
					draw_string_outline(font, p, s["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
					draw_string(font, p, s["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_polyline(points: Array, world: bool, closed: bool, color: Color, width: float) -> void:
	var n := points.size()
	if n < 2:
		return
	var count := n if closed else n - 1
	if not world:
		var pts := PackedVector2Array(points)
		if closed:
			pts.append(points[0])
		draw_polyline(pts, color, width, true)
		return
	# World: clip each segment against the near plane, then join runs of
	# consecutive visible segments into one polyline so joints look right.
	var run := PackedVector2Array()
	for i in count:
		var seg: Variant = _clip_project(points[i], points[(i + 1) % n])
		if seg == null:
			if run.size() >= 2:
				draw_polyline(run, color, width, true)
			run = PackedVector2Array()
			continue
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if run.is_empty() or not run[run.size() - 1].is_equal_approx(a):
			if run.size() >= 2:
				draw_polyline(run, color, width, true)
			run = PackedVector2Array([a])
		run.append(b)
	if run.size() >= 2:
		draw_polyline(run, color, width, true)


func _to_screen(p: Variant, world: bool) -> Variant:
	if not world:
		return p
	return view.project(p)


## Camera-space depth of a world point.
func _depth(p: Vector3) -> float:
	return (p - camera.eye()).dot(camera.forward())


## The window segment for world segment a-b, clipped to the part in front of
## the camera, or null when it is entirely behind.
func _clip_project(a: Vector3, b: Vector3) -> Variant:
	var da := _depth(a)
	var db := _depth(b)
	if da <= NEAR and db <= NEAR:
		return null
	if da <= NEAR:
		a = a.lerp(b, (NEAR - da) / (db - da) + 1e-6)
	elif db <= NEAR:
		b = b.lerp(a, (NEAR - db) / (da - db) + 1e-6)
	var pa: Variant = view.project(a)
	var pb: Variant = view.project(b)
	if pa == null or pb == null:
		return null
	return [pa, pb]
