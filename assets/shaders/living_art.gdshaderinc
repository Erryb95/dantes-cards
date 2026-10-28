// Living art (included by card_fx.gdshader): a still card painting brought to life, driven by data/living_art.json
// through ArtLiving (docs/LIVING_ART.md is the authoring guide). Everything is read in the full picture's UV
// (`living_rect` places the card's framed art in it) and weighted by the card's masks (tools/cards/living_mask.py):
//
// assets/cards/living/<id>.png, the base mask (every living card):
//   R flow: the paint drifts along a flow (a flow map: two samples drift and cross-fade every `living_period` seconds,
//     so the picture never tears and always returns to the painting). The flow is the whirl around `living_vortex`
//     (`living_swirl`, with a crisp wave along its arms, `living_churn`) and / or the flow map's own directions
//     (`living_flow_speed`: water, lava, blood, smoke, clouds). R is also how fast it flows there.
//   G fire: flames rise with the flow (`living_rise`); their warm light trembles and breathes, a heat haze shimmers.
//   B sway: hair, cloth, wings and leaves flutter in waves that run down the wind (`living_sway`, `living_wind`).
// assets/cards/living/<id>_flow.png, the flow map (only when the recipe gives directions or ripples):
//   RG the local direction of the flow (0.5 = none, unit vectors in the picture's pixels), B ripple: long wavy crests
//   lying across the picture (water seen from the side) roll toward the viewer, drift along that direction, lift
//   the paint up and down and shimmer (rivers, the Styx, the sea, boiling pitch, molten rock).
// assets/cards/living/<id>_fx.png, three layer slots (only when the entry lists "layers"): each channel is the
//   region of one layer whose kind and parameters come from the entry (living_k0..2, living_s0..2 / t0..2 / c0..2 /
//   d0..2): glow (light that breathes: eyes, lamps, lava, embers in cracks), glint (frost, ice and water sparkle),
//   mist (drifting smoke, fog and cloud), fall (ash, sparks, fire rain, snow, rain, along a direction), flash
//   (lightning, rare), rays (shafts of light), sway (a second flutter with its own wind), haze (heat shimmer),
//   breathe (a slow swell around a centre: a chest, wings).
// Faces are black in every mask (nothing bends them; the recipe may still light eyes over them); figures and "still"
// shapes keep out of the flow so they keep their outline. `living_level`: 0 off (every other card), 1 lite (no heat
// haze, no embers, one layer of falling particles, cheaper noise), 2 full. `living_ext` false (Francesca) runs the
// original path only.

uniform int living_level = 0;
uniform sampler2D living_mask : filter_linear, repeat_disable;
uniform vec4 living_rect = vec4(0.0, 0.0, 1.0, 1.0); // the framed art's 0..1 in the full picture's UV
uniform float living_aspect = 0.727; // the full picture's w / h, so the whirl is round
uniform vec2 living_vortex = vec2(0.5, 0.3);
uniform float living_swirl = 0.0; // flow speed, picture heights per second
uniform float living_spiral = 0.2; // share of the flow that turns inward
uniform float living_churn = 0.0; // the whirl's to-and-fro wave, UV
uniform float living_period = 2.0;
uniform float living_rise = 0.0;
uniform float living_flicker = 0.0;
uniform float living_glow = 0.0;
uniform float living_haze = 0.0;
uniform float living_sway = 0.0;
uniform vec2 living_wind = vec2(1.0, 0.0);
uniform float living_embers = 0.0;
uniform vec3 living_ember_color : source_color = vec3(1.0, 0.62, 0.25);

// The extension (any card but Francesca): the flow map and the three layer slots.
uniform bool living_ext = false;
uniform bool living_has_flowmap = false;
uniform sampler2D living_flowmap : hint_default_black, filter_linear, repeat_disable;
uniform float living_flow_speed = 0.0; // the flow map's speed where R is 1, picture heights per second
uniform float living_ripple = 0.0; // the ripple's bend, picture heights
uniform float living_ripple_scale = 140.0; // crests per picture height x 2 pi (140: a crest every 32 px of a 704 px picture)
uniform float living_ripple_speed = 2.5; // radians per second
uniform float living_ripple_light = 0.15; // how much the crests shimmer
uniform bool living_has_fx = false;
uniform sampler2D living_fx : hint_default_black, filter_linear, repeat_disable;
uniform int living_k0 = 0; // slot kinds: 0 none, 1 glow, 2 glint, 3 mist, 4 fall, 5 flash, 6 rays, 7 sway, 8 haze, 9 breathe
uniform int living_k1 = 0;
uniform int living_k2 = 0;
uniform vec4 living_s0 = vec4(0.0); // each kind's first four parameters (ArtLiving.KINDS)
uniform vec4 living_s1 = vec4(0.0);
uniform vec4 living_s2 = vec4(0.0);
uniform vec4 living_t0 = vec4(0.0); // ... and its next four
uniform vec4 living_t1 = vec4(0.0);
uniform vec4 living_t2 = vec4(0.0);
uniform vec3 living_c0 : source_color = vec3(1.0);
uniform vec3 living_c1 : source_color = vec3(1.0);
uniform vec3 living_c2 : source_color = vec3(1.0);
uniform vec2 living_d0 = vec2(0.0, 1.0); // its direction, a unit vector in the picture's pixels (y down)
uniform vec2 living_d1 = vec2(0.0, 1.0);
uniform vec2 living_d2 = vec2(0.0, 1.0);

// The flow map's direction at a texel (a unit vector in the picture's pixels); the wind where it has none.
vec2 living_dir(vec2 rg) {
	vec2 v = rg * 2.0 - 1.0;
	float l = length(v);
	return l > 0.02 ? v / l : vec2(1.0, 0.0);
}

// The flow at `p` (full UV) in UV per second.
vec2 living_flow(vec2 p, vec4 m, vec3 fm) {
	vec2 d = (p - living_vortex) * vec2(living_aspect, 1.0);
	float r = length(d) + 1e-4;
	vec2 dir = vec2(d.y, -d.x) / r - d / r * living_spiral;
	float v = living_swirl * smoothstep(0.0, 0.14, r) * (0.7 + 0.6 * noise(p * 3.0 + 4.0));
	vec2 f = dir * v * m.r + vec2(0.0, -living_rise) * m.g;
	if (living_ext && living_has_flowmap) {
		f += living_dir(fm.rg) * living_flow_speed * m.r * (0.75 + 0.5 * noise(p * 4.0 + 9.0));
	}
	return f / vec2(living_aspect, 1.0);
}

// Sparks on a field that turns rigidly with the whirl (a rigid turn never smears them), each one born, glowing and
// dying on its own clock. Two layers of cells, one spark at most per cell.
float living_ember_field(vec2 p) {
	vec2 q = (p - living_vortex) * vec2(living_aspect, 1.0);
	float a = TIME * 0.22;
	q = vec2(cos(a) * q.x - sin(a) * q.y, sin(a) * q.x + cos(a) * q.y);
	q.y += TIME * 0.018; // and they rise a little
	float sum = 0.0;
	for (int l = 0; l < 2; l++) {
		float cell = l == 0 ? 0.085 : 0.052;
		vec2 g = q / cell + float(l) * 31.7;
		vec2 id = floor(g);
		float h = hash(id);
		if (h > living_embers * (l == 0 ? 0.55 : 0.7)) {
			continue;
		}
		vec2 at = vec2(hash(id + 3.1), hash(id + 7.7)) * 0.6 + 0.2;
		float life = fract(TIME * (0.16 + 0.14 * hash(id + 1.3)) + h * 7.0);
		float fade = smoothstep(0.0, 0.25, life) * (1.0 - smoothstep(0.55, 1.0, life));
		float rad = 0.045 + 0.035 * hash(id + 9.2);
		vec2 dd = (fract(g) - at) / rad;
		sum += exp(-dot(dd, dd)) * fade * (0.75 + 0.25 * sin(TIME * 11.0 + h * 40.0));
	}
	return sum;
}

// A displacing slot (sway, haze, breathe) at `p` with amount `a`: its shift in UV of the full picture.
vec2 living_slot_shift(int k, float a, vec4 s, vec4 t, vec2 dir, vec2 p) {
	if (k < 7 || a <= 0.002) {
		return vec2(0.0);
	}
	vec2 q = p * vec2(living_aspect, 1.0);
	if (k == 7) { // sway: s = (amount, speed, scale, gust)
		vec2 across = vec2(-dir.y, dir.x);
		float along = dot(q, dir);
		float gust = 1.0 - s.w + s.w * (0.5 + 0.5 * sin(TIME * 0.7 + q.x * 2.0 + q.y));
		float w = sin(along * s.z - TIME * s.y + noise(q * 6.0) * 2.5) + 0.4 * sin(along * s.z * 2.1 - TIME * s.y * 1.7);
		vec2 v = across * w + dir * 0.3 * sin(along * s.z * 0.7 - TIME * s.y * 0.6);
		return v * s.x * a * gust / vec2(living_aspect, 1.0);
	}
	if (k == 8) { // haze: s = (amount, speed, scale)
		if (living_level < 2) {
			return vec2(0.0);
		}
		vec2 hz = vec2(noise(q * s.z + vec2(0.0, TIME * s.y)), noise(q * s.z + vec2(5.2, TIME * s.y))) - 0.5;
		return hz * 2.0 * s.x * a / vec2(living_aspect, 1.0);
	}
	if (k == 9) { // breathe: s = (amount, speed, centre x, centre y), the centre in UV
		return (p - s.zw) * s.x * a * sin(TIME * s.y);
	}
	return vec2(0.0);
}

// Falling (or flying) particles along `dir`: s = (density, speed, size, streak), t = (flutter, brightness, blend, life).
// `pix` is a screen pixel in picture heights: a particle is never drawn smaller than a pixel (it would sparkle on a
// small card), it only grows fainter.
float living_fall(vec2 p, vec4 s, vec4 t, vec2 dir, float pix) {
	vec2 q = p * vec2(living_aspect, 1.0);
	vec2 across = vec2(-dir.y, dir.x);
	float sum = 0.0;
	int layers = living_level > 1 ? 2 : 1;
	for (int l = 0; l < 2; l++) {
		if (l >= layers) {
			break;
		}
		float near = l == 0 ? 1.0 : 0.65; // the second layer is farther: smaller and slower
		float cell = s.z * 10.0 * near;
		vec2 csz = vec2(cell, cell * (1.0 + s.w));
		vec2 g = vec2(dot(q, across), dot(q, dir) - TIME * s.y * near) / csz + float(l) * 17.3;
		vec2 id = floor(g);
		float h = hash(id);
		if (h > s.x * (l == 0 ? 1.0 : 0.8)) {
			continue;
		}
		vec2 at = vec2(hash(id + 3.1), hash(id + 7.7)) * 0.4 + 0.3;
		vec2 d = (fract(g) - at) * csz;
		d.x += t.x * s.z * 2.0 * sin(TIME * (1.3 + h * 2.0) + h * 30.0);
		d.y /= 1.0 + s.w;
		float rad = s.z * (0.7 + 0.6 * hash(id + 9.2)) * near;
		float re = max(rad, pix * 0.8);
		float e = exp(-dot(d, d) / (re * re)) * (rad * rad) / (re * re);
		if (t.w > 0.0) {
			float life = fract(TIME * t.w * (0.7 + 0.6 * hash(id + 1.3)) + h * 7.0);
			e *= smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.6, 1.0, life));
		}
		sum += e * (l == 0 ? 1.0 : 0.6);
	}
	return sum;
}

// Twinkles on the bright paint: s = (strength, density, size, speed), t.x = the paint brightness where they show.
float living_glint(vec2 p, vec4 s, vec4 t, float lum, float pix) {
	vec2 q = p * vec2(living_aspect, 1.0);
	float cell = s.z * 8.0;
	vec2 g = q / cell;
	vec2 id = floor(g);
	float h = hash(id + 0.7);
	if (h > s.y) {
		return 0.0;
	}
	vec2 at = vec2(hash(id + 5.3), hash(id + 2.9)) * 0.6 + 0.2;
	float grow = max(1.0, pix * 0.8 / (s.z * 0.7)); // never under a pixel: fainter instead
	vec2 d = (fract(g) - at) * 8.0 / grow;
	float life = fract(TIME * s.w * (0.6 + 0.8 * hash(id + 4.4)) + h * 13.0);
	float tw = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.2, 0.55, life));
	float r2 = dot(d, d);
	return (exp(-r2 * 2.0) + 0.3 * exp(-r2 * 0.35)) * tw * smoothstep(t.x, t.x + 0.25, lum) / (grow * grow);
}

// A lighting slot over the sampled paint `rgb` at `p` (amount `a`, the paint's luminance `lum`).
vec3 living_slot_light(int k, float a, vec4 s, vec4 t, vec3 col, vec2 dir, vec2 p, vec3 rgb, float lum, float pix) {
	if (k == 0 || k >= 7 || a <= 0.002) {
		return rgb;
	}
	vec2 q = p * vec2(living_aspect, 1.0);
	if (k == 1) { // glow: s = (strength, speed, flicker, spread), t.x = flicker scale
		float breath = 0.5 + 0.5 * sin(TIME * s.y + noise(q * 2.5) * s.w);
		float fl = noise(q * t.x + vec2(0.0, TIME * 2.3));
		float pulse = mix(breath, fl, s.z);
		float g = a * s.x * pulse;
		return rgb * (1.0 + g) + col * g * 0.35;
	}
	if (k == 2) { // glint
		return rgb + col * living_glint(p, s, t, lum, pix) * a * s.x;
	}
	if (k == 3) { // mist: s = (strength, speed, scale, softness)
		vec2 mp = q * s.z - dir * TIME * s.y * s.z + vec2(0.0, TIME * 0.03);
		float n = living_level > 1 ? fbm(mp) : noise(mp * 1.6);
		float veil = smoothstep(0.5 - s.w, 0.5 + s.w, n);
		return mix(rgb, col, veil * a * s.x);
	}
	if (k == 4) { // fall
		float e = living_fall(p, s, t, dir, pix) * a * t.y;
		return mix(rgb + col * e, mix(rgb, col, clamp(e, 0.0, 1.0)), t.z);
	}
	if (k == 5) { // flash: s = (strength, period); every so often a double stroke of light
		float x = TIME / s.y;
		float i = floor(x);
		float dt = (fract(x) - hash(vec2(i, 1.1)) * 0.7) * s.y;
		float env = 0.0;
		if (dt > 0.0 && hash(vec2(i, 3.7)) < 0.8) {
			env = exp(-dt * 10.0) + 0.8 * exp(-abs(dt - 0.2) * 28.0);
		}
		return rgb + col * env * a * s.x * (0.25 + 1.5 * lum);
	}
	if (k == 6) { // rays: s = (strength, speed, scale); shafts along `dir` that slowly shift
		float u = dot(q, vec2(-dir.y, dir.x)) * s.z;
		float n = noise(vec2(u, TIME * s.y)) * 0.6 + noise(vec2(u * 2.7 + 3.1, TIME * s.y * 1.7)) * 0.4;
		return rgb + col * smoothstep(0.45, 0.85, n) * a * s.x;
	}
	return rgb;
}

// Where the painting at `suv` (the framed art's 0..1) is read from now: `ua` and `ub` cross-faded by `w` (equal, w 0,
// where nothing flows). Returns false where every mask is black (a figure, a face): the painting as it is. The caller
// samples (TEXTURE cannot be handed to a function on every renderer) and then calls living_light with `m` and `lx`
// (the layer slots' amounts in xyz, the ripple's shimmer in w).
bool living_uv(vec2 suv, out vec2 ua, out vec2 ub, out float w, out vec4 m, out vec4 lx) {
	vec2 p = living_rect.xy + suv * living_rect.zw;
	m = texture(living_mask, p);
	lx = vec4(0.0);
	vec3 fm = vec3(0.5, 0.5, 0.0);
	ua = suv;
	ub = suv;
	w = 0.0;
	if (living_ext) {
		if (living_has_flowmap) {
			fm = texture(living_flowmap, p).rgb;
		}
		if (living_has_fx) {
			lx.xyz = texture(living_fx, p).rgb;
		}
	}
	if (m.r + m.g + m.b < 0.004 && (!living_ext || fm.b + lx.x + lx.y + lx.z < 0.004)) {
		return false;
	}
	vec2 to_suv = 1.0 / living_rect.zw;
	// Hair and cloth: waves running down the wind bend them across it.
	vec2 wind = normalize(living_wind);
	vec2 across = vec2(-wind.y, wind.x);
	vec2 still = vec2(0.0);
	if (m.b > 0.0) {
		float along = dot(p, wind);
		float s = sin(along * 34.0 - TIME * 2.4 + noise(p * 9.0) * 2.5) + 0.45 * sin(along * 71.0 - TIME * 4.1);
		still += (across * s + wind * 0.35 * sin(along * 23.0 - TIME * 1.6)) * living_sway * m.b;
	}
	if (m.r > 0.0) {
		// The whirl churns: a crisp wave runs out along its spiral arms, pushing the paint to and fro along the rings.
		vec2 d = (p - living_vortex) * vec2(living_aspect, 1.0);
		float r = length(d) + 1e-4;
		float wave = sin(r * 24.0 - TIME * 1.6 + atan(d.y, d.x));
		still += vec2(d.y, -d.x) / r / vec2(living_aspect, 1.0) * wave * living_churn * m.r * smoothstep(0.0, 0.14, r);
	}
	if (living_level > 1 && m.g > 0.0) {
		vec2 hz = vec2(noise(p * vec2(30.0, 16.0) + vec2(0.0, TIME * 1.6)),
			noise(p * vec2(30.0, 16.0) + vec2(5.2, TIME * 1.6))) - 0.5;
		still += hz * 2.0 * living_haze * m.g;
	}
	if (living_ext) {
		if (fm.b > 0.004 && living_ripple > 0.0) {
			// Ripples on water seen from the side: long, wavy crests lying across the picture roll toward the viewer and
			// drift with the flow, lifting the paint up and down; the crests catch the light. Patchy, never a grid.
			vec2 dir = living_dir(fm.rg);
			float k = living_ripple_scale;
			vec2 rp = p * vec2(living_aspect, 1.0) - dir * TIME * max(living_flow_speed, 0.004);
			float warp = noise(rp * vec2(k * 0.05, k * 0.18)) * 5.0 + noise(rp * vec2(k * 0.13, k * 0.45)) * 1.5;
			float s = sin(rp.y * k + warp - TIME * living_ripple_speed);
			s *= 0.35 + 0.9 * noise(rp * vec2(k * 0.06, k * 0.16) + vec2(TIME * 0.12, 0.0));
			still += vec2(dir.x * 0.35, 1.0) * s * living_ripple * fm.b / vec2(living_aspect, 1.0);
			lx.w = s * fm.b;
		}
		if (living_has_fx) {
			still += living_slot_shift(living_k0, lx.x, living_s0, living_t0, living_d0, p);
			still += living_slot_shift(living_k1, lx.y, living_s1, living_t1, living_d1, p);
			still += living_slot_shift(living_k2, lx.z, living_s2, living_t2, living_d2, p);
		}
	}
	if (m.r + m.g > 0.004) {
		vec2 flow = living_flow(p, m, fm) * living_period;
		float ph = TIME / living_period + noise(p * 2.5) * 1.5;
		float f0 = fract(ph);
		float f1 = fract(ph + 0.5);
		ua = suv + (still - flow * (f0 - 0.5)) * to_suv;
		ub = suv + (still - flow * (f1 - 0.5)) * to_suv;
		w = smoothstep(0.1, 0.9, abs(1.0 - 2.0 * f0)); // short cross-fades: less double image
	} else {
		ua = suv + still * to_suv;
		ub = ua;
	}
	return true;
}

// The living light over the sampled painting `c` at `suv` (`m` and `lx` from living_uv; `pix` the size of a screen
// pixel in the framed art's UV height, fwidth(suv.y), taken where every pixel runs the same code).
vec4 living_light(vec4 c, vec2 suv, vec4 m, vec4 lx, float pix) {
	vec2 p = living_rect.xy + suv * living_rect.zw;
	// Firelight: where the flames are, their own warm paint trembles and breathes.
	float warm = clamp((c.r - c.b) * 2.4 - 0.15, 0.0, 1.0) * m.g;
	if (warm > 0.0) {
		vec2 fp = p * vec2(7.0, 3.5) + vec2(0.0, TIME * 0.85);
		float n = living_level > 1 ? fbm(fp) : noise(fp);
		float breath = 0.5 + 0.5 * sin(TIME * 1.15 + p.y * 5.0 + p.x * 2.0);
		c.rgb *= 1.0 + warm * living_flicker * (n - 0.5) * 2.2;
		c.rgb += living_ember_color * warm * living_glow * breath;
	}
	if (living_ext) {
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		if (lx.w != 0.0) {
			c.rgb *= 1.0 + living_ripple_light * lx.w * (0.3 + lum);
		}
		if (living_has_fx) {
			c.rgb = living_slot_light(living_k0, lx.x, living_s0, living_t0, living_c0, living_d0, p, c.rgb, lum, pix * living_rect.w);
			c.rgb = living_slot_light(living_k1, lx.y, living_s1, living_t1, living_c1, living_d1, p, c.rgb, lum, pix * living_rect.w);
			c.rgb = living_slot_light(living_k2, lx.z, living_s2, living_t2, living_c2, living_d2, p, c.rgb, lum, pix * living_rect.w);
		}
	}
	if (living_level > 1 && living_embers > 0.0) {
		float e = living_ember_field(p) * clamp((m.r + m.g) * 1.5, 0.0, 1.0);
		c.rgb += living_ember_color * e * 1.1 * c.a;
		c.rgb += vec3(1.0, 0.9, 0.7) * e * e * 0.5 * c.a; // white-hot cores
	}
	return c;
}
