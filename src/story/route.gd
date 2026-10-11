class_name Route
extends RefCounted
## The escape route through the default Mandelbox (scale -2.09, fold 1, radii
## 0.7 / 1): where the failed punch jump strands the ship, the named
## "Mandelbrought characteristics" the support agent can point at, and the exit
## rift. Positions are world units; the agent and the HUD speak metres
## (METERS_PER_UNIT), so a 0.02-unit tunnel is a 20 m squeeze.
##
## The route was found offline: a clearance-weighted path search over a 0.025
## grid of the distance estimator, from the chamber behind the +X face's great
## round port out to an opening in that face, simplified into straight legs.
## Every leg keeps at least LOS_CLEARANCE from the surface along its length
## (route_test checks this with DistanceEstimator), and the shortcuts to the
## rift from the start, #4096 and #7071 do not, so the ship has to hop.

const METERS_PER_UNIT := 1000.0
## A straight flight is allowed when the distance estimate stays above this
## along the whole segment (7 m).
const LOS_CLEARANCE := 0.007
## Where the ship arrives after the failed jump, and what it is looking at.
const START_EYE := Vector3(1.5, 0.0, 0.0)
const START_LOOK_AT := Vector3(0.8781, 0.0, 0.0)   # the Grand Inversion Sphere

const EXIT_ID := "9001"
const RIFT_POS := Vector3(2.45, -1.425, 0.0)
const RIFT_NORMAL := Vector3(-1.0, 0.0, 0.0)
const RIFT_RADIUS := 0.1
## Inside this range of the rift's centre the egress jump fires (if the waiver
## is signed); the ship is held at RIFT_HOLD when it is not.
const RIFT_TRIGGER := 0.06
const RIFT_HOLD := 0.14

## kind: "route" (a waypoint on the way out), "landmark" (scenery to point at)
## or "exit". `route_index` orders the waypoints; -1 for the others.
const FEATURES := [
	{"id": "1113", "name": "The Grand Inversion Sphere", "kind": "landmark", "route_index": -1,
		"pos": Vector3(0.8781, 0.0, 0.0),
		"blurb": "The sphere-fold boundary. Anything inside the minimum radius gets inflated by a factor of about two. Do not touch."},
	{"id": "1729", "name": "Ramanujan's Taxicab Rank", "kind": "landmark", "route_index": -1,
		"pos": Vector3(1.5, 0.6043, 0.0),
		"blurb": "A wall of folded lattice. There are no taxis. There have never been taxis."},
	{"id": "3141", "name": "The Transcendental Skylight", "kind": "landmark", "route_index": -1,
		"pos": Vector3(1.5, 0.0, 0.6043),
		"blurb": "An irrational ceiling. Never repeats, never ends, never lets the light in."},
	{"id": "2312", "name": "The Recursive Cul-de-sac", "kind": "route", "route_index": 0,
		"pos": Vector3(1.025, -0.775, 0.0),
		"blurb": "A dead end that loops back into itself at every scale except this one, which is why it is the way out."},
	{"id": "4096", "name": "The Box-Fold Bypass", "kind": "route", "route_index": 1,
		"pos": Vector3(1.05, -1.025, 0.0),
		"blurb": "Where the box fold reflects space back on itself. Tight squeeze; mind the clamp."},
	{"id": "6174", "name": "The Kaprekar Roundabout", "kind": "landmark", "route_index": -1,
		"pos": Vector3(1.5601, -1.175, 0.5504),
		"blurb": "Every path eventually ends up here. This is not as helpful as it sounds."},
	{"id": "7071", "name": "The Lipschitz Narrows", "kind": "route", "route_index": 2,
		"pos": Vector3(1.45, -1.175, 0.0),
		"blurb": "The narrowest stretch of the way out. The distance estimate here is honest but unforgiving."},
	{"id": "8128", "name": "The Outer Aperture", "kind": "route", "route_index": 3,
		"pos": Vector3(1.95, -1.425, 0.0),
		"blurb": "An opening in the cube's +X face with ordinary space beyond. A perfect number, and a perfect place to leave."},
	{"id": "9001", "name": "The Egress Rift", "kind": "exit", "route_index": 4,
		"pos": Vector3(2.45, -1.425, 0.0),
		"blurb": "A tear back into ordinary three-space. Fly into it to complete the jump. Requires a signed egress waiver."},
]


## The feature with `id` ("2312", "#2312" or 2312 all work), or {} if none.
static func feature(id: Variant) -> Dictionary:
	var key := normalize_id(id)
	for f in FEATURES:
		if f["id"] == key:
			return f
	return {}


static func normalize_id(id: Variant) -> String:
	var s := str(id).strip_edges().trim_prefix("#")
	if s.is_valid_int():
		return "%04d" % int(s)
	return s


## The waypoints in flight order, ending with the exit.
static func waypoints() -> Array:
	var out: Array = []
	for f in FEATURES:
		if f["route_index"] >= 0:
			out.append(f)
	out.sort_custom(func(a, b): return a["route_index"] < b["route_index"])
	return out


static func start_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, START_EYE).looking_at(START_LOOK_AT, Vector3(0, 0, 1))


## The smallest distance estimate along the segment a -> b, sampled every
## `step` world units (and at both ends).
static func segment_clearance(a: Vector3, b: Vector3, params: FractalParams, step := 0.002) -> float:
	var n := maxi(2, int(ceil(a.distance_to(b) / step)) + 1)
	var lo := INF
	for i in n:
		var p := a.lerp(b, float(i) / float(n - 1))
		lo = minf(lo, DistanceEstimator.estimate(p, params))
	return lo


## Whether the ship can fly straight from a to b without coming within
## `clearance` of the fractal. Sphere-traced: the estimate d at a point bounds
## the clearance of every point within s of it by d - s, so stepping d -
## clearance never skips a pinch. Far cheaper than segment_clearance.
static func path_clear(a: Vector3, b: Vector3, params: FractalParams, clearance := LOS_CLEARANCE) -> bool:
	var length := a.distance_to(b)
	if length < 1e-9:
		return DistanceEstimator.estimate(a, params) >= clearance
	var dir := (b - a) / length
	var t := 0.0
	while true:
		var d := DistanceEstimator.estimate(a + dir * minf(t, length), params)
		if d < clearance:
			return false
		if t >= length:
			return true
		t += maxf(d - clearance, clearance * 0.25)
	return true


static func meters(units: float) -> int:
	return int(round(units * METERS_PER_UNIT))
