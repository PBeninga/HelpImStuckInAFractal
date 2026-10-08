// Pseudo-Kleinian distance estimate (Knighty's, in 4D), included by
// mandelbox.gdshader. KleinianEstimator is the CPU copy and explains the
// formula. Uniform names are the catalogue ids (src/fractal/kleinian_shape.gd).

uniform float kleinian_box_0;
uniform float kleinian_box_1;
uniform float kleinian_box_2;
uniform float kleinian_box_3;
uniform float kleinian_radius;
uniform float kleinian_shift_0;
uniform float kleinian_shift_1;
uniform float kleinian_shift_2;
uniform float kleinian_shift_3;
uniform float kleinian_thickness;
uniform float kleinian_view_distance;   // read by view_limit() in the main shader

float kleinian_de(vec4 p, int iters) {
	vec4 b = vec4(kleinian_box_0, kleinian_box_1, kleinian_box_2, kleinian_box_3);
	vec4 shift = vec4(kleinian_shift_0, kleinian_shift_1, kleinian_shift_2, kleinian_shift_3);
	float k = kleinian_radius * kleinian_radius;
	float dr = 1.0;
	for (int i = 0; i < 32; i++) {
		if (i >= iters) { break; }
		vec4 before = p;
		p = clamp(p, -b, b) * 2.0 - p;
		float m = max(k / max(dot(p, p), 1e-12), 1.0);
		p = p * m + shift;
		dr *= m;
		if (p == before) { break; }
	}
	float rxy = length(p.xy);
	float t = kleinian_thickness;
	return abs(0.5 * (abs(rxy * p.z) - t) / sqrt(dot(p, p) + abs(t))) / dr;
}
