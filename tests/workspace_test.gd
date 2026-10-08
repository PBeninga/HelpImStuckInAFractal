extends "res://tests/test_case.gd"
## Workspace version 2: a view (shape table + axes + prefs + camera) survives a
## save and a load, a version-1 file migrates, and a bad file changes nothing it
## cannot read.

const TMP := "user://workspace_test.json"


func _table() -> AttributeTable:
	return AttributeTable.new(ShapeCatalogue.specs())


func run() -> void:
	# --- a round trip restores defaults, a binding, axes, prefs and camera ---
	var table := _table()
	table.set_default(&"box_scale", -2.29)
	table.set_default(&"fold_limit", 0.72)
	table.set_default(&"julia_all", true)
	table.set_default(&"color_mode", 15)
	var bind := Binding.new()
	bind.source = &"a"; bind.gain = 0.5; bind.waveform = Binding.Waveform.SINE; bind.period = 3.0
	table.set_binding(&"box_scale", bind)

	var axes := Axes.new()
	axes.add(&"a", "Axis A", 1.0)
	axes.set_value(&"a", 2.5)

	var params := FractalParams.new()
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
	camera.speed_factor = 3.5

	check_eq(Workspace.save_file(TMP, table, axes, params, camera), OK, "the view saves")

	var t2 := _table()
	var a2 := Axes.new(); a2.add(&"a", "Axis A", 1.0)
	var p2 := FractalParams.new()
	var c2 := CameraState.make_default()
	var result := Workspace.load_file(TMP, t2, a2, p2, c2)
	check(result["ok"], "and loads")
	check_eq(result["warnings"], [], "with no warnings")
	check_approx(t2.get_default(&"box_scale"), -2.29, "box_scale default")
	check_approx(t2.get_default(&"fold_limit"), 0.72, "fold_limit default")
	check_eq(t2.get_default(&"julia_all"), true, "julia_all default")
	check_eq(t2.get_default(&"color_mode"), 15, "color_mode default")
	var b2 := t2.binding(&"box_scale")
	check(b2 != null and b2.source == &"a", "the binding's source restores")
	check_approx(b2.gain, 0.5, "the binding's gain")
	check_eq(b2.waveform, Binding.Waveform.SINE, "the binding's waveform")
	check_approx(b2.period, 3.0, "the binding's period")
	check_approx(a2.value(&"a"), 2.5, "the axis value restores")
	check(not p2.fast_controls, "fast controls")
	check_eq(p2.camera_mode, FractalParams.CameraMode.ORBIT, "camera mode")
	check_approx(p2.mouse_sensitivity, 0.2, "mouse sensitivity")
	check_approx(p2.detail, 2.5, "detail")
	check_approx(p2.detail_range, 40.0, "detail range")
	check_approx(p2.detail_falloff, 1.5, "detail falloff")
	check_eq(p2.max_steps, 256, "max steps")
	check_approx(p2.min_render_scale, 0.4, "min render scale")
	check(c2.eye().is_equal_approx(camera.eye()), "camera eye %s" % c2.eye())
	check_approx(c2.speed_factor, 3.5, "speed factor")

	# --- the file is readable JSON with the documented sections ---
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP))
	check_eq(int(data["version"]), Workspace.VERSION, "the file carries version 2")
	check(data.has("shape") and data.has("axes") and data.has("fractal") and data.has("camera"),
		"it has the shape / axes / fractal / camera sections")
	check_eq(data["fractal"]["camera_mode"], "orbit", "camera mode is saved by name")
	check(data["shape"]["bindings"].has("box_scale"), "only active bindings are written")

	# --- unknown shape id and unknown axis id warn and are skipped ---
	var t3 := _table()
	var a3 := Axes.new(); a3.add(&"a", "Axis A", 1.0)
	var p3 := FractalParams.new()
	var warnings := Workspace.restore({
		"version": 2,
		"shape": {"defaults": {"box_scale": -3.0, "ghost": 9.0}, "bindings": {}},
		"axes": {"a": 1.0, "zzz": 4.0},
		"fractal": {"fast_controls": true},
	}, t3, a3, p3, CameraState.make_default())
	check_approx(t3.get_default(&"box_scale"), -3.0, "a good shape value still restores")
	check_approx(a3.value(&"a"), 1.0, "a known axis value restores")
	check_eq(warnings.size(), 2, "one warning per skipped thing: %s" % [warnings])

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
	var t4 := _table()
	var a4 := Axes.new()
	var p4 := FractalParams.new()
	var r4 := Workspace.load_file(TMP, t4, a4, p4, CameraState.make_default())
	check(r4["ok"] and r4["warnings"].is_empty(), "a version-1 file migrates with no warnings: %s" % [r4["warnings"]])
	check_approx(t4.get_default(&"box_scale"), -1.5, "v1 scale -> box_scale")
	check_approx(t4.get_default(&"min_radius"), 0.4, "v1 inner_radius -> min_radius")
	check_approx(t4.get_default(&"fixed_radius"), 0.8, "v1 outer_radius -> fixed_radius")
	check_eq(t4.get_default(&"julia_all"), true, "v1 julia_enabled -> julia_all")
	check_approx(t4.get_default(&"c_0"), 0.1, "v1 julia_point -> c_0")
	check_approx(t4.get_default(&"c_2"), 0.3, "v1 julia_point -> c_2")
	check(not p4.fast_controls, "v1 fast_controls migrates")
	check_eq(p4.camera_mode, FractalParams.CameraMode.ORBIT, "v1 camera_mode migrates")

	# --- the renderer options are checked too ---
	var p6 := FractalParams.new()
	var w6 := Workspace.restore({"version": 2, "shape": {}, "axes": {}, "fractal": {
		"detail_falloff": -2.0, "max_steps": "lots", "detail": 0.0, "detail_range": 25,
	}}, _table(), Axes.new(), p6, CameraState.make_default())
	check_approx(p6.detail_falloff, 0.0, "a negative falloff is ignored")
	check_eq(p6.max_steps, 128, "a non-number step budget is ignored")
	check_approx(p6.detail, 1.0, "a non-positive detail is ignored")
	check_approx(p6.detail_range, 25.0, "an integer range restores")
	check_eq(w6.size(), 3, "one warning each for the three bad ones: %s" % [w6])

	# --- files that cannot load change nothing ---
	var p5 := _table()
	var missing := Workspace.load_file("user://does_not_exist.json", p5, Axes.new(), FractalParams.new(), CameraState.make_default())
	check(not missing["ok"], "a missing file fails")
	_write(TMP, "{ not json")
	check(not Workspace.load_file(TMP, _table(), Axes.new(), FractalParams.new(), CameraState.make_default())["ok"], "bad JSON fails")
	_write(TMP, JSON.stringify({"version": 3, "shape": {}}))
	check(not Workspace.load_file(TMP, _table(), Axes.new(), FractalParams.new(), CameraState.make_default())["ok"], "an unsupported version fails")

	# --- the additive noise key round-trips, and its absence is null ---
	var noise_dict := {"nodes": [{"id": "position_0", "type": "position"}], "links": []}
	Workspace.save_file(TMP, _table(), Axes.new(), params, camera, noise_dict)
	var rn := Workspace.load_file(TMP, _table(), Axes.new(), FractalParams.new(), CameraState.make_default())
	check(rn["ok"] and rn["warnings"].is_empty(), "a save with a noise key loads with no warnings")
	check(rn["noise"] is Dictionary and (rn["noise"] as Dictionary)["nodes"].size() == 1,
		"the noise graph round-trips under 'noise'")
	Workspace.save_file(TMP, _table(), Axes.new(), params, camera)
	var rn2 := Workspace.load_file(TMP, _table(), Axes.new(), FractalParams.new(), CameraState.make_default())
	check(rn2["noise"] == null, "a file without a noise key reports null")
	check(not FileAccess.get_file_as_string(TMP).contains("\"noise\""), "…and no empty noise key is written")

	# --- every committed view save loads cleanly (keymap.json is not a view) ---
	var dir := DirAccess.open("res://saves")
	check(dir != null, "res://saves exists")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension() != "json" or f == "keymap.json":
				continue
			var r := Workspace.load_file("res://saves/" + f, _table(), Axes.new(), FractalParams.new(), CameraState.make_default())
			check(r["ok"] and r["warnings"].is_empty(), "saves/%s loads with no warnings %s" % [f, r["warnings"]])

	# --- the fractal: saved and restored; a file without one is a Mandelbox ---
	var kt := _table()
	kt.set_default(&"shape", FractalParams.Shape.KIFS)
	kt.set_default(&"kifs_scale", 2.2)
	check_eq(Workspace.save_file(TMP, kt, Axes.new(), FractalParams.new(), CameraState.make_default()), OK, "a KIFS view saves")
	var back := _table()
	check(Workspace.load_file(TMP, back, Axes.new(), FractalParams.new(), CameraState.make_default())["ok"], "and loads")
	check_eq(back.get_default(&"shape"), FractalParams.Shape.KIFS, "as a KIFS")
	check_approx(back.get_default(&"kifs_scale"), 2.2, "with its scale")
	var old_view := _table()
	old_view.set_default(&"shape", FractalParams.Shape.KLEINIAN)
	var ow := Workspace.restore({"version": 2, "shape": {"defaults": {"box_scale": -1.5}, "bindings": {}}},
		old_view, Axes.new(), FractalParams.new(), CameraState.make_default())
	check(ow.is_empty(), "a view from before the fractal row loads without warnings %s" % [ow])
	check_eq(old_view.get_default(&"shape"), FractalParams.Shape.MANDELBOX, "as the Mandelbox it was, whatever was showing")
	check_approx(old_view.get_default(&"box_scale"), -1.5, "with its own values")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
