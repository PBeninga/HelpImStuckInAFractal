class_name DistanceEstimator
extends RefCounted
## CPU copy of the shader's distance estimators, N = 32 (the high-precision
## variant) unless a smaller iteration count is asked for, as the shader's
## coarse pass does (ShapeParams.coarse_iters), and the scene functions built
## on them. estimate_at() takes a point in ONE shape's own frame and dispatches
## on shape.shape to the Mandelbox core below, KifsEstimator, KleinianEstimator
## or MandelbulbEstimator. The Mandelbox core mirrors mandelbox.gdshader's
## mb_step in 64-bit scalars (zx, zy, zz, zw): the fold (box, cylinder or
## octahedral, or the box-to-abs hybrid fold), the sphere fold, optional 4D
## iteration rotation, scale (drifting with the iteration) and add, carrying
## the running derivative dz. Must give the same numbers as the shader's
## `de(i, p, iters)`.
##
## The scene: a world point is mapped into each shape's frame (ShapeParams
## .to_local, 64-bit), the local estimate is scaled back by the shape's size,
## and the smallest wins: the union of the shapes. A shape whose cube is further
## away than the best distance so far is skipped, as the shader does.
##
## The orbit runs in scalar `float` locals (GDScript floats are 64-bit) rather
## than Vector math, because Vector components are 32-bit in a standard build
## and that lost input precision is amplified near the surface, throwing off the
## near-boundary fixtures; the frame maths is 64-bit for the same reason, where
## it matters even more (a small shape far from the origin).

const ITERATIONS := 32

# The six rotation planes, in the shader's fixed order, as (a, b) index pairs
# into (x, y, z, w) = (0, 1, 2, 3).
const PLANES := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]


# ------------------------------------------------------------------ the scene

## The scene distance at a world point: the smallest shape distance.
static func estimate(p: Vector3, params: FractalParams, iters: int = -1) -> float:
	return scene_estimate_at(p.x, p.y, p.z, params, iters)


## The scene distance at a world point given in 64-bit components.
static func scene_estimate_at(px: float, py: float, pz: float, params: FractalParams,
		iters: int = -1) -> float:
	return nearest_at(px, py, pz, params, iters)["distance"]


## The nearest shape and its (world) distance at a world point:
## {"distance": float, "index": int}.
static func nearest_at(px: float, py: float, pz: float, params: FractalParams,
		iters: int = -1) -> Dictionary:
	iters = params.fractal_iterations if iters < 0 else mini(iters, params.fractal_iterations)
	var best := INF
	var which := 0
	for i in params.visible_shape_indices():
		var s := params.shapes[i]
		var q := s.to_local(px, py, pz)
		var bound := cube_distance(q[0], q[1], q[2], s.bound_half()) * s.size
		if bound >= best:
			continue
		var d := estimate_at(q[0], q[1], q[2], s, iters,
			params.kifs_bailout_margin, params.mandelbulb_bailout_margin) * s.size
		if d < best:
			best = d
			which = i
	return {"distance": best, "index": which}


## Distance from a local point to the cube of half-size `half` (0 inside): the
## cheap lower bound the scene uses to skip shapes that cannot be nearest.
static func cube_distance(qx: float, qy: float, qz: float, half: float) -> float:
	var dx := maxf(absf(qx) - half, 0.0)
	var dy := maxf(absf(qy) - half, 0.0)
	var dz := maxf(absf(qz) - half, 0.0)
	return sqrt(dx * dx + dy * dy + dz * dz)


## Where a world ray enters and leaves the union of the shapes' cubes, in world
## ray distance: [t_enter, t_exit], or null when it meets none. Each cube is
## intersected in its shape's own frame (so a rotated shape's box is oriented).
## Clipped to the exit sphere and scene view distance (a Kleinian's horizon),
## matching the renderer so picks and the centre ray only see visible shapes.
static func scene_bounds(ex: float, ey: float, ez: float, dir: Vector3, params: FractalParams) -> Variant:
	var t_start := INF
	var t_exit := -1.0
	for i in params.visible_shape_indices():
		var s := params.shapes[i]
		var o := s.to_local(ex, ey, ez)
		var d := s.dir_to_local(dir.x, dir.y, dir.z)
		var tb := box_intersect(o, d, s.bound_half())
		var enter: float = tb[0] * s.size
		var leave: float = tb[1] * s.size
		if leave >= maxf(enter, 0.0):
			t_start = minf(t_start, maxf(enter, 0.0))
			t_exit = maxf(t_exit, leave)
	if t_exit < 0.0:
		return null
	var origin := params.escape_origin()
	ex -= origin[0]
	ey -= origin[1]
	ez -= origin[2]
	var b := ex * dir.x + ey * dir.y + ez * dir.z
	var radius := params.escape_radius()
	var discriminant := b * b - (ex * ex + ey * ey + ez * ez) + radius * radius
	if discriminant < 0.0:
		return null
	var root := sqrt(discriminant)
	t_start = maxf(t_start, maxf(0.0, -b - root))
	t_exit = minf(t_exit, -b + root)
	var vd := params.scene_view_distance()
	if vd > 0.0:
		t_exit = minf(t_exit, vd)   # the shader stops there too
	if t_start > t_exit:
		return null
	return [t_start, t_exit]


## Ray vs the axis-aligned cube of half-size `half` at the origin, in whatever
## frame `o` and `d` are given: [t_enter, t_exit]; a miss has
## t_exit < max(t_enter, 0). Mirrors box_intersect() in the shader.
static func box_intersect(o: Array, d: Array, half: float) -> Array:
	var t_enter := -INF
	var t_exit := INF
	for a in 3:
		var sgn := 1.0 if d[a] >= 0.0 else -1.0
		var safe: float = sgn * maxf(absf(d[a]), 1e-9)
		var inv := 1.0 / safe
		var n: float = inv * o[a]
		var k := absf(inv) * half
		t_enter = maxf(t_enter, -n - k)
		t_exit = minf(t_exit, -n + k)
	return [t_enter, t_exit]


## Single-phase high-precision CPU march of a world ray from a 64-bit eye, with
## the shader's level-of-detail hit threshold. Returns the hit Vector3 or null.
## The orbit camera uses it to re-centre on what is under the cursor.
static func march(ex: float, ey: float, ez: float, dir: Vector3, params: FractalParams, max_steps := 200) -> Variant:
	var bounds: Variant = scene_bounds(ex, ey, ez, dir, params)
	if bounds == null:
		return null
	var total: float = bounds[0]
	var t_exit: float = bounds[1]
	var near := scene_estimate_at(ex, ey, ez, params)
	for i in max_steps:
		var px := ex + dir.x * total
		var py := ey + dir.y * total
		var pz := ez + dir.z * total
		var n := nearest_at(px, py, pz, params)
		var d: float = n["distance"]
		if d < params.hit_epsilon(total, near, params.shapes[n["index"]].precision):
			return Vector3(px, py, pz)
		total += d
		if total > t_exit:
			return null
	return null


# ------------------------------------------------------------------ one shape

## The distance of one shape at a point in ITS OWN frame, in local units.
## `iters` is clamped to [0, ITERATIONS]; the default is the shader's `de(i, p, 32)`.
## Scene callers supply their view's margins; standalone estimates keep 1x.
static func estimate_at(px: float, py: float, pz: float, shape: ShapeParams,
		iters: int = ITERATIONS, kifs_bailout_margin: float = 1.0,
		mandelbulb_bailout_margin: float = 1.0) -> float:
	match shape.shape:
		FractalParams.Shape.KIFS:
			return KifsEstimator.estimate_at(px, py, pz, shape, iters, kifs_bailout_margin)
		FractalParams.Shape.KLEINIAN:
			return KleinianEstimator.estimate_at(px, py, pz, shape, iters)
		FractalParams.Shape.MANDELBULB:
			return MandelbulbEstimator.estimate_at(px, py, pz, shape, iters, mandelbulb_bailout_margin)
	return mandelbox_at(px, py, pz, shape, iters)


## The Mandelbox estimate, whatever shape.shape says.
static func mandelbox_at(px: float, py: float, pz: float, params: ShapeParams,
		iters: int = ITERATIONS) -> float:
	var scale := params.box_scale
	var drift := params.scale_drift
	var fold_shape := params.fold_shape
	var mix := params.hybrid_mix
	var every := maxi(params.hybrid_every, 1)
	var mr2 := params.min_radius * params.min_radius
	var fr2 := params.fixed_radius * params.fixed_radius
	var fold := params.fold_limit
	var fold_order := params.fold_order

	var z0 := [px, py, pz, params.w]
	# Per component: the Julia constant where it is checked, else the point's own.
	var c := [
		params.c_0 if (params.julia_all or params.julia_0) else z0[0],
		params.c_1 if (params.julia_all or params.julia_1) else z0[1],
		params.c_2 if (params.julia_all or params.julia_2) else z0[2],
		params.c_3 if (params.julia_all or params.julia_3) else z0[3],
	]

	var angles := [params.iter_rot_xy, params.iter_rot_xz, params.iter_rot_xw,
		params.iter_rot_yz, params.iter_rot_yw, params.iter_rot_zw]
	var rotating := false
	for a in angles:
		if absf(a) > 1e-6:
			rotating = true
			break
	# Precompute cos/sin per plane once.
	var cosv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var sinv := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if rotating:
		for i in 6:
			var r := deg_to_rad(angles[i])
			cosv[i] = cos(r)
			sinv[i] = sin(r)

	var z := [z0[0], z0[1], z0[2], z0[3]]
	var dz := 1.0
	for i in clampi(iters, 0, ITERATIONS):
		var hybrid := mix > 0.0 and i % every == every - 1
		if fold_order == 0:
			_fold(z, fold, fold_shape, hybrid, mix)
			dz = _sphere_fold(z, dz, mr2, fr2)
		else:
			dz = _sphere_fold(z, dz, mr2, fr2)
			_fold(z, fold, fold_shape, hybrid, mix)
		if rotating:
			for p in 6:
				_rot_plane(z, PLANES[p][0], PLANES[p][1], cosv[p], sinv[p])
		var s := scale + drift * i
		z[0] = s * z[0] + c[0]
		z[1] = s * z[1] + c[1]
		z[2] = s * z[2] + c[2]
		z[3] = s * z[3] + c[3]
		dz = dz * absf(s) + 1.0
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	return sqrt(r2) / absf(dz)



## The fold step: the chosen fold, or on a hybrid iteration the morph from the
## box fold toward the abs fold (see hybrid_fold). Every fold reflects through
## a convex set's boundary, so each is 1-Lipschitz and the running derivative
## needs no factor.
static func _fold(z: Array, fold: float, fold_shape: int, hybrid: bool, mix: float) -> void:
	if hybrid:
		hybrid_fold(z, fold, mix)
	elif fold_shape == MandelboxShape.FoldShape.CYLINDER:
		_cylinder_fold(z, fold)
	elif fold_shape == MandelboxShape.FoldShape.OCTAHEDRAL:
		_octahedral_fold(z, fold)
	else:
		_box_fold(z, fold)


## Reflect each component through the interval [lo, hi], which slides from the
## box fold's [-L, L] at mix 0 to [0, infinity) at mix 1: the abs fold, KIFS's
## fold into the positive corner. Blending the two folds' results instead would
## cancel far from the centre (the box fold sends x to about -x, the abs fold to
## |x|), and nothing would ever escape; a moving interval is a true fold all
## the way.
static func hybrid_fold(z: Array, fold: float, mix: float) -> void:
	var lo := -fold * (1.0 - mix)
	var hi := (fold + mix) / maxf(1.0 - mix, 1e-6)
	for k in 4:
		z[k] = clampf(z[k], lo, hi) * 2.0 - z[k]


## KIFS's coordinate fold: fold into the positive orthant, then sort x >= y >= z.
static func menger_fold(z: Array) -> void:
	for k in 4:
		z[k] = absf(z[k])
	if z[0] < z[1]:
		var t: float = z[0]; z[0] = z[1]; z[1] = t
	if z[0] < z[2]:
		var t: float = z[0]; z[0] = z[2]; z[2] = t
	if z[1] < z[2]:
		var t: float = z[1]; z[1] = z[2]; z[2] = t


## Reflect the xy pair through the circle of radius `fold` (r -> 2 fold - r
## outside it, the box fold's rule applied to the radius); z and w get the
## plain box fold.
static func _cylinder_fold(z: Array, fold: float) -> void:
	var r := sqrt(z[0] * z[0] + z[1] * z[1])
	if r > fold:
		var f := (2.0 * fold - r) / r
		z[0] *= f
		z[1] *= f
	z[2] = clampf(z[2], -fold, fold) * 2.0 - z[2]
	z[3] = clampf(z[3], -fold, fold) * 2.0 - z[3]


## Reflect xyz through the octahedron |x| + |y| + |z| <= fold: twice the
## nearest point of the octahedron, minus the point. (The box fold is the same
## rule for the cube.) The nearest point soft-thresholds every |component| by
## the theta that lands it on the surface. w gets the plain box fold.
static func _octahedral_fold(z: Array, fold: float) -> void:
	var lim := maxf(fold, 0.0)
	var ax := absf(z[0])
	var ay := absf(z[1])
	var az := absf(z[2])
	if ax + ay + az > lim:
		# u: the three magnitudes, largest first.
		var u1 := maxf(ax, maxf(ay, az))
		var u3 := minf(ax, minf(ay, az))
		var u2 := ax + ay + az - u1 - u3
		var theta := u1 - lim
		var t2 := (u1 + u2 - lim) / 2.0
		if u2 > t2:
			theta = t2
			var t3 := (u1 + u2 + u3 - lim) / 3.0
			if u3 > t3:
				theta = t3
		for k in 3:
			var a := absf(z[k])
			var pk := signf(z[k]) * maxf(a - theta, 0.0)
			z[k] = 2.0 * pk - z[k]
	z[3] = clampf(z[3], -fold, fold) * 2.0 - z[3]


static func _box_fold(z: Array, fold: float) -> void:
	z[0] = clampf(z[0], -fold, fold) * 2.0 - z[0]
	z[1] = clampf(z[1], -fold, fold) * 2.0 - z[1]
	z[2] = clampf(z[2], -fold, fold) * 2.0 - z[2]
	z[3] = clampf(z[3], -fold, fold) * 2.0 - z[3]


static func _sphere_fold(z: Array, dz: float, mr2: float, fr2: float) -> float:
	var mr := maxf(mr2, 1e-12)
	var fr := maxf(fr2, 1e-12)
	var r2: float = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3]
	var f := 1.0
	if r2 < mr:
		f = fr / mr
	elif r2 < fr:
		f = fr / maxf(r2, 1e-12)
	z[0] *= f
	z[1] *= f
	z[2] *= f
	z[3] *= f
	return dz * f


static func _rot_plane(z: Array, a: int, b: int, c: float, s: float) -> void:
	var za: float = z[a]
	var zb: float = z[b]
	z[a] = za * c - zb * s
	z[b] = za * s + zb * c
