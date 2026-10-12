extends "res://call_center/tests/test_case.gd"
const Tints := preload("res://src/ui/screen_tints.gd")
const Tools := preload("res://call_center/mcp/ship_tools.gd")
const Adapter := preload("res://call_center/adapter/explorer_adapter.gd")

class Game extends Node:
	var view: Node

class View extends Node:
	var screen_tints: Node

class Center extends Node:
	signal game_detached
	var adapter: Node
	var custom_tools := {}

func run() -> void:
	var tint := Tints.new()
	var view := View.new()
	view.screen_tints = tint
	var game := Game.new()
	game.view = view
	var center := Center.new()
	center.adapter = Adapter.new(game)
	var tools := Tools.new(center)
	var args: Dictionary = JSON.parse_string('{"regions":[{"center":[0.7,0.3],"radius":0.1,"color":[0,1,0]}],"seconds":2}')
	var result: Dictionary = await tools.call_tool("set_screen_tints", args)
	check(result.ok and tint.visible, "JSON tool call reaches the screen overlay")
	check_eq(tint.regions[0].center, [0.7, 0.3], "uses depth scan UV directly")
	var before := tint.regions.duplicate(true)
	result = await tools.call_tool("set_screen_tints", {"regions": [{"center": [2, 0], "radius": 0.1, "color": [1, 0, 0]}]})
	check(not result.ok and tint.regions == before, "invalid update preserves existing guidance")
	tint._process(1.0)
	check(tint.visible, "guidance remains before expiry")
	tint._process(1.0)
	check(not tint.visible and tint.regions.is_empty(), "expired marks disappear")
	await tools.call_tool("set_screen_tints", args)
	result = await tools.call_tool("clear_screen_tints", {})
	check(result.ok and not tint.visible, "clear tool removes marks")
	center.adapter.free()
	center.free()
	game.free()
	view.free()
	tint.free()
