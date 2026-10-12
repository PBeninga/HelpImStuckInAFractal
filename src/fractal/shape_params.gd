class_name ShapeParams
extends Resource
## The RESOLVED knob values of one shape in the scene: its placement (where its
## local frame sits in the world) and the shape knobs evaluated inside that
## frame: which fractal (`shape`), w, the Mandelbox, KIFS, Kleinian and
## Mandelbulb groups and the Render precision. Every field is named by its
## catalogue id (src/fractal/shape_catalogue.gd, the per-shape specs) and
## written once per frame by apply_resolved() from the shape's AttributeTable;
## setters emit Resource's built-in `changed`, and apply_resolved batches a
## frame's writes into at most one emit. The scene's look (colour, light,
## material) and preferences live on FractalParams, which holds the list of
## these.
##
## Placement: a world point p maps into the shape as
##   q = Rᵀ (p − position) / size
## and a local distance maps back as d_world = d_local × size. R is the rotation
## Rz(rot_z) · Ry(rot_y) · Rx(rot_x) (degrees, about the world axes, x first).
## The frame maths runs in 64-bit scalars (GDScript floats), never Vector3,
## because Vector3 components are 32-bit in a standard build and p − position is
## a catastrophic cancellation for a small shape far from the origin: that is
## what lets a nested shape sit three orders of magnitude below its parent.

## The resolved fields, in catalogue order (ShapeCatalogue.shape_ids()).
## apply_resolved writes these.
const RESOLVED_KEYS: Array[StringName] = [
	&"pos_x", &"pos_y", &"pos_z", &"rot_x", &"rot_y", &"rot_z", &"size",
	&"shape", &"w", &"box_scale", &"fold_limit", &"min_radius", &"fixed_radius", &"fold_order",
	&"fold_shape", &"hybrid_mix", &"hybrid_every", &"scale_drift", &"julia_all", &"julia_0",
	&"julia_1", &"julia_2", &"julia_3", &"c_0", &"c_1", &"c_2", &"c_3", &"iter_rot_xy",
	&"iter_rot_xz", &"iter_rot_xw", &"iter_rot_yz", &"iter_rot_yw", &"iter_rot_zw", &"kifs_scale",
	&"kifs_fold", &"kifs_poly_k", &"kifs_twist", &"kifs_offset_0", &"kifs_offset_1",
	&"kifs_offset_2", &"kifs_offset_3", &"kifs_rot1_xy", &"kifs_rot1_xz", &"kifs_rot1_xw",
	&"kifs_rot1_yz", &"kifs_rot1_yw", &"kifs_rot1_zw", &"kifs_rot2_xy", &"kifs_rot2_xz",
	&"kifs_rot2_xw", &"kifs_rot2_yz", &"kifs_rot2_yw", &"kifs_rot2_zw", &"kleinian_box_0",
	&"kleinian_box_1", &"kleinian_box_2", &"kleinian_box_3", &"kleinian_radius",
	&"kleinian_shift_0", &"kleinian_shift_1", &"kleinian_shift_2", &"kleinian_shift_3",
	&"kleinian_thickness", &"kleinian_view_distance", &"mandelbulb_power",
	&"mandelbulb_phase_theta", &"mandelbulb_phase_phi", &"mandelbulb_julia", &"mandelbulb_c_0",
	&"mandelbulb_c_1", &"mandelbulb_c_2", &"precision",
]

## The smallest size a shape can have: sizes below this would be lost to the
## ray parameter's float32 resolution anyway.
const SIZE_MIN := 1e-9

## The Kleinian's bounding cube: effectively none (see bound_half()).
const KLEINIAN_BOUND := 1.0e4

## The fewest iterations the march's coarse pass uses (the site's fixed count),
## and the box half-size its count is worked out against.
const COARSE_ITERS_MIN := 16
const COARSE_BOX_HALF := 2.0

## The zoom floor sits where the hit threshold is this many times finer than
## the 32-bit grid. Measured: hits start failing at a distance of 1e-4 with
## ulp32 ~1.2e-7 and eps 2.5e-5, which is ulp32 / (48 × eps).
const ZOOM_FLOOR_DIVISOR := 50.0

# While true the setters do not emit; apply_resolved emits once at the end.
var _suppress := false

# --- Placement ---
@export var pos_x: float = 0.0:
	set(v): pos_x = v; _emit()
@export var pos_y: float = 0.0:
	set(v): pos_y = v; _emit()
@export var pos_z: float = 0.0:
	set(v): pos_z = v; _emit()
@export var rot_x: float = 0.0:
	set(v): rot_x = v; _emit()
@export var rot_y: float = 0.0:
	set(v): rot_y = v; _emit()
@export var rot_z: float = 0.0:
	set(v): rot_z = v; _emit()
@export var size: float = 1.0:
	set(v): size = maxf(v, SIZE_MIN); _emit()

# --- Fractal: which fractal de() draws (see FractalParams.Shape) ---
@export var shape: int = FractalParams.Shape.MANDELBOX:
	set(v): shape = v; _emit()

# --- Box ---
@export var box_scale: float = -2.09:
	set(v): box_scale = v; _emit()
@export var fold_limit: float = 1.0:
	set(v): fold_limit = v; _emit()
@export var min_radius: float = 0.7:
	set(v): min_radius = v; _emit()
@export var fixed_radius: float = 1.0:
	set(v): fixed_radius = v; _emit()
@export var fold_order: int = 0:
	set(v): fold_order = v; _emit()
@export var w: float = 0.0:
	set(v): w = v; _emit()
@export var fold_shape: int = 0:
	set(v): fold_shape = v; _emit()
@export var hybrid_mix: float = 0.0:
	set(v): hybrid_mix = v; _emit()
@export var hybrid_every: int = 2:
	set(v): hybrid_every = v; _emit()
@export var scale_drift: float = 0.0:
	set(v): scale_drift = v; _emit()

# --- Julia ---
@export var julia_all: bool = false:
	set(v): julia_all = v; _emit()
@export var julia_0: bool = false:
	set(v): julia_0 = v; _emit()
@export var julia_1: bool = false:
	set(v): julia_1 = v; _emit()
@export var julia_2: bool = false:
	set(v): julia_2 = v; _emit()
@export var julia_3: bool = false:
	set(v): julia_3 = v; _emit()
@export var c_0: float = -0.23:
	set(v): c_0 = v; _emit()
@export var c_1: float = 1.512:
	set(v): c_1 = v; _emit()
@export var c_2: float = 1.892:
	set(v): c_2 = v; _emit()
@export var c_3: float = 0.0:
	set(v): c_3 = v; _emit()

# --- Iteration rotation (degrees) ---
@export var iter_rot_xy: float = 0.0:
	set(v): iter_rot_xy = v; _emit()
@export var iter_rot_xz: float = 0.0:
	set(v): iter_rot_xz = v; _emit()
@export var iter_rot_xw: float = 0.0:
	set(v): iter_rot_xw = v; _emit()
@export var iter_rot_yz: float = 0.0:
	set(v): iter_rot_yz = v; _emit()
@export var iter_rot_yw: float = 0.0:
	set(v): iter_rot_yw = v; _emit()
@export var iter_rot_zw: float = 0.0:
	set(v): iter_rot_zw = v; _emit()

# --- KIFS (see KifsShape) ---
@export var kifs_scale: float = 3.0:
	set(v): kifs_scale = v; _emit()
@export var kifs_fold: int = 0:
	set(v): kifs_fold = v; _emit()
@export var kifs_poly_k: float = 5.0:
	set(v): kifs_poly_k = v; _emit()
@export var kifs_twist: float = 0.0:
	set(v): kifs_twist = v; _emit()
@export var kifs_offset_0: float = 1.0:
	set(v): kifs_offset_0 = v; _emit()
@export var kifs_offset_1: float = 1.0:
	set(v): kifs_offset_1 = v; _emit()
@export var kifs_offset_2: float = 1.0:
	set(v): kifs_offset_2 = v; _emit()
@export var kifs_offset_3: float = 0.0:
	set(v): kifs_offset_3 = v; _emit()
@export var kifs_rot1_xy: float = 0.0:
	set(v): kifs_rot1_xy = v; _emit()
@export var kifs_rot1_xz: float = 0.0:
	set(v): kifs_rot1_xz = v; _emit()
@export var kifs_rot1_xw: float = 0.0:
	set(v): kifs_rot1_xw = v; _emit()
@export var kifs_rot1_yz: float = 0.0:
	set(v): kifs_rot1_yz = v; _emit()
@export var kifs_rot1_yw: float = 0.0:
	set(v): kifs_rot1_yw = v; _emit()
@export var kifs_rot1_zw: float = 0.0:
	set(v): kifs_rot1_zw = v; _emit()
@export var kifs_rot2_xy: float = 0.0:
	set(v): kifs_rot2_xy = v; _emit()
@export var kifs_rot2_xz: float = 0.0:
	set(v): kifs_rot2_xz = v; _emit()
@export var kifs_rot2_xw: float = 0.0:
	set(v): kifs_rot2_xw = v; _emit()
@export var kifs_rot2_yz: float = 0.0:
	set(v): kifs_rot2_yz = v; _emit()
@export var kifs_rot2_yw: float = 0.0:
	set(v): kifs_rot2_yw = v; _emit()
@export var kifs_rot2_zw: float = 0.0:
	set(v): kifs_rot2_zw = v; _emit()

# --- Kleinian (see KleinianShape) ---
@export var kleinian_box_0: float = 0.92436:
	set(v): kleinian_box_0 = v; _emit()
@export var kleinian_box_1: float = 0.90756:
	set(v): kleinian_box_1 = v; _emit()
@export var kleinian_box_2: float = 0.92436:
	set(v): kleinian_box_2 = v; _emit()
@export var kleinian_box_3: float = 0.92436:
	set(v): kleinian_box_3 = v; _emit()
@export var kleinian_radius: float = 1.0:
	set(v): kleinian_radius = v; _emit()
@export var kleinian_shift_0: float = 0.0:
	set(v): kleinian_shift_0 = v; _emit()
@export var kleinian_shift_1: float = 0.0:
	set(v): kleinian_shift_1 = v; _emit()
@export var kleinian_shift_2: float = 0.0:
	set(v): kleinian_shift_2 = v; _emit()
@export var kleinian_shift_3: float = 0.0:
	set(v): kleinian_shift_3 = v; _emit()
@export var kleinian_thickness: float = 0.01:
	set(v): kleinian_thickness = v; _emit()
@export var kleinian_view_distance: float = 1.0:
	set(v): kleinian_view_distance = v; _emit()

# --- Mandelbulb (see MandelbulbShape) ---
@export var mandelbulb_power: float = 8.0:
	set(v): mandelbulb_power = v; _emit()
@export var mandelbulb_phase_theta: float = 0.0:
	set(v): mandelbulb_phase_theta = v; _emit()
@export var mandelbulb_phase_phi: float = 0.0:
	set(v): mandelbulb_phase_phi = v; _emit()
@export var mandelbulb_julia: bool = false:
	set(v): mandelbulb_julia = v; _emit()
@export var mandelbulb_c_0: float = -0.2:
	set(v): mandelbulb_c_0 = v; _emit()
@export var mandelbulb_c_1: float = 0.6:
	set(v): mandelbulb_c_1 = v; _emit()
@export var mandelbulb_c_2: float = 0.4:
	set(v): mandelbulb_c_2 = v; _emit()

# --- Render ---
@export var precision: float = 0.001:
	set(v): precision = v; _emit()


func _emit() -> void:
	if not _suppress:
		emit_changed()


## Write every listed resolved value (by catalogue id) in one batch, emitting
## `changed` at most once and only if something actually differed. A shape with
## no active binding costs no signal per frame.
func apply_resolved(values: Dictionary) -> void:
	var dirty := false
	_suppress = true
	for k in RESOLVED_KEYS:
		if not values.has(k):
			continue
		var v: Variant = values[k]
		if get(k) != v:
			set(k, v)
			dirty = true
	_suppress = false
	if dirty:
		emit_changed()


## Copy every resolved field from another shape (placement included).
func copy_from(other: ShapeParams) -> void:
	var values := {}
	for k in RESOLVED_KEYS:
		values[k] = other.get(k)
	apply_resolved(values)


## The Julia constant's first three components, in the shape's own frame.
func julia_point() -> Vector3:
	return Vector3(c_0, c_1, c_2)


## Whether the Julia marker shows: the master toggle, on the Mandelbox only
## (the other shapes have no Julia constant).
func julia_enabled() -> bool:
	return julia_all and shape == FractalParams.Shape.MANDELBOX


## Half the side of the shape-centred cube (in local units) the rays march in
## (and the orbit camera aims into): the Mandelbox's 2, or 20 for its Julia
## sets, which reach further, and more with a hybrid fold, whose interval
## [lo, hi] lets the shape grow to about hi (measured: 3.2 at mix 0.5, 5.6 at
## 0.75, 13 at 0.9; capped at 20); for the KIFS a margin over its offset, which
## its attractor lies within; for the Kleinian, which fills space, a cube too
## large to matter (view_distance() ends its rays instead); for the Mandelbulb
## its escape radius (MandelbulbEstimator.escape_radius: 2^(1/7), about 1.1, at
## power 8), which every point of it lies within, or 2 if larger.
func bound_half() -> float:
	match shape:
		FractalParams.Shape.MANDELBULB:
			return maxf(2.0, MandelbulbEstimator.escape_radius(self))
		FractalParams.Shape.KIFS:
			var o := sqrt(kifs_offset_0 * kifs_offset_0 + kifs_offset_1 * kifs_offset_1
				+ kifs_offset_2 * kifs_offset_2 + kifs_offset_3 * kifs_offset_3)
			return maxf(2.0, 1.5 * o)
		FractalParams.Shape.KLEINIAN:
			return KLEINIAN_BOUND
	var half := 20.0 if julia_all else 2.0
	if hybrid_mix > 0.0:
		var hi := (fold_limit + hybrid_mix) / maxf(1.0 - hybrid_mix, 1e-6)
		half = maxf(half, minf(1.0 + hi, 20.0))
	return half


## How far from the eye a ray may go before it stops, in world units, or 0 for
## no limit: the Kleinian's View distance (a local length, scaled by the
## size), so its endless corridors end in a soft horizon.
func view_distance() -> float:
	return kleinian_view_distance * size if shape == FractalParams.Shape.KLEINIAN else 0.0


## How many iterations the march's coarse pass needs for a camera `near` (in
## this shape's local units) from the nearest surface, at the view's `detail`.
## Each iteration adds detail |box_scale| times finer, so stopping after n
## leaves a smoother surface about COARSE_BOX_HALF / |box_scale|^n away from
## the real one. The coarse pass stops at twice the hit threshold, 2 × eps ×
## near (eps = precision / detail), so it needs that gap under the threshold:
## n = log(box / (2 eps near)) / log|box_scale|, rounded up, kept in [16, 32].
## 16 at the default view, so the site's picture is unchanged; it rises inside
## about 0.3 of the surface and reaches 32 by about 3e-6. A |box_scale| of 1 or
## less has no shrinking detail: 32. Uses the unshed detail: the still frame
## renders at load level 0.
##
## The KIFS shrinks its detail by its own scale each iteration, so the same
## rule runs on kifs_scale. The Kleinian has no steady rate (its inversion
## magnifies only inside the sphere, by a varying amount), so it always gets
## the full 32; its loop stops early anyway once the point settles. (With a
## scale drift the Mandelbox's rate changes along the orbit; |box_scale| is the
## rate it starts at.) The Mandelbulb's orbit near its surface has radius about
## 1, where each iteration stretches by about the power, so the rule runs on
## mandelbulb_power.
func coarse_iters(near: float, detail: float = 1.0) -> int:
	var s := absf(box_scale)
	match shape:
		FractalParams.Shape.KLEINIAN:
			return DistanceEstimator.ITERATIONS
		FractalParams.Shape.KIFS:
			s = absf(kifs_scale)
		FractalParams.Shape.MANDELBULB:
			s = absf(mandelbulb_power)
	if s <= 1.0:
		return DistanceEstimator.ITERATIONS
	var gap := maxf(2.0 * precision / detail * maxf(near, 0.0), 1e-300)
	var n := ceilf(log(COARSE_BOX_HALF / gap) / log(s))
	return clampi(int(minf(n, 1e6)), COARSE_ITERS_MIN, DistanceEstimator.ITERATIONS)


## How close the fly camera may come to this shape's surface with its eye at
## the given world point, in world units. The shader works out ray positions in
## the shape's own frame, in 32-bit floats, which near the eye can only land on
## a grid ulp32(largest |local coordinate|) apart; once the hit threshold
## (eps × distance, eps = precision / detail) is much finer than that grid, rays
## reach the surface only by luck and the picture breaks into speckle and pits.
## The floor is ulp32 / (ZOOM_FLOOR_DIVISOR × eps) local units, times the size:
## about 1e-4 × size near the box at the default precision, so a nested shape's
## floor shrinks with it. A higher Detail (a finer threshold) and a larger local
## coordinate (Julia mode's bigger box) both push it further out. Uses the
## unshed detail, like coarse_iters.
func zoom_floor(ex: float, ey: float, ez: float, detail: float = 1.0) -> float:
	var q := to_local(ex, ey, ez)
	var m := maxf(absf(q[0]), maxf(absf(q[1]), absf(q[2])))
	return FractalParams.ulp32(m) * size / (ZOOM_FLOOR_DIVISOR * maxf(precision / detail, 1e-30))


# ------------------------------------------------------------------ the frame

## The rotation R = Rz · Ry · Rx as nine 64-bit floats, row-major:
## [r00, r01, r02, r10, r11, r12, r20, r21, r22]. Column j is the shape's local
## axis j expressed in world coordinates.
func frame() -> Array:
	var a := deg_to_rad(rot_x)
	var b := deg_to_rad(rot_y)
	var c := deg_to_rad(rot_z)
	var ca := cos(a); var sa := sin(a)
	var cb := cos(b); var sb := sin(b)
	var cc := cos(c); var sc := sin(c)
	return [
		cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa,
		sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa,
		-sb, cb * sa, cb * ca,
	]


## The local axes in world coordinates (the columns of R), as three Vector3.
func axes() -> Array:
	var r := frame()
	return [Vector3(r[0], r[3], r[6]), Vector3(r[1], r[4], r[7]), Vector3(r[2], r[5], r[8])]


func basis() -> Basis:
	var ax := axes()
	return Basis(ax[0], ax[1], ax[2])


## A world point (64-bit components) in the shape's frame: Rᵀ (p − pos) / size.
## Returns [x, y, z] as 64-bit floats.
func to_local(px: float, py: float, pz: float) -> Array:
	var r := frame()
	var dx := px - pos_x
	var dy := py - pos_y
	var dz := pz - pos_z
	var inv := 1.0 / size
	return [
		(r[0] * dx + r[3] * dy + r[6] * dz) * inv,
		(r[1] * dx + r[4] * dy + r[7] * dz) * inv,
		(r[2] * dx + r[5] * dy + r[8] * dz) * inv,
	]


## A direction (no translation, no scale) into the shape's frame: Rᵀ d.
func dir_to_local(dx: float, dy: float, dz: float) -> Array:
	var r := frame()
	return [
		r[0] * dx + r[3] * dy + r[6] * dz,
		r[1] * dx + r[4] * dy + r[7] * dz,
		r[2] * dx + r[5] * dy + r[8] * dz,
	]


## A local point back into the world: R q × size + pos. Returns [x, y, z].
func to_world(qx: float, qy: float, qz: float) -> Array:
	var r := frame()
	return [
		(r[0] * qx + r[1] * qy + r[2] * qz) * size + pos_x,
		(r[3] * qx + r[4] * qy + r[5] * qz) * size + pos_y,
		(r[6] * qx + r[7] * qy + r[8] * qz) * size + pos_z,
	]


## Vector3 conveniences (32-bit, for drawing and projection; never for the march).
func to_local_v(p: Vector3) -> Vector3:
	var q := to_local(p.x, p.y, p.z)
	return Vector3(q[0], q[1], q[2])


func to_world_v(q: Vector3) -> Vector3:
	var p := to_world(q.x, q.y, q.z)
	return Vector3(p[0], p[1], p[2])


func position() -> Vector3:
	return Vector3(pos_x, pos_y, pos_z)
