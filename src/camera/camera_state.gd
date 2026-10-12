class_name CameraState
extends Resource
## The camera as a Transform3D (Godot convention: forward = -basis.z) plus a
## distance-speed multiplier. Setters emit Resource's built-in `changed`, but
## only when the value actually differs: stray input that re-assigns the same
## transform must not make the governor re-render a still view. The comparison
## is exact, so even a deep-zoom move of 1e-7 counts.
##
## The eye's true position is eye_x, eye_y, eye_z, three 64-bit floats (a
## Transform3D's origin is 32-bit: near the default eye it can only sit on a grid
## about 1e-6 apart). transform.origin is their rounded shadow, which every 32-bit
## consumer reads through eye(). The deep-zoom code reads eye64(). Assigning a
## transform whose origin is the shadow keeps the doubles (FlyCamera._set_forward
## rebuilds the basis that way); any other origin replaces them.

const DEFAULT_EYE := Vector3(8.175847, 3.812460, 3.283393)

@export var transform: Transform3D = Transform3D.IDENTITY:
	set(v):
		if v == transform:
			return
		if v.origin != Vector3(eye_x, eye_y, eye_z):
			eye_x = v.origin.x
			eye_y = v.origin.y
			eye_z = v.origin.z
		transform = v
		emit_changed()
@export var speed_factor: float = 1.0:
	set(v):
		if v == speed_factor:
			return
		speed_factor = v
		emit_changed()
## The 64-bit eye. Set them through set_eye64(), which keeps the transform's
## origin in step. (Declared after `transform` so a loaded resource ends with the
## exact doubles.)
@export var eye_x: float = 0.0
@export var eye_y: float = 0.0
@export var eye_z: float = 0.0


## Move the eye to (x, y, z) in 64-bit; the origin becomes its rounding. Emits
## changed when any double differs, even when the 32-bit shadow does not move.
func set_eye64(x: float, y: float, z: float) -> void:
	if x == eye_x and y == eye_y and z == eye_z:
		return
	eye_x = x
	eye_y = y
	eye_z = z
	var t := transform
	t.origin = Vector3(x, y, z)
	if t == transform:
		emit_changed()   # the doubles moved under the same shadow
	else:
		transform = t    # its origin is the new shadow, so the doubles stay


func eye64() -> PackedFloat64Array:
	return PackedFloat64Array([eye_x, eye_y, eye_z])


func eye() -> Vector3:
	return transform.origin


func forward() -> Vector3:
	return -transform.basis.z


func right() -> Vector3:
	return transform.basis.x


func up() -> Vector3:
	return transform.basis.y


## The site's initial view: eye at DEFAULT_EYE, looking at the origin, +Z up.
static func make_default() -> CameraState:
	var c := CameraState.new()
	var t := Transform3D(Basis.IDENTITY, DEFAULT_EYE)
	c.transform = t.looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	return c
