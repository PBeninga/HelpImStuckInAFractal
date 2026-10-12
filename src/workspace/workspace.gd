class_name Workspace
extends RefCounted
## Saving and loading a level as JSON, version 5: the shapes as a list (each a
## label and an AttributeTable over the per-shape catalogue: defaults + active
## bindings, placement included), its own look table (light and material),
## which one is active, the keymap
## (its axes, keys, speeds and values), the non-shape preference fields, the
## camera, gameplay (spawn, exit sphere and movement), and the noise graph.
## There is one file type — the level — tagged
## `"kind": "level"`; `"kind": "sequence"` is reserved for the level-sequence
## editor to come, and such a file is refused by name here. The clock and
## anything derivable (the orbit centre, the governor's render scale, rendered
## pixels) are not saved.
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
## which then loads as the Mandelbox it was saved from. Version 3 (one "shape"
## table over the whole catalogue) loads as a one-shape scene at the identity
## placement, its light and material rows going to the look table; version 1
## (the old flat "fractal" section) and version 2 (axes as a dict of id→value,
## keys left alone) still load the same way, all without warnings. A saved
## light_shininess (from before Roughness replaced it) becomes roughness =
## sqrt(2 / (shininess + 2)) with no warning; a binding on light_shininess is
## dropped with one. Saving always writes version 5. The camera's eye is
## written at full precision (every digit of its 64-bit value): a camera inside
## a nested shape sits at a position the 7 digits
## the unit vectors get would not hold.

const VERSION := 5

## The preference and renderer fields kept under "fractal" (everything that is
## not a shape knob), in file order.
const FRACTAL_KEYS: Array[String] = [
	"fast_controls", "camera_mode", "mouse_sensitivity",
	"detail", "detail_range", "detail_falloff", "max_steps", "min_render_scale",
	"fractal_iterations", "painterly_enabled", "painterly_scale", "painterly_brush_size",
	"kifs_bailout_margin", "mandelbulb_bailout_margin",
	"phosphor_enabled", "phosphor_bands", "phosphor_decay", "phosphor_glow",
]
const CAMERA_MODE_NAMES: Array[String] = ["fly", "orbit"]


## Snapshot the level. Pure: it reads, it does not change anything.
static func capture(shapes: ShapeList, _look: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState, noise := {}) -> Dictionary:
	var fractal := {}
	for key in FRACTAL_KEYS:
		var value: Variant = params.get(key)
		if key == "camera_mode":
			value = CAMERA_MODE_NAMES[int(value)]
		fractal[key] = value
	var out := {
		"version": VERSION,
		"kind": "level",
		"gameplay": params.gameplay.to_dict(),
		"shapes": shapes.to_dict(),
		"active": params.active,
		"axes": keymap.to_list(),
		"fractal": fractal,
		"camera": {
			"eye": _eye_to_array(camera),
			"forward": _vec_to_array(camera.forward()),
			"up": _vec_to_array(camera.up()),
			"speed_factor": camera.speed_factor,
		},
	}
	if not noise.is_empty():
		out["noise"] = noise
	return out


## Apply a capture. Version 5 stores look per shape; older shared looks are
## copied into independent shape tables. Accepts version 4 ("shapes" a list, "look" a table),
## version 3 (one "shape" table, split here into one shape and the look) and
## version 2 ("axes" a dict of id→value, applied onto the axes in hand, keys
## left alone). Returns the warnings.
static func restore(data: Dictionary, shapes: ShapeList, look: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState) -> Array:
	var warnings: Array = []
	for warning in params.gameplay.apply_dict(data.get("gameplay", {})):
		warnings.append(warning)

	if data.has("shape") and not data.has("shapes"):
		data = _split_shape(data)
	var saved_look: Variant = data.get("look", {})
	var legacy_look := {}
	if saved_look is Dictionary:
		legacy_look = _migrate_shininess(saved_look, warnings)
	else:
		warnings.append("Malformed look section ignored")
	var saved_shapes: Variant = data.get("shapes", [])
	if saved_shapes is Array:
		var prepared: Array = []
		for raw in saved_shapes:
			if raw is Dictionary:
				var entry: Dictionary = (raw as Dictionary).duplicate(true)
				if not entry.has("look"):
					entry["look"] = legacy_look.duplicate(true)
				elif entry["look"] is Dictionary:
					entry["look"] = _migrate_shininess(entry["look"], warnings)
				# Levels saved before there was a choice of fractal are all Mandelboxes.
				var defaults: Variant = entry.get("defaults", {})
				if defaults is Dictionary and not (defaults as Dictionary).has("shape"):
					(defaults as Dictionary)["shape"] = FractalParams.Shape.MANDELBOX
				prepared.append(entry)
			else:
				prepared.append(raw)
		for w in shapes.apply_dict(prepared):
			warnings.append(w)
	else:
		for w in shapes.apply_dict(saved_shapes):   # warns, keeps one default shape
			warnings.append(w)
	params.set_shape_count(shapes.count())
	var active: Variant = data.get("active", 0)
	if active is float or active is int:
		params.active = clampi(int(active), 0, shapes.count() - 1)
	else:
		warnings.append("Malformed active shape ignored")

	# Compatibility output for callers of the older Workspace API. Rendering
	# and editing use shapes.look_table() directly; this is only a snapshot.
	look.apply_dict(shapes.look_table(params.active).to_dict())

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

	# Old levels must not inherit opt-in rendering or more expensive bailout
	# margins from the previously open level. Reset before applying saved keys.
	var renderer_defaults := FractalParams.new()
	for key in ["phosphor_enabled", "phosphor_bands", "phosphor_decay", "phosphor_glow",
			"kifs_bailout_margin", "mandelbulb_bailout_margin"]:
		params.set(key, renderer_defaults.get(key))
	var fractal: Variant = data.get("fractal", {})
	if fractal is Dictionary:
		# Pre-painting levels should retain their original presentation even
		# when loaded immediately after a level that opted into painting.
		if not fractal.has("painterly_enabled"):
			params.painterly_enabled = false
		for key in fractal:
			# Retired renderer settings in older levels are harmless and discarded.
			if key in ["perturbation_enabled", "perturbation_iterations"]:
				continue
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


static func save_file(path: String, shapes: ShapeList, look: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState, noise := {}) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(capture(shapes, look, keymap, params, camera, noise), "\t", false, true))
	file.flush()
	var err := file.get_error()
	file.close()
	return err


## Read `path` and restore it as a level. Never throws. A version-1 file is
## migrated before restoring, without a warning; version-2 and -3 files load
## through restore()'s own handling of their one "shape" table. A sequence
## save, or an old keymap file, is refused by name and changes nothing.
static func load_file(path: String, shapes: ShapeList, look: AttributeTable, keymap: Keymap, params: FractalParams, camera: CameraState) -> Dictionary:
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
	elif version < 2 or version > VERSION:
		return _failure("Save version %d is not supported (this build reads up to version %d)" % [version, VERSION])
	var noise: Variant = (data as Dictionary).get("noise", null)
	if not (noise is Dictionary):
		noise = null
	return {"ok": true, "warnings": restore(data, shapes, look, keymap, params, camera), "noise": noise}


## Classify parsed JSON by the one save family it belongs to: "level" (this
## build's save, or a version-1/2/3 file with a shape(s)/fractal section), "sequence"
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
		if d.has("shape") or d.has("shapes") or d.has("fractal"):
			return "level"
		if d.get("axes") is Array:
			return "keymap"
	return "unknown"


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "warnings": [message]}


## Turn a file with one "shape" table over the whole old catalogue (version 3
## and earlier) into the version-4 sections: its per-shape ids become one
## "shapes" entry at the identity placement, labelled Shape 1, and its look ids
## the "look" table. Ids neither catalogue knows stay with the shape, so
## apply_dict warns about them as before.
static func _split_shape(data: Dictionary) -> Dictionary:
	var out := data.duplicate()
	out.erase("shape")
	var shape: Variant = data.get("shape", {})
	if not (shape is Dictionary):
		out["shapes"] = shape   # restore() warns about it
		out["look"] = {}
		return out
	var look_ids := {}
	for id in ShapeCatalogue.scene_ids():
		look_ids[String(id)] = true
	look_ids["light_shininess"] = true   # migrated into roughness by restore()
	var entry := {"label": "Shape 1", "defaults": {}, "bindings": {}}
	var look := {"defaults": {}, "bindings": {}}
	for section in ["defaults", "bindings"]:
		var raw: Variant = (shape as Dictionary).get(section, {})
		if not (raw is Dictionary):
			continue
		for key in raw:
			if look_ids.has(String(key)):
				look[section][key] = raw[key]
			else:
				entry[section][key] = raw[key]
	out["shapes"] = [entry]
	out["look"] = look
	out["active"] = 0
	return out


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
## version-3 shape (one "shape" table, which restore() then splits). Unknown/new
## ids are mapped; v1 had no axes or keymap, so the keymap in hand (the
## default) is left alone (an empty "axes" dict).
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
		"version": 3,
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
		"fast_controls", "painterly_enabled", "phosphor_enabled":
			return raw if raw is bool else null
		"camera_mode":
			var index := CAMERA_MODE_NAMES.find(String(raw)) if raw is String else -1
			return index if index >= 0 else null
		"precision", "mouse_sensitivity", "detail", "detail_range", "min_render_scale", "painterly_scale", "painterly_brush_size", "phosphor_decay":
			return float(raw) if (raw is float or raw is int) and float(raw) > 0.0 else null
		"detail_falloff", "phosphor_glow":
			return float(raw) if (raw is float or raw is int) and float(raw) >= 0.0 else null
		"max_steps", "fractal_iterations", "phosphor_bands":
			return int(raw) if (raw is float or raw is int) and float(raw) >= 1.0 else null
		_:
			return float(raw) if (raw is float or raw is int) else null


static func _restore_camera(cam: Dictionary, camera: CameraState, warnings: Array) -> void:
	var eye_raw: Variant = _array_to_floats(cam.get("eye", null))
	var forward: Variant = _array_to_vec(cam.get("forward", null))
	var up: Variant = _array_to_vec(cam.get("up", null))
	if eye_raw != null and forward != null and up != null:
		var f := (forward as Vector3).normalized()
		var u := (up as Vector3).normalized()
		if f.is_zero_approx() or u.is_zero_approx() or absf(f.dot(u)) > 0.999:
			warnings.append("Malformed camera orientation ignored")
		else:
			camera.set_basis(Basis.looking_at(f, u))
			camera.set_eye(eye_raw[0], eye_raw[1], eye_raw[2])   # 64-bit, past Vector3
	elif cam.has("eye") or cam.has("forward") or cam.has("up"):
		warnings.append("Malformed camera position ignored")
	if cam.has("speed_factor"):
		var s: Variant = cam["speed_factor"]
		if (s is float or s is int) and float(s) > 0.0:
			camera.speed_factor = float(s)
		else:
			warnings.append("Malformed camera speed_factor ignored")


## The 64-bit eye at full precision (no _tidy: a deep view needs every digit).
static func _eye_to_array(camera: CameraState) -> Array:
	var e := camera.eye64()
	return [e[0], e[1], e[2]]


static func _vec_to_array(v: Vector3) -> Array:
	return [_tidy(v.x), _tidy(v.y), _tidy(v.z)]


## Round to `digits` significant digits, so the JSON stays readable.
static func _tidy(x: float, digits := 7) -> float:
	if x == 0.0 or not is_finite(x):
		return x
	var decimals := digits - int(ceil(log(absf(x)) / log(10.0)))
	var p := pow(10.0, decimals)
	return roundf(x * p) / p


## Three numbers as 64-bit floats, or null.
static func _array_to_floats(raw: Variant) -> Variant:
	if not (raw is Array) or raw.size() != 3:
		return null
	for n in raw:
		if not (n is float or n is int):
			return null
	return [float(raw[0]), float(raw[1]), float(raw[2])]


static func _array_to_vec(raw: Variant) -> Variant:
	var f: Variant = _array_to_floats(raw)
	if f == null:
		return null
	return Vector3(f[0], f[1], f[2])
