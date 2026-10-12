extends "res://tests/test_case.gd"


func run() -> void:
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	view.size = Vector2(1280, 800)
	view.setup(params, cam)
	var shapes := ShapeList.new()
	var table := shapes.table(0)
	var marker := JuliaMarker.new()
	root.add_child(marker)
	marker.size = Vector2(1280, 800)
	marker.setup(params, cam, view, shapes)
	await frames(1)

	# hidden unless Julia is on
	check(not marker.visible, "marker hidden while Julia is off")
	params.shape().julia_all = true
	await frames(1)
	check(marker.visible, "marker shows when Julia is on")

	# the ring sits at project(julia_point)
	var expected: Variant = view.project(params.shape().julia_point())
	var got: Variant = marker.screen_point()
	check(expected != null and got != null and (got as Vector2).is_equal_approx(expected),
		"ring is drawn at the projected Julia point")

	# dragging the ring moves the point via unproject (same facing plane)
	if got != null:
		var started: bool = marker.begin_drag(got)
		check(started, "a press on the ring starts a drag")
		var target := (got as Vector2) + Vector2(40, -25)
		marker.update_drag(target)
		await frames(1)
		check_approx(table.get_default(&"c_0"), params.shape().julia_point().x,
			"the drag wrote c_0 into the table")
		var reproj: Variant = view.project(params.shape().julia_point())
		check(reproj != null and (reproj as Vector2).distance_to(target) < 2.0,
			"after the drag the point reprojects to the cursor")

	# a second, placed shape: the marker follows the ACTIVE shape and draws its
	# constant at the world position of the local point; a drag writes back the
	# constant in that shape's frame
	shapes.add({&"pos_x": 1.0, &"pos_y": -0.5, &"pos_z": 0.25, &"rot_z": 90.0, &"size": 0.2, &"julia_all": true})
	params.set_shape_count(2)
	var second := params.shape(1)
	second.apply_resolved(BindingResolver.resolve(shapes.table(1), {}, 0.0))
	params.active = 1
	await frames(1)
	check(marker.visible, "the marker shows for the active shape's Julia")
	var world := second.to_world_v(second.julia_point())
	var sp2: Variant = marker.screen_point()
	var exp2: Variant = view.project(world)
	check(sp2 != null and exp2 != null and (sp2 as Vector2).is_equal_approx(exp2),
		"the ring is at the projected world point of the placed shape's constant")
	if sp2 != null:
		check(marker.begin_drag(sp2), "a press on it starts a drag")
		var target2 := (sp2 as Vector2) + Vector2(-30, 20)
		marker.update_drag(target2)
		await frames(1)
		var t1 := shapes.table(1)
		var c := Vector3(t1.get_default(&"c_0"), t1.get_default(&"c_1"), t1.get_default(&"c_2"))
		var reproj2: Variant = view.project(second.to_world_v(c))
		check(reproj2 != null and (reproj2 as Vector2).distance_to(target2) < 2.0,
			"the drag wrote the constant in the shape's frame: it reprojects to the cursor")
		check_approx(float(shapes.table(0).get_default(&"c_0")), params.shape(0).julia_point().x,
			"the first shape's table is untouched")
		marker.end_drag()
	params.active = 0
	await frames(1)
	check(marker.visible, "back on the first shape the marker is still shown (its Julia is on)")

	marker.queue_free()
	view.queue_free()
	await frames(1)
