// Living art (included by card_fx.gdshader): a legendary's still painting brought to life, driven by data/living_art.json
// through ArtLiving. Everything is read in the full picture's UV (`living_rect` places the card's framed art in it) and
// weighted by the card's mask (assets/cards/living/<id>.png): R the whirl, G the flames, B hair and cloth.
// - The whirl: the paint flows around `living_vortex` (a flow map: two samples drift along the flow and cross-fade
//   every `living_period` seconds, so the picture never tears and always returns to the painting).
//   A crisp wave also runs along the whirl's arms (`living_churn`), so the motion reads without blurring the engraving.
// - The flames rise with it; their light trembles (moving noise) and breathes, and a heat haze shimmers over them.
// - Hair and cloth flutter in waves that run down the wind.
// - Embers turn with the whirl, born and dying in the flame-lit air.
// Faces, figures and the birds are black in the mask, so they never bend. `living_level`: 0 off (every other card),
// 1 lite (no haze, no embers, cheaper noise), 2 full.

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

// The flow at `p` (full UV) in UV per second.
vec2 living_flow(vec2 p, vec4 m) {
	vec2 d = (p - living_vortex) * vec2(living_aspect, 1.0);
	float r = length(d) + 1e-4;
	vec2 dir = vec2(d.y, -d.x) / r - d / r * living_spiral;
	float v = living_swirl * smoothstep(0.0, 0.14, r) * (0.7 + 0.6 * noise(p * 3.0 + 4.0));
	vec2 f = dir * v * m.r + vec2(0.0, -living_rise) * m.g;
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

// Where the painting at `suv` (the framed art's 0..1) is read from now: `ua` and `ub` cross-faded by `w` (equal, w 0,
// where nothing flows). Returns false where the mask is black (a figure, a face): the painting as it is. The caller
// samples (TEXTURE cannot be handed to a function on every renderer) and then calls living_light.
bool living_uv(vec2 suv, out vec2 ua, out vec2 ub, out float w, out vec4 m) {
	vec2 p = living_rect.xy + suv * living_rect.zw;
	m = texture(living_mask, p);
	ua = suv;
	ub = suv;
	w = 0.0;
	if (m.r + m.g + m.b < 0.004) {
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
	if (m.r + m.g > 0.004) {
		vec2 flow = living_flow(p, m) * living_period;
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

// The living light over the sampled painting `c` at `suv` (`m` from living_uv).
vec4 living_light(vec4 c, vec2 suv, vec4 m) {
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
	if (living_level > 1 && living_embers > 0.0) {
		float e = living_ember_field(p) * clamp((m.r + m.g) * 1.5, 0.0, 1.0);
		c.rgb += living_ember_color * e * 1.1 * c.a;
		c.rgb += vec3(1.0, 0.9, 0.7) * e * e * 0.5 * c.a; // white-hot cores
	}
	return c;
}
