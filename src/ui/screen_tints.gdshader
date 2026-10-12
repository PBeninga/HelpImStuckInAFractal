shader_type canvas_item;
render_mode unshaded;

uniform int region_count = 0;
uniform vec3 circles[8]; // screen UV center + radius in view heights
uniform vec4 tints[8];   // RGB + opacity
uniform float aspect = 1.0;

void fragment() {
	vec3 premultiplied = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= region_count) { break; }
		vec2 offset = (UV - circles[i].xy) * vec2(aspect, 1.0);
		float mask = 1.0 - smoothstep(circles[i].z * 0.55, circles[i].z, length(offset));
		float opacity = tints[i].a * mask;
		premultiplied = tints[i].rgb * opacity + premultiplied * (1.0 - opacity);
		alpha = opacity + alpha * (1.0 - opacity);
	}
	COLOR = vec4(premultiplied / max(alpha, 0.00001), alpha);
}
