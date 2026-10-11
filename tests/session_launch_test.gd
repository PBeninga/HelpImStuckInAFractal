extends "res://tests/test_case.gd"
## SessionLaunch.parks_window: Spellgraft's rules for a Claude-launched window.


func _env(vars: Dictionary) -> Callable:
	return func(name: String) -> String: return vars.get(name, "")


func run() -> void:
	var none := PackedStringArray()
	check(not SessionLaunch.parks_window(none, _env({})), "a person's launch keeps a normal window")
	check(SessionLaunch.parks_window(none, _env({"CLAUDECODE": "1"})), "a Claude session parks it")
	check(not SessionLaunch.parks_window(none, _env({"CLAUDECODE": "1", "FRACTAL_PLAY": "1"})),
		"FRACTAL_PLAY=1 hands it back to a person")
	check(SessionLaunch.parks_window(PackedStringArray(["--background-window"]), _env({})),
		"--background-window parks it anywhere")
	check(not SessionLaunch.parks_window(PackedStringArray(["--foreground-window"]), _env({"CLAUDECODE": "1"})),
		"--foreground-window keeps a normal window in a Claude session")
	check(not SessionLaunch.is_requested(), "never in a headless run")
