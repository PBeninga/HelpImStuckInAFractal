extends "res://tests/test_case.gd"

# A measured input fixture; the planner and all unit/timing calculations are real.
class MeasuredCorridor extends RefCounted:
	func cached_recommendations(_game: Node) -> Array:
		return [{"direction": [1.0, 0.0, 0.0], "neighbour_min_depth": 20.0,
			"exit_clear": true, "no_hit_fraction": 1.0}]

class Flight extends Node:
	var params := FractalParams.new()
	var camera := CameraState.new()
	var fly := FlyCamera.new()
	var ship_depth_scanner := MeasuredCorridor.new()

func run() -> void:
	await frames(1)
	var game := Flight.new()
	root.add_child(game)
	game.params.gameplay_active = 0
	game.params.gameplay.distance_scaling = false
	game.params.gameplay.move_speed = 2.0
	game.params.world_unit_size = 2.0
	game.camera.set_basis(CameraState.facing_basis(Vector3.RIGHT))
	var planner := preload("res://src/mcp/escape_planner.gd").new()
	var result: Dictionary = await planner.plan(game)
	check(result.ok, "planner accepts measured corridor")
	check_approx(result.points[0][0], 15.5, "speed-scaled boundary beyond the scan keeps a bounded leg")
	check(not result.exit_clear, "render-boundary clearance does not promise gameplay-boundary clearance")
	game.params.world_unit_size = 0.5
	game.params.gameplay.move_speed = 0.5
	result = await planner.plan(game)
	check_approx(result.points[0][0], 10.501, "a measured boundary uses the converted scene radius")
	check(result.exit_clear, "a converted boundary within measured clearance can finish the leg")
	game.params.world_unit_size = 1.0
	game.params.gameplay.move_speed = 1.0
	result = await planner.plan(game)
	check_approx(result.points[0][0], 20.502, "a boundary at the scan edge retains the small crossing margin")
	check(result.exit_clear, "matching scan and gameplay boundaries can still finish")
	game.fly.free()
	game.queue_free()
	await frames(1)
