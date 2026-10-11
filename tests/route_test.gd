extends "res://tests/test_case.gd"
## The escape route is flyable in the default Mandelbox: every leg clears the
## surface, the shortcuts to the rift do not, and the features sit where their
## kinds say (waypoints in open space, landmarks on the surface).


func run() -> void:
	var params := FractalParams.new()

	# ids are unique, and lookups accept "#2312", "2312" and 2312
	var ids := {}
	for f in Route.FEATURES:
		check(not ids.has(f["id"]), "feature id %s is unique" % f["id"])
		ids[f["id"]] = true
	check_eq(Route.feature("#2312").get("name"), "The Recursive Cul-de-sac", "lookup by '#2312'")
	check_eq(Route.feature(2312).get("id"), "2312", "lookup by int")
	check(Route.feature("nope").is_empty(), "an unknown id is {}")

	var wps := Route.waypoints()
	check_eq(wps.size(), 5, "four waypoints and the exit")
	check_eq(wps[-1]["id"], Route.EXIT_ID, "the route ends at the rift")
	check(wps[-1]["pos"].is_equal_approx(Route.RIFT_POS), "the exit feature is the rift")

	# the start chamber has room to breathe
	var start_d := DistanceEstimator.estimate(Route.START_EYE, params)
	check(start_d > 0.05, "the start has > 50 m clearance (%.4f)" % start_d)
	check(Route.start_transform().origin.is_equal_approx(Route.START_EYE), "start transform sits at START_EYE")

	# every leg is clear, sampled finely and by the sphere trace
	var prev: Vector3 = Route.START_EYE
	for w in wps:
		var c := Route.segment_clearance(prev, w["pos"], params)
		check(c >= Route.LOS_CLEARANCE, "leg to #%s clears %.4f >= %.3f" % [w["id"], c, Route.LOS_CLEARANCE])
		check(Route.path_clear(prev, w["pos"], params), "leg to #%s is path_clear" % w["id"])
		prev = w["pos"]

	# no shortcuts to the rift
	for from_id in ["start", "4096", "7071"]:
		var a: Vector3 = Route.START_EYE if from_id == "start" else Route.feature(from_id)["pos"]
		check(not Route.path_clear(a, Route.RIFT_POS, params), "no straight flight from %s to the rift" % from_id)

	# waypoints in open space, landmarks on the surface
	for f in Route.FEATURES:
		var d := DistanceEstimator.estimate(f["pos"], params)
		if f["kind"] == "landmark":
			check(d < 0.002, "landmark #%s is on the surface (%.5f)" % [f["id"], d])
		else:
			check(d > 0.02, "%s #%s is in open space (%.4f)" % [f["kind"], f["id"], d])

	check_eq(Route.meters(0.0231), 23, "metres round to the nearest metre")
