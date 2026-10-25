shader_type canvas_item;
// Shared by every part of a card / minion (children use_parent_material): art mask, hit flash,
// desaturation and the burn-away dissolve. The noise is in canvas space, so all parts burn as one sheet.
// `tilt` turns the whole card in fake 3D: every vertex is projected through a pinhole camera in the card's own
// frame (card_center / card_x / card_y are its canvas transform), UVs are interpolated perspective-correct, and a
// glare and a light falloff follow the tilt.

uniform int mask_mode = 0; // 0 none, 1 oval, 2 rounded rectangle
uniform float corner = 0.08;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float desat : hint_range(0.0, 1.0) = 0.0;
uniform float shine = -1.0; // foil sweep position (-1 off, 0..1 across)
uniform float noise_scale = 0.018;
uniform vec2 tilt = vec2(0.0); // radians around the card's Y and X axes; positive pushes the right / bottom edge away
uniform vec2 card_center = vec2(0.0);
uniform vec2 card_x = vec2(1.0, 0.0);
uniform vec2 card_y = vec2(0.0, 1.0);
uniform float half_h = 180.0;
uniform float cam_dist = 2.6; // in half-heights; smaller = stronger perspective
// Off for text: MSDF glyphs are decoded before this shader runs, so they must not be resampled.
uniform bool resample = true;

varying vec2 world;
varying vec3 puv; // (UV * w, w) for perspective-correct sampling
varying vec2 cardn; // card-local position in half-heights, before projection
varying float depth;
varying vec4 vcol;

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
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	puv = vec3(UV, 1.0);
	cardn = vec2(0.0);
	depth = 0.0;
	vcol = COLOR;
	if (tilt != vec2(0.0)) {
		vec2 d = world - card_center;
		vec2 n = vec2(dot(d, card_x) / dot(card_x, card_x), dot(d, card_y) / dot(card_y, card_y)) / half_h;
		cardn = n;
		float z = -(n.x * sin(tilt.x) + n.y * sin(tilt.y));
		float w = cam_dist / (cam_dist - z);
		vec2 q = vec2(n.x * cos(tilt.x), n.y * cos(tilt.y)) * w * half_h;
		vec2 wp = card_center + card_x * q.x + card_y * q.y;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 0.0, 1.0)).xy;
		puv = vec3(UV * w, w);
		depth = z;
	}
}

void fragment() {
	vec4 c = COLOR;
	vec2 uv = UV;
	if (tilt != vec2(0.0) && resample) {
		uv = puv.xy / puv.z;
		c = texture(TEXTURE, uv) * vcol;
	}
	if (mask_mode == 1) {
		float d = length((uv - 0.5) * 2.0);
		c.a *= 1.0 - smoothstep(0.955, 1.0, d);
		c.rgb *= mix(1.0, 0.55, smoothstep(0.6, 1.0, d)); // inner vignette
	} else if (mask_mode == 2) {
		vec2 q = abs(uv - 0.5) * 2.0 - (1.0 - corner);
		float d = length(max(q, 0.0)) / corner;
		c.a *= 1.0 - smoothstep(0.85, 1.0, d);
		float edge = max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0;
		c.rgb *= mix(1.0, 0.7, smoothstep(0.75, 1.0, edge));
	}
	if (shine >= 0.0) {
		float s = (uv.x + uv.y) * 0.5 - shine;
		c.rgb += vec3(1.0, 0.85, 0.5) * exp(-s * s * 260.0) * 0.45 * c.a;
	}
	if (tilt != vec2(0.0) && max(c.r, max(c.g, c.b)) > 0.01) {
		// The edge turned away falls into shade; the edge turned toward the viewer catches a moving glare.
		c.rgb *= clamp(1.0 + depth * 0.55, 0.6, 1.15);
		vec2 hl = -normalize(tilt + 1e-5) * 0.55;
		float g = exp(-dot(cardn - hl, cardn - hl) * 3.0) * min(length(tilt) * 1.6, 0.4);
		c.rgb += vec3(1.0, 0.9, 0.75) * g * c.a;
	}
	c.rgb = mix(c.rgb, vec3(dot(c.rgb, vec3(0.3, 0.59, 0.11))), desat);
	c.rgb = mix(c.rgb, flash_color.rgb, flash * 0.75);
	if (burn > 0.0) {
		float n = fbm(world * noise_scale);
		float th = burn * 1.3 - 0.15;
		float e = n - th;
		if (e < 0.0) {
			c.a = 0.0;
		} else if (e < 0.1) {
			float k = 1.0 - e / 0.1;
			c.rgb = mix(c.rgb, mix(vec3(0.9, 0.3, 0.05), vec3(1.0, 0.9, 0.55), k), k);
			c.rgb *= 1.0 + k * 0.6;
		}
	}
	COLOR = c;
}
