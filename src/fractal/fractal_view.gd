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

const DepthScan := preload("res://src/mcp/screen_depth_scan.gd")

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
signal escape_changed(escaped: bool)

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
var _paint_viewport: SubViewport
var _paint_rect: TextureRect
var _brush_material: ShaderMaterial
var _phosphor: PhosphorScan
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
var _depth_scan: Node
var _escaped := false
var _escape_elapsed := 0.0


func _ready() -> void:
	_viewport = $SubViewport
	var performance_menu := get_node_or_null("/root/PerformanceMenu")
	if performance_menu != null:
		performance_menu.watch_viewport(_viewport)
	_rect = $SubViewport/ColorRect
	_display = $Display
	_material = _rect.material as ShaderMaterial
	# Each view owns its ray coordinates and scan uniforms.
	_material = _material.duplicate()
	_rect.material = _material
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
	_phosphor = PhosphorScan.new()
	add_child(_phosphor)
	_phosphor.setup(self)
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
	_setup_depth_scan()
	request_frame()


func setup(params: FractalParams, camera: CameraState) -> void:
	if _depth_scan != null and (params != _params or camera != _camera):
		_depth_scan.free()
		_depth_scan = null
	if _center_ray == null or params != _params or camera != _camera:
		# Made before the view connects its own handlers, so the ray has heard
		# of a change before the view asks it where the dot goes.
		_center_ray = CenterRay.new(params, camera)
	_escape_elapsed = 0.0
	_params = params
	_camera = camera
	_apply_size()
	if _phosphor != null and _phosphor.active:
		_phosphor.reset_history()
	if not params.changed.is_connected(_on_params_changed):
		params.changed.connect(_on_params_changed)
	if not camera.changed.is_connected(_on_camera_changed):
		camera.changed.connect(_on_camera_changed)
	_push_params()
	_push_camera()
	_push_probe()
	_setup_depth_scan()
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
	var started := FrameProfiler.begin()
	_rebuild_noise_impl()
	FrameProfiler.end(&"Noise shader rebuild", started)


func _rebuild_noise_impl() -> void:
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
	if _phosphor != null and _phosphor.active:
		_phosphor.reset_history()
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
	return _pending_size


## The last presented frame: the full-resolution painted target when enabled,
## otherwise the ray target at its current scale. null before _ready.
func capture() -> Image:
	if _viewport == null:
		return null
	return _display.texture.get_image()


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
	request_frame()


## True while a level drop is still easing in.
func restoring() -> bool:
	return _restore_frame < RESTORE_FRAMES


func _process(delta: float) -> void:
	if _escaped and _params != null:
		var game := _params.gameplay
		var duration := maxf(maxf(game.escape_sky_duration, game.escape_fog_duration),
			maxf(game.escape_ground_duration, game.escape_fractal_duration))
		if _escape_elapsed < duration:
			_escape_elapsed = minf(_escape_elapsed + delta, duration)
			_push_escape()
			request_frame()
		# Grass wind remains animated after the transitions have completed.
		else:
			request_frame(false)
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


func request_frame(invalidate_depth := true) -> void:
	if invalidate_depth and _depth_scan != null:
		_depth_scan.invalidate()
	if _viewport == null:
		return  # setup() may run before _ready wires the SubViewport
	if continuous or (_phosphor != null and _phosphor.active):
		return  # never downgrade UPDATE_ALWAYS to UPDATE_ONCE mid-motion
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_continuous(on: bool) -> void:
	continuous = on
	if _viewport == null:
		return
	_viewport.render_target_update_mode = \
		SubViewport.UPDATE_ALWAYS if on or (_phosphor != null and _phosphor.active) else SubViewport.UPDATE_DISABLED


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
	# The governor may restore its scale to 1 at rest. Painting keeps its
	# independent ceiling, while still allowing the governor to go lower.
	var ray_scale := render_scale
	if _params != null and _params.painterly_enabled:
		ray_scale = minf(ray_scale, _params.painterly_scale)
	var s := ray_scale * _content_scale()
	var px := Vector2i(maxi(1, int(round(size.x * s))), maxi(1, int(round(size.y * s))))
	if _material:
		_material.set_shader_parameter("aspect", _aspect())
	_pending_size = px
	if _phosphor != null and _params != null:
		_phosphor.configure(_params.phosphor_enabled, px, _params.phosphor_bands)
	_update_painterly()
	if _brush_material != null:
		_brush_material.set_shader_parameter("display_size", size)
		var display_px := Vector2i(maxi(1, roundi(size.x * _content_scale())), maxi(1, roundi(size.y * _content_scale())))
		_paint_viewport.size = display_px
		_paint_rect.size = Vector2(display_px)
	if _phosphor != null and _phosphor.active:
		return
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


func _update_painterly() -> void:
	if _display == null:
		return
	var source := _viewport.get_texture()
	if _phosphor != null and _phosphor.active:
		source = _phosphor.output.get_texture()
	if _params == null or not _params.painterly_enabled:
		_display.texture = source
		if _phosphor != null and _phosphor.output.get_parent() != _phosphor:
			_phosphor.output.reparent(_phosphor)
		if _paint_viewport != null:
			_paint_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _brush_material == null:
		# A full-resolution presentation target keeps clipboard/MCP capture
		# identical to the on-screen painting without re-marching any rays.
		_paint_viewport = SubViewport.new()
		_paint_viewport.name = "PaintViewport"
		_paint_viewport.disable_3d = true
		add_child(_paint_viewport)
		_paint_rect = TextureRect.new()
		_paint_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paint_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_paint_viewport.add_child(_paint_rect)
		_brush_material = ShaderMaterial.new()
		_brush_material.shader = preload("res://src/fractal/painterly.gdshader")
	# Finish reconstruction before painting; never stretch a single scan strip.
	if _phosphor != null and _phosphor.output.get_parent() != _paint_viewport:
		_phosphor.output.reparent(_paint_viewport)
	_paint_rect.texture = source
	_brush_material.set_shader_parameter("ray_texture", source)
	_brush_material.set_shader_parameter("brush_size", _params.painterly_brush_size)
	_paint_rect.material = _brush_material
	_display.texture = _paint_viewport.get_texture()
	_paint_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _on_params_changed() -> void:
	_apply_size()
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
	var started := FrameProfiler.begin()
	_push_params_impl()
	FrameProfiler.end(&"Shader parameter upload", started)


func _push_params_impl() -> void:
	if _material == null or _params == null:
		return
	_material.set_shader_parameter("exit_radius", _params.gameplay.exit_radius)
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
	_material.set_shader_parameter("detail_range", _params.detail_range)
	_material.set_shader_parameter("detail_falloff", _params.detail_falloff)
	_material.set_shader_parameter("kifs_bailout_radius_squared",
		KifsEstimator.BAILOUT2 * _params.kifs_bailout_margin * _params.kifs_bailout_margin)
	_material.set_shader_parameter("mandelbulb_bailout_margin", _params.mandelbulb_bailout_margin)
	_sync_escape()
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
	var iterations := mini(_params.fractal_iterations, int(_shed["iterations"]))
	_material.set_shader_parameter("fractal_iterations", iterations)
	_material.set_shader_parameter("surface_detail", load_level < LoadShedder.top())
	var budget := clampi(int(round(_params.max_steps * _steps)),
		FractalParams.MAX_STEPS_MIN, int(_shed["step_cap"]))
	_material.set_shader_parameter("coarse_steps", _params.coarse_steps(budget))
	_material.set_shader_parameter("fine_steps", _params.fine_steps(budget))
	_push_escape()
	_material.set_shader_parameter("fog_color", _params.fog_color())
	# The self-shadow march's budget, shed with the ladder (full 48 at level 0;
	# it steps with the level rather than easing, since it is a step count).
	_material.set_shader_parameter("shadow_steps", int(round(FractalParams.SHADOW_STEPS * _shed["shadow"])))


## Reentering the sphere resets immediately, including a return to spawn.
func _sync_escape() -> void:
	if _params == null or _camera == null:
		return
	var outside := _params.gameplay.is_outside(_camera)
	if outside != _escaped:
		_escaped = outside
		_escape_elapsed = 0.0
		escape_changed.emit(_escaped)
	_push_escape()


func is_escaped() -> bool:
	return _escaped


func _escape_progress(duration: float) -> float:
	if not _escaped:
		return 0.0
	return 1.0 if duration <= 0.0 else smoothstep(0.0, duration, _escape_elapsed)


## Only presentation values change; the level's saved fog is preserved.
func _push_escape() -> void:
	if _material == null or _params == null:
		return
	var alpha := _escape_progress(_params.gameplay.escape_sky_duration)
	var clear := _escape_progress(_params.gameplay.escape_fog_duration)
	_material.set_shader_parameter("exit_has_skybox", alpha > 0.0 and _params.gameplay.exit_skybox != null)
	_material.set_shader_parameter("exit_sky_alpha", alpha)
	_material.set_shader_parameter("escape_fog_clear", clear)
	_material.set_shader_parameter("escape_ground_alpha", _escape_progress(_params.gameplay.escape_ground_duration))
	_material.set_shader_parameter("escape_fractal_dissolve", _escape_progress(_params.gameplay.escape_fractal_duration))
	_material.set_shader_parameter("fog_distance", _params.fog_distance if clear < 1.0 else 0.0)
	_material.set_shader_parameter("fog_dist", 1.0 / _fog_inv if _fog_inv > 0.0 and clear < 1.0 else 0.0)
	_material.set_shader_parameter("fog_clear", 1.0 - (1.0 - _fog_clear) * (1.0 - clear))


func _push_camera() -> void:
	if _material == null or _camera == null:
		return
	_sync_escape()
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
	var started := FrameProfiler.begin()
	_push_near_impl()
	FrameProfiler.end(&"Camera distance + shape frames", started)


func _push_near_impl() -> void:
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


func _setup_depth_scan() -> void:
	if _depth_scan != null or _material == null or _params == null or _camera == null:
		return
	_depth_scan = DepthScan.new()
	_depth_scan.name = "ScreenDepthCache"
	add_child(_depth_scan)
	_depth_scan.setup(self, _params, _camera, _material, TAN_HALF_FOV)


func depth_scan() -> Dictionary:
	return _depth_scan.snapshot() if _depth_scan != null else {"available": false, "distances": [], "status": []}


func request_depth_scan(args: Dictionary = {}) -> Dictionary:
	return _depth_scan.request(args) if _depth_scan != null else {"ok": true, "available": false}
