class_name Keymap
extends RefCounted
## Maps each virtual axis to a pair of physical keys, owns the Axes, and keeps
## two InputMap actions per axis (`axis_<id>_pos` / `axis_<id>_neg`) equal to
## the pair. Keys are physical keycodes, so key names are layout-independent. The
## keymap has no file of its own: the keys and axes travel inside the level save
## (Workspace), which reads this through `to_list()` / `apply_list()`. At boot it
## holds the shipped default (`reset_to_default`) until a level is loaded.

signal changed

var _axes := Axes.new()
## id -> {"positive": int, "negative": int} physical keycodes (KEY_NONE = none).
var _pairs: Dictionary = {}


func axes() -> Axes:
	return _axes


## id -> {positive, negative} physical keycodes.
func pairs() -> Dictionary:
	return _pairs


func positive_key(id: StringName) -> int:
	return int(_pairs.get(id, {}).get("positive", KEY_NONE))


func negative_key(id: StringName) -> int:
	return int(_pairs.get(id, {}).get("negative", KEY_NONE))


func add_axis(id: StringName, label: String, speed: float, positive: int, negative: int) -> void:
	if _axes.has(id):
		push_warning("Keymap.add_axis: duplicate id '%s'" % id)
		return
	_axes.add(id, label, speed)
	_pairs[id] = {"positive": positive, "negative": negative}
	_register_actions(id)
	changed.emit()


func remove_axis(id: StringName) -> void:
	if not _axes.has(id):
		return
	_erase_actions(id)
	_pairs.erase(id)
	_axes.remove(id)
	changed.emit()


## Repoint an axis's key pair. Either key may be KEY_NONE.
func bind(id: StringName, positive: int, negative: int) -> void:
	if not _axes.has(id):
		return
	_pairs[id] = {"positive": positive, "negative": negative}
	_register_actions(id)
	changed.emit()


func set_speed(id: StringName, units_per_second: float) -> void:
	_axes.set_speed(id, units_per_second)
	changed.emit()


func set_label(id: StringName, text: String) -> void:
	_axes.set_label(id, text)
	changed.emit()


func pos_action(id: StringName) -> StringName:
	return StringName("axis_%s_pos" % id)


func neg_action(id: StringName) -> StringName:
	return StringName("axis_%s_neg" % id)


# --------------------------------------------------------------- InputMap

func _register_actions(id: StringName) -> void:
	_set_action(pos_action(id), positive_key(id))
	_set_action(neg_action(id), negative_key(id))


func _set_action(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	if keycode != KEY_NONE:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		InputMap.action_add_event(action, ev)


func _erase_actions(id: StringName) -> void:
	for action in [pos_action(id), neg_action(id)]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)


# ----------------------------------------------- level save (to/from a list)

## This keymap's axes as a list of entries for a level save:
## {id, label, speed, positive, negative, value}. Keys are stored by name
## (`OS.get_keycode_string`), with "" for an unbound key (KEY_NONE).
func to_list() -> Array:
	var entries: Array = []
	for a in _axes.list():
		entries.append({
			"id": String(a.id),
			"label": a.label,
			"speed": a.speed,
			"positive": _key_name(positive_key(a.id)),
			"negative": _key_name(negative_key(a.id)),
			"value": a.value,
		})
	return entries


## Replace every axis with the level's entries, rebinding through `add_axis` so
## the InputMap actions follow (clear all, then add each). Lenient: a malformed
## entry, or one with a missing or duplicate id, is skipped with a warning.
## Returns the warnings.
func apply_list(entries: Array) -> Array:
	var warnings: Array = []
	_clear_all()
	for entry in entries:
		if not (entry is Dictionary):
			warnings.append("Skipped a malformed axis entry")
			continue
		var id := StringName(str(entry.get("id", "")))
		if id == &"" or _axes.has(id):
			warnings.append("Skipped an axis with a missing or duplicate id")
			continue
		var label := str(entry.get("label", String(id)))
		var speed := float(entry.get("speed", 1.0))
		var pos := _key_from_name(str(entry.get("positive", "")))
		var neg := _key_from_name(str(entry.get("negative", "")))
		add_axis(id, label, speed, pos, neg)
		var v: Variant = entry.get("value", 0.0)
		if v is float or v is int:
			_axes.set_value(id, float(v))
		else:
			warnings.append("Malformed value for axis '%s' ignored" % id)
	return warnings


## Put the keys and axes back to the shipped default: one axis "a" on E / Q.
func reset_to_default() -> void:
	_clear_all()
	add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)


func _clear_all() -> void:
	for id in _axes.ids():
		_erase_actions(id)
	_pairs.clear()
	_axes.clear()


static func _key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode != KEY_NONE else ""


static func _key_from_name(name: String) -> int:
	if name == "":
		return KEY_NONE
	var code := OS.find_keycode_from_string(name)
	return code if code != KEY_NONE else KEY_NONE
