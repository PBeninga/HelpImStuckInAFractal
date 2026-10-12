extends "res://tests/test_case.gd"
## The Mandelbulb CPU estimator: captured fixtures, the knobs each matter, the
## classic bulb's symmetries (a mirror in y, and a turn of 360/(n - 1) degrees
## about z), w ignored (it is 3D), and the escape radius that bounds it.


func _de(p: Vector3, params: ShapeParams, expected: float, label: String) -> void:
	var got := MandelbulbEstimator.estimate_at(p.x, p.y, p.z, params)
	var tol := maxf(1e-9, 1e-5 * absf(expected))
	check(absf(got - expected) <= tol, "%s: expected %s got %s (tol %s)" % [label, expected, got, tol])


func _bulb() -> ShapeParams:
	var p := ShapeParams.new()
	p.shape = FractalParams.Shape.MANDELBULB
	return p


func _d(p: Vector3, params: ShapeParams) -> float:
	return MandelbulbEstimator.estimate_at(p.x, p.y, p.z, params)


func run() -> void:
	var b := _bulb()
	_de(Vector3(1.2, -0.3, 0.8), b, 0.27918556994179683, "default (1.2,-0.3,0.8)")
	_de(Vector3(0.5, 0.5, 0.5), b, 0.005105471095993192, "default (0.5,0.5,0.5)")
	_de(Vector3(0.1, 0.9, 0.6), b, 0.021859336558981302, "default (0.1,0.9,0.6)")
	_de(Vector3(0.7, 0.2, -0.65), b, 0.0002776822353474958, "default (0.7,0.2,-0.65)")
	var j := _bulb(); j.mandelbulb_julia = true; j.mandelbulb_power = 6.0
	_de(Vector3(1.2, -0.3, 0.8), j, 0.3085462364907737, "Julia power 6 (1.2,-0.3,0.8)")
	_de(Vector3(0.3, 0.6, 0.2), j, 0.026874741816201458, "Julia power 6 (0.3,0.6,0.2)")
	var ph := _bulb(); ph.mandelbulb_phase_theta = 40.0; ph.mandelbulb_phase_phi = -25.0; ph.mandelbulb_power = 3.0
	_de(Vector3(1.2, -0.3, 0.8), ph, 0.13438412439176003, "phased power 3 (1.2,-0.3,0.8)")
	_de(Vector3(0.3, 0.6, 0.2), ph, 0.0003274602370423045, "phased power 3 (0.3,0.6,0.2)")
	check(DistanceEstimator.estimate_at(1.2, -0.3, 0.8, b) == MandelbulbEstimator.estimate_at(1.2, -0.3, 0.8, b),
		"DistanceEstimator hands the Mandelbulb to MandelbulbEstimator")

	# --- the classic bulb's symmetries ---
	# In 64-bit scalars: a Vector3 rounds to 32 bits, and orbits near the
	# surface amplify that.
	var turn := TAU / 7.0   # power 8: a turn of 360/7 degrees about z
	for q in [[0.7, 0.3, 0.55], [1.0, -0.4, 0.2], [0.2, 0.8, -0.6]]:
		var dq := MandelbulbEstimator.estimate_at(q[0], q[1], q[2], b)
		check_approx(MandelbulbEstimator.estimate_at(q[0], -q[1], q[2], b), dq, "D mirrors in y at %s" % [q],
			1e-9 + 1e-6 * absf(dq))
		var rx: float = q[0] * cos(turn) - q[1] * sin(turn)
		var ry: float = q[0] * sin(turn) + q[1] * cos(turn)
		check_approx(MandelbulbEstimator.estimate_at(rx, ry, q[2], b), dq, "D repeats every 360/7 degrees about z at %s" % [q],
			1e-9 + 1e-6 * absf(dq))

	# --- far outside, near the surface, inside ---
	check(_d(Vector3(3.0, 0.0, 0.0), b) > 1.0, "far outside, the distance is large")
	check(_d(Vector3(0.0, 0.0, 0.0), b) <= 0.0, "the origin is inside (it never escapes)")

	# --- the knobs ---
	var base := _d(Vector3(0.6, 0.4, 0.5), b)
	for knob in [[&"mandelbulb_power", 6.0], [&"mandelbulb_phase_theta", 30.0], [&"mandelbulb_phase_phi", 30.0],
			[&"mandelbulb_julia", true]]:
		var c := _bulb()
		c.set(knob[0], knob[1])
		check(absf(_d(Vector3(0.6, 0.4, 0.5), c) - base) > 1e-6, "'%s' changes the distance" % knob[0])
	var jc := _bulb(); jc.mandelbulb_julia = true
	var jbase := _d(Vector3(0.6, 0.4, 0.5), jc)
	for i in 3:
		var c := _bulb(); c.mandelbulb_julia = true
		c.set(StringName("mandelbulb_c_%d" % i), 0.1)
		check(absf(_d(Vector3(0.6, 0.4, 0.5), c) - jbase) > 1e-6, "Julia constant %d changes the distance" % i)
	var cw := _bulb(); cw.mandelbulb_c_0 = 0.9
	check_eq(_d(Vector3(0.6, 0.4, 0.5), cw), base, "the constant does nothing while Julia is off")
	var ww := _bulb(); ww.w = 1.5
	check_eq(_d(Vector3(0.6, 0.4, 0.5), ww), base, "w does nothing: the Mandelbulb is 3D")

	# --- the escape radius, the bound and the bailout ---
	check_approx(MandelbulbEstimator.escape_radius(b), pow(2.0, 1.0 / 7.0), "power 8 escapes past 2^(1/7)")
	check_eq(b.bound_half(), 2.0, "so the cube is the usual 2")
	check_eq(MandelbulbEstimator.bailout(b), 2.0, "and so is the bailout")
	var low := _bulb(); low.mandelbulb_power = 1.5
	check_approx(low.bound_half(), 4.0, "power 1.5 reaches 2^(1/0.5) = 4")
	var far := _bulb(); far.mandelbulb_julia = true
	far.mandelbulb_c_0 = 3.0; far.mandelbulb_c_1 = 0.0; far.mandelbulb_c_2 = 0.0
	check_approx(far.bound_half(), 3.0, "a Julia constant past the escape radius widens the cube to |c|")
	check_approx(MandelbulbEstimator.bailout(far), 3.0, "and the bailout with it")
	for q in [Vector3(1.11, 0.0, 0.0), Vector3(0.0, 0.0, -1.11), Vector3(0.7, 0.7, 0.5)]:
		check(_d(q, b) > 0.0, "every point past the escape radius is outside: %s" % q)

	# --- the rest of ShapeParams ---
	check_eq(b.coarse_iters(3.0), 16, "the coarse pass runs the usual 16 iterations at a normal distance")
	check_approx(b.view_distance(), 0.0, "rays do not stop early")
	check(not b.julia_enabled(), "no Julia marker off the Mandelbox")
	b.mandelbulb_julia = true
	check(not b.julia_enabled(), "not even in the Mandelbulb's Julia mode")
