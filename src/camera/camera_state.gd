class_name CameraState
extends Resource
## The camera as a Transform3D (Godot convention: forward = -basis.z) plus a
## distance-speed multiplier, and a 64-bit copy of the eye. Setters emit
## Resource's built-in `changed`, but only when the value actually differs:
## stray input that re-assigns the same transform must not make the governor
## re-render a still view. The comparison is exact, so even a deep-zoom move
## of 1e-7 counts.
##
## Why the 64-bit eye: Vector3 components are 32-bit in a standard build, so
## `transform.origin` resolves to about 1e-6 at a distance of 10 from the
## origin. Inside a nested shape a thousandth the size of its parent, a frame's
## travel is smaller than that, and the camera would stick or jitter. The fly
## camera and a loaded level move the eye through set_eye() / move_by(), which
## accumulate in 64-bit (GDScript floats) and keep transform.origin as the
## rounded mirror everything else reads; assigning `transform` directly (the
## orbit camera, tests) makes its 32-bit origin the truth again.

const DEFAULT_EYE := Vector3(8.175847, 3.812460, 3.283393)

@export var transform: Transform3D = Transform3D.IDENTITY:
	set(v):
		if v == transform:
			return
		if v.origin != transform.origin:
			_ex = v.origin.x
			_ey = v.origin.y
			_ez = v.origin.z
		transform = v
		emit_changed()
@export var speed_factor: float = 1.0:
	set(v):
		if v == speed_factor:
			return
		speed_factor = v
		emit_changed()


# The 64-bit eye; transform.origin is its 32-bit mirror.
var _ex := 0.0
var _ey := 0.0
var _ez := 0.0


func eye() -> Vector3:
	return transform.origin


## The eye's 64-bit components.
func eye_x() -> float:
	return _ex


func eye_y() -> float:
	return _ey


func eye_z() -> float:
	return _ez


## Put the eye at a 64-bit position, keeping the orientation. Emits `changed`
## once even when the 32-bit mirror does not move.
func set_eye(x: float, y: float, z: float) -> void:
	if x == _ex and y == _ey and z == _ez:
		return
	var t := transform
	t.origin = Vector3(x, y, z)
	var mirror_moved := t != transform
	transform = t   # emits when the mirror moved (and copies the rounded origin)
	_ex = x
	_ey = y
	_ez = z
	if not mirror_moved:
		emit_changed()


## Move the eye by a world-space delta, accumulated in 64-bit.
func move_by(delta: Vector3) -> void:
	set_eye(_ex + delta.x, _ey + delta.y, _ez + delta.z)


## Re-orient without touching the 64-bit eye.
func set_basis(b: Basis) -> void:
	transform = Transform3D(b, transform.origin)


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
