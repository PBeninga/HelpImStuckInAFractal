extends Node
## The call centre's only door into the game. Everything else in call_center/
## (the HUD, the MCP tools, the diagnostics log, the relay) talks to the ship
## through these methods and never touches a game class.
##
## explorer_adapter.gd implements it over today's explorer (Main's camera,
## params and view). A game that wants a different ship can hand the call
## centre its own adapter: give the game scene a method
## `call_center_adapter() -> Node` returning a Node that extends this script
## and overrides what it supports. Every method has a safe default, so a
## partial adapter works; unsupported controls answer {ok: false}.
##
## Conventions: positions are world units (meters_per_unit() converts for
## speech); angles are degrees; bearings are positive to the pilot's right,
## pitches positive up; control results are Dictionaries with `ok`.

## A manoeuvre began / ended. `info.completed` is false when it was cancelled,
## `info.reason` says why, `info.target_id` names the feature it flew to.
signal maneuver_started(kind: String, info: Dictionary)
signal maneuver_finished(kind: String, info: Dictionary)
## The pilot grabbed the controls during a manoeuvre.
signal manual_override


## Metres per world unit, for everything the agent and the HUD say.
func meters_per_unit() -> float:
	return 1.0


## {position, forward, right, up} (world space, unit axes).
func pose() -> Dictionary:
	return {"position": Vector3.ZERO, "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP}


## Move the ship (the demo and tests place it); returns whether it could.
func set_pose(_position: Vector3, _look_at: Vector3) -> bool:
	return false


## Distance to the nearest obstacle in world units; INF when unknown.
func clearance() -> float:
	return INF


func is_paused() -> bool:
	return is_inside_tree() and get_tree().paused


## The window pixel of a world point, or null when it is behind the camera.
func project(_point: Vector3) -> Variant:
	return null


## Whether the ship can fly straight from a to b without hitting anything.
func path_clear(_a: Vector3, _b: Vector3) -> bool:
	return true


## Whether `point` can be seen from the camera (the HUD dims hidden markers).
func visible_from_camera(_point: Vector3) -> bool:
	return true


## Facts about the world for the agent's technical explanations.
func world_info() -> Dictionary:
	return {}


# ------------------------------------------------------------- controls

func turn(_yaw_deg: float, _pitch_deg: float) -> Dictionary:
	return unsupported("turning")


func face(_point: Vector3, _info: Dictionary = {}) -> Dictionary:
	return unsupported("turning to face a point")


## direction: forward, back, left, right, up, down.
func thrust(_direction: String, _meters: float) -> Dictionary:
	return unsupported("thrust")


## Fly to `point`, stopping `standoff` world units short of it. `info` is
## echoed in maneuver_started / maneuver_finished (target_id).
func fly_to(_point: Vector3, _standoff: float, _info: Dictionary = {}) -> Dictionary:
	return unsupported("the autopilot")


## Cancel any manoeuvre; returns whether one was running.
func stop(_reason := "stopped") -> bool:
	return false


## {active, kind, target_id, seconds_left}.
func autopilot_state() -> Dictionary:
	return {"active": false, "kind": "idle"}


## Colour palettes the view can switch to (cosmetic), and switching.
func palettes() -> Array:
	return []


func set_palette(_name: String) -> Dictionary:
	return unsupported("palettes")


# ------------------------------------------------------------- helpers

func meters(units: float) -> int:
	return int(round(units * meters_per_unit()))


func unsupported(what: String) -> Dictionary:
	return {"ok": false, "reason": "unsupported", "message": "This ship does not support %s." % what}
