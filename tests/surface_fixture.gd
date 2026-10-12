class_name SurfaceFixture
extends RefCounted
## A point on the default view's surface, for the deep-zoom tests:
##   var s := SurfaceFixture.default_surface(params)   # [x, y, z, fx, fy, fz]
## The centre ray's hit (CenterRay.march) stops within its hit threshold of the
## surface, about 1.7e-4 short of it at the default view; this marches on along
## the same ray in 64-bit scalars until the 32-iteration estimate is under
## 1e-10 (round-off stalls it near 2e-11), so a camera backed off from the
## point by d sits about d (along the ray) from the real surface. (fx, fy, fz) is the default camera's forward.


## Fixed exterior Mandelbox view: numerical fixtures must not depend on the
## player's default spawn, which is inside the Kleinian now.
const OVERVIEW_EYE := Vector3(8.175847, 3.812460, 3.283393)

static func overview_camera() -> CameraState:
	var camera := CameraState.new()
	camera.transform = Transform3D(Basis.IDENTITY, OVERVIEW_EYE).looking_at(Vector3.ZERO, Vector3(0, 0, 1))
	return camera


static func default_surface(params: FractalParams) -> Array:
	var cam := overview_camera()
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


## The camera `back` short of the surface point s along its ray, in 64-bit.
static func backed(s: Array, back: float) -> PackedFloat64Array:
	return PackedFloat64Array([s[0] - s[3] * back, s[1] - s[4] * back, s[2] - s[5] * back])


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
