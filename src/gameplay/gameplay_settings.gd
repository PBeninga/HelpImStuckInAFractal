class_name GameplaySettings
extends Resource
## Level-owned spawn, flight tuning and a spherical exit/background at world
## origin. The optional skybox is an equirectangular Texture2D on this sphere.
## Spawn and escape detection use doubles, never the camera's Vector3 mirror.

const NUMERIC_KEYS := [&"exit_radius", &"spawn_x", &"spawn_y", &"spawn_z",
	&"move_speed", &"shift_multiplier", &"distance_power", &"near_cap", &"max_distance_speed"]

@export var exit_radius := 20.0:
	set(v):
		if _positive(v) and v != exit_radius:
			exit_radius = v
			emit_changed()
@export var spawn_x := 0.0:
	set(v):
		if is_finite(v) and v != spawn_x:
			spawn_x = v
			emit_changed()
@export var spawn_y := 0.0:
	set(v):
		if is_finite(v) and v != spawn_y:
			spawn_y = v
			emit_changed()
@export var spawn_z := 0.0:
	set(v):
		if is_finite(v) and v != spawn_z:
			spawn_z = v
			emit_changed()
@export var move_speed := 1.0:
	set(v):
		if _positive(v) and v != move_speed:
			move_speed = v
			emit_changed()
@export var shift_multiplier := 2.0:
	set(v):
		if _positive(v) and v != shift_multiplier:
			shift_multiplier = v
			emit_changed()
@export var distance_scaling := true:
	set(v):
		if v != distance_scaling:
			distance_scaling = v
			emit_changed()
@export var distance_power := 1.0:
	set(v):
		if _positive(v) and v <= 4.0 and v != distance_power:
			distance_power = v
			emit_changed()
@export var near_cap := 10.0:
	set(v):
		if _positive(v) and v != near_cap:
			near_cap = v
			emit_changed()
@export var max_distance_speed := 20.0:
	set(v):
		if _positive(v) and v != max_distance_speed:
			max_distance_speed = v
			emit_changed()
@export var exit_skybox: Texture2D:
	set(v):
		if v != exit_skybox:
			exit_skybox = v
			emit_changed()


func is_outside(camera: CameraState) -> bool:
	# Scale before squaring, avoiding overflow for large world coordinates.
	var x := camera.eye_x() / exit_radius
	var y := camera.eye_y() / exit_radius
	var z := camera.eye_z() / exit_radius
	return x * x + y * y + z * z > 1.0


func return_to_spawn(camera: CameraState) -> void:
	camera.set_eye(spawn_x, spawn_y, spawn_z)
	camera.speed_factor = 1.0


func to_dict() -> Dictionary:
	var out := {"distance_scaling": distance_scaling}
	for key in NUMERIC_KEYS:
		out[String(key)] = get(key)
	if exit_skybox != null and not exit_skybox.resource_path.is_empty():
		out["exit_skybox"] = exit_skybox.resource_path
	return out


## Missing fields reset to defaults, so loading an older level cannot inherit
## the previous level's gameplay. Keep this Resource's identity for listeners.
func apply_dict(raw: Variant) -> Array:
	var warnings: Array = []
	var defaults := GameplaySettings.new()
	for key in NUMERIC_KEYS:
		set(key, defaults.get(key))
	distance_scaling = true
	exit_skybox = null
	if not raw is Dictionary:
		return ["Malformed gameplay section ignored"]
	for key in raw:
		var value: Variant = raw[key]
		if NUMERIC_KEYS.has(StringName(key)):
			var valid := (value is float or value is int) and is_finite(float(value))
			if not String(key).begins_with("spawn_"):
				valid = valid and float(value) > 0.0
			if key == "distance_power":
				valid = valid and float(value) <= 4.0
			if valid:
				set(key, float(value))
			else:
				warnings.append("Malformed gameplay '%s' ignored" % key)
		elif key == "distance_scaling" and value is bool:
			distance_scaling = value
		elif key == "exit_skybox" and value is String and value.begins_with("res://") and ResourceLoader.exists(value, "Texture2D"):
			exit_skybox = load(value) as Texture2D
		else:
			warnings.append("Unknown or malformed gameplay '%s' ignored" % key)
	return warnings


func _positive(value: float) -> bool:
	return is_finite(value) and value > 0.0
