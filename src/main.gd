class_name Main
extends Node
## Wires shape/look tables, axes, cameras and the console. Gameplay owns level
## files, spawn and escape controls; View owns rendering and window controls.
## Escape frees the mouse; a Ctrl tap toggles the console. Return to spawn uses
## the level's configured coordinates. R toggles the centre-ray probe.
##
## Fullscreen (the View tab's button, or the OS's own green button) docks the
## console into the main window's right-hand strip and narrows the view to the
## rest, so the two fill one fullscreen window; leaving fullscreen makes the
## console a separate window again. Reset window puts the main window back at
## its default size and the console beside it.

const MENU_SCENE := "res://src/ui/main_menu.tscn"
## The main window's size in points (logical units); see UiScale.
const WINDOW_SIZE := Vector2i(1280, 800)
## For now the console opens beside the main window at startup (the mouse stays
## captured and the main window keeps focus); false starts it hidden.
const OPEN_CONSOLE_AT_START := true
## Seconds to let the OS finish leaving fullscreen (macOS animates it) before a
## native console reopens beside the main window, or Reset window measures it.
const WINDOW_SETTLE_DELAY := 0.8
## A new shape is a tenth of the selected one's size, centred this many of its
## own sizes in front of the camera: far enough for its whole cube (4 × size
## across) to fit the 40° view with a margin.
const NEW_SHAPE_SIZE_RATIO := 0.1
const NEW_SHAPE_DISTANCE := 7.0

var params: FractalParams
var camera: CameraState
var shape_run: ShapeRun
## Set before entering the tree when the title menu owns this editable scene.
var preparing := false
## Shared by direct MCP and phone tools; runs only on explicit request.
var ship_depth_scanner := preload("res://src/mcp/ship_depth_scan.gd").new()

@onready var view: FractalView = $FractalView
@onready var governor: ResolutionGovernor = $ResolutionGovernor
@onready var fly: FlyCamera = $FlyCamera

var _orbit: OrbitCamera
var _marker: JuliaMarker
var _shapes: ShapeList
var _keymap: Keymap
var _axis_controller: AxisController
var _clock: Clock
var _console: ConsoleWindow
var _last_mode := -1
var _files: WorkspaceFiles
var _view_pane: ViewPane
var _gameplay_pane: GameplayPane
var _noise: NoiseWindow
var _chat: ChatPanel
var _loading := false
## True once Escape, a Ctrl tap or a file panel has freed the mouse; a click in the view
## clears it and recaptures. Capture no longer depends on the console's state.
var _free_requested := false
## The intended capture state. Tracked here rather than read back from
## Input.mouse_mode, which a headless run cannot report as CAPTURED.
var _captured := false
var _ctrl := CtrlTap.new()
## The viewports whose focused text field silences WASD, the axis keys, N and
## the Ctrl tap: the main window's, the console's and the noise window's. One
## array, shared by reference with the fly camera and the axis controller.
var _text_viewports: Array = []
## The console is docked beside the view in one fullscreen window.
var _docked := false
## Whether the main window was fullscreen when last looked at; a change docks
## or undocks the console.
var _was_fullscreen := false
var _escape_active := false
var _escape_ui := {}


func _ready() -> void:
	# Normally done by the title menu already; repeated so main.tscn run on its
	# own is scaled too (both calls are no-ops the second time).
	UiScale.apply(get_window())
	WindowGeometry.place_main_window(get_window(), Settings.window_rect(&"main"))
	UiScale.follow_size(get_window(), WINDOW_SIZE)
	params = FractalParams.new()
	camera = CameraState.make_default()

	_shapes = ShapeList.new()
	_shapes.table(0).set_default(&"shape", FractalParams.Shape.KLEINIAN)
	# The default flight is escaped by flying out; scripts belong to authored levels.
	_shapes.set_stage(0, 0.0, [])
	_shapes.changed.connect(_sync_shapes)
	_keymap = Keymap.new()
	_keymap.reset_to_default()   # the shipped default (E / Q) until a level is loaded

	view.setup(params, camera)
	governor.setup(params, view)
	governor.shed_level_changed.connect(_on_shed_level_changed)
	fly.setup(params, camera, view.center_ray())

	_orbit = get_node_or_null("OrbitCamera")
	if _orbit:
		_orbit.setup(params, camera, view)
	_marker = get_node_or_null("JuliaMarker")
	if _marker:
		_marker.setup(params, camera, view, _shapes)

	_build_clock()
	_build_console()
	_build_axis_controller()

	# Each window is its own viewport, embedded or not; typing in any of them
	# must silence WASD and the axis keys. (The noise window joins when built.)
	fly.set_text_viewports(_focus_viewports())

	_build_workspace_files()
	_build_view_pane()
	_build_gameplay()
	_build_noise_window()
	_build_chat()
	view.escape_changed.connect(_on_escape_changed)
	_on_escape_changed(view.is_escaped())
	_clock.set_process(not preparing)
	_axis_controller.set_process(not preparing)
	_chat.visible = not preparing
	_chat.process_mode = Node.PROCESS_MODE_DISABLED if preparing else Node.PROCESS_MODE_INHERIT
	_view_pane.menu_button.disabled = preparing

	# The sensitivity is the player's, not the view's: Settings owns it.
	params.mouse_sensitivity = Settings.mouse_sensitivity
	_view_pane.set_sensitivity(Settings.mouse_sensitivity)
	view.show_probe = Settings.show_center_ray and not _escape_active
	Settings.changed.connect(_on_settings_changed)
	params.changed.connect(_sync_sensitivity_to_settings)

	_ctrl.typing_guard = func() -> bool: return TextFocus.any(_focus_viewports())

	params.changed.connect(_apply_mode)
	camera.changed.connect(func(): governor.mark_changed())
	# Reopen the last successful save through the ordinary level loader.
	var default_level := WorkspaceFiles.last_saved_file()
	if default_level != "":
		load_level_from(default_level)
	_resolve_once()
	_apply_mode()
	shape_run = ShapeRun.new(_shapes, params, camera)
	shape_run.changed.connect(_on_shape_run_changed)
	shape_run.fog_changed.connect(view.set_stage_fog)
	shape_run.stage_activated.connect(_on_stage_activated)
	params.gameplay.changed.connect(_refresh_shape_boundary)
	_shapes.stage_changed.connect(func(_i): _restart_shape_run())
	_shapes.next_level_distance_changed.connect(func(_i): _refresh_shape_boundary())
	var bridge := get_node_or_null("/root/McpBridge")
	if bridge != null:
		bridge.chat.message_added.connect(_on_run_chat_message)
	_restart_shape_run()
	var gameplay_menu := get_node_or_null("/root/GameplayMenu")
	if gameplay_menu != null:
		gameplay_menu.watch_game(self)
	# After follow_size's handler, so a resize has refitted the scale first.
	get_window().size_changed.connect(_on_window_resized)
	# Keys now come to the main window, so a field left focused in the console
	# would only silence WASD.
	get_window().focus_entered.connect(_drop_side_focus)
	_was_fullscreen = _is_fullscreen()
	if _was_fullscreen:
		set_docked(true)
	if OPEN_CONSOLE_AT_START:
		# Deferred so the main window has its final size and place to sit beside.
		_open_console_at_start.call_deferred()


## Activate the scene already edited in the title screen's console.
func begin_play() -> void:
	_drop_side_focus()   # Commit any text still being edited in a spin box.
	_resolve_once()
	preparing = false
	_clock.set_process(true)
	_axis_controller.set_process(true)
	_chat.show()
	_chat.process_mode = Node.PROCESS_MODE_INHERIT
	_view_pane.menu_button.disabled = false
	_free_requested = false
	_apply_mode()
	_restart_shape_run()
	get_window().grab_focus()


func workspace_files() -> WorkspaceFiles:
	return _files


func gameplay_pane() -> GameplayPane:
	return _gameplay_pane


func view_pane() -> ViewPane:
	return _view_pane


func noise_window() -> NoiseWindow:
	return _noise


func console() -> ConsoleWindow:
	return _console


func chat() -> ChatPanel:
	return _chat


## The scene's shapes (their tables).
func shapes() -> ShapeList:
	return _shapes


## The selected shape's look table (light and material).
func look_table() -> AttributeTable:
	return _shapes.look_table(clampi(params.active, 0, _shapes.count() - 1))


## The active (console-selected) shape's table.
func table() -> AttributeTable:
	return _shapes.table(clampi(params.active, 0, _shapes.count() - 1))


## The defaults for a shape added from the console: the active shape's knobs
## (bindings aside) at NEW_SHAPE_SIZE_RATIO of its size, centred
## NEW_SHAPE_DISTANCE of the new size in front of the camera, unrotated.
func new_shape_defaults() -> Dictionary:
	var defaults := table().defaults()
	var size: float = float(defaults.get(&"size", 1.0)) * NEW_SHAPE_SIZE_RATIO
	var f := camera.forward()
	var d := NEW_SHAPE_DISTANCE * size
	defaults[&"size"] = size
	defaults[&"pos_x"] = camera.eye_x() + f.x * d
	defaults[&"pos_y"] = camera.eye_y() + f.y * d
	defaults[&"pos_z"] = camera.eye_z() + f.z * d
	defaults[&"rot_x"] = 0.0
	defaults[&"rot_y"] = 0.0
	defaults[&"rot_z"] = 0.0
	return defaults


## Add a shape from the console's defaults and make it the active one.
func add_shape() -> int:
	var i := _shapes.add(new_shape_defaults(), "", look_table().defaults())
	if i >= 0:
		if _console != null:
			_console.shape_pane().set_expanded(i, true)
			_console.shape_pane().select(i)
		params.active = i
	return i


## Keep params.shapes the same length as the list (a load, an add, a remove);
## the next resolve fills the values.
func _sync_shapes() -> void:
	params.set_shape_count(_shapes.count())
	params.active = clampi(params.active, 0, _shapes.count() - 1)
	_resolve_once()
	if shape_run != null and not _loading:
		_restart_shape_run()


func keymap() -> Keymap:
	return _keymap


# ------------------------------------------------------------- build helpers

func _build_clock() -> void:
	_clock = Clock.new()
	_clock.name = "Clock"
	add_child(_clock)


func _build_console() -> void:
	_console = ConsoleWindow.new()
	_console.name = "ConsoleWindow"
	_console.setup(_shapes, look_table(), _keymap, _clock, ShapeCatalogue.group_tooltips(),
		func() -> float: return camera.speed_factor, new_shape_defaults)
	add_child(_console)
	_console.shape_pane().selected_changed.connect(func(i: int): params.active = i)
	_console.toggle_requested.connect(_on_console_toggle)
	_console.unhandled_key.connect(_on_window_key)
	_console.game_focus_requested.connect(return_to_game)
	# The zoom is the player's, like the sensitivity: Settings keeps it.
	_console.set_zoom(Settings.console_zoom)
	_console.zoom_changed.connect(func(z: float): Settings.console_zoom = z)
	# Its place is the player's too: put it back where it was last left.
	_console.remembered_rect = Settings.window_rect(&"console")
	Settings.track_window(&"console", _console)
	_console.visibility_changed.connect(_layout_view)


func _build_axis_controller() -> void:
	_axis_controller = AxisController.new()
	_axis_controller.name = "AxisController"
	_axis_controller.setup(_keymap, _focus_viewports())
	add_child(_axis_controller)


func _focus_viewports() -> Array:
	if _text_viewports.is_empty():
		_text_viewports.append(get_viewport())
	for w in [_console, _noise]:
		if w != null and not _text_viewports.has(w):
			_text_viewports.append(w)
	return _text_viewports


func _build_noise_window() -> void:
	_noise = NoiseWindow.new()
	_noise.name = "NoiseWindow"
	add_child(_noise)
	_noise.setup(view)
	_noise.close_requested.connect(_update_mouse)
	_noise.unhandled_key.connect(_on_window_key)
	_noise.game_focus_requested.connect(return_to_game)
	_focus_viewports()


## The pilot chat down the right of the view. Its log belongs to McpBridge, so
## the conversation survives Back to Menu; without the bridge it is local.
func _build_chat() -> void:
	var bridge := get_node_or_null(^"/root/McpBridge")
	var chat_log: ChatLog = bridge.chat if bridge != null else ChatLog.new()
	_chat = ChatPanel.new()
	_chat.name = "ChatPanel"
	add_child(_chat)
	_chat.setup(chat_log)


func _toggle_noise() -> void:
	if _escape_active:
		return
	_noise.toggle()
	_update_mouse()


func _build_view_pane() -> void:
	_view_pane = _console.view_pane()
	_view_pane.setup(params)
	_view_pane.menu_requested.connect(back_to_menu)
	_view_pane.noise_requested.connect(_open_noise)
	_view_pane.sensitivity_changed.connect(func(v: float): Settings.mouse_sensitivity = v)
	# Deferred: docking hides and re-makes the console, which must not happen
	# inside the console's own click.
	_view_pane.fullscreen_requested.connect(toggle_fullscreen, CONNECT_DEFERRED)
	_view_pane.reset_window_requested.connect(reset_window, CONNECT_DEFERRED)


func _build_gameplay() -> void:
	_gameplay_pane = _console.gameplay_pane()
	_gameplay_pane.setup(params.gameplay)
	_gameplay_pane.show_file(_files.display_name())
	_gameplay_pane.save_requested.connect(_files.prompt_save)
	_gameplay_pane.load_requested.connect(_files.prompt_load)
	_gameplay_pane.return_requested.connect(return_to_spawn)
	_gameplay_pane.find_surface_requested.connect(find_nearest_surface)
	_console.escape_animation_pane().setup(params.gameplay)


## Show the console beside the main window, then hand focus back to the main
## window so flying starts as it would with the console closed.
func _open_console_at_start() -> void:
	if _escape_active:
		return
	_console.open()
	get_window().grab_focus()


## The View tab's Noise editor button: open it (the mouse is already free).
func _open_noise() -> void:
	if _escape_active:
		return
	_noise.open()
	_update_mouse()


# ------------------------------------------------------------- windows

func is_docked() -> bool:
	return _docked


## The View tab's Fullscreen button: enter fullscreen with the console docked on
## the right, or leave it with the console a separate window again.
func toggle_fullscreen() -> void:
	var on := not _docked
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	_was_fullscreen = on
	set_docked(on)


## Dock the console into the main window's right-hand strip (and show it), or
## undock it. Undocking reopens a console that was open as a native window
## once the main window has settled, so it lands beside the windowed main
## window rather than the fullscreen one.
func set_docked(on: bool) -> void:
	if on == _docked:
		if on:
			_console.dock(_dock_rect())
			_layout_view()
		return
	_docked = on
	if on:
		_console.dock(_dock_rect())
		if not _escape_active:
			_console.open()
	else:
		var was_open := _console.visible
		_console.undock()
		if was_open:
			_after_window_settles(_reopen_console)
	_layout_view()
	_view_pane.show_fullscreen(on)


## The View tab's Reset window: forget where the windows were left, put the
## main window back at its default size and place, and the console beside it.
## Leaves fullscreen first, then waits for the window to settle.
func reset_window() -> void:
	if _docked:
		toggle_fullscreen()
		_after_window_settles(reset_window)
		return
	Settings.forget_window_rects()
	WindowGeometry.reset_main_window(get_window())
	_console.reset_place()


func _is_fullscreen() -> bool:
	var mode := get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN


## The main window changed size: entering or leaving fullscreen (by the button
## or the OS) docks or undocks the console; docked, the strip follows the size.
func _on_window_resized() -> void:
	var fullscreen := _is_fullscreen()
	if fullscreen != _was_fullscreen:
		_was_fullscreen = fullscreen
		set_docked(fullscreen)
	elif _docked:
		set_docked(true)


## The docked console's strip of the main window's canvas: the right-hand
## WindowGeometry.dock_width() points, full height.
func _dock_rect() -> Rect2i:
	var canvas := get_viewport().get_visible_rect()
	var per_unit := UiScale.points_per_unit(get_window())
	var width := roundi(WindowGeometry.dock_width(canvas.size.x * per_unit) / per_unit)
	return Rect2i(Vector2i(roundi(canvas.end.x) - width, roundi(canvas.position.y)),
		Vector2i(width, roundi(canvas.size.y)))


## Docked with the console showing, the view (and the Julia marker over it)
## stops at the console's left edge, and the pilot chat moves left beside it;
## otherwise they fill the window.
func _layout_view() -> void:
	var right := 0.0
	if _docked and _console.visible:
		right = -float(_dock_rect().size.x)
	for c in [view, _marker]:
		if c != null:
			c.offset_right = right
	if _chat != null:
		_chat.set_right_inset(-right)


func _reopen_console() -> void:
	if not _escape_active and not _docked and not _console.visible:
		_console.open()


func _after_window_settles(then: Callable) -> void:
	get_tree().create_timer(WINDOW_SETTLE_DELAY).timeout.connect(then)


func back_to_menu() -> void:
	if preparing:
		return
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_settings_changed() -> void:
	params.mouse_sensitivity = Settings.mouse_sensitivity
	_view_pane.set_sensitivity(Settings.mouse_sensitivity)
	view.show_probe = Settings.show_center_ray and not _escape_active


func _sync_sensitivity_to_settings() -> void:
	if not _loading:
		Settings.mouse_sensitivity = params.mouse_sensitivity


func _on_file_current_changed(display_name: String) -> void:
	if _gameplay_pane != null:
		_gameplay_pane.show_file(display_name)


func _build_workspace_files() -> void:
	_files = WorkspaceFiles.new()
	_files.name = "WorkspaceFiles"
	add_child(_files)
	_files.save_to.connect(save_level_to)
	_files.load_from.connect(load_level_from)
	_files.current_changed.connect(_on_file_current_changed)
	_files.prompting.connect(_on_prompting)
	var directory := WorkspaceFiles.directory()
	if directory != WorkspaceFiles.REPO_DIR:
		_report("Saves go to %s: this build cannot write into the project." % directory)
	elif WorkspaceFiles.ensure_directory() != OK:
		_report("Could not create %s; the file panel opens at your home folder." % directory)


# ------------------------------------------------------------- per-frame

func _process(_delta: float) -> void:
	if shape_run != null and not preparing:
		shape_run.step(_delta)
	_resolve_once()
	if shape_run != null:
		_check_shape_progress()
	if _escape_active:
		governor.mark_changed()
	# The fly camera's zoom limit reaches the Movement pane the way the shed
	# level does, polled since it can change on any physics tick.
	if _console != null:
		_console.show_zoom_limit(fly.at_zoom_limit)


## Resolve every shape's table (into its ShapeParams) and the look table (into
## params) + axis values + clock, and feed the console's readouts (the rows and
## the Shape tab's self-similarity line, for the active shape). Cheap (about a
## hundred scalars per shape); apply_resolved emits at most once per shape, and
## nothing when no binding is active.
func _resolve_once() -> void:
	var started := FrameProfiler.begin()
	if params.shapes.size() != _shapes.count():
		params.set_shape_count(_shapes.count())
	var axis_values := _keymap.axes().values()
	var all := _shapes.resolve(axis_values, _clock.t)
	for i in all.size():
		if shape_run != null and not _loading:
			all[i].merge(shape_run.overrides(i), true)
		params.shapes[i].apply_resolved(all[i])
	# Only resolve the rendered shape's look: inactive editor previews use defaults.
	var rendered_shape := clampi(params.gameplay_active if params.gameplay_active >= 0 else params.active, 0, _shapes.count() - 1)
	var look := BindingResolver.resolve(_shapes.look_table(rendered_shape), axis_values, _clock.t)
	params.apply_resolved(look)
	FrameProfiler.end(&"Bindings + scene updates", started)
	if _console != null and _console.visible:
		started = FrameProfiler.begin()
		_console.set_resolved(all, look, rendered_shape)
		var active: Dictionary = all[clampi(params.active, 0, all.size() - 1)]
		_console.show_self_similarity(ShapeCatalogue.self_similarity(
			active, NoiseCompiler.displaces(view.noise_graph())))
		FrameProfiler.end(&"Console readouts", started)


# ------------------------------------------------------------- save / load

func save_level_to(path: String) -> void:
	var noise: Dictionary = _noise.to_dict() if _noise != null else {}
	var err := Workspace.save_file(path, _shapes, look_table(), _keymap, params, camera, noise)
	if err != OK:
		_report("Save failed (error %d): %s" % [err, path])
		return
	_files.note_saved(path)
	var pointer_err := WorkspaceFiles.remember_saved(path)
	if pointer_err != OK:
		_report("Saved %s, but could not update startup pointer (error %d)." % [path.get_file(), pointer_err])
		return
	_report("Saved %s" % path.get_file())


func load_level_from(path: String) -> void:
	_loading = true
	var result := Workspace.load_file(path, _shapes, look_table(), _keymap, params, camera)
	_loading = false
	params.mouse_sensitivity = Settings.mouse_sensitivity
	var warnings: Array = result["warnings"]
	if not result["ok"]:
		_report("Load failed: %s" % warnings[0])
		return
	_files.note_loaded(path)
	if _console != null:
		_console.shape_pane().select(params.active)
	if shape_run != null:
		_restart_shape_run()
	_resolve_once()   # push the loaded table straight into params
	var noise: Variant = result.get("noise", null)
	if noise is Dictionary and _noise != null:
		var noise_warnings := _noise.apply_dict(noise)
		for w in noise_warnings:
			warnings.append("noise: %s" % w)
	if _orbit and params.camera_mode == FractalParams.CameraMode.ORBIT:
		_orbit.enter()
	if warnings.is_empty():
		_report("Loaded %s" % path.get_file())
	else:
		_report("Loaded %s with %d warning(s): %s" % [path.get_file(), warnings.size(), "; ".join(warnings)])


## Return to the level's configured spawn, preserving the look direction.
func return_to_spawn() -> void:
	if shape_run != null:
		_restart_shape_run(true)
	else:
		params.gameplay.return_to_spawn(camera)
	if _orbit and params.camera_mode == FractalParams.CameraMode.ORBIT:
		_orbit.enter()
	_report("Returned to spawn")


## Recover a lost shape without moving the eye or changing flight speed.
func find_nearest_surface() -> Dictionary:
	var hit := SurfaceFinder.find(params, camera)
	if hit.is_empty():
		var message := "No surface found within the visible scene."
		_report(message)
		return {"ok": false, "message": message}
	var direction: Vector3 = hit.direction
	camera.set_basis(CameraState.facing_basis(direction))
	if _orbit and params.camera_mode == FractalParams.CameraMode.ORBIT:
		var distance: float = hit.distance
		_orbit.recenter_on(Vector3(camera.eye_x() + direction.x * distance,
			camera.eye_y() + direction.y * distance, camera.eye_z() + direction.z * distance))
	var message := "Facing nearest surface (distance %s)." % hit.distance
	_report(message)
	return {"ok": true, "message": message, "distance": hit.distance}


## Cmd/Ctrl+P: put the fractal (without any UI) on the clipboard.
func copy_screenshot() -> void:
	var err := ClipboardImage.copy(view.capture())
	if err == OK:
		_report("Screenshot copied to clipboard")
	else:
		_report("Could not copy screenshot: %s" % error_string(err))


## The load shedder's top level caps the Fly speed; the console's Movement pane
## shows the level.
func _on_shed_level_changed(level: int) -> void:
	fly.speed_limit = LoadShedder.settings(level)["speed"]
	_console.show_shed_level(level)


func _report(line: String) -> void:
	print(line)
	if _gameplay_pane != null:
		_gameplay_pane.show_status(line)


## A file panel is opening (possibly from Cmd+S with the mouse captured): free
## the mouse so the panel can be used.
func _on_prompting() -> void:
	_free_requested = true
	_update_mouse()


# ------------------------------------------------------------- mouse / mode

func _on_escape_changed(escaped: bool) -> void:
	if escaped == _escape_active:
		return
	_escape_active = escaped
	view.screen_tints.set_suppressed(escaped)
	var performance := get_node_or_null("/root/PerformanceMenu")
	if performance != null:
		performance.set_suppressed(escaped)
	var cc := get_node_or_null("/root/CallCenter")
	if cc != null and cc.hud != null:
		cc.hud.set_escaped(escaped)
	fly.movement_locked = escaped
	_axis_controller.set_process(not escaped and not preparing)
	_files.quick_save_enabled = not escaped
	if _marker:
		_marker.suppressed = escaped
	if escaped:
		_escape_ui = {"console": _console.visible, "chat": _chat.visible}
		_drop_side_focus()
		_chat.input.release_focus()
		_console.hide_console()
		_noise.close()
		_chat.hide()
		_chat.process_mode = Node.PROCESS_MODE_DISABLED
		view.show_probe = false
		if _marker:
			_marker.end_drag()
		_free_requested = false
	else:
		_chat.visible = _escape_ui.get("chat", true)
		_chat.process_mode = Node.PROCESS_MODE_INHERIT
		view.show_probe = Settings.show_center_ray and not _escape_active
		if _escape_ui.get("console", false):
			_console.open()
	_apply_mode()

func _apply_mode() -> void:
	var is_fly := _escape_active or params.camera_mode == FractalParams.CameraMode.FLY
	fly.enabled = is_fly and not preparing
	if _orbit:
		_orbit.enabled = not is_fly and not preparing
		if not is_fly and params.camera_mode != _last_mode:
			_orbit.enter()
	_last_mode = params.camera_mode
	_update_mouse()


func _update_mouse() -> void:
	_captured = not preparing and (_escape_active or params.camera_mode == FractalParams.CameraMode.FLY) \
			and not _free_requested \
			and not (_noise != null and _noise.visible)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE)


## Whether the mouse is (meant to be) captured. Headless cannot report CAPTURED
## through Input.mouse_mode, so Main tracks the intent itself.
func is_mouse_captured() -> bool:
	return _captured


## A Ctrl tap, from Main's window or the console's. Captured (flying): free the
## mouse and make sure the console is open. Free: toggle the console, and when
## that closes it, allow the mouse to recapture.
func _on_console_toggle() -> void:
	if _escape_active:
		return
	if _captured:
		_free_requested = true
		if not _console.visible:
			_console.open()
	else:
		_console.toggle()
		if not _console.visible:
			_free_requested = false
	_update_mouse()


## Back to the game: let go of any text field the console or the noise window
## still holds. A spin box keeps its focus after Enter, and a focused field in
## any window silences WASD (TextFocus), so without this flying stays dead
## after a console edit. A spin box applies what was typed as it lets go.
func _drop_side_focus() -> void:
	for w: Window in [_console, _noise]:
		if w != null:
			w.gui_release_focus()


## WASD pressed in the console or the noise window: give the main window
## keyboard focus and, as a click in the view would, close the noise editor and
## recapture the mouse, so the key that asked flies.
func return_to_game() -> void:
	if preparing:
		return
	if _noise != null:
		_noise.close()
	get_window().grab_focus()
	_free_requested = false
	_update_mouse()


## A key the focused console or noise window did not use. A window
## that holds keyboard focus keeps keys from the main window, so they come here
## to get the same Ctrl tap / Escape / N / screenshot / quick-save handling.
func _on_window_key(event: InputEventKey) -> void:
	_unhandled_input(event)
	if _files != null and event.is_action_pressed(&"workspace_quick_save"):
		_files.quick_save()


func _active_camera() -> Node:
	return fly if params.camera_mode == FractalParams.CameraMode.FLY else _orbit


## Every key press first lets go of a modifier the OS no longer holds (Cmd and
## Shift left stuck by Cmd+Shift+5, which would stop WASD), before anything reads it.
func _input(event: InputEvent) -> void:
	StaleModifiers.release(event)


# The only mouse dispatcher: Ctrl tap -> Escape/screenshot -> noise -> marker -> camera.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quit_game"):
		get_viewport().set_input_as_handled()
		get_tree().quit()
		return

	if _escape_active:
		if event.is_action_pressed("cancel"):
			_free_requested = true
			_update_mouse()
		elif event.is_action_pressed("copy_screenshot"):
			copy_screenshot()
		elif event is InputEventMouseMotion and _captured:
			fly.apply_look(event.relative.x, event.relative.y)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_free_requested = false
			_update_mouse()
		get_viewport().set_input_as_handled()
		return

	# 1. A Ctrl tap (down then up with no other key between) toggles the console.
	if _ctrl.feed(event):
		_on_console_toggle()
		get_viewport().set_input_as_handled()
		return
	if preparing:
		return

	# Escape frees the mouse and nothing else: the console and the noise window
	# stay as they are. A click in the view recaptures.
	if event.is_action_pressed("cancel"):
		_free_requested = true
		_update_mouse()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("copy_screenshot"):
		copy_screenshot()
		get_viewport().set_input_as_handled()
		return

	# 1b. N toggles the noise editor (ignored while a text field is focused).
	if event.is_action_pressed("toggle_noise_editor"):
		if TextFocus.any(_focus_viewports()):
			return
		_toggle_noise()
		get_viewport().set_input_as_handled()
		return

	# 1c. R shows or hides the centre-ray probe dot (not while typing).
	if event.is_action_pressed("toggle_center_ray"):
		if TextFocus.any(_focus_viewports()):
			return
		Settings.show_center_ray = not Settings.show_center_ray
		get_viewport().set_input_as_handled()
		return

	# 2. Julia marker drag (of the active shape), only while the mouse is free
	if _marker and params.julia_enabled() and not _captured:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _marker.begin_drag(event.position):
					get_viewport().set_input_as_handled()
					return
			else:
				_marker.end_drag()
		elif event is InputEventMouseMotion and _marker.is_dragging():
			_marker.update_drag(event.position)
			get_viewport().set_input_as_handled()
			return

	# 3. click in the view in FLY mode while free: recapture, close the noise
	# editor, drop any text focus left in the console, and LEAVE the console
	# open, so its readouts stay in sight while flying. (A click on the console
	# or noise window is that window's; it never gets here.)
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and params.camera_mode == FractalParams.CameraMode.FLY \
			and not _captured:
		_free_requested = false
		_drop_side_focus()
		if _noise != null:
			_noise.close()
		_update_mouse()
		get_viewport().set_input_as_handled()
		return

	# 4. the active camera handles the rest (look when captured, wheel, orbit drags)
	var cam_node := _active_camera()
	if cam_node and cam_node.handle_event(event):
		get_viewport().set_input_as_handled()


func _restart_shape_run(move_to_spawn := false) -> void:
	# Reset before moving so the old run cannot advance at the new spawn.
	shape_run.reset()
	if move_to_spawn:
		params.gameplay.return_to_spawn(camera)
	_send_run_briefing("run_started")

func _on_shape_run_changed() -> void:
	_resolve_once()
	params.emit_changed()
	fly.movement_locked = shape_run.escaped or shape_run.transitioning()
	if _console != null:
		_console.shape_pane().set_gameplay_active(params.gameplay_active)

func _on_stage_activated(_index: int) -> void:
	view.reset_shape_history()
	_send_run_briefing("active_shape_changed")

func _send_run_briefing(kind: String) -> void:
	if preparing:
		return
	var cc := get_node_or_null("/root/CallCenter")
	if cc != null:
		cc.notify_agent(kind, "Active shape briefing: " + JSON.stringify(shape_run.briefing()), {}, true)

func _on_run_chat_message(message: Dictionary) -> void:
	if not preparing and message.get("role", "") == "human":
		shape_run.note_human_message(str(message.get("text", "")))


func _check_shape_progress() -> void:
	if not _loading and not preparing:
		shape_run.check_position(fly.current_speed())


func _refresh_shape_boundary() -> void:
	if not _loading and shape_run != null:
		shape_run.refresh_boundary()
