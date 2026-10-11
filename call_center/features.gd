extends RefCounted
## The points of interest the support agent can talk about, highlight and fly
## to: "Mandelbrought characteristics". The game registers them (CallCenter's
## register_feature / set_route / set_exit, or a JSON file); the call centre
## never invents world content. A feature:
##
##   {id: "2312", name: "The Recursive Cul-de-sac", kind: "route"|"landmark"|"exit",
##    pos: Vector3 (world units), blurb: "one line the agent can riff on"}
##
## `route` lists waypoint ids in flight order; `exit` is the way out.

signal changed

var route: Array = []
var exit_id := ""
var visited := {}

var _by_id := {}
var _order: Array = []


## "#2312", "2312" and 2312 all name feature "2312".
static func normalize_id(id: Variant) -> String:
	var s := str(id).strip_edges().trim_prefix("#")
	if s.is_valid_int():
		return "%04d" % int(s)
	return s


func add(id: Variant, name: String, pos: Vector3, kind := "landmark", blurb := "") -> Dictionary:
	var key := normalize_id(id)
	var f := {"id": key, "name": name, "pos": pos, "kind": kind, "blurb": blurb}
	if not _by_id.has(key):
		_order.append(key)
	_by_id[key] = f
	changed.emit()
	return f


func remove(id: Variant) -> void:
	var key := normalize_id(id)
	_by_id.erase(key)
	_order.erase(key)
	route.erase(key)
	if exit_id == key:
		exit_id = ""
	changed.emit()


func clear() -> void:
	_by_id.clear()
	_order.clear()
	route.clear()
	exit_id = ""
	visited.clear()
	changed.emit()


## The feature with `id`, or {} if there is none.
func find(id: Variant) -> Dictionary:
	return _by_id.get(normalize_id(id), {})


func all() -> Array:
	var out: Array = []
	for key in _order:
		out.append(_by_id[key])
	return out


func is_empty() -> bool:
	return _by_id.is_empty()


func set_route(ids: Array) -> void:
	route = ids.map(func(i): return normalize_id(i))
	changed.emit()


func set_exit(id: Variant) -> void:
	exit_id = normalize_id(id)
	changed.emit()


func exit() -> Dictionary:
	return find(exit_id) if exit_id != "" else {}


## The first route waypoint not yet visited (the exit once they all are), or {}.
func next_waypoint() -> Dictionary:
	for key in route:
		if not visited.has(key) and _by_id.has(key):
			return _by_id[key]
	if exit_id != "" and not visited.has(exit_id):
		return exit()
	return {}


## Load {features: [{id, name, kind, pos: [x, y, z], blurb}], route: [...],
## exit: id, start: {eye: [...], look_at: [...]}}. Returns the parsed data, or
## {} when the file is missing or malformed.
func load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary:
		push_warning("CallCenter: could not read features from %s" % path)
		return {}
	for f in data.get("features", []):
		var p: Array = f.get("pos", [0, 0, 0])
		add(f.get("id", ""), str(f.get("name", "")), Vector3(p[0], p[1], p[2]),
			str(f.get("kind", "landmark")), str(f.get("blurb", "")))
	if data.has("route"):
		set_route(data["route"])
	if data.has("exit"):
		set_exit(data["exit"])
	return data


## Where `point` is relative to a pose ({position, forward, right, up}):
## range in metres, bearing (degrees, positive = right), elevation (positive =
## up) and a plain-words direction.
static func relative(pose: Dictionary, point: Vector3, meters_per_unit: float) -> Dictionary:
	var rel: Vector3 = point - pose["position"]
	var f: float = rel.dot(pose["forward"])
	var r: float = rel.dot(pose["right"])
	var u: float = rel.dot(pose["up"])
	var bearing := rad_to_deg(atan2(r, f))
	var elevation := rad_to_deg(atan2(u, sqrt(f * f + r * r)))
	return {"range_m": int(round(rel.length() * meters_per_unit)), "bearing_deg": int(round(bearing)),
		"elevation_deg": int(round(elevation)), "direction": describe(bearing, elevation)}


## "dead ahead", "behind-left, slightly above" ...
static func describe(bearing: float, elevation: float) -> String:
	var a := absf(bearing)
	var side := "right" if bearing > 0.0 else "left"
	var horiz := ""
	if a <= 12.0:
		horiz = "dead ahead"
	elif a <= 40.0:
		horiz = "ahead, slightly %s" % side
	elif a <= 70.0:
		horiz = "ahead-%s" % side
	elif a <= 110.0:
		horiz = "to the %s" % side
	elif a <= 160.0:
		horiz = "behind-%s" % side
	else:
		horiz = "directly behind"
	if elevation > 25.0:
		horiz += ", well above"
	elif elevation > 8.0:
		horiz += ", slightly above"
	elif elevation < -25.0:
		horiz += ", well below"
	elif elevation < -8.0:
		horiz += ", slightly below"
	return horiz
