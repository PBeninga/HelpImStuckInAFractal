class_name OrbitCamera
extends Node
## The site's orbit controller. Keeps a `center`; rotation orbits it, pan moves
## both camera and centre, dolly/zoom change the distance. The mouse is never
## captured in this mode. Main dispatches mouse events to handle_event().

const WORLD_UP := Vector3(0, 0, 1)
const MAX_FORWARD_Z := 0.9998476951563913   # sin(89 deg): keep forward 1 deg off +/-Z
const ROT_PER_PIXEL := 0.5          # degrees per pixel at sensitivity 0.1
const PAN_PER_PIXEL := 0.001        # * distance_to_center
const DOLLY_PER_PIXEL := 0.005      # * distance_to_center
const ZOOM_PER_TICK := 0.1          # * distance_to_center
const CLICK_SLOP := 4.0             # px of motion below which a release is a click

var enabled := false
var center := Vector3.ZERO

var _params: FractalParams
var _camera: CameraState
var _view: FractalView
var _left := false
var _right := false
var _moved := 0.0


func setup(params: FractalParams, camera: CameraState, view: FractalView) -> void:
	_params = params
	_camera = camera
	_view = view


## Main's single dispatcher calls this. Returns true when consumed.
func handle_event(event: InputEvent) -> bool:
	if not enabled:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left = true
				_moved = 0.0
			else:
				var was := _left
				_left = false
				if was and _moved < CLICK_SLOP:
					_click(event.position)
				return was
			return true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right = event.pressed
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(true, _cursor_dir(event.position))
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(false, _cursor_dir(event.position))
			return true
	elif event is InputEventMouseMotion:
		var d: Vector2 = event.relative
		if _left:
			_moved += d.length()
			if event.shift_pressed:
				pan(d.x, d.y)
			elif event.alt_pressed:
				dolly(d.y)
			else:
				rotate_view(d.x, d.y)
			return true
		elif _right:
			dolly(d.y)
			return true
	return false


## On switching into ORBIT: centre on the surface hit by the centre ray, or the
## origin if that march runs past twice the current distance to the origin.
func enter() -> void:
	var dist_origin := _camera.eye().length()
	var hit: Variant = _march(_camera.eye(), _camera.forward())
	if hit != null and (hit as Vector3).distance_to(_camera.eye()) <= 2.0 * maxf(dist_origin, 1e-6):
		center = hit
	else:
		center = Vector3.ZERO


func rotate_view(dx: float, dy: float) -> void:
	var sens := ROT_PER_PIXEL * (_params.mouse_sensitivity / 0.1)
	var yaw := deg_to_rad(-dx * sens)
	var pitch := deg_to_rad(-dy * sens)
	var offset := _camera.eye() - center
	offset = offset.rotated(WORLD_UP, yaw)
	var right := _camera.right()
	offset = offset.rotated(right, pitch)
	# clamp pitch: keep the view direction away from +/-Z
	var new_eye := center + offset
	var fwd := (center - new_eye).normalized()
	if absf(fwd.z) > MAX_FORWARD_Z:
		# too steep: keep the yaw, drop the pitch for this step
		offset = (_camera.eye() - center).rotated(WORLD_UP, yaw)
		new_eye = center + offset
	_look_from(new_eye)


func pan(dx: float, dy: float) -> void:
	var dist := _camera.eye().distance_to(center)
	var delta := (-_camera.right() * dx + _camera.up() * dy) * dist * PAN_PER_PIXEL
	center += delta
	var t := _camera.transform
	t.origin += delta
	_camera.transform = t


func dolly(dy: float) -> void:
	var dist := _camera.eye().distance_to(center)
	var dir := (_camera.eye() - center).normalized()
	var new_dist := maxf(dist + dy * dist * DOLLY_PER_PIXEL, 1e-4)
	_look_from(center + dir * new_dist)


## Wheel: move toward the point under the cursor (dir is the cursor ray dir).
func zoom(up: bool, dir: Vector3) -> void:
	var dist := _camera.eye().distance_to(center)
	var step := dist * ZOOM_PER_TICK * (1.0 if up else -1.0)
	var t := _camera.transform
	t.origin += dir.normalized() * step
	_camera.transform = t


func recenter_on(hit: Vector3) -> void:
	center = hit


## A click (press without drag): march the cursor ray; recentre on the hit when
## it is within twice the current eye-to-centre distance, else onto the origin.
func _click(pixel: Vector2) -> void:
	var dir := _cursor_dir(pixel)
	var hit: Variant = _march(_camera.eye(), dir)
	var dist_c := _camera.eye().distance_to(center)
	if hit != null and (hit as Vector3).distance_to(_camera.eye()) <= 2.0 * maxf(dist_c, 1e-6):
		center = hit
	else:
		center = Vector3.ZERO


func _cursor_dir(pixel: Vector2) -> Vector3:
	return (_view.unproject(pixel, 1.0) - _camera.eye()).normalized()


func _look_from(eye: Vector3) -> void:
	var t := Transform3D(Basis.IDENTITY, eye)
	_camera.transform = t.looking_at(center, WORLD_UP)


## Single-phase high-precision CPU march, with the shader's level-of-detail hit
## threshold. Returns the hit Vector3 or null.
func _march(ro: Vector3, rd: Vector3) -> Variant:
	var tb := _box(ro, rd, _params.bound_half())
	if _params.view_distance() > 0.0:
		tb.y = minf(tb.y, _params.view_distance())   # the shader stops there too
	if tb.y < maxf(tb.x, 0.0):
		return null
	var total := maxf(tb.x, 0.0)
	var near := DistanceEstimator.estimate(ro, _params)
	for i in 200:
		var pos := ro + rd * total
		var d := DistanceEstimator.estimate(pos, _params)
		if d < _params.hit_epsilon(total, near):
			return pos
		total += d
		if total > tb.y:
			return null
	return null


func _box(ro: Vector3, rd: Vector3, half_size: float) -> Vector2:
	var sgn := Vector3(1.0 if rd.x >= 0.0 else -1.0, 1.0 if rd.y >= 0.0 else -1.0, 1.0 if rd.z >= 0.0 else -1.0)
	var safe := sgn * Vector3(maxf(absf(rd.x), 1e-9), maxf(absf(rd.y), 1e-9), maxf(absf(rd.z), 1e-9))
	var inv := Vector3(1.0 / safe.x, 1.0 / safe.y, 1.0 / safe.z)
	var n := inv * ro
	var k := inv.abs() * half_size
	var t1 := -n - k
	var t2 := -n + k
	var t_enter := maxf(maxf(t1.x, t1.y), t1.z)
	var t_exit := minf(minf(t2.x, t2.y), t2.z)
	return Vector2(t_enter, t_exit)
