class_name Mission
extends Node
## The escape, as a state machine: INTRO (the failed jump plays) -> STRANDED
## (the crash report, waiting for support) -> ESCAPING (on the line, or flying)
## -> EGRESS (the rift has the ship) -> ESCAPED. Marks waypoints as the ship
## passes them, raises the egress waiver when the ship nears the rift, and fires
## the egress once the ship is inside the rift with the waiver signed.

signal stage_changed(stage: int)
signal waypoint_reached(feature: Dictionary)
signal rift_refused(issue_id: String)
signal egress_started

enum Stage { INTRO, STRANDED, ESCAPING, EGRESS, ESCAPED }
const STAGE_NAMES := ["intro", "stranded", "escaping", "egress", "escaped"]

## A waypoint counts as reached inside this range (30 m).
const REACH_RADIUS := 0.03
## The waiver is raised when the ship comes this close to the rift.
const WAIVER_RANGE := 0.65

var stage := Stage.INTRO
var visited := {}
var waiver_issue_id := ""
var waiver_signed := false
## Seconds since the ship landed in fractal space (until it escapes).
var stranded_seconds := 0.0

var _params: FractalParams
var _camera: CameraState
var _log: IssueLog
var _refused := false


func setup(params: FractalParams, camera: CameraState, issue_log: IssueLog) -> void:
	_params = params
	_camera = camera
	_log = issue_log
	issue_log.issue_resolved.connect(_on_issue_resolved)


func set_stage(s: int) -> void:
	if s == stage:
		return
	stage = s
	stage_changed.emit(s)


func stage_name() -> String:
	return STAGE_NAMES[stage]


func _physics_process(delta: float) -> void:
	step(delta)


## Advance by `delta` seconds (the tests call this directly).
func step(delta: float) -> void:
	if stage == Stage.STRANDED or stage == Stage.ESCAPING:
		stranded_seconds += delta
		check_position()


func check_position() -> void:
	var eye := _camera.eye()
	for f in Route.waypoints():
		if f["kind"] == "route" and not visited.has(f["id"]) \
				and eye.distance_to(f["pos"]) < REACH_RADIUS:
			visited[f["id"]] = true
			waypoint_reached.emit(f)
	var rift_d := eye.distance_to(Route.RIFT_POS)
	if waiver_issue_id == "" and not waiver_signed and rift_d < WAIVER_RANGE:
		waiver_issue_id = _log.raise_pilot_issue(IssueCatalogue.EGRESS_WAIVER)["issue_id"]
	if rift_d < Route.RIFT_TRIGGER:
		if waiver_signed:
			begin_egress()
		elif not _refused:
			_refused = true
			if waiver_issue_id == "":
				waiver_issue_id = _log.raise_pilot_issue(IssueCatalogue.EGRESS_WAIVER)["issue_id"]
			_log.add("Rift handshake refused: egress waiver %s unsigned" % waiver_issue_id, "fail")
			rift_refused.emit(waiver_issue_id)
	elif rift_d > Route.RIFT_TRIGGER * 2.0:
		_refused = false


func begin_egress() -> void:
	if stage == Stage.EGRESS or stage == Stage.ESCAPED:
		return
	set_stage(Stage.EGRESS)
	egress_started.emit()


## The first route waypoint not yet passed (the exit once all are), or {}.
func next_waypoint() -> Dictionary:
	for f in Route.waypoints():
		if not visited.has(f["id"]):
			return f
	return {}


func is_inside_rift() -> bool:
	return _camera.eye().distance_to(Route.RIFT_POS) < Route.RIFT_TRIGGER


func _on_issue_resolved(issue: Dictionary, _answer: String, _by: String) -> void:
	if issue["issue_id"] == waiver_issue_id:
		waiver_signed = true
		_log.add("Egress rift unlocked. Fly into it to leave.", "info")
		if is_inside_rift():
			begin_egress()
