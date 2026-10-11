shader_type canvas_item;
// Mandelbox raymarcher. Written from the design spec's algorithm; nothing is
// copied from icefractal.com. All float math is highp (WebGL 2 => float32),
// which is Godot's canvas_item default.
//
// One Mandelbox iteration (mb_step) runs for both de() and field(): box fold,
// sphere fold, optional per-iteration 4D rotation, scale and add. Each shape
// uniform is named exactly as its catalogue id (src/fractal/mandelbox_shape.gd),
// so the uniform set equals MandelboxShape.catalogue_ids() plus the renderer's
// own camera uniforms.

uniform vec3 eye;
uniform vec3 cam_right;
uniform vec3 cam_up;
uniform vec3 cam_forward;
uniform float tan_half_fov;
uniform float aspect;
uniform float box_half;
// Level of detail with distance (see hit_eps) and the step budget.
uniform float detail_range;
uniform float detail_falloff;
uniform float near_dist;
uniform int coarse_steps;
uniform int fine_steps;
// The load shedder's distance fog: rays stop at fog_dist x near_dist and fade
// into fog_color on the way there. fog_dist 0 is no fog.
uniform float fog_dist;
uniform vec3 fog_color;

// --- shape uniforms (names == catalogue ids) ---
uniform float box_scale;
uniform float fold_limit;
uniform float min_radius;
uniform float fixed_radius;
uniform int fold_order;       // 0 box -> sphere, 1 sphere -> box
uniform float w;              // the sample point's fourth coordinate

uniform bool julia_all;
uniform bool julia_0;
uniform bool julia_1;
uniform bool julia_2;
uniform bool julia_3;
uniform float c_0;
uniform float c_1;
uniform float c_2;
uniform float c_3;

uniform float iter_rot_xy;
uniform float iter_rot_xz;
uniform float iter_rot_xw;
uniform float iter_rot_yz;
uniform float iter_rot_yw;
uniform float iter_rot_zw;

uniform int color_mode;
uniform float precision;

// NOISE:BEGIN
float noise_displace(vec3 p) { return 0.0; }
float noise_step_scale() { return 1.0; }
vec3 noise_tint(vec3 col, vec3 p) { return col; }
// NOISE:END

// The hit threshold at ray distance t: the pixel cone precision * t (detail is
// folded into `precision` on the CPU, so the defaults are bit-for-bit the plain
// cone), coarsened by (t / start)^falloff past start = detail_range x the
// camera's distance to the nearest surface. Mirrors FractalParams.hit_epsilon.
float hit_eps(float t) {
	float e = precision * t;
	float start = detail_range * near_dist;
	if (detail_falloff > 0.0 && t > start) {
		e *= pow(t / start, detail_falloff);
	}
	return e;
}

// How far into the fog a point at ray distance t is: 0 clear, 1 fully fogged.
float fog_amount(float t) {
	if (fog_dist <= 0.0) { return 0.0; }
	float t_fog = fog_dist * near_dist;
	return smoothstep(0.35 * t_fog, t_fog, t);
}

// Reflect every component that leaves [-L, L] back inside.
vec4 mb_box_fold(vec4 p) {
	return clamp(p, -fold_limit, fold_limit) * 2.0 - p;
}

// Inflate the inner sphere, invert the shell between the two radii, and carry
// the same factor into the running derivative.
void mb_sphere_fold(inout vec4 p, inout float dr) {
	float r2 = dot(p, p);
	float mr2 = max(min_radius * min_radius, 1e-12);
	float fr2 = max(fixed_radius * fixed_radius, 1e-12);
	if (r2 < mr2) {
		float f = fr2 / mr2;
		p *= f;
		dr *= f;
	} else if (r2 < fr2) {
		float f = fr2 / max(r2, 1e-12);
		p *= f;
		dr *= f;
	}
}

vec4 mb_axis(int i) {
	if (i == 0) return vec4(1.0, 0.0, 0.0, 0.0);
	if (i == 1) return vec4(0.0, 1.0, 0.0, 0.0);
	if (i == 2) return vec4(0.0, 0.0, 1.0, 0.0);
	return vec4(0.0, 0.0, 0.0, 1.0);
}

// Rotate p in the (a, b) plane by `deg` degrees:
//   a' = a cos - b sin,  b' = a sin + b cos.
vec4 mb_rot_plane(vec4 p, int a, int b, float deg) {
	float r = radians(deg);
	float c = cos(r);
	float s = sin(r);
	vec4 ea = mb_axis(a);
	vec4 eb = mb_axis(b);
	float pa = dot(p, ea);
	float pb = dot(p, eb);
	return p - pa * ea - pb * eb + (pa * c - pb * s) * ea + (pa * s + pb * c) * eb;
}

// The six per-iteration angles, fixed order xy, xz, xw, yz, yw, zw.
vec4 mb_iter_rotate(vec4 p) {
	p = mb_rot_plane(p, 0, 1, iter_rot_xy);
	p = mb_rot_plane(p, 0, 2, iter_rot_xz);
	p = mb_rot_plane(p, 0, 3, iter_rot_xw);
	p = mb_rot_plane(p, 1, 2, iter_rot_yz);
	p = mb_rot_plane(p, 1, 3, iter_rot_yw);
	p = mb_rot_plane(p, 2, 3, iter_rot_zw);
	return p;
}

bool mb_rotating() {
	return (abs(iter_rot_xy) + abs(iter_rot_xz) + abs(iter_rot_xw)
		+ abs(iter_rot_yz) + abs(iter_rot_yw) + abs(iter_rot_zw)) > 1e-6;
}

// One Mandelbox iteration on the 4D orbit point z with running derivative dz.
void mb_step(inout vec4 z, inout float dz, vec4 c, bool rotating) {
	if (fold_order == 0) { z = mb_box_fold(z); mb_sphere_fold(z, dz); }
	else                 { mb_sphere_fold(z, dz); z = mb_box_fold(z); }
	if (rotating) { z = mb_iter_rotate(z); }
	z = box_scale * z + c;
	dz = dz * abs(box_scale) + 1.0;
}

// Per component: the Julia constant where it is checked, the point's own
// coordinate where it is not.
vec4 mb_constant(vec4 z0) {
	return vec4(
		(julia_all || julia_0) ? c_0 : z0.x,
		(julia_all || julia_1) ? c_1 : z0.y,
		(julia_all || julia_2) ? c_2 : z0.z,
		(julia_all || julia_3) ? c_3 : z0.w);
}

// Mandelbox distance estimate, up to `iters` iterations (<= 32).
float de(vec3 p, int iters) {
	vec4 z0 = vec4(p, w);
	vec4 c = mb_constant(z0);
	vec4 z = z0;
	float dz = 1.0;
	bool rotating = mb_rotating();
	for (int i = 0; i < 32; i++) {
		if (i >= iters) { break; }
		mb_step(z, dz, c, rotating);
	}
	return length(z) / abs(dz) + noise_displace(p);
}

// The "Ice Fractal" field: a 16-iteration Mandelbox orbit from z=0, c=(q, w),
// no derivative, offset by -8. Not a true distance; its gradient gives the look.
float field(vec3 q) {
	vec4 z = vec4(0.0);
	vec4 c = vec4(q, w);
	float dz = 1.0;
	bool rotating = mb_rotating();
	for (int i = 0; i < 16; i++) {
		mb_step(z, dz, c, rotating);
	}
	return length(z) - 8.0 + noise_displace(q);
}

// Central-difference normal from the high-precision estimator.
vec3 calc_normal(vec3 v, float delta) {
	vec2 e = vec2(delta, 0.0);
	return normalize(vec3(
		de(v + e.xyy, 32) - de(v - e.xyy, 32),
		de(v + e.yxy, 32) - de(v - e.yxy, 32),
		de(v + e.yyx, 32) - de(v - e.yyx, 32)));
}

// The Ice Fractal normal: field at the half-scale base point h = v/2, offset
// samples at the full-scale point + 0.01. Not a true gradient, by design.
vec3 calc_nf(vec3 v, vec3 h) {
	float lw = field(h);
	vec3 g = vec3(
		field(v + vec3(0.01, 0.0, 0.0)) - lw,
		field(v + vec3(0.0, 0.01, 0.0)) - lw,
		field(v + vec3(0.0, 0.0, 0.01)) - lw) / 0.01;
	return normalize(g);
}

// Six-segment rainbow ramp: red->yellow->green->cyan->blue->magenta->red.
vec3 hue(float q) {
	q = clamp(q, 0.0, 0.999999);
	float h6 = q * 6.0;
	float x = 1.0 - abs(mod(h6, 2.0) - 1.0);
	if (h6 < 1.0) { return vec3(1.0, x, 0.0); }
	else if (h6 < 2.0) { return vec3(x, 1.0, 0.0); }
	else if (h6 < 3.0) { return vec3(0.0, 1.0, x); }
	else if (h6 < 4.0) { return vec3(0.0, x, 1.0); }
	else if (h6 < 5.0) { return vec3(x, 0.0, 1.0); }
	return vec3(1.0, 0.0, x);
}

// Ray vs axis-aligned cube of half-size `half_size`, centred at the origin.
// Returns vec2(t_enter, t_exit); a miss has t_exit < max(t_enter, 0).
vec2 box_intersect(vec3 ro, vec3 rd, float half_size) {
	// Guard against exactly axis-aligned rays: floor each |component| at 1e-9
	// (keeping its sign), so 1.0/rd never produces an infinity or NaN.
	vec3 sgn = vec3(rd.x >= 0.0 ? 1.0 : -1.0, rd.y >= 0.0 ? 1.0 : -1.0, rd.z >= 0.0 ? 1.0 : -1.0);
	vec3 safe_rd = sgn * max(abs(rd), vec3(1e-9));
	vec3 inv = 1.0 / safe_rd;
	vec3 n = inv * ro;
	vec3 k = abs(inv) * half_size;
	vec3 t1 = -n - k;
	vec3 t2 = -n + k;
	float t_enter = max(max(t1.x, t1.y), t1.z);
	float t_exit = min(min(t2.x, t2.y), t2.z);
	return vec2(t_enter, t_exit);
}

void fragment() {
	vec2 ndc = (UV - 0.5) * 2.0;
	ndc.y = -ndc.y;  // +y up
	vec3 dir = normalize(cam_forward
		+ ndc.x * aspect * tan_half_fov * cam_right
		+ ndc.y * tan_half_fov * cam_up);

	vec3 bg = (color_mode == 5 || color_mode == 6) ? vec3(1.0) : vec3(0.0);
	// A miss is infinitely far, so under fog the sky is the fog: far surfaces fade
	// into it without a seam.
	if (fog_dist > 0.0) { bg = fog_color; }

	vec2 tb = box_intersect(eye, dir, box_half);
	if (tb.y < max(tb.x, 0.0)) {
		COLOR = vec4(bg, 1.0);
	} else {
		float t_exit = tb.y;
		if (fog_dist > 0.0) {
			t_exit = min(t_exit, fog_dist * near_dist);  // nothing past the fog is marched
		}
		float total = max(tb.x, 0.0);
		bool left_cube = total > t_exit;

		// Phase 1: low precision (N=16), up to coarse_steps (<= 384) steps.
		int n1 = coarse_steps;
		for (int i = 0; i < 384; i++) {
			if (left_cube || i >= coarse_steps) { break; }
			vec3 pos = eye + dir * total;
			float d = de(pos, 16);
			if (d < hit_eps(total) * 2.0) { n1 = i; break; }
			total += d * noise_step_scale();
			if (total > t_exit) { left_cube = true; break; }
		}

		// Phase 2: high precision (N=32), up to fine_steps (<= 128) steps,
		// continuing on.
		int n2 = fine_steps;
		if (!left_cube) {
			for (int i = 0; i < 128; i++) {
				if (i >= fine_steps) { break; }
				vec3 pos = eye + dir * total;
				float d = de(pos, 32);
				if (d < hit_eps(total)) { n2 = i; break; }
				total += d * noise_step_scale();
				if (total > t_exit) { left_cube = true; break; }
			}
		}

		if (left_cube) {
			COLOR = vec4(bg, 1.0);  // the only misses: leaving the cube, or reaching the fog
		} else {
			// Step-count shading stays on the original 128-step scale whatever the
			// budget, so a ray that hits looks the same; one that ran out is 1.
			float ce = n2 == fine_steps ? 1.0 : min(float(n1 + n2) / 128.0, 1.0);
			float inv = 1.0 - ce;
			if (color_mode == 0) {
				COLOR = vec4(mix(vec3(inv), fog_color, fog_amount(total)), 1.0);  // Grayscale needs no normal: stay cheap
			} else {
				vec3 v = eye + dir * total;
			vec3 h = v * 0.5;
			vec3 eh = eye * 0.5;
			float delta = hit_eps(total) * 40.0;

			// Normal: NF for modes 1..9 outside Julia mode, N otherwise.
			vec3 n;
			if (color_mode >= 1 && color_mode <= 9 && !julia_all) {
				n = calc_nf(v, h);
			} else {
				n = calc_normal(v, delta);
			}

			vec3 ldir = normalize(2.0 * eh - h);
			float lgt = abs(dot(n, ldir));
			lgt = 0.5 * lgt + pow(lgt, 160.0) + 0.1;
			vec3 base = vec3(lgt) * (-n * 0.25 + 0.75) + vec3(0.0, 0.0, 0.2);

				vec3 col;
				if (color_mode == 1) {
				col = base * vec3(inv + 0.5, 2.0 * inv * inv + 0.5, 5.0 * pow(inv, 4.0) + 0.5);
			} else if (color_mode == 2) {
				col = base * vec3(max(lgt * ce, inv), max(ce, inv), max(0.5 * lgt * ce, inv));
			} else if (color_mode == 3) {
				float q = dot(h, h) / 4.0;
				col = hue(q) * ce + 0.5 * lgt;
			} else if (color_mode == 4) {
				float q = dot(h, h) / 4.0;
				col = hue(q) * inv;
			} else if (color_mode == 8) {
				float q = n.z * 0.5 + 0.5 - 0.1;
				col = hue(q) * inv;
			} else if (color_mode == 5) {
				float avg = (base.r + base.g + base.b) / 3.0;
				col = base * vec3(lgt * max(lgt * ce, inv), lgt + avg, inv + lgt);
			} else if (color_mode == 6) {
				float avg = (base.r + base.g + base.b) / 3.0;
				col = base * vec3(lgt * max(lgt * ce, inv), lgt + avg, inv + lgt) + vec3(ce * ce);
			} else if (color_mode == 7) {
				float avg = (base.r + base.g + base.b) / 3.0;
				col = vec3(1.0 - 2.0 * ce * (lgt + 0.5), avg * inv, inv * (lgt + 0.5));
			} else if (color_mode == 9) {
				col = vec3(inv * inv, 1.0 - 1.9 * ce * ce, 1.17 - ce * ce);
			} else if (color_mode == 16) {
				col = clamp(vec3(inv * inv, 1.0 - 1.9 * ce * ce, 1.17 - ce * ce), 0.0, 1.0) * (lgt + 0.5);
			} else if (color_mode == 15) {
				vec3 nv = vec3(dot(n, cam_right), dot(n, cam_up), dot(n, -cam_forward));
				float lv = pow(max(0.0, nv.z), 4.0);
				vec3 n2v = normalize(nv + vec3(0.5, 0.5, 0.0));
				col = (n2v + 1.0) * 0.5 * (lv - 2.0 * ce + 0.5);
			} else if (color_mode == 14) {
				vec3 nv = vec3(dot(n, cam_right), dot(n, cam_up), dot(n, -cam_forward));
				float lv = pow(max(0.0, nv.z), 4.0);
				col = (0.75 - ce) * 2.0 * vec3(lv, lv * lv, lv * ce);
			} else {
				col = vec3(inv);
			}
				COLOR = vec4(mix(noise_tint(col, v), fog_color, fog_amount(total)), 1.0);
			}
		}
	}
}
