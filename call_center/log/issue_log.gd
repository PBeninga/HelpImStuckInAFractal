extends Node
## The ship's diagnostics log: a stream of entries the HUD scrolls. Plays the
## scripted crash report, then (while `auto_running`) raises a problem every
## few seconds and fixes it a moment later. Pilot issues wait for an answer
## (the support agent asks the caller and calls resolve()); each has a timeout
## after which the ship assumes its default answer, so nothing soft-locks
## without a call.
##
## Entry styles: "error" (a new problem), "ok" (fixed), "fail" (could not be
## fixed), "pilot" (needs the pilot), "info", "agent" (posted by the support
## agent), "system" (call and link status).

const IssueCatalogue := preload("res://call_center/log/issue_catalogue.gd")

signal entry_added(entry: Dictionary)
signal intro_script_finished
signal pilot_input_required(issue: Dictionary)
signal issue_resolved(issue: Dictionary, answer: String, by: String)

const MAX_ENTRIES := 200
## Seconds between automatic problems, and from a problem to its fix.
const AUTO_GAP := Vector2(50.0, 100.0)
const FIX_GAP := Vector2(1.2, 2.8)
## Seconds a pilot issue waits for an answer before the default is assumed.
const PILOT_TIMEOUT := 120.0
const PILOT_TIMEOUT_OFFLINE := 25.0

var entries: Array[Dictionary] = []
var auto_running := false
## True while someone (the support agent) can answer pilot issues; without it
## they time out quickly.
var agent_available := false
var resolved_count := 0
var pilot_answers := 0

var _rng := RandomNumberGenerator.new()
var _script_queue: Array = []
var _script_wait := 0.0
var _scripting := false
var _auto_wait := 30.0
var _fix_queue: Array = []        # [{at, text}]
var _auto_pool: Array = []
var _pilot_pool: Array = []
var _pending: Array[Dictionary] = []
var _clock := 0.0
var _next_entry_id := 1


func _init(seed_value: int = -1) -> void:
	# freezes with the game's pause even under the always-on CallCenter
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func _process(delta: float) -> void:
	advance(delta)


## Step the log by `delta` seconds (the tests call this directly).
func advance(delta: float) -> void:
	_clock += delta
	if _scripting:
		_script_wait -= delta
		while _scripting and _script_wait <= 0.0:
			var line: Dictionary = _script_queue.pop_front()
			add(line["text"], line["style"])
			if _script_queue.is_empty():
				_scripting = false
				intro_script_finished.emit()
			else:
				_script_wait += _script_queue[0]["delay"]
	var i := 0
	while i < _fix_queue.size():
		if _fix_queue[i]["at"] <= _clock:
			add(_fix_queue[i]["text"], "ok")
			resolved_count += 1
			_fix_queue.remove_at(i)
		else:
			i += 1
	if auto_running:
		_auto_wait -= delta
		if _auto_wait <= 0.0:
			_raise_auto()
			_auto_wait = _rng.randf_range(AUTO_GAP.x, AUTO_GAP.y)
	for issue in _pending.duplicate():
		if _clock >= issue["deadline"]:
			resolve(issue["id"], issue["default"], "timeout")


func play_intro_script() -> void:
	_script_queue = IssueCatalogue.INTRO_SCRIPT.duplicate(true)
	_script_wait = _script_queue[0]["delay"]
	_scripting = true


func is_scripting() -> bool:
	return _scripting


func add(text: String, style := "info") -> Dictionary:
	var entry := {"n": _next_entry_id, "text": text, "style": style, "time": _clock}
	_next_entry_id += 1
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(entry)
	return entry


## The last `n` entries, oldest first.
func recent(n: int) -> Array:
	return entries.slice(maxi(0, entries.size() - n))


func _raise_auto() -> void:
	if _auto_pool.is_empty():
		_auto_pool = IssueCatalogue.AUTO_ISSUES.duplicate()
		_shuffle(_auto_pool)
	var pair: Array = _auto_pool.pop_back()
	add(IssueCatalogue.line("auto_error", {"code": _code(), "problem": pair[0]}), "error")
	_fix_queue.append({"at": _clock + _rng.randf_range(FIX_GAP.x, FIX_GAP.y),
		"text": IssueCatalogue.line("auto_resolved", {"fix": pair[1]})})


## Raise a pilot issue: the next from the shuffled pool, or `template` (e.g.
## IssueCatalogue.EGRESS_WAIVER). Returns the issue.
func raise_pilot_issue(template: Dictionary = {}) -> Dictionary:
	var t := template
	if t.is_empty():
		if _pilot_pool.is_empty():
			_pilot_pool = IssueCatalogue.PILOT_ISSUES.duplicate()
			_shuffle(_pilot_pool)
		t = _pilot_pool.pop_back()
	var code := int(t.get("code", _code()))
	var timeout := PILOT_TIMEOUT if agent_available else PILOT_TIMEOUT_OFFLINE
	var issue := {
		"id": "#%d" % code,
		"problem": t["problem"],
		"question": t["question"],
		"default": t["default"],
		"outcome": t["outcome"],
		"gating": t.get("gating", false),
		"deadline": _clock + timeout,
		"raised_at": _clock,
	}
	_pending.append(issue)
	add(IssueCatalogue.line("pilot_error", {"id": issue["id"], "problem": issue["problem"]}), "error")
	add(IssueCatalogue.line("pilot_prompt", {"question": issue["question"]}), "pilot")
	pilot_input_required.emit(_public(issue))
	return _public(issue)


## Answer a pending pilot issue. `by` is "pilot" (through the agent), "timeout"
## or "keyboard". Returns the logged outcome, or "" when no such issue is open.
func resolve(issue_id: String, answer: String, by := "pilot") -> String:
	var key := issue_id.strip_edges()
	if not key.begins_with("#"):
		key = "#" + key
	for issue in _pending:
		if issue["id"] == key:
			_pending.erase(issue)
			var a := answer.strip_edges()
			if a.is_empty():
				a = issue["default"]
			var outcome := IssueCatalogue.outcome(issue["outcome"], a)
			var how := IssueCatalogue.line("how_pilot" if by != "timeout" else "how_timeout", {})
			add(IssueCatalogue.line("pilot_resolved", {"id": issue["id"], "how": how, "outcome": outcome}), "ok")
			resolved_count += 1
			if by != "timeout":
				pilot_answers += 1
			issue_resolved.emit(_public(issue), a, by)
			return outcome
	return ""


## Open pilot issues, oldest first (without internal timing fields).
func pending() -> Array:
	var out: Array = []
	for issue in _pending:
		out.append(_public(issue))
	return out


func has_pending(issue_id: String) -> bool:
	for issue in _pending:
		if issue["id"] == issue_id:
			return true
	return false


## Give the open issues the agent's longer timeout (or the offline one).
func set_agent_available(on: bool) -> void:
	agent_available = on
	for issue in _pending:
		var timeout := PILOT_TIMEOUT if on else PILOT_TIMEOUT_OFFLINE
		issue["deadline"] = maxf(issue["deadline"], _clock + timeout) if on else minf(issue["deadline"], _clock + timeout)


func _public(issue: Dictionary) -> Dictionary:
	return {
		"issue_id": issue["id"],
		"problem": issue["problem"],
		"question": issue["question"],
		"blocks_exit": issue["gating"],
		"seconds_left": int(ceil(maxf(0.0, issue["deadline"] - _clock))),
	}


func _code() -> int:
	return _rng.randi_range(10000, 99999)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
