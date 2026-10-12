class_name SurfaceFixture
extends RefCounted
## A point on the default view's surface, for the deep-zoom tests:
##   var s := SurfaceFixture.default_surface(params)   # [x, y, z, fx, fy, fz]
## The centre ray's hit (CenterRay.march) stops within its hit threshold of the
## surface, about 1.7e-4 short of it at the default view; this marches on along
## the same ray in 64-bit scalars until the 32-iteration estimate is under
## 1e-10 (round-off stalls it near 2e-11), so a camera backed off from the
## point by d sits about d (along the ray) from the real surface. (fx, fy, fz) is the default camera's forward.


static func default_surface(params: FractalParams) -> Array:
	var cam := CameraState.make_default()
	var e := cam.eye()
	var f := cam.forward()
	var t: float = CenterRay.march(e, f, params)[0]
	var x: float = e.x + f.x * t
	var y: float = e.y + f.y * t
	var z: float = e.z + f.z * t
	for _i in 400:
		var d := DistanceEstimator.scene_estimate_at(x, y, z, params)
		if d < 1e-10:
			break
		x += f.x * d
		y += f.y * d
		z += f.z * d
	return [x, y, z, f.x, f.y, f.z]


## The surface point the ray from `eye` toward the origin meets, refined in
## 64-bit like default_surface, but marched from the eye itself so any shape and
## eye work. Where round-off stalls the march it keeps the closest point it
## reached. Returns [x, y, z, fx, fy, fz].
static func surface_from(params: FractalParams, eye: Vector3) -> Array:
	var f := (Vector3.ZERO - eye).normalized()
	var x: float = eye.x
	var y: float = eye.y
	var z: float = eye.z
	var best := [x, y, z]
	var best_d := INF
	for _i in 3000:
		var d := DistanceEstimator.scene_estimate_at(x, y, z, params)
		if d < best_d:
			best_d = d
			best = [x, y, z]
		if d < 1e-10:
			break
		x += f.x * d
		y += f.y * d
		z += f.z * d
	return [best[0], best[1], best[2], f.x, f.y, f.z]


## The surface point along unit `dir` from the 64-bit point `from`: marched in
## 64-bit until the 32-iteration estimate is under `tol`, keeping the closest
## point reached if round-off stalls it first. Returns [x, y, z, dx, dy, dz, estimate].
static func along(params: FractalParams, from: PackedFloat64Array, dir: Vector3, tol: float) -> Array:
	var x: float = from[0]
	var y: float = from[1]
	var z: float = from[2]
	var best := [x, y, z]
	var best_d := INF
	for _i in 4000:
		var d := DistanceEstimator.scene_estimate_at(x, y, z, params)
		if d < best_d:
			best_d = d
			best = [x, y, z]
		if d < tol:
			break
		x += dir.x * d
		y += dir.y * d
		z += dir.z * d
	return [best[0], best[1], best[2], dir.x, dir.y, dir.z, best_d]


## The camera `back` short of the surface point s along its ray, in 64-bit.
static func backed(s: Array, back: float) -> PackedFloat64Array:
	return PackedFloat64Array([s[0] - s[3] * back, s[1] - s[4] * back, s[2] - s[5] * back])


## FractalParams with a saved view's shape defaults applied (its bindings and
## camera ignored), e.g. save_params("res://saves/juliaIceTerraces.json").
static func save_params(path: String) -> FractalParams:
	var p := FractalParams.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var defaults: Dictionary = data["shape"]["defaults"]
	var values := {}
	for key in defaults:
		values[StringName(key)] = defaults[key]
	p.shape().apply_resolved(values)
	p.apply_resolved(values)
	return p


## How far back along s's ray the 32-iteration estimate at the eye is `target`
## (within 5%): a bisection on log10(back) over [-10, -1]. The estimate is not
## strictly monotone in back, so callers check what they got.
static func back_for_distance(params: FractalParams, s: Array, target: float) -> float:
	var lo := -10.0
	var hi := -1.0
	var mid := 0.0
	for _i in 80:
		mid = 0.5 * (lo + hi)
		var e := backed(s, pow(10.0, mid))
		var d := DistanceEstimator.scene_estimate_at(e[0], e[1], e[2], params)
		if absf(d / target - 1.0) < 0.05:
			break
		if d < target:
			lo = mid
		else:
			hi = mid
	return pow(10.0, mid)


## A 64-bit march from o along unit dir with the shader's fine-pass test (32
## iterations, a hit once the estimate is under eps × t, eps = precision /
## detail), `steps` steps. Returns [t, hit].
static func march64(o: PackedFloat64Array, dir: Array, params: FractalParams, steps: int) -> Array:
	var eps := params.shape().precision / params.detail
	var t := 0.0
	for _i in steps:
		var d := DistanceEstimator.scene_estimate_at(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, params)
		if d < eps * t:
			return [t, true]
		t += d
	return [t, false]


## Every shape variant the perturbation tests run: [name, params, eye, perturbable].
## The eye is where surface_from starts (the fly tests' eyes for the other shapes).
static func variants() -> Array:
	var box_eye := CameraState.DEFAULT_EYE
	var menger_eye := Vector3(3.2, 2.4, 1.9)
	var kl_eye := Vector3(2.5, 1.6, 1.2)
	var kifs := FractalParams.Shape.KIFS
	var kl := FractalParams.Shape.KLEINIAN
	var cyl := MandelboxShape.FoldShape.CYLINDER
	return [
		["default box", _with({}), box_eye, true],
		["box, sphere first", _with({&"fold_order": 1}), box_eye, true],
		["cylinder", _with({&"fold_shape": cyl}), box_eye, true],
		["cylinder, sphere first", _with({&"fold_shape": cyl, &"fold_order": 1}), box_eye, true],
		["hybrid", _with({&"hybrid_mix": 0.5}), box_eye, true],
		["rotating, drifting", _with({&"iter_rot_xy": 5.0, &"iter_rot_xw": 3.0, &"scale_drift": 0.01}), box_eye, true],
		["partial Julia", _with({&"julia_0": true}), box_eye, true],
		["ice field", save_params("res://saves/juliaIceField.json"), box_eye, true],
		["terraces", save_params("res://saves/juliaIceTerraces.json"), box_eye, true],
		["octahedral", _with({&"fold_shape": MandelboxShape.FoldShape.OCTAHEDRAL}), box_eye, false],
		["Menger", _with({&"shape": kifs}), menger_eye, true],
		["Menger, rotated, twisted", _with({&"shape": kifs, &"kifs_rot1_xy": 12.0, &"kifs_rot2_yz": 7.0, &"kifs_twist": 4.0}), menger_eye, true],
		["Sierpinski", _with({&"shape": kifs, &"kifs_fold": KifsEstimator.FoldSet.DIAGONAL, &"kifs_scale": 2.0}), Vector3(3.5, -2.0, 2.2), true],
		["polyfold", _with({&"shape": kifs, &"kifs_fold": KifsEstimator.FoldSet.POLYFOLD}), menger_eye, false],
		["Kleinian", _with({&"shape": kl}), kl_eye, true],
		["Kleinian, shifted", _with({&"shape": kl, &"kleinian_shift_0": 0.1, &"kleinian_shift_2": -0.05}), kl_eye, true],
		["Mandelbulb", _with({&"shape": FractalParams.Shape.MANDELBULB}), Vector3(2.2, 1.6, 1.2), false],
	]


static func _with(values: Dictionary) -> FractalParams:
	var p := FractalParams.new()
	p.shape().apply_resolved(values)
	return p
