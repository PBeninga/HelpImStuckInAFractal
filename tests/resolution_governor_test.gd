extends "res://tests/test_case.gd"
## Pure step() logic on fabricated frame times. Target is 1/60 s.


func run() -> void:
	# A smooth-looking 45 fps is still too slow for our 60 fps target.
	var target := ResolutionGovernor.new()
	for i in 120: target.step(1.0 / 45.0, true)
	check(target.scale < 1.0, "45 fps reduces resolution toward the 60 fps target")
	target.min_scale = 0.1
	target.cooldown = 0.0
	for i in 600: target.step(1.0 / 45.0, true)
	check_eq(target.shedder.level, 4, "45 fps continues shedding all the way to the top")
	check_approx(target.scale, 0.1, "maximum shedding can use the 10 percent floor", 1e-6)
	target.free()

	var slow := 0.1       # 100 ms  >> 1.2 * (1/60) = 20 ms
	var fast := 0.001     # 1 ms    <  0.6 * (1/60) = 10 ms

	# --- slow frames lower the scale, but at most once per 0.5 s ---
	var g := ResolutionGovernor.new()
	g.fast_controls = true
	g.min_scale = 0.25
	g.step(slow, true)                       # first slow frame: adjusts
	check_eq(g.mode, ResolutionGovernor.Mode.CONTINUOUS, "changing => CONTINUOUS")
	check(g.scale < 1.0, "a slow frame lowered the scale")
	var after_one := g.scale
	g.step(slow, true)                       # within 0.5 s: no second change
	check_approx(g.scale, after_one, "not lowered twice within 0.5 s", 1e-6)
	# with the cooldown removed, sustained slow frames walk down to the floor
	g.cooldown = 0.0
	for i in 15: g.step(slow, true)
	check_approx(g.scale, 0.25, "sustained slow frames reach the 0.25 floor", 1e-6)

	# --- fast frames raise it again, never above 1.0 ---
	g.shedder.reset()    # the floor also shed a level; this block is the scale loop alone
	for i in 40: g.step(fast, true)
	check_approx(g.scale, 1.0, "sustained fast frames reach the 1.0 ceiling", 1e-6)

	# --- stopping: settle, then one FINAL_FRAME at scale 1, then IDLE ---
	g.step(0.016, true)                      # something is changing
	g.step(0.016, false)                     # first still frame
	check_eq(g.mode, ResolutionGovernor.Mode.SETTLING, "first still frame is SETTLING")
	for i in 7: g.step(0.016, false)         # 0.128 s quiet: still settling
	check_eq(g.mode, ResolutionGovernor.Mode.SETTLING, "still settling before 0.15 s of quiet")
	g.step(0.016, false)                     # 0.144 s
	g.step(0.016, false)                     # 0.16 s
	check_eq(g.mode, ResolutionGovernor.Mode.FINAL_FRAME, "0.15 s of quiet => FINAL_FRAME")
	check_approx(g.scale, 1.0, "final frame renders at full scale", 1e-6)
	g.step(0.016, false)                     # next still frame
	check_eq(g.mode, ResolutionGovernor.Mode.IDLE, "then it goes IDLE")

	# --- stray input while settling skips the expensive full-scale frame ---
	var st := ResolutionGovernor.new()
	st.step(0.016, true)
	var saw_final := false
	for i in 50:                             # a twitch every 0.1 s, never 0.15 s quiet
		st.step(0.016, i % 6 == 0)
		saw_final = saw_final or st.mode == ResolutionGovernor.Mode.FINAL_FRAME
	check(not saw_final, "changes every 0.1 s never trigger a final frame")
	check(st.mode != ResolutionGovernor.Mode.IDLE, "and never go idle")

	# --- Fast Controls off: scale stays 1.0, same mode logic ---
	var h := ResolutionGovernor.new()
	h.fast_controls = false
	for i in 10: h.step(slow, true)
	check_approx(h.scale, 1.0, "fast controls off keeps scale at 1.0", 1e-6)
	check_eq(h.mode, ResolutionGovernor.Mode.CONTINUOUS, "still CONTINUOUS while changing")
	h.settle = 0.0
	h.step(slow, false)
	check_eq(h.mode, ResolutionGovernor.Mode.FINAL_FRAME, "one final frame with fast off")
	h.step(slow, false)
	check_eq(h.mode, ResolutionGovernor.Mode.IDLE, "then idle with fast off")

	# --- the floor follows min_scale, and raising it lifts the scale ---
	var m := ResolutionGovernor.new()
	m.fast_controls = true
	m.cooldown = 0.0
	m.min_scale = 0.5
	for i in 20: m.step(slow, true)
	check_approx(m.scale, 0.5, "slow frames stop at min_scale", 1e-6)
	m.min_scale = 0.1
	for i in 20: m.step(slow, true)
	check(m.scale < 0.5 and m.scale >= 0.1, "a lower floor lets it drop further (%s)" % m.scale)
	m.min_scale = 0.75
	m.step(slow, true)
	check(m.scale >= 0.75, "raising the floor lifts the scale at once (%s)" % m.scale)

	# --- the shed ladder: only once the scale is at its floor ---
	var sh := ResolutionGovernor.new()
	sh.fast_controls = true
	sh.cooldown = 0.0
	sh.min_scale = 0.25
	sh.step(slow, true)
	check(sh.scale < 1.0 and sh.shedder.level == 0, "first the scale drops, no shed yet")
	for i in 12: sh.step(slow, true)         # scale reaches the floor, then 0.5 s+ slow
	check_approx(sh.scale, 0.25, "scale at its floor", 1e-6)
	check_eq(sh.shedder.level, 1, "then the shedder sheds a level")
	check_eq(sh.applied_level(), 1, "and the view gets that level while moving")

	# --- restoring: levels come off before the scale climbs ---
	var climbed_early := false
	var t := 0.0
	while sh.shedder.level > 0 and t < 5.0:
		sh.step(fast, true)
		t += fast
		if sh.shedder.level > 0 and sh.scale > 0.25 + 1e-6:
			climbed_early = true
	check_eq(sh.shedder.level, 0, "fast frames restore the level")
	check(not climbed_early, "the scale held at its floor until level 0")
	for i in 40: sh.step(fast, true)
	check(sh.scale > 0.25, "then the scale climbs (%s)" % sh.scale)

	# --- the level and the moving scale persist through idle; the final frame
	# --- renders at level 0 and full scale ---
	var p := ResolutionGovernor.new()
	p.fast_controls = true
	p.min_scale = 0.25
	p.cooldown = 0.0
	p.settle = 0.0
	for i in 20: p.step(slow, true)
	var moving_scale := p.scale
	var moving_level := p.shedder.level
	check(moving_level >= 1, "shed while moving (level %d)" % moving_level)
	p.step(0.016, false)
	check_eq(p.mode, ResolutionGovernor.Mode.FINAL_FRAME, "stopped: final frame")
	check_eq(p.applied_level(), 0, "the final frame renders at level 0")
	check_approx(p.scale, 1.0, "at full scale", 1e-6)
	p.step(0.016, false)
	check_eq(p.applied_level(), 0, "idle stays at level 0")
	check_eq(p.shedder.level, moving_level, "the shed level is remembered through idle")
	p.step(0.03, true)
	check_approx(p.scale, moving_scale, "moving again resumes at the moving scale", 1e-6)
	check_eq(p.applied_level(), moving_level, "and at the remembered level")

	# --- turning Fast Controls off drops back to full quality ---
	p.fast_controls = false
	p.step(0.03, true)
	check_eq(p.shedder.level, 0, "fast controls off resets the shed level")

	for n in [g, st, h, m, sh, p]:
		n.free()
