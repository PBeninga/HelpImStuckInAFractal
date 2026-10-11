extends Node
## Starts the game with the call centre attached, without changing the game or
## the project settings: it puts CallCenter at /root/CallCenter (where an
## autoload would sit) and then loads the game's own main scene, so the title
## menu, Play and Back to Menu all work as usual. If CallCenter is already
## there (say it is registered as an autoload one day), it is reused.

const CallCenter := preload("res://call_center/call_center.gd")

## Load the sample escape route and its rules (demo/).
@export var demo := false
## The scene to start; empty = the project's main scene. The demo goes straight
## to the cockpit.
@export_file("*.tscn") var scene := ""


func _ready() -> void:
	var root := get_tree().root
	if root.get_node_or_null(^"CallCenter") == null:
		var cc := CallCenter.new()
		cc.name = "CallCenter"
		cc.demo = demo or "--call-center-demo" in OS.get_cmdline_user_args()
		root.add_child.call_deferred(cc)
	var target := scene
	if target == "" or not ResourceLoader.exists(target):
		target = str(ProjectSettings.get_setting("application/run/main_scene"))
	get_tree().change_scene_to_file.call_deferred(target)
