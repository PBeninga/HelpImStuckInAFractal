extends "res://tests/test_case.gd"
## Workspace version 4: a level (shape list + look table + the keymap's
## keys/axes/values + prefs + camera + noise) survives a save and a load; a
## version-3 file (one "shape" table) loads as a one-shape scene at the
## identity placement with its light and material rows in the look table; a
## version-2 file (axes a dict of values) and a version-1 file still load as
## levels; a sequence save and an old keymap file are refused by name; and
## every level in saves/ loads cleanly while old keymaps there are refused.

const TMP := "user://workspace_test.json"


func _table() -> ShapeList:
	return ShapeList.new()


func _look() -> AttributeTable:
	return AttributeTable.new(ShapeCatalogue.scene_specs())


## A fresh keymap at the shipped default (one axis "a" on E / Q).
func _keymap() -> Keymap:
	var km := Keymap.new()
	km.reset_to_default()
	return km


func run() -> void:
	# --- a round trip restores defaults, a binding, the keymap and camera ---
	var shapes := _table()
	var table := shapes.table(0)
	table.set_default(&"box_scale", -2.29)
	table.set_default(&"fold_limit", 0.72)
	table.set_default(&"julia_all", true)
	var look := _look()
	look.set_default(&"color_mode", 15)
	var bind := Binding.new()
	bind.source = &"a"; bind.gain = 0.5; bind.waveform = Binding.Waveform.SINE; bind.period = 3.0
	table.set_binding(&"box_scale", bind)
	var lbind := Binding.new()
	lbind.source = &"time"; lbind.gain = 0.2
	look.set_binding(&"light_yaw", lbind)
	shapes.add({&"pos_x": 1.5, &"size": 0.01, &"rot_y": 30.0}, "Inner")

	var km := Keymap.new()
	km.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	km.add_axis(&"turn", "Turn", 2.5, KEY_D, KEY_A)
	km.axes().set_value(&"a", 2.5)

	var params := FractalParams.new()
	params.set_shape_count(2)
	params.active = 1
	params.fast_controls = false
	params.camera_mode = FractalParams.CameraMode.ORBIT
	params.mouse_sensitivity = 0.2
	params.detail = 2.5
	params.detail_range = 40.0
	params.detail_falloff = 1.5
	params.max_steps = 256
	params.min_render_scale = 0.4
	var camera := CameraState.new()
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(1, -2, 0.5)).looking_at(Vector3(0, 0, 0.25), Vector3(0, 0, 1))
	camera.set_eye(1.000000001234, -2.0, 0.5)   # a 64-bit eye, past Vector3
	camera.speed_factor = 3.5

	check_eq(Workspace.save_file(TMP, shapes, look, km, params, camera), OK, "the level saves")

	var s2 := _table()
	var l2 := _look()
	var k2 := _keymap()                     # default E/Q only; the load replaces it
	var p2 := FractalParams.new()
	var c2 := CameraState.make_default()
	var result := Workspace.load_file(TMP, s2, l2, k2, p2, c2)
	check(result["ok"], "and loads")
	check_eq(result["warnings"], [], "with no warnings")
	check_eq(s2.count(), 2, "both shapes are back")
	check_eq(s2.label(1), "Inner", "with their labels")
	check_approx(float(s2.table(1).get_default(&"pos_x")), 1.5, "and placement")
	check_approx(float(s2.table(1).get_default(&"size")), 0.01, "size included", 1e-12)
	check_approx(float(s2.table(1).get_default(&"rot_y")), 30.0, "rotation included")
	check_eq(p2.shape_count(), 2, "params were sized to the list")
	check_eq(p2.active, 1, "and the active shape restored")
	var t2 := s2.table(0)
	check_approx(t2.get_default(&"box_scale"), -2.29, "box_scale default")
	check_approx(t2.get_default(&"fold_limit"), 0.72, "fold_limit default")
	check_eq(t2.get_default(&"julia_all"), true, "julia_all default")
	check_eq(l2.get_default(&"color_mode"), 15, "color_mode default, in the look table")
	var b2 := t2.binding(&"box_scale")
	check(b2 != null and b2.source == &"a", "the binding's source restores")
	check_approx(b2.gain, 0.5, "the binding's gain")
	check_eq(b2.waveform, Binding.Waveform.SINE, "the binding's waveform")
	check_approx(b2.period, 3.0, "the binding's period")
	check(l2.binding(&"light_yaw").source == &"time", "the look's binding restores")
	# the keymap: its axes, labels, speeds, values and keys all travel with the level
	check_approx(k2.axes().value(&"a"), 2.5, "the axis value restores")
	check(k2.axes().has(&"turn"), "the second axis is restored")
	check_eq(k2.axes().label(&"turn"), "Turn", "with its label")
	check_approx(k2.axes().speed(&"turn"), 2.5, "and its speed")
	check_eq(k2.positive_key(&"turn"), KEY_D, "and its positive key by name")
	check_eq(k2.negative_key(&"turn"), KEY_A, "and its negative key")
	check(InputMap.action_get_events(&"axis_turn_pos").size() == 1, "the InputMap action followed the restored key")
	check(not p2.fast_controls, "fast controls")
	check_eq(p2.camera_mode, FractalParams.CameraMode.ORBIT, "camera mode")
	check_approx(p2.mouse_sensitivity, 0.2, "mouse sensitivity")
	check_approx(p2.detail, 2.5, "detail")
	check_approx(p2.detail_range, 40.0, "detail range")
	check_approx(p2.detail_falloff, 1.5, "detail falloff")
	check_eq(p2.max_steps, 256, "max steps")
	check_approx(p2.min_render_scale, 0.4, "min render scale")
	check(c2.eye().is_equal_approx(camera.eye()), "camera eye %s" % c2.eye())
	check(absf(c2.eye_x() - 1.000000001234) < 1e-12, "the eye's 64-bit x survives the file (%s)" % c2.eye_x())
	check(c2.forward().is_equal_approx(camera.forward()), "and its facing")
	check_approx(c2.speed_factor, 3.5, "speed factor")

	# --- the file is readable JSON with the documented sections ---
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP))
	check_eq(int(data["version"]), Workspace.VERSION, "the file carries version 4")
	check_eq(data["kind"], "level", "and is tagged as a level")
	check(data.has("shapes") and data.has("active") and data.has("look") and data.has("axes") and data.has("fractal") and data.has("camera"),
		"it has the shapes / active / look / axes / fractal / camera sections")
	check(not data.has("shape"), "and no version-3 'shape' section")
	check(data["axes"] is Array, "axes is a list of entries")
	check_eq(data["fractal"]["camera_mode"], "orbit", "camera mode is saved by name")
	check(data["shapes"][0]["bindings"].has("box_scale"), "only active bindings are written")
	check_eq(data["shapes"][1]["label"], "Inner", "each entry carries its label")
	check(data["shapes"][1]["defaults"].has("pos_x"), "and its placement among the defaults")
	check(not data["shapes"][0]["defaults"].has("color_mode"), "the look is not repeated per shape")
	check(data["look"]["defaults"].has("color_mode") and data["look"]["bindings"].has("light_yaw"), "it is in the look section")

	# --- kind_of classifies each save family ---
	check_eq(Workspace.kind_of(data), "level", "a v4 save is a level")
	check_eq(Workspace.kind_of({"version": 3, "kind": "level", "shape": {}, "axes": [], "fractal": {}}), "level", "a v3 level is a level")
	check_eq(Workspace.kind_of({"version": 2, "shape": {}, "axes": {}, "fractal": {}}), "level", "a v2 view is a level")
	check_eq(Workspace.kind_of({"version": 1, "fractal": {}}), "level", "a v1 file is a level")
	check_eq(Workspace.kind_of({"kind": "sequence"}), "sequence", "a sequence tag is a sequence")
	check_eq(Workspace.kind_of({"version": 1, "axes": [{"id": "a"}]}), "keymap", "an old axes-list file is a keymap")
	check_eq(Workspace.kind_of({"foo": 1}), "unknown", "anything else is unknown")
	check_eq(Workspace.kind_of("not a dict"), "unknown", "non-dicts are unknown")

	# --- a version-2 file: axes is a dict of values onto the axes in hand ---
	# unknown shape id and unknown axis id warn and are skipped; keys stay put.
	var s3 := _table()
	var k3 := Keymap.new()
	k3.add_axis(&"a", "Axis A", 1.0, KEY_E, KEY_Q)
	var warnings := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {"box_scale": -3.0, "ghost": 9.0}, "bindings": {}},
		"axes": {"a": 1.0, "zzz": 4.0},
		"fractal": {"fast_controls": true},
	}, s3, _look(), k3, FractalParams.new(), CameraState.make_default())
	var t3 := s3.table(0)
	check_approx(t3.get_default(&"box_scale"), -3.0, "a good shape value still restores")
	check_approx(k3.axes().value(&"a"), 1.0, "a known axis value restores")
	check_eq(k3.positive_key(&"a"), KEY_E, "a v2 file leaves the key binding alone")
	check_eq(warnings.size(), 2, "one warning per skipped thing (ghost shape, zzz axis): %s" % [warnings])

	# --- a version-3 file (one "shape" over the whole catalogue) loads as a
	# one-shape scene: its light and material rows go to the look table ---
	var v3 := {
		"version": 3, "kind": "level",
		"shape": {"defaults": {"box_scale": -1.7, "fold_limit": 0.9, "color_mode": 5, "light_yaw": 33.0, "shape": 2},
			"bindings": {"w": {"source": "time", "gain": 0.1, "waveform": "SINE", "period": 2.0},
				"exposure": {"source": "time", "gain": 0.3, "waveform": "SINE", "period": 2.0}}},
		"axes": [],
		"fractal": {"fast_controls": true},
		"camera": {"eye": [1, 1, 1], "forward": [-1, 0, 0], "up": [0, 0, 1], "speed_factor": 2.0},
	}
	_write(TMP, JSON.stringify(v3))
	var s5 := _table()
	s5.add({}, "Extra")
	var l5 := _look()
	var p5v := FractalParams.new()
	p5v.set_shape_count(2)
	var r5 := Workspace.load_file(TMP, s5, l5, _keymap(), p5v, CameraState.make_default())
	check(r5["ok"] and r5["warnings"].is_empty(), "a version-3 file loads with no warnings: %s" % [r5["warnings"]])
	check_eq(s5.count(), 1, "as one shape (replacing the two that were there)")
	check_eq(p5v.shape_count(), 1, "and params follow")
	check_approx(float(s5.table(0).get_default(&"box_scale")), -1.7, "with its knobs")
	check_eq(s5.table(0).get_default(&"shape"), FractalParams.Shape.KLEINIAN, "its fractal")
	check_approx(float(s5.table(0).get_default(&"size")), 1.0, "at the identity placement")
	check(s5.table(0).binding(&"w").source == &"time", "and its shape binding")
	check_eq(l5.get_default(&"color_mode"), 5, "its colour mode lands in the look table")
	check_approx(float(l5.get_default(&"light_yaw")), 33.0, "and its light")
	check(l5.binding(&"exposure").source == &"time", "with the look's binding")
	check(not s5.table(0).has(&"color_mode"), "the shape's table has no look rows")

	# --- a version-1 file migrates its keys without a warning ---
	var v1 := {
		"version": 1,
		"fractal": {
			"scale": -1.5, "inner_radius": 0.4, "outer_radius": 0.8, "fold_limit": 0.9,
			"color_mode": 3, "precision": 0.0001, "julia_enabled": true,
			"julia_point": [0.1, 0.2, 0.3], "fast_controls": false,
			"camera_mode": "orbit", "mouse_sensitivity": 0.15,
		},
		"camera": {"eye": [1, 1, 1], "forward": [-1, 0, 0], "up": [0, 0, 1], "speed_factor": 2.0},
	}
	_write(TMP, JSON.stringify(v1))
	var s4 := _table()
	var l4 := _look()
	var k4 := _keymap()
	var p4 := FractalParams.new()
	var r4 := Workspace.load_file(TMP, s4, l4, k4, p4, CameraState.make_default())
	check(r4["ok"] and r4["warnings"].is_empty(), "a version-1 file migrates with no warnings: %s" % [r4["warnings"]])
	check_eq(s4.count(), 1, "into one shape")
	var t4 := s4.table(0)
	check_approx(t4.get_default(&"box_scale"), -1.5, "v1 scale -> box_scale")
	check_approx(t4.get_default(&"min_radius"), 0.4, "v1 inner_radius -> min_radius")
	check_approx(t4.get_default(&"fixed_radius"), 0.8, "v1 outer_radius -> fixed_radius")
	check_eq(t4.get_default(&"julia_all"), true, "v1 julia_enabled -> julia_all")
	check_approx(t4.get_default(&"c_0"), 0.1, "v1 julia_point -> c_0")
	check_approx(t4.get_default(&"c_2"), 0.3, "v1 julia_point -> c_2")
	check_eq(l4.get_default(&"color_mode"), 3, "v1 color_mode -> the look's color_mode")
	check(not p4.fast_controls, "v1 fast_controls migrates")
	check_eq(p4.camera_mode, FractalParams.CameraMode.ORBIT, "v1 camera_mode migrates")
	check(k4.axes().has(&"a") and k4.positive_key(&"a") == KEY_E, "and v1 leaves the default keymap alone")

	# --- the renderer options are checked too ---
	var p6 := FractalParams.new()
	var w6 := Workspace.restore({"version": 4, "shapes": [{}], "look": {}, "axes": [], "fractal": {
		"detail_falloff": -2.0, "max_steps": "lots", "detail": 0.0, "detail_range": 25,
	}}, _table(), _look(), _keymap(), p6, CameraState.make_default())
	check_approx(p6.detail_falloff, 0.0, "a negative falloff is ignored")
	check_eq(p6.max_steps, 128, "a non-number step budget is ignored")
	check_approx(p6.detail, 1.0, "a non-positive detail is ignored")
	check_approx(p6.detail_range, 25.0, "an integer range restores")
	check_eq(w6.size(), 3, "one warning each for the three bad ones: %s" % [w6])

	# --- a malformed shapes section warns and keeps one default shape ---
	var s7 := _table()
	var w7 := Workspace.restore({"version": 4, "shapes": "nope", "look": {}, "axes": [], "fractal": {}}, s7, _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check_eq(s7.count(), 1, "a malformed shapes section leaves one shape")
	check(w7.size() >= 1 and String(w7[0]).to_lower().contains("shape"), "and warns: %s" % [w7])
	var s8 := _table()
	var w8 := Workspace.restore({"version": 4, "shapes": [], "look": {}, "axes": [], "fractal": {}}, s8, _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check_eq(s8.count(), 1, "an empty list leaves one shape")
	check(w8.size() == 1, "with one warning: %s" % [w8])
	var p9 := FractalParams.new()
	var w9 := Workspace.restore({"version": 4, "shapes": [{}, {}], "active": 7, "look": "bad", "axes": [], "fractal": {}}, _table(), _look(), _keymap(), p9, CameraState.make_default())
	check_eq(p9.active, 1, "an active index past the list is clamped")
	check(w9.size() == 1 and String(w9[0]).to_lower().contains("look"), "a malformed look section warns: %s" % [w9])

	# --- files that cannot load change nothing ---
	var missing := Workspace.load_file("user://does_not_exist.json", _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check(not missing["ok"], "a missing file fails")
	_write(TMP, "{ not json")
	check(not Workspace.load_file(TMP, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())["ok"], "bad JSON fails")
	_write(TMP, JSON.stringify({"version": 9, "kind": "level", "shapes": []}))
	check(not Workspace.load_file(TMP, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())["ok"], "an unsupported version fails")

	# --- the additive noise key round-trips, and its absence is null ---
	var noise_dict := {"nodes": [{"id": "position_0", "type": "position"}], "links": []}
	Workspace.save_file(TMP, _table(), _look(), _keymap(), params, camera, noise_dict)
	var rn := Workspace.load_file(TMP, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check(rn["ok"] and rn["warnings"].is_empty(), "a save with a noise key loads with no warnings")
	check(rn["noise"] is Dictionary and (rn["noise"] as Dictionary)["nodes"].size() == 1,
		"the noise graph round-trips under 'noise'")
	Workspace.save_file(TMP, _table(), _look(), _keymap(), params, camera)
	var rn2 := Workspace.load_file(TMP, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check(rn2["noise"] == null, "a file without a noise key reports null")
	check(not FileAccess.get_file_as_string(TMP).contains("\"noise\""), "…and no empty noise key is written")

	# --- a sequence save is refused by name, and changes nothing ---
	_write(TMP, JSON.stringify({"version": 1, "kind": "sequence", "steps": []}))
	var rs := Workspace.load_file(TMP, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check(not rs["ok"], "a sequence save does not load as a level")
	check(rs["warnings"].size() == 1 and String(rs["warnings"][0]).contains("sequence"),
		"and the message says it is a sequence save: %s" % [rs["warnings"]])

	# --- an old keymap file is refused by name, and changes nothing ---
	# (Keys and axes used to have their own file, saved into saves/ with the same
	# names; such a file must say so instead of wiping the level in hand.)
	_write(TMP, JSON.stringify({"version": 1, "axes": [{"id": "a", "label": "Axis A", "speed": 1.0, "positive": "E", "negative": "Q"}]}))
	var kept := _table()
	kept.table(0).set_default(&"shape", FractalParams.Shape.KLEINIAN)
	kept.add({}, "Second")
	var kept_km := Keymap.new()
	kept_km.add_axis(&"z", "Axis Z", 1.0, KEY_Z, KEY_X)
	var kc := CameraState.make_default()
	kc.speed_factor = 7.0
	var rk := Workspace.load_file(TMP, kept, _look(), kept_km, FractalParams.new(), kc)
	check(not rk["ok"], "an old keymap file does not load as a level")
	check(rk["warnings"].size() == 1 and String(rk["warnings"][0]).contains("keymap") and String(rk["warnings"][0]).contains("level"),
		"and the message says it is an old keymap and to load a level instead: %s" % [rk["warnings"]])
	check_eq(kept.table(0).get_default(&"shape"), FractalParams.Shape.KLEINIAN, "the shape is left alone")
	check_eq(kept.count(), 2, "and so is the list")
	check(kept_km.axes().has(&"z"), "the keymap in hand is left alone")
	check_approx(kc.speed_factor, 7.0, "and so is the camera")

	# --- every level in saves/ loads cleanly; non-levels (old keymaps) are refused ---
	# (The user's own keys-and-axes files live in saves/ too, under level-ish
	# names, so the sweep must refuse them rather than break on them.)
	var dir := DirAccess.open("res://saves")
	check(dir != null, "res://saves exists")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension() != "json":
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://saves/" + f))
			var kind := Workspace.kind_of(parsed)
			var r := Workspace.load_file("res://saves/" + f, _table(), _look(), _keymap(), FractalParams.new(), CameraState.make_default())
			if kind == "level":
				check(r["ok"] and r["warnings"].is_empty(), "saves/%s loads with no warnings %s" % [f, r["warnings"]])
			else:
				check(not r["ok"], "saves/%s is not a level and is refused" % f)

	# --- the fractal: saved and restored; a file without one is a Mandelbox ---
	var kt := _table()
	kt.table(0).set_default(&"shape", FractalParams.Shape.KIFS)
	kt.table(0).set_default(&"kifs_scale", 2.2)
	check_eq(Workspace.save_file(TMP, kt, _look(), _keymap(), FractalParams.new(), CameraState.make_default()), OK, "a KIFS level saves")
	var back := _table()
	check(Workspace.load_file(TMP, back, _look(), _keymap(), FractalParams.new(), CameraState.make_default())["ok"], "and loads")
	check_eq(back.table(0).get_default(&"shape"), FractalParams.Shape.KIFS, "as a KIFS")
	check_approx(back.table(0).get_default(&"kifs_scale"), 2.2, "with its scale")
	var old_view := _table()
	old_view.table(0).set_default(&"shape", FractalParams.Shape.KLEINIAN)
	var ow := Workspace.restore({"version": 2, "shape": {"defaults": {"box_scale": -1.5}, "bindings": {}}},
		old_view, _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check(ow.is_empty(), "a level from before the fractal row loads without warnings %s" % [ow])
	check_eq(old_view.table(0).get_default(&"shape"), FractalParams.Shape.MANDELBOX, "as the Mandelbox it was, whatever was showing")
	check_approx(old_view.table(0).get_default(&"box_scale"), -1.5, "with its own values")

	# --- a v2 file carrying light_shininess migrates to roughness ---
	var mt := _table()
	var ml := _look()
	var mw := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {"light_shininess": 160.0, "box_scale": -1.7}, "bindings": {}},
		"axes": {}, "fractal": {},
	}, mt, ml, _keymap(), FractalParams.new(), CameraState.make_default())
	check_approx(ml.get_default(&"roughness"), 1.0 / 9.0,
		"light_shininess 160 loads as roughness 1/9 (sqrt(2/(160+2))), in the look table")
	check_approx(mt.table(0).get_default(&"box_scale"), -1.7, "the rest of the shape still restores")
	check(mw.is_empty(), "the shininess migration warns nothing: %s" % [mw])

	# --- a binding on light_shininess is dropped with one warning ---
	var mt2 := _table()
	var mw2 := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {}, "bindings": {"light_shininess": {"source": "time", "gain": 1.0, "waveform": 0, "period": 1.0}}},
		"axes": {}, "fractal": {},
	}, mt2, _look(), _keymap(), FractalParams.new(), CameraState.make_default())
	check_eq(mw2.size(), 1, "the dropped shininess binding warns once: %s" % [mw2])
	check(String(mw2[0]).to_lower().contains("shininess"), "and the warning names shininess")

	# clean up the runtime InputMap actions the keymaps registered
	for id in [&"a", &"turn", &"z"]:
		for action in [StringName("axis_%s_pos" % id), StringName("axis_%s_neg" % id)]:
			if InputMap.has_action(action):
				InputMap.erase_action(action)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
