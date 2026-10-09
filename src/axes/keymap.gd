class_name Keymap
extends RefCounted
## Maps each virtual axis to a pair of physical keys, owns the Axes, and keeps
## two InputMap actions per axis (`axis_<id>_pos` / `axis_<id>_neg`) equal to
## the pair. Keys are physical keycodes, stored by name so the JSON file is
## readable and layout-independent. A level can rewrite this at runtime.
##
##   {"version": 1, "axes": [{"id":"a","label":"Axis A","speed":1.0,
##                            "positive":"E","negative":"Q"}]}

signal changed

const VERSION := 1
const DEFAULT_FILE := "keymap.json"

var current_path := ""

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


# --------------------------------------------------------------- files

enum _Load { LOADED, USE_DEFAULT, REFUSED }

## Load a keymap JSON file. A missing or malformed file yields the shipped
## default (one axis on Q/E) with a warning. A saved view (the View tab's file,
## which shares saves/) is refused by name and leaves the keymap in hand, and
## the current path, alone. Returns {ok, warnings}.
func load_file(path: String = "") -> Dictionary:
	if path == "":
		path = _default_path()
	var warnings: Array = []
	var outcome := _load_into(path, warnings)
	if outcome == _Load.REFUSED:
		return {"ok": false, "warnings": warnings}
	if outcome == _Load.USE_DEFAULT:
		_apply_default()
	current_path = path
	return {"ok": outcome == _Load.LOADED, "warnings": warnings}


func _load_into(path: String, warnings: Array) -> _Load:
	if not FileAccess.file_exists(path):
		warnings.append("No keymap at %s; using the default" % path)
		return _Load.USE_DEFAULT
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		warnings.append("Could not read %s; using the default" % path)
		return _Load.USE_DEFAULT
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		warnings.append("%s is not valid JSON; using the default" % path)
		return _Load.USE_DEFAULT
	var data: Variant = json.data
	if data is Dictionary and _is_view(data):
		warnings.append("%s is a saved view, not a keymap: load it with the View tab's Load view…" % path.get_file())
		return _Load.REFUSED
	if not (data is Dictionary) or not (data as Dictionary).get("axes") is Array:
		warnings.append("%s is not a keymap; using the default" % path)
		return _Load.USE_DEFAULT
	_clear_all()
	for entry in (data as Dictionary)["axes"]:
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
	return _Load.LOADED


## A view file (Workspace's shape): a "shape" or "fractal" section, or an
## "axes" dictionary of values where a keymap has a list of axes.
static func _is_view(data: Dictionary) -> bool:
	return data.has("shape") or data.has("fractal") or data.get("axes") is Dictionary


func save_file(path: String = "") -> Error:
	if path == "":
		path = current_path if current_path != "" else _default_path()
	var entries: Array = []
	for a in _axes.list():
		entries.append({
			"id": String(a.id),
			"label": a.label,
			"speed": a.speed,
			"positive": OS.get_keycode_string(positive_key(a.id)) if positive_key(a.id) != KEY_NONE else "",
			"negative": OS.get_keycode_string(negative_key(a.id)) if negative_key(a.id) != KEY_NONE else "",
		})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "axes": entries}, "\t", false))
	file.close()
	current_path = path
	return OK


func _clear_all() -> void:
	for id in _axes.ids():
		_erase_actions(id)
	_pairs.clear()
	_axes.clear()


func _apply_default() -> void:
	_clear_all()
	add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)


static func _key_from_name(name: String) -> int:
	if name == "":
		return KEY_NONE
	var code := OS.find_keycode_from_string(name)
	return code if code != KEY_NONE else KEY_NONE


func _default_path() -> String:
	return WorkspaceFiles.directory() + DEFAULT_FILE
