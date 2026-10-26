shader_type canvas_item;
// One intro shot: samples a Doré plate (or a Wan video frame) through a moving camera window and
// grades it as a living engraving: levels, ember warmth, drifting procedural mist, flicker,
// vermilion grade (earthquake), vignette and paper grain.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 window = vec4(0.0, 0.0, 1.0, 1.0); // x, y, w, h of the visible part of the texture (uv)
uniform float time = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;      // alpha of the whole shot (crossfades)
uniform float exposure = 0.86;
uniform vec3 paper_tint = vec3(0.93, 0.87, 0.74);     // what white becomes
uniform vec3 ink_tint = vec3(0.016, 0.014, 0.013);    // what black becomes
uniform float contrast = 1.08;
uniform float mist : hint_range(0.0, 1.0) = 0.0;
uniform float mist_speed = 0.02;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float ember : hint_range(0.0, 1.0) = 0.0;    // warm the highlights toward ember orange
uniform float red : hint_range(0.0, 1.0) = 0.0;      // vermilion grade
uniform float vignette : hint_range(0.0, 1.5) = 0.8;
uniform float grain : hint_range(0.0, 0.3) = 0.07;
uniform float aspect = 2.39;
// Glowing coals set into the engraving (Charon's eyes): xy = position in the plate (uv), z = core radius (uv of the
// plate height), w = strength 0..1 (0 = off). The ink of the engraving stays in front of the embers.
uniform vec4 coal_a = vec4(0.0);
uniform vec4 coal_b = vec4(0.0);
uniform float tex_aspect = 1.818;

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
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 suv = UV;
	vec2 tuv = window.xy + suv * window.zw;
	tuv = 0.014 + tuv * (1.0 - 0.028); // hides the paper margin of the scans
	float l = dot(texture(tex, tuv).rgb, vec3(0.299, 0.587, 0.114));
	l = clamp((l - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 c = mix(ink_tint, paper_tint, pow(l, 1.05)) * exposure;

	// Ember warmth on the lit parts.
	float hi = smoothstep(0.55, 1.0, l);
	c = mix(c, c * vec3(1.25, 0.78, 0.45) + vec3(0.06, 0.02, 0.0) * hi, ember * (0.35 + 0.65 * hi));

	// Drifting mist (two octaves moving in opposite directions), screen-blended.
	vec2 mp = vec2(suv.x * aspect, suv.y);
	float m1 = fbm(mp * 1.6 + vec2(time * mist_speed, time * mist_speed * 0.4));
	float m2 = fbm(mp * 3.1 - vec2(time * mist_speed * 1.7, -time * mist_speed * 0.6) + 7.3);
	float m = smoothstep(0.35, 0.85, m1 * 0.65 + m2 * 0.45);
	vec3 mist_col = vec3(0.62, 0.58, 0.5);
	c = c + (1.0 - c) * mist_col * m * mist * 0.5;

	// Light flicker (fire / torch): two incommensurate sines + noise.
	float fl = 1.0 + flicker * (0.10 * sin(time * 9.3) + 0.07 * sin(time * 23.1 + 1.7) + 0.12 * (vnoise(vec2(time * 7.0, 3.1)) - 0.5));
	c *= fl;

	// Coals: deep-set embers that breathe, drawn behind the engraved lines (ink = 1 - plate luminance).
	float ink = 1.0 - l;
	for (int i = 0; i < 2; i++) {
		vec4 cl = i == 0 ? coal_a : coal_b;
		if (cl.w > 0.0) {
			vec2 pc = vec2(0.014) + cl.xy * 0.972;
			vec2 dv = (tuv - pc) * vec2(tex_aspect, 1.0);
			float d = length(dv) / cl.z;
			float ph = float(i) * 2.3;
			float pulse = 0.78 + 0.14 * sin(time * 1.7 + ph) + 0.08 * sin(time * 5.3 + ph * 3.0)
				+ 0.16 * (vnoise(vec2(time * 2.6 + ph, 4.0)) - 0.5);
			float core = exp(-d * d * 1.8);
			float halo = exp(-d * 0.55) * 0.30;
			vec3 coal = mix(vec3(0.95, 0.22, 0.04), vec3(1.0, 0.72, 0.30), smoothstep(0.35, 1.0, core));
			c += coal * (core * (0.45 + 0.55 * ink) * 1.5 + halo * ink * ink * 0.55) * pulse * cl.w;
		}
	}

	// Vermilion grade: luminance carries the red, shadows stay deep.
	if (red > 0.0) {
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 rc = vec3(1.0, 0.16, 0.05) * (0.25 + lum * 1.9) + vec3(0.18, 0.0, 0.0);
		c = mix(c, rc, red);
	}

	// Vignette in screen space.
	vec2 q = suv - 0.5;
	q.x *= aspect / 1.6;
	c *= 1.0 - vignette * smoothstep(0.25, 0.95, length(q) * 1.15);

	// Paper grain (animated at ~12 fps so it does not crawl).
	float g = hash(floor(suv * vec2(aspect * 540.0, 540.0)) + floor(time * 12.0) * 3.7) - 0.5;
	c += g * grain;

	COLOR = vec4(max(c, vec3(0.0)), fade);
}
