class_name FlyCamera
extends Node
## Free-fly camera: mouse-look (yaw about world +Z, pitch about the camera's own
## right, no roll) and WASD + Space/Backspace (up/down) movement whose speed
## follows how far away the surface straight ahead is (the CenterRay), capped
## by the distance to the nearest surface (of any shape) in any direction, so
## inside a small nested shape it crawls at that shape's scale. Holding Shift
## doubles the speed. A move that would take the camera below the zoom floor of
## the nearest shape (FractalParams.zoom_floor: where the perturbed march or 32
## iterations run out, or the 32-bit floor for shapes that are not perturbed)
## is refused. Reads and writes a shared CameraState, moving its eye in 64-bit.

const WORLD_UP := Vector3(0, 0, 1)
const MAX_FORWARD_Z := 0.9998476951563913   # sin(89 deg): keep forward 1 deg off +/-Z
## The centre-ray distance may raise the speed to at most this many times the
## nearest-surface distance, so flying alongside a wall while looking down a
## long corridor cannot carry you sideways through the wall.
const NEAR_CAP := 10.0
## Sprint ("sprint", Shift) multiplies the speed by this while held.
const SPRINT_MULTIPLIER := 2.0
## base_speed()'s lowest value. The speed is about the distance to the surface,
## so it must be able to fall below any zoom floor or the camera would outrun its
## own stop.
const SPEED_FLOOR := 1e-14

var enabled := false
## The load shedder's cap on travel speed: 1.0 normally, lower at its top level.
var speed_limit := 1.0
## Whether Shift was held on the last physics tick.
var sprinting := false
## True on a tick that refused a move because it would take the camera below
## FractalParams.zoom_floor. Cleared by the next accepted move, a tick with no
## move key held, or disabling the camera. Main shows it in the Movement pane.
var at_zoom_limit := false

var _params: FractalParams
var _camera: CameraState
var _ray: CenterRay
## Viewports whose text focus silences WASD, so typing in the console or a
## panel never flies the camera. Set by Main; empty for a standalone camera.
var _text_viewports: Array = []


## `ray` is the view's centre ray, so the speed and the probe dot share one
## march; a standalone camera makes its own.
func setup(params: FractalParams, camera: CameraState, ray: CenterRay = null) -> void:
	_params = params
	_camera = camera
	_ray = ray if ray != null else CenterRay.new(params, camera)


## The viewports (main window + console) whose text focus silences movement.
func set_text_viewports(viewports: Array) -> void:
	_text_viewports = viewports


## Mouse dispatch is owned by Main, which calls this for the active camera.
## Returns true when the event was consumed. Look only while captured; wheel
## adjusts the speed factor.
func handle_event(event: InputEvent) -> bool:
	if not enabled:
		return false
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# macOS sends zero-delta motion while a captured mouse rests; apply_look
		# ignores it, so a still view stays still.
		apply_look(event.relative.x, event.relative.y)
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll(true)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll(false)
			return true
	return false


func _physics_process(delta: float) -> void:
	if not enabled:
		at_zoom_limit = false
		return
	var dir := move_direction()
	sprinting = Input.is_action_pressed("sprint")
	if dir.length() == 0.0:
		at_zoom_limit = false
		return
	var step := dir * current_speed() * delta
	var to := [_camera.eye_x() + step.x, _camera.eye_y() + step.y, _camera.eye_z() + step.z]
	if not move_allowed_at([_camera.eye_x(), _camera.eye_y(), _camera.eye_z()], to):
		at_zoom_limit = true
		return
	at_zoom_limit = false
	_camera.move_by(step)   # accumulated in 64-bit


## Whether the camera may move from `from` to `to` (Vector3s, or 64-bit
## [x, y, z] / PackedFloat64Array eyes): yes when `to` is at least the zoom
## floor from the surface, or no closer than `from` is (backing away is always
## allowed, so a camera already past the floor, say from a loaded save, can
## leave). The speed already shrinks with the distance, so the last accepted
## step before the floor is tiny and the stop does not pop.
func move_allowed(from, to) -> bool:
	return move_allowed_at([from[0], from[1], from[2]], [to[0], to[1], to[2]])


## move_allowed() on 64-bit points ([x, y, z] each). One ReferenceOrbit at `to`
## gives both its distance and its floor.
func move_allowed_at(from: Array, to: Array) -> bool:
	var orbit := ReferenceOrbit.build(_params, to[0], to[1], to[2])
	if orbit.distance >= _params.zoom_floor_for(orbit):
		return true
	return orbit.distance >= DistanceEstimator.scene_estimate_at(from[0], from[1], from[2], _params)


## Rotate the view by a mouse delta (pixels). Yaw turns the heading about world
## +Z (pitch preserved); pitch sets the elevation angle, clamped to +/-89 deg so
## the forward vector never reaches +/-Z. Clamping the ANGLE (not forward.z after
## an arbitrary rotation) means even a huge delta saturates instead of wrapping.
func apply_look(dx: float, dy: float) -> void:
	if dx == 0.0 and dy == 0.0:
		return   # rebuilding the basis would round off, and a round-off is a change
	var sens := _params.mouse_sensitivity
	var fwd := _camera.forward().rotated(WORLD_UP, deg_to_rad(-dx * sens))  # yaw keeps pitch
	var max_pitch := asin(MAX_FORWARD_Z)
	var pitch_new := clampf(asin(clampf(fwd.z, -1.0, 1.0)) + deg_to_rad(-dy * sens), -max_pitch, max_pitch)
	var horiz := Vector3(fwd.x, fwd.y, 0.0)
	if horiz.length() > 1e-9:
		horiz = horiz.normalized()
	else:
		horiz = Vector3(_camera.right().y, -_camera.right().x, 0.0).normalized()
	_set_forward(horiz * cos(pitch_new) + WORLD_UP * sin(pitch_new))


## Unit movement direction in world space from the six actions (camera axes).
## Nothing while Cmd or Ctrl is held: Cmd+S saves, a Ctrl tap toggles the panel,
## and S alone is move_back.
func move_direction() -> Vector3:
	if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
		return Vector3.ZERO
	if TextFocus.any(_text_viewports):
		return Vector3.ZERO
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var s := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var u := Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	var dir := _camera.forward() * f + _camera.right() * s + _camera.up() * u
	if dir.length() > 0.0:
		dir = dir.normalized()
	return dir


## Travel speed: base_speed(), times SPRINT_MULTIPLIER while sprinting.
func current_speed() -> float:
	return base_speed() * (SPRINT_MULTIPLIER if sprinting else 1.0)


## Speed before sprinting: ~one second covers the distance to the surface
## straight ahead, but never more than NEAR_CAP times the distance to the
## nearest surface (a miss, at infinity, takes the cap), times the speed factor
## and the load shedder's speed_limit.
func base_speed() -> float:
	var near := DistanceEstimator.scene_estimate_at(_camera.eye_x(), _camera.eye_y(), _camera.eye_z(), _params)
	var d := minf(_ray.distance(), near * NEAR_CAP)
	return clampf(d, SPEED_FLOOR, 20.0) * _camera.speed_factor * speed_limit


func scroll(up: bool) -> void:
	var f := _camera.speed_factor * (1.25 if up else 1.0 / 1.25)
	_camera.speed_factor = clampf(f, 0.01, 100.0)


## Rebuild the basis from a forward vector with +Z as the up hint (no roll),
## keeping the (64-bit) eye where it is.
func _set_forward(fwd: Vector3) -> void:
	_camera.set_basis(Basis.looking_at(fwd, WORLD_UP))
