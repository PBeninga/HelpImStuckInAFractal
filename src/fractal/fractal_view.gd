class_name FractalView
extends Control
## Renders the scene of shapes in a SubViewport and displays it full-window.
## Also owns the ray maths (project/unproject) so the Julia marker and orbit
## camera agree with the shader exactly. Every per-shape knob goes to the shader
## as an array indexed by shape; each shape's frame (the eye in its local
## coordinates, its axes) is computed here in 64-bit; the scene's look knobs go
## as the scalar uniforms they always were.
##
## `size` (and so project/unproject) is in logical units; the SubViewport is in
## physical pixels: size * render_scale * the window's content scale (UiScale),
## so the still frame is sharp on a HiDPI screen.

const TAN_HALF_FOV := 0.36397023426620234  # tan(20 degrees), half of a 40 deg vertical FOV
## The probe dot's radius as a fraction of its distance: about 5 px across the
## 800 px-high view's 40 deg field, whatever the distance.
const PROBE_ANGULAR_RADIUS := 0.005
## Frames a level drop takes to ease in, instead of popping to full quality:
## the shed fog recedes to the full view distance, and the detail and step
## budget climb back to the level's. A shed is never eased: that is the governor
## buying frame time back now.
const RESTORE_FRAMES := 18
## The per-shape uniform ids that travel as PackedInt32Array (enums and the
## bool toggles); every other shader id is a PackedFloat32Array.
const INT_IDS: Array[StringName] = [
	&"shape", &"fold_order", &"fold_shape", &"hybrid_every", &"kifs_fold",
	&"julia_all", &"julia_0", &"julia_1", &"julia_2", &"julia_3", &"mandelbulb_julia",
]

## A noise rebuild failed to compile, or recovered. "" means all clear. The panel
## shows the message on its status line; the console gets it too.
signal noise_status(text: String)

var render_scale := 1.0
## Paint the centre-ray probe's dot on the surface (see CenterRay).
var show_probe := false:
	set(v):
		if v == show_probe:
			return
		show_probe = v
		_push_probe()
		request_frame()
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
# What is on screen, which trails _shed while a restore eases in. The fog is an
# inverse distance (1 / fog_dist, 0 = none) so a fog on its way out recedes
# towards infinity in even steps; a fog leaving entirely also thins
# (_fog_clear 0 -> 1) as it recedes. _detail and _steps are the shed factors on
# the detail and the step budget.
var _fog_inv := 0.0
var _fog_clear := 0.0
var _detail := 1.0
var _steps := 1.0
var _from := {}                       # the on-screen values the restore started from
var _restore_frame := RESTORE_FRAMES  # frames into the restore tween; done at RESTORE_FRAMES
var _restore_stepped_on := -1         # the process frame the tween last stepped on
var _center_ray: CenterRay


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
		_push_probe()
	if _noise_graph != null:
		_rebuild_noise()
	request_frame()


func setup(params: FractalParams, camera: CameraState) -> void:
	if _center_ray == null or params != _params or camera != _camera:
		# Made before the view connects its own handlers, so the ray has heard
		# of a change before the view asks it where the dot goes.
		_center_ray = CenterRay.new(params, camera)
	_params = params
	_camera = camera
	if not params.changed.is_connected(_on_params_changed):
		params.changed.connect(_on_params_changed)
	if not camera.changed.is_connected(_on_camera_changed):
		camera.changed.connect(_on_camera_changed)
	_push_params()
	_push_camera()
	_push_probe()
	request_frame()


## The ray through the middle of the screen, shared with the fly camera so the
## speed and the dot come from one march. null before setup().
func center_ray() -> CenterRay:
	return _center_ray


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
	_push_probe()
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
	var shedding := level > load_level
	load_level = level
	_shed = LoadShedder.settings(level)
	if shedding:
		_fog_inv = _fog_target()
		_fog_clear = 0.0
		_detail = _shed["detail"]
		_steps = _shed["steps"]
		_restore_frame = RESTORE_FRAMES
	else:
		_from = {"fog_inv": _fog_inv, "detail": _detail, "steps": _steps}
		_restore_frame = 0
		_step_restore()
	_push_params()


## True while a level drop is still easing in.
func restoring() -> bool:
	return _restore_frame < RESTORE_FRAMES


func _process(_delta: float) -> void:
	if restoring() and _restore_stepped_on != Engine.get_process_frames():
		_step_restore()
		_push_shed()
		request_frame()


func _fog_target() -> float:
	var fog: float = _shed["fog"]
	return 1.0 / fog if fog > 0.0 else 0.0


## One frame of the restore tween: the fog recedes towards the target level's
## (thinning on the way when the target is none) while the detail and step
## budget climb towards it.
func _step_restore() -> void:
	_restore_frame += 1
	_restore_stepped_on = Engine.get_process_frames()
	var t := float(_restore_frame) / RESTORE_FRAMES
	var target := _fog_target()
	_fog_inv = lerpf(_from["fog_inv"], target, t)
	_fog_clear = t if target == 0.0 and t < 1.0 else 0.0
	_detail = lerpf(_from["detail"], _shed["detail"], t)
	_steps = lerpf(_from["steps"], _shed["steps"], t)


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
	_push_probe()
	request_frame()


func _on_camera_changed() -> void:
	_push_camera()
	_push_probe()
	request_frame()


## The probe dot: on while shown and the centre ray hits, at the hit point,
## sized to stay the same on screen. Marches only while shown (the fly camera
## asks for the distance itself while it moves).
func _push_probe() -> void:
	if _material == null:
		return
	var on := show_probe and _center_ray != null and _center_ray.hit()
	_material.set_shader_parameter("probe_on", on)
	if on:
		_material.set_shader_parameter("probe_point", _center_ray.point())
		_material.set_shader_parameter("probe_radius",
			maxf(_center_ray.distance() * PROBE_ANGULAR_RADIUS, 1e-12))


func _push_params() -> void:
	if _material == null or _params == null:
		return
	_material.set_shader_parameter("exit_radius", _params.gameplay.exit_radius)
	_material.set_shader_parameter("exit_has_skybox", _params.gameplay.exit_skybox != null)
	_material.set_shader_parameter("exit_skybox", _params.gameplay.exit_skybox)
	# Every scene id is a scalar uniform of the same name, pushed as it is; the
	# COLOR keys go as a vec3 (the shader's colour uniforms).
	for key in FractalParams.RESOLVED_KEYS:
		if FractalParams.COLOR_KEYS.has(key):
			var c: Color = _params.get(key)
			_material.set_shader_parameter(key, Vector3(c.r, c.g, c.b))
		else:
			_material.set_shader_parameter(key, _params.get(key))
	# Every per-shape shader id is an array of MAX_SHAPES entries, filled from
	# params.shapes in order and padded with zeros (the precision folds in the
	# detail and the load shedder's factor, in _push_shed).
	var n := FractalParams.MAX_SHAPES
	var floats := {}
	var ints := {}
	for id in ShapeCatalogue.shader_ids():
		if id == &"precision":
			continue
		if INT_IDS.has(id):
			var a := PackedInt32Array()
			a.resize(n)
			ints[id] = a
		else:
			var f := PackedFloat32Array()
			f.resize(n)
			floats[id] = f
	var sizes := PackedFloat32Array()
	sizes.resize(n)
	var halves := PackedFloat32Array()
	halves.resize(n)
	for i in _params.shapes.size():
		var sh := _params.shapes[i]
		for id in floats:
			floats[id][i] = sh.get(id)
		for id in ints:
			ints[id][i] = int(sh.get(id))
		sizes[i] = sh.size
		halves[i] = sh.bound_half()
	for id in floats:
		_material.set_shader_parameter(id, floats[id])
	for id in ints:
		_material.set_shader_parameter(id, ints[id])
	_material.set_shader_parameter("shape_size", sizes)
	_material.set_shader_parameter("box_half", halves)
	_material.set_shader_parameter("shape_count", _params.shapes.size())
	_material.set_shader_parameter("view_limit", _params.scene_view_distance())
	_material.set_shader_parameter("tan_half_fov", TAN_HALF_FOV)
	_material.set_shader_parameter("fractal_iterations", _params.fractal_iterations)
	_material.set_shader_parameter("detail_range", _params.detail_range)
	_material.set_shader_parameter("detail_falloff", _params.detail_falloff)
	_push_shed()
	_push_near()


## The values the load-shed level (or a restore easing in) bends: the precision
## (per shape), the step budget and the fog.
func _push_shed() -> void:
	if _material == null or _params == null:
		return
	var precisions := PackedFloat32Array()
	precisions.resize(FractalParams.MAX_SHAPES)
	for i in _params.shapes.size():
		precisions[i] = _params.shapes[i].precision / (_params.detail * _detail)
	_material.set_shader_parameter("precision", precisions)
	var budget := maxi(FractalParams.MAX_STEPS_MIN, int(round(_params.max_steps * _steps)))
	_material.set_shader_parameter("coarse_steps", _params.coarse_steps(budget))
	_material.set_shader_parameter("fine_steps", _params.fine_steps(budget))
	_material.set_shader_parameter("fog_dist", 1.0 / _fog_inv if _fog_inv > 0.0 else 0.0)
	_material.set_shader_parameter("fog_clear", _fog_clear)
	_material.set_shader_parameter("fog_color", _params.fog_color())
	# The self-shadow march's budget, shed with the ladder (full 48 at level 0;
	# it steps with the level rather than easing, since it is a step count).
	_material.set_shader_parameter("shadow_steps", int(round(FractalParams.SHADOW_STEPS * _shed["shadow"])))


func _push_camera() -> void:
	if _material == null or _camera == null:
		return
	_material.set_shader_parameter("eye", _camera.eye())
	_material.set_shader_parameter("cam_right", _camera.right())
	_material.set_shader_parameter("cam_up", _camera.up())
	_material.set_shader_parameter("cam_forward", _camera.forward())
	_push_near()


## Every shape's frame as the shader wants it — the eye mapped into the frame
## (Rᵀ (eye − position) / size, in 64-bit, so a small shape far from the
## origin keeps its precision) and the frame's axes in world space — along with
## the camera's distance to the nearest surface (of any shape), which the
## level-of-detail range is measured in, and the coarse pass's iteration count
## per shape and the shading crossfade that follow from it. The distance is
## estimated at the 64-bit eye. These depend on both the camera and the shapes,
## so both pushes refresh them.
func _push_near() -> void:
	if _material == null or _params == null or _camera == null:
		return
	var n := FractalParams.MAX_SHAPES
	var eyes := PackedVector3Array()
	eyes.resize(n)
	var fx := PackedVector3Array()
	fx.resize(n)
	var fy := PackedVector3Array()
	fy.resize(n)
	var fz := PackedVector3Array()
	fz.resize(n)
	var iters := PackedInt32Array()
	iters.resize(n)
	var ex := _camera.eye_x()
	var ey := _camera.eye_y()
	var ez := _camera.eye_z()
	var near := maxf(DistanceEstimator.scene_estimate_at(ex, ey, ez, _params), FractalParams.NEAR_FLOOR)
	for i in _params.shapes.size():
		var sh := _params.shapes[i]
		var q := sh.to_local(ex, ey, ez)
		eyes[i] = Vector3(q[0], q[1], q[2])
		var ax := sh.axes()
		fx[i] = ax[0]
		fy[i] = ax[1]
		fz[i] = ax[2]
		iters[i] = _params.coarse_iters(near, i)
	_material.set_shader_parameter("local_eye", eyes)
	_material.set_shader_parameter("frame_x", fx)
	_material.set_shader_parameter("frame_y", fy)
	_material.set_shader_parameter("frame_z", fz)
	_material.set_shader_parameter("coarse_iters", iters)
	_material.set_shader_parameter("near_dist", near)
	_material.set_shader_parameter("nf_weight", FractalParams.nf_weight(near))


## The shape the camera is nearest to (index into params.shapes).
func nearest_shape() -> int:
	if _params == null or _camera == null:
		return 0
	return DistanceEstimator.nearest_at(_camera.eye_x(), _camera.eye_y(), _camera.eye_z(), _params)["index"]
