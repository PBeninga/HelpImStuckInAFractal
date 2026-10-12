extends "res://tests/test_case.gd"
const Overlay := preload("res://call_center/hud/feature_overlay.gd")

func run() -> void:
	var pose := {"position": Vector3.ZERO, "forward": Vector3.RIGHT, "right": Vector3.UP, "up": Vector3.BACK}
	var screen := Vector2(1000, 600)
	for case in [
		[Vector3(1, 1, 0), "Turn right"],
		[Vector3(1, -1, 0), "Turn left"],
		[Vector3(1, 0, 1), "Look up"],
		[Vector3(1, 0, -1), "Look down"],
		[Vector3(-1, 0, 0), "Turn right"],
		[Vector3(-1, -0.1, 0), "Turn left"],
		[Vector3(1, 0, 0), "Facing target"],
		[Vector3.ZERO, "Facing target"],
	]:
		var guide := Overlay.direction_guide(pose, case[0], screen)
		check_eq(guide.instruction, case[1], "target direction")
		check(Rect2(Vector2.ZERO, screen).has_point(guide.position), "arrow stays within viewport")
	var target := Vector3(0, 10, 0)
	pose.forward = Vector3.UP
	pose.right = Vector3.LEFT
	check(Overlay.direction_guide(pose, target, screen).aligned, "turning camera toward target aligns cue")
	var overlay := Overlay.new()
	overlay.point_direction(target, "Look here", 2.0)
	overlay._process(1.0)
	check(not overlay.direction_target.is_empty(), "arrow remains during lifetime")
	overlay._process(1.0)
	check(overlay.direction_target.is_empty(), "arrow expires")
	overlay.point_direction(target, "Look here", 20.0)
	overlay.clear()
	check(overlay.direction_target.is_empty(), "clearing MCP highlights removes arrow")
	overlay.free()
