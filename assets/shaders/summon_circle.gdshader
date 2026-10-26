shader_type canvas_item;
render_mode blend_add;
// Summoning circle drawn on the board under a minion that lands: a burst of light at the centre, two rune rings
// turning in opposite directions (procedural glyph strokes), radial rays and a shock ring that races outward,
// all driven by `t` (0 -> 1 over the effect). The node is squashed vertically to lie flat on the table.

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float seed = 0.0;

float hash(float x) { return fract(sin(x * 91.17 + seed * 7.3) * 43758.5453); }

// A ring of rune-like strokes: short arcs and ticks whose layout comes from a hash per cell.
float runes(float r, float a, float radius, float width, float cells, float spin) {
	float band = 1.0 - smoothstep(0.0, width, abs(r - radius));
	float u = (a / 6.28318 + spin) * cells;
	float id = floor(u);
	float f = fract(u);
	float h = hash(id);
	float stroke = 0.0;
	if (h > 0.25) {
		stroke = step(0.15, f) * step(f, 0.15 + 0.5 * h); // an arc segment
	}
	float tick = 1.0 - smoothstep(0.0, 0.06, abs(f - 0.5)); // a vertical tick
	float inner = 1.0 - smoothstep(0.0, width * 0.5, abs(r - radius));
	return band * max(stroke * 0.9, tick * step(h, 0.5)) + inner * 0.15;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Envelope: quick ignition, hold, slow fade.
	float on = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.55, 1.0, t));
	float grow = 0.55 + 0.45 * smoothstep(0.0, 0.3, t);
	float rr = r / grow;
	float spin = t * 0.35;
	float ring_a = runes(rr, a, 0.78, 0.07, 28.0, spin);
	float ring_b = runes(rr, a, 0.56, 0.05, 18.0, -spin * 1.6 + 0.3);
	float lines = (1.0 - smoothstep(0.0, 0.012, abs(rr - 0.9))) + (1.0 - smoothstep(0.0, 0.01, abs(rr - 0.66)))
		+ (1.0 - smoothstep(0.0, 0.01, abs(rr - 0.45)));
	// A pentagram-ish star: five straight chords inside the inner ring.
	float star = 0.0;
	for (int i = 0; i < 5; i++) {
		float a0 = 6.28318 * float(i) / 5.0 + spin * 2.0;
		float a1 = a0 + 6.28318 * 2.0 / 5.0;
		vec2 v0 = vec2(cos(a0), sin(a0)) * 0.45;
		vec2 v1 = vec2(cos(a1), sin(a1)) * 0.45;
		vec2 pa = p / grow - v0;
		vec2 ba = v1 - v0;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		star += 1.0 - smoothstep(0.0, 0.012, length(pa - ba * h));
	}
	float rays = pow(max(0.0, sin(a * 12.0 + t * 4.0)), 18.0) * smoothstep(0.95, 0.3, rr) * 0.5;
	float core = exp(-r * r * 9.0) * (1.0 - smoothstep(0.0, 0.5, t)) * 2.2;
	float shock_r = smoothstep(0.0, 0.6, t) * 1.05;
	float shock = (1.0 - smoothstep(0.0, 0.06, abs(r - shock_r))) * (1.0 - smoothstep(0.3, 0.7, t));
	float flicker = 0.85 + 0.15 * sin(t * 60.0 + a * 3.0);
	float glyphs = (ring_a + ring_b + lines * 0.7 + star * 0.6) * flicker;
	float m = (glyphs + rays) * on + core + shock * 1.4;
	m *= 1.0 - smoothstep(0.96, 1.0, r);
	vec3 col = mix(color.rgb, hot.rgb, clamp(core * 0.6 + shock + glyphs * 0.25, 0.0, 1.0));
	COLOR = vec4(col, clamp(m, 0.0, 1.5));
}
