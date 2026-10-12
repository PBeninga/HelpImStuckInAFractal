// Pseudo-Kleinian distance estimate (Knighty's, in 4D), included by
// mandelbox.gdshader. KleinianEstimator is the CPU copy and explains the
// formula. Uniform names are the catalogue ids (src/fractal/kleinian_shape.gd),
// one array entry per shape.

uniform float kleinian_box_0[MAX_SHAPES];
uniform float kleinian_box_1[MAX_SHAPES];
uniform float kleinian_box_2[MAX_SHAPES];
uniform float kleinian_box_3[MAX_SHAPES];
uniform float kleinian_radius[MAX_SHAPES];
uniform float kleinian_shift_0[MAX_SHAPES];
uniform float kleinian_shift_1[MAX_SHAPES];
uniform float kleinian_shift_2[MAX_SHAPES];
uniform float kleinian_shift_3[MAX_SHAPES];
uniform float kleinian_thickness[MAX_SHAPES];
uniform float kleinian_view_distance[MAX_SHAPES];   // the CPU folds these into view_limit

// Iterations first..iters-1 of shape s's Kleinian orbit p with running scale
// dr; stops early once a step leaves the point unchanged.
void kleinian_orbit(int s, inout vec4 p, inout float dr, int first, int iters) {
	vec4 b = vec4(kleinian_box_0[s], kleinian_box_1[s], kleinian_box_2[s], kleinian_box_3[s]);
	vec4 shift = vec4(kleinian_shift_0[s], kleinian_shift_1[s], kleinian_shift_2[s], kleinian_shift_3[s]);
	float k = kleinian_radius[s] * kleinian_radius[s];
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		vec4 before = p;
		p = clamp(p, -b, b) * 2.0 - p;
		float m = max(k / max(dot(p, p), 1e-12), 1.0);
		p = p * m + shift;
		dr *= m;
		if (p == before) { break; }
	}
}

float kleinian_distance(int s, vec4 p, float dr) {
	float rxy = length(p.xy);
	float t = kleinian_thickness[s];
	return abs(0.5 * (abs(rxy * p.z) - t) / sqrt(dot(p, p) + abs(t))) / dr;
}

float kleinian_de(int s, vec4 p, int iters) {
	float dr = 1.0;
	kleinian_orbit(s, p, dr, 0, iters);
	return kleinian_distance(s, p, dr);
}
