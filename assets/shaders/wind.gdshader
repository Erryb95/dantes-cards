shader_type canvas_item;
// The current of wind across the middle of the second circle: drifting mist and thin streaks racing sideways.
// `gust` (0..1, set by code on a touch) speeds the streaks up and brightens them; `gust_x` is where it started.

uniform vec4 mist_color : source_color = vec4(0.72, 0.68, 0.8, 0.32);
uniform vec4 streak_color : source_color = vec4(0.95, 0.9, 1.0, 0.55);
uniform float aspect = 12.0;
uniform float speed = 1.0;
uniform float gust = 0.0;
uniform float gust_x = 0.5;
uniform float time_offset = 0.0; // accumulated by code so a gust speeds the wind without a jump

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float x = UV.x * aspect;
	float y = UV.y;
	float t = time_offset;
	// The band sways gently up and down along its length.
	float sway = sin(x * 0.45 + t * 0.6) * 0.06;
	float yy = y + sway;
	// Rolling mist.
	float m = fbm(vec2(x * 0.5 - t * 0.35, yy * 3.0 + t * 0.05));
	m = fbm(vec2(x * 0.5 - t * 0.5, yy * 3.0) + m * 1.4);
	float band = smoothstep(0.0, 0.35, yy) * smoothstep(1.0, 0.65, yy);
	float mist = smoothstep(0.35, 0.8, m) * band;
	// Streaks: noise stretched along x, scrolling fast.
	float s = noise(vec2(x * 0.25 - t * 2.2, yy * 26.0));
	s *= noise(vec2(x * 0.9 - t * 3.0, yy * 13.0 + 4.0));
	float streak = smoothstep(0.45, 0.75, s) * band;
	// Gust: brighter near where it was touched, spreading downwind.
	float g = gust * exp(-abs(UV.x - gust_x - gust * 0.1) * 3.0);
	vec3 col = mist_color.rgb * mist * mist_color.a + streak_color.rgb * streak * streak_color.a * (1.0 + g * 2.5);
	float a = clamp(mist * mist_color.a + streak * streak_color.a * (1.0 + g * 2.0), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.04, UV.x) * smoothstep(1.0, 0.96, UV.x);
	COLOR = vec4(col / max(a, 0.001), a * edge);
}
