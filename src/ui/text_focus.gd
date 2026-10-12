class_name TextFocus
extends RefCounted
## Is a text-entry control focused in any of the given viewports? The main
## window, the console and the noise window are separate viewports (each
## Window is its own viewport, even embedded), so the axis controller and the
## fly camera ask about all of them: typing "e" into a spin box must never move
## an axis or the camera. is_game_key() is the other side: which W, A, S or D
## presses in the console or the noise window mean "back to the game".

## The move actions (W, A, S, D) whose press hands focus back to the game.
const GAME_KEY_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]


## True when a LineEdit or TextEdit holds keyboard focus in any viewport.
static func any(viewports: Array) -> bool:
	for vp in viewports:
		if vp == null:
			continue
		var owner := (vp as Viewport).gui_get_focus_owner()
		if owner is LineEdit or owner is TextEdit:
			return true
	return false


## Whether `event` is a plain W, A, S or D press (the move actions) that should
## leave `vp` for the game: anything but a key typed into a free-text field
## mid-edit (an axis label). A spin box's field takes numbers, so a letter there
## leaves. Cmd, Ctrl and Alt chords are never moves (Cmd+S saves); Shift is
## sprint and passes.
static func is_game_key(event: InputEvent, vp: Viewport) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return false
	if not GAME_KEY_ACTIONS.any(func(a: StringName) -> bool: return k.is_action_pressed(a)):
		return false
	var owner := vp.gui_get_focus_owner()
	if owner is TextEdit:
		return false
	if owner is LineEdit:
		return owner.get_parent() is SpinBox or not (owner as LineEdit).is_editing()
	return true
