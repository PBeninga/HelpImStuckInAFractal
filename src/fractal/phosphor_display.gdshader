shader_type canvas_item;
render_mode unshaded;

uniform float glow = 0.5;
uniform float scan_center = 0.0;
uniform float scan_width = 0.125;
uniform float output_height = 800.0;

void fragment() {
	vec3 col = texture(TEXTURE, UV).rgb;
	vec2 d = TEXTURE_PIXEL_SIZE * 2.0;
	vec3 halo = (texture(TEXTURE, UV + vec2(d.x, 0.0)).rgb
		+ texture(TEXTURE, UV - vec2(d.x, 0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0, d.y)).rgb
		+ texture(TEXTURE, UV - vec2(0.0, d.y)).rgb) * 0.25;
	float light = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 phosphor = mix(col, light * vec3(0.3, 1.15, 1.0), 0.45);
	float lines = 0.88 + 0.12 * cos(UV.y * output_height * 3.14159265);
	float beam = 1.0 - smoothstep(scan_width * 0.3, scan_width * 0.65,
		abs(UV.y - scan_center));
	COLOR = vec4(phosphor * lines + halo * glow * 0.55
		+ vec3(0.025, 0.11, 0.09) * beam * (0.4 + glow), 1.0);
}
