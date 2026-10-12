// Grass adapted from the user-supplied Shadertoy shader:
// https://www.shadertoy.com/view/tls3RX
// Retains the blade geometry, wind, colour variation and cloud shadows.
// The game's skybox replaces its sky/lens effects; no channel textures or AA.
// Grass coordinates are Y-up, converted from the game's Z-up view ray.
// A stationary eye 18.5 grass units above the ground preserves the reference
// proportions. The plane is beneath the escape point, independent of level scale.
const float ESCAPE_GRASS_HEIGHT = 7.35;
const float ESCAPE_GRASS_HALFWIDTH = 0.35;

float escape_grass_noise(vec2 p) {
	float rx = p.x + sin(p.y / 43.0) * 43.0;
	float ry = p.y + sin(p.x / 37.0) * 37.0;
	float f = sin(rx / 11.2312) + sin(ry / 14.4235);
	f = f * 0.5 + sin(rx / 24.0) * sin(ry / 24.0);
	rx += sin(p.y / 210.23) * 210.23;
	ry += sin(p.x / 270.0) * 270.0;
	f = f * 0.5 + sin(rx / 65.0) * sin(ry / 65.0);
	return f * 0.5 + sin(rx / 165.0) * sin(ry / 165.0);
}

float escape_grass_wind(float x) {
	float wind = (sin(x / 12.5) + sin(x / 32.5)) * 1.2;
	float bigw = (sin(x / 87.5) + sin(x / 82.5)) * 0.25 + 0.5;
	wind += bigw * bigw * 3.0;
	float hf = sin(x / 1.625) * 0.2;
	float lowf = max(sin(x / 42.5), 0.0);
	return lowf * (hf - lowf * 0.6) + wind;
}

bool escape_grass_triangle(vec3 ro, vec3 rd, vec3 v0, vec3 v1, vec3 v2, out vec3 hit) {
	vec3 edge1 = v1 - v0;
	vec3 edge2 = v2 - v0;
	vec3 h = cross(rd, edge2);
	float a = dot(edge1, h);
	if (abs(a) < 0.0000001) { return false; }
	float f = 1.0 / a;
	vec3 s = ro - v0;
	float u = f * dot(s, h);
	if (u < 0.0 || u > 1.0) { return false; }
	vec3 q = cross(s, edge1);
	float v = f * dot(rd, q);
	if (v < 0.0 || u + v > 1.0) { return false; }
	float t = f * dot(edge2, q);
	if (t <= 0.0000001) { return false; }
	hit = ro + rd * t;
	return true;
}

bool escape_grass_blade(vec3 ro, vec3 rd, vec3 right, vec3 pos, float time, out vec3 color) {
	vec3 center = vec3(floor(pos.x), 0.0, floor(pos.z));
	float angle = fract(center.x / 4.5678234 * center.z / 3.1415);
	float noise = max((sin(center.x / 34.0) * cos(center.z / 34.0) * 0.5
		+ sin(center.x / 13.0) * cos(center.z / 13.0) * 0.4) / 1.5, 0.0);
	center.x += cos(angle * 8.5) * ESCAPE_GRASS_HALFWIDTH * 2.0;
	center.z += sin(angle * 8.5) * ESCAPE_GRASS_HALFWIDTH * 2.0;
	vec3 v0 = center + right * ESCAPE_GRASS_HALFWIDTH;
	vec3 v1 = center - right * ESCAPE_GRASS_HALFWIDTH;
	vec3 v2 = center + vec3(0.0, ESCAPE_GRASS_HEIGHT * (0.8 + 0.2 * noise), 0.0);
	v2.x -= escape_grass_wind(sin(center.x / 10.0) * sin(center.z / 10.0) * 19.0 + time * 40.0) * 1.3;
	vec3 hit;
	if (!escape_grass_triangle(ro, rd, v0, v1, v2, hit)) { return false; }
	// Colour and cloud shading only matter for blades actually hit by the ray.
	float n = escape_grass_noise(center.xz * 5.0);
	float xt = center.x - time * 40.0;
	float clouds = clamp(sin(xt / 50.0) * sin(center.z / 50.0)
		+ sin(xt / 87.0) * sin(center.z / 87.0), 0.0, 1.0);
	color = mix(vec3(1.0, 0.45, 0.0), vec3(0.7, 0.6, 0.5), clamp(n, 0.0, 1.0));
	color *= (1.0 - 0.5 * clouds) * clamp(hit.y / v2.y, 0.0, 1.0);
	return true;
}

vec3 escape_grass_color(vec3 world_dir, vec3 world_right, vec3 horizon, float time) {
	vec3 rd = world_dir.xzy;
	if (rd.y >= -0.00001) { return horizon; }
	vec3 ro = vec3(0.0, 18.5, 0.0);
	vec3 across = cross(rd, vec3(0.0, 1.0, 0.0));
	vec3 right = dot(across, across) > 1e-10 ? normalize(across) : normalize(world_right.xzy);
	vec3 pos = ro + rd * ((ro.y - ESCAPE_GRASS_HEIGHT) / -rd.y);
	vec3 step_ray = rd / -rd.y * 0.3;
	vec3 final_color = vec3(0.0);
	int hits = 0;
	for (int i = 0; i < 100; i++) {
		if (hits >= 2 || pos.y < 0.0) { break; }
		for (int k = -2; k <= 2; k++) {
			vec3 color;
			if (escape_grass_blade(ro, rd, right, pos + right * float(k), time, color)) {
				final_color += color;
				hits++;
				break;
			}
		}
		pos += step_ray;
	}
	if (hits > 0) { final_color /= float(hits); }
	// Use the actual escape sky at the horizon so the two meet without a seam.
	float fog = 1.0 - exp(-length(ro - pos) * 0.002);
	return mix(final_color, horizon, fog);
}

// Stable ordered 4x4 coverage. Midpoint thresholds make 0 and 1 exact.
float escape_dither_threshold(vec2 pixel) {
	ivec2 p = ivec2(floor(pixel)) & ivec2(3);
	int low = ((p.x ^ p.y) & 1) * 2 + (p.y & 1);
	int high = (((p.x >> 1) ^ (p.y >> 1)) & 1) * 2 + ((p.y >> 1) & 1);
	return (float(low * 4 + high) + 0.5) / 16.0;
}
