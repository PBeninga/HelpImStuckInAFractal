extends Control
## Draws over the game view: corner brackets and a label on each highlighted
## feature (an arrow at the screen edge when it is off screen or behind), the
## exit's marker, a dotted course line while the autopilot flies, the scan
## pulse and a reticle. Projection and visibility come from the ship adapter,
## so the brackets sit exactly on the game's picture.

const Features := preload("res://call_center/features.gd")

const COLOR_HIGHLIGHT := Color(1.0, 0.82, 0.3)
const COLOR_EXIT := Color(0.45, 0.95, 1.0)
const COLOR_RETICLE := Color(0.55, 0.85, 1.0, 0.45)
const EDGE_INSET := 46.0
## Seconds between visibility refreshes (each can trace the world on the CPU).
const LOS_PERIOD := 0.4
## The exit's glow ring radius, in metres.
const EXIT_GLOW_M := 100.0

var show_exit := false
## id -> {label, until (seconds on _clock), occluded}
var highlights := {}
var course_target := ""
## The ship adapter (ship_adapter.gd) and the feature registry (features.gd).
var adapter: Node
var features: Features

var _font: Font
var _clock := 0.0
var _los_wait := 0.0
var _scan_t := -1.0
var _exit_occluded := false


func setup(p_adapter: Node, p_features: Features) -> void:
	adapter = p_adapter
	features = p_features
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func highlight(id: String, label: String, seconds: float) -> void:
	var key := Features.normalize_id(id)
	var old: Dictionary = highlights.get(key, {})
	highlights[key] = {"label": label if label != "" else old.get("label", ""),
		"until": _clock + seconds, "occluded": old.get("occluded", false)}
	_los_wait = 0.0
	queue_redraw()


func clear() -> void:
	highlights.clear()
	queue_redraw()


func scan_pulse() -> void:
	_scan_t = 0.0


func _process(delta: float) -> void:
	_clock += delta
	for id in highlights.keys():
		if highlights[id]["until"] < _clock:
			highlights.erase(id)
	if _scan_t >= 0.0:
		_scan_t += delta
		if _scan_t > 1.4:
			_scan_t = -1.0
	_los_wait -= delta
	if _los_wait <= 0.0 and _ready_to_draw():
		_los_wait = LOS_PERIOD
		for id in highlights:
			var f := features.find(id)
			if not f.is_empty():
				highlights[id]["occluded"] = not adapter.visible_from_camera(f["pos"])
		var ex := features.exit()
		if show_exit and not ex.is_empty():
			_exit_occluded = not adapter.visible_from_camera(ex["pos"])
	queue_redraw()


func _ready_to_draw() -> bool:
	return adapter != null and is_instance_valid(adapter) and features != null


func _draw() -> void:
	if not _ready_to_draw():
		return
	_draw_reticle()
	if _scan_t >= 0.0:
		var r := lerpf(20.0, size.length() * 0.6, _scan_t / 1.4)
		draw_arc(size * 0.5, r, 0.0, TAU, 96, Color(0.5, 0.9, 1.0, 0.6 * (1.0 - _scan_t / 1.4)), 3.0, true)
	if course_target != "":
		var cf := features.find(course_target)
		if not cf.is_empty():
			var sp: Variant = adapter.project(cf["pos"])
			if sp != null and Rect2(Vector2.ZERO, size).has_point(sp):
				_dotted(size * 0.5, sp, Color(COLOR_HIGHLIGHT, 0.7))
	var ex := features.exit()
	if show_exit and not ex.is_empty():
		_draw_marker(ex, "EXIT", COLOR_EXIT, _exit_occluded, 1.0)
	var pulse := 0.65 + 0.35 * sin(_clock * 6.0)
	for id in highlights:
		if show_exit and id == features.exit_id:
			continue
		var f := features.find(id)
		if not f.is_empty():
			var h: Dictionary = highlights[id]
			_draw_marker(f, h["label"], COLOR_HIGHLIGHT, h["occluded"], pulse)


func _draw_reticle() -> void:
	var c := size * 0.5
	draw_arc(c, 9.0, 0.0, TAU, 32, COLOR_RETICLE, 1.5, true)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * 14.0, c + d * 22.0, COLOR_RETICLE, 1.5, true)


func _draw_marker(f: Dictionary, caption: String, color: Color, occluded: bool, alpha: float) -> void:
	var rel := Features.relative(adapter.pose(), f["pos"], adapter.meters_per_unit())
	if rel["range_m"] < 10:
		return   # the ship is there: nothing to point at
	var col := Color(color, color.a * alpha * (0.5 if occluded else 1.0))
	var range_text := "%d m" % rel["range_m"] if rel["range_m"] < 1000 else "%.2f km" % (rel["range_m"] / 1000.0)
	var title := "#%s %s" % [f["id"], String(f["name"]).to_upper()]
	var sub := range_text + ("  (behind the wall)" if occluded else "")
	if caption != "":
		sub = caption + "  ·  " + sub
	var sp: Variant = adapter.project(f["pos"])
	var screen := Rect2(Vector2.ZERO, size).grow(-8.0)
	if sp != null and screen.has_point(sp):
		if f["kind"] == "exit" and not occluded:
			_exit_glow(f["pos"], sp)
		var units: float = maxf(rel["range_m"] / adapter.meters_per_unit(), 0.005)
		var s := clampf(1.1 / units, 16.0, 64.0)
		_brackets(sp, s, col)
		_label(sp + Vector2(s + 8.0, -s), title, sub, col)
		return
	# off screen or behind: an arrow on an inset ellipse, toward the bearing
	var b := deg_to_rad(rel["bearing_deg"])
	var e := deg_to_rad(rel["elevation_deg"])
	var dir := Vector2(sin(b), -sin(e))
	if absf(rel["bearing_deg"]) > 90:
		dir.x = 1.0 if b >= 0.0 else -1.0   # behind: point to the shorter turn
	if dir.length() < 1e-3:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half := size * 0.5 - Vector2(EDGE_INSET, EDGE_INSET)
	var k := 1.0 / sqrt(pow(dir.x / half.x, 2.0) + pow(dir.y / half.y, 2.0))
	var p := size * 0.5 + dir * k
	var perp := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([p + dir * 16.0, p - dir * 7.0 + perp * 12.0, p - dir * 7.0 - perp * 12.0])
	draw_colored_polygon(tri, Color(col, maxf(col.a, 0.8)))
	tri.append(tri[0])
	draw_polyline(tri, Color(0, 0, 0, 0.8), 2.0, true)
	var line2: String = sub + "  ·  " + rel["direction"]
	var w := maxf(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x,
		_font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var lp: Vector2
	if absf(dir.x) > absf(dir.y):
		# an arrow on a side edge: the label sits beside it, toward the middle
		lp = Vector2(p.x + 24.0 if dir.x < 0.0 else p.x - 24.0 - w, p.y + 4.0)
	else:
		lp = p - dir * 40.0
		lp.x -= w * 0.5
	lp.x = clampf(lp.x, 8.0, size.x - w - 8.0)
	lp.y = clampf(lp.y, 24.0, size.y - 30.0)
	_label(lp, title, line2, col)


## A HUD glow ring where the exit is (EXIT_GLOW_M across in the world), so the
## destination reads even when the game draws nothing there.
func _exit_glow(pos: Vector3, sp: Vector2) -> void:
	var pose: Dictionary = adapter.pose()
	var edge: Variant = adapter.project(pos + pose["right"] * (EXIT_GLOW_M / adapter.meters_per_unit()))
	var r := clampf((edge as Vector2).distance_to(sp) if edge != null else 12.0, 6.0, size.y * 0.45)
	var pulse := 0.75 + 0.25 * sin(_clock * 3.0)
	for i in 6:
		var k := float(i) / 6.0
		draw_arc(sp, r * (1.0 + k * 0.6), 0.0, TAU, 64, Color(COLOR_EXIT, 0.35 * (1.0 - k) * pulse), 3.0 + 4.0 * k, true)
	draw_arc(sp, r, 0.0, TAU, 64, Color(1, 1, 1, 0.85 * pulse), 2.5, true)
	for i in 3:
		var a0 := _clock * 1.5 + i * TAU / 3.0
		draw_arc(sp, r * 0.62, a0, a0 + 1.4, 24, Color(1.0, 0.45, 0.95, 0.7 * pulse), 3.0, true)


func _brackets(c: Vector2, s: float, col: Color) -> void:
	var l := s * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx * s, sy * s)
			draw_line(corner, corner - Vector2(sx * l, 0), col, 2.0, true)
			draw_line(corner, corner - Vector2(0, sy * l), col, 2.0, true)


func _label(at: Vector2, title: String, sub: String, col: Color) -> void:
	var w := maxf(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x,
		_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	draw_rect(Rect2(at + Vector2(-6, -16), Vector2(w + 12, 38)), Color(0.0, 0.03, 0.08, 0.72 * col.a))
	draw_string(_font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, maxf(col.a, 0.75)))
	draw_string(_font, at + Vector2(0, 16), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, maxf(col.a, 0.75) * 0.85))


func _dotted(a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(a.distance_to(b) / 12.0)
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 2.0, true)
