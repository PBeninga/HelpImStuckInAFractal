extends Node
## Player preferences that belong to the player rather than to a saved view:
## the mouse sensitivity, the console's zoom, whether the centre-ray probe
## dot is shown, and where the main window and the console last sat on the
## desktop. Autoloaded as `Settings` and kept in
## user://settings.cfg, so it survives restarts and is not overwritten by
## loading a view.
##
## Window places: a window has no "moved" signal, so the windows handed to
## track_window() (the main window always) are polled a few times a second, and
## a changed rect is remembered while the window is a visible, native, windowed
## OS window (never while fullscreen, maximised or embedded). Headless and the
## web skip the poll: a test's 64x64 root must never become the player's
## window.

signal changed

const DEFAULT_PATH := "user://settings.cfg"
const SENSITIVITY_MIN := 0.02
const SENSITIVITY_MAX := 0.5
const SENSITIVITY_DEFAULT := 0.1
const CONSOLE_ZOOM_MIN := 0.5
const CONSOLE_ZOOM_MAX := 2.0
## Seconds between looks at the tracked windows.
const WINDOW_POLL_INTERVAL := 0.5

## Tests point this somewhere else so they never touch the player's file.
var config_path := DEFAULT_PATH

var mouse_sensitivity := SENSITIVITY_DEFAULT:
	set(v):
		v = clampf(v, SENSITIVITY_MIN, SENSITIVITY_MAX)
		if is_equal_approx(v, mouse_sensitivity):
			return
		mouse_sensitivity = v
		changed.emit()
		_queue_save()

## The console window's zoom (see ConsoleWindow.ZOOM_STEPS).
var console_zoom := 1.0:
	set(v):
		v = clampf(v, CONSOLE_ZOOM_MIN, CONSOLE_ZOOM_MAX)
		if is_equal_approx(v, console_zoom):
			return
		console_zoom = v
		changed.emit()
		_queue_save()

## Paint the centre-ray probe's dot (R toggles it while flying).
var show_center_ray := false:
	set(v):
		if v == show_center_ray:
			return
		show_center_ray = v
		changed.emit()
		_queue_save()

## Each tracked window's last native, windowed place in screen pixels, by key
## (&"main", &"console").
var _window_rects := {}
## key -> WeakRef to the Window being polled.
var _tracked := {}
var _poll_wait := 0.0
var _save_queued := false


func _ready() -> void:
	load_settings()
	var polls := DisplayServer.get_name() != "headless" and not OS.has_feature("web")
	set_process(polls)
	if polls:
		track_window(&"main", get_tree().root)


func _process(delta: float) -> void:
	_poll_wait -= delta
	if _poll_wait <= 0.0:
		_poll_wait = WINDOW_POLL_INTERVAL
		poll_windows()


func _exit_tree() -> void:
	if is_processing():
		poll_windows()
	if _save_queued:
		save_settings()


## Where the window `key` was last left, or an empty rect when it never was.
func window_rect(key: StringName) -> Rect2i:
	return _window_rects.get(key, Rect2i())


func set_window_rect(key: StringName, rect: Rect2i) -> void:
	if _window_rects.get(key, Rect2i()) == rect:
		return
	_window_rects[key] = rect
	_queue_save()


## Forget every window's place, so each opens at its default next time.
func forget_window_rects() -> void:
	if _window_rects.is_empty():
		return
	_window_rects.clear()
	_queue_save()


## Remember `window`'s place under `key` from now on (see poll_windows()).
func track_window(key: StringName, window: Window) -> void:
	_tracked[key] = weakref(window)


## Record each tracked window's rect when it is a visible, native, windowed OS
## window. Windows that have been freed are dropped.
func poll_windows() -> void:
	for key in _tracked.keys():
		var window := (_tracked[key] as WeakRef).get_ref() as Window
		if window == null:
			_tracked.erase(key)
			continue
		if window.visible and window.mode == Window.MODE_WINDOWED and not window.is_embedded():
			set_window_rect(key, Rect2i(window.position, window.size))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	var sens: Variant = cfg.get_value("mouse", "sensitivity", SENSITIVITY_DEFAULT)
	if sens is float or sens is int:
		mouse_sensitivity = float(sens)
	var zoom: Variant = cfg.get_value("console", "zoom", 1.0)
	if zoom is float or zoom is int:
		console_zoom = float(zoom)
	var probe: Variant = cfg.get_value("view", "show_center_ray", false)
	if probe is bool:
		show_center_ray = probe
	if cfg.has_section("window"):
		for key in cfg.get_section_keys("window"):
			var rect: Variant = cfg.get_value("window", key)
			if rect is Rect2i:
				_window_rects[StringName(key)] = rect
	_save_queued = false   # what was just read is already on disk


func save_settings() -> Error:
	_save_queued = false
	var cfg := ConfigFile.new()
	cfg.set_value("mouse", "sensitivity", mouse_sensitivity)
	cfg.set_value("console", "zoom", console_zoom)
	cfg.set_value("view", "show_center_ray", show_center_ray)
	for key in _window_rects:
		cfg.set_value("window", String(key), _window_rects[key])
	return cfg.save(config_path)


## A slider drag changes the value every frame; write the file once at the end
## of the frame instead of on every tick.
func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	if _save_queued:
		save_settings()
