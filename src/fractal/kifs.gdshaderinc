// KIFS distance estimate, included by mandelbox.gdshader after mb_rot_plane
// and menger_fold. Ported from Fractacular's kifs technique; KifsEstimator is
// the CPU copy, and its header explains the two changes from Fractacular (the
// diagonal fold before any abs; the mirror polyfold). Uniform names are the
// catalogue ids (src/fractal/kifs_shape.gd), one array entry per shape.

uniform float kifs_scale[MAX_SHAPES];
uniform int kifs_fold[MAX_SHAPES];        // 0 coordinate, 1 diagonal, 2 polyfold
uniform float kifs_poly_k[MAX_SHAPES];
uniform float kifs_twist[MAX_SHAPES];     // degrees per iteration, in xy
uniform float kifs_offset_0[MAX_SHAPES];
uniform float kifs_offset_1[MAX_SHAPES];
uniform float kifs_offset_2[MAX_SHAPES];
uniform float kifs_offset_3[MAX_SHAPES];
uniform float kifs_rot1_xy[MAX_SHAPES];
uniform float kifs_rot1_xz[MAX_SHAPES];
uniform float kifs_rot1_xw[MAX_SHAPES];
uniform float kifs_rot1_yz[MAX_SHAPES];
uniform float kifs_rot1_yw[MAX_SHAPES];
uniform float kifs_rot1_zw[MAX_SHAPES];
uniform float kifs_rot2_xy[MAX_SHAPES];
uniform float kifs_rot2_xz[MAX_SHAPES];
uniform float kifs_rot2_xw[MAX_SHAPES];
uniform float kifs_rot2_yz[MAX_SHAPES];
uniform float kifs_rot2_yw[MAX_SHAPES];
uniform float kifs_rot2_zw[MAX_SHAPES];

vec4 kifs_rot1(int s, vec4 p) {
	p = mb_rot_plane(p, 0, 1, kifs_rot1_xy[s]);
	p = mb_rot_plane(p, 0, 2, kifs_rot1_xz[s]);
	p = mb_rot_plane(p, 0, 3, kifs_rot1_xw[s]);
	p = mb_rot_plane(p, 1, 2, kifs_rot1_yz[s]);
	p = mb_rot_plane(p, 1, 3, kifs_rot1_yw[s]);
	p = mb_rot_plane(p, 2, 3, kifs_rot1_zw[s]);
	return p;
}

vec4 kifs_rot2(int s, vec4 p) {
	p = mb_rot_plane(p, 0, 1, kifs_rot2_xy[s]);
	p = mb_rot_plane(p, 0, 2, kifs_rot2_xz[s]);
	p = mb_rot_plane(p, 0, 3, kifs_rot2_xw[s]);
	p = mb_rot_plane(p, 1, 2, kifs_rot2_yz[s]);
	p = mb_rot_plane(p, 1, 3, kifs_rot2_yw[s]);
	p = mb_rot_plane(p, 2, 3, kifs_rot2_zw[s]);
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
vec4 kifs_poly_fold(int s, vec4 p) {
	float sector = 6.283185307179586 / float(max(int(floor(kifs_poly_k[s] + 0.5)), 2));
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

float kifs_de(int s, vec4 p, int iters) {
	float sc = kifs_scale[s];
	vec4 o = vec4(kifs_offset_0[s], kifs_offset_1[s], kifs_offset_2[s], kifs_offset_3[s]);
	int fold = kifs_fold[s];
	float twist = kifs_twist[s];
	bool rot1 = (abs(kifs_rot1_xy[s]) + abs(kifs_rot1_xz[s]) + abs(kifs_rot1_xw[s])
		+ abs(kifs_rot1_yz[s]) + abs(kifs_rot1_yw[s]) + abs(kifs_rot1_zw[s])) > 1e-6;
	bool rot2 = (abs(kifs_rot2_xy[s]) + abs(kifs_rot2_xz[s]) + abs(kifs_rot2_xw[s])
		+ abs(kifs_rot2_yz[s]) + abs(kifs_rot2_yw[s]) + abs(kifs_rot2_zw[s])) > 1e-6;
	int n = 0;
	for (int i = 0; i < 32; i++) {
		if (i >= iters) { break; }
		if (rot1) { p = kifs_rot1(s, p); }
		if (fold == 1) {
			p = kifs_diagonal_fold(p);
		} else {
			if (fold == 2) { p = kifs_poly_fold(s, p); }
			p = menger_fold(p);
		}
		if (rot2) { p = kifs_rot2(s, p); }
		if (twist != 0.0) { p = mb_rot_plane(p, 0, 1, twist * float(i)); }
		p = sc * p - (sc - 1.0) * o;
		if (fold == 0) {
			// The Menger correction: reflect the far z layer back.
			float t = o.z * (sc - 1.0);
			if (p.z < -0.5 * t) { p.z += t; }
		}
		n = i + 1;
		if (dot(p, p) > 1.0e6) { break; }
	}
	float d = fold == 0 ? kifs_box_distance(p) : length(p);
	return d * pow(sc, -float(n));
}
