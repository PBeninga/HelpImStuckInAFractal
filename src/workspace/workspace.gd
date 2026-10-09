class_name Workspace
extends RefCounted
## Saving and loading a level as JSON, version 3: the shape as an AttributeTable
## (defaults + active bindings), the keymap (its axes, keys, speeds and values),
## the non-shape preference fields, the camera, and the noise graph. There is one
## file type — the level — tagged `"kind": "level"`; `"kind": "sequence"` is
## reserved for the level-sequence editor to come, and such a file is refused by
## name here. The clock and anything derivable (the orbit centre, the governor's
## render scale, rendered pixels) are not saved.
##
## The keys and axes travel with the level: `axes` is a list of entries
## {id, label, speed, positive, negative, value} (keys by name, "" for none),
## read and written through Keymap.to_list() / apply_list(). Loading a level
## replaces the keymap in hand with the file's axes; until a level is loaded the
## keymap is the shipped default (E / Q).
##
## What else is saved under "fractal": fast controls, the camera mode, the mouse
## sensitivity and the renderer options (level of detail, step budget and
## minimum render scale).
##
## Loading never fails on unfamiliar content: an unknown shape id is skipped with
## a warning, and a key the file lacks leaves the current value alone — except
## the fractal (`shape`), which a file from before there was a choice lacks, and
## which then loads as the Mandelbox it was saved from. Version 1 (the old flat
## "fractal" section) and version 2 (axes as a dict of id→value, keys left alone)
## both still load as levels, without warnings. A saved light_shininess (from
## before Roughness replaced it) becomes roughness = sqrt(2 / (shininess + 2))
## with no warning; a binding on light_shininess is dropped with one. Saving
## always writes version 3.

const VERSION := 3

## The preference and renderer fields kept under "fractal" (everything that is
## not a shape knob), in file order.
const FRACTAL_KEYS: Array[String] = [
	"fast_controls", "camera_mode", "mouse_sensitivity",
	"detail", "detail_range", "detail_falloff", "max_steps", "min_render_scale",
]
const CAMERA_MODE_NAMES: Array[String] = ["fly", "orbit"]


## Snapshot the level. Pure: it reads, it does not change anything.
static func capture(table: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState, noise := {}) -> Dictionary:
	var fractal := {}
	for key in FRACTAL_KEYS:
		var value: Variant = params.get(key)
		if key == "camera_mode":
			value = CAMERA_MODE_NAMES[int(value)]
		fractal[key] = value
	var out := {
		"version": VERSION,
		"kind": "level",
		"shape": table.to_dict(),
		"axes": keymap.to_list(),
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


## Apply a capture. Accepts version 3 ("axes" a list of entries, which replaces
## the keymap) and version 2 ("axes" a dict of id→value, applied onto the axes in
## hand, keys left alone). Returns the warnings.
static func restore(data: Dictionary, table: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState) -> Array:
	var warnings: Array = []

	var shape: Variant = data.get("shape", {})
	if shape is Dictionary:
		# An old save's light_shininess becomes the new roughness (see below).
		shape = _migrate_shininess(shape as Dictionary, warnings)
		# Levels saved before there was a choice of fractal are all Mandelboxes.
		var defaults: Variant = (shape as Dictionary).get("defaults", {})
		if defaults is Dictionary and not (defaults as Dictionary).has("shape") and table.has(&"shape"):
			table.set_default(&"shape", FractalParams.Shape.MANDELBOX)
		for w in table.apply_dict(shape):
			warnings.append(w)
	else:
		warnings.append("Malformed shape section ignored")

	var axis_data: Variant = data.get("axes", {})
	if axis_data is Array:
		# Version 3: the file's axes (keys and all) replace the keymap in hand.
		for w in keymap.apply_list(axis_data):
			warnings.append(w)
	elif axis_data is Dictionary:
		# Version 2: values by id onto whichever axes already exist; keys stay.
		var axes := keymap.axes()
		for key in axis_data:
			var id := StringName(key)
			if not axes.has(id):
				warnings.append("Axis value for unknown axis '%s' dropped" % key)
				continue
			var v: Variant = axis_data[key]
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


static func save_file(path: String, table: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState, noise := {}) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(capture(table, keymap, params, camera, noise), "\t", false))
	file.close()
	return OK


## Read `path` and restore it as a level. Never throws. A version-1 file is
## migrated before restoring, without a warning; a version-2 file loads as is. A
## sequence save, or an old keymap file, is refused by name and changes nothing.
static func load_file(path: String, table: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("No level at %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not read %s (error %d)" % [path, FileAccess.get_open_error()])
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("%s is not valid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
	var data: Variant = json.data
	match kind_of(data):
		"sequence":
			return _failure("%s is a sequence save, not a level; the sequence editor will load those" % path.get_file())
		"keymap":
			return _failure("%s is an old keymap file; keys are now saved inside each level, so load a level instead" % path.get_file())
		"level":
			pass
		_:
			return _failure("%s does not contain a level" % path)
	var version := int((data as Dictionary).get("version", 0))
	if version == 1:
		data = _migrate_v1(data)
	elif version != 2 and version != VERSION:
		return _failure("Save version %d is not supported (this build reads up to version %d)" % [version, VERSION])
	var noise: Variant = (data as Dictionary).get("noise", null)
	if not (noise is Dictionary):
		noise = null
	return {"ok": true, "warnings": restore(data, table, keymap, params, camera), "noise": noise}


## Classify parsed JSON by the one save family it belongs to: "level" (this
## build's save, or a version-1/2 file with a shape/fractal section), "sequence"
## (reserved, tagged kind), "keymap" (an old keys-and-axes file: an "axes" list
## with no kind/shape/fractal) or "unknown". A version-3 level is distinguished
## from an old keymap by its "kind"/"shape"/"fractal", never by "axes" alone,
## since both carry an "axes" list.
static func kind_of(data: Variant) -> String:
	if not (data is Dictionary):
		return "unknown"
	var d := data as Dictionary
	var kind := str(d.get("kind", ""))
	if kind == "level" or kind == "sequence":
		return kind
	if kind == "":
		if d.has("shape") or d.has("fractal"):
			return "level"
		if d.get("axes") is Array:
			return "keymap"
	return "unknown"


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "warnings": [message]}


## Turn an old save's light_shininess into the new roughness, in place of
## apply_dict's "unknown attribute" warning. The specular exponent was
## 2/roughness^2 - 2, so roughness = sqrt(2 / (shininess + 2)); the default 160
## gives 1/9. A default migrates silently; a binding on it is dropped with a
## warning (roughness drives the exponent through a square root, so the old
## additive drive no longer means anything).
static func _migrate_shininess(shape: Dictionary, warnings: Array) -> Dictionary:
	var out := shape.duplicate(true)
	var defaults: Variant = out.get("defaults", {})
	if defaults is Dictionary and (defaults as Dictionary).has("light_shininess"):
		var sh := float((defaults as Dictionary)["light_shininess"])
		(defaults as Dictionary).erase("light_shininess")
		if not (defaults as Dictionary).has("roughness"):
			(defaults as Dictionary)["roughness"] = sqrt(2.0 / maxf(sh + 2.0, 1e-6))
	var bindings: Variant = out.get("bindings", {})
	if bindings is Dictionary and (bindings as Dictionary).has("light_shininess"):
		(bindings as Dictionary).erase("light_shininess")
		warnings.append("Binding on 'light_shininess' dropped (shininess is now Roughness)")
	return out


## Turn a version-1 file (flat "fractal" section with the old ids) into the
## version-3 shape. Unknown/new ids are mapped; v1 had no axes or keymap, so the
## keymap in hand (the default) is left alone (an empty "axes" dict).
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
		"kind": "level",
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
