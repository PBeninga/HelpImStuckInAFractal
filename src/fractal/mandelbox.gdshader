shader_type canvas_item;
// The fractal raymarcher for a SCENE of up to MAX_SHAPES shapes: each a
// Mandelbox (written from the design spec's algorithm; nothing is copied from
// icefractal.com) or, through its `shape` entry, the KIFS, Kleinian or
// Mandelbulb of kifs.gdshaderinc, kleinian.gdshaderinc and
// mandelbulb.gdshaderinc. All float math is highp (WebGL 2 => float32), which
// is Godot's canvas_item default.
//
// Every per-shape knob is a uniform ARRAY named exactly as its catalogue id
// (src/fractal/shape_catalogue.gd), indexed by shape, so the uniform set equals
// ShapeCatalogue.shader_ids() plus the scene's look uniforms (scene_ids(),
// scalars) plus the renderer's own. One Mandelbox iteration (mb_step) runs for
// both de() and field(): the fold (box, cylinder or octahedral, or the
// box-to-abs hybrid fold), sphere fold, optional per-iteration 4D rotation,
// scale (drifting with the iteration) and add.
//
// Each shape is evaluated in its OWN frame. The CPU (FractalView._push_frames,
// in 64-bit) hands the shader the eye already mapped into every frame
// (local_eye) and the frame's axes in world space (frame_x/y/z); a point at a
// world offset `off` from the eye is then local_eye + Rᵀoff / size, so the
// numbers a fold sees are O(1) whatever the shape's size or distance from the
// origin. Forming eye + dir · t in world space and subtracting the shape's
// position here would lose a nested shape to float32 cancellation.
//
const int MAX_SHAPES = 8;

uniform vec3 eye;             // world; probe dot and the exit sphere
// Finite background sphere at the world origin. A future sky picker can set
// GameplaySettings.exit_skybox; longitude wraps, latitude runs pole to pole.
uniform float exit_radius = 20.0;
uniform bool exit_has_skybox = false;
uniform sampler2D exit_skybox : source_color, filter_linear, repeat_enable;
uniform vec3 cam_right;
uniform vec3 cam_up;
uniform vec3 cam_forward;
uniform float tan_half_fov;
uniform float aspect;
// Level of detail with distance (see hit_eps) and the step budget.
uniform float detail_range;
uniform float detail_falloff;
uniform float near_dist;
uniform int coarse_steps;
uniform int fine_steps;
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
// How far from the eye a ray may go before it stops, world units, 0 for no
// limit: the smallest View distance among the scene's Kleinians
// (FractalParams.scene_view_distance).
uniform float view_limit;
// The centre-ray probe: a dot painted on the surface where the ray through the
// middle of the screen hits (CenterRay, marched on the CPU). Off when the probe
// is hidden or the ray misses.
uniform bool probe_on;
uniform vec3 probe_point;
uniform float probe_radius;

// --- the shapes' frames (CPU, 64-bit; see FractalView._push_frames) ---
uniform int shape_count;
uniform vec3 local_eye[MAX_SHAPES];    // the eye in each shape's frame (already / size)
uniform vec3 frame_x[MAX_SHAPES];      // the shape's local x axis in world space
uniform vec3 frame_y[MAX_SHAPES];
uniform vec3 frame_z[MAX_SHAPES];
uniform float shape_size[MAX_SHAPES];  // world units per local unit
uniform float box_half[MAX_SHAPES];    // the cube the march is bounded to (ShapeParams.bound_half)
// The coarse pass's iteration count per shape, 16..32: more as the camera
// nears the surface, so the smoother surface it marches toward stays within
// its hit threshold of the real one (ShapeParams.coarse_iters). 16 at the
// default view.
uniform int fractal_iterations = 32;
uniform int coarse_iters[MAX_SHAPES];

// --- per-shape uniforms (names == catalogue ids, one entry per shape) ---
uniform int shape[MAX_SHAPES];            // 0 Mandelbox, 1 KIFS, 2 Kleinian, 3 Mandelbulb
uniform float w[MAX_SHAPES];              // the sample point's fourth coordinate
uniform float box_scale[MAX_SHAPES];
uniform float fold_limit[MAX_SHAPES];
uniform float min_radius[MAX_SHAPES];
uniform float fixed_radius[MAX_SHAPES];
uniform int fold_order[MAX_SHAPES];       // 0 box -> sphere, 1 sphere -> box
uniform int fold_shape[MAX_SHAPES];       // 0 box, 1 cylinder, 2 octahedral
uniform float hybrid_mix[MAX_SHAPES];     // 0 off; box fold -> abs fold on hybrid iterations
uniform int hybrid_every[MAX_SHAPES];     // the hybrid iterations: i % every == every - 1
uniform float scale_drift[MAX_SHAPES];    // iteration i scales by box_scale + scale_drift * i

uniform int julia_all[MAX_SHAPES];        // the toggles are ints: 0 off, 1 on
uniform int julia_0[MAX_SHAPES];
uniform int julia_1[MAX_SHAPES];
uniform int julia_2[MAX_SHAPES];
uniform int julia_3[MAX_SHAPES];
uniform float c_0[MAX_SHAPES];
uniform float c_1[MAX_SHAPES];
uniform float c_2[MAX_SHAPES];
uniform float c_3[MAX_SHAPES];

uniform float iter_rot_xy[MAX_SHAPES];
uniform float iter_rot_xz[MAX_SHAPES];
uniform float iter_rot_xw[MAX_SHAPES];
uniform float iter_rot_yz[MAX_SHAPES];
uniform float iter_rot_yw[MAX_SHAPES];
uniform float iter_rot_zw[MAX_SHAPES];

uniform float precision[MAX_SHAPES];

// --- the scene's look (names == catalogue ids) ---
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
// Persistent camera-relative fog wall, independent of the load shedder.
// Distance is in near_dist units; 0 disables both the fade and the cutoff.
uniform float fog_distance = 0.0;
uniform float fog_start = 0.35;
uniform vec3 fog_tint = vec3(0.2, 0.2, 0.2);
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

// The hit threshold at ray distance t for a shape of precision `prec`: the
// pixel cone prec * t (detail is folded into each `precision` entry on the
// CPU, so the defaults are bit-for-bit the plain cone), coarsened by
// (t / start)^falloff past start = detail_range x the camera's distance to the
// nearest surface. Mirrors FractalParams.hit_epsilon.
float hit_eps(float t, float prec) {
	float e = prec * t;
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

float fog_wall_distance() {
	return fog_distance * near_dist;
}

vec3 fog_wall_color(vec3 col, float t) {
	if (fog_distance <= 0.0) { return col; }
	float wall = fog_wall_distance();
	float a = smoothstep(clamp(fog_start, 0.0, 0.99) * wall, wall, t);
	return mix(col, fog_tint, a);
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

// A world direction in shape s's frame: Rᵀ d (unit length stays unit).
vec3 local_dir(int s, vec3 d) {
	return vec3(dot(d, frame_x[s]), dot(d, frame_y[s]), dot(d, frame_z[s]));
}

// A local direction back in the world: R d.
vec3 world_dir(int s, vec3 d) {
	return frame_x[s] * d.x + frame_y[s] * d.y + frame_z[s] * d.z;
}

// The point a world offset `off` from the eye, in shape s's frame.
vec3 local_offset_point(int s, vec3 off) {
	return local_eye[s] + local_dir(s, off) / shape_size[s];
}

// The point at world ray distance t, in shape s's frame.
vec3 local_point(int s, vec3 dir, float t) {
	return local_offset_point(s, dir * t);
}

// Distance from a local point to shape s's cube (0 inside): a cheap lower
// bound on the shape's distance, used to skip shapes that cannot be nearest.
float cube_dist(vec3 q, float half_size) {
	vec3 d = max(abs(q) - vec3(half_size), vec3(0.0));
	return length(d);
}

// Reflect every component that leaves [-L, L] back inside.
vec4 mb_box_fold(int s, vec4 p) {
	return clamp(p, -fold_limit[s], fold_limit[s]) * 2.0 - p;
}

// Inflate the inner sphere, invert the shell between the two radii, and carry
// the same factor into the running derivative.
void mb_sphere_fold(int s, inout vec4 p, inout float dr) {
	float r2 = dot(p, p);
	float mr2 = max(min_radius[s] * min_radius[s], 1e-12);
	float fr2 = max(fixed_radius[s] * fixed_radius[s], 1e-12);
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
vec4 mb_cylinder_fold(int s, vec4 p) {
	float L = fold_limit[s];
	float r = length(p.xy);
	if (r > L) { p.xy *= (2.0 * L - r) / r; }
	p.zw = clamp(p.zw, -L, L) * 2.0 - p.zw;
	return p;
}

// Reflect xyz through the octahedron |x| + |y| + |z| <= L: twice its nearest
// point minus the point (the box fold is the same rule for the cube). The
// nearest point soft-thresholds every |component| by the theta that lands it on
// the surface. w gets the plain box fold.
vec4 mb_octahedral_fold(int s, vec4 p) {
	float L = fold_limit[s];
	float lim = max(L, 0.0);
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
	p.w = clamp(p.w, -L, L) * 2.0 - p.w;
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
vec4 mb_hybrid_fold(int s, vec4 p) {
	float L = fold_limit[s];
	float mix_ = hybrid_mix[s];
	float lo = -L * (1.0 - mix_);
	float hi = (L + mix_) / max(1.0 - mix_, 1e-6);
	return clamp(p, vec4(lo), vec4(hi)) * 2.0 - p;
}

// The fold step of iteration i: the chosen fold, or the hybrid fold on a
// hybrid iteration. Each reflects through a convex set's boundary, so each is
// 1-Lipschitz and the running derivative needs no factor.
vec4 mb_fold(int s, vec4 p, int i) {
	if (hybrid_mix[s] > 0.0) {
		int every = max(hybrid_every[s], 1);
		if (i % every == every - 1) { return mb_hybrid_fold(s, p); }
	}
	if (fold_shape[s] == 1) { return mb_cylinder_fold(s, p); }
	if (fold_shape[s] == 2) { return mb_octahedral_fold(s, p); }
	return mb_box_fold(s, p);
}

// The six per-iteration angles, fixed order xy, xz, xw, yz, yw, zw.
vec4 mb_iter_rotate(int s, vec4 p) {
	p = mb_rot_plane(p, 0, 1, iter_rot_xy[s]);
	p = mb_rot_plane(p, 0, 2, iter_rot_xz[s]);
	p = mb_rot_plane(p, 0, 3, iter_rot_xw[s]);
	p = mb_rot_plane(p, 1, 2, iter_rot_yz[s]);
	p = mb_rot_plane(p, 1, 3, iter_rot_yw[s]);
	p = mb_rot_plane(p, 2, 3, iter_rot_zw[s]);
	return p;
}

bool mb_rotating(int s) {
	return (abs(iter_rot_xy[s]) + abs(iter_rot_xz[s]) + abs(iter_rot_xw[s])
		+ abs(iter_rot_yz[s]) + abs(iter_rot_yw[s]) + abs(iter_rot_zw[s])) > 1e-6;
}

// Iteration i of shape s's Mandelbox on the 4D orbit point z with running
// derivative dz.
void mb_step(int s, inout vec4 z, inout float dz, vec4 c, bool rotating, int i) {
	if (fold_order[s] == 0) { z = mb_fold(s, z, i); mb_sphere_fold(s, z, dz); }
	else                    { mb_sphere_fold(s, z, dz); z = mb_fold(s, z, i); }
	if (rotating) { z = mb_iter_rotate(s, z); }
	float sc = box_scale[s] + scale_drift[s] * float(i);
	z = sc * z + c;
	dz = dz * abs(sc) + 1.0;
}

// Per component: the Julia constant where it is checked, the point's own
// coordinate where it is not.
vec4 mb_constant(int s, vec4 z0) {
	bool all = julia_all[s] != 0;
	return vec4(
		(all || julia_0[s] != 0) ? c_0[s] : z0.x,
		(all || julia_1[s] != 0) ? c_1[s] : z0.y,
		(all || julia_2[s] != 0) ? c_2[s] : z0.z,
		(all || julia_3[s] != 0) ? c_3[s] : z0.w);
}

// Up to iters iterations of shape s's Mandelbox orbit.
void mb_orbit(int s, inout vec4 z, inout float dz, vec4 c, int iters) {
	bool rotating = mb_rotating(s);
	for (int i = 0; i < 32; i++) {
		if (i >= iters) { break; }
		mb_step(s, z, dz, c, rotating, i);
	}
}

#include "res://src/fractal/kifs.gdshaderinc"
#include "res://src/fractal/kleinian.gdshaderinc"
#include "res://src/fractal/mandelbulb.gdshaderinc"

// How far past the start of the view distance's horizon a hit at t is: 0 clear,
// 1 at the limit, where it has faded fully into the background.
float view_fade(float t) {
	if (view_limit <= 0.0) { return 0.0; }
	return smoothstep(0.67 * view_limit, view_limit, t);
}

// Shape s's distance estimate at a point p in its own frame, up to `iters`
// iterations (<= 32), in local units. The Mandelbox's is below;
// DistanceEstimator is the CPU copy.
float de(int s, vec3 p, int iters) {
	int kind = shape[s];
	if (kind == 1) { return kifs_de(s, vec4(p, w[s]), iters) + noise_displace(p); }
	if (kind == 2) { return kleinian_de(s, vec4(p, w[s]), iters) + noise_displace(p); }
	if (kind == 3) { return mandelbulb_de(s, p, iters) + noise_displace(p); }
	vec4 z0 = vec4(p, w[s]);
	vec4 c = mb_constant(s, z0);
	vec4 z = z0;
	float dz = 1.0;
	mb_orbit(s, z, dz, c, iters);
	return length(z) / abs(dz) + noise_displace(p);
}

// The scene distance at a world offset `off` from the eye, in world units:
// the smallest shape distance, each evaluated in its own frame and scaled back
// by its size, with the coarse pass's iteration count per shape when `coarse`
// (32 otherwise). `which` is the shape that gave it. A shape whose cube is
// further away than the best so far cannot be nearest and is skipped (its true
// distance is at least that far, so the step stays safe).
float de_scene(vec3 off, bool coarse, out int which) {
	float best = 1e30;
	which = 0;
	for (int i = 0; i < MAX_SHAPES; i++) {
		if (i >= shape_count) { break; }
		vec3 q = local_offset_point(i, off);
		float bound = cube_dist(q, box_half[i]) * shape_size[i];
		if (bound >= best) { continue; }
		int iters = coarse ? clamp(coarse_iters[i], 1, fractal_iterations) : fractal_iterations;
		float d = de(i, q, iters) * shape_size[i];
		if (d < best) { best = d; which = i; }
	}
	return best;
}

// The "Ice Fractal" field of shape s: a 16-iteration Mandelbox orbit from z=0,
// c=(q, w), no derivative, offset by -8. Not a true distance; its gradient
// gives the look.
float field(int s, vec3 q) {
	vec4 z = vec4(0.0);
	vec4 c = vec4(q, w[s]);
	float dz = 1.0;
	bool rotating = mb_rotating(s);
	for (int i = 0; i < 16; i++) {
		mb_step(s, z, dz, c, rotating, i);
	}
	return length(z) - 8.0 + noise_displace(q);
}

// Central-difference normal from the high-precision estimator, in shape s's
// frame.
vec3 calc_normal(int s, vec3 v, float delta) {
	vec2 e = vec2(delta, 0.0);
	return normalize(vec3(
		de(s, v + e.xyy, fractal_iterations) - de(s, v - e.xyy, fractal_iterations),
		de(s, v + e.yxy, fractal_iterations) - de(s, v - e.yxy, fractal_iterations),
		de(s, v + e.yyx, fractal_iterations) - de(s, v - e.yyx, fractal_iterations)));
}

// The Ice Fractal normal: field at the half-scale base point h = v/2, offset
// samples at the full-scale point + 0.01 (local units). Not a true gradient,
// by design.
vec3 calc_nf(int s, vec3 v, vec3 h) {
	float lw = field(s, h);
	vec3 g = vec3(
		field(s, v + vec3(0.01, 0.0, 0.0)) - lw,
		field(s, v + vec3(0.0, 0.01, 0.0)) - lw,
		field(s, v + vec3(0.0, 0.0, 0.01)) - lw) / 0.01;
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

// A soft self-shadow for a hit on shape s at world ray distance `total` along
// `dir`: march from just off the surface toward the light (`ldir`, world), up
// to shadow_steps steps (<= 64), stopping at the hit shape's cube's far side,
// against the whole scene. A near-hit darkens fully; otherwise the closest
// approach, scaled by the lamp's angular size, is the penumbra. k widens the
// penumbra as the lamp widens (light_size); a size-0 lamp is near-hard. Costs
// one extra ray per pixel; skipped when shadow_steps is 0. The world offset
// from the eye (dir · total + the normal lift + ldir · t) is what every shape
// maps into its own frame, so the hit shape's numbers stay O(1); and since it
// goes through de_scene, every estimate is evaluated in its shape's frame.
float soft_shadow(int s, vec3 n_world, vec3 dir, vec3 ldir, float total) {
	float eps0 = hit_eps(total, precision[s]);
	vec3 lift = dir * total + n_world * 4.0 * eps0;
	vec3 ro_local = local_offset_point(s, lift);
	float far = box_intersect(ro_local, local_dir(s, ldir), box_half[s]).y * shape_size[s];
	if (fog_distance > 0.0) {
		// Shadow origins are offsets from the eye. Intersect this ray with
		// the SAME camera-centred sphere, not a new radius from the hit.
		float wall = fog_wall_distance();
		float c = dot(lift, lift) - wall * wall;
		if (c >= 0.0) { return 1.0; }
		float b = dot(lift, ldir);
		far = min(far, -b + sqrt(max(b * b - c, 0.0)));
	}
	float k = 1.0 / tan(max(radians(light_size), radians(0.5)));
	float res = 1.0;
	float t = eps0;
	int which = 0;
	for (int i = 0; i < 64; i++) {
		if (i >= shadow_steps || t >= far) { break; }
		float d = de_scene(lift + ldir * t, true, which);
		if (d < eps0) { return 0.0; }
		res = min(res, k * d / t);
		t += d * noise_step_scale();
		if (t > far) { break; }
	}
	return clamp(res, 0.0, 1.0);
}

// With a manual wall, the performance fog is in front of it. Its opaque
// colour includes the manual fade at the shed distance, so hits and the sky
// meet there and both ease towards the manual wall as the shed fog clears.
vec3 finish_surface(vec3 col, float t, vec3 dir, vec3 bg, vec3 sky) {
	if (fog_distance <= 0.0) {
		return mix(probe_dot(mix(col, fog_color, fog_amount(t)), eye + dir * t), bg, view_fade(t));
	}
	col = fog_wall_color(probe_dot(col, eye + dir * t), t);
	if (fog_dist > 0.0) {
		vec3 shed_tint = fog_wall_color(fog_color, fog_dist * near_dist);
		col = mix(col, shed_tint, fog_amount(t));
	}
	return mix(col, sky, view_fade(t));
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
	float sphere_b = dot(eye, dir);
	float sphere_discriminant = sphere_b * sphere_b - dot(eye, eye) + exit_radius * exit_radius;
	float sphere_start = 0.0;
	float sphere_end = -1.0;
	if (sphere_discriminant >= 0.0) {
		float root = sqrt(sphere_discriminant);
		sphere_start = max(0.0, -sphere_b - root);
		sphere_end = -sphere_b + root;
	}
	if (exit_has_skybox && sphere_end > 0.0
			&& (fog_distance <= 0.0 || sphere_end < fog_wall_distance())) {
		vec3 normal = normalize(eye + dir * sphere_end);
		vec2 sky_uv = vec2(atan(normal.y, normal.x) / (2.0 * PI) + 0.5,
			acos(clamp(normal.z, -1.0, 1.0)) / PI);
		bg = texture(exit_skybox, sky_uv).rgb;
	}
	// A miss is infinitely far, so under fog the sky is the fog: far surfaces fade
	// into it without a seam.
	vec3 base_bg = bg;
	if (fog_dist > 0.0) { bg = mix(fog_color, bg, fog_clear); }
	float bg_distance = sphere_end > 0.0 ? sphere_end : fog_wall_distance();
	if (view_limit > 0.0) { bg_distance = min(bg_distance, view_limit); }
	vec3 sky = bg;
	if (fog_distance > 0.0) {
		vec3 far_color = base_bg;
		if (bg_distance < fog_wall_distance()) {
			far_color = scatter(base_bg, bg_distance, dir, sky_ldir);
		}
		sky = fog_wall_color(far_color, bg_distance);
		if (fog_dist > 0.0) {
			vec3 shed_tint = fog_wall_color(fog_color, min(bg_distance, fog_dist * near_dist));
			sky = mix(sky, shed_tint, 1.0 - fog_clear);
		}
	}

	// The march covers the union of the shapes' cubes, each met in its own
	// frame (so a rotated shape's cube is oriented) and mapped back to world
	// ray distance by its size.
	float t_start = 1e30;
	float t_exit = -1.0;
	for (int i = 0; i < MAX_SHAPES; i++) {
		if (i >= shape_count) { break; }
		vec2 tb = box_intersect(local_eye[i], local_dir(i, dir), box_half[i]) * shape_size[i];
		if (tb.y >= max(tb.x, 0.0)) {
			t_start = min(t_start, max(tb.x, 0.0));
			t_exit = max(t_exit, tb.y);
		}
	}

	// The exit sphere is the scene's finite background surface. Fractal
	// geometry behind it does not hide the sky, including while outside.
	t_start = max(t_start, sphere_start);
	t_exit = min(t_exit, sphere_end);
	if (fog_distance > 0.0) {
		t_exit = min(t_exit, fog_wall_distance());
	}
	if (t_exit < 0.0 || t_start > t_exit) {
		COLOR = vec4(sky, 1.0);
	} else {
		if (fog_dist > 0.0 && fog_clear <= 0.0) {
			t_exit = min(t_exit, fog_dist * near_dist);  // nothing past the fog is marched
		}
		if (view_limit > 0.0) {
			t_exit = min(t_exit, view_limit);  // nor past the view distance
		}
		float total = t_start;
		bool left_cube = total >= t_exit;
		int which = 0;

		// Phase 1: low precision (N = each shape's coarse_iters, 16 at the
		// default view), up to coarse_steps (<= 384) steps.
		int n1 = coarse_steps;
		for (int i = 0; i < 384; i++) {
			if (left_cube || i >= coarse_steps) { break; }
			float d = de_scene(dir * total, true, which);
			if (d < hit_eps(total, precision[which]) * 2.0) { n1 = i; break; }
			total += d * noise_step_scale();
			if (total >= t_exit) { left_cube = true; break; }
		}

		// Phase 2: high precision (N=32), up to fine_steps (<= 128) steps,
		// continuing on.
		int n2 = fine_steps;
		if (!left_cube) {
			for (int i = 0; i < 128; i++) {
				if (i >= fine_steps) { break; }
				float d = de_scene(dir * total, false, which);
				if (d < hit_eps(total, precision[which])) { n2 = i; break; }
				total += d * noise_step_scale();
				if (total >= t_exit) { left_cube = true; break; }
			}
		}

		if (left_cube) {
			// The only misses: leaving every cube, the fog or the view distance.
			// The haze fills the space the ray marched, to its exit (default: no haze).
			float t_scat = min(t_exit, total);
			if (fog_distance > 0.0) {
				COLOR = vec4(sky, 1.0);  // same background as a ray that missed every cube
			} else {
				COLOR = vec4(scatter(bg, t_scat, dir, sky_ldir), 1.0);
			}
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
				COLOR = vec4(finish_surface(gcol, total, dir, bg, sky), 1.0);
			} else {
				// Everything below is in the hit shape's own frame: the point, the
				// eye, the normal and the light, so one shape at the identity
				// placement shades exactly as the single-shape viewer did. The
				// camera's axes come into the frame for the light's swing; the
				// normal and light go back to world for the view-relative modes,
				// the shadow and the haze.
				int s = which;
				vec3 v = local_point(s, dir, total);
				vec3 h = v * 0.5;
				vec3 eh = local_eye[s] * 0.5;
				float delta = hit_eps(total, precision[s]) * 40.0 / shape_size[s];
				vec3 cam_up_l = local_dir(s, cam_up);
				vec3 cam_right_l = local_dir(s, cam_right);

				// Normal: NF for modes 1..9 on the Mandelbox outside Julia mode (the NF
				// field is the Mandelbox's own orbit), N otherwise. Up close NF
				// crossfades to N by nf_weight; each end computes only its own normal,
				// so a weight of exactly 1 (the default view) is the site's maths.
				vec3 n;
				if (shape[s] == 0 && color_mode >= 1 && color_mode <= 9 && julia_all[s] == 0) {
					if (nf_weight >= 1.0) {
						n = calc_nf(s, v, h);
					} else if (nf_weight <= 0.0) {
						n = calc_normal(s, v, delta);
					} else {
						vec3 nf = calc_nf(s, v, h);
						vec3 m = mix(calc_normal(s, v, delta), nf, nf_weight);
						// The two can point nearly opposite ways (NF is not a gradient);
						// a blend that cancels to nothing keeps NF rather than a NaN.
						n = dot(m, m) > 1e-12 ? normalize(m) : nf;
					}
				} else {
					n = calc_normal(s, v, delta);
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
					ldir = rotate_about(rotate_about(ldir, cam_up_l, light_yaw), cam_right_l, light_pitch);
				}
				vec3 n_world = world_dir(s, n);
				vec3 ldir_world = world_dir(s, ldir);
				// Shadow only when the lamp is off the headlight: a headlight's shadow
				// ray retraces the view ray and would self-shadow the whole surface.
				float sh = 1.0;
				if (shadows > 0.0 && shadow_steps > 0 && swung) {
					sh = mix(1.0, soft_shadow(s, n_world, dir, ldir_world, total), shadows);
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
					// The view-relative modes read the normal against the camera's
					// axes, so it goes back to world space first.
					vec3 nv = vec3(dot(n_world, cam_right), dot(n_world, cam_up), dot(n_world, -cam_forward));
					float lv = pow(max(0.0, nv.z), 4.0);
					vec3 n2v = normalize(nv + vec3(0.5, 0.5, 0.0));
					col = (n2v + 1.0) * 0.5 * (lv - 2.0 * ce + 0.5);
				} else if (color_mode == 14) {
					vec3 nv = vec3(dot(n_world, cam_right), dot(n_world, cam_up), dot(n_world, -cam_forward));
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
				shaded = scatter(shaded, total, dir, ldir_world);
				COLOR = vec4(finish_surface(shaded, total, dir, bg, sky), 1.0);
			}
		}
	}
}
