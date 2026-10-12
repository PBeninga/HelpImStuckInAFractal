extends RefCounted
## What the ship's diagnostics log says, loaded from diagnostics.json beside
## this script: edit the text there. The scripted crash report after the failed
## punch jump, the endless stream of problems the ship fixes on its own, the
## ones it needs the pilot for, and the wording around each line. EGRESS_WAIVER
## is a ready-made template the game can raise
## (CallCenter.raise_pilot_issue_from) to gate its exit.

const SOURCE := "res://call_center/log/diagnostics.json"

static var _data: Dictionary = _load()

## The crash report, played once the ship lands in fractal space. Each line
## waits `delay` seconds after the previous one. Styles: see IssueLog.
static var INTRO_SCRIPT: Array = _data.get("intro", [])
## [problem, how it was fixed]. Drawn at random (without repeats until the
## pool is spent) while the ship is stranded.
static var AUTO_ISSUES: Array = _data.get("auto_issues", []).map(
	func(i: Dictionary) -> Array: return [i["problem"], i["fix"]])
## Issues the ship cannot resolve without asking the pilot. `question` is what
## the support agent should ask; `default` is what the ship assumes if nobody
## answers in time; `outcome` formats the pilot's answer ({answer}) into the log.
static var PILOT_ISSUES: Array = _data.get("pilot_issues", [])
## A template for the game: an issue that must be answered before the exit.
static var EGRESS_WAIVER: Dictionary = _data.get("egress_waiver", {})
## The frame around each log line ({code}, {id}, {problem}, {fix}, {question},
## {how}, {outcome}).
static var WORDING: Dictionary = _data.get("wording", {})


static func _load() -> Dictionary:
	# load() rather than FileAccess: a .json is a JSON resource, so an exported
	# build carries it.
	var res := load(SOURCE) as JSON
	if res == null or not res.data is Dictionary:
		push_error("IssueCatalogue: could not read %s" % SOURCE)
		return {}
	return res.data


## `outcome` with the pilot's answer filled in.
static func outcome(template: String, answer: String) -> String:
	return template.format({"answer": answer})


## A WORDING line with its fields filled in.
static func line(key: String, fields: Dictionary) -> String:
	return str(WORDING.get(key, "")).format(fields)
