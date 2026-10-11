class_name StoryHud
extends CanvasLayer
## The cockpit HUD over the fractal: the scrolling SHIP DIAGNOSTICS log (top
## right), ship status (top left), the SUB-DIMENSIONAL SUPPORT call panel with
## a live transcript (bottom left) and the FeatureOverlay's brackets. Drawn
## under the pause menu (layer 10) and never takes the mouse.

const LAYER := 4
const PANEL_BG := Color(0.02, 0.05, 0.1, 0.78)
const PANEL_BORDER := Color(0.35, 0.75, 1.0, 0.55)
const FLASH_BORDER := Color(1.0, 0.82, 0.3, 1.0)
const STYLE_COLORS := {
	"error": "#ff7b7b", "ok": "#7dffa8", "fail": "#ff4d4d", "pilot": "#ffd166",
	"info": "#b9cdf5", "agent": "#8fd8ff", "system": "#9aa3c7",
}
const STYLE_PREFIX := {
	"error": "", "ok": "  -> ", "fail": "!! ", "pilot": "?? ", "info": "", "agent": "AGENT> ", "system": "-- ",
}
const TRANSCRIPT_LINES := 6

var overlay: FeatureOverlay
var log_label: RichTextLabel
var status_label: Label
var call_title: Label
var call_status: Label
var transcript_label: RichTextLabel

var _panels := {}            # element name -> PanelContainer
var _root: Control
var _camera: CameraState
var _params: FractalParams
var _mission: Mission
var _ship: ShipController
var _issue_log: IssueLog
var _support_number := ""
var _link_up := false
var _call_state := "idle"
var _agent_name := ""
var _call_started := 0.0
var _clock := 0.0
var _status_wait := 0.0
var _transcript: Array[Dictionary] = []   # {item_id, role, text}
var _mono: Font
var _mono_bold: Font


func _init() -> void:
	layer = LAYER


func setup(view: FractalView, camera: CameraState, params: FractalParams,
		mission: Mission, ship: ShipController, issue_log: IssueLog) -> void:
	_camera = camera
	_params = params
	_mission = mission
	_ship = ship
	_issue_log = issue_log
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
	overlay.setup(view, camera, params)

	_build_diagnostics()
	_build_status()
	_build_call_panel()
	issue_log.entry_added.connect(_on_entry)
	ship.maneuver_started.connect(_on_maneuver_started)
	ship.maneuver_finished.connect(_on_maneuver_finished)
	set_panels_visible(false)


# ------------------------------------------------------------- building

func _panel(element: String, anchor_preset: int, at: Vector2, panel_size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.name = element
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	p.set_anchors_preset(anchor_preset)
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
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	box.add_child(t)
	return t


func _build_diagnostics() -> void:
	var box := _panel("diagnostics_log", Control.PRESET_TOP_RIGHT, Vector2(16, 16), Vector2(460, 360))
	_title(box, "SHIP DIAGNOSTICS  //  AUTO-RESOLUTION ACTIVE")
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.fit_content = false
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_font_override("normal_font", _mono)
	log_label.add_theme_font_override("bold_font", _mono_bold)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.add_theme_font_size_override("bold_font_size", 12)
	box.add_child(log_label)


func _build_status() -> void:
	var box := _panel("ship_status", Control.PRESET_TOP_LEFT, Vector2(16, 16), Vector2(330, 150))
	_title(box, "ICEBOX  //  SUB-DIMENSIONAL DRIFT")
	status_label = Label.new()
	status_label.add_theme_font_override("font", _mono)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	box.add_child(status_label)


func _build_call_panel() -> void:
	var box := _panel("call_panel", Control.PRESET_BOTTOM_LEFT, Vector2(16, 16), Vector2(600, 210))
	call_title = _title(box, "SUB-DIMENSIONAL SUPPORT")
	call_status = Label.new()
	call_status.add_theme_font_size_override("font_size", 18)
	call_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	call_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(call_status)
	transcript_label = RichTextLabel.new()
	transcript_label.bbcode_enabled = true
	transcript_label.scroll_following = true
	transcript_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transcript_label.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(transcript_label)
	_refresh_call()


# ------------------------------------------------------------- public API

func set_panels_visible(on: bool) -> void:
	for p in _panels.values():
		p.visible = on


func set_panel_visible(element: String, on: bool) -> void:
	if _panels.has(element):
		_panels[element].visible = on


func is_panel_visible(element: String) -> bool:
	return _panels.has(element) and _panels[element].visible


## Slide the panels in from the screen edges (after the intro).
func reveal() -> void:
	set_panels_visible(true)
	for element in _panels:
		var p: Control = _panels[element]
		p.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(p, "modulate:a", 1.0, 0.6)
	overlay.show_exit = true


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
		_transcript.clear()
		_render_transcript()
	_refresh_call()


func call_state() -> String:
	return _call_state


## Show (or update, by item_id) a transcript line.
func show_transcript(role: String, item_id: String, text: String, _final: bool) -> void:
	for line in _transcript:
		if item_id != "" and line["item_id"] == item_id:
			line["text"] = text
			_render_transcript()
			return
	_transcript.append({"item_id": item_id, "role": role, "text": text})
	while _transcript.size() > TRANSCRIPT_LINES:
		_transcript.pop_front()
	_render_transcript()


func highlight_feature(id: String, label: String, seconds: float) -> void:
	overlay.highlight(Route.normalize_id(id), label, seconds)


func scan_pulse(ids: Array) -> void:
	overlay.scan_pulse()
	for id in ids:
		overlay.highlight(Route.normalize_id(id), "", 8.0)


func clear_highlights() -> void:
	overlay.clear()


## Pulse a HUD panel's border (or the exit marker / reticle) to draw the eye.
func flash(element: String, _label: String = "") -> void:
	if element == "exit_marker":
		overlay.highlight(Route.EXIT_ID, _label, 8.0)
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
		tw.tween_callback(_set_border.bind(sb, PANEL_BORDER, 1))
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
		if _call_state == "connected" or (_call_state == "idle" and _link_up):
			_refresh_call()


func _on_maneuver_started(kind: String, info: Dictionary) -> void:
	if kind == "fly":
		overlay.course_target = info.get("target_id", "")


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
	if _camera == null or status_label == null:
		return
	var fwd := _camera.forward()
	var heading := fposmod(rad_to_deg(atan2(fwd.y, fwd.x)), 360.0)
	var pitch := rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0)))
	var clearance := Route.meters(DistanceEstimator.estimate(_camera.eye(), _params))
	var ap := _ship.state()
	var ap_text := "idle"
	if ap["active"]:
		ap_text = "%s %s (%.1f s)" % [ap["kind"], ("-> #" + ap["target_id"]) if ap["target_id"] != "" else "", ap["seconds_left"]]
	var exit := ShipController.relative(_camera, Route.RIFT_POS)
	var exit_range := "%d m" % exit["range_m"] if exit["range_m"] < 1000 else "%.2f km" % (exit["range_m"] / 1000.0)
	status_label.text = "\n".join([
		"CLEARANCE  %d m%s" % [clearance, "   ! PROXIMITY" if clearance < 10 else ""],
		"HEADING    %03d°   PITCH %+d°" % [int(round(heading)), int(round(pitch))],
		"AUTOPILOT  %s" % ap_text,
		"EXIT RIFT  %s, %s" % [exit_range, exit["direction"]],
		"WAYPOINTS  %d / %d    WAIVER %s" % [_mission.visited.size(), Route.waypoints().size() - 1,
			"signed" if _mission.waiver_signed else "unsigned"],
	])


func _refresh_call() -> void:
	if call_status == null:
		return
	# blink amber/white while waiting for the pilot to ring
	var waiting := _call_state == "idle" and _link_up and _support_number != ""
	var bright := not waiting or int(_clock * 2.0) % 2 == 0
	call_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if bright else Color(1, 1, 1))
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
				call_status.text = "Support line offline. Start the relay server (see server/README) to call for help."
			elif _support_number != "":
				call_status.text = "CALL %s FOR ASSISTANCE" % _support_number
			else:
				call_status.text = "Support line ready. Call your support number for assistance."


func _render_transcript() -> void:
	var lines: Array[String] = []
	for line in _transcript:
		var who := "AGENT" if line["role"] == "agent" else "YOU"
		var color := "#8fd8ff" if line["role"] == "agent" else "#ffffff"
		lines.append("[color=%s][b]%s:[/b] %s[/color]" % [color, who, _escape(line["text"])])
	transcript_label.text = "\n".join(lines)


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
