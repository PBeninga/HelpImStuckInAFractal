// KIFS distance estimate, included by mandelbox.gdshader after mb_rot_plane
// and menger_fold. Ported from Fractacular's kifs technique; KifsEstimator is
// the CPU copy, and its header explains the two changes from Fractacular (the
// diagonal fold before any abs; the mirror polyfold). Uniform names are the
// catalogue ids (src/fractal/kifs_shape.gd).

uniform float kifs_scale;
uniform int kifs_fold;        // 0 coordinate, 1 diagonal, 2 polyfold
uniform float kifs_poly_k;
uniform float kifs_twist;     // degrees per iteration, in xy
uniform float kifs_offset_0;
uniform float kifs_offset_1;
uniform float kifs_offset_2;
uniform float kifs_offset_3;
uniform float kifs_rot1_xy;
uniform float kifs_rot1_xz;
uniform float kifs_rot1_xw;
uniform float kifs_rot1_yz;
uniform float kifs_rot1_yw;
uniform float kifs_rot1_zw;
uniform float kifs_rot2_xy;
uniform float kifs_rot2_xz;
uniform float kifs_rot2_xw;
uniform float kifs_rot2_yz;
uniform float kifs_rot2_yw;
uniform float kifs_rot2_zw;

vec4 kifs_rot1(vec4 p) {
	p = mb_rot_plane(p, 0, 1, kifs_rot1_xy);
	p = mb_rot_plane(p, 0, 2, kifs_rot1_xz);
	p = mb_rot_plane(p, 0, 3, kifs_rot1_xw);
	p = mb_rot_plane(p, 1, 2, kifs_rot1_yz);
	p = mb_rot_plane(p, 1, 3, kifs_rot1_yw);
	p = mb_rot_plane(p, 2, 3, kifs_rot1_zw);
	return p;
}

vec4 kifs_rot2(vec4 p) {
	p = mb_rot_plane(p, 0, 1, kifs_rot2_xy);
	p = mb_rot_plane(p, 0, 2, kifs_rot2_xz);
	p = mb_rot_plane(p, 0, 3, kifs_rot2_xw);
	p = mb_rot_plane(p, 1, 2, kifs_rot2_yz);
	p = mb_rot_plane(p, 1, 3, kifs_rot2_yw);
	p = mb_rot_plane(p, 2, 3, kifs_rot2_zw);
	return p;
}

// Reflect across x = -y, x = -z, y = -z and x = -w: the Sierpinski fold.
vec4 kifs_diagonal_fold(vec4 p) {
	if (p.x + p.y < 0.0) { p.xy = -p.yx; }
	if (p.x + p.z < 0.0) { p.xz = -p.zx; }
	if (p.y + p.z < 0.0) { p.yz = -p.zy; }
	if (p.x + p.w < 0.0) { p.xw = -p.wx; }
	return p;
}

// Mirror the xy angle into [0, sector / 2]: k-fold mirror symmetry,
// continuous across the wedge edges.
vec4 kifs_poly_fold(vec4 p) {
	float sector = 6.283185307179586 / float(max(int(floor(kifs_poly_k + 0.5)), 2));
	float r = length(p.xy);
	float a = abs(mod(atan(p.y, p.x) + 0.5 * sector, sector) - 0.5 * sector);
	p.xy = r * vec2(cos(a), sin(a));
	return p;
}

// Signed distance from p to the box [-1, 1]^4.
float kifs_box_distance(vec4 p) {
	vec4 q = abs(p) - 1.0;
	return length(max(q, 0.0)) + min(max(max(q.x, q.y), max(q.z, q.w)), 0.0);
}

bool kifs_rot1_on() {
	return (abs(kifs_rot1_xy) + abs(kifs_rot1_xz) + abs(kifs_rot1_xw)
		+ abs(kifs_rot1_yz) + abs(kifs_rot1_yw) + abs(kifs_rot1_zw)) > 1e-6;
}

bool kifs_rot2_on() {
	return (abs(kifs_rot2_xy) + abs(kifs_rot2_xz) + abs(kifs_rot2_xw)
		+ abs(kifs_rot2_yz) + abs(kifs_rot2_yw) + abs(kifs_rot2_zw)) > 1e-6;
}

// Iterations first..iters-1 of the KIFS orbit p; n counts the iterations run. The
// direct kifs_de runs them all from 0, the perturbed de_pert from its handoff.
void kifs_orbit(inout vec4 p, inout int n, int first, int iters) {
	float s = kifs_scale;
	vec4 o = vec4(kifs_offset_0, kifs_offset_1, kifs_offset_2, kifs_offset_3);
	bool rot1 = kifs_rot1_on();
	bool rot2 = kifs_rot2_on();
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		if (rot1) { p = kifs_rot1(p); }
		if (kifs_fold == 1) {
			p = kifs_diagonal_fold(p);
		} else {
			if (kifs_fold == 2) { p = kifs_poly_fold(p); }
			p = menger_fold(p);
		}
		if (rot2) { p = kifs_rot2(p); }
		if (kifs_twist != 0.0) { p = mb_rot_plane(p, 0, 1, kifs_twist * float(i)); }
		p = s * p - (s - 1.0) * o;
		if (kifs_fold == 0) {
			// The Menger correction: reflect the far z layer back.
			float t = o.z * (s - 1.0);
			if (p.z < -0.5 * t) { p.z += t; }
		}
		n = i + 1;
		if (dot(p, p) > 1.0e6) { break; }
	}
}

// The distance from the orbit's end point, shrunk by the scale once per iteration.
float kifs_distance(vec4 p, int n) {
	float d = kifs_fold == 0 ? kifs_box_distance(p) : length(p);
	return d * pow(kifs_scale, -float(n));
}

float kifs_de(vec4 p, int iters) {
	int n = 0;
	kifs_orbit(p, n, 0, iters);
	return kifs_distance(p, n);
}
