extends "res://tests/test_case.gd"
## A depth request must never install a second fractal raymarch draw.

func run() -> void:
	var view = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	var params := FractalParams.new()
	view.setup(params, CameraState.make_default())
	view._depth_scan._capture()
	check_eq(_ray_draws(view, view._material.shader), 1,
		"depth capture reuses display rays instead of scheduling another march")
	view.request_depth_scan({"include_grid": true})
	check_eq(_ray_draws(view, view._material.shader), 1,
		"pilot requests do not create raymarch draws")
	params.phosphor_enabled = true
	view._depth_scan._last_frame = -1000
	view._depth_scan._capture()
	check_eq(_ray_draws(view, view._material.shader), 1,
		"phosphor depth capture does not march unseen screen rows")
	view.free()
	await frames(1)


func _ray_draws(node: Node, shader: Shader) -> int:
	var count := 0
	if node is CanvasItem and node.material is ShaderMaterial and node.material.shader == shader:
		count += 1
	for child in node.get_children():
		count += _ray_draws(child, shader)
	return count
