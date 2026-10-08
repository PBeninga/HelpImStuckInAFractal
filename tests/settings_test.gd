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

	# window places: remembered by key, polled from tracked windows, round-tripped
	check(not settings.is_processing(), "headless never polls the windows on its own")
	check_eq(settings.window_rect(&"nowhere"), Rect2i(), "a window never seen has no place")
	settings.set_window_rect(&"main", Rect2i(100, 200, 2444, 1580))
	settings.set_window_rect(&"console", Rect2i(2600, 200, 2000, 1400))
	await frames(1)
	settings.forget_window_rects()
	check_eq(settings.window_rect(&"main"), Rect2i(), "forget clears every place")
	settings.load_settings()
	check_eq(settings.window_rect(&"main"), Rect2i(100, 200, 2444, 1580), "loading restores the main window's place")
	check_eq(settings.window_rect(&"console"), Rect2i(2600, 200, 2000, 1400), "and the console's")

	# The root is native even headless, but headless reports it minimised after
	# the first frame, and a minimised window's rect is not its place.
	settings.track_window(&"root", root)
	var embedded := Window.new()
	embedded.size = Vector2i(300, 200)
	root.add_child(embedded)
	settings.track_window(&"embedded", embedded)
	settings.poll_windows()
	if root.mode == Window.MODE_WINDOWED:
		check_eq(settings.window_rect(&"root"), Rect2i(root.position, root.size), "a poll records a native window's rect")
	else:
		check_eq(settings.window_rect(&"root"), Rect2i(), "a poll skips a window that is not windowed")
	check_eq(settings.window_rect(&"embedded"), Rect2i(), "but never an embedded one's")
	embedded.free()
	settings.poll_windows()
	check(not settings._tracked.has(&"embedded"), "a freed window is dropped from the poll")
	settings._tracked.erase(&"root")
	settings.forget_window_rects()
	await frames(1)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	settings.load_settings()   # a missing file leaves the value alone
	check_approx(settings.mouse_sensitivity, 0.3, "a missing file changes nothing")

	settings.mouse_sensitivity = original
	settings.console_zoom = original_zoom
	await frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
