class_name AttributeTable
extends RefCounted
## The shape's state: an ordered list of specs, a default value for each, and a
## Binding for each bindable one. Emits `changed(id)` whenever a default or a
## binding is edited, so views can re-render on change instead of every frame.
## Ported from Fractacular's AttributeTable; the per-category helpers are gone
## (there is one table here).

signal changed(id: StringName)

var specs: Array[AttributeSpec] = []
var _by_id: Dictionary = {}
var _defaults: Dictionary = {}
var _bindings: Dictionary = {}


func _init(spec_list: Array[AttributeSpec] = []) -> void:
	for s in spec_list:
		_add(s)


func _add(s: AttributeSpec) -> void:
	if _by_id.has(s.id):
		push_error("AttributeTable: duplicate attribute id '%s'" % s.id)
		return
	specs.append(s)
	_by_id[s.id] = s
	_defaults[s.id] = s.default_value
	if s.bindable:
		_bindings[s.id] = Binding.new()


func has(id: StringName) -> bool:
	return _by_id.has(id)


func spec(id: StringName) -> AttributeSpec:
	return _by_id.get(id)


## Attribute ids in declaration order.
func ids() -> Array:
	return specs.map(func(s: AttributeSpec) -> StringName: return s.id)


func get_default(id: StringName) -> Variant:
	return _defaults.get(id)


## Sanitizes through the spec, stores, and emits `changed` if it differs.
func set_default(id: StringName, value: Variant) -> void:
	var s := spec(id)
	if s == null:
		push_warning("AttributeTable.set_default: unknown id '%s'" % id)
		return
	var v: Variant = s.sanitize(value)
	if v == _defaults[id]:
		return
	_defaults[id] = v
	changed.emit(id)


## A copy of every default, keyed by id.
func defaults() -> Dictionary:
	return _defaults.duplicate()


## The Binding for a bindable id, or null.
func binding(id: StringName) -> Binding:
	return _bindings.get(id)


func set_binding(id: StringName, b: Binding) -> void:
	if not _bindings.has(id):
		push_warning("AttributeTable.set_binding: '%s' is not bindable" % id)
		return
	_bindings[id] = b
	changed.emit(id)


## Call after editing a Binding object in place.
func notify_binding_changed(id: StringName) -> void:
	changed.emit(id)


func has_active_binding() -> bool:
	for b: Binding in _bindings.values():
		if b.is_active():
			return true
	return false


func duplicate() -> AttributeTable:
	var t := AttributeTable.new(specs)
	for id in _defaults:
		t._defaults[id] = _defaults[id]
	for id in _bindings:
		t._bindings[id] = _bindings[id].duplicate()
	return t


## JSON-friendly: String keys, only active bindings.
func to_dict() -> Dictionary:
	var d := {"defaults": {}, "bindings": {}}
	for id in _defaults:
		var v: Variant = _defaults[id]
		var s := spec(id)
		if s != null and s.type == AttributeSpec.Type.COLOR and v is Color:
			var c: Color = v
			d["defaults"][String(id)] = [c.r, c.g, c.b]
		else:
			d["defaults"][String(id)] = v
	for id in _bindings:
		if _bindings[id].is_active():
			d["bindings"][String(id)] = _bindings[id].to_dict()
	return d


## Apply a dictionary from `to_dict()`. Unknown ids are skipped; one warning
## string per skipped id is returned.
func apply_dict(d: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	for key in d.get("defaults", {}):
		var id := StringName(key)
		if not has(id):
			warnings.append("Unknown attribute '%s' ignored" % key)
			continue
		set_default(id, d["defaults"][key])
	for key in d.get("bindings", {}):
		var id := StringName(key)
		if not _bindings.has(id):
			warnings.append("Unknown or non-bindable attribute '%s' binding ignored" % key)
			continue
		set_binding(id, Binding.from_dict(d["bindings"][key]))
	return warnings
