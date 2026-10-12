extends "res://tests/test_case.gd"


func run() -> void:
	var params := FractalParams.new()
	var cam := CameraState.make_default()
	var view: FractalView = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	view.size = Vector2(1280, 800)
	view.setup(params, cam)
	var table := AttributeTable.new(ShapeCatalogue.specs())
	var marker := JuliaMarker.new()
	root.add_child(marker)
	marker.size = Vector2(1280, 800)
	marker.setup(params, cam, view, table)
	await frames(1)

	# hidden unless Julia is on
	check(not marker.visible, "marker hidden while Julia is off")
	params.julia_all = true
	await frames(1)
	check(marker.visible, "marker shows when Julia is on")

	# the ring sits at project(julia_point)
	var expected: Variant = view.project(params.julia_point())
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
		check_approx(table.get_default(&"c_0"), params.julia_point().x,
			"the drag wrote c_0 into the table")
		var reproj: Variant = view.project(params.julia_point())
		check(reproj != null and (reproj as Vector2).distance_to(target) < 2.0,
			"after the drag the point reprojects to the cursor")

	marker.queue_free()
	view.queue_free()
	await frames(1)
