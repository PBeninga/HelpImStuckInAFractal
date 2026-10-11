class_name StoryIntro
extends CanvasLayer
## The failed jump: a hyperspace warp that accelerates, stutters (the stars
## jump backwards, the frame tears), whites out, and drops the ship into
## fractal space with the glitch fading off the picture. Any key or click skips
## to the landing. Emits `landed` when the fractal first shows and `finished`
## when the glitch has gone.

signal landed
signal finished

const LAYER := 8
const WARP_END := 3.2
const STUTTER_END := 4.8
const FLASH_END := 5.3
const GLITCH_END := 7.3

var t := 0.0
var running := false

var _warp: ColorRect
var _glitch: ColorRect
var _white: ColorRect
var _title: Label
var _sub: Label
var _warp_mat: ShaderMaterial
var _glitch_mat: ShaderMaterial
var _travel := 0.0
var _speed := 0.15
var _stutter_wait := 0.0
var _landed := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	layer = LAYER


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_warp = ColorRect.new()
	_warp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = load("res://src/story/fx/warp.gdshader")
	_warp.material = _warp_mat
	root.add_child(_warp)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	center.add_child(stack)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	stack.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.85))
	stack.add_child(_sub)

	_glitch = ColorRect.new()
	_glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = load("res://src/story/fx/glitch.gdshader")
	_glitch.material = _glitch_mat
	_glitch.visible = false
	root.add_child(_glitch)

	_white = ColorRect.new()
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.color = Color(1, 1, 1, 0)
	root.add_child(_white)
	visible = false


func start() -> void:
	t = 0.0
	_travel = 0.0
	_landed = false
	running = true
	visible = true
	_warp.visible = true
	_title.visible = true
	_sub.visible = true
	_title.text = "HYPERSPACE PUNCH JUMP ENGAGED"
	_sub.text = "Destination: Kepler-452b   ·   ETA 0.8 s   ·   press any key to skip"


## Jump straight to the landing.
func skip() -> void:
	if running and t < FLASH_END:
		t = FLASH_END


func _input(event: InputEvent) -> void:
	if not running or t >= FLASH_END:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if running:
		advance(delta)


## Step the timeline by `delta` seconds (the tests call this directly).
func advance(delta: float) -> void:
	t += delta
	_warp_mat.set_shader_parameter("aspect", _aspect())
	if t < WARP_END:
		_speed = lerpf(0.15, 1.0, t / WARP_END)
		_travel += delta * (0.25 + _speed * 1.6)
		_set_glitch(0.0)
	elif t < STUTTER_END:
		_stutter_wait -= delta
		if _stutter_wait <= 0.0:
			_stutter_wait = _rng.randf_range(0.08, 0.22)
			_travel -= _rng.randf_range(0.05, 0.3)            # the frame jumps back
			_speed = _rng.randf_range(0.2, 1.2)
			_set_glitch(_rng.randf_range(0.3, 1.0))
			var warn := ["WARNING: RECURSION DEPTH EXCEEDED", "JUMP VECTOR NOT FOUND",
				"WARNING: RECURSION DEPTH EXCEEDED", "FRAME 1 OF 1 OF 1 OF 1 OF"]
			_title.text = warn[_rng.randi_range(0, warn.size() - 1)]
			_sub.text = "Mandelbrought recurrence detected in jump vector"
			_title.visible = _rng.randf() > 0.25
		else:
			_travel += delta * 0.3
	elif t < FLASH_END:
		_white.color.a = clampf((t - STUTTER_END) / (FLASH_END - STUTTER_END), 0.0, 1.0)
		_set_glitch(0.0)
	else:
		if not _landed:
			_landed = true
			_warp.visible = false
			_title.visible = false
			_sub.visible = false
			landed.emit()
		var k := clampf((t - FLASH_END) / (GLITCH_END - FLASH_END), 0.0, 1.0)
		_white.color.a = clampf(1.0 - (t - FLASH_END) / 0.9, 0.0, 1.0)
		_set_glitch((1.0 - k) * (0.6 + 0.4 * _rng.randf()))
		if t >= GLITCH_END:
			running = false
			visible = false
			_set_glitch(0.0)
			finished.emit()
	_warp_mat.set_shader_parameter("travel", _travel)
	_warp_mat.set_shader_parameter("speed", _speed)
	_warp_mat.set_shader_parameter("flash", 0.0)


func _set_glitch(amount: float) -> void:
	_glitch.visible = amount > 0.01
	_glitch_mat.set_shader_parameter("amount", amount)
	_glitch_mat.set_shader_parameter("seed", _rng.randf() * 100.0)


func _aspect() -> float:
	var s := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 800)
	return s.x / maxf(s.y, 1.0)
