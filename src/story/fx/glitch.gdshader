shader_type canvas_item;
// A broken-jump glitch over whatever is on screen: tearing bands, colour
// fringing, noise and scanlines, all scaled by `amount` (0 = untouched).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 36.0 + seed * 5.0);
	float tear = step(0.62, hash(band * 1.7 + seed)) * (hash(band + seed) - 0.5) * 0.12 * amount;
	uv.x = fract(uv.x + tear);
	float fringe = 0.008 * amount;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(fringe, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(fringe, 0.0)).b;
	c += (hash(uv.y * 811.0 + uv.x * 37.0 + seed) - 0.5) * 0.25 * amount;
	c *= 1.0 - 0.25 * amount * step(0.5, fract(SCREEN_UV.y * 200.0));
	COLOR = vec4(c, 1.0);
}
