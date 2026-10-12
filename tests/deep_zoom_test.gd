extends "res://tests/test_case.gd"
## The deep-zoom regression: the design spec's table as one ray. A CPU copy of
## the shader's two-phase march (96 coarse steps stopping under twice the hit
## threshold, then 32 fine steps at 32 iterations), run in 64-bit from a camera
## backed off the default view's surface. With the site's fixed 16-iteration
## coarse pass the coarse surface sits further from the real one than the hit
## threshold, so the coarse pass spends its whole budget creeping toward it (the
## step count is the Ice Fractal colour: the picture darkens) or the ray runs
## out (a dark pit). With FractalParams.coarse_iters(near) it hits in under half
## the budget. At the default view the two are the same march.

const COARSE := 96
const FINE := 32
const BUDGET := COARSE + FINE


## The shader's march from `o` along unit `dir` with `coarse` iterations in the
## coarse pass. Returns [steps used, hit]: the step count the shader shades by.
func _march(o: Array, dir: Array, params: FractalParams, coarse: int) -> Array:
	var near := maxf(DistanceEstimator.scene_estimate_at(o[0], o[1], o[2], params), FractalParams.NEAR_FLOOR)
	var t := 0.0
	var n1 := COARSE
	for i in COARSE:
		var d := DistanceEstimator.scene_estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t,
			params, coarse)
		if d < params.hit_epsilon(t, near) * 2.0:
			n1 = i
			break
		t += d
	for i in FINE:
		var d := DistanceEstimator.scene_estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if d < params.hit_epsilon(t, near):
			return [n1 + i, true]
		t += d
	return [n1 + FINE, false]


func run() -> void:
	var params := FractalParams.new()
	params.shape().precision = 0.000025  # original deep-detail regression
	params.fractal_iterations = 32  # this regression exercises optional deep detail
	var s := SurfaceFixture.default_surface(params)
	var dir := [s[3], s[4], s[5]]
	check(DistanceEstimator.scene_estimate_at(s[0], s[1], s[2], params) < 1e-10, "the fixture point is on the surface")

	for back in [1e-3, 1e-5]:
		var o := [s[0] - dir[0] * back, s[1] - dir[1] * back, s[2] - dir[2] * back]
		var near := DistanceEstimator.scene_estimate_at(o[0], o[1], o[2], params)
		var fixed := _march(o, dir, params, 16)
		check(not fixed[1] or fixed[0] > 0.6 * BUDGET,
			"backed off %s (near %s): the fixed 16-iteration coarse pass uses %d of %d steps (hit %s)"
			% [back, near, fixed[0], BUDGET, fixed[1]])
		var ci := params.coarse_iters(near)
		var depth := _march(o, dir, params, ci)
		check(depth[1] and depth[0] < BUDGET / 2,
			"backed off %s: coarse_iters(near) = %d hits in %d steps (under half the budget)"
			% [back, ci, depth[0]])

	# the default view: the depth-aware count is the site's 16, so the march is identical
	var cam := SurfaceFixture.overview_camera()
	var e := cam.eye()
	var f := cam.forward()
	var near0 := DistanceEstimator.estimate(e, params)
	check_eq(params.coarse_iters(near0), 16, "the default view's coarse count is 16")
	check_eq(_march([e.x, e.y, e.z], [f.x, f.y, f.z], params, params.coarse_iters(near0)),
		_march([e.x, e.y, e.z], [f.x, f.y, f.z], params, 16), "so its march is the site's, step for step")
