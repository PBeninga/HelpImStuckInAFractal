extends "res://tests/test_case.gd"
## The project boots headless, declares GL Compatibility, and has every action.


func run() -> void:
	check_eq(ProjectSettings.get_setting("application/config/name"), "Help I'm Stuck In A Fractal",
		"project name is set")
	var feats: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	check(feats.has("GL Compatibility"), "GL Compatibility is declared")
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"move_up", "move_down", "sprint", "toggle_panel", "cancel"]:
		check(InputMap.has_action(action), "action '%s' exists" % action)
