extends Node
## The call centre's demo: the sample escape route (sample_route.json) and a
## few rules, written only against the CallCenter API, the same way a game
## would use it. It places the ship in the chamber behind the great round
## port, registers the route, and when the ship reaches the exit tells the agent
## the pilot is out and shows a banner. Enabled by CallCenter.demo
## (call_center/demo.tscn, or `-- --call-center-demo`).

const SAMPLE := "res://call_center/demo/sample_route.json"
var cc: Node
var escaped := false
var _data := {}
var _began_at := 0.0


func setup(call_center: Node) -> void:
	cc = call_center
	_data = cc.load_features_json(SAMPLE)
	cc.game_attached.connect(_on_game_attached)
	cc.exit_reached.connect(_on_exit_reached)


func _on_game_attached(_scene: Node) -> void:
	escaped = false
	var start: Dictionary = _data.get("start", {})
	if start.has("eye"):
		var e: Array = start["eye"]
		var l: Array = start["look_at"]
		cc.adapter.set_pose(Vector3(e[0], e[1], e[2]), Vector3(l[0], l[1], l[2]))
	_began_at = Time.get_ticks_msec() / 1000.0


func _on_exit_reached(_id: String) -> void:
	if escaped:
		return
	escaped = true
	cc.adapter.stop("escaped")
	cc.issues.auto_running = false
	cc.log_line("Rift handshake accepted. Punch jump resuming.", "ok")
	var secs := int(Time.get_ticks_msec() / 1000.0 - _began_at)
	cc.notify_agent("escaped", "The ship has flown into the exit rift and left fractal space. The pilot is safe. Congratulate them and sign off.",
		{"stranded_seconds": secs})
	cc.hud.show_banner("WELCOME BACK TO ORDINARY SPACE", [
		"Time stuck in fractal space: %d min %02d s" % [secs / 60, secs % 60],
		"Waypoints navigated: %d of %d" % [cc.features.visited.size(), cc.features.route.size()],
		"Issues auto-resolved: %d" % cc.issues.resolved_count,
		"",
		"Thank you for calling Sub-Dimensional Support.",
	])
