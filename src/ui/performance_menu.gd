extends "res://src/ui/debug_overlay.gd"
## F3 is global, including while a child window or text field owns keyboard focus.
## Only the game window draws the overlay, below embedded windows (layer 1024).

const REFRESH_SECONDS := 0.25

var measured_viewport: SubViewport
var _elapsed := 0.0
var _frames := 0
var _rendered := false
var _render_samples := 0
var _render_cpu := 0.0
var _render_gpu := 0.0
var _suppressed := false
var _visible_before_suppression := false


func _ready() -> void:
	super._ready()
	process_priority = 1000


func _add_shortcut(window_id: int) -> void:
	var window := instance_from_id(window_id) as Window
	if window == null or not window.is_inside_tree():
		return
	var shortcut := preload("res://src/ui/window_shortcut.gd").new()
	shortcut.name = shortcut_name
	shortcut.shortcut_key = shortcut_key
	shortcut.process_mode = Node.PROCESS_MODE_ALWAYS
	shortcut.toggle = func() -> void:
		if not _suppressed:
			visible = not visible
	window.add_child(shortcut)


func set_suppressed(on: bool) -> void:
	if on == _suppressed:
		return
	_suppressed = on
	if on:
		_visible_before_suppression = visible
		hide()
	else:
		visible = _visible_before_suppression


func watch_viewport(viewport: SubViewport) -> void:
	_release_viewport()
	measured_viewport = viewport
	viewport.tree_exiting.connect(_release_viewport, CONNECT_ONE_SHOT)
	if visible:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)


func _release_viewport() -> void:
	if is_instance_valid(measured_viewport):
		RenderingServer.viewport_set_measure_render_time(measured_viewport.get_viewport_rid(), false)
		if measured_viewport.tree_exiting.is_connected(_release_viewport):
			measured_viewport.tree_exiting.disconnect(_release_viewport)
	measured_viewport = null
	_render_samples = 0
	_render_cpu = 0.0
	_render_gpu = 0.0
	set_suppressed(false)


func _visibility_changed() -> void:
	FrameProfiler.set_enabled(visible)
	set_process(visible)
	_elapsed = 0.0
	_frames = 0
	_render_samples = 0
	_render_cpu = 0.0
	_render_gpu = 0.0
	_rendered = false
	if is_instance_valid(measured_viewport):
		RenderingServer.viewport_set_measure_render_time(measured_viewport.get_viewport_rid(), visible)
	if visible:
		RenderingServer.frame_pre_draw.connect(_before_draw)
		RenderingServer.frame_post_draw.connect(_after_draw)
		_refresh([])
	else:
		if RenderingServer.frame_pre_draw.is_connected(_before_draw):
			RenderingServer.frame_pre_draw.disconnect(_before_draw)
		if RenderingServer.frame_post_draw.is_connected(_after_draw):
			RenderingServer.frame_post_draw.disconnect(_after_draw)


func _exit_tree() -> void:
	_visible_before_suppression = false
	hide()
	_release_viewport()
	FrameProfiler.set_enabled(false)


func _before_draw() -> void:
	_rendered = is_instance_valid(measured_viewport) \
		and measured_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


func _after_draw() -> void:
	if not _rendered or not is_instance_valid(measured_viewport):
		return
	var rid := measured_viewport.get_viewport_rid()
	# Renderer results may arrive a few frames late. Read the latest available
	# result only when drawing, never turn an idle cached image into fake work.
	_render_cpu = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_render_gpu = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_render_samples += 1


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	if _elapsed >= REFRESH_SECONDS:
		_refresh(FrameProfiler.take_snapshot(_frames))
		_elapsed = 0.0
		_frames = 0
		_render_samples = 0


func _refresh(rows: Array) -> void:
	var lines := PackedStringArray([
		"F3  PERFORMANCE  ·  %d FPS" % Engine.get_frames_per_second(),
		"60 FPS budget: 16.67 ms  ·  100% = one frame",
		"",
		"CPU operations · average / frame (last 0.25 s)",
	])
	if rows.is_empty():
		lines.append("Waiting for samples…")
	for row: Dictionary in rows:
		lines.append("%s:  %.3f ms  /  %.1f%%" % [row.name, row.ms, row.percent])
	lines.append("")
	lines.append("Fractal renderer · latest available rendered frame")
	if measured_viewport == null:
		lines.append("No fractal view")
	elif _render_samples == 0:
		lines.append("Idle / waiting for a rendered frame")
	else:
		lines.append(_render_line("GPU ray march + shading", _render_gpu))
		lines.append(_render_line("CPU render submission", _render_cpu))
	lines.append("")
	lines.append("Nested CPU timings overlap; CPU and GPU run in parallel.")
	lines.append("F3 to close · measurement stops when hidden")
	readout.text = "\n".join(lines)
	panel.reset_size()


func _render_line(label: String, ms: float) -> String:
	if ms <= 0.0:
		return label + ": unavailable / warming up"
	return "%s:  %.3f ms  /  %.1f%%" % [label, ms, ms / FrameProfiler.FRAME_BUDGET_MS * 100.0]
