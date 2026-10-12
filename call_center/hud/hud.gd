extends CanvasLayer
## The call centre's HUD over the game: ship status upper-left, the diagnostics
## log lower-right, and SUB-DIMENSIONAL SUPPORT lower-left. McpBridge's pilot
## chat sits upper-right. Also draws feature brackets and big-moment banners.
## Never takes the mouse.

const Features := preload("res://call_center/features.gd")
const FeatureOverlay := preload("res://call_center/hud/feature_overlay.gd")
const IssueLog := preload("res://call_center/log/issue_log.gd")
const FrostedGlass := preload("res://src/ui/frosted_glass.gd")

const LAYER := 4
const PANEL_BG := Color(0.025, 0.14, 0.06, 0.68)
const PANEL_BORDER := Color.TRANSPARENT
const FLASH_BORDER := Color(0.9, 0.95, 1.0, 1.0)
const AMBER := Color(1.0, 0.85, 0.4)
const STYLE_COLORS := {
	"error": "#ff7b7b", "ok": "#7dffa8", "fail": "#ff4d4d", "pilot": "#ffd166",
	"info": "#b4d9b5", "agent": "#87f59a", "system": "#93a894",
}
const STYLE_PREFIX := {
	"error": "", "ok": "  -> ", "fail": "!! ", "pilot": "?? ", "info": "", "agent": "AGENT> ", "system": "-- ",
}
const ELEMENTS := ["diagnostics_log", "ship_status", "call_panel", "exit_marker", "reticle"]

var overlay: FeatureOverlay
var log_label: RichTextLabel
var status_label: Label
var call_status: Label
var banner: PanelContainer

var _panels := {}            # element name -> PanelContainer
var _root: Control
var _adapter: Node
var _features: Features
var _issues: IssueLog
var _support_number := ""
var _link_up := false
var _call_state := "idle"
var _agent_name := ""
var _call_started := 0.0
var _clock := 0.0
var _status_wait := 0.0
var _mono: Font
var _mono_bold: Font
var _banner_title: Label
var _banner_body: Label
var _escaped := false
var _before_escape := {}


func _init() -> void:
	layer = LAYER


func setup(features: Features, issues: IssueLog) -> void:
	_features = features
	_issues = issues
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "Liberation Mono", "monospace"])
	_mono = mono
	var mono_bold := SystemFont.new()
	mono_bold.font_names = mono.font_names
	mono_bold.font_weight = 700
	_mono_bold = mono_bold

	_root = Control.new()
	_root.name = "HudRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	overlay = FeatureOverlay.new()
	overlay.name = "FeatureOverlay"
	_root.add_child(overlay)
	overlay.setup(null, features)
	_build_diagnostics()
	_build_status()
	_build_call_panel()
	_build_banner()
	for e in issues.entries:
		_on_entry(e)
	issues.entry_added.connect(_on_entry)
	set_panels_visible(false)


## Point the HUD at the ship (ship_adapter.gd), or null when no game is up.
func set_adapter(adapter: Node) -> void:
	set_escaped(false)
	if _adapter != null and is_instance_valid(_adapter):
		if _adapter.maneuver_started.is_connected(_on_maneuver_started):
			_adapter.maneuver_started.disconnect(_on_maneuver_started)
			_adapter.maneuver_finished.disconnect(_on_maneuver_finished)
	_adapter = adapter
	overlay.adapter = adapter
	overlay.course_target = ""
	if adapter != null:
		adapter.maneuver_started.connect(_on_maneuver_started)
		adapter.maneuver_finished.connect(_on_maneuver_finished)
	visible = adapter != null


# ------------------------------------------------------------- building

func _panel(element: String, anchor_preset: int, at: Vector2, panel_size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.name = element
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	FrostedGlass.apply(p)
	_root.add_child(p)
	p.set_anchors_preset(anchor_preset)
	if anchor_preset != Control.PRESET_LEFT_WIDE:
		p.size = panel_size
		p.custom_minimum_size = panel_size
	match anchor_preset:
		Control.PRESET_TOP_RIGHT:
			p.offset_left = -panel_size.x - at.x
			p.offset_right = -at.x
			p.offset_top = at.y
			p.offset_bottom = at.y + panel_size.y
		Control.PRESET_BOTTOM_LEFT:
			p.offset_left = at.x
			p.offset_right = at.x + panel_size.x
			p.offset_top = -panel_size.y - at.y
			p.offset_bottom = -at.y
		Control.PRESET_BOTTOM_RIGHT:
			p.offset_left = -panel_size.x - at.x
			p.offset_right = -at.x
			p.offset_top = -panel_size.y - at.y
			p.offset_bottom = -at.y
		Control.PRESET_LEFT_WIDE:
			# from `at.y` below the top to `panel_size.y` above the bottom
			p.offset_left = at.x
			p.offset_right = at.x + panel_size.x
			p.offset_top = at.y
			p.offset_bottom = -panel_size.y
		_:
			p.position = at
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	p.add_child(box)
	_panels[element] = p
	return box


func _title(box: VBoxContainer, text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.add_theme_font_override("font", _mono_bold)
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Color(0.53, 0.95, 0.58))
	box.add_child(t)
	return t


func _build_diagnostics() -> void:
	var box := _panel(
		"diagnostics_log", Control.PRESET_BOTTOM_RIGHT, Vector2(16, 16), Vector2(256, 256))
	_title(box, "ERROR LOG  //  AUTO-RESOLUTION")
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_font_override("normal_font", _mono)
	log_label.add_theme_font_override("bold_font", _mono_bold)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.add_theme_font_size_override("bold_font_size", 12)
	box.add_child(log_label)


func _build_status() -> void:
	var box := _panel("ship_status", Control.PRESET_TOP_LEFT, Vector2(16, 16), Vector2(440, 134))
	_title(box, "ICEBOX  //  SUB-DIMENSIONAL DRIFT")
	status_label = Label.new()
	status_label.add_theme_font_override("font", _mono)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.78, 0.94, 0.80))
	box.add_child(status_label)


func _build_call_panel() -> void:
	var box := _panel("call_panel", Control.PRESET_BOTTOM_LEFT, Vector2(16, 16), Vector2(440, 94))
	_title(box, "SUB-DIMENSIONAL SUPPORT")
	call_status = Label.new()
	call_status.add_theme_font_size_override("font_size", 17)
	call_status.add_theme_color_override("font_color", AMBER)
	call_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(call_status)
	_refresh_call()


func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.name = "Banner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(24)
	banner.add_theme_stylebox_override("panel", sb)
	FrostedGlass.apply(banner)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.add_child(banner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	banner.add_child(box)
	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 30)
	_banner_title.add_theme_color_override("font_color", Color(0.48, 1.0, 0.56))
	box.add_child(_banner_title)
	_banner_body = Label.new()
	_banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_body.add_theme_font_size_override("font_size", 17)
	_banner_body.add_theme_color_override("font_color", Color(0.78, 0.94, 0.80))
	box.add_child(_banner_body)
	banner.visible = false


# ------------------------------------------------------------- public API

func set_panels_visible(on: bool) -> void:
	for element in _panels:
		set_panel_visible(element, on)


func set_panel_visible(element: String, on: bool) -> void:
	if _panels.has(element):
		_panels[element].visible = element == "call_panel" if _escaped else on


## Only the flashing support sign-off remains after the final escape.
func set_escaped(on: bool) -> void:
	if on == _escaped:
		return
	_escaped = on
	if on:
		_before_escape = {"overlay": overlay.visible, "banner": banner.visible}
		for element in _panels:
			_before_escape[element] = _panels[element].visible
		set_panels_visible(false)
		overlay.clear()
		overlay.hide()
		overlay.set_process(false)
		banner.hide()
	else:
		for element in _panels:
			set_panel_visible(element, _before_escape.get(element, false))
		overlay.visible = _before_escape.get("overlay", true)
		overlay.set_process(true)
		banner.visible = _before_escape.get("banner", false)
		_before_escape.clear()
	_refresh_call()


func is_panel_visible(element: String) -> bool:
	return _panels.has(element) and _panels[element].visible


## Fade the panels in (when the call centre begins).
func reveal() -> void:
	set_panels_visible(true)
	for element in _panels:
		var p: Control = _panels[element]
		p.modulate.a = 0.0
		create_tween().tween_property(p, "modulate:a", 1.0, 0.6)
	overlay.show_exit = true


## A big centred message (the demo's escape); `seconds` <= 0 keeps it up. It
## owns the middle of the screen, so the log and status panels step aside
## (the call panel stays for the sign-off).
func show_banner(title: String, lines: Array, seconds := 0.0) -> void:
	if _escaped:
		return
	_banner_title.text = title
	_banner_body.text = "\n".join(lines)
	banner.visible = true
	set_panel_visible("diagnostics_log", false)
	set_panel_visible("ship_status", false)
	if seconds > 0.0:
		get_tree().create_timer(seconds, true).timeout.connect(hide_banner)


func hide_banner() -> void:
	banner.visible = false
	set_panel_visible("diagnostics_log", true)
	set_panel_visible("ship_status", true)


func set_link_state(up: bool) -> void:
	_link_up = up
	_refresh_call()


func set_support_number(number: String) -> void:
	_support_number = number
	_refresh_call()


func set_call_state(state: String, info: Dictionary = {}) -> void:
	_call_state = state
	if info.has("agent_name"):
		_agent_name = str(info["agent_name"])
	if state == "connected":
		_call_started = _clock
	_refresh_call()


func call_state() -> String:
	return _call_state


func highlight_feature(id: String, label: String, seconds: float) -> void:
	overlay.highlight(id, label, seconds)
	var feature: Dictionary = _features.find(id)
	if not feature.is_empty():
		overlay.point_direction(feature["pos"], label if label != "" else feature["name"], seconds)


func scan_pulse(ids: Array) -> void:
	overlay.scan_pulse()
	for id in ids:
		overlay.highlight(str(id), "", 8.0)


func clear_highlights() -> void:
	overlay.clear()


## Pulse a HUD panel's border (or the exit marker / reticle) to draw the eye.
func flash(element: String, label: String = "") -> void:
	if element == "exit_marker":
		if _features.exit_id != "":
			overlay.highlight(_features.exit_id, label, 8.0)
		return
	if element == "reticle":
		overlay.scan_pulse()
		return
	var p: PanelContainer = _panels.get(element)
	if p == null:
		return
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	var tw := create_tween()
	for i in 4:
		tw.tween_callback(_set_border.bind(sb, FLASH_BORDER, 3))
		tw.tween_interval(0.35)
		tw.tween_callback(_set_border.bind(sb, PANEL_BORDER, 0))
		tw.tween_interval(0.25)


static func _set_border(sb: StyleBoxFlat, color: Color, width: int) -> void:
	sb.border_color = color
	sb.set_border_width_all(width)


func is_flashing(element: String) -> bool:
	var p: PanelContainer = _panels.get(element)
	return p != null and (p.get_theme_stylebox("panel") as StyleBoxFlat).border_color == FLASH_BORDER


# ------------------------------------------------------------- updates

func _process(delta: float) -> void:
	_clock += delta
	_status_wait -= delta
	if _status_wait <= 0.0:
		_status_wait = 0.2
		_refresh_status()
		_refresh_call()


func _on_maneuver_started(kind: String, info: Dictionary) -> void:
	if kind == "fly" and info.has("target"):
		var point: Array = info.target
		overlay.point_direction(Vector3(point[0], point[1], point[2]), "Flight target", 30.0)


func _on_maneuver_finished(_kind: String, _info: Dictionary) -> void:
	overlay.course_target = ""


func _on_entry(entry: Dictionary) -> void:
	var style: String = entry["style"]
	var color: String = STYLE_COLORS.get(style, "#ffffff")
	var text: String = STYLE_PREFIX.get(style, "") + _escape(entry["text"])
	if style == "fail" or style == "pilot":
		text = "[b]%s[/b]" % text
	log_label.append_text("[color=%s]%s[/color]\n" % [color, text])


func _refresh_status() -> void:
	if _escaped or status_label == null or _adapter == null or not is_instance_valid(_adapter):
		return
	var pose: Dictionary = _adapter.pose()
	var fwd: Vector3 = pose["forward"]
	var heading := fposmod(rad_to_deg(atan2(fwd.y, fwd.x)), 360.0)
	var pitch := rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0)))
	var clear_units: float = _adapter.clearance()
	var clearance := "unknown" if is_inf(clear_units) else "%d m" % _adapter.meters(clear_units)
	var ap: Dictionary = _adapter.autopilot_state()
	var ap_text := "idle"
	if ap.get("active", false):
		ap_text = "%s (est. %s s)" % [ap["kind"], String.num_scientific(ap.get("seconds_left", 0.0))]
	var lines := [
		"CLEARANCE  %s%s" % [clearance, "   ! PROXIMITY" if not is_inf(clear_units) and _adapter.meters(clear_units) < 10 else ""],
		"HEADING    %03d°   PITCH %+d°" % [int(round(heading)), int(round(pitch))],
		"AUTOPILOT  %s" % ap_text,
	]
	var escape: Dictionary = _adapter.escape_state()
	if escape.has("distance_to_boundary"):
		lines.append("EXIT       %s" % ("escaped" if escape.escaped else "%s m to boundary" % String.num_scientific(float(escape.distance_to_boundary) * _adapter.meters_per_unit())))
	lines.append("SPEED      %s m/s" % String.num_scientific(_adapter.travel_speed() * _adapter.meters_per_unit()))
	status_label.text = "\n".join(lines)


func _refresh_call() -> void:
	if call_status == null:
		return
	var waiting := _escaped or (_call_state == "idle" and _link_up and _support_number != "")
	var bright := not waiting or int(_clock * 2.0) % 2 == 0
	call_status.add_theme_color_override("font_color", AMBER if bright else Color(1, 1, 1))
	if _escaped:
		call_status.text = "Dimensional void traversed, Have a nice day!"
		return
	match _call_state:
		"ringing":
			call_status.text = "Incoming connection... routing you to the next available agent"
		"connected":
			var secs := int(_clock - _call_started)
			call_status.text = "ON CALL with %s   %02d:%02d" % [
				_agent_name if _agent_name != "" else "Support", secs / 60, secs % 60]
		"ended":
			call_status.text = "Call ended. Call again any time%s." % (
				(": " + _support_number) if _support_number != "" else "")
		_:
			if not _link_up:
				call_status.text = "Support line not linked. Set FRACTAL_SERVER_URL and GAME_LINK_TOKEN (server/.env) and restart."
			elif _support_number != "":
				call_status.text = "CALL %s FOR ASSISTANCE" % _support_number
			else:
				call_status.text = "Support line ready. Call your support number for assistance."


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
