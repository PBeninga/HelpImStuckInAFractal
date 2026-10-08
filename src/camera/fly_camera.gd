class_name FlyCamera
extends Node
## Free-fly camera: mouse-look (yaw about world +Z, pitch about the camera's own
## right, no roll) and WASD + Space/Backspace (up/down) movement whose speed
## follows how far away the surface straight ahead is (the CenterRay), capped
## by the distance to the nearest surface in any direction. Holding Shift
## sprints and keeps accelerating; letting go of Shift eases back down, and
## letting go of every move key stops dead. Reads and writes a shared
## CameraState.

const WORLD_UP := Vector3(0, 0, 1)
const MAX_FORWARD_Z := 0.9998476951563913   # sin(89 deg): keep forward 1 deg off +/-Z
## The centre-ray distance may raise the speed to at most this many times the
## nearest-surface distance, so flying alongside a wall while looking down a
## long corridor cannot carry you sideways through the wall.
const NEAR_CAP := 10.0
## Sprint ("sprint", Shift) starts at SPRINT_MULTIPLIER, climbs by SPRINT_RATE
## every second held, and stops growing at SPRINT_MAX. Released, the boost
## halves every BOOST_HALVING seconds back down to 1.
const SPRINT_MULTIPLIER := 4.0
const SPRINT_RATE := 100.0
const SPRINT_MAX := 1000.0
const BOOST_HALVING := 0.5

var enabled := false
## The load shedder's cap on travel speed: 1.0 normally, lower at its top level.
var speed_limit := 1.0

var _params: FractalParams
var _camera: CameraState
var _ray: CenterRay
## The sprint multiplier on the base speed: 1 at rest, see step_boost().
var _boost := 1.0
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
		return
	var dir := move_direction()
	step_boost(delta, dir.length() > 0.0, Input.is_action_pressed("sprint"))
	if dir.length() == 0.0:
		return
	var t := _camera.transform
	t.origin += dir * current_speed() * delta
	_camera.transform = t


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


## Travel speed: base_speed() times the sprint boost.
func current_speed() -> float:
	return base_speed() * _boost


## Speed before sprinting: ~one second covers the distance to the surface
## straight ahead, but never more than NEAR_CAP times the distance to the
## nearest surface (a miss, at infinity, takes the cap), times the speed factor
## and the load shedder's speed_limit.
func base_speed() -> float:
	var near := DistanceEstimator.estimate(_camera.eye(), _params)
	var d := minf(_ray.distance(), near * NEAR_CAP)
	return clampf(d, 1e-6, 20.0) * _camera.speed_factor * speed_limit


## The current sprint multiplier (1 when not sprinting).
func boost() -> float:
	return _boost


## Advance the sprint boost by `delta` seconds. Not moving: back to 1 at once,
## so letting go of the move keys stops dead and the next start is gentle.
## Sprinting: at least SPRINT_MULTIPLIER, climbing by SPRINT_RATE per second up
## to SPRINT_MAX. Moving without Shift: halving every BOOST_HALVING s down to 1.
func step_boost(delta: float, moving: bool, sprinting: bool) -> void:
	if not moving:
		_boost = 1.0
	elif sprinting:
		_boost = minf(maxf(_boost, SPRINT_MULTIPLIER) + SPRINT_RATE * delta, SPRINT_MAX)
	else:
		_boost = maxf(_boost * pow(0.5, delta / BOOST_HALVING), 1.0)


func scroll(up: bool) -> void:
	var f := _camera.speed_factor * (1.25 if up else 1.0 / 1.25)
	_camera.speed_factor = clampf(f, 0.01, 100.0)


## Rebuild the basis from a forward vector with +Z as the up hint (no roll),
## keeping the eye where it is.
func _set_forward(fwd: Vector3) -> void:
	var t := Transform3D(Basis.IDENTITY, _camera.eye())
	_camera.transform = t.looking_at(_camera.eye() + fwd, WORLD_UP)
