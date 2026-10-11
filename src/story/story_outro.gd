class_name StoryOutro
extends CanvasLayer
## The way out: a white-out as the ship enters the rift, the hyperspace warp
## resuming, then an end card with the stats of the ordeal and two buttons:
## Back to Menu, or Keep Exploring (fly the fractal freely from outside).

signal back_to_menu_requested
signal keep_exploring_requested

const LAYER := 9
const FLASH_IN := 0.6
const WARP_END := 3.4
const FLASH_OUT := 4.0

var t := 0.0
var running := false
var back_button: Button
var explore_button: Button

var _warp: ColorRect
var _warp_mat: ShaderMaterial
var _white: ColorRect
var _title: Label
var _card: PanelContainer
var _stats: Label
var _card_shown := false


func _init() -> void:
	layer = LAYER


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_warp = ColorRect.new()
	_warp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = load("res://src/story/fx/warp.gdshader")
	_warp_mat.set_shader_parameter("tint", Vector3(1.0, 0.75, 1.0))
	_warp.material = _warp_mat
	root.add_child(_warp)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.text = "PUNCH JUMP RESUMED"
	center.add_child(_title)

	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.09, 0.94)
	sb.border_color = Color(0.45, 0.95, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	_card.add_theme_stylebox_override("panel", sb)
	var card_center := CenterContainer.new()
	card_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(card_center)
	card_center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_card.add_child(box)
	var head := Label.new()
	head.text = "WELCOME BACK TO ORDINARY SPACE"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", Color(0.6, 0.97, 1.0))
	box.add_child(head)
	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 17)
	box.add_child(_stats)
	var thanks := Label.new()
	thanks.text = "Thank you for calling Sub-Dimensional Support.\nPlease stay on the line to rate your agent from 1 to 5 fractal dimensions."
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
	box.add_child(thanks)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	explore_button = MenuButtons.make("Keep Exploring")
	back_button = MenuButtons.make("Back to Menu")
	row.add_child(explore_button)
	row.add_child(back_button)
	explore_button.pressed.connect(func(): keep_exploring_requested.emit())
	back_button.pressed.connect(func(): back_to_menu_requested.emit())
	_card.visible = false
	_white = ColorRect.new()
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.color = Color(1, 1, 1, 0)
	root.add_child(_white)
	visible = false


## Run the egress, then show `stats` (lines of text) on the card.
func start(stats: Array) -> void:
	_stats.text = "\n".join(stats)
	t = 0.0
	running = true
	visible = true
	_card_shown = false
	_card.visible = false
	_warp.visible = false
	_title.visible = false


func hide_card() -> void:
	_card.visible = false
	visible = false
	running = false


func card_visible() -> bool:
	return visible and _card.visible


func _process(delta: float) -> void:
	if running:
		advance(delta)


func advance(delta: float) -> void:
	t += delta
	if t < FLASH_IN:
		_white.color.a = t / FLASH_IN
	elif t < WARP_END:
		_warp.visible = true
		_title.visible = true
		_white.color.a = clampf(1.0 - (t - FLASH_IN) / 0.5, 0.0, 1.0)
		var k := (t - FLASH_IN) / (WARP_END - FLASH_IN)
		_warp_mat.set_shader_parameter("speed", lerpf(1.2, 0.3, k))
		_warp_mat.set_shader_parameter("travel", t * 1.4)
		_warp_mat.set_shader_parameter("aspect", _aspect())
	elif t < FLASH_OUT:
		_white.color.a = (t - WARP_END) / (FLASH_OUT - WARP_END)
	elif not _card_shown:
		_card_shown = true
		_warp.visible = false
		_title.visible = false
		_card.visible = true
		var tw := create_tween()
		tw.tween_property(_white, "color:a", 0.0, 0.8)
		explore_button.grab_focus.call_deferred()
		running = false


func _aspect() -> float:
	var s := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 800)
	return s.x / maxf(s.y, 1.0)
