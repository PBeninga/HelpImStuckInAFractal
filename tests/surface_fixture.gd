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
