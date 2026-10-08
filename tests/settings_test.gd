extends "res://tests/test_case.gd"
## The Settings autoload (sensitivity and console zoom) clamps, signals, and round-trips through its file.

const TMP := "user://settings_test.cfg"


func run() -> void:
	var settings: Node = root.get_node("Settings")
	check(settings != null, "Settings is autoloaded")
	var original: float = settings.mouse_sensitivity
	var original_zoom: float = settings.console_zoom
	settings.config_path = TMP

	var fired := [0]
	settings.changed.connect(func(): fired[0] += 1)
	settings.mouse_sensitivity = 0.25
	check_eq(fired[0], 1, "a change emits changed")
	settings.mouse_sensitivity = 0.25
	check_eq(fired[0], 1, "setting the same value does not")
	settings.mouse_sensitivity = 5.0
	check_approx(settings.mouse_sensitivity, settings.SENSITIVITY_MAX, "clamped to the max")
	settings.mouse_sensitivity = 0.0
	check_approx(settings.mouse_sensitivity, settings.SENSITIVITY_MIN, "clamped to the min")

	settings.mouse_sensitivity = 0.3
	await frames(1)   # the deferred save
	check(FileAccess.file_exists(TMP), "a change is written to disk")
	settings.mouse_sensitivity = 0.05
	settings.load_settings()
	check_approx(settings.mouse_sensitivity, 0.3, "loading restores the saved value")

	# the console zoom clamps and round-trips the same way
	settings.console_zoom = 9.0
	check_approx(settings.console_zoom, settings.CONSOLE_ZOOM_MAX, "the console zoom is clamped")
	settings.console_zoom = 1.25
	await frames(1)
	settings.console_zoom = 1.0
	settings.load_settings()
	check_approx(settings.console_zoom, 1.25, "loading restores the console zoom")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	settings.load_settings()   # a missing file leaves the value alone
	check_approx(settings.mouse_sensitivity, 0.3, "a missing file changes nothing")

	settings.mouse_sensitivity = original
	settings.console_zoom = original_zoom
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
