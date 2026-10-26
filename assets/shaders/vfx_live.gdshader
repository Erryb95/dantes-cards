shader_type canvas_item;
render_mode blend_add;
// Brings the painted VFX sprites to life without extra frames: the painting flows (rising heat for fire, a faint
// shimmer for ice and light), and instead of fading uniformly it burns away through noise with a hot rim. The fade
// is driven by the sprite's alpha (modulate.a), so the existing tweens animate it unchanged.

uniform float flow = 0.025; // UV distortion strength
uniform float rise = 0.35; // how fast the distortion field drifts upward (heat)
uniform float scale = 3.0; // noise frequency across the sprite
uniform float seed = 0.0;
uniform float rim = 1.6; // brightness of the burning edge while it erodes

varying vec4 v_col;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return 0.65 * vnoise(p) + 0.35 * vnoise(p * 2.17 + 3.1);
}

void vertex() {
	v_col = COLOR;
}

void fragment() {
	vec2 drift = vec2(seed, seed * 1.7 - TIME * rise);
	vec2 warp = vec2(fbm(UV * scale + drift), fbm(UV * scale + drift + vec2(5.2, 1.3))) - 0.5;
	// Stronger near the top of the sprite, like heat rising off a flame; the base stays anchored.
	vec2 uv = UV + warp * flow * (0.4 + 0.6 * (1.0 - UV.y));
	vec4 tex = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	// The first 30% of a fade dims the sprite as usual; the rest eats it away through the noise (so a sprite held at
	// partial alpha is only a little eroded).
	float fade = v_col.a;
	float bright = max(fade, 0.7);
	float t = clamp(1.0 - fade / 0.7, 0.0, 1.0); // 0 = whole, 1 = gone
	float n = fbm(UV * scale * 1.6 + vec2(seed * 3.1, seed));
	float keep = smoothstep(t, t + 0.18, n) * step(0.001, fade);
	float edge = (1.0 - smoothstep(t, t + 0.07, n)) * keep * step(0.02, t);
	vec3 rgb = tex.rgb * v_col.rgb * bright * (1.0 + edge * rim);
	COLOR = vec4(rgb * keep, tex.a * keep);
}
