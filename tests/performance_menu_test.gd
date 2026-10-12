extends "res://tests/test_case.gd"
## Catches hidden sampling, incorrect budget math and F3 getting lost in menus.


func key(echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F3
	event.pressed = true
	event.echo = echo
	return event


func run() -> void:
	await frames(1)
	var menu := root.get_node_or_null("PerformanceMenu")
	check(menu != null, "F3 performance menu is available across scenes")
	if menu == null:
		return
	var profiler = load("res://src/perf/frame_profiler.gd")
	check(not menu.visible and not profiler.enabled, "starts hidden with profiling disabled")
	check(not menu.is_processing(), "hidden menu has no polling callback")
	check_eq(profiler.begin(), -1, "hidden scope does not start a timer")
	profiler.record(&"Hidden", 8000.0)
	check(profiler.take_snapshot(1).is_empty(), "hidden work is never recorded")
	root.push_input(key())
	check(menu.visible and profiler.enabled, "F3 opens and enables profiling")
	check(menu.layer < 1024, "overlay stays below embedded console windows")
	check_eq(menu.panel.get_theme_stylebox("panel").bg_color.a, 1.0, "panel is fully opaque")
	root.push_input(key(true))
	check(menu.visible, "key repeat does not close the menu")
	profiler.record(&"Small", 1000.0)
	profiler.record(&"Large", 8000.0)
	profiler.record(&"Large", 2000.0)
	var rows: Array = profiler.take_snapshot(2)
	check_eq(rows[0].name, &"Large", "most expensive operation sorts first")
	check_approx(rows[0].ms, 5.0, "repeated work is averaged over all frames")
	check_approx(rows[0].percent, 30.0, "5 ms is 30 percent of a 60 FPS budget")
	check(profiler.take_snapshot(1).is_empty(), "snapshot starts a fresh sampling interval")

	var main = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	check(menu.measured_viewport == main.view.get_node("SubViewport"), "fractal rendering is measured separately")
	profiler.take_snapshot(1)
	main._resolve_once()
	main.view.center_ray()._mark_dirty()
	main.view.center_ray().distance()
	rows = profiler.take_snapshot(1)
	var names: Array = rows.map(func(row): return row.name)
	check(names.has(&"Bindings + scene updates"), "actual scene update is instrumented")
	check(names.has(&"Console readouts"), "actual console refresh is instrumented")
	check(names.has(&"CPU centre ray"), "actual centre march is instrumented")
	var mirror: CanvasLayer = main.console().get_node_or_null("PerformanceOverlay")
	check(mirror == null, "console has no performance overlay")
	check(menu.get_viewport() == root, "performance overlay belongs to the game window")
	var edit := LineEdit.new()
	main.console().add_child(edit)
	edit.grab_focus()
	main.console().push_input(key())
	check(not menu.visible and not profiler.enabled, "F3 closes even from a focused console text field")
	check(not RenderingServer.frame_post_draw.is_connected(menu._after_draw), "closing disconnects renderer sampling")
	main._resolve_once()
	main.view.center_ray()._mark_dirty()
	main.view.center_ray().distance()
	await frames(2)
	check(profiler.take_snapshot(1).is_empty(), "real work while closed collects no samples")
	main.noise_window().open()
	main.noise_window().push_input(key())
	check(menu.visible and profiler.enabled, "F3 reopens from the noise window")
	await create_timer(0.3).timeout
	check(menu.readout.text.contains("FPS") and menu.readout.text.contains("16.67"), "readout shows FPS and the frame budget")
	check(main.noise_window().get_node_or_null("PerformanceOverlay") == null, "noise window has no performance overlay")
	main.queue_free()
	await frames(2)
	check(menu.measured_viewport == null, "scene exit releases render measurement target")
	menu.hide()
	check(not profiler.enabled and not menu.is_processing(), "hiding by any route stops profiling")
	# A transient window can disappear before deferred shortcut setup runs.
	var transient := Window.new()
	root.add_child(transient)
	transient.free()
	await frames(1)
