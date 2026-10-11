extends "res://call_center/tests/test_case.gd"
## The demo's sample escape route is flyable in the default Mandelbox: every leg
## clears the surface, the shortcuts to the exit do not, and the features sit
## where their kinds say (waypoints in open space, landmarks on the surface).
## Uses the explorer adapter's own trace, which the autopilot flies by.

const Features := preload("res://call_center/features.gd")
const ExplorerAdapter := preload("res://call_center/adapter/explorer_adapter.gd")


class FakeGame extends Node:
	var camera := CameraState.make_default()
	var params := FractalParams.new()
	var view: FractalView = null


func run() -> void:
	var features := Features.new()
	var data := features.load_json("res://call_center/demo/sample_route.json")
	check(not data.is_empty(), "the sample route loads")
	check_eq(features.route.size(), 4, "four waypoints")
	check_eq(features.exit_id, "9001", "the exit is #9001")
	check_eq(features.find("#2312").get("name"), "The Recursive Cul-de-sac", "lookup by '#2312'")
	check_eq(features.find(2312).get("id"), "2312", "lookup by int")

	var game := FakeGame.new()
	var adapter := ExplorerAdapter.new(game)
	var params: FractalParams = game.params
	var e: Array = data["start"]["eye"]
	var start := Vector3(e[0], e[1], e[2])
	check(DistanceEstimator.estimate(start, params) > 0.05, "the start chamber has > 50 m clearance")

	var prev := start
	for id in features.route + [features.exit_id]:
		var p: Vector3 = features.find(id)["pos"]
		check(adapter.path_clear(prev, p), "the leg to #%s is clear" % id)
		prev = p
	var rift: Vector3 = features.exit()["pos"]
	for from_id in ["start", "4096", "7071"]:
		var a: Vector3 = start if from_id == "start" else features.find(from_id)["pos"]
		check(not adapter.path_clear(a, rift), "no straight flight from %s to the exit" % from_id)
	for f in features.all():
		var d := DistanceEstimator.estimate(f["pos"], params)
		if f["kind"] == "landmark":
			check(d < 0.002, "landmark #%s is on the surface (%.5f)" % [f["id"], d])
		else:
			check(d > 0.02, "%s #%s is in open space (%.4f)" % [f["kind"], f["id"], d])
	adapter.free()
	game.free()
