class_name Palette
extends RefCounted
## The colour scheme of the Palette colour mode: Inigo Quilez's cosine palette
##
##   color(t) = A + B · cos(2π (C·t + D))
##
## with A, B, C and D as RGB vectors, so twelve numbers describe a whole
## gradient. Ported from Fractacular's Palette, with one difference: the twelve
## numbers are not held here. Each is a catalogue attribute in the shape table
## (`palette_a_r` … `palette_d_b`, see MandelboxShape), so each can be bound to
## an axis or the clock with its own gain and waveform, and is saved with the
## view like any other knob. This class is the twelve-number view of those
## attributes that the Colour window's sliders, curve plot and strip need.
##
## `color_at()` is the same formula as `palette()` in mandelbox.gdshader. It
## reads the values the shader is actually drawn with: the resolved value for
## a component that is bound (set_live), the table default otherwise, so the
## strip previews the picture even while a binding animates it.

signal changed

const VECTOR_NAMES := ["A", "B", "C", "D"]
const CHANNEL_NAMES := ["r", "g", "b"]
const VECTOR_KEYS := ["a", "b", "c", "d"]

## The Colour mode id that paints with this palette (FractalParams.COLOR_MODE_IDS).
const MODE_ID := 20

## Slider range per vector, as (min, max). A and B are levels, so [0, 1]; C is
## a count of cycles across the gradient, only interesting up to a few; D is a
## phase, and a whole turn is 1.
const RANGES: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(0.0, 1.0), Vector2(0.0, 4.0), Vector2(0.0, 1.0)]
const STEP := 0.01

const DEFAULT_A := Vector3(0.5, 0.5, 0.5)
const DEFAULT_B := Vector3(0.5, 0.5, 0.5)
const DEFAULT_C := Vector3(1.0, 1.0, 1.0)
## Thirds of a turn between the channels: that is what makes it a rainbow.
const DEFAULT_D := Vector3(0.0, 0.33, 0.67)
const DEFAULTS: Array[Vector3] = [DEFAULT_A, DEFAULT_B, DEFAULT_C, DEFAULT_D]
## The same twelve as exact floats, A.r first (index vector * 3 + channel): a
## Vector3 holds 0.33 as float32, and the catalogue defaults must be the
## decimal values FractalParams and the shader declare.
const DEFAULT_COMPONENTS: Array[float] = [
	0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 0.0, 0.33, 0.67]

var _table: AttributeTable
## The last resolved values (id -> float) for the twelve ids.
var _live: Dictionary = {}
# While true, table edits do not each emit; _write() emits once at the end.
var _batch := false


## The catalogue id of one component: `vector` 0..3 = A..D, `channel` 0..2 = r, g, b.
static func id(vector: int, channel: int) -> StringName:
	return StringName("palette_%s_%s" % [VECTOR_KEYS[clampi(vector, 0, 3)], CHANNEL_NAMES[clampi(channel, 0, 2)]])


## All twelve ids, A.r first, D.b last.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for v in 4:
		for ch in 3:
			out.append(id(v, ch))
	return out


## The four vectors as set (the table defaults). Assigning one writes its
## three components, clamped by their specs, with one `changed`.
var a: Vector3:
	set(value):
		_assign(0, value)
	get:
		return _vector(0, false)
var b: Vector3:
	set(value):
		_assign(1, value)
	get:
		return _vector(1, false)
var c: Vector3:
	set(value):
		_assign(2, value)
	get:
		return _vector(2, false)
var d: Vector3:
	set(value):
		_assign(3, value)
	get:
		return _vector(3, false)


## A palette over `shape_table`, which must hold the twelve palette ids. Without a
## table (a window built bare in a test) it is a private one over the shape
## catalogue's defaults.
func _init(shape_table: AttributeTable = null) -> void:
	_table = shape_table if shape_table != null else AttributeTable.new(MandelboxShape.specs())
	_table.changed.connect(_on_table_changed)


func table() -> AttributeTable:
	return _table


## The colour at position t along the gradient, with the values the shader is
## drawn with. t is not wrapped here: the shader has already taken `fract()`
## of it and the strip only asks for [0, 1]. Clamped, because A + B can reach
## 2 and A − B can reach −1.
func color_at(t: float) -> Color:
	var va := _vector(0, true)
	var vb := _vector(1, true)
	var vc := _vector(2, true)
	var vd := _vector(3, true)
	return Color(
		clampf(va.x + vb.x * cos(TAU * (vc.x * t + vd.x)), 0.0, 1.0),
		clampf(va.y + vb.y * cos(TAU * (vc.y * t + vd.y)), 0.0, 1.0),
		clampf(va.z + vb.z * cos(TAU * (vc.z * t + vd.z)), 0.0, 1.0))


## One of the twelve numbers as set (the table default, not a driven value).
func get_component(vector: int, channel: int) -> float:
	return float(_table.get_default(id(vector, channel)))


## Write one of the twelve numbers; the table clamps it to the spec's range.
func set_component(vector: int, channel: int, value: float) -> void:
	_table.set_default(id(vector, channel), value)


## Back to IQ's rainbow, with a single `changed` for the whole move.
func reset() -> void:
	var before := _snapshot()
	_batch = true
	for i in DEFAULT_COMPONENTS.size():
		_table.set_default(id(i / 3, i % 3), DEFAULT_COMPONENTS[i])
	_batch = false
	if _snapshot() != before:
		changed.emit()


## Feed one frame of resolved values (id -> value, the whole table's is fine).
## Emits `changed` only when a bound component's value moved, so an unbound
## palette costs nothing per frame.
func set_live(values: Dictionary) -> void:
	var moved := false
	for pid in ids():
		if not values.has(pid):
			continue
		var v := float(values[pid])
		var was: Variant = _live.get(pid)
		_live[pid] = v
		if was != v and _is_bound(pid):
			moved = true
	if moved:
		changed.emit()


## Whether the Colour mode is the one that paints with this palette.
func in_use() -> bool:
	return int(_table.get_default(&"color_mode")) == MODE_ID


# ------------------------------------------------------------------ private

func _is_bound(pid: StringName) -> bool:
	var bnd := _table.binding(pid)
	return bnd != null and bnd.is_active()


func _value(pid: StringName, live: bool) -> float:
	if live and _is_bound(pid) and _live.has(pid):
		return float(_live[pid])
	return float(_table.get_default(pid))


func _vector(vector: int, live: bool) -> Vector3:
	return Vector3(_value(id(vector, 0), live), _value(id(vector, 1), live), _value(id(vector, 2), live))


## Write one whole vector (each component clamped by its spec), one `changed`.
func _assign(vector: int, value: Vector3) -> void:
	_write({clampi(vector, 0, 3): value})


## Write {vector index: Vector3} into the table, emitting `changed` once at the
## end and only if something moved.
func _write(vectors: Dictionary) -> void:
	var before := _snapshot()
	_batch = true
	for v in vectors:
		for ch in 3:
			_table.set_default(id(v, ch), (vectors[v] as Vector3)[ch])
	_batch = false
	if _snapshot() != before:
		changed.emit()


func _snapshot() -> Array:
	return [_vector(0, false), _vector(1, false), _vector(2, false), _vector(3, false)]


func _on_table_changed(changed_id: StringName) -> void:
	if _batch:
		return
	if changed_id == &"color_mode" or ids().has(changed_id):
		changed.emit()
