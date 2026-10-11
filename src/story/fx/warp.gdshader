shader_type canvas_item;
// Hyperspace: star streaks racing out from the centre. `travel` is how far the
// stars have come (the intro stutters it backwards); `speed` stretches the
// streaks; `flash` washes everything to white.

uniform float travel = 0.0;
uniform float speed = 0.2;
uniform float flash = 0.0;
uniform float aspect = 1.6;
uniform vec3 tint = vec3(0.55, 0.8, 1.0);

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);
		float slices = 140.0 + 110.0 * fl;
		float id = floor(a * slices);
		float h = hash(id + 31.7 * fl);
		float z = fract(h * 9.13 + travel * (0.35 + 0.15 * fl));
		float pos = z * z * 1.25;                     // accelerate outward
		float len = 0.01 + speed * 0.45 * z;          // stretch with speed and distance
		float along = smoothstep(pos - len, pos, r) * (1.0 - smoothstep(pos, pos + 0.01, r));
		float centre = (id + 0.5) / slices;
		float across = abs(a - centre) * slices;      // 0 on the streak's spine, 0.5 at the slice edge
		float thin = smoothstep(0.18 + 0.05 * fl, 0.0, across);
		col += along * thin * mix(tint, vec3(1.0), h) * (0.6 + 0.6 * z);
	}
	col += tint * exp(-r * r * 10.0) * (0.15 + speed * 0.5);   // the tunnel's glow
	COLOR = vec4(mix(col, vec3(1.0), clamp(flash, 0.0, 1.0)), 1.0);
}
