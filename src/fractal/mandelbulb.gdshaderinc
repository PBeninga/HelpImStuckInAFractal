// Mandelbulb distance estimate (White and Nylander's triplex power), included
// by mandelbox.gdshader. MandelbulbEstimator is the CPU copy and explains the
// formula. 3D: w is not read. Uniform names are the catalogue ids
// (src/fractal/mandelbulb_shape.gd), one array entry per shape.

uniform float mandelbulb_power[MAX_SHAPES];
// Renderer-owned; changes the orbit threshold, not the shape's spatial bound.
uniform float mandelbulb_bailout_margin = 1.0;
uniform float mandelbulb_phase_theta[MAX_SHAPES];   // degrees
uniform float mandelbulb_phase_phi[MAX_SHAPES];     // degrees
uniform int mandelbulb_julia[MAX_SHAPES];           // 0 off, 1 on
uniform float mandelbulb_c_0[MAX_SHAPES];
uniform float mandelbulb_c_1[MAX_SHAPES];
uniform float mandelbulb_c_2[MAX_SHAPES];

// The radius past which every orbit escapes, at least 2
// (MandelbulbEstimator.bailout).
float mandelbulb_bailout(int s) {
	float n = mandelbulb_power[s];
	float r = n <= 1.0 ? 20.0 : min(pow(2.0, 1.0 / (n - 1.0)), 20.0);
	if (mandelbulb_julia[s] != 0) {
		r = max(r, length(vec3(mandelbulb_c_0[s], mandelbulb_c_1[s], mandelbulb_c_2[s])));
	}
	return max(2.0, r);
}

float mandelbulb_de(int s, vec3 p, int iters) {
	float n = mandelbulb_power[s];
	bool julia = mandelbulb_julia[s] != 0;
	vec3 c = julia ? vec3(mandelbulb_c_0[s], mandelbulb_c_1[s], mandelbulb_c_2[s]) : p;
	float add = julia ? 0.0 : 1.0;
	float a = radians(mandelbulb_phase_theta[s]);
	float b = radians(mandelbulb_phase_phi[s]);
	float bail = mandelbulb_bailout(s) * mandelbulb_bailout_margin;
	float escape_inverse = mandelbulb_bailout_margin > 1.0 ? 1.0 / (bail + length(c)) : 0.0;
	vec3 z = p;
	float dr = 1.0;
	float r = length(z);
	for (int i = 0; i < 32; i++) {
		if (i >= iters || r > bail) { break; }
		float theta = acos(clamp(z.z / max(r, 1e-30), -1.0, 1.0)) * n + a;
		// atan(0, 0) is undefined in GLSL; the CPU's atan2 gives 0 there.
		float phi = (z.x == 0.0 && z.y == 0.0) ? 0.0 : atan(z.y, z.x);
		phi = phi * n + b;
		float st = sin(theta);
		vec3 direction = vec3(st * cos(phi), st * sin(phi), cos(theta));
		if (mandelbulb_bailout_margin > 1.0 && r > 1.0) {
			float inv_rn = pow(r, -n);
			if (inv_rn < escape_inverse) {
				// r^n - |c| > bail: this step must escape. Evaluate its
				// SAME final DE with r^n cancelled, so large margins/powers
				// cannot overflow the last point, length or derivative.
				float q = length(direction + c * inv_rn);
				return 0.5 * (n * log(r) + log(q)) * q / ((n / r) * dr + add * inv_rn);
			}
		}
		dr = n * pow(r, n - 1.0) * dr + add;
		z = pow(r, n) * direction + c;
		r = length(z);
	}
	r = max(r, 1e-30);
	return 0.5 * log(r) * r / dr;
}
