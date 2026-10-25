shader_type canvas_item;
// The Acheron band across the middle of the board: slow flowing caustics, ember reflections,
// and up to 4 touch ripples (ripples[i] = vec4(x, y, start_time, strength) in UV space).

uniform vec4 deep : source_color = vec4(0.02, 0.025, 0.03, 0.55);
uniform vec4 glint : source_color = vec4(1.0, 0.45, 0.15, 1.0);
uniform float aspect = 6.0;
uniform vec4 ripples[4];
uniform float now = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	float t = TIME * 0.08;
	vec2 warp = vec2(noise(p * 3.0 + vec2(t * 2.0, 0.0)), noise(p * 3.0 + vec2(0.0, t * 1.5) + 7.0));
	float ring = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 r = ripples[i];
		float age = now - r.z;
		if (age > 0.0 && age < 2.2 && r.w > 0.0) {
			vec2 d = vec2((UV.x - r.x) * aspect, UV.y - r.y);
			float dist = length(d);
			float wave = sin((dist - age * 0.55) * 60.0) * exp(-abs(dist - age * 0.55) * 18.0);
			ring += wave * (1.0 - age / 2.2) * r.w;
			warp += d * wave * 0.08;
		}
	}
	float n = noise(p * vec2(9.0, 22.0) + warp * 2.5 + vec2(-t * 6.0, 0.0));
	float caust = pow(smoothstep(0.55, 0.95, n), 3.0);
	float edge = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	vec3 col = deep.rgb + glint.rgb * caust * 0.35 + vec3(0.9, 0.6, 0.35) * max(ring, 0.0) * 0.35;
	COLOR = vec4(col, (deep.a + caust * 0.25 + abs(ring) * 0.3) * edge);
}
