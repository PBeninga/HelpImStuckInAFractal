class_name ShapeList
extends RefCounted
## The scene's shapes as the player authors them: an ordered list of entries,
## each a label and an AttributeTable over the per-shape catalogue
## (ShapeCatalogue.shape_specs(): placement knobs included, so a shape's
## position or size can be bound to an axis like any other knob). Main resolves
## every table into its FractalParams.shapes entry each frame, the console
## shows one collapsible panel per entry, and Workspace saves the list under
## "shapes". Never empty: the last shape cannot be removed.
##
## `changed` is the list's structure (an entry added or removed, or the whole
## list replaced by a load); `relabelled(index)` an entry's new label;
## `entry_changed(index, id)` relays a table edit with the entry it came from.

const DEFAULT_NEXT_LEVEL_DISTANCE := 20.0

signal changed
signal stage_changed(index: int)
signal next_level_distance_changed(index: int)
signal relabelled(index: int)
signal entry_changed(index: int, id: StringName)

## One shape's authoring state.
class Entry:
	var label: String
	var table: AttributeTable
	var look := AttributeTable.new(ShapeCatalogue.scene_specs())
	## Zero contributes the default 20 world units to the cumulative gameplay threshold.
	var next_level_distance := 0.0
	var commands: Array[String] = []

	func _init(p_label: String, p_table: AttributeTable) -> void:
		label = p_label
		table = p_table


var _entries: Array[Entry] = []
var _next_number := 1


func _init(count: int = 1) -> void:
	for i in maxi(count, 1):
		add()


func count() -> int:
	return _entries.size()


func entry(i: int) -> Entry:
	return _entries[i]


func next_level_distance(i: int) -> float:
	var distance := _entries[i].next_level_distance
	return distance if distance > 0.0 else DEFAULT_NEXT_LEVEL_DISTANCE


## Absolute distance from the run origin needed to finish this stage.
func next_level_threshold(i: int) -> float:
	var total := 0.0
	for index in range(i + 1):
		total += next_level_distance(index)
	return total


func table(i: int) -> AttributeTable:
	return _entries[i].table


func look_table(i: int) -> AttributeTable:
	return _entries[i].look


func label(i: int) -> String:
	return _entries[i].label


func set_label(i: int, text: String) -> void:
	text = text.strip_edges()
	if i < 0 or i >= _entries.size() or text == "" or _entries[i].label == text:
		return
	_entries[i].label = text
	relabelled.emit(i)


## Every table, in order.
func tables() -> Array:
	var out: Array = []
	for e in _entries:
		out.append(e.table)
	return out


## Append a shape at the catalogue defaults, overridden by `defaults` (id ->
## value, sanitized through the specs). Returns its index, or -1 when the scene
## is full.
func add(defaults: Dictionary = {}, p_label: String = "", look_defaults: Dictionary = {}) -> int:
	if _entries.size() >= FractalParams.MAX_SHAPES:
		push_warning("ShapeList.add: already holds %d shapes" % FractalParams.MAX_SHAPES)
		return -1
	var t := AttributeTable.new(ShapeCatalogue.shape_specs())
	for id in defaults:
		if t.has(StringName(id)):
			t.set_default(StringName(id), defaults[id])
	var name := p_label if p_label != "" else "Shape %d" % _next_number
	_next_number += 1
	var e := Entry.new(name, t)
	for id in look_defaults:
		if e.look.has(StringName(id)):
			e.look.set_default(StringName(id), look_defaults[id])
	e.commands = default_commands(t)
	_entries.append(e)
	t.changed.connect(_on_table_changed.bind(e))
	e.look.changed.connect(_on_table_changed.bind(e))
	changed.emit()
	return _entries.size() - 1


## Drop the i-th shape. Returns false (and does nothing) for the last one.
func remove(i: int) -> bool:
	if _entries.size() <= 1 or i < 0 or i >= _entries.size():
		return false
	var e := _entries[i]
	e.table.changed.disconnect(_on_table_changed)
	e.look.changed.disconnect(_on_table_changed)
	_entries.remove_at(i)
	changed.emit()
	return true


## Resolve every table for one frame: one Dictionary (id -> value) per shape,
## in order.
func resolve(axis_values: Dictionary, t: float) -> Array:
	var out: Array = []
	for e in _entries:
		out.append(BindingResolver.resolve(e.table, axis_values, t))
	return out


## Whether any shape has a binding driving a knob.
func has_active_binding() -> bool:
	for e in _entries:
		if e.table.has_active_binding() or e.look.has_active_binding():
			return true
	return false


## JSON-friendly: [{label, defaults, bindings}, …].
func to_dict() -> Array:
	var out: Array = []
	for e in _entries:
		var d := e.table.to_dict()
		d["label"] = e.label
		d["look"] = e.look.to_dict()
		d["next_level_distance"] = e.next_level_distance
		d["commands"] = Array(e.commands)
		out.append(d)
	return out


## Replace the list with a saved one (from to_dict()). A malformed entry is
## skipped with a warning; an empty or malformed list leaves one default shape.
## Returns the warnings.
func apply_dict(saved: Variant) -> Array[String]:
	var warnings: Array[String] = []
	if not (saved is Array):
		warnings.append("Malformed shapes section ignored")
		return warnings
	var fresh: Array[Entry] = []
	var number := 1
	for raw in saved:
		if not (raw is Dictionary):
			warnings.append("Malformed shape entry ignored")
			continue
		if fresh.size() >= FractalParams.MAX_SHAPES:
			warnings.append("More than %d shapes: the rest were dropped" % FractalParams.MAX_SHAPES)
			break
		var t := AttributeTable.new(ShapeCatalogue.shape_specs())
		for w in t.apply_dict(raw):
			warnings.append(w)
		var name := String(raw.get("label", "")).strip_edges()
		if name == "":
			name = "Shape %d" % number
		number += 1
		var e := Entry.new(name, t)
		var look: Variant = raw.get("look", {})
		if look is Dictionary:
			for warning in e.look.apply_dict(look):
				warnings.append("%s look: %s" % [name, warning])
		else:
			warnings.append("Malformed look for %s ignored" % name)
		var distance: Variant = raw.get("next_level_distance", raw.get("escape_distance", 0.0))
		if (distance is float or distance is int) and is_finite(float(distance)) and float(distance) >= 0.0:
			e.next_level_distance = float(distance)
		else:
			warnings.append("Invalid next level distance for %s; using automatic stage distance" % name)
		var commands: Variant = raw.get("commands", default_commands(t))
		var error := validate_commands(t, commands)
		if error == "":
			e.commands.assign(commands)
		else:
			warnings.append("Invalid commands for %s: %s (stage blocked until corrected)" % [name, error])
			e.commands.assign(commands if commands is Array and commands.all(func(c): return c is String) else ["invalid_command"])
		fresh.append(e)
	if fresh.is_empty():
		warnings.append("No shapes in the file: kept one default shape")
		fresh.append(Entry.new("Shape 1", AttributeTable.new(ShapeCatalogue.shape_specs())))
	for e in _entries:
		e.table.changed.disconnect(_on_table_changed)
		e.look.changed.disconnect(_on_table_changed)
	_entries = fresh
	_next_number = _entries.size() + 1
	for e in _entries:
		e.table.changed.connect(_on_table_changed.bind(e))
		e.look.changed.connect(_on_table_changed.bind(e))
	changed.emit()
	return warnings


func _on_table_changed(id: StringName, e: Entry) -> void:
	var i := _entries.find(e)
	if i >= 0:
		entry_changed.emit(i, id)


## Atomically edit saved stage objectives. Empty scripts support older levels.
func set_stage(i: int, distance: float, commands: Array) -> bool:
	if i < 0 or i >= count() or not is_finite(distance) or distance < 0.0:
		return false
	if validate_commands(table(i), commands) != "":
		return false
	var commands_changed := Array(_entries[i].commands) != commands
	var distance_changed := _entries[i].next_level_distance != distance
	_entries[i].next_level_distance = distance
	_entries[i].commands.assign(commands)
	if commands_changed:
		stage_changed.emit(i)
	elif distance_changed:
		# Distance edits preserve the active shape and its runtime geometry.
		next_level_distance_changed.emit(i)
	return true


static func validate_commands(t: AttributeTable, commands: Variant) -> String:
	if not commands is Array:
		return "Commands must be an array of strings."
	var values := t.defaults()
	for command in commands:
		if not command is String:
			return "Every command must be a string."
		var result := ShapeCommand.parse(command, t, values)
		if not result.ok:
			return result.message
		values[result.id] = result.value
	return ""


static func default_commands(t: AttributeTable) -> Array[String]:
	match int(t.get_default(&"shape")):
		FractalParams.Shape.MANDELBOX, FractalParams.Shape.KLEINIAN:
			var id := &"kleinian_radius" if int(t.get_default(&"shape")) == FractalParams.Shape.KLEINIAN else &"fixed_radius"
			var radius: float = t.get_default(id)
			var target := maxf(radius * 0.5, t.spec(id).hard_min)
			if target != radius:
				return ["inversion %s" % (target - radius)]
		FractalParams.Shape.KIFS:
			return ["kifs_scale %s" % (2.5 if float(t.get_default(&"kifs_scale")) != 2.5 else 3.0)]
		FractalParams.Shape.MANDELBULB:
			return ["mandelbulb_power %s" % (6.0 if float(t.get_default(&"mandelbulb_power")) != 6.0 else 8.0)]
	return ["w %s" % (-0.5 if float(t.get_default(&"w")) != -0.5 else 0.0)]
