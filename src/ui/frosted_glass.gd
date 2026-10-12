extends RefCounted
## Shared screen-glass material for the cockpit panels.

const SHADER: Shader = preload("res://src/ui/frosted_glass.gdshader")


static func apply(control: CanvasItem) -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	control.material = material
