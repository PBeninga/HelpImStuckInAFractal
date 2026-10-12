extends CanvasLayer
## F3 is global, including while a child window or text field owns keyboard focus.
## Only the game window draws the overlay, below embedded windows (layer 1024).

const REFRESH_SECONDS := 0.25

## A handler in each window's viewport, before focused Controls consume keys.
class WindowShortcut extends Node:
	var toggle: Callable

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_F3 or event.physical_keycode == KEY_F3):
			toggle.call()
			get_viewport().set_input_as_handled()


var panel: PanelContainer
var readout: Label
var measured_viewport: SubViewport
var _elapsed := 0.0
var _frames := 0
var _rendered := false
var _render_samples := 0
var _render_cpu := 0.0
var _render_gpu := 0.0


func _ready() -> void:
	layer = 1023
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	visible = false
	set_process(false)
	panel = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.065, 1.0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	readout = Label.new()
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	readout.add_theme_font_size_override("font_size", 16)
	panel.add_child(readout)
	visibility_changed.connect(_visibility_changed)
	_watch_windows(get_tree().root)
	get_tree().node_added.connect(_watch_window)


func _watch_windows(node: Node) -> void:
	_watch_window(node)
	for child in node.get_children():
		_watch_windows(child)


func _watch_window(node: Node) -> void:
	if node is Window:
		# A transient popup may be freed before this deferred call gets its turn.
		_add_shortcut.call_deferred(node.get_instance_id())


func _add_shortcut(window_id: int) -> void:
	var window := instance_from_id(window_id) as Window
	if window == null or not window.is_inside_tree():
		return
	var shortcut := WindowShortcut.new()
	shortcut.name = "PerformanceShortcut"
	shortcut.process_mode = Node.PROCESS_MODE_ALWAYS
	shortcut.toggle = func() -> void: visible = not visible
	window.add_child(shortcut)


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
