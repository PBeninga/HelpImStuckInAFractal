shader_type canvas_item;
render_mode unshaded;

// Only this cheap presentation pass runs at full display resolution. TEXTURE
// is the smaller ray-marched viewport; no distance estimates or camera rays here.
uniform sampler2D ray_texture : filter_linear, repeat_disable;
uniform vec2 display_size = vec2(1280.0, 800.0);
uniform float brush_size = 12.0;

float mark_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 sample_paint(sampler2D source, vec2 uv, vec2 texel) {
	return texture(source, clamp(uv, texel * 0.5, vec2(1.0) - texel * 0.5)).rgb;
}

float luminance(vec3 rgb) {
	return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 screen_size = max(display_size, vec2(1.0));
	vec2 pixel = UV * screen_size;
	float spacing = max(brush_size * 0.65, 1.0);
	vec2 cell = floor(pixel / spacing);
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec3 base = sample_paint(ray_texture, UV, texel);
	vec3 paint = vec3(0.0);
	float total = 0.0;
	// Screen-anchored jittered lattice, deterministic at rest (no TIME/random
	// frames). Neighbouring ellipses overlap; edge-aware weights limit bleeding.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = cell + vec2(float(x), float(y));
			float seed = mark_hash(id);
			vec2 jitter = vec2(seed, mark_hash(id + vec2(19.0, 7.0))) - 0.5;
			vec2 centre = (id + 0.5 + jitter * 0.45) * spacing;
			vec2 uv = centre / screen_size;
			vec3 ink = sample_paint(ray_texture, uv, texel);
			float gx = luminance(sample_paint(ray_texture, uv + vec2(texel.x, 0.0), texel))
				- luminance(sample_paint(ray_texture, uv - vec2(texel.x, 0.0), texel));
			float gy = luminance(sample_paint(ray_texture, uv + vec2(0.0, texel.y), texel))
				- luminance(sample_paint(ray_texture, uv - vec2(0.0, texel.y), texel));
			vec2 gradient = vec2(gx, gy);
			float angle = seed * 6.2831853;
			vec2 tangent = vec2(cos(angle), sin(angle));
			if (dot(gradient, gradient) > 0.0001) {
				tangent = normalize(vec2(-gy, gx));
			}
			vec2 delta = pixel - centre;
			vec2 local = vec2(dot(delta, tangent), dot(delta, vec2(-tangent.y, tangent.x)));
			local /= brush_size * vec2(0.88, 0.34);
			float bristle = 0.87 + 0.13 * sin(local.y * 27.0 + seed * 30.0);
			float dab = 1.0 - smoothstep(0.65, 1.0, length(local) / bristle);
			vec3 difference = ink - base;
			float edge = exp(-dot(difference, difference) * 70.0);
			float weight = dab * edge;
			paint += ink * (0.95 + 0.1 * seed) * weight;
			total += weight;
		}
	}
	// Keep source colour in gaps and at rejected edges, so silhouettes are not
	// erased. A slight paper grain gives quiet areas a stable painted surface.
	vec3 color = (paint + base * 0.12) / (total + 0.12);
	float grain = mark_hash(floor(pixel));
	color *= 0.985 + 0.03 * grain;
	COLOR = vec4(color, 1.0);
}
