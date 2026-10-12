class_name StaleModifiers
extends RefCounted
## Releases a modifier Input still holds after the real key came up elsewhere.
## A macOS shortcut such as Cmd+Shift+5 (screen recording) takes keyboard focus
## mid-chord: Godot clears its held keys when the window loses focus, then
## delivers the Cmd and Shift presses it had already queued, and the key-ups go
## to the screenshot toolbar. A stuck Cmd stops the fly camera (nothing moves
## under Cmd, so Cmd+S can save) and a stuck Shift sprints.
##
## Every key press from the OS carries the true modifier flags, so release()
## compares them with Input's and releases what is no longer held, left and
## right (Input does not say which side it holds). Presses only: a press
## disarms the Ctrl tap first, so the synthetic Ctrl-up cannot fire one.

## Modifier keycode -> the InputEventWithModifiers flag that reports it.
const FLAGS := {
	KEY_META: &"meta_pressed",
	KEY_SHIFT: &"shift_pressed",
	KEY_CTRL: &"ctrl_pressed",
	KEY_ALT: &"alt_pressed",
}


static func release(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	# A modifier's own event leaves out its own flag (macOS clears it), so it
	# cannot say the others are up either; the next ordinary key will.
	if FLAGS.has(k.keycode) or FLAGS.has(k.physical_keycode):
		return
	for key: Key in FLAGS:
		if Input.is_key_pressed(key) and not k.get(FLAGS[key]):
			for loc in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
				var up := InputEventKey.new()
				up.keycode = key
				up.physical_keycode = key
				up.location = loc
				up.window_id = k.window_id
				Input.parse_input_event(up)
