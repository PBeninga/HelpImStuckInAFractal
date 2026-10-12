extends "res://tests/test_case.gd"


func run() -> void:
	var c := CameraState.make_default()

	# the site's default view
	check(c.eye().is_equal_approx(Vector3(8.175847, 3.812460, 3.283393)), "default eye")
	check(c.forward().is_equal_approx((Vector3.ZERO - c.eye()).normalized()),
		"forward looks at the origin")
	check_approx(c.forward().length(), 1.0, "forward is unit length")
	check_approx(c.right().dot(c.up()), 0.0, "right and up are orthogonal", 1e-5)
	check_approx(c.right().dot(c.forward()), 0.0, "right and forward are orthogonal", 1e-5)
	# +Z is the up hint: right stays horizontal
	check_approx(c.right().z, 0.0, "right is level (world +Z up hint)", 1e-5)
	check_approx(c.speed_factor, 1.0, "speed factor default")

	# setters emit changed
	var fired := [0]
	c.changed.connect(func(): fired[0] += 1)
	c.transform = Transform3D.IDENTITY
	c.speed_factor = 2.0
	check_eq(fired[0], 2, "both setters emitted changed")
	check(c.eye().is_equal_approx(Vector3.ZERO), "transform setter moved the eye")

	# assigning the value it already holds is not a change: stray input must not
	# make the governor re-render a still view
	var before: int = fired[0]
	c.transform = c.transform
	c.speed_factor = c.speed_factor
	check_eq(fired[0], before, "re-assigning the same values emits nothing")
	c.transform = c.transform.translated(Vector3(1e-7, 0, 0))
	check_eq(fired[0], before + 1, "a deep-zoom move of 1e-7 still emits")

	# --- the 64-bit eye: sub-ulp moves accumulate, the mirror follows ---
	var d := CameraState.make_default()
	check(absf(d.eye_x() - 8.175847) < 1e-6 and absf(d.eye_z() - 3.283393) < 1e-6, "the 64-bit eye starts at the default")
	var moves := [0]
	d.changed.connect(func(): moves[0] += 1)
	var x0 := d.eye_x()
	for i in 1000:
		d.move_by(Vector3(1e-9, 0, 0))   # each step is below float32's resolution at 8
	check(absf(d.eye_x() - (x0 + 1e-6)) < 1e-12, "1000 moves of 1e-9 accumulate to 1e-6 in 64-bit (%s)" % (d.eye_x() - x0))
	check_eq(moves[0], 1000, "every sub-ulp move still emits changed")
	check(absf(d.eye().x - d.eye_x()) < 1e-5, "the 32-bit mirror tracks it (%s)" % d.eye().x)
	d.set_eye(1.000000001, 2.0, 3.0)
	check(absf(d.eye_x() - 1.000000001) < 1e-15, "set_eye keeps the full 64-bit value")
	check(d.eye().is_equal_approx(Vector3(1, 2, 3)), "and mirrors it into transform.origin")
	var fwd := d.forward()
	d.set_basis(Basis.looking_at(Vector3(0, 1, 0), Vector3(0, 0, 1)))
	check(not d.forward().is_equal_approx(fwd), "set_basis turns the camera")
	check(absf(d.eye_x() - 1.000000001) < 1e-15, "without touching the 64-bit eye")
	d.transform = Transform3D(Basis.IDENTITY, Vector3(5, 5, 5))
	check(absf(d.eye_x() - 5.0) < 1e-12, "assigning a transform makes its origin the eye again")
