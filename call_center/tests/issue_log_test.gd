extends "res://call_center/tests/test_case.gd"
## The diagnostics log: automatic problems get fixed a moment later, pilot
## issues wait for an answer (longer while an agent is on the line) and fall
## back to their default, and resolve() accepts ids with or without '#'.

const IssueLog := preload("res://call_center/log/issue_log.gd")
const IssueCatalogue := preload("res://call_center/log/issue_catalogue.gd")


func run() -> void:
	var issues := IssueLog.new(7)
	var resolved: Array = []
	issues.issue_resolved.connect(func(issue: Dictionary, answer: String, by: String):
		resolved.append([issue["issue_id"], answer, by]))

	# automatic issues: an error, then its fix
	issues.auto_running = true
	for i in 40:
		issues.advance(0.5)
	var errors := 0
	var fixes := 0
	for e in issues.entries:
		if e["style"] == "error":
			errors += 1
		elif e["style"] == "ok":
			fixes += 1
	check(errors >= 2, "auto issues are raised (%d)" % errors)
	check(fixes >= errors - 1, "and fixed (%d of %d)" % [fixes, errors])
	check(issues.entries[0]["text"].begins_with("Error #"), "an issue reads 'Error #NNNNN ...'")
	issues.auto_running = false

	# a pilot issue offline times out quickly to its default
	var issue := issues.raise_pilot_issue()
	check(issue["issue_id"].begins_with("#"), "pilot issues have '#' ids")
	check_eq(issues.pending().size(), 1, "one pending issue")
	check_eq(issues.recent(1)[0]["style"], "pilot", "the log shows the question")
	issues.advance(IssueLog.PILOT_TIMEOUT_OFFLINE + 0.1)
	check_eq(issues.pending().size(), 0, "offline, it times out after %d s" % IssueLog.PILOT_TIMEOUT_OFFLINE)
	check_eq(resolved[-1][2], "timeout", "resolved by timeout")
	check(issues.recent(1)[0]["text"].contains("executive decision"), "the log says nobody answered")

	# with an agent on the line it waits longer, and takes the pilot's answer
	issues.set_agent_available(true)
	var waiver := issues.raise_pilot_issue(IssueCatalogue.EGRESS_WAIVER)
	check_eq(waiver["issue_id"], "#99812", "the waiver keeps its fixed code")
	check(waiver["blocks_exit"], "and blocks the exit")
	issues.advance(IssueLog.PILOT_TIMEOUT_OFFLINE + 1.0)
	check_eq(issues.pending().size(), 1, "with an agent available it is still waiting")
	check_eq(issues.resolve("99812", "  Grace Hopper "), IssueCatalogue.EGRESS_WAIVER["outcome"] % "Grace Hopper",
		"resolve accepts an id without '#', and trims the answer")
	check_eq(resolved[-1], ["#99812", "Grace Hopper", "pilot"], "issue_resolved reports the pilot's answer")
	check_eq(issues.pilot_answers, 1, "one pilot answer counted")
	check_eq(issues.resolve("#99812", "again"), "", "a resolved issue cannot be resolved twice")

	# an empty answer falls back to the default
	var q := issues.raise_pilot_issue()
	issues.resolve(q["issue_id"], "   ")
	check(issues.recent(1)[0]["text"].contains("via pilot input"), "an empty answer still resolves")

	# the intro script plays in order and announces its end
	var done := [false]
	issues.intro_script_finished.connect(func(): done[0] = true)
	var n := issues.entries.size()
	issues.play_intro_script()
	for i in 30:
		issues.advance(0.5)
	check(done[0], "the crash report finishes")
	check_eq(issues.entries.size() - n, IssueCatalogue.INTRO_SCRIPT.size(), "every scripted line is logged once")
	check_eq(issues.entries[-1]["text"], IssueCatalogue.INTRO_SCRIPT[-1]["text"], "ending on 'connecting to agent'")
	issues.free()
