extends "res://tests/test_case.gd"
## Pure step() logic on fabricated smoothed frame times: dwell before shedding,
## the cooldown between sheds, the dead band, the restore dwell and its
## anti-flap backoff.

const DT := 0.05
const SLOW := 0.1          # 10 fps  < 58
const FAST := 1.0 / 120.0  # 120 fps > 59.5
const MID := 1.0 / 59.0    # 59 fps, inside the dead band


## Step `s` for `seconds` at a fixed smoothed frame time; returns the number of
## level changes it reported.
func _run_for(s: LoadShedder, seconds: float, ema: float, can_shed := true) -> int:
	var changes := 0
	var t := 0.0
	while t < seconds - 1e-9:
		if s.step(DT, ema, can_shed):
			changes += 1
		t += DT
	return changes


func run() -> void:
	# --- the ladder: fog and detail go long before the speed cap ---
	check_eq(LoadShedder.top(), 4, "four shed levels above full quality")
	var l0 := LoadShedder.settings(0)
	check(l0["fog"] == 0.0 and l0["detail"] == 1.0 and l0["steps"] == 1.0 and l0["speed"] == 1.0,
		"level 0 is full quality with no fog and no cap")
	for i in range(1, LoadShedder.top() + 1):
		var s := LoadShedder.settings(i)
		var prev := LoadShedder.settings(i - 1)
		check(s["fog"] > 0.0, "level %d has fog" % i)
		check(s["detail"] <= prev["detail"] and s["steps"] <= prev["steps"],
			"level %d degrades detail and steps monotonically" % i)
		if i > 1:
			check(s["fog"] < prev["fog"], "level %d pulls the fog closer" % i)
		if i < LoadShedder.top():
			check_eq(s["speed"], 1.0, "level %d leaves the speed alone" % i)
	check(LoadShedder.settings(LoadShedder.top())["speed"] < 1.0, "only the top level caps the speed")
	check_eq(LoadShedder.settings(99), LoadShedder.settings(LoadShedder.top()), "levels clamp to the top")

	# --- shadows: full at level 0, halved at 1, off from level 2 ---
	check_approx(LoadShedder.settings(0)["shadow"], 1.0, "level 0 marches the full shadow")
	check_approx(LoadShedder.settings(1)["shadow"], 0.5, "level 1 halves the shadow march")
	for i in range(2, LoadShedder.top() + 1):
		check_eq(LoadShedder.settings(i)["shadow"], 0.0, "level %d skips the shadow march" % i)

	# --- no shedding while the render scale can still drop ---
	var a := LoadShedder.new()
	check_eq(_run_for(a, 3.0, SLOW, false), 0, "slow but scale not at its floor: no shed")
	check_eq(a.level, 0, "still level 0")

	# --- shed one level after 0.5 s of sustained slow frames ---
	var b := LoadShedder.new()
	_run_for(b, 0.45, SLOW)
	check_eq(b.level, 0, "0.45 s slow is not enough")
	_run_for(b, 0.05, SLOW)
	check_eq(b.level, 1, "0.5 s slow sheds one level")

	# --- at most one shed per second ---
	_run_for(b, 0.95, SLOW)
	check_eq(b.level, 1, "no second shed within 1 s")
	_run_for(b, 0.05, SLOW)
	check_eq(b.level, 2, "the second shed after the 1 s cooldown")
	_run_for(b, 10.0, SLOW)
	check_eq(b.level, LoadShedder.top(), "sustained slow frames reach the top level")
	check_eq(_run_for(b, 5.0, SLOW), 0, "and stop there")

	# --- one slow blip does not shed: the dwell resets ---
	var c := LoadShedder.new()
	for i in 20:
		_run_for(c, 0.3, SLOW)
		_run_for(c, 0.05, MID)
	check_eq(c.level, 0, "intermittent slow frames never sustain 0.5 s")

	# --- the dead band holds the level ---
	var d := LoadShedder.new()
	_run_for(d, 0.5, SLOW)
	check_eq(d.level, 1, "shed to 1")
	check_eq(_run_for(d, 30.0, MID), 0, "59 fps holds the level within the hysteresis band")

	# --- restore one level after 2 s of sustained fast frames ---
	_run_for(d, 1.95, FAST)
	check_eq(d.level, 1, "1.95 s fast is not enough to restore")
	_run_for(d, 0.05, FAST)
	check_eq(d.level, 0, "2 s fast restores one level")
	check_eq(_run_for(d, 10.0, FAST), 0, "fast frames at level 0 change nothing")
	check_eq(d.level, 0, "never below level 0")

	# --- anti-flap: a shed soon after a restore doubles the restore dwell ---
	var e := LoadShedder.new()
	_run_for(e, 0.5, SLOW)           # -> 1
	_run_for(e, 1.0, MID)            # cooldown passes
	_run_for(e, 0.5, SLOW)           # -> 2
	_run_for(e, 2.0, FAST)           # restore -> 1
	check_eq(e.level, 1, "restored to 1")
	_run_for(e, 1.0, MID)
	_run_for(e, 0.5, SLOW)           # shed again 1.5 s after the restore -> 2
	check_eq(e.level, 2, "shed again")
	check_approx(e.restore_dwell, 4.0, "a flap doubles the restore dwell")
	_run_for(e, 2.0, FAST)
	check_eq(e.level, 2, "2 s fast no longer restores")
	_run_for(e, 2.0, FAST)
	check_eq(e.level, 1, "4 s fast does")
	for i in 6:                      # keep flapping: the dwell caps at 16 s
		_run_for(e, 1.0, MID)
		_run_for(e, 0.5, SLOW)
		_run_for(e, e.restore_dwell, FAST)
	check_approx(e.restore_dwell, LoadShedder.RESTORE_DWELL_MAX, "the backoff caps at 16 s")

	# --- a restore that sticks for 10 s resets the backoff ---
	_run_for(e, 9.5, MID)
	check_approx(e.restore_dwell, LoadShedder.RESTORE_DWELL_MAX, "9.5 s after the restore it still waits 16 s")
	_run_for(e, 0.5, MID)
	check_approx(e.restore_dwell, LoadShedder.RESTORE_DWELL, "10 s after it, the backoff resets")

	# 60 fps can restore quality even on a display paced to 60 Hz.
	var paced := LoadShedder.new()
	_run_for(paced, 4.0, 1.0 / 45.0)
	check_eq(paced.level, 4, "45 fps is under target and reaches maximum shedding")
	_run_for(paced, 2.0, 1.0 / 60.0)
	check_eq(paced.level, 3, "sustained 60 fps restores one level on a paced display")

	# --- reset() returns to full quality ---
	e.reset()
	check_eq(e.level, 0, "reset() returns to level 0")
	check_approx(e.restore_dwell, LoadShedder.RESTORE_DWELL, "reset() clears the backoff")
