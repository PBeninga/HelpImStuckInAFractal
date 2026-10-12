class_name TestCase
extends SceneTree
## Base for headless tests. Subclass, override `run()`, and call the checks.
##
##   godot4 --headless --path . -s tests/<name>_test.gd
##
## `run()` may `await`. `finish()` prints a summary and quits with 0 or 1.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	# Most suites need a fresh, unsaved scene independent of the team's chosen
	# opening level. Startup tests explicitly restore or replace this setting.
	ProjectSettings.set_setting("application/run/default_level", "")
	await run()
	finish()


## Override. Put every check in here.
func run() -> void:
	pass


func check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func check_approx(actual: float, expected: float, message: String, eps: float = 1e-4) -> void:
	check(absf(actual - expected) <= eps, "%s (expected %s, got %s)" % [message, expected, actual])


## Wait `n` process frames.
func frames(n: int) -> void:
	for i in n:
		await process_frame


## Hold an input action down for `seconds` of process time.
func hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time()
	Input.action_release(action)
	await process_frame


## Send a press+release of an action through the event pipeline, so that
## `_input` / `_unhandled_input` handlers see it (Input.action_press does not).
func press_action(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func finish() -> void:
	var name: String = get_script().resource_path.get_file()
	if _failures == 0:
		print("%s PASSED (%d checks)" % [name, _checks])
		quit(0)
	else:
		print("%s FAILED (%d of %d checks)" % [name, _failures, _checks])
		quit(1)
