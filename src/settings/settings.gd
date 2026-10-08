extends Node
## Player preferences that belong to the player rather than to a saved view:
## the mouse sensitivity and the console's zoom. Autoloaded as `Settings` and kept in
## user://settings.cfg, so it survives restarts and is not overwritten by
## loading a view.

signal changed

const DEFAULT_PATH := "user://settings.cfg"
const SENSITIVITY_MIN := 0.02
const SENSITIVITY_MAX := 0.5
const SENSITIVITY_DEFAULT := 0.1
const CONSOLE_ZOOM_MIN := 0.5
const CONSOLE_ZOOM_MAX := 2.0

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

var _save_queued := false


func _ready() -> void:
	load_settings()


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
	_save_queued = false   # what was just read is already on disk


func save_settings() -> Error:
	_save_queued = false
	var cfg := ConfigFile.new()
	cfg.set_value("mouse", "sensitivity", mouse_sensitivity)
	cfg.set_value("console", "zoom", console_zoom)
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
