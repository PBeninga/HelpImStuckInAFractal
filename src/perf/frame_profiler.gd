class_name FrameProfiler
extends RefCounted
## Opt-in CPU scopes. Disabled scopes neither read the clock nor allocate samples.
## Inclusive timings: nested operations overlap and must not be added together.

const FRAME_BUDGET_MS := 1000.0 / 60.0
static var enabled := false
static var _samples: Dictionary = {}


static func set_enabled(on: bool) -> void:
	enabled = on
	_samples.clear()


static func begin() -> int:
	return Time.get_ticks_usec() if enabled else -1


static func end(operation: StringName, started: int) -> void:
	if enabled and started >= 0:
		record(operation, float(Time.get_ticks_usec() - started))


static func record(operation: StringName, usec: float) -> void:
	if enabled:
		_samples[operation] = float(_samples.get(operation, 0.0)) + usec


## Average per game frame, including frames where an operation did not run.
static func take_snapshot(frames: int) -> Array:
	var rows: Array = []
	for operation in _samples:
		var ms: float = _samples[operation] / (1000.0 * maxi(frames, 1))
		rows.append({"name": operation, "ms": ms, "percent": ms / FRAME_BUDGET_MS * 100.0})
	_samples.clear()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	return rows
