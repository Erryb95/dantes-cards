shader_type canvas_item;
// Full-screen drifting fog + vignette over the backdrop.

uniform vec4 fog_color : source_color = vec4(0.35, 0.18, 0.12, 1.0);
uniform float density = 0.35;
uniform float vignette = 0.75;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.025;
	float f = fbm(uv * vec2(3.0, 2.0) + vec2(t, t * 0.3));
	f = fbm(uv * vec2(3.0, 2.0) + f * 1.6 + vec2(-t * 0.6, 0.0));
	float band = 1.0 - 0.55 * smoothstep(0.25, 0.5, uv.y) * smoothstep(0.75, 0.5, uv.y);
	float a = smoothstep(0.35, 0.9, f) * density * band;
	vec2 v = (uv - 0.5) * vec2(1.25, 1.0);
	float vig = smoothstep(0.35, 0.95, length(v)) * vignette;
	vec3 col = mix(fog_color.rgb, vec3(0.0), vig / max(a + vig, 0.001));
	COLOR = vec4(col, clamp(a + vig, 0.0, 0.95));
}
