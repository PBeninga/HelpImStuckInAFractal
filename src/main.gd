class_name Main
extends Node
## Wires the shape table, the keymap/axes, the clock and the console into every
## child, selects the active camera from camera_mode, owns the mouse capture,
## and is the single mouse-event dispatcher. Each frame it resolves the shape
## table + axis values + clock into the params every consumer reads. Saving and
## loading a view: WorkspaceFiles picks the file, Workspace does the reading and
## writing, the console's View tab shows the result. Escape only frees the
## mouse; a Ctrl tap opens the console, whose View tab holds Save / Load, the
## camera mode, the renderer and Back to Menu. Reset camera (in the Movement
## pane and the View tab's Renderer options) puts the camera back where the
## current file has it. R shows or hides the centre-ray probe dot (a Settings
## preference).
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

var params: FractalParams
var camera: CameraState

@onready var view: FractalView = $FractalView
@onready var governor: ResolutionGovernor = $ResolutionGovernor
@onready var fly: FlyCamera = $FlyCamera

var _orbit: OrbitCamera
var _marker: JuliaMarker
var _table: AttributeTable
var _keymap: Keymap
var _axis_controller: AxisController
var _clock: Clock
var _console: ConsoleWindow
var _last_mode := -1
var _files: WorkspaceFiles
var _view_pane: ViewPane
var _noise: NoiseWindow
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
## Where Reset camera goes: the camera as the current file has it (as last
## loaded or saved), or the starting view while no file is current.
var _home_transform: Transform3D
## The home eye in 64-bit: the transform's origin is only its 32-bit shadow, and a
## deep view's eye differs from it by far more than the zoom floor.
var _home_eye := PackedFloat64Array([0.0, 0.0, 0.0])
var _home_speed := 1.0
## The console is docked beside the view in one fullscreen window.
var _docked := false
## Whether the main window was fullscreen when last looked at; a change docks
## or undocks the console.
var _was_fullscreen := false


func _ready() -> void:
	# Normally done by the title menu already; repeated so main.tscn run on its
	# own is scaled too (both calls are no-ops the second time).
	UiScale.apply(get_window())
	WindowGeometry.place_main_window(get_window(), Settings.window_rect(&"main"))
	UiScale.follow_size(get_window(), WINDOW_SIZE)
	params = FractalParams.new()
	camera = CameraState.make_default()
	_remember_home()

	_table = AttributeTable.new(ShapeCatalogue.specs())
	_keymap = Keymap.new()
	_keymap.load_file()   # saves/keymap.json, or the shipped default

	view.setup(params, camera)
	governor.setup(params, view)
	governor.shed_level_changed.connect(_on_shed_level_changed)
	fly.setup(params, camera, view.center_ray())

	_orbit = get_node_or_null("OrbitCamera")
	if _orbit:
		_orbit.setup(params, camera, view)
	_marker = get_node_or_null("JuliaMarker")
	if _marker:
		_marker.setup(params, camera, view, _table)

	_build_clock()
	_build_console()
	_build_axis_controller()

	# Each window is its own viewport, embedded or not; typing in any of them
	# must silence WASD and the axis keys. (The noise window joins when built.)
	fly.set_text_viewports(_focus_viewports())

	_build_workspace_files()
	_build_view_pane()
	_build_noise_window()

	# The sensitivity is the player's, not the view's: Settings owns it.
	params.mouse_sensitivity = Settings.mouse_sensitivity
	_view_pane.set_sensitivity(Settings.mouse_sensitivity)
	view.show_probe = Settings.show_center_ray
	Settings.changed.connect(_on_settings_changed)
	params.changed.connect(_sync_sensitivity_to_settings)

	_ctrl.typing_guard = func() -> bool: return TextFocus.any(_focus_viewports())

	params.changed.connect(_apply_mode)
	camera.changed.connect(func(): governor.mark_changed())
	_resolve_once()
	_apply_mode()
	# After follow_size's handler, so a resize has refitted the scale first.
	get_window().size_changed.connect(_on_window_resized)
	_was_fullscreen = _is_fullscreen()
	if _was_fullscreen:
		set_docked(true)
	if OPEN_CONSOLE_AT_START:
		# Deferred so the main window has its final size and place to sit beside.
		_open_console_at_start.call_deferred()


func workspace_files() -> WorkspaceFiles:
	return _files


func view_pane() -> ViewPane:
	return _view_pane


func noise_window() -> NoiseWindow:
	return _noise


func console() -> ConsoleWindow:
	return _console


func table() -> AttributeTable:
	return _table


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
	_console.setup(_table, _keymap, _clock, ShapeCatalogue.group_tooltips(),
		func() -> float: return camera.speed_factor)
	add_child(_console)
	_console.toggle_requested.connect(_on_console_toggle)
	_console.unhandled_key.connect(_on_window_key)
	_console.game_focus_requested.connect(return_to_game)
	# The zoom is the player's, like the sensitivity: Settings keeps it.
	_console.set_zoom(Settings.console_zoom)
	_console.zoom_changed.connect(func(z: float): Settings.console_zoom = z)
	_console.reset_camera_requested.connect(reset_camera)
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


func _toggle_noise() -> void:
	_noise.toggle()
	_update_mouse()


func _build_view_pane() -> void:
	_view_pane = _console.view_pane()
	_view_pane.setup(params)
	_view_pane.show_file(_files.display_name())
	_view_pane.renderer.reset_camera_requested.connect(reset_camera)
	_view_pane.menu_requested.connect(back_to_menu)
	_view_pane.save_requested.connect(_files.prompt_save)
	_view_pane.load_requested.connect(_files.prompt_load)
	_view_pane.noise_requested.connect(_open_noise)
	_view_pane.sensitivity_changed.connect(func(v: float): Settings.mouse_sensitivity = v)
	# Deferred: docking hides and re-makes the console, which must not happen
	# inside the console's own click.
	_view_pane.fullscreen_requested.connect(toggle_fullscreen, CONNECT_DEFERRED)
	_view_pane.reset_window_requested.connect(reset_window, CONNECT_DEFERRED)


## Show the console beside the main window, then hand focus back to the main
## window so flying starts as it would with the console closed.
func _open_console_at_start() -> void:
	_console.open()
	get_window().grab_focus()


## The View tab's Noise editor button: open it (the mouse is already free).
func _open_noise() -> void:
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
## stops at the console's left edge; otherwise it fills the window.
func _layout_view() -> void:
	var right := 0.0
	if _docked and _console.visible:
		right = -float(_dock_rect().size.x)
	for c in [view, _marker]:
		if c != null:
			c.offset_right = right


func _reopen_console() -> void:
	if not _docked and not _console.visible:
		_console.open()


func _after_window_settles(then: Callable) -> void:
	get_tree().create_timer(WINDOW_SETTLE_DELAY).timeout.connect(then)


func back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_settings_changed() -> void:
	params.mouse_sensitivity = Settings.mouse_sensitivity
	_view_pane.set_sensitivity(Settings.mouse_sensitivity)
	view.show_probe = Settings.show_center_ray


func _sync_sensitivity_to_settings() -> void:
	if not _loading:
		Settings.mouse_sensitivity = params.mouse_sensitivity


func _on_file_current_changed(display_name: String) -> void:
	if _view_pane != null:
		_view_pane.show_file(display_name)


func _build_workspace_files() -> void:
	_files = WorkspaceFiles.new()
	_files.name = "WorkspaceFiles"
	add_child(_files)
	_files.save_to.connect(save_view_to)
	_files.load_from.connect(load_view_from)
	_files.current_changed.connect(_on_file_current_changed)
	_files.prompting.connect(_on_prompting)
	var directory := WorkspaceFiles.directory()
	if directory != WorkspaceFiles.REPO_DIR:
		_report("Saves go to %s: this build cannot write into the project." % directory)
	elif WorkspaceFiles.ensure_directory() != OK:
		_report("Could not create %s; the file panel opens at your home folder." % directory)


# ------------------------------------------------------------- per-frame

func _process(_delta: float) -> void:
	_resolve_once()
	# The fly camera's zoom limit reaches the Movement pane the way the shed
	# level does, polled since it can change on any physics tick; so does the
	# view's perturbed iteration count.
	if _console != null:
		_console.show_zoom_limit(fly.at_zoom_limit)
		_console.show_deep(view.pert_iters())


## Resolve the shape table + axis values + clock into params, and feed the
## console's readouts (the rows and the Shape tab's self-similarity line).
## Cheap (about thirty scalars); apply_resolved emits at most once, and nothing
## when no binding is active.
func _resolve_once() -> void:
	var values := BindingResolver.resolve(_table, _keymap.axes().values(), _clock.t)
	params.apply_resolved(values)
	if _console != null and _console.visible:
		_console.set_resolved(values)
		_console.show_self_similarity(ShapeCatalogue.self_similarity(
			values, NoiseCompiler.displaces(view.noise_graph())))


# ------------------------------------------------------------- save / load

func save_view_to(path: String) -> void:
	var noise: Dictionary = _noise.to_dict() if _noise != null else {}
	var err := Workspace.save_file(path, _table, _keymap.axes(), params, camera, noise)
	if err != OK:
		_report("Save failed (error %d): %s" % [err, path])
		return
	_files.note_saved(path)
	_remember_home()
	_report("Saved %s" % path.get_file())


func load_view_from(path: String) -> void:
	_loading = true
	var result := Workspace.load_file(path, _table, _keymap.axes(), params, camera)
	_loading = false
	params.mouse_sensitivity = Settings.mouse_sensitivity
	var warnings: Array = result["warnings"]
	if not result["ok"]:
		_report("Load failed: %s" % warnings[0])
		return
	_files.note_loaded(path)
	_remember_home()
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


## Put the camera (and its speed factor) back where the current file has it, or
## at the starting view while no file is current. In Orbit, re-centre on what
## the camera now looks at.
func reset_camera() -> void:
	camera.transform = _home_transform
	# the transform alone can leave the doubles behind (a move below the 32-bit grid
	# keeps the same transform), so put the 64-bit eye back explicitly
	camera.set_eye64(_home_eye[0], _home_eye[1], _home_eye[2])
	camera.speed_factor = _home_speed
	if _orbit and params.camera_mode == FractalParams.CameraMode.ORBIT:
		_orbit.enter()
	var file_name := _files.display_name() if _files != null else ""
	_report("Camera reset to %s" % (file_name if file_name != "" else "the starting view"))


func _remember_home() -> void:
	_home_transform = camera.transform
	_home_eye = camera.eye64()
	_home_speed = camera.speed_factor


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
	if _view_pane != null:
		_view_pane.show_status(line)


## A file panel is opening (possibly from Cmd+S with the mouse captured): free
## the mouse so the panel can be used.
func _on_prompting() -> void:
	_free_requested = true
	_update_mouse()


# ------------------------------------------------------------- mouse / mode

func _apply_mode() -> void:
	var is_fly := params.camera_mode == FractalParams.CameraMode.FLY
	fly.enabled = is_fly
	if _orbit:
		_orbit.enabled = not is_fly
		if not is_fly and params.camera_mode != _last_mode:
			_orbit.enter()
	_last_mode = params.camera_mode
	_update_mouse()


func _update_mouse() -> void:
	_captured = params.camera_mode == FractalParams.CameraMode.FLY \
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
	if _captured:
		_free_requested = true
		if not _console.visible:
			_console.open()
	else:
		_console.toggle()
		if not _console.visible:
			_free_requested = false
	_update_mouse()


## WASD pressed in the console or the noise window: give the main window
## keyboard focus and, as a click in the view would, close the noise editor and
## recapture the mouse, so the key that asked flies.
func return_to_game() -> void:
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


# The only mouse dispatcher: Ctrl tap -> Escape/screenshot -> noise -> marker -> camera.
func _unhandled_input(event: InputEvent) -> void:
	# 1. A Ctrl tap (down then up with no other key between) toggles the console.
	if _ctrl.feed(event):
		_on_console_toggle()
		get_viewport().set_input_as_handled()
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

	# 2. Julia marker drag, only while the mouse is free
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
	# editor, and LEAVE the console open, so its readouts stay in sight while
	# flying. (A click on the console or noise window is that window's; it never
	# gets here.)
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and params.camera_mode == FractalParams.CameraMode.FLY \
			and not _captured:
		_free_requested = false
		if _noise != null:
			_noise.close()
		_update_mouse()
		get_viewport().set_input_as_handled()
		return

	# 4. the active camera handles the rest (look when captured, wheel, orbit drags)
	var cam_node := _active_camera()
	if cam_node and cam_node.handle_event(event):
		get_viewport().set_input_as_handled()
