class_name PhosphorScan
extends Node
## A short raymarch target feeds an opaque strip into a retained canvas target.
## The first canvas draw multiplies the previous frame by exp(-delta / decay)
## using fixed-function alpha blending. Neither canvas draw samples its own
## target: history is only sampled later by the presentation viewport.

var output: SubViewport
var history: SubViewport
var _screen: TextureRect
var strip: TextureRect
var fade: ColorRect
var active := false
var _view: FractalView
var _next_row := 0
var _elapsed := 0.0
var _bands := 8
var _clear_pending := true
var _presentation: ShaderMaterial


func setup(view: FractalView) -> void:
	_view = view
	output = SubViewport.new()
	output.name = "PhosphorOutput"
	output.disable_3d = true
	output.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(output)
	history = SubViewport.new()
	history.name = "PhosphorHistory"
	history.disable_3d = true
	history.render_target_update_mode = SubViewport.UPDATE_DISABLED
	history.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	output.add_child(history)
	fade = ColorRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_child(fade)
	strip = TextureRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.texture = view._viewport.get_texture()
	history.add_child(strip)
	_presentation = ShaderMaterial.new()
	_presentation.shader = preload("res://src/fractal/phosphor_display.gdshader")
	_screen = TextureRect.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.texture = history.get_texture()
	_screen.material = _presentation
	output.add_child(_screen)
	RenderingServer.frame_pre_draw.connect(draw_frame)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(draw_frame):
		RenderingServer.frame_pre_draw.disconnect(draw_frame)


func _process(delta: float) -> void:
	if active:
		_elapsed += delta


func configure(enabled: bool, px: Vector2i, bands: int) -> void:
	# SubViewport clamps targets to at least 2x2. Match all quads and UV
	# maths to that actual size, including tiny windows / high band counts.
	px = Vector2i(maxi(2, px.x), maxi(2, px.y))
	var changed := active != enabled or history.size != px or _bands != bands
	_bands = bands
	if active != enabled:
		active = enabled
		if enabled:
			# Nested viewports are drawn before their parent. The history therefore
			# composites the same strip whose ray coordinates were set this frame.
			_view._viewport.reparent(history)
			_view._display.texture = output.get_texture()
		else:
			_view._viewport.reparent(_view)
			_view._display.texture = _view._viewport.get_texture()
			_view._display.material = null
			history.render_target_update_mode = SubViewport.UPDATE_DISABLED
			output.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_view._material.set_shader_parameter("scan_y_offset", 0.0)
			_view._material.set_shader_parameter("scan_y_scale", 1.0)
	if not active:
		return
	if changed:
		output.size = px
		_screen.size = Vector2(px)
		history.size = px
		fade.size = Vector2(px)
		var rows := maxi(2, ceili(float(px.y) / _bands))
		_view._viewport.size = Vector2i(px.x, rows)
		_view._rect.size = Vector2(px.x, rows)
		strip.size = Vector2(px.x, rows)
		reset_history()
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	history.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func reset_history() -> void:
	# Gameplay can reset presentation history while this optional effect is off.
	# Its unused target size must never change the full-frame ray coordinates.
	if not active:
		return
	_next_row = 0
	_clear_pending = true
	_elapsed = 0.0
	history.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# Also paint black on the first pass: independent of project clear colour.
	fade.color = Color(0, 0, 0, 1)
	_set_row(0)


## Called immediately before an actual render, rather than advancing on process
## ticks that may never draw. This also keeps a stationary camera scanning.
func draw_frame() -> void:
	if not active:
		return
	_set_row(_next_row)
	fade.color = Color(0, 0, 0, 1.0 if _clear_pending else 1.0 - exp(-_elapsed / _view._params.phosphor_decay))
	_clear_pending = false
	_elapsed = 0.0
	_presentation.set_shader_parameter("glow", _view._params.phosphor_glow)
	_presentation.set_shader_parameter("output_height", float(history.size.y))
	_next_row += _view._viewport.size.y
	if _next_row >= history.size.y:
		_next_row = 0


func _set_row(row: int) -> void:
	strip.position = Vector2(0, row)
	var height := float(history.size.y)
	var rows := float(_view._viewport.size.y)
	_view._material.set_shader_parameter("scan_y_offset", row / height)
	_view._material.set_shader_parameter("scan_y_scale", rows / height)
	_presentation.set_shader_parameter("scan_center", (row + rows * 0.5) / height)
	_presentation.set_shader_parameter("scan_width", rows / height)
