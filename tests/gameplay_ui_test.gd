extends "res://tests/test_case.gd"
## The new tab driven through real GUI typing/clicks, including tiny values
## and the Return button's keyboard-focus behavior during flight.


func run() -> void:
	var ui := UiDriver.new(self)
	await ui.setup()
	var game := GameplaySettings.new()
	var keys := Keymap.new()
	var clock := Clock.new()
	root.add_child(clock)
	var console := ConsoleWindow.new()
	console.setup(ShapeList.new(), AttributeTable.new(ShapeCatalogue.scene_specs()),
		keys, clock, ShapeCatalogue.group_tooltips())
	root.add_child(console)
	var pane := console.gameplay_pane()
	pane.setup(game)
	console.open()
	await ui.frames(2)
	var bar := console.tabs().get_tab_bar()
	await ui.click_at(ui.control_point(bar, bar.get_tab_rect(4).get_center()))
	check_eq(console.tabs().current_tab, 4, "clicking Gameplay opens the tab")
	check(pane.save_button.is_visible_in_tree() and pane.load_button.is_visible_in_tree(),
		"Save and Load are visible on Gameplay")
	check(not pane.controls.has(&"exit_radius"), "Gameplay no longer exposes an exit radius")
	var spawn: SpinBox = pane.controls[&"spawn_x"]
	check(await ui.scroll_to(pane, spawn), "spawn can be reached by scrolling")
	await ui.type_text(spawn.get_line_edit(), "-1.23456789012345")
	check_approx(game.spawn_x, -1.23456789012345, "typing spawn retains full precision", 1e-14)
	var move: DecimalSpinBox = pane.controls[&"move_speed"]
	check(await ui.scroll_to(pane, move), "movement speed can be reached")
	await ui.type_text(move.get_line_edit(), "0.5")
	check_eq(game.move_speed, 0.5, "typing movement speed updates gameplay")
	var geometry_rays: SpinBox = pane.controls[&"surrounding_ray_count"]
	check(await ui.scroll_to(pane, geometry_rays), "geometry fidelity can be reached")
	geometry_rays.value = 24
	check_eq(game.surrounding_ray_count, 24, "geometry fidelity updates the ray count")
	check(await ui.scroll_to(pane, pane.scaling_check), "distance scaling can be reached")
	await ui.click(pane.scaling_check)
	check(not game.distance_scaling, "the checkbox disables adaptive speed")
	check(not pane.controls[&"distance_power"].editable, "adaptive controls disable with the feature")
	var returns := []
	pane.return_requested.connect(func(): returns.append(true))
	check(await ui.scroll_to(pane, pane.return_button), "Return to spawn is reachable")
	await ui.click(pane.return_button)
	check_eq(returns.size(), 1, "a click requests one return to spawn")
	await ui.tap(KEY_SPACE)
	check_eq(returns.size(), 1, "Space after a return keeps flying rather than returning again")
	var escape_pane := console.escape_animation_pane()
	escape_pane.setup(game)
	await ui.click_at(ui.control_point(bar, bar.get_tab_rect(5).get_center()))
	check_eq(console.tabs().current_tab, 5, "clicking Escape Animation opens the new tab")
	var sky_duration: SpinBox = escape_pane.controls[&"escape_sky_duration"]
	var fog_duration: SpinBox = escape_pane.controls[&"escape_fog_duration"]
	check(sky_duration.is_visible_in_tree() and fog_duration.is_visible_in_tree(), "both fade controls are visible")
	await ui.type_text(sky_duration.get_line_edit(), "1.5")
	await ui.type_text(fog_duration.get_line_edit(), "4")
	check_approx(game.escape_sky_duration, 1.5, "typing sky duration edits the live level")
	check_approx(game.escape_fog_duration, 4.0, "typing fog duration independently edits the live level")
	game.apply_dict({"escape_sky_duration": 0.0, "escape_fog_duration": 2.0})
	check_approx(sky_duration.value, 0.0, "loading updates the sky control, including instant transitions")
	check_approx(fog_duration.value, 2.0, "loading updates the fog control")
	console.queue_free()
	clock.queue_free()
	await ui.frames(1)
