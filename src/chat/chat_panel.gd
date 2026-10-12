class_name ChatPanel
extends Control
## The pilot chat: a translucent column at the upper-right of the view with the
## conversation, the agent's state and an input line. Enter focuses the input
## (WASD and the axis keys fall silent while it has focus, through TextFocus);
## Enter sends, Escape or a click on the view leaves it. Clicks and drags
## anywhere else in the column go through to the view.

const WIDTH := 360.0
const MARGIN := 16.0
## The 256 px diagnostics square, its gap, and bottom margin.
const LOWER_RIGHT_RESERVE := 284.0
const FONT_SIZE := 15
const FrostedGlass := preload("res://src/ui/frosted_glass.gd")

const BG := Color(0.025, 0.14, 0.06, 0.68)
const PANEL_EDGE := Color(0.22, 0.82, 0.38, 0.68)
const HUMAN_BG := Color(0.08, 0.34, 0.15, 0.46)
const AGENT_BG := Color(0.04, 0.18, 0.09, 0.50)
const NAME_HUMAN := Color(0.65, 0.95, 0.70)
const NAME_AGENT := Color(0.42, 1.0, 0.52)
const SYSTEM_TEXT := Color(0.67, 0.82, 0.70, 0.9)
const STATE_TEXT := {
	ChatLog.AgentState.OFFLINE: ["○  no agent listening", Color(0.6, 0.6, 0.65)],
	ChatLog.AgentState.LISTENING: ["●  agent listening", Color(0.45, 0.95, 0.55)],
	ChatLog.AgentState.WORKING: ["●  agent working…", Color(1.0, 0.78, 0.30)],
}

var input: LineEdit
var log_box: VBoxContainer

var _log: ChatLog
var _scroll: ScrollContainer
var _state: Label
var _agent_button: Button


func setup(chat_log: ChatLog) -> void:
	_log = chat_log
	_build()
	for m in _log.messages:
		_append(m)
	_log.message_added.connect(_on_message)
	_log.cleared.connect(_on_cleared)
	_log.state_changed.connect(_show_state)
	_log.draft_changed.connect(_on_draft)
	_show_state()


func _exit_tree() -> void:
	# The log outlives this panel (it belongs to the bridge).
	if _log == null:
		return
	for pair in [[_log.message_added, _on_message], [_log.cleared, _on_cleared],
			[_log.state_changed, _show_state], [_log.draft_changed, _on_draft]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if _log.chat_agent_state != "off":
		_log.chat_agent_requested.emit("stop")


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	set_right_inset(0.0)
	offset_top = MARGIN
	offset_bottom = -LOWER_RIGHT_RESERVE

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _box(BG, 12, 12, PANEL_EDGE))
	FrostedGlass.apply(panel)
	add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_theme_constant_override("separation", 8)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray([
		"DejaVu Sans Mono", "Menlo", "Consolas", "Liberation Mono", "monospace",
	])
	col.add_theme_font_override("font", mono)
	panel.add_child(col)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("Pilot", FONT_SIZE + 2, Color(0.78, 1.0, 0.82, 0.96))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_state = _label("", FONT_SIZE - 2, Color.WHITE)
	header.add_child(_state)
	col.add_child(header)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.get_v_scroll_bar().modulate.a = 0.4
	col.add_child(_scroll)
	log_box = VBoxContainer.new()
	log_box.mouse_filter = Control.MOUSE_FILTER_PASS
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	log_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(log_box)

	var agent_row := HBoxContainer.new()
	_agent_button = Button.new()
	_agent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_agent_button.pressed.connect(func():
		_log.chat_agent_requested.emit("start" if _log.chat_agent_state == "off" else "stop"))
	agent_row.add_child(_agent_button)
	col.add_child(agent_row)

	input = LineEdit.new()
	input.placeholder_text = "Enter to talk to the pilot…"
	input.add_theme_font_size_override("font_size", FONT_SIZE)
	input.add_theme_font_override("font", mono)
	input.add_theme_stylebox_override(
		"normal", _box(Color(0.01, 0.08, 0.035, 0.72), 8, 8, Color(0.18, 0.52, 0.25, 0.5)))
	input.add_theme_stylebox_override(
		"focus", _box(Color(0.015, 0.11, 0.045, 0.84), 8, 8, Color(0.42, 1.0, 0.52, 0.9)))
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	col.add_child(input)


## Keep `inset` clear at the window's right edge (the docked console's strip),
## so the panel sits beside it rather than under it.
func set_right_inset(inset: float) -> void:
	offset_left = -WIDTH - MARGIN - inset
	offset_right = -MARGIN - inset


## Focus the input (Enter), from wherever the keyboard was.
func focus_input() -> void:
	input.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"chat_focus") and not input.has_focus():
		focus_input()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# A click anywhere but the input leaves it, so WASD flies again.
	if input.has_focus() and event is InputEventMouseButton and event.pressed \
			and not input.get_global_rect().has_point(event.position):
		input.release_focus()


func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		input.release_focus()
		input.accept_event()


func _on_submit(text: String) -> void:
	if _log.chat_agent_state == "connecting":
		return
	text = text.strip_edges()
	input.clear()
	input.release_focus()
	if not text.is_empty():
		_log.add("human", text, "typed")


func _on_message(m: Dictionary) -> void:
	_append(m)


func _on_cleared() -> void:
	for c in log_box.get_children():
		c.queue_free()


func _on_draft(text: String) -> void:
	input.text = text
	input.caret_column = text.length()


func _show_state() -> void:
	var s: Array = STATE_TEXT[_log.agent_state()]
	_state.text = s[0]
	_state.add_theme_color_override("font_color", s[1])
	_agent_button.text = "Start text agent"
	if _log.chat_agent_state == "connecting":
		_agent_button.text = "Connecting… Cancel"
	elif _log.chat_agent_state == "ready":
		_agent_button.text = "End text agent"
	_agent_button.disabled = not _log.chat_agent_available and _log.chat_agent_state == "off"
	_agent_button.tooltip_text = "Test the support agent and its ship tools in text mode" if _log.chat_agent_available else "Connect a server with OPENAI_API_KEY to enable text mode"
	input.editable = _log.chat_agent_state != "connecting"
	input.placeholder_text = "Connecting to support…" if not input.editable else "Enter to talk to the pilot…"


func _append(m: Dictionary) -> void:
	var role: String = m["role"]
	var row: Control
	if role == "system":
		var l := _label(m["text"], FONT_SIZE - 2, SYSTEM_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row = l
	else:
		var human := role == "human"
		var bubble := PanelContainer.new()
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.add_theme_stylebox_override("panel", _box(HUMAN_BG if human else AGENT_BG, 10, 8))
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 2)
		var who := "You" if human else "Pilot"
		if m.get("source", "") == "voice":
			who += "  (voice)"
		elif not human and m.get("source", "") == "phone":
			who = "Support  (phone)"   # the call centre's voice agent, said on the call
		elif not human and m.get("source", "") == "chatbox":
			who = "Support  (text)"
		stack.add_child(_label(who, FONT_SIZE - 3, NAME_HUMAN if human else NAME_AGENT))
		stack.add_child(_label(m["text"], FONT_SIZE, Color(1, 1, 1, 0.95)))
		bubble.add_child(stack)
		row = bubble
	row.set_meta(&"message_id", m["id"])
	log_box.add_child(row)
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	return l


static func _box(color: Color, radius: int, pad: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(1)
	return b
