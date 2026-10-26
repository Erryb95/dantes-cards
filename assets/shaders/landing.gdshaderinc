// Shared by landing_ground / landing_glow: the stone cracks and dust ring left when a minion slams onto the board.
// The node is squashed vertically so it lies flat on the table. `t` runs 0 -> 1 over the effect.

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float seed = 0.0;
uniform float power = 0.0; // 0..1: longer cracks, hotter glow for expensive minions

float h1(float x) { return fract(sin(x * 91.17 + seed * 7.31) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Jagged radial cracks from the impact point, each with one side branch. Returns the crack mask (1 on a crack).
float cracks(vec2 p) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float spread = smoothstep(0.0, 0.16, t); // they race out in the first instants
	float m = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float base = 6.28318 * (fi + 0.4 * h1(fi)) / 7.0;
		float len = (0.45 + 0.4 * h1(fi + 11.0)) * (0.75 + 0.25 * power) * spread;
		// Wobble the crack's angle along its length so it zig-zags like broken stone.
		// Low-frequency, stepped wobble: broken stone runs in straight-ish segments with sharp kinks.
		// A continuous polyline: random angular offsets at knots along the radius, joined by straight runs.
		float u = r * 6.0;
		float seg = floor(u);
		float wob = mix(h1(seg * 1.7 + fi * 5.3), h1((seg + 1.0) * 1.7 + fi * 5.3), fract(u)) - 0.5;
		wob = wob * 0.5 / (0.6 + r * 2.0); // wider kinks near the centre, where the angle covers less ground
		float da = abs(mod(a - base - wob + 3.14159, 6.28318) - 3.14159) * r;
		float width = 0.03 * (1.0 - r / max(len, 0.001)) + 0.004;
		float line = (1.0 - smoothstep(0.0, width, da)) * step(r, len) * step(0.06, r);
		// One branch splitting off halfway.
		float bstart = len * (0.35 + 0.3 * h1(fi + 23.0));
		float bdir = base + (h1(fi + 5.0) > 0.5 ? 0.5 : -0.5);
		float db = abs(mod(a - bdir - wob * 0.5 + 3.14159, 6.28318) - 3.14159) * r;
		float bline = (1.0 - smoothstep(0.0, width * 0.8, db)) * step(bstart, r) * step(r, bstart + len * 0.45);
		m = max(m, max(line, bline * step(0.1, r)));
	}
	// A broken ring where the stone caved in.
	float ring_r = 0.11 + 0.02 * vnoise(vec2(a * 3.0, 1.0));
	m = max(m, (1.0 - smoothstep(0.0, 0.008, abs(r - ring_r))) * step(0.35, vnoise(vec2(a * 4.0, 7.0))) * spread);
	return m;
}
