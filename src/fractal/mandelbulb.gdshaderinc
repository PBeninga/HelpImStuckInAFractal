// Mandelbulb distance estimate (White and Nylander's triplex power), included
// by mandelbox.gdshader. MandelbulbEstimator is the CPU copy and explains the
// formula. 3D: w is not read. Uniform names are the catalogue ids
// (src/fractal/mandelbulb_shape.gd).

uniform float mandelbulb_power;
uniform float mandelbulb_phase_theta;   // degrees
uniform float mandelbulb_phase_phi;     // degrees
uniform bool mandelbulb_julia;
uniform float mandelbulb_c_0;
uniform float mandelbulb_c_1;
uniform float mandelbulb_c_2;

// The radius past which every orbit escapes, at least 2
// (MandelbulbEstimator.bailout).
float mandelbulb_bailout() {
	float n = mandelbulb_power;
	float r = n <= 1.0 ? 20.0 : min(pow(2.0, 1.0 / (n - 1.0)), 20.0);
	if (mandelbulb_julia) {
		r = max(r, length(vec3(mandelbulb_c_0, mandelbulb_c_1, mandelbulb_c_2)));
	}
	return max(2.0, r);
}

float mandelbulb_de(vec3 p, int iters) {
	float n = mandelbulb_power;
	vec3 c = mandelbulb_julia ? vec3(mandelbulb_c_0, mandelbulb_c_1, mandelbulb_c_2) : p;
	float add = mandelbulb_julia ? 0.0 : 1.0;
	float a = radians(mandelbulb_phase_theta);
	float b = radians(mandelbulb_phase_phi);
	float bail = mandelbulb_bailout();
	vec3 z = p;
	float dr = 1.0;
	float r = length(z);
	for (int i = 0; i < 32; i++) {
		if (i >= iters || r > bail) { break; }
		dr = n * pow(r, n - 1.0) * dr + add;
		float theta = acos(clamp(z.z / max(r, 1e-30), -1.0, 1.0)) * n + a;
		// atan(0, 0) is undefined in GLSL; the CPU's atan2 gives 0 there.
		float phi = (z.x == 0.0 && z.y == 0.0) ? 0.0 : atan(z.y, z.x);
		phi = phi * n + b;
		float st = sin(theta);
		z = pow(r, n) * vec3(st * cos(phi), st * sin(phi), cos(theta)) + c;
		r = length(z);
	}
	r = max(r, 1e-30);
	return 0.5 * log(r) * r / dr;
}
