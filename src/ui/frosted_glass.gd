extends RefCounted
## Shared glass backgrounds. Panel borders and content retain their own drawing.

const SHADER: Shader = preload("res://src/ui/frosted_glass.gdshader")


static func apply(control: PanelContainer) -> void:
	if control.has_node("GlassBackground"):
		return
	var source := control.get_theme_stylebox("panel") as StyleBoxFlat
	if source == null:
		return
	var border := source.duplicate() as StyleBoxFlat
	border.draw_center = false
	control.add_theme_stylebox_override("panel", border)
	control.material = null

	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint_color", source.bg_color)
	material.set_shader_parameter("corner_radius", float(source.corner_radius_top_left))

	# A Node2D keeps the background out of the PanelContainer's content layout.
	# Its entire subtree draws beneath the normal (including flashing) border.
	var background := Node2D.new()
	background.name = "GlassBackground"
	background.show_behind_parent = true
	control.add_child(background)
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.material = material
	background.add_child(glass)
	var resize_glass := func() -> void:
		glass.size = control.size
		material.set_shader_parameter("panel_size", control.size.max(Vector2.ONE))
	control.resized.connect(resize_glass)
	resize_glass.call()
