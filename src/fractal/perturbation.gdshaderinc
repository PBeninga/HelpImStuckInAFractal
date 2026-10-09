// Perturbation: the march past the 32-bit floor (spec: docs/superpowers/specs/
// 2026-10-09-perturbation-deep-zoom-design.md). Included by mandelbox.gdshader
// after calc_nf. While pert_iters > 0 the march never forms eye + dir * t for the
// estimate. The CPU (ReferenceOrbit) runs the camera's own orbit X_0 .. X_32 in
// 64-bit and hands down, for each of the first iterations, the gaps between X and
// each fold's creases: small numbers, which a 32-bit float holds precisely. The
// GPU iterates only the pixel's offset dl = P - X, with a difference formula per
// step that never subtracts two nearly equal large numbers. Each ray hands off on
// its own, at the first iteration h where it runs out of records or its offset
// reaches PERT_HANDOFF: z = X_h + dl (pert_x[h], a 32-bit sum, now precise
// enough), and the ordinary loop runs from h. A far ray (|off| >= PERT_HANDOFF)
// hands off at h = 0, where z = eye + off: today's expression exactly.
// tests/perturbation_port.gd is this file's GDScript twin: keep them in step.
//
// The record for iteration i (ReferenceOrbit builds it):
//   Mandelbox  a: lo - X per component of the fold's input (cylinder: a.xy = X.xy itself)
//              b: hi - X              c: the sphere fold's input point
//              d: (|c|^2 - min_r^2, |c|^2 - fixed_r^2, the reference's factor m, cylinder r_xy - L)
//   KIFS       a: -X after R1 (the abs gaps)
//              b: the three sort gaps, or the four diagonal gaps, each at its comparison
//              c.x: the Menger gap X_z + t/2 after the scale    d: X_{i+1}
//   Kleinian   a: -box - X    b: box - X    c: the post-fold point
//              d: (|c|^2 - radius^2, m, 0, 0)

uniform int pert_iters;    // the records available, min(PERT_MAX, n); 0 = off (the direct march, exactly as before)
uniform vec4 pert_a[20];   // the record, ReferenceOrbit.PERT_MAX = 20 iterations
uniform vec4 pert_b[20];
uniform vec4 pert_c[20];
uniform vec4 pert_d[20];
uniform vec4 pert_x[21];   // X_0 .. X_PERT_MAX: the point a ray hands off to after h perturbed iterations

const int PERT_MAX = 20;
// A ray hands off once |dl| reaches this (FractalParams.PERT_HANDOFF; shader_test checks they match).
const float PERT_HANDOFF = 0.1;

// ---- the perturbed steps: each turns the offset entering a step into the offset leaving it

// A reflection through [lo, hi] (box fold, hybrid fold, Kleinian box), per
// component, given glo = lo - X and ghi = hi - X. One formula covers all nine
// side pairs (inside -> inside gives dl, inside -> above 2 ghi - dl, ...).
vec4 pert_clamp(vec4 dl, vec4 glo, vec4 ghi) {
	return 2.0 * (clamp(dl, glo, ghi) - clamp(vec4(0.0), glo, ghi)) - dl;
}

vec2 pert_clamp2(vec2 dl, vec2 glo, vec2 ghi) {
	return 2.0 * (clamp(dl, glo, ghi) - clamp(vec2(0.0), glo, ghi)) - dl;
}

// The KIFS abs fold: the clamp with its crease at 0 and none above; g = -X.
vec4 pert_abs(vec4 dl, vec4 g) {
	return 2.0 * (max(dl, g) - max(vec4(0.0), g)) - dl;
}

// One compare-and-swap of the KIFS sort (swap when a < b) on the offset pair
// d = (a, b), given g = X_a - X_b at that comparison.
vec2 pert_swap(vec2 d, float g) {
	bool ps = d.x - d.y < -g;   // the pixel swaps
	bool rs = g < 0.0;          // the reference swaps
	if (ps && rs) { return d.yx; }
	if (ps) { return vec2(d.y - g, d.x + g); }
	if (rs) { return vec2(d.x + g, d.y - g); }
	return d;
}

vec4 pert_sort(vec4 dl, vec4 g) {
	dl.xy = pert_swap(dl.xy, g.x);
	dl.xz = pert_swap(dl.xz, g.y);
	dl.yz = pert_swap(dl.yz, g.z);
	return dl;
}

// One diagonal reflection ((a, b) -> (-b, -a) when a + b < 0), given g = X_a + X_b.
vec2 pert_flip(vec2 d, float g) {
	bool ps = d.x + d.y < -g;
	bool rs = g < 0.0;
	if (ps && rs) { return -d.yx; }
	if (ps) { return vec2(-g - d.y, -g - d.x); }
	if (rs) { return vec2(d.x + g, d.y + g); }
	return d;
}

vec4 pert_diagonal(vec4 dl, vec4 g) {
	dl.xy = pert_flip(dl.xy, g.x);
	dl.xz = pert_flip(dl.xz, g.y);
	dl.yz = pert_flip(dl.yz, g.z);
	dl.xw = pert_flip(dl.xw, g.w);
	return dl;
}

// The Menger correction (z += t when z < -t/2) on the offset's z, given
// g = X_z + t/2 after the scale.
float pert_menger(float dz, float g, float t) {
	float pc = dz < -g ? 1.0 : 0.0;
	float rc = g < 0.0 ? 1.0 : 0.0;
	return dz + t * (pc - rc);
}

// The sphere fold (and the Kleinian inversion): dl' = m' dl + X (m' - m), m and m'
// the reference's and the pixel's factors. X is the fold's input (record c);
// gmin = |X|^2 - mr2 and gfix = |X|^2 - fr2 come from the CPU in full precision;
// q = |P|^2 - |X|^2 = 2 X.dl + dl.dl is a sum of products, so no cancellation.
// Regimes: 0 inside (factor fr2 / mr2), 1 shell (fr2 / |P|^2), 2 outside (1).
// m' - m is written per regime pair as a precise small number over a product,
// never as a difference of two factors.
void pert_sphere(inout vec4 dl, inout float dz, vec4 X, float gmin, float gfix, float mr2, float fr2) {
	float q = 2.0 * dot(X, dl) + dot(dl, dl);
	float x2 = dot(X, X);
	float p2 = x2 + q;
	int rx = gmin < 0.0 ? 0 : (gfix < 0.0 ? 1 : 2);
	int rp = gmin + q < 0.0 ? 0 : (gfix + q < 0.0 ? 1 : 2);
	float mp = rp == 0 ? fr2 / mr2 : (rp == 1 ? fr2 / max(p2, 1e-12) : 1.0);
	float dm = 0.0;
	if (rx == 1 && rp == 1) { dm = -fr2 * q / (p2 * x2); }
	else if (rx == 0 && rp == 1) { dm = -fr2 * (gmin + q) / (p2 * mr2); }
	else if (rx == 1 && rp == 0) { dm = fr2 * gmin / (mr2 * x2); }
	else if (rx == 1 && rp == 2) { dm = gfix / x2; }
	else if (rx == 2 && rp == 1) { dm = -(gfix + q) / p2; }
	else if (rx == 0 && rp == 2) { dm = 1.0 - fr2 / mr2; }
	else if (rx == 2 && rp == 0) { dm = fr2 / mr2 - 1.0; }
	dl = mp * dl + X * dm;
	dz *= mp;
}

// The cylinder fold's xy pair (r -> 2L - r outside the circle of radius L): the
// sphere fold's template with m = (2L - r) / r. X is the reference's xy (record
// a.xy), g = r - L its radial gap (record d.w).
vec2 pert_cylinder(vec2 d, vec2 X, float g) {
	float L = fold_limit;
	float rr = L + g;
	float q = 2.0 * dot(X, d) + dot(d, d);
	float rp = sqrt(max(rr * rr + q, 0.0));
	float dr = q / max(rp + rr, 1e-30);   // r' - r without cancellation
	bool xo = g > 0.0;
	bool po = g + dr > 0.0;
	float mp = po ? (2.0 * L - rp) / rp : 1.0;
	float dm = 0.0;
	if (xo && po) { dm = -2.0 * L * dr / (rr * rp); }
	else if (po) { dm = -2.0 * (g + dr) / rp; }
	else if (xo) { dm = 2.0 * g / rr; }
	return mp * d + X * dm;
}

// The Mandelbox's fold step on the offset: the clamp on every component (the
// box fold, or on a hybrid iteration the hybrid interval: the CPU's gaps already
// use the right creases), or the cylinder fold on xy and the clamp on zw.
vec4 pert_mb_fold(vec4 dl, vec4 a, vec4 b, float gr, int i) {
	bool hybrid = false;
	if (hybrid_mix > 0.0) {
		int every = max(hybrid_every, 1);
		hybrid = i % every == every - 1;
	}
	if (fold_shape == 1 && !hybrid) {
		return vec4(pert_cylinder(dl.xy, a.xy, gr), pert_clamp2(dl.zw, a.zw, b.zw));
	}
	return pert_clamp(dl, a, b);
}

// ---- the perturbed estimates. Each runs the perturbed step while i < lim
// (min(pert_iters, iters)) and |dl| < PERT_HANDOFF, then hands off at h.

float de_pert_mandelbox(vec4 dl, vec3 p, int iters) {
	int lim = min(pert_iters, iters);
	// The pixel's c differs from the reference's by its own starting offset where
	// c follows the point (Mandelbrot mode), by nothing where c is the Julia
	// constant; w is the slice's own, the same for both.
	vec4 dc = vec4(
		(julia_all || julia_0) ? 0.0 : dl.x,
		(julia_all || julia_1) ? 0.0 : dl.y,
		(julia_all || julia_2) ? 0.0 : dl.z,
		0.0);
	float mr2 = max(min_radius * min_radius, 1e-12);
	float fr2 = max(fixed_radius * fixed_radius, 1e-12);
	float dz = 1.0;
	bool rotating = mb_rotating();
	int h = 0;
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= lim || dot(dl, dl) >= PERT_HANDOFF * PERT_HANDOFF) { break; }
		vec4 ra = pert_a[i];
		vec4 rb = pert_b[i];
		vec4 rc = pert_c[i];
		vec4 rd = pert_d[i];
		if (fold_order == 0) {
			dl = pert_mb_fold(dl, ra, rb, rd.w, i);
			pert_sphere(dl, dz, rc, rd.x, rd.y, mr2, fr2);
		} else {
			pert_sphere(dl, dz, rc, rd.x, rd.y, mr2, fr2);
			dl = pert_mb_fold(dl, ra, rb, rd.w, i);
		}
		if (rotating) { dl = mb_iter_rotate(dl); }
		float s = box_scale + scale_drift * float(i);
		dl = s * dl + dc;
		dz = dz * abs(s) + 1.0;
		h = i + 1;
	}
	vec4 z = pert_x[h] + dl;
	// 32-bit c: about one eye-ulp off, against an offset of at least PERT_HANDOFF
	vec4 c = mb_constant(vec4(p, w));
	mb_orbit(z, dz, c, h, iters);
	return length(z) / abs(dz);
}

float de_pert_kifs(vec4 dl, int iters) {
	int lim = min(pert_iters, iters);
	float s = kifs_scale;
	float t = kifs_offset_2 * (s - 1.0);
	bool rot1 = kifs_rot1_on();
	bool rot2 = kifs_rot2_on();
	int n = 0;
	int h = 0;
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= lim || dot(dl, dl) >= PERT_HANDOFF * PERT_HANDOFF) { break; }
		if (rot1) { dl = kifs_rot1(dl); }
		if (kifs_fold == 1) {
			dl = pert_diagonal(dl, pert_b[i]);
		} else {
			dl = pert_sort(pert_abs(dl, pert_a[i]), pert_b[i]);
		}
		if (rot2) { dl = kifs_rot2(dl); }
		if (kifs_twist != 0.0) { dl = mb_rot_plane(dl, 0, 1, kifs_twist * float(i)); }
		dl = s * dl;   // the offset term -(s - 1) o cancels
		if (kifs_fold == 0) { dl.z = pert_menger(dl.z, pert_c[i].x, t); }
		n = i + 1;
		h = i + 1;
		vec4 zi = pert_d[i] + dl;   // the pixel's point: large, fine in 32 bits
		if (dot(zi, zi) > 1.0e6) { return kifs_distance(zi, n); }   // the pixel escapes first
	}
	vec4 z = pert_x[h] + dl;
	kifs_orbit(z, n, h, iters);
	return kifs_distance(z, n);
}

float de_pert_kleinian(vec4 dl, int iters) {
	int lim = min(pert_iters, iters);
	float kk = kleinian_radius * kleinian_radius;
	float dr = 1.0;
	int h = 0;
	for (int i = 0; i < PERT_MAX; i++) {
		if (i >= lim || dot(dl, dl) >= PERT_HANDOFF * PERT_HANDOFF) { break; }
		dl = pert_clamp(dl, pert_a[i], pert_b[i]);
		// the inversion: the sphere fold's template with no inner core and
		// fixed_radius^2 = radius^2; the shift cancels
		pert_sphere(dl, dr, pert_c[i], 1.0e30, pert_d[i].x, kk, kk);
		h = i + 1;
	}
	vec4 z = pert_x[h] + dl;
	kleinian_orbit(z, dr, h, iters);
	return kleinian_distance(z, dr);
}

// The estimate at eye + off while pert_iters > 0, without forming that sum for the
// orbit. The noise field is still evaluated at the 32-bit point: a displaced
// surface is smooth below the displacement's size, so there is nothing finer to
// resolve.
float de_pert(vec3 off, int iters) {
	vec3 p = eye + off;
	if (shape == 3) { return de(p, iters); }   // never perturbed (ReferenceOrbit.perturbable is false)
	vec4 dl = vec4(off, 0.0);
	float d;
	if (shape == 1) { d = de_pert_kifs(dl, iters); }
	else if (shape == 2) { d = de_pert_kleinian(dl, iters); }
	else { d = de_pert_mandelbox(dl, p, iters); }
	return d + noise_displace(p);
}

// The march's estimate at ray distance t: the perturbed one while pert_iters > 0,
// else exactly today's de(eye + dir * t). pos is that 32-bit point, off = dir * t.
float march_de(vec3 pos, vec3 off, int iters) {
	if (pert_iters > 0) { return de_pert(off, iters); }
	return de(pos, iters);
}

// calc_normal for the perturbed march: central differences of de_pert around off.
vec3 calc_normal_pert(vec3 off, float delta) {
	vec2 e = vec2(delta, 0.0);
	return normalize(vec3(
		de_pert(off + e.xyy, 32) - de_pert(off - e.xyy, 32),
		de_pert(off + e.yxy, 32) - de_pert(off - e.yxy, 32),
		de_pert(off + e.yyx, 32) - de_pert(off - e.yyx, 32)));
}

// The true surface normal at v = eye + off: today's calc_normal(v, delta) while
// pert_iters is 0.
vec3 true_normal(vec3 v, vec3 off, float delta) {
	if (pert_iters > 0) { return calc_normal_pert(off, delta); }
	return calc_normal(v, delta);
}
