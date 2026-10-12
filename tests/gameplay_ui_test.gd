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
	var radius: DecimalSpinBox = pane.controls[&"exit_radius"]
	check(await ui.scroll_to(pane, radius), "the exit radius control is reachable")
	await ui.type_text(radius.get_line_edit(), "0.0001")
	check_eq(game.exit_radius, 0.0001, "typing a tiny radius updates gameplay without rounding")
	await ui.type_text(radius.get_line_edit(), "0")
	check_eq(game.exit_radius, 0.0001, "zero cannot remove the sphere")
	check_eq(radius.value, 0.0001, "a rejected value restores the displayed radius")
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
	console.queue_free()
	clock.queue_free()
	await ui.frames(1)
