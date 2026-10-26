shader_type canvas_item;
// Heat shimmer above the ember crack of Dis: wobbles whatever was drawn under it (the board), strongest near the
// bottom of the rect, rising and fading upward. Drawn on the board layer, so cards and the UI stay crisp.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 3.0;   // pixels of displacement
uniform float glow = 0.12;      // faint orange haze

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float t = TIME;
	// Rising heat: strongest at the crack (the vertical middle of the rect), fading above and below.
	float rise = exp(-abs(UV.y - 0.55) * 4.0);
	float edge = smoothstep(0.0, 0.05, UV.x) * smoothstep(1.0, 0.95, UV.x);
	vec2 q = vec2(UV.x * 40.0, UV.y * 6.0 + t * 1.6);
	vec2 off = vec2(noise(q) - 0.5, noise(q + vec2(17.0, 3.0)) - 0.5) * 2.0;
	off *= strength * rise * edge;
	vec3 col = textureLod(screen_tex, SCREEN_UV + off * SCREEN_PIXEL_SIZE, 0.0).rgb;
	col += vec3(1.0, 0.35, 0.08) * glow * rise * edge * (0.6 + 0.4 * noise(q * 0.5));
	COLOR = vec4(col, 1.0);
}
