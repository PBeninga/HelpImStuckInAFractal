extends Node
## Handles a diagnostic shortcut before focused Controls consume it.
var toggle: Callable
var shortcut_key: Key

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == shortcut_key or event.physical_keycode == shortcut_key):
		toggle.call()
		get_viewport().set_input_as_handled()
