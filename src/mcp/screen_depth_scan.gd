extends Node
## A small GPU pass of the live scene shader. Publish only complete frames;
## requests read the cache, never start a synchronous CPU sweep.
const STATUS := {0: "unknown", 1: "surface", 2: "exit_background", 3: "range_limit", 4: "step_limit"}
var _view: Control
var _params: FractalParams
var _camera: CameraState
var _source: ShaderMaterial
var _viewport: SubViewport
var _rect: ColorRect
var _pending: Dictionary = {}
var _cached: Dictionary = {}
var _last_frame := -1000
var _revision := 0
var _tan_half_fov := 0.0
var _last_delivery_ms := -2000
var _last_delivery_revision := -1
var _last_delivered_frame := -1
var _last_grid_columns := 0
const DELIVERY_INTERVAL_MS := 2000

func setup(view: Control, params: FractalParams, camera: CameraState, material: ShaderMaterial, tan_half_fov: float) -> void:
	_tan_half_fov = tan_half_fov
	_view = view
	_params = params
	_camera = camera
	_source = material
	params.changed.connect(_changed)
	camera.changed.connect(_changed)
	view.resized.connect(_changed)
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	_rect = ColorRect.new()
	_viewport.add_child(_rect)
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_pre_draw.connect(_capture)
		RenderingServer.frame_post_draw.connect(_publish)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_capture):
		RenderingServer.frame_pre_draw.disconnect(_capture)
	if RenderingServer.frame_post_draw.is_connected(_publish):
		RenderingServer.frame_post_draw.disconnect(_publish)

func _changed() -> void:
	invalidate()

func invalidate() -> void:
	_revision += 1

func _capture() -> void:
	var frame := Engine.get_process_frames()
	if frame - _last_frame < _params.gameplay.depth_scan_interval or _view.size.x <= 0 or _view.size.y <= 0:
		return
	_last_frame = frame
	var width := _params.gameplay.depth_scan_width
	var height := clampi(int(round(width * _view.size.y / _view.size.x)), 2, 128)
	_viewport.size = Vector2i(width, height)
	_rect.size = Vector2(width, height)
	var material := _source.duplicate() as ShaderMaterial
	material.set_shader_parameter("depth_scan", true)
	# Navigation always observes the full screen, even when display rays scan a strip.
	material.set_shader_parameter("scan_y_offset", 0.0)
	material.set_shader_parameter("scan_y_scale", 1.0)
	_rect.material = material
	_pending = {"available": true, "frame_id": frame, "captured_at_ms": Time.get_ticks_msec(),
		"revision": _revision, "width": width, "height": height, "units": "world",
		"layout": "distances[row][column]; top-left origin; samples at cell centers; ray distance from eye",
		"screen_size": [_view.size.x, _view.size.y], "aspect": _view.size.x / _view.size.y,
		"tan_half_fov": _tan_half_fov,
		"eye": Array(_camera.eye64()), "forward": _array(_camera.forward()),
		"right": _array(_camera.right()), "up": _array(_camera.up()),
		"status_codes": STATUS, "approximate": true,
		"note": "Scene depth, excluding HUD. range_limit means no hit up to that distance and is useful for steering; beyond it is unknown. step_limit/unknown are not clear rays. Log depth precision is about 0.2%."}
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _publish() -> void:
	if _pending.is_empty():
		return
	var picture := _viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		_pending = {}
		return
	var decoded := decode_image(picture)
	_pending.merge(decoded)
	_pending["open_patches"] = open_patches(_pending)
	_cached = _pending
	_pending = {}

func snapshot() -> Dictionary:
	if _cached.is_empty():
		return {"available": false, "message": "No rendered depth frame is available yet.", "distances": [], "status": []}
	var out := _cached.duplicate(true)
	out["age_frames"] = Engine.get_process_frames() - int(out["frame_id"])
	out["age_ms"] = Time.get_ticks_msec() - int(out["captured_at_ms"])
	out["scene_or_pose_changed"] = int(out["revision"]) != _revision
	return out

static func decode_image(picture: Image) -> Dictionary:
	var distances: Array = []
	var status: Array = []
	for y in picture.get_height():
		var row: Array = []
		var flags: Array = []
		for x in picture.get_width():
			var color := picture.get_pixel(x, y)
			var flag := int(round(color.b * 255.0))
			var encoded := int(round(color.r * 255.0)) * 256 + int(round(color.g * 255.0))
			if flag > 0 and flag <= 4:
				var distance := pow(2.0, float(encoded) / 65535.0 * 192.0 - 96.0)
				# Round to four significant digits numerically; GDScript has no %g.
				var step := pow(10.0, floor(log(distance) / log(10.0)) - 3.0)
				row.append(round(distance / step) * step)
			else:
				row.append(null)
			flags.append(flag)
		distances.append(row)
		status.append(flags)
	return {"distances": distances, "status": status}

static func direction_at(scan: Dictionary, u: float, v: float) -> Vector3:
	var f := Vector3(scan.forward[0], scan.forward[1], scan.forward[2])
	var r := Vector3(scan.right[0], scan.right[1], scan.right[2])
	var up := Vector3(scan.up[0], scan.up[1], scan.up[2])
	return (f + (2.0 * u - 1.0) * float(scan.aspect) * float(scan.tan_half_fov) * r
		+ (1.0 - 2.0 * v) * float(scan.tan_half_fov) * up).normalized()

## Prefer broad distant patches, including no-hit rays reaching the range cap.
## Their distances are lower bounds, not permission to fly beyond the cap.
static func open_patches(scan: Dictionary) -> Array:
	var candidates: Array = []
	for y in range(1, int(scan.height) - 1):
		for x in range(1, int(scan.width) - 1):
			var minimum := INF
			var total := 0.0
			var valid := true
			var no_hit := 0
			var exit_rays := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var flag: int = scan.status[y + dy][x + dx]
					if flag != 1 and flag != 2 and flag != 3:
						valid = false
						continue
					var d: float = scan.distances[y + dy][x + dx]
					if not is_finite(d) or d <= 0.0:
						valid = false
						continue
					no_hit += int(flag == 2 or flag == 3)
					exit_rays += int(flag == 2)
					minimum = minf(minimum, d)
					total += d
			if valid:
				var u := (x + 0.5) / float(scan.width)
				var v := (y + 0.5) / float(scan.height)
				candidates.append({"column": x, "row": y, "uv": [u, v], "cell_count": 9,
					"min_distance": minimum, "mean_distance": total / 9.0,
					"no_hit_fraction": no_hit / 9.0, "exit_clear": exit_rays == 9,
					"center_status": STATUS.get(scan.status[y][x], "unknown"),
					"direction": _array(direction_at(scan, u, v))})
	candidates.sort_custom(func(a, b):
		if is_equal_approx(a.min_distance, b.min_distance):
			return a.no_hit_fraction > b.no_hit_fraction
		return a.min_distance > b.min_distance)
	var best: Array = []
	for candidate in candidates:
		if best.any(func(p): return abs(p.column - candidate.column) < 3 and abs(p.row - candidate.row) < 3):
			continue
		best.append(candidate)
		if best.size() == 6:
			break
	return best

static func _array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## The only external delivery path. Caching cadence and agent delivery cadence
## are deliberately independent. Summary by default; bounded grids on request.
func request(args: Dictionary) -> Dictionary:
	for key in ["after_frame", "max_columns"]:
		if args.has(key) and (not (args[key] is int or args[key] is float) or not is_finite(float(args[key])) or float(args[key]) != floor(float(args[key]))):
			return {"ok": false, "message": "%s must be a finite integer." % key}
	if args.has("include_grid") and not args.include_grid is bool:
		return {"ok": false, "message": "include_grid must be a boolean."}
	if int(args.get("after_frame", 0)) < 0:
		return {"ok": false, "message": "after_frame must be nonnegative."}
	var columns := clampi(int(args.get("max_columns", 32)), 8, 64)
	var include_grid := bool(args.get("include_grid", false))
	if _cached.is_empty():
		return {"ok": true, "available": false, "message": "No rendered depth frame is available yet."}
	if int(args.get("after_frame", -1)) >= int(_cached.frame_id):
		return {"ok": true, "available": true, "unchanged": true, "frame_id": _cached.frame_id}
	if args.has("after_frame") and int(args.after_frame) >= _last_delivered_frame and int(_cached.revision) == _last_delivery_revision and (not include_grid or _last_grid_columns >= columns):
		return {"ok": true, "available": true, "unchanged": true, "frame_id": _cached.frame_id,
			"scene_or_pose_changed": int(_cached.revision) != _revision,
			"message": "The cached observation is unchanged; reuse the previous scan and check scene_or_pose_changed."}
	var now := Time.get_ticks_msec()
	if now - _last_delivery_ms < DELIVERY_INTERVAL_MS:
		return {"ok": true, "throttled": true, "retry_after_ms": DELIVERY_INTERVAL_MS - (now - _last_delivery_ms),
			"message": "Use the previous scan; no depth data resent."}
	_last_delivery_ms = now
	_last_delivery_revision = int(_cached.revision)
	_last_delivered_frame = int(_cached.frame_id)
	_last_grid_columns = columns if include_grid else 0
	var out := snapshot()
	out["ok"] = true
	out["grid_included"] = include_grid
	if not out.grid_included:
		out.erase("distances")
		out.erase("status")
		return out
	# Bound even a high-fidelity local cache to at most 64x64 transmitted cells.
	var scale := maxf(1.0, maxf(float(out.width), float(out.height)) / columns)
	var width := maxi(1, int(out.width / scale))
	var height := maxi(1, int(out.height / scale))
	var source_rows: Array = []
	var source_columns: Array = []
	for y in height:
		source_rows.append(mini(int((y + 0.5) * out.height / height), int(out.height) - 1))
	for x in width:
		source_columns.append(mini(int((x + 0.5) * out.width / width), int(out.width) - 1))
	var distances: Array = []
	var flags: Array = []
	for y in source_rows:
		var row: Array = []
		var status_row: Array = []
		for x in source_columns:
			row.append(out.distances[y][x])
			status_row.append(out.status[y][x])
		distances.append(row)
		flags.append(status_row)
	out["source_size"] = [out.width, out.height]
	out["source_rows"] = source_rows
	out["source_columns"] = source_columns
	out["open_patch_coordinates"] = "row/column refer to source_size; uv and direction remain screen/world coordinates"
	out["width"] = width
	out["height"] = height
	out["distances"] = distances
	out["status"] = flags
	return out
