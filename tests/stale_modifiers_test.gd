extends "res://tests/test_case.gd"
## Cmd+Shift+5 (macOS screen recording) takes keyboard focus mid-chord. Godot
## clears its held keys when the window loses focus, then delivers the Cmd and
## Shift presses it had already queued, and the key-ups go to the screenshot
## toolbar, so Input still holds Cmd and Shift when the game has focus again.

const SETTINGS := "user://stale_modifiers_test_settings.cfg"


func _modifier(keycode: int, pressed: bool, location := KEY_LOCATION_LEFT) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.location = location
	ev.pressed = pressed
	return ev


## A W press as the OS sends it once the chord is over: no modifier flags.
func _w(echo := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	ev.echo = echo
	return ev


## The state Cmd+Shift+5 leaves behind: Cmd and Shift held as far as Input knows.
func _stick_cmd_shift() -> void:
	Input.parse_input_event(_modifier(KEY_META, true))
	Input.parse_input_event(_modifier(KEY_SHIFT, true))
	Input.flush_buffered_events()


func _release_all() -> void:
	for key in [KEY_META, KEY_SHIFT, KEY_CTRL, KEY_ALT]:
		for loc in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
			Input.parse_input_event(_modifier(key, false, loc))
	Input.flush_buffered_events()


func run() -> void:
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var fly := FlyCamera.new()
	root.add_child(fly)
	fly.setup(params, cam)

	# --- the bug: stuck Cmd stops WASD, stuck Shift sprints ---
	_stick_cmd_shift()
	check(Input.is_key_pressed(KEY_META), "setup: Input believes Cmd is held")
	check(Input.is_action_pressed(&"sprint"), "setup: and a left Shift holds sprint")

	# --- a W press whose flags say no modifier is held releases them ---
	StaleModifiers.release(_w())
	Input.flush_buffered_events()
	check(not Input.is_key_pressed(KEY_META), "a W press without the Cmd flag releases Cmd")
	check(not Input.is_key_pressed(KEY_SHIFT), "and Shift")
	check(not Input.is_action_pressed(&"sprint"), "and stops the sprint")
	Input.action_press(&"move_forward")
	var dir := fly.move_direction()
	Input.action_release(&"move_forward")
	check(dir.is_equal_approx(cam.forward()), "W flies forward again (got %s)" % dir)

	# --- a right-hand modifier is released too ---
	Input.parse_input_event(_modifier(KEY_SHIFT, true, KEY_LOCATION_RIGHT))
	Input.flush_buffered_events()
	StaleModifiers.release(_w())
	Input.flush_buffered_events()
	check(not Input.is_key_pressed(KEY_SHIFT), "a stuck right Shift is released")

	# --- a held W repeating (echo) after focus comes back also fixes it ---
	_stick_cmd_shift()
	StaleModifiers.release(_w(true))
	Input.flush_buffered_events()
	check(not Input.is_key_pressed(KEY_META), "an echo W without the Cmd flag releases Cmd")

	# --- a modifier that really is held stays held ---
	_stick_cmd_shift()
	var cmd_s := InputEventKey.new()
	cmd_s.keycode = KEY_S
	cmd_s.physical_keycode = KEY_S
	cmd_s.pressed = true
	cmd_s.meta_pressed = true
	cmd_s.shift_pressed = true
	StaleModifiers.release(cmd_s)
	Input.flush_buffered_events()
	check(Input.is_key_pressed(KEY_META), "Cmd+Shift+S leaves Cmd held")
	check(Input.is_key_pressed(KEY_SHIFT), "and Shift")

	# --- a modifier's own event leaves out its own flag: not a sign it is stale ---
	var shift_down := _modifier(KEY_SHIFT, true)
	shift_down.meta_pressed = true
	StaleModifiers.release(shift_down)
	Input.flush_buffered_events()
	check(Input.is_key_pressed(KEY_META), "a Shift press under Cmd leaves Cmd held")
	var cmd_down := _modifier(KEY_META, true)
	StaleModifiers.release(cmd_down)
	Input.flush_buffered_events()
	check(Input.is_key_pressed(KEY_SHIFT), "a Cmd press (flags without Shift) leaves Shift held")

	# --- a key release is not used: the Ctrl tap must not fire on a synthetic Ctrl-up ---
	_release_all()
	Input.parse_input_event(_modifier(KEY_CTRL, true))
	Input.flush_buffered_events()
	var w_up := _w()
	w_up.pressed = false
	StaleModifiers.release(w_up)
	Input.flush_buffered_events()
	check(Input.is_key_pressed(KEY_CTRL), "a key release leaves a stuck modifier for the next press")

	# --- Main runs it on the main window's keys ---
	_release_all()
	var settings: Node = root.get_node("Settings")
	settings.config_path = SETTINGS
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	# Headless, the console is embedded and takes the keys; on the desktop it is
	# a window of its own and the main window has focus.
	main.console().hide()
	await frames(1)
	_stick_cmd_shift()
	root.push_input(_w(), true)
	await frames(1)
	Input.flush_buffered_events()
	check(not Input.is_key_pressed(KEY_META), "a W press in the main window releases a stuck Cmd")
	check(not Input.is_key_pressed(KEY_SHIFT), "and a stuck Shift")
	_release_all()
	main.queue_free()
	await frames(1)
	for action in [&"axis_a_pos", &"axis_a_neg"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
