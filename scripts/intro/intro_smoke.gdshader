shader_type canvas_item;
render_mode blend_add;
// Smoke rising behind the title card: slow billowing noise, lit from below by the ember glow of the
// letters (vermilion near the title band, cold grey higher up). Additive, so it never greys the black.

uniform float time = 0.0;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float band_y = 0.5;          // vertical centre of the title (0..1 of the card)
uniform float aspect = 2.39;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 5.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float rise = time * 0.05;
	// domain-warped, upward-drifting smoke
	vec2 q = vec2(fbm(p * 1.3 + vec2(0.0, rise)), fbm(p * 1.3 + vec2(5.2, rise * 1.3)));
	float n = fbm(p * 1.8 + q * 1.6 - vec2(0.0, rise * 1.6));
	float s = smoothstep(0.38, 0.85, n);
	// concentrated in a soft band that starts just under the letters and fans upward
	float dy = uv.y - band_y;
	float shape = smoothstep(0.45, -0.05, dy) * smoothstep(-0.55, -0.02, dy) * smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x);
	float glow = exp(-abs(dy) * 7.0);
	vec3 warm = vec3(0.85, 0.22, 0.06);
	vec3 cold = vec3(0.16, 0.14, 0.13);
	vec3 col = mix(cold, warm, glow * glow);
	COLOR = vec4(col * s * shape * amount * 0.95, 1.0);
}
