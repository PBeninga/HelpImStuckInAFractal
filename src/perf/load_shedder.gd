class_name LoadShedder
extends RefCounted
## The rungs below full quality, and when to step between them. The governor
## owns one and feeds it the smoothed frame time while the view is moving; it
## only sheds once the render scale is already at its floor (`can_shed`), so
## the scale stays the first lever. Thresholds are sticky: shedding needs 0.5 s
## below 58 fps, restoring needs 2 s above 59.5 fps, nothing happens in between,
## and a shed soon after a restore makes the next restore wait twice as long
## (until a restore sticks for 10 s).

## Per level: fog distance (in multiples of the camera's distance to the nearest
## surface, 0 = no fog), multipliers on detail, the step budget and the Fly
## speed, and the shadow-march factor (× FractalParams.SHADOW_STEPS: shadows cost
## one extra ray, so they halve at level 1 and drop out from level 2). Fog and
## detail go long before the speed cap, which is a last resort. Iteration and
## absolute step caps also bound expensive user settings; the top level skips
## surface texture/bump work (displacement still defines the geometry).
const LEVELS: Array[Dictionary] = [
	{"fog": 0.0, "detail": 1.0, "steps": 1.0, "speed": 1.0, "shadow": 1.0, "iterations": 32, "step_cap": 512},
	{"fog": 400.0, "detail": 0.75, "steps": 1.0, "speed": 1.0, "shadow": 0.5, "iterations": 24, "step_cap": 384},
	{"fog": 150.0, "detail": 0.55, "steps": 0.75, "speed": 1.0, "shadow": 0.0, "iterations": 16, "step_cap": 256},
	{"fog": 60.0, "detail": 0.4, "steps": 0.5, "speed": 1.0, "shadow": 0.0, "iterations": 12, "step_cap": 96},
	{"fog": 40.0, "detail": 0.35, "steps": 0.25, "speed": 0.4, "shadow": 0.0, "iterations": 8, "step_cap": 32},
]

const TARGET_FPS := 60.0
const SHED_FPS := 58.0
# A 60 Hz paced display must be able to restore; demanding >60 would lock it
# into low quality forever. Dwell and anti-flap backoff protect this narrow band.
const RESTORE_FPS := 59.5
const SHED_DWELL := 0.5          # seconds below SHED_FPS before a shed
const SHED_COOLDOWN := 1.0       # seconds after any level change before the next shed
const RESTORE_DWELL := 2.0       # seconds above RESTORE_FPS before a restore
const RESTORE_DWELL_MAX := 16.0
const FLAP_WINDOW := 5.0         # a shed this soon after a restore is a flap
const CALM_RESET := 10.0         # a restore that sticks this long forgives past flaps
const _EPS := 1e-6               # summed frame times land a hair under a dwell

var level := 0
var restore_dwell := RESTORE_DWELL

var _slow := 0.0
var _fast := 0.0
var _since_change := SHED_COOLDOWN   # the first shed needs no cooldown
var _since_restore := INF
var _since_shed := INF


static func top() -> int:
	return LEVELS.size() - 1


static func settings(lvl: int) -> Dictionary:
	return LEVELS[clampi(lvl, 0, top())]


func reset() -> void:
	level = 0
	restore_dwell = RESTORE_DWELL
	_slow = 0.0
	_fast = 0.0
	_since_change = SHED_COOLDOWN
	_since_restore = INF
	_since_shed = INF


## Pure logic: advance by one frame of `frame_time` with smoothed frame time
## `ema`. Returns true when the level changed.
func step(frame_time: float, ema: float, can_shed: bool) -> bool:
	_since_change += frame_time
	_since_restore += frame_time
	_since_shed += frame_time
	var fps := 1.0 / maxf(ema, 1e-6)

	_slow = _slow + frame_time if fps < SHED_FPS and can_shed and level < top() else 0.0
	_fast = _fast + frame_time if fps > RESTORE_FPS and level > 0 else 0.0
	if _since_restore < _since_shed and _since_restore >= CALM_RESET - _EPS:
		restore_dwell = RESTORE_DWELL

	if _slow >= SHED_DWELL - _EPS and _since_change >= SHED_COOLDOWN - _EPS:
		if _since_restore < FLAP_WINDOW:
			restore_dwell = minf(restore_dwell * 2.0, RESTORE_DWELL_MAX)
		level += 1
		_since_shed = 0.0
		_changed()
		return true
	if _fast >= restore_dwell - _EPS:
		level -= 1
		_since_restore = 0.0
		_changed()
		return true
	return false


func _changed() -> void:
	_slow = 0.0
	_fast = 0.0
	_since_change = 0.0
