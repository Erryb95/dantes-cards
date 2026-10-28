shader_type canvas_item;
// Shared by every part of a card / minion (children use_parent_material): art mask, hit flash,
// desaturation and the burn-away dissolve. The noise is in canvas space, so all parts burn as one sheet.
// `tilt` turns the whole card in fake 3D: every vertex is projected through a pinhole camera in the card's own
// frame (card_center / card_x / card_y are its canvas transform), UVs are interpolated perspective-correct, and a
// glare and a light falloff follow the tilt.
// Depth parallax (art only): with a depth map (near = white) the painting is sampled through a window: what lies behind
// `depth_focus` slides against the frame as the view turns (`parallax`, radians like `tilt`), what lies in front slides the
// other way. The art is over-scaled by `depth_margin` so a shifted edge never shows.
// Living art (art only, `living_level` > 0): see living_art.gdshaderinc and docs/LIVING_ART.md.

uniform int mask_mode = 0; // 0 none, 1 oval, 2 rounded rectangle
uniform float corner = 0.08;
// Sub-rectangle (x, y, w, h in 0..1) of the texture to show across the rect, for a video that is cropped to the card's
// art framing on the GPU. The default shows the whole texture; the masks below still see UV 0..1 across the rect.
uniform vec4 crop = vec4(0.0, 0.0, 1.0, 1.0);
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform vec4 burn_edge : source_color = vec4(0.9, 0.3, 0.05, 1.0); // the dissolve's glowing rim: outer colour
uniform vec4 burn_hot : source_color = vec4(1.0, 0.9, 0.55, 1.0); // ... and its white-hot inner line
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
uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float depth_amount = 0.0; // UV shift per radian of view for a full depth step; 0 = no parallax
uniform vec2 parallax = vec2(0.0); // view direction in radians (+x: seen from the left, +y: seen from above)
uniform vec4 depth_rect = vec4(0.0, 0.0, 1.0, 1.0); // where the art's UV 0..1 lies in the depth map
uniform float depth_focus = 0.6; // the depth that stays put (the window plane)
uniform float depth_margin = 0.03; // over-scale, >= the largest shift
uniform float art_aspect = 1.0; // w / h of the art rect, so a turn shifts as many pixels across as down
// Off for text: MSDF glyphs are decoded before this shader runs, so they must not be resampled.
uniform bool resample = true;
// The card's name in engraved gold (as gilded_text.gdshader): the fill's light turns to gold metal from the
// capitals' top (gild_top) to the baseline (gild_base), in the label's own pixels; the dark outline stays.
uniform bool gild = false;
uniform float gild_top = 0.0;
uniform float gild_base = 30.0;

varying vec2 world;
varying vec3 puv; // (UV * w, w) for perspective-correct sampling
varying vec2 cardn; // card-local position in half-heights, before projection
varying float depth;
varying vec4 vcol;
varying vec2 local; // the vertex in the item's own space, before the tilt moves it

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

#include "res://assets/shaders/living_art.gdshaderinc"

vec3 gold_ramp(float t) {
	vec3 top = vec3(1.0, 0.95, 0.76);
	vec3 bright = vec3(0.97, 0.78, 0.38);
	vec3 band = vec3(0.52, 0.31, 0.1);
	vec3 low = vec3(0.92, 0.68, 0.3);
	if (t < 0.42) {
		return mix(top, bright, t / 0.42);
	} else if (t < 0.58) {
		return mix(bright, band, (t - 0.42) / 0.16);
	}
	return mix(band, low, clamp((t - 0.58) / 0.3, 0.0, 1.0));
}

#include "res://assets/shaders/death_fx.gdshaderinc"

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	puv = vec3(UV, 1.0);
	cardn = vec2(0.0);
	depth = 0.0;
	vcol = COLOR;
	local = VERTEX;
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
	vec2 suv = uv; // where the art is sampled; the masks below keep using the frame's uv
	if (depth_amount > 0.0) {
		suv = 0.5 + (uv - 0.5) * (1.0 - 2.0 * depth_margin);
		if (parallax != vec2(0.0)) {
			vec2 k = parallax * vec2(1.0, art_aspect) * depth_amount;
			// Two taps: the second reads the depth where the first one landed, so silhouettes keep their shape.
			float d = texture(depth_tex, depth_rect.xy + suv * depth_rect.zw).r;
			vec2 off = (depth_focus - d) * k;
			d = texture(depth_tex, depth_rect.xy + (suv + off) * depth_rect.zw).r;
			off = 0.5 * (off + (depth_focus - d) * k);
			suv += clamp(off, -depth_margin, depth_margin);
		}
	}
	vec2 lua;
	vec2 lub;
	float lw;
	vec4 lm;
	vec4 lx;
	float lpix = living_level > 0 ? fwidth(suv.y) : 0.0; // before any branch that differs between pixels
	if (living_level > 0 && living_uv(suv, lua, lub, lw, lm, lx)) {
		// A legendary's living art (it never plays a video loop).
		c = texture(TEXTURE, lua);
		if (lw > 0.0) {
			c = mix(c, texture(TEXTURE, lub), lw);
		}
		c = living_light(c * vcol, suv, lm, lx, lpix);
	} else if (living_level > 0) {
		c = texture(TEXTURE, suv) * vcol;
	} else if (crop.zw != vec2(1.0)) {
		c = texture(TEXTURE, crop.xy + suv * crop.zw) * vcol;
	} else if (depth_amount > 0.0) {
		c = texture(TEXTURE, suv) * vcol;
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
	if (gild) {
		float t = clamp((local.y - gild_top) / max(1.0, gild_base - gild_top), 0.0, 1.0);
		float hatch = 0.92 + 0.08 * sin(local.y * 2.4 + local.x * 0.35);
		c.rgb = mix(c.rgb, gold_ramp(t) * hatch, smoothstep(0.3, 0.55, max(c.r, max(c.g, c.b))));
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
	if (death_mode > 0) {
		c = death_fx(c, world); // a death in the killer's school (death_fx.gdshaderinc)
	} else if (burn > 0.0) {
		float n = fbm(world * noise_scale);
		float th = burn * 1.3 - 0.15;
		float e = n - th;
		if (e < 0.0) {
			c.a = 0.0;
		} else if (e < 0.1) {
			float k = 1.0 - e / 0.1;
			c.rgb = mix(c.rgb, mix(burn_edge.rgb, burn_hot.rgb, k), k);
			c.rgb *= 1.0 + k * 0.6;
		}
	}
	COLOR = c;
}
