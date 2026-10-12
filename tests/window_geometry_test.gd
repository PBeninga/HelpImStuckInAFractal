extends "res://tests/test_case.gd"
## WindowGeometry: a first-run main window covers half its screen's pixels,
## centred under the title bar; a remembered rect is put back only while it is
## still on a screen; the docked console's width stays within its bounds; and
## place_main_window() places a default-sized window once.


func run() -> void:
	# --- default_rect: half the pixels, the screen's shape, centred ---
	# A 3456x2234 Retina panel whose usable rect loses a 74 px menu bar.
	var screen := Vector2i(3456, 2234)
	var usable := Rect2i(0, 74, 3456, 2160)
	var r := WindowGeometry.default_rect(screen, usable, 56)
	check_eq(r.size, Vector2i(2444, 1580), "each side is sqrt(1/2) of the screen's")
	var area := float(r.size.x * r.size.y) / float(screen.x * screen.y)
	check_approx(area, 0.5, "so the window covers half the screen's pixels", 0.002)
	check_eq(r.position.x, (3456 - 2444) / 2, "centred across")
	check_eq(r.position.y, 74 + 56 + (2160 - 56 - 1580) / 2, "and down, under the title bar")
	check(usable.encloses(Rect2i(r.position - Vector2i(0, 56), r.size + Vector2i(0, 56))),
		"title bar included, it fits the usable rect")

	# A second monitor to the right, offset on the desktop.
	var right := WindowGeometry.default_rect(Vector2i(2560, 1440), Rect2i(3456, 0, 2560, 1415), 28)
	check_eq(right.size, Vector2i(1810, 1018), "a 2560x1440 monitor gets 1810x1018")
	check(Rect2i(3456, 0, 2560, 1415).encloses(right), "on that monitor")

	# A usable rect too short for the shape shrinks the window to fit.
	var short := WindowGeometry.default_rect(Vector2i(2000, 2000), Rect2i(0, 0, 2000, 1000), 20)
	check_eq(short.size.y, 980, "a short usable rect caps the height")
	check_eq(short.position.y, 20, "under the title bar")

	# --- restorable: still on a connected screen ---
	var screens: Array[Rect2i] = [Rect2i(0, 74, 3456, 2160), Rect2i(3456, 0, 2560, 1415)]
	check(WindowGeometry.restorable(Rect2i(200, 300, 2000, 1200), screens), "a window on the laptop screen")
	check(WindowGeometry.restorable(Rect2i(4000, 200, 1500, 900), screens), "a window on the second monitor")
	check(WindowGeometry.restorable(Rect2i(3000, 200, 1500, 900), screens), "one straddling the two")
	check(not WindowGeometry.restorable(Rect2i(7000, 200, 1500, 900), screens),
		"not one on a monitor that is no longer there")
	check(not WindowGeometry.restorable(Rect2i(200, 2200, 1500, 900), screens),
		"not one whose title bar is below every screen")
	check(not WindowGeometry.restorable(Rect2i(200, 20, 1500, 900), [Rect2i(0, 74, 3456, 2160)] as Array[Rect2i]),
		"not one whose top edge is above the usable area")
	check(not WindowGeometry.restorable(Rect2i(3400, 300, 1500, 900), [screens[0]] as Array[Rect2i]),
		"not one with only a sliver left on the screen")
	check(not WindowGeometry.restorable(Rect2i(), screens), "not the empty rect (never remembered)")
	check(not WindowGeometry.restorable(Rect2i(200, 300, 2000, 1200), [] as Array[Rect2i]),
		"not with no screens (headless)")

	# --- dock_width: 40 %, at least the console's minimum, at most 60 % ---
	check_approx(WindowGeometry.dock_width(2560.0), 1024.0, "40 % of a wide screen")
	check_approx(WindowGeometry.dock_width(1728.0), 700.0, "a laptop screen gets the console's minimum")
	check_approx(WindowGeometry.dock_width(1000.0), 600.0, "a narrow window keeps 40 % for the view")

	# --- place_main_window: once, only at the project's default pixel size ---
	# Headless has no screen to measure, so a default window keeps its point size.
	UiScale.override = 2.0
	var default_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var resized := Window.new()
	resized.size = Vector2i(900, 600)
	WindowGeometry.place_main_window(resized)
	check_eq(resized.size, Vector2i(900, 600), "a window the player resized is left alone")
	resized.free()
	var main_window := Window.new()
	main_window.size = default_size
	WindowGeometry.place_main_window(main_window, Rect2i(200, 300, 2000, 1200))
	check_eq(main_window.size, Vector2i(2560, 1600),
		"with no screen to measure, a default-sized window keeps its point size (the remembered rect is off every screen)")
	main_window.size = default_size
	WindowGeometry.place_main_window(main_window)
	check_eq(main_window.size, default_size, "the placing happens once per process")
	main_window.free()
	UiScale.override = 0.0
