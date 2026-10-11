shader_type canvas_item;
// The fractal raymarcher: the Mandelbox (written from the design spec's
// algorithm; nothing is copied from icefractal.com), and through `shape` the
// KIFS, Kleinian and Mandelbulb of kifs.gdshaderinc, kleinian.gdshaderinc and
// mandelbulb.gdshaderinc. All float
// math is highp (WebGL 2 => float32), which is Godot's canvas_item default.
//
// One Mandelbox iteration (mb_step) runs for both de() and field(): the fold
// (box, cylinder or octahedral, or the box-to-abs hybrid fold),
// sphere fold, optional per-iteration 4D rotation, scale (drifting with the
// iteration) and add. Each shape uniform is named exactly as its catalogue id
// (src/fractal/shape_catalogue.gd), so the uniform set equals
// ShapeCatalogue.catalogue_ids() plus the renderer's own camera uniforms.
// Past the 32-bit floor the march runs perturbed (perturbation.gdshaderinc); with
// pert_iters 0 every path is exactly the direct one.

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
// The coarse pass's iteration count, 16..32: more as the camera nears the
// surface, so the smoother surface it marches toward stays within its hit
// threshold of the real one (FractalParams.coarse_iters). 16 at the default view.
uniform int coarse_iters;
// The self-shadow march's step budget (0 = no shadow ray). The view pushes it
// from FractalParams.SHADOW_STEPS through the load-shed ladder, so it has no
// default here: an unpushed frame casts no shadow, like the site.
uniform int shadow_steps;
// How much of the Ice Fractal normal (calc_nf) the probe-lit colour modes use:
// 1 far from the surface, fading to 0 (the true normal) up close, where
// calc_nf's fixed 0.01 offset turns to noise (FractalParams.nf_weight).
uniform float nf_weight;
// The load shedder's distance fog: rays stop at fog_dist x near_dist and fade
// into fog_color on the way there. fog_dist 0 is no fog. fog_clear (0..1) is
// how far a fog on its way out has thinned: above 0 the march is no longer cut
// at the fog, so the far geometry fades in through it rather than popping.
uniform float fog_dist;
uniform vec3 fog_color;
uniform float fog_clear;
// The centre-ray probe: a dot painted on the surface where the ray through the
// middle of the screen hits (CenterRay, marched on the CPU). Off when the probe
// is hidden or the ray misses.
uniform bool probe_on;
uniform vec3 probe_point;
uniform float probe_radius;

// --- shape uniforms (names == catalogue ids) ---
uniform int shape;            // 0 Mandelbox, 1 KIFS, 2 Kleinian, 3 Mandelbulb
uniform float box_scale;
uniform float fold_limit;
uniform float min_radius;
uniform float fixed_radius;
uniform int fold_order;       // 0 box -> sphere, 1 sphere -> box
uniform int fold_shape;       // 0 box, 1 cylinder, 2 octahedral
uniform float hybrid_mix;     // 0 off; box fold -> abs fold on hybrid iterations
uniform int hybrid_every;     // the hybrid iterations: i % every == every - 1
uniform float scale_drift;    // iteration i scales by box_scale + scale_drift * i
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

uniform float precision;

uniform int color_mode;
uniform int palette_source = 0;   // 0 steps, 1 radius, 2 normal
uniform float palette_frequency = 1.0;
uniform float palette_offset = 0.0;
uniform float palette_occlusion = 0.5;

// Light. The defaults are the site's constants, so the picture is unchanged
// until one is moved. light_color and surface_color are the two COLOR rows,
// pushed from Color as a vec3 (FractalParams.COLOR_KEYS).
uniform vec3 light_color = vec3(1.0, 1.0, 1.0);
uniform float light_yaw = 0.0;      // degrees about cam_up
uniform float light_pitch = 0.0;    // degrees about cam_right
uniform float light_size = 0.0;     // the lamp's angular radius, degrees
uniform float light_ambient = 0.1;
uniform float light_diffuse = 0.5;
uniform float shadows = 0.0;        // 0 off (no shadow ray), toward 1 darker
// Scattering: light-tinted distance haze, off at density 0.
uniform float scatter_density = 0.0;
uniform float scatter_glow = 0.0;
uniform float scatter_brightness = 1.0;
uniform float exposure = 1.0;
uniform float saturation = 1.0;
// Surface. roughness 0.111111111111 (1/9) is the site's specular exponent of 160.
uniform vec3 surface_color = vec3(1.0, 1.0, 1.0);
uniform float roughness = 0.111111111111;
uniform float light_specular = 1.0;
// Texture: the noise editor's Texture and Bump outputs scale by these.
uniform float texture_strength = 1.0;
uniform float bump_strength = 1.0;

// The Palette mode's cosine palette A + B cos(2pi (C t + D)), one float per
// vector and channel so each is a catalogue id of its own.
uniform float palette_a_r = 0.5;
uniform float palette_a_g = 0.5;
uniform float palette_a_b = 0.5;
uniform float palette_b_r = 0.5;
uniform float palette_b_g = 0.5;
uniform float palette_b_b = 0.5;
uniform float palette_c_r = 1.0;
uniform float palette_c_g = 1.0;
uniform float palette_c_b = 1.0;
uniform float palette_d_r = 0.0;
uniform float palette_d_g = 0.33;
uniform float palette_d_b = 0.67;

// NOISE:BEGIN
float noise_displace(vec3 p) { return 0.0; }
float noise_step_scale() { return 1.0; }
vec3 noise_tint(vec3 col, vec3 p) { return col; }
vec3 noise_texture(vec3 p) { return vec3(1.0); }
float noise_bump(vec3 p) { return 0.0; }
const bool noise_texture_on = false;
const bool noise_bump_on = false;
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
	return (1.0 - fog_clear) * smoothstep(0.35 * t_fog, t_fog, t);
}

// The probe dot over a surface colour at hit point v: a white disc of radius
// probe_radius around probe_point with a thin dark rim, so it reads on bright
// surfaces too. Measured in world space, it lies on the geometry and stretches
// across a slanted surface.
vec3 probe_dot(vec3 col, vec3 v) {
	if (!probe_on) { return col; }
	float r = length(v - probe_point) / probe_radius;
	if (r >= 1.0) { return col; }
	float rim = smoothstep(0.55, 0.7, r) * (1.0 - smoothstep(0.85, 1.0, r));
	vec3 dot_col = mix(vec3(1.0), vec3(0.0), rim);
	return mix(dot_col, col, smoothstep(0.85, 1.0, r));
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

// Reflect the xy pair through the circle of radius L (r -> 2L - r outside it);
// z and w get the plain box fold.
vec4 mb_cylinder_fold(vec4 p) {
	float r = length(p.xy);
	if (r > fold_limit) { p.xy *= (2.0 * fold_limit - r) / r; }
	p.zw = clamp(p.zw, -fold_limit, fold_limit) * 2.0 - p.zw;
	return p;
}

// Reflect xyz through the octahedron |x| + |y| + |z| <= L: twice its nearest
// point minus the point (the box fold is the same rule for the cube). The
// nearest point soft-thresholds every |component| by the theta that lands it on
// the surface. w gets the plain box fold.
vec4 mb_octahedral_fold(vec4 p) {
	float lim = max(fold_limit, 0.0);
	vec3 a = abs(p.xyz);
	float sum = a.x + a.y + a.z;
	if (sum > lim) {
		float u1 = max(a.x, max(a.y, a.z));
		float u3 = min(a.x, min(a.y, a.z));
		float u2 = sum - u1 - u3;
		float theta = u1 - lim;
		float t2 = (u1 + u2 - lim) / 2.0;
		if (u2 > t2) {
			theta = t2;
			float t3 = (sum - lim) / 3.0;
			if (u3 > t3) { theta = t3; }
		}
		p.xyz = 2.0 * sign(p.xyz) * max(a - theta, 0.0) - p.xyz;
	}
	p.w = clamp(p.w, -fold_limit, fold_limit) * 2.0 - p.w;
	return p;
}

// KIFS's coordinate fold: into the positive orthant, then sort x >= y >= z.
vec4 menger_fold(vec4 p) {
	p = abs(p);
	if (p.x < p.y) { p.xy = p.yx; }
	if (p.x < p.z) { p.xz = p.zx; }
	if (p.y < p.z) { p.yz = p.zy; }
	return p;
}

// The hybrid fold: reflect each component through [lo, hi], sliding from the
// box fold's [-L, L] at mix 0 to [0, infinity) at mix 1, the abs fold. (Mixing
// the two folds' results would cancel far out; see DistanceEstimator.)
vec4 mb_hybrid_fold(vec4 p) {
	float lo = -fold_limit * (1.0 - hybrid_mix);
	float hi = (fold_limit + hybrid_mix) / max(1.0 - hybrid_mix, 1e-6);
	return clamp(p, vec4(lo), vec4(hi)) * 2.0 - p;
}

// The fold step of iteration i: the chosen fold, or the hybrid fold on a
// hybrid iteration. Each reflects through a convex set's boundary, so each is
// 1-Lipschitz and the running derivative needs no factor.
vec4 mb_fold(vec4 p, int i) {
	if (hybrid_mix > 0.0) {
		int every = max(hybrid_every, 1);
		if (i % every == every - 1) { return mb_hybrid_fold(p); }
	}
	if (fold_shape == 1) { return mb_cylinder_fold(p); }
	if (fold_shape == 2) { return mb_octahedral_fold(p); }
	return mb_box_fold(p);
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

// Iteration i of the Mandelbox on the 4D orbit point z with running
// derivative dz.
void mb_step(inout vec4 z, inout float dz, vec4 c, bool rotating, int i) {
	if (fold_order == 0) { z = mb_fold(z, i); mb_sphere_fold(z, dz); }
	else                 { mb_sphere_fold(z, dz); z = mb_fold(z, i); }
	if (rotating) { z = mb_iter_rotate(z); }
	float s = box_scale + scale_drift * float(i);
	z = s * z + c;
	dz = dz * abs(s) + 1.0;
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

// Iterations first..iters-1 of the Mandelbox orbit: the direct de() runs them all
// from 0 (exactly the loop it always ran), the perturbed de_pert() from its handoff.
void mb_orbit(inout vec4 z, inout float dz, vec4 c, int first, int iters) {
	bool rotating = mb_rotating();
	for (int i = first; i < 32; i++) {
		if (i >= iters) { break; }
		mb_step(z, dz, c, rotating, i);
	}
}

#include "res://src/fractal/kifs.gdshaderinc"
#include "res://src/fractal/kleinian.gdshaderinc"
#include "res://src/fractal/mandelbulb.gdshaderinc"

// The Kleinian's rays stop at its View distance (0: no limit for the others).
float view_limit() {
	return shape == 2 ? kleinian_view_distance : 0.0;
}

// How far past the start of the view distance's horizon a hit at t is: 0 clear,
// 1 at the limit, where it has faded fully into the background.
float view_fade(float t) {
	float vd = view_limit();
	if (vd <= 0.0) { return 0.0; }
	return smoothstep(0.67 * vd, vd, t);
}

// The distance estimate for the shape being drawn, up to `iters` iterations
// (<= 32). The Mandelbox's is below; DistanceEstimator is the CPU copy.
float de(vec3 p, int iters) {
	if (shape == 1) { return kifs_de(vec4(p, w), iters) + noise_displace(p); }
	if (shape == 2) { return kleinian_de(vec4(p, w), iters) + noise_displace(p); }
	if (shape == 3) { return mandelbulb_de(p, iters) + noise_displace(p); }
	vec4 z0 = vec4(p, w);
	vec4 c = mb_constant(z0);
	vec4 z = z0;
	float dz = 1.0;
	mb_orbit(z, dz, c, 0, iters);
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
		mb_step(z, dz, c, rotating, i);
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

#include "res://src/fractal/perturbation.gdshaderinc"

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

// Inigo Quilez's cosine palette. Palette.color_at() is the same formula, so the
// Colour window's strip previews exactly this.
vec3 palette(float t) {
	vec3 a = vec3(palette_a_r, palette_a_g, palette_a_b);
	vec3 b = vec3(palette_b_r, palette_b_g, palette_b_b);
	vec3 c = vec3(palette_c_r, palette_c_g, palette_c_b);
	vec3 d = vec3(palette_d_r, palette_d_g, palette_d_b);
	return clamp(a + b * cos(6.283185307179586 * (c * t + d)), 0.0, 1.0);
}

// Rotate v by `deg` degrees about the unit axis k (Rodrigues).
vec3 rotate_about(vec3 v, vec3 k, float deg) {
	float r = radians(deg);
	float c = cos(r);
	float s = sin(r);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
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

// Henyey-Greenstein phase: how strongly haze scatters toward c = cos(angle to
// the light). g = 0 is even in all directions; g -> 1 bunches it forward.
float hg(float c, float g) {
	float gg = g * g;
	return (1.0 - gg) / pow(max(1.0 + gg - 2.0 * g * c, 1e-6), 1.5);
}

// Light-tinted distance haze for a ray that travelled t toward dir, with the
// light coming from ldir. Off when the density is 0, so the default is untouched.
vec3 scatter(vec3 col, float t, vec3 dir, vec3 ldir) {
	if (scatter_density <= 0.0) { return col; }
	float a = 1.0 - exp(-scatter_density * t / max(near_dist, 1e-6));
	float phase = hg(dot(dir, ldir), scatter_glow) / hg(1.0, scatter_glow);
	vec3 haze = light_color * scatter_brightness * phase;
	return mix(col, haze, clamp(a, 0.0, 1.0));
}

// A soft self-shadow: march from just off the surface toward the light, up to
// shadow_steps steps (<= 64), stopping at the cube's far side. A near-hit darkens
// fully; otherwise the closest approach, scaled by the lamp's angular size, is the
// penumbra. k widens the penumbra as the lamp widens (light_size); a size-0 lamp
// is near-hard. Costs one extra ray per pixel; skipped when shadow_steps is 0.
float soft_shadow(vec3 v, vec3 n, vec3 ldir, float total) {
	float eps0 = hit_eps(total);
	vec3 ro = v + n * 4.0 * eps0;
	float far = box_intersect(ro, ldir, box_half).y;
	float k = 1.0 / tan(max(radians(light_size), radians(0.5)));
	int n_coarse = clamp(coarse_iters, 16, 32);
	float res = 1.0;
	float t = eps0;
	for (int i = 0; i < 64; i++) {
		if (i >= shadow_steps) { break; }
		float d = de(ro + ldir * t, n_coarse);
		if (d < eps0) { return 0.0; }
		res = min(res, k * d / t);
		t += d * noise_step_scale();
		if (t > far) { break; }
	}
	return clamp(res, 0.0, 1.0);
}

void fragment() {
	vec2 ndc = (UV - 0.5) * 2.0;
	ndc.y = -ndc.y;  // +y up
	vec3 dir = normalize(cam_forward
		+ ndc.x * aspect * tan_half_fov * cam_right
		+ ndc.y * tan_half_fov * cam_up);

	// The headlight direction for the haze over a miss or the sky: the view ray
	// back toward the eye, swung by the light's yaw and pitch like the hit light.
	vec3 sky_ldir = -dir;
	if (light_yaw != 0.0 || light_pitch != 0.0) {
		sky_ldir = rotate_about(rotate_about(sky_ldir, cam_up, light_yaw), cam_right, light_pitch);
	}

	vec3 bg = (color_mode == 5 || color_mode == 6) ? vec3(1.0) : vec3(0.0);
	// A miss is infinitely far, so under fog the sky is the fog: far surfaces fade
	// into it without a seam.
	if (fog_dist > 0.0) { bg = mix(fog_color, bg, fog_clear); }

	vec2 tb = box_intersect(eye, dir, box_half);
	if (tb.y < max(tb.x, 0.0)) {
		COLOR = vec4(bg, 1.0);
	} else {
		float t_exit = tb.y;
		if (fog_dist > 0.0 && fog_clear <= 0.0) {
			t_exit = min(t_exit, fog_dist * near_dist);  // nothing past the fog is marched
		}
		if (view_limit() > 0.0) {
			t_exit = min(t_exit, view_limit());  // nor past the view distance
		}
		float total = max(tb.x, 0.0);
		bool left_cube = total > t_exit;

		// Phase 1: low precision (N = coarse_iters, 16 at the default view), up to
		// coarse_steps (<= 384) steps. An unpushed 0 reads as the site's 16.
		int n_coarse = clamp(coarse_iters, 16, 32);
		int n1 = coarse_steps;
		for (int i = 0; i < 384; i++) {
			if (left_cube || i >= coarse_steps) { break; }
			vec3 pos = eye + dir * total;
			float d = march_de(pos, dir * total, n_coarse);
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
				float d = march_de(pos, dir * total, 32);
				if (d < hit_eps(total)) { n2 = i; break; }
				total += d * noise_step_scale();
				if (total > t_exit) { left_cube = true; break; }
			}
		}

		if (left_cube) {
			// The only misses: leaving the cube, the fog or the view distance. The
			// haze fills the space the ray marched, to its exit (default: no haze).
			float t_scat = min(t_exit, total);
			COLOR = vec4(scatter(bg, t_scat, dir, sky_ldir), 1.0);
		} else {
			// Step-count shading stays on the original 128-step scale whatever the
			// budget, so a ray that hits looks the same; one that ran out is 1.
			float ce = n2 == fine_steps ? 1.0 : min(float(n1 + n2) / 128.0, 1.0);
			float inv = 1.0 - ce;
			if (color_mode == 0) {
				// Grayscale needs no normal: stay cheap. The haze still fills the space.
				vec3 sldir = -dir;
				if (light_yaw != 0.0 || light_pitch != 0.0) {
					sldir = rotate_about(rotate_about(sldir, cam_up, light_yaw), cam_right, light_pitch);
				}
				vec3 gcol = scatter(vec3(inv), total, dir, sldir);
				COLOR = vec4(mix(probe_dot(mix(gcol, fog_color, fog_amount(total)), eye + dir * total),
					bg, view_fade(total)), 1.0);
			} else {
				vec3 v = eye + dir * total;
			vec3 h = v * 0.5;
			vec3 eh = eye * 0.5;
			float delta = hit_eps(total) * 40.0;

			// Normal: NF for modes 1..9 on the Mandelbox outside Julia mode (the NF
			// field is the Mandelbox's own orbit), N otherwise. Up close NF
			// crossfades to N by nf_weight; each end computes only its own normal,
			// so a weight of exactly 1 (the default view) is the site's maths.
			vec3 n;
			if (shape == 0 && color_mode >= 1 && color_mode <= 9 && !julia_all) {
				if (nf_weight >= 1.0) {
					n = calc_nf(v, h);
				} else if (nf_weight <= 0.0) {
					n = true_normal(v, dir * total, delta);
				} else {
					vec3 nf = calc_nf(v, h);
					vec3 m = mix(true_normal(v, dir * total, delta), nf, nf_weight);
					// The two can point nearly opposite ways (NF is not a gradient);
					// a blend that cancels to nothing keeps NF rather than a NaN.
					n = dot(m, m) > 1e-12 ? normalize(m) : nf;
				}
			} else {
				n = true_normal(v, dir * total, delta);
			}

			// Bump: tilt the normal by the across-surface part of noise_bump's
			// gradient (a fake relief; the surface does not move). A result with
			// no length (a NaN) keeps the old normal.
			if (noise_bump_on && bump_strength != 0.0) {
				vec2 e2 = vec2(delta, 0.0);
				vec3 g = vec3(
					noise_bump(v + e2.xyy) - noise_bump(v - e2.xyy),
					noise_bump(v + e2.yxy) - noise_bump(v - e2.yxy),
					noise_bump(v + e2.yyx) - noise_bump(v - e2.yyx)) / (2.0 * delta);
				vec3 m = n - bump_strength * (g - n * dot(n, g));
				if (dot(m, m) > 1e-12) { n = normalize(m); }
			}

			vec3 ldir = normalize(2.0 * eh - h);
			bool swung = light_yaw != 0.0 || light_pitch != 0.0;
			if (swung) {
				ldir = rotate_about(rotate_about(ldir, cam_up, light_yaw), cam_right, light_pitch);
			}
			// Shadow only when the lamp is off the headlight: a headlight's shadow
			// ray retraces the view ray and would self-shadow the whole surface.
			float sh = 1.0;
			if (shadows > 0.0 && shadow_steps > 0 && swung) {
				sh = mix(1.0, soft_shadow(v, n, ldir, total), shadows);
			}
			float nl = abs(dot(n, ldir));
			// The specular exponent from roughness; the lamp's size widens the lobe.
			// r_eff^2 = roughness^2 + radians(light_size)^2, so size 0 is the site's.
			// Floored at 0 (r_eff^2 >= 1, a matte surface under a wide light): the
			// widest lobe is a flat sheen, never a negative power that blows up
			// at grazing angles (pow(0, neg) is a NaN).
			float r_eff2 = roughness * roughness + radians(light_size) * radians(light_size);
			float e = max(0.0, 2.0 / max(r_eff2, 1e-9) - 2.0);
			float lgt = sh * (light_diffuse * nl + light_specular * pow(nl, e)) + light_ambient;
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
			} else if (color_mode == 20) {
				float src = ce;
				if (palette_source == 1) { src = dot(h, h) / 4.0; }
				else if (palette_source == 2) { src = n.z * 0.5 + 0.5; }
				float pt = fract(src * palette_frequency + palette_offset);
				col = palette(pt) * (lgt + 0.5) * mix(1.0, inv, palette_occlusion);
			} else {
				col = vec3(inv);
			}
				// Texture: recolour the surface by the Texture output (white = no change).
				if (noise_texture_on) { col *= mix(vec3(1.0), noise_texture(v), texture_strength); }
				// Surface and light colour, each guarded so white stays bit-for-bit.
				if (surface_color != vec3(1.0)) { col *= surface_color; }
				if (light_color != vec3(1.0)) { col *= light_color; }
				// Each guarded, so at the defaults the site's modes stay bit-for-bit.
				if (exposure != 1.0) { col *= exposure; }
				if (saturation != 1.0) {
					float luma = dot(col, vec3(0.299, 0.587, 0.114));
					col = mix(vec3(luma), col, saturation);
				}
				vec3 shaded = noise_tint(col, v);
				shaded = scatter(shaded, total, dir, ldir);
				shaded = mix(shaded, fog_color, fog_amount(total));
				COLOR = vec4(mix(probe_dot(shaded, v), bg, view_fade(total)), 1.0);
			}
		}
	}
}
