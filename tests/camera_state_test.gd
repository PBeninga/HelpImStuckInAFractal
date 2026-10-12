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
	_eye64()


## The 64-bit eye: the doubles are the truth, the transform's origin their rounded shadow.
func _eye64() -> void:
	var d := CameraState.make_default()
	var e0 := d.eye64()
	check_eq(e0.size(), 3, "eye64() has three entries")
	check(Vector3(e0[0], e0[1], e0[2]) == d.eye(), "the default eye's doubles are its 32-bit origin")
	check_eq(d.transform, Transform3D(Basis.IDENTITY, CameraState.DEFAULT_EYE).looking_at(Vector3.ZERO, Vector3(0, 0, 1)),
		"make_default is unchanged")
	var emits := [0]
	d.changed.connect(func(): emits[0] += 1)
	var x := 1.9600000012345678
	d.set_eye64(x, 0.914, 0.787)
	check_eq(emits[0], 1, "set_eye64 emits changed")
	check_eq(d.eye64()[0], x, "and keeps the double exactly")
	check(d.eye() == Vector3(x, 0.914, 0.787), "eye() is the rounded shadow")
	d.set_eye64(x + 1e-12, 0.914, 0.787)
	check_eq(d.eye64()[0], x + 1e-12, "a 1e-12 move round-trips")
	check(d.eye() == Vector3(x, 0.914, 0.787), "under the same 32-bit shadow")
	check_eq(emits[0], 2, "and still emits: the doubles moved")
	d.set_eye64(x + 1e-12, 0.914, 0.787)
	check_eq(emits[0], 2, "the same doubles emit nothing")
	# re-basing at the shadow origin (FlyCamera._set_forward) keeps the doubles
	d.transform = Transform3D(Basis.IDENTITY, d.eye()).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	check_eq(d.eye64()[0], x + 1e-12, "a transform whose origin is the shadow keeps the doubles")
	# a new origin (orbit camera, Reset camera) replaces them
	d.transform = Transform3D(d.transform.basis, Vector3(1, 2, 3))
	check_eq(d.eye64(), PackedFloat64Array([1.0, 2.0, 3.0]), "a new origin replaces the doubles")
