shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod = 1.5;
uniform float scanline_strength = 0.018;
uniform float scanline_spacing = 3.0;

void fragment() {
	vec3 behind = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	float tint_strength = clamp(COLOR.a, 0.0, 1.0);
	vec3 glass = mix(behind, COLOR.rgb, tint_strength);
	float scanline = step(0.66, fract(FRAGCOORD.y / scanline_spacing));
	glass *= 1.0 - scanline * scanline_strength;
	COLOR = vec4(glass, 1.0);
}
