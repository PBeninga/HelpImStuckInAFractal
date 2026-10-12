class_name GameplaySettings
extends Resource
## Level-owned spawn, flight tuning and escape animation settings.
## ShapeList owns per-shape absolute gameplay thresholds; escape reveals a sky around the camera.
## Spawn and escape detection use doubles, never the camera's Vector3 mirror.

const DEFAULT_SKYBOX := preload("res://Assets/sky_82_2k.png")
const DURATION_KEYS := [&"escape_sky_duration", &"escape_fog_duration",
	&"escape_ground_duration", &"escape_fractal_duration"]

const NUMERIC_KEYS := [&"spawn_x", &"spawn_y", &"spawn_z",
	&"move_speed", &"shift_multiplier", &"distance_power", &"near_cap", &"max_distance_speed",
	&"surrounding_ray_count", &"depth_scan_width", &"depth_scan_interval",
	&"escape_sky_duration", &"escape_fog_duration",
	&"escape_ground_duration", &"escape_fractal_duration"]
const INTEGER_KEYS := [&"surrounding_ray_count", &"depth_scan_width", &"depth_scan_interval"]

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
## Number of rays in the agent's low-fidelity surrounding geometry sweep.
@export var surrounding_ray_count := 12:
	set(v):
		if v >= 4 and v <= 64 and v != surrounding_ray_count:
			surrounding_ray_count = v
			emit_changed()
@export var depth_scan_width := 32:
	set(v):
		if v >= 8 and v <= 128 and v != depth_scan_width:
			depth_scan_width = v
			emit_changed()
@export var depth_scan_interval := 2:
	set(v):
		if v >= 1 and v <= 30 and v != depth_scan_interval:
			depth_scan_interval = v
			emit_changed()
## Seconds from crossing the exit boundary; zero completes immediately.
@export var escape_sky_duration := 3.0:
	set(v):
		if is_finite(v) and v >= 0.0 and v != escape_sky_duration:
			escape_sky_duration = v
			emit_changed()
@export var escape_fog_duration := 3.0:
	set(v):
		if is_finite(v) and v >= 0.0 and v != escape_fog_duration:
			escape_fog_duration = v
			emit_changed()
@export var escape_ground_duration := 3.0:
	set(v):
		if is_finite(v) and v >= 0.0 and v != escape_ground_duration:
			escape_ground_duration = v
			emit_changed()
@export var escape_fractal_duration := 3.0:
	set(v):
		if is_finite(v) and v >= 0.0 and v != escape_fractal_duration:
			escape_fractal_duration = v
			emit_changed()
@export var exit_skybox: Texture2D = DEFAULT_SKYBOX:
	set(v):
		if v != exit_skybox:
			exit_skybox = v
			emit_changed()


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
	exit_skybox = DEFAULT_SKYBOX
	if not raw is Dictionary:
		return ["Malformed gameplay section ignored"]
	for key in raw:
		# Older levels may still contain the removed, independent exit radius.
		if key == "exit_radius":
			continue
		var value: Variant = raw[key]
		if NUMERIC_KEYS.has(StringName(key)):
			var valid := (value is float or value is int) and is_finite(float(value))
			if DURATION_KEYS.has(StringName(key)):
				valid = valid and float(value) >= 0.0
			elif not String(key).begins_with("spawn_"):
				valid = valid and float(value) > 0.0
			if key == "distance_power":
				valid = valid and float(value) <= 4.0
			if valid and INTEGER_KEYS.has(StringName(key)):
				var limits: Array = {"surrounding_ray_count": [4, 64], "depth_scan_width": [8, 128], "depth_scan_interval": [1, 30]}[String(key)]
				valid = float(value) == floor(float(value)) and float(value) >= limits[0] and float(value) <= limits[1]
			if valid:
				set(key, int(value) if INTEGER_KEYS.has(StringName(key)) else float(value))
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
