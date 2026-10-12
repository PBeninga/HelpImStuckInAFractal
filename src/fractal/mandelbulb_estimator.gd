class_name MandelbulbEstimator
extends RefCounted
## CPU copy of mandelbulb.gdshaderinc's mandelbulb_de at N = 32, in 64-bit
## scalars (see DistanceEstimator for why). The Mandelbulb is 3D, so w is not
## read.
##
## One iteration, power n: with r = |z|, theta = acos(z.z / r) and phi =
## atan2(z.y, z.x), z becomes r^n (sin(n theta + a) cos(n phi + b),
## sin(n theta + a) sin(n phi + b), cos(n theta + a)) + c, where a and b are
## the two phases and c is the point itself (or the Julia constant). The orbit
## stops once r passes bailout(). Alongside it runs dr, how much the orbit has
## stretched a small step at the start: dr becomes n r^(n-1) dr + 1 (the + 1
## because c moves with the point; 0 in Julia mode, where it does not). The
## distance is 0.5 r ln(r) / dr, the escape-time estimate (Hubbard and
## Douady's, for the Mandelbrot set): far outside it is about the distance to
## the set, and it falls to 0 at the surface. Points that never escape can read
## negative, which the march takes as a hit.

const ITERATIONS := 32
## The smallest bailout radius; bailout() raises it for low powers and big
## Julia constants.
const BAILOUT := 2.0


## The radius past which every orbit escapes, at least BAILOUT: 2^(1/(n-1))
## for power n (a point that far out gains radius every iteration however c
## points), or |c| in Julia mode if larger. ShapeParams.bound_half() uses the
## same radius.
static func escape_radius(params: ShapeParams) -> float:
	var n := params.mandelbulb_power
	var r := 20.0 if n <= 1.0 else minf(pow(2.0, 1.0 / (n - 1.0)), 20.0)
	if params.mandelbulb_julia:
		r = maxf(r, Vector3(params.mandelbulb_c_0, params.mandelbulb_c_1, params.mandelbulb_c_2).length())
	return r


static func bailout(params: ShapeParams) -> float:
	return maxf(BAILOUT, escape_radius(params))


## `iters` is clamped to [0, ITERATIONS], as DistanceEstimator's.
static func estimate_at(px: float, py: float, pz: float, params: ShapeParams,
		iters: int = ITERATIONS, bailout_margin: float = 1.0) -> float:
	var n := params.mandelbulb_power
	var julia := params.mandelbulb_julia
	var cx := params.mandelbulb_c_0 if julia else px
	var cy := params.mandelbulb_c_1 if julia else py
	var cz := params.mandelbulb_c_2 if julia else pz
	var add := 0.0 if julia else 1.0
	var a := deg_to_rad(params.mandelbulb_phase_theta)
	var b := deg_to_rad(params.mandelbulb_phase_phi)
	var bail := bailout(params) * bailout_margin
	var escape_inverse := 1.0 / (bail + sqrt(cx * cx + cy * cy + cz * cz)) if bailout_margin > 1.0 else 0.0
	var zx := px
	var zy := py
	var zz := pz
	var dr := 1.0
	var r := sqrt(zx * zx + zy * zy + zz * zz)
	for _i in clampi(iters, 0, ITERATIONS):
		if r > bail:
			break
		var theta := acos(clampf(zz / maxf(r, 1e-30), -1.0, 1.0)) * n + a
		var phi := atan2(zy, zx) * n + b
		var dx := sin(theta) * cos(phi)
		var dy := sin(theta) * sin(phi)
		var dz := cos(theta)
		if bailout_margin > 1.0 and r > 1.0:
			var inv_rn := pow(r, -n)
			if inv_rn < escape_inverse:
				# This next step must escape. Cancel r^n in its final DE,
				# matching the shader's overflow-safe evaluation.
				var qx := dx + cx * inv_rn
				var qy := dy + cy * inv_rn
				var qz := dz + cz * inv_rn
				var q := sqrt(qx * qx + qy * qy + qz * qz)
				return 0.5 * (n * log(r) + log(q)) * q / ((n / r) * dr + add * inv_rn)
		dr = n * pow(r, n - 1.0) * dr + add
		var rn := pow(r, n)
		zx = rn * dx + cx
		zy = rn * dy + cy
		zz = rn * dz + cz
		r = sqrt(zx * zx + zy * zy + zz * zz)
	r = maxf(r, 1e-30)
	return 0.5 * log(r) * r / dr
