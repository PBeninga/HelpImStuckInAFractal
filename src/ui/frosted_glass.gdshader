shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 panel_size = vec2(1.0);
uniform vec4 tint_color : source_color = vec4(0.025, 0.14, 0.06, 0.68);
uniform float corner_radius = 12.0;
uniform float blur_lod = 2.5;
uniform float refraction_px = 4.0;
uniform float bevel_width = 18.0;
uniform float scanline_strength = 0.012;
uniform float scanline_spacing = 3.0;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec2 half_size = max(panel_size, vec2(1.0)) * 0.5;
	float radius = clamp(corner_radius, 0.0, min(half_size.x, half_size.y));
	vec2 p = (UV - 0.5) * panel_size;
	vec2 q = abs(p) - half_size + radius;
	vec2 outside = max(q, vec2(0.0));
	float outside_length = length(outside);
	float distance = outside_length + min(max(q.x, q.y), 0.0) - radius;
	float aa = max(fwidth(distance), 0.75);
	float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);

	// Analytic edge normal: no extra scene samples or distance evaluations.
	vec2 edge_normal = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
	if (outside_length > 0.001) {
		edge_normal = sign(p) * outside / outside_length;
	}
	float edge = 1.0 - smoothstep(0.0, bevel_width, -distance);
	float bevel = edge * edge;
	vec2 sample_uv = SCREEN_UV + edge_normal * bevel * refraction_px * SCREEN_PIXEL_SIZE;
	sample_uv = clamp(sample_uv, SCREEN_PIXEL_SIZE * 0.5, vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5);
	// One mipmapped sample gives a frosted center and a clearer refracting rim.
	vec3 behind = textureLod(screen_texture, sample_uv, mix(blur_lod, 0.8, bevel)).rgb;
	vec3 glass = mix(behind, tint_color.rgb, clamp(tint_color.a * 0.76, 0.0, 1.0));
	float lighting = 0.35 + 0.65 * max(dot(edge_normal, vec2(-0.6, -0.8)), 0.0);
	glass += vec3(1.0) * lighting * bevel * 0.10;
	float scanline = step(0.66, fract(FRAGCOORD.y / scanline_spacing));
	glass *= 1.0 - scanline * scanline_strength;
	COLOR = vec4(glass * vertex_tint.rgb, coverage * vertex_tint.a);
}
