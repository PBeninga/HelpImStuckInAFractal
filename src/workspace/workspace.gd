class_name Workspace
extends RefCounted
## Saving and loading a view as JSON, version 2: the shape as an AttributeTable
## (defaults + active bindings), the axis values, the non-shape preference
## fields, and the camera. The clock and the keymap are deliberately not saved
## (a level loads a view and a keymap separately, and the same view plays under
## different key pairs).
##
## What else is saved under "fractal": fast controls, the camera mode, the mouse
## sensitivity and the renderer options (level of detail, step budget and
## minimum render scale). What is not: anything derivable (the orbit centre, the
## governor's render scale, rendered pixels).
##
## Loading never fails on unfamiliar content: an unknown shape id or axis id is
## skipped with a warning, and a key the file lacks leaves the current value
## alone — except the fractal (`shape`), which a file from before there was a
## choice lacks, and which then loads as the Mandelbox it was saved from. A version-1 file (the old flat "fractal" section) is migrated to the
## new ids without a warning. Saving always writes version 2.

const VERSION := 2

## The preference and renderer fields kept under "fractal" (everything that is
## not a shape knob), in file order.
const FRACTAL_KEYS: Array[String] = [
	"fast_controls", "camera_mode", "mouse_sensitivity",
	"detail", "detail_range", "detail_falloff", "max_steps", "min_render_scale",
]
const CAMERA_MODE_NAMES: Array[String] = ["fly", "orbit"]


## Snapshot the view. Pure: it reads, it does not change anything.
static func capture(table: AttributeTable, axes: Axes, params: FractalParams, camera: CameraState, noise := {}) -> Dictionary:
	var fractal := {}
	for key in FRACTAL_KEYS:
		var value: Variant = params.get(key)
		if key == "camera_mode":
			value = CAMERA_MODE_NAMES[int(value)]
		fractal[key] = value
	var out := {
		"version": VERSION,
		"shape": table.to_dict(),
		"axes": axes.values_by_string(),
		"fractal": fractal,
		"camera": {
			"eye": _vec_to_array(camera.eye()),
			"forward": _vec_to_array(camera.forward()),
			"up": _vec_to_array(camera.up()),
			"speed_factor": camera.speed_factor,
		},
	}
	if not noise.is_empty():
		out["noise"] = noise
	return out


## Apply a capture (already in version-2 shape). Returns the warnings.
static func restore(data: Dictionary, table: AttributeTable, axes: Axes, params: FractalParams, camera: CameraState) -> Array:
	var warnings: Array = []

	var shape: Variant = data.get("shape", {})
	if shape is Dictionary:
		# Views saved before there was a choice of fractal are all Mandelboxes.
		var defaults: Variant = (shape as Dictionary).get("defaults", {})
		if defaults is Dictionary and not (defaults as Dictionary).has("shape") and table.has(&"shape"):
			table.set_default(&"shape", FractalParams.Shape.MANDELBOX)
		for w in table.apply_dict(shape):
			warnings.append(w)
	else:
		warnings.append("Malformed shape section ignored")

	var axis_values: Variant = data.get("axes", {})
	if axis_values is Dictionary:
		for key in axis_values:
			var id := StringName(key)
			if not axes.has(id):
				warnings.append("Axis value for unknown axis '%s' dropped" % key)
				continue
			var v: Variant = axis_values[key]
			if v is float or v is int:
				axes.set_value(id, float(v))
			else:
				warnings.append("Malformed axis value '%s' ignored" % key)
	else:
		warnings.append("Malformed axes section ignored")

	var fractal: Variant = data.get("fractal", {})
	if fractal is Dictionary:
		for key in fractal:
			if not FRACTAL_KEYS.has(key):
				warnings.append("Unknown fractal value '%s' ignored" % key)
				continue
			var value: Variant = _parse_fractal(key, fractal[key])
			if value == null:
				warnings.append("Malformed '%s' ignored" % key)
				continue
			params.set(key, value)
	else:
		warnings.append("Malformed fractal section ignored")

	var cam: Variant = data.get("camera", {})
	if cam is Dictionary:
		_restore_camera(cam, camera, warnings)
	else:
		warnings.append("Malformed camera section ignored")

	return warnings


static func save_file(path: String, table: AttributeTable, axes: Axes, params: FractalParams, camera: CameraState, noise := {}) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(capture(table, axes, params, camera, noise), "\t", false))
	file.close()
	return OK


## Read `path` and restore it. Never throws. A version-1 file is migrated to the
## version-2 shape before restoring, without a warning.
static func load_file(path: String, table: AttributeTable, axes: Axes, params: FractalParams, camera: CameraState) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("No saved view at %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not read %s (error %d)" % [path, FileAccess.get_open_error()])
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("%s is not valid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
	var data: Variant = json.data
	if not (data is Dictionary):
		return _failure("%s does not contain a saved view" % path)
	var version := int((data as Dictionary).get("version", 0))
	if version == 1:
		data = _migrate_v1(data)
	elif version != VERSION:
		return _failure("Save version %d is not supported (this build reads version %d)" % [version, VERSION])
	var noise: Variant = (data as Dictionary).get("noise", null)
	if not (noise is Dictionary):
		noise = null
	return {"ok": true, "warnings": restore(data, table, axes, params, camera), "noise": noise}


## A graph-only noise file: {"version": VERSION, "noise": {...}}.
static func save_noise_file(path: String, noise_dict: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "noise": noise_dict}, "\t", false))
	file.close()
	return OK


## Read a graph-only noise file. Returns {ok, warnings, noise}. Accepts version
## 1 and 2 (the noise section is the same in both).
static func load_noise_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "warnings": ["No noise graph at %s" % path], "noise": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "warnings": ["Could not read %s" % path], "noise": {}}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "warnings": ["%s is not valid JSON" % path], "noise": {}}
	var data: Variant = json.data
	if not (data is Dictionary):
		return {"ok": false, "warnings": ["%s does not contain a noise graph" % path], "noise": {}}
	var version := int((data as Dictionary).get("version", 0))
	if version != 1 and version != VERSION:
		return {"ok": false, "warnings": ["Noise file version %d is not supported" % version], "noise": {}}
	var noise: Variant = (data as Dictionary).get("noise", {})
	if not (noise is Dictionary):
		return {"ok": false, "warnings": ["%s has no noise section" % path], "noise": {}}
	return {"ok": true, "warnings": [], "noise": noise}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "warnings": [message]}


## Turn a version-1 file (flat "fractal" section with the old ids) into the
## version-2 shape. Unknown/new ids are mapped; the clock and axes had no v1.
static func _migrate_v1(data: Dictionary) -> Dictionary:
	var old: Dictionary = data.get("fractal", {}) if data.get("fractal", {}) is Dictionary else {}
	var defaults := {}
	var rename := {
		"scale": "box_scale", "inner_radius": "min_radius", "outer_radius": "fixed_radius",
		"fold_limit": "fold_limit", "color_mode": "color_mode", "precision": "precision",
		"julia_enabled": "julia_all",
	}
	for k in rename:
		if old.has(k):
			defaults[rename[k]] = old[k]
	if old.has("julia_point") and old["julia_point"] is Array and (old["julia_point"] as Array).size() == 3:
		var jp: Array = old["julia_point"]
		defaults["c_0"] = jp[0]
		defaults["c_1"] = jp[1]
		defaults["c_2"] = jp[2]
	var fractal := {}
	for k in FRACTAL_KEYS:
		if old.has(k):
			fractal[k] = old[k]
	var out := {
		"version": VERSION,
		"shape": {"defaults": defaults, "bindings": {}},
		"axes": {},
		"fractal": fractal,
		"camera": data.get("camera", {}),
	}
	if data.has("noise"):
		out["noise"] = data["noise"]
	return out


## The typed value for one "fractal" key, or null when malformed.
static func _parse_fractal(key: String, raw: Variant) -> Variant:
	match key:
		"fast_controls":
			return raw if raw is bool else null
		"camera_mode":
			var index := CAMERA_MODE_NAMES.find(String(raw)) if raw is String else -1
			return index if index >= 0 else null
		"precision", "mouse_sensitivity", "detail", "detail_range", "min_render_scale":
			return float(raw) if (raw is float or raw is int) and float(raw) > 0.0 else null
		"detail_falloff":
			return float(raw) if (raw is float or raw is int) and float(raw) >= 0.0 else null
		"max_steps":
			return int(raw) if (raw is float or raw is int) and float(raw) >= 1.0 else null
		_:
			return float(raw) if (raw is float or raw is int) else null


static func _restore_camera(cam: Dictionary, camera: CameraState, warnings: Array) -> void:
	var eye: Variant = _array_to_vec(cam.get("eye", null))
	var forward: Variant = _array_to_vec(cam.get("forward", null))
	var up: Variant = _array_to_vec(cam.get("up", null))
	if eye != null and forward != null and up != null:
		var f := (forward as Vector3).normalized()
		var u := (up as Vector3).normalized()
		if f.is_zero_approx() or u.is_zero_approx() or absf(f.dot(u)) > 0.999:
			warnings.append("Malformed camera orientation ignored")
		else:
			camera.transform = Transform3D(Basis.IDENTITY, eye).looking_at(eye + f, u)
	elif cam.has("eye") or cam.has("forward") or cam.has("up"):
		warnings.append("Malformed camera position ignored")
	if cam.has("speed_factor"):
		var s: Variant = cam["speed_factor"]
		if (s is float or s is int) and float(s) > 0.0:
			camera.speed_factor = float(s)
		else:
			warnings.append("Malformed camera speed_factor ignored")


static func _vec_to_array(v: Vector3) -> Array:
	return [_tidy(v.x), _tidy(v.y), _tidy(v.z)]


static func _tidy(x: float) -> float:
	if x == 0.0 or not is_finite(x):
		return x
	var decimals := 7 - int(ceil(log(absf(x)) / log(10.0)))
	var p := pow(10.0, decimals)
	return roundf(x * p) / p


static func _array_to_vec(raw: Variant) -> Variant:
	if not (raw is Array) or raw.size() != 3:
		return null
	for n in raw:
		if not (n is float or n is int):
			return null
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
