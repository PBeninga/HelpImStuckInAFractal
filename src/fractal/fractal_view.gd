class_name FractalView
extends Control
## Renders the fractal in a SubViewport and displays it full-window. Also owns
## the ray maths (project/unproject) so the Julia marker and orbit camera agree
## with the shader exactly.
##
## `size` (and so project/unproject) is in logical units; the SubViewport is in
## physical pixels: size * render_scale * the window's content scale (UiScale),
## so the still frame is sharp on a HiDPI screen.

const TAN_HALF_FOV := 0.36397023426620234  # tan(20 degrees), half of a 40 deg vertical FOV

## A noise rebuild failed to compile, or recovered. "" means all clear. The panel
## shows the message on its status line; the console gets it too.
signal noise_status(text: String)

var render_scale := 1.0
var continuous := false
## The governor's load-shed level (0 = full quality); see set_load_level().
var load_level := 0

var _params: FractalParams
var _camera: CameraState
var _viewport: SubViewport
var _rect: ColorRect
var _display: TextureRect
var _material: ShaderMaterial
var _pending_size := Vector2i(1280, 800)

## The original mandelbox shader (with its inert NOISE stub) and its source. When
## nothing is wired to the field's Output, this exact resource is used again, so
## the picture and cost are identical to having no editor at all.
var _base_shader: Shader
var _base_code := ""
var _noise_graph: NoiseGraph
var _shed: Dictionary = LoadShedder.settings(0)


func _ready() -> void:
	_viewport = $SubViewport
	_rect = $SubViewport/ColorRect
	_display = $Display
	_material = _rect.material as ShaderMaterial
	_capture_base()
	_display.texture = _viewport.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	# The view covers the window, so if it took mouse events the GUI would eat
	# every click and every captured mouse-look motion before Main saw them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_apply_size)
	# A content-scale change resizes the window's viewport without necessarily
	# resizing this Control; the pixel size still has to follow.
	get_viewport().size_changed.connect(_apply_size)
	_apply_size()
	# setup() may have run before _ready wired the material (e.g. a test or the
	# screenshot pass that adds the view and calls setup() in the same frame).
	# Push whatever state is already held so the first frame is not blank.
	if _params != null:
		_push_params()
	if _camera != null:
		_push_camera()
	if _noise_graph != null:
		_rebuild_noise()
	request_frame()


func setup(params: FractalParams, camera: CameraState) -> void:
	_params = params
	_camera = camera
	if not params.changed.is_connected(_on_params_changed):
		params.changed.connect(_on_params_changed)
	if not camera.changed.is_connected(_on_camera_changed):
		camera.changed.connect(_on_camera_changed)
	_push_params()
	_push_camera()
	request_frame()


## Show a noise field on the fractal. The view listens to the graph: a structural
## change or a baked (INT/BOOL/ENUM) parameter edit rebuilds the shader; a live
## (FLOAT, or the tint colour) edit only pushes its uniform. Passing null, or a
## graph with nothing wired to its Output, restores the base shader exactly.
func set_noise_graph(graph: NoiseGraph) -> void:
	if _noise_graph != null:
		if _noise_graph.changed.is_connected(_on_noise_changed):
			_noise_graph.changed.disconnect(_on_noise_changed)
		if _noise_graph.node_changed.is_connected(_on_noise_node_changed):
			_noise_graph.node_changed.disconnect(_on_noise_node_changed)
	_noise_graph = graph
	if _noise_graph != null:
		_noise_graph.changed.connect(_on_noise_changed)
		_noise_graph.node_changed.connect(_on_noise_node_changed)
	_rebuild_noise()


func noise_graph() -> NoiseGraph:
	return _noise_graph


func _capture_base() -> void:
	if _base_shader == null and _material != null and _material.shader != null:
		_base_shader = _material.shader
		_base_code = _base_shader.code


func _on_noise_changed() -> void:
	_rebuild_noise()


func _on_noise_node_changed(id: StringName, param_id: StringName) -> void:
	if _noise_graph != null and NoiseCompiler.is_live_param(_noise_graph, id, param_id):
		_push_noise()
		request_frame()
	else:
		_rebuild_noise()


## Compile the graph, swap the material's shader, and re-push every uniform. On a
## compile failure the old shader stays and the failure is reported.
func _rebuild_noise() -> void:
	_capture_base()
	if _material == null or _base_shader == null:
		return
	if _noise_graph == null:
		_material.shader = _base_shader
		_repush_all()
		return
	var result := NoiseCompiler.compile(_noise_graph)
	if not result["errors"].is_empty():
		var msg := "Noise: " + "; ".join(result["errors"])
		push_warning(msg)
		noise_status.emit(msg)
		return
	if (result["uniforms"] as Array).is_empty():
		_material.shader = _base_shader
	else:
		var sh := Shader.new()
		sh.code = NoiseCompiler.splice(_base_code, result["code"])
		if sh.get_shader_uniform_list().is_empty():
			var msg := "Noise: new shader failed to compile; kept the previous one"
			push_error(msg)
			noise_status.emit(msg)
			return
		_material.shader = sh
	noise_status.emit("")
	_repush_all()


func _repush_all() -> void:
	_push_params()
	_push_camera()
	if _material != null:
		_material.set_shader_parameter("aspect", _aspect())
	_push_noise()
	request_frame()


func _push_noise() -> void:
	if _material == null or _noise_graph == null:
		return
	var values := NoiseCompiler.live_values(_noise_graph)
	for name in values:
		_material.set_shader_parameter(name, values[name])


func shader_uniform_names() -> Array:
	var out: Array = []
	if _material and _material.shader:
		for u in _material.shader.get_shader_uniform_list():
			out.append(u["name"])
	return out


func viewport_size() -> Vector2i:
	if _viewport == null:
		return Vector2i.ZERO
	return _viewport.size


## The last frame the view rendered, at its current render scale (full scale
## once the governor has settled). null before _ready.
func capture() -> Image:
	if _viewport == null:
		return null
	return _viewport.get_texture().get_image()


func set_render_scale(s: float) -> void:
	render_scale = clampf(s, FractalParams.RENDER_SCALE_FLOOR, 1.0)
	_apply_size()


## Render at a LoadShedder level: its fog, and its detail and step-budget
## factors on top of the view's own. Level 0 is exactly the view's settings.
func set_load_level(level: int) -> void:
	level = clampi(level, 0, LoadShedder.top())
	if level == load_level:
		return
	load_level = level
	_shed = LoadShedder.settings(level)
	_push_params()


func request_frame() -> void:
	if _viewport == null:
		return  # setup() may run before _ready wires the SubViewport
	if continuous:
		return  # never downgrade UPDATE_ALWAYS to UPDATE_ONCE mid-motion
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_continuous(on: bool) -> void:
	continuous = on
	if _viewport == null:
		return
	_viewport.render_target_update_mode = \
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Returns the window pixel of `point`, or null when it is behind the camera.
func project(point: Vector3) -> Variant:
	var rel := point - _camera.eye()
	var z_c := rel.dot(_camera.forward())
	if z_c <= 0.0:
		return null
	var x_c := rel.dot(_camera.right())
	var y_c := rel.dot(_camera.up())
	var a := _aspect()
	var ndc_x := (x_c / z_c) / (a * TAN_HALF_FOV)
	var ndc_y := (y_c / z_c) / TAN_HALF_FOV
	var uv := Vector2(ndc_x * 0.5 + 0.5, 0.5 - ndc_y * 0.5)
	return uv * size


## The world point at camera-forward depth `depth` under window `pixel`.
func unproject(pixel: Vector2, depth: float) -> Vector3:
	var uv := pixel / size
	var ndc_x := (uv.x - 0.5) * 2.0
	var ndc_y := -(uv.y - 0.5) * 2.0
	var a := _aspect()
	var d := _camera.forward() \
		+ ndc_x * a * TAN_HALF_FOV * _camera.right() \
		+ ndc_y * TAN_HALF_FOV * _camera.up()
	return _camera.eye() + d * depth


func _aspect() -> float:
	return size.x / maxf(size.y, 1.0)


## Size the SubViewport in physical pixels. A new size reallocates its target,
## so it also requests a frame: with UPDATE_ONCE already consumed, a window
## resize used to leave the view black until something moved.
func _apply_size() -> void:
	if _viewport == null:
		return  # setup()/set_render_scale() may run before _ready
	var s := render_scale * _content_scale()
	var px := Vector2i(maxi(1, int(round(size.x * s))), maxi(1, int(round(size.y * s))))
	if _material:
		_material.set_shader_parameter("aspect", _aspect())
	if px == _viewport.size:
		return
	_viewport.size = px
	_rect.size = Vector2(px)
	request_frame()


## Physical pixels per logical unit where the view is drawn: its window's
## content scale, 1 inside a SubViewport or out of the tree.
func _content_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var win := get_viewport() as Window
	return win.content_scale_factor if win != null else 1.0


func _on_params_changed() -> void:
	_push_params()
	request_frame()


func _on_camera_changed() -> void:
	_push_camera()
	request_frame()


func _push_params() -> void:
	if _material == null or _params == null:
		return
	_material.set_shader_parameter("box_scale", _params.box_scale)
	_material.set_shader_parameter("fold_limit", _params.fold_limit)
	_material.set_shader_parameter("min_radius", _params.min_radius)
	_material.set_shader_parameter("fixed_radius", _params.fixed_radius)
	_material.set_shader_parameter("fold_order", _params.fold_order)
	_material.set_shader_parameter("w", _params.w)
	_material.set_shader_parameter("julia_all", _params.julia_all)
	_material.set_shader_parameter("julia_0", _params.julia_0)
	_material.set_shader_parameter("julia_1", _params.julia_1)
	_material.set_shader_parameter("julia_2", _params.julia_2)
	_material.set_shader_parameter("julia_3", _params.julia_3)
	_material.set_shader_parameter("c_0", _params.c_0)
	_material.set_shader_parameter("c_1", _params.c_1)
	_material.set_shader_parameter("c_2", _params.c_2)
	_material.set_shader_parameter("c_3", _params.c_3)
	_material.set_shader_parameter("iter_rot_xy", _params.iter_rot_xy)
	_material.set_shader_parameter("iter_rot_xz", _params.iter_rot_xz)
	_material.set_shader_parameter("iter_rot_xw", _params.iter_rot_xw)
	_material.set_shader_parameter("iter_rot_yz", _params.iter_rot_yz)
	_material.set_shader_parameter("iter_rot_yw", _params.iter_rot_yw)
	_material.set_shader_parameter("iter_rot_zw", _params.iter_rot_zw)
	_material.set_shader_parameter("precision", _params.precision / (_params.detail * _shed["detail"]))
	_material.set_shader_parameter("color_mode", _params.color_mode)
	_material.set_shader_parameter("tan_half_fov", TAN_HALF_FOV)
	_material.set_shader_parameter("box_half", 20.0 if _params.julia_enabled() else 2.0)
	_material.set_shader_parameter("detail_range", _params.detail_range)
	_material.set_shader_parameter("detail_falloff", _params.detail_falloff)
	var budget := maxi(FractalParams.MAX_STEPS_MIN, int(round(_params.max_steps * _shed["steps"])))
	_material.set_shader_parameter("coarse_steps", _params.coarse_steps(budget))
	_material.set_shader_parameter("fine_steps", _params.fine_steps(budget))
	_material.set_shader_parameter("fog_dist", _shed["fog"])
	_material.set_shader_parameter("fog_color", _params.fog_color())
	_push_near()


func _push_camera() -> void:
	if _material == null or _camera == null:
		return
	_material.set_shader_parameter("eye", _camera.eye())
	_material.set_shader_parameter("cam_right", _camera.right())
	_material.set_shader_parameter("cam_up", _camera.up())
	_material.set_shader_parameter("cam_forward", _camera.forward())
	_push_near()


## The camera's distance to the nearest surface, which the level-of-detail range
## is measured in. It depends on both the camera and the shape, so both pushes
## refresh it.
func _push_near() -> void:
	if _material == null or _params == null or _camera == null:
		return
	var near := maxf(DistanceEstimator.estimate(_camera.eye(), _params), FractalParams.NEAR_FLOOR)
	_material.set_shader_parameter("near_dist", near)
