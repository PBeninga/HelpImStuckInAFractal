class_name ResolutionGovernor
extends Node
## Owns FractalView.render_scale, its update mode and its load-shed level. While
## the view is changing it adapts the scale to target 60 fps, never below the
## view's min_render_scale; once the scale is at that floor its LoadShedder
## brings in fog and cheaper detail, and at the last resort caps Fly speed.
## When changes stop it waits `settle` seconds of quiet, renders one full-scale,
## full-quality frame and then freezes. The moving scale and shed level are kept
## through idle, so moving again picks up where it left off.

## The shed level changed (0 = full quality). Main uses it for the Fly speed cap
## and the panel's readout.
signal shed_level_changed(level: int)

enum Mode { CONTINUOUS, SETTLING, FINAL_FRAME, IDLE }

const TARGET := 1.0 / LoadShedder.TARGET_FPS
const EMA_ALPHA := 0.2
const STEP := 0.8               # scale multiplier per adjustment

var scale := 1.0
var mode := Mode.IDLE
var fast_controls := true
var min_scale := 0.1            # follows FractalParams.min_render_scale
var cooldown := 0.5             # seconds between scale changes; tests may lower it
## Seconds of quiet before the full-scale final frame. Without it, the stray
## zero-length mouse motion a captured mouse produces while resting bought a
## full-resolution frame every time. Tests may lower it.
var settle := 0.15
var shedder := LoadShedder.new()

var _params: FractalParams
var _view: FractalView
var _ema := TARGET
var _since_change := 0.5        # allow an adjustment on the first frame
var _idle_pending := false
var _dirty := false
var _quiet := 0.0
var _moving_scale := 1.0        # the scale to resume at after a final frame


func setup(params: FractalParams, view: FractalView) -> void:
	_params = params
	_view = view
	_follow_params()
	params.changed.connect(func(): _dirty = true; _follow_params())


func _follow_params() -> void:
	fast_controls = _params.fast_controls
	min_scale = _params.min_render_scale


func mark_changed() -> void:
	_dirty = true


## The shed level the view should render at now: the shedder's while moving or
## settling (the last moving frame stays on screen), full quality otherwise.
func applied_level() -> int:
	if mode == Mode.CONTINUOUS or mode == Mode.SETTLING:
		return shedder.level
	return 0


func _process(delta: float) -> void:
	if _view == null:
		return
	var changing := _dirty
	_dirty = false
	var level_before := shedder.level
	step(delta, changing)
	if shedder.level != level_before:
		shed_level_changed.emit(shedder.level)
	# Only touch the view when something differs: re-setting the same size and
	# update mode every idle frame was wasted work, and forcing UPDATE_DISABLED
	# every frame could swallow a frame requested directly on the view.
	if _view.load_level != applied_level():
		_view.set_load_level(applied_level())
	if _view.render_scale != scale:
		_view.set_render_scale(scale)
	match mode:
		Mode.CONTINUOUS:
			if not _view.continuous:
				_view.set_continuous(true)
		Mode.FINAL_FRAME:
			_view.set_continuous(false)
			_view.request_frame()
		Mode.SETTLING, Mode.IDLE:
			if _view.continuous:
				_view.set_continuous(false)


## Pure logic: update `scale`, `mode` and the shed level from one frame's time
## and whether anything is changing. No side effects.
func step(frame_time: float, changing: bool) -> void:
	_since_change += frame_time
	if changing:
		if mode == Mode.FINAL_FRAME or mode == Mode.IDLE:
			scale = _moving_scale     # resume where moving left off, not at 1.0
		scale = maxf(scale, min_scale)   # the floor may have been raised
		mode = Mode.CONTINUOUS
		_idle_pending = true
		_quiet = 0.0
		if fast_controls:
			_ema = _ema * (1.0 - EMA_ALPHA) + frame_time * EMA_ALPHA
			if _since_change >= cooldown:
				if _ema > 1.0 / LoadShedder.SHED_FPS and scale > min_scale:
					scale = clampf(scale * STEP, min_scale, 1.0)
					_since_change = 0.0
				elif _ema < 1.0 / LoadShedder.RESTORE_FPS and scale < 1.0 and shedder.level == 0:
					# shed levels come off before the scale climbs
					scale = clampf(scale / STEP, min_scale, 1.0)
					_since_change = 0.0
			shedder.step(frame_time, _ema, scale <= min_scale)
		else:
			scale = 1.0
			if shedder.level != 0:
				shedder.reset()
		_moving_scale = scale
	elif _idle_pending:
		_quiet += frame_time
		if _quiet >= settle:
			mode = Mode.FINAL_FRAME
			scale = 1.0
			_idle_pending = false
		else:
			mode = Mode.SETTLING
	else:
		scale = maxf(scale, min_scale)
		mode = Mode.IDLE
