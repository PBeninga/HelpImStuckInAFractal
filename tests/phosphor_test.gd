extends "res://tests/test_case.gd"
## The ray viewport must shrink, every row must be visited, and the governor's
## idle freeze must not stop scanning. History is reset at size/toggle changes.

func run() -> void:
	var params := FractalParams.new()
	var has_phosphor := false
	for prop in params.get_property_list():
		if prop.name == "phosphor_enabled":
			has_phosphor = true
	check(has_phosphor, "renderer offers opt-in phosphor scanning")
	if not has_phosphor:
		return
	await _exercise(params)


func _exercise(params: FractalParams) -> void:
	var view = load("res://src/fractal/fractal_view.tscn").instantiate()
	root.add_child(view)
	await frames(1)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(320, 101)
	view.setup(params, CameraState.make_default())
	check_eq(view._viewport.size, Vector2i(320, 101), "disabled mode marches full frame")
	# Stage activation resets history even when the optional effect is off.
	# It must not remap full-frame rays using an unconfigured history height.
	var initial_offset: Variant = view._material.get_shader_parameter("scan_y_offset")
	var initial_scale: Variant = view._material.get_shader_parameter("scan_y_scale")
	view._phosphor.reset_history()
	check_eq(view._material.get_shader_parameter("scan_y_offset"), initial_offset, "inactive startup reset preserves ray origin")
	check_eq(view._material.get_shader_parameter("scan_y_scale"), initial_scale, "inactive startup reset preserves vertical field of view")
	params.set("phosphor_bands", 8)
	params.set("phosphor_enabled", true)
	var scan = view._phosphor
	check_eq(view._viewport.size, Vector2i(320, 13), "scan marches at most 13 of 101 rows")
	check_eq(scan.history.size, Vector2i(320, 101), "history retains full output size")
	check_eq(view._display.texture, scan.output.get_texture(), "display and capture use the complete styled output")
	check_eq(scan.history.get_parent(), scan.output, "history is drawn before presentation")
	params.phosphor_glow = 0.7
	check_eq(view._display.texture, scan.output.get_texture(), "parameter edits preserve the complete phosphor output")
	params.painterly_enabled = true
	check_eq(view._paint_rect.texture, scan.output.get_texture(), "painting samples the complete phosphor output, not a scan strip")
	check_eq(view._display.texture, view._paint_viewport.get_texture(), "combined modes present the painted output")
	check_eq(scan.output.get_parent(), view._paint_viewport, "phosphor completes before its painting pass")
	params.phosphor_enabled = false
	check_eq(view._display.texture, view._paint_viewport.get_texture(), "disabling phosphor preserves painting")
	check_eq(view._paint_rect.texture, view._viewport.get_texture(), "painting returns to full-frame rays")
	params.phosphor_enabled = true
	params.painterly_enabled = false
	check_eq(view._display.texture, scan.output.get_texture(), "disabling painting preserves phosphor")
	check_eq(scan.output.get_parent(), scan, "phosphor detaches from the disabled painting target")
	check_eq(view._viewport.get_parent(), scan.history, "march viewport draws before its parent history")
	check_eq(scan.history.render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "new history clears once")
	view.set_continuous(false)
	check_eq(view._viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "governor idle keeps scan alive")
	var covered := 0
	for i in 8:
		scan.draw_frame()
		check_eq(int(scan.strip.position.y), covered, "bands cover each row without gaps")
		covered += mini(int(scan.strip.size.y), 101 - covered)
		check(view._viewport.size.y <= 13, "march target stays below full-frame height")
	check_eq(covered, 101, "one sweep visits every row exactly once, including odd tail")
	scan._process(0.1)
	scan.draw_frame()
	check(scan.fade.color.a > 0.0 and scan.fade.color.a < 1.0, "later frames decay history instead of clearing it")
	check_eq(int(scan.strip.position.y), 0, "stationary scan wraps to the top")
	check_approx(float(view._material.get_shader_parameter("scan_y_scale")), 13.0 / 101.0, "strip rays use full-frame coordinates")
	view._depth_scan._capture()
	var depth_material: ShaderMaterial = view._depth_scan._rect.material
	check_approx(float(depth_material.get_shader_parameter("scan_y_offset")), 0.0, "navigation depth starts at the top of the full screen")
	check_approx(float(depth_material.get_shader_parameter("scan_y_scale")), 1.0, "navigation depth covers the full screen during phosphor scanning")
	check_approx(float(view._material.get_shader_parameter("scan_y_scale")), 13.0 / 101.0, "depth capture preserves the display scan strip")
	view.set_render_scale(0.5)
	check_eq(scan.history.size, Vector2i(160, 51), "history follows resolution governor")
	check_eq(scan.history.render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "resize clears stale history")
	scan.draw_frame()
	check_eq(int(scan.strip.position.y), 0, "resize restarts reconstruction")
	params.set("phosphor_enabled", false)
	check_eq(view._viewport.get_parent(), view, "disable restores original viewport parent")
	check_eq(view._viewport.size, Vector2i(160, 51), "disable restores full-frame marching")
	check_eq(view._display.material, null, "disable removes phosphor presentation")
	check_approx(float(view._material.get_shader_parameter("scan_y_scale")), 1.0, "disable restores original ray coordinates")
	# Resize after disabling: the retained history now has a different height.
	view.size = Vector2(400, 240)
	scan.reset_history()
	check_approx(float(view._material.get_shader_parameter("scan_y_offset")), 0.0, "inactive reset after resizing preserves ray origin")
	check_approx(float(view._material.get_shader_parameter("scan_y_scale")), 1.0, "inactive reset after resizing preserves full-frame projection")
	view.size = Vector2(320, 101)
	params.set("phosphor_enabled", true)
	check_eq(scan.history.render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "reenable clears previous session")
	params.set("phosphor_bands", 32)
	view.set_render_scale(0.1)
	check_eq(view._viewport.size, Vector2i(32, 2), "tiny scan target remains drawable with a two-row minimum")
	check_eq(view._rect.size, Vector2(32, 2), "ray quad fills the clamped target")
	check_eq(scan.strip.size, Vector2(32, 2), "history copies both clamped rows")
	view.size = Vector2.ONE
	check_eq(scan.history.size, Vector2i(2, 2), "tiny history remains drawable")
	check_eq(view._viewport.size, Vector2i(2, 2), "tiny ray target remains drawable")
	check_eq(scan.fade.size, Vector2(2, 2), "fade fills the clamped history")
	view.size = Vector2(320, 101)
	var panel := RendererOptions.new()
	root.add_child(panel)
	panel.setup(params)
	panel.phosphor_check.set_pressed(false)
	check(not params.get("phosphor_enabled"), "UI toggle changes renderer mode")
	panel.phosphor_check.set_pressed(true)
	panel.phosphor_bands_slider.value = 16
	await frames(1)
	check_eq(params.get("phosphor_bands"), 16, "UI controls scan ray budget")
	panel.reset_defaults()
	check(not params.get("phosphor_enabled"), "renderer reset disables phosphor")
	panel.free()
	params.set("phosphor_enabled", true)
	params.set("phosphor_bands", 12)
	params.set("phosphor_decay", 0.8)
	params.set("phosphor_glow", 0.7)
	var saved := Workspace.capture(ShapeList.new(), AttributeTable.new(ShapeCatalogue.scene_specs()), Keymap.new(), params, CameraState.make_default())
	check_eq(saved.fractal.phosphor_enabled, true, "workspace stores scan mode")
	check_eq(saved.fractal.phosphor_bands, 12, "workspace stores scan budget")
	check_approx(saved.fractal.phosphor_decay, 0.8, "workspace stores decay")
	check_approx(saved.fractal.phosphor_glow, 0.7, "workspace stores glow")
	var restored := FractalParams.new()
	Workspace.restore(saved, ShapeList.new(), AttributeTable.new(ShapeCatalogue.scene_specs()), Keymap.new(), restored, CameraState.make_default())
	check(restored.get("phosphor_enabled"), "loading restores scan mode")
	check_eq(restored.get("phosphor_bands"), 12, "loading restores scan budget")
	check_approx(restored.get("phosphor_decay"), 0.8, "loading restores decay")
	check_approx(restored.get("phosphor_glow"), 0.7, "loading restores glow")
	for key in ["phosphor_enabled", "phosphor_bands", "phosphor_decay", "phosphor_glow"]:
		saved.fractal.erase(key)
	Workspace.restore(saved, ShapeList.new(), AttributeTable.new(ShapeCatalogue.scene_specs()), Keymap.new(), restored, CameraState.make_default())
	check(not restored.get("phosphor_enabled"), "loading legacy level disables scan mode")
	view.queue_free()
	await frames(1)
