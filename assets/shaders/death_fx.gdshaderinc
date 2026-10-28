// Deaths in the killer's school (scripts/battle/death_fx.gd). Included by card_fx.gdshader, which calls death_fx()
// in place of its plain burn while death_mode > 0. Uses card_fx's hash / noise / fbm and its `burn` (the dissolve,
// 0..1), `burn_edge` / `burn_hot` (the rim: outer colour, white-hot cut) and `noise_scale`.
// `death_pre` (0..1) is the look that comes before the dissolve: scorch, tar, frost, sickness, pallor, stone,
// gilding, a white wash. Every piece of a card dies as one sheet: positions are in canvas space, measured against
// the piece's centre and half size.
// Modes: 1 burn (fire, judgment), 2 tar (pitch), 3 shatter (ice), 4 melt (venom), 5 spirit (soul, shadow),
// 6 crumble (stone), 7 shred (wind), 8 sink (water), 9 rend (blood, plain blows, thorn), 10 fade (holy, word),
// 11 coins (gold).

uniform int death_mode = 0;
uniform float death_pre : hint_range(0.0, 1.0) = 0.0;
uniform vec2 death_center = vec2(0.0); // the piece's centre, canvas space
uniform vec2 death_half = vec2(58.0, 74.0); // its half size, canvas pixels
uniform vec2 death_dir = vec2(0.0, -1.0); // the blow's direction (killer to victim), unit
uniform vec2 death_hit = vec2(0.0); // where the blow landed, in the piece's -1..1 frame (+y down)
uniform vec4 death_accent : source_color = vec4(0.0); // the victim's own school: a thin line inside the rim (a = how much)
uniform float death_seed = 0.0;

float dfx_lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

// Cells: x = distance to the nearest seed, y = distance to the cell's border (F2 - F1), z = the cell's own random.
vec3 dfx_cells(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + vec2(hash(n + g), hash(n + g + vec2(17.3, 5.1))) - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash(n + g + vec2(3.7, 9.2));
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	f1 = sqrt(f1);
	return vec3(f1, sqrt(f2) - f1, id);
}

// The dissolve's threshold for a field that runs lo..hi with a rim `w` wide: nothing is cut at burn 0, all at 1.
float dfx_th(float lo, float hi, float w) {
	return mix(lo - w - 0.01, hi + 0.01, burn);
}

// Cuts where e < 0 and lights the band 0..w: the rim (burn_edge outside, burn_hot at the cut) with the victim's
// accent as a thin line inside it.
vec4 dfx_rim(vec4 c, float e, float w, float glow) {
	if (e < 0.0) {
		c.a = 0.0;
	} else if (e < w) {
		float k = 1.0 - e / w;
		vec3 rim = mix(burn_edge.rgb, burn_hot.rgb, k * k);
		float acc = death_accent.a * exp(-pow((k - 0.4) * 4.5, 2.0));
		rim = mix(rim, death_accent.rgb, acc);
		c.rgb = mix(c.rgb, rim, k);
		c.rgb *= 1.0 + k * glow;
	}
	return c;
}

vec4 death_fx(vec4 c, vec2 w) {
	vec2 p = (w - death_center) / max(death_half, vec2(1.0));
	vec2 dir = normalize(death_dir + vec2(1e-5, 0.0));
	float n = fbm(w * noise_scale + death_seed);
	float lum = dfx_lum(c.rgb);
	float pre = clamp(death_pre, 0.0, 1.0);
	float y = p.y * 0.5 + 0.5; // 0 at the top, 1 at the bottom
	if (death_mode == 1) {
		// burn: the edges char and glow, then a fire line eats inward
		float d = length(p * vec2(0.92, 0.9));
		float edge = smoothstep(0.4, 1.05, d + (n - 0.5) * 0.5);
		c.rgb *= 1.0 - 0.75 * edge * pre;
		c.rgb += burn_edge.rgb * 0.4 * pre * edge * (0.5 + 0.5 * n);
		float v = clamp((1.15 - d) * 0.65 + n * 0.55, 0.0, 1.3);
		c = dfx_rim(c, v - dfx_th(0.0, 1.3, 0.14), 0.14, 0.7);
	} else if (death_mode == 2) {
		// tar: black pitch runs down over it in drips, a dull ember line at its front, then it burns away under it
		float drip = noise(vec2(p.x * 5.0 + death_seed, 0.5)) * 0.35 + noise(vec2(p.x * 13.0, 2.0)) * 0.12;
		float front = pre * 1.6 - y - drip * pre;
		float tar = smoothstep(0.0, 0.05, front);
		vec3 black = vec3(0.025, 0.018, 0.015) + vec3(1.0, 0.7, 0.45) * pow(n, 5.0) * 0.9;
		c.rgb = mix(c.rgb, black, tar * 0.93);
		c.rgb += burn_edge.rgb * 0.7 * (smoothstep(-0.02, 0.02, front) - smoothstep(0.02, 0.09, front)) * pre;
		float v = clamp(n * 0.8 + (1.0 - y) * 0.45, 0.0, 1.3);
		c = dfx_rim(c, v - dfx_th(0.0, 1.3, 0.16), 0.16, 0.5);
	} else if (death_mode == 3) {
		// shatter: frost spreads from the blow and cracks it; then it breaks into shards, nearest the blow first
		vec3 cell = dfx_cells(p * vec2(3.4, 2.8) + death_seed);
		float from_hit = length(p - death_hit);
		float reach = pre * 2.8;
		float frost = 1.0 - smoothstep(reach - 0.5, reach, from_hit + (n - 0.5) * 0.6);
		vec3 ice = mix(vec3(lum) * vec3(0.75, 0.9, 1.08) + vec3(0.12, 0.2, 0.3), burn_hot.rgb, 0.25);
		c.rgb = mix(c.rgb, ice, frost * 0.85);
		float crack = (1.0 - smoothstep(0.0, 0.05, cell.y)) * frost;
		c.rgb = mix(c.rgb, burn_hot.rgb * 1.5, crack * pre);
		c.rgb += burn_hot.rgb * crack * burn * 0.8;
		float v = clamp(cell.z * 0.75 + from_hit * 0.2, 0.0, 1.1);
		c = dfx_rim(c, v - dfx_th(0.0, 1.1, 0.08), 0.08, 0.8);
	} else if (death_mode == 4) {
		// melt: sickly green creeps down from the top, then it runs off in drips, top first
		float col = noise(vec2(p.x * 6.0 + death_seed, 1.7));
		float streak = fbm(vec2(p.x * 9.0, p.y * 1.2) + death_seed);
		float sick = clamp(pre * 1.6 - y + (streak - 0.5) * 0.5, 0.0, 1.0);
		c.rgb = mix(c.rgb, vec3(lum) * vec3(0.55, 1.0, 0.35) * 0.9 + burn_edge.rgb * 0.15, sick * 0.75);
		float v = clamp(y * 0.8 + col * 0.35 + streak * 0.25 - 0.1, 0.0, 1.3);
		c = dfx_rim(c, v - dfx_th(0.0, 1.3, 0.12), 0.12, 0.6);
	} else if (death_mode == 5) {
		// spirit: drained pale, then drawn upward into thin streaks
		c.rgb = mix(c.rgb, vec3(lum) * burn_hot.rgb * 1.25, pre * 0.65);
		float streak = fbm(vec2(p.x * 11.0 + death_seed, p.y * 0.9 + burn * 1.5));
		float v = clamp(y * 0.55 + streak * 0.7 - 0.1, 0.0, 1.2);
		c = dfx_rim(c, v - dfx_th(0.0, 1.2, 0.2), 0.2, 0.9);
	} else if (death_mode == 6) {
		// crumble: it turns to grey stone from the blow and cracks, then falls apart in chunks, bottom first
		float from_hit = length(p - death_hit);
		float stone = 1.0 - smoothstep(pre * 2.8 - 0.4, pre * 2.8, from_hit + (n - 0.5) * 0.5);
		float grain = noise(w * 0.35) * 0.18 + n * 0.25;
		vec3 grey = vec3(lum * 0.7 + 0.18) * vec3(0.92, 0.88, 0.82) * (0.8 + grain);
		c.rgb = mix(c.rgb, grey, stone * 0.92);
		vec3 cell = dfx_cells(p * vec2(4.5, 3.8) + death_seed);
		float crack = (1.0 - smoothstep(0.0, 0.07, cell.y)) * smoothstep(0.45, 1.0, pre) * stone;
		c.rgb *= 1.0 - crack * 0.75;
		float v = clamp(cell.z * 0.55 + (1.0 - y) * 0.55, 0.0, 1.1);
		c = dfx_rim(c, v - dfx_th(0.0, 1.1, 0.06), 0.06, 0.1);
	} else if (death_mode == 7) {
		// shred: torn into strips along the gust, the side facing the killer first
		vec2 q = vec2(dot(p, dir), dot(p, vec2(-dir.y, dir.x)));
		float shred = fbm(vec2(q.x * 1.4 - burn * 2.5, q.y * 8.0) + death_seed);
		c.rgb = mix(c.rgb, c.rgb * 0.8 + burn_hot.rgb * 0.2, pre * 0.5);
		float v = clamp((q.x * 0.5 + 0.5) * 0.6 + shred * 0.6, 0.0, 1.3);
		c = dfx_rim(c, v - dfx_th(0.0, 1.3, 0.1), 0.1, 0.5);
	} else if (death_mode == 8) {
		// sink: soaked blue with moving light, then a waterline rises over it in waves
		float wave = sin(p.x * 7.0 + burn * 14.0 + death_seed) * 0.05 + sin(p.x * 13.0 - burn * 9.0) * 0.025;
		float caust = pow(noise(w * 0.05 + vec2(0.0, burn * 3.0)), 3.0);
		c.rgb = mix(c.rgb, c.rgb * vec3(0.55, 0.78, 1.05) + burn_hot.rgb * caust * 0.6, pre * 0.6);
		float v = clamp((1.0 - y) * 0.9 + wave + n * 0.15, 0.0, 1.2);
		c = dfx_rim(c, v - dfx_th(0.0, 1.2, 0.07), 0.07, 0.9);
	} else if (death_mode == 9) {
		// rend: split open along a cut through the point of impact, and torn outward from there
		vec2 r = p - death_hit;
		float across = abs(dot(r, dir));
		c.rgb = mix(c.rgb, burn_edge.rgb * 0.8, pre * 0.6 * exp(-across * 5.0));
		c.rgb *= 1.0 - pre * 0.25;
		float v = clamp(across * 1.3 + length(r) * 0.35 + (n - 0.5) * 0.45, 0.0, 1.4);
		c = dfx_rim(c, v - dfx_th(0.0, 1.4, 0.1), 0.1, 0.5);
	} else if (death_mode == 10) {
		// fade: washed out to white light, then it comes apart into fine motes
		// (the painting stays faintly readable under the light: a pure white blob read as a hole)
		c.rgb = mix(c.rgb, vec3(dfx_lum(c.rgb)) * burn_hot.rgb * 1.4, pre * 0.6) + burn_hot.rgb * pre * 0.1;
		float grain = hash(floor(w / 5.0) + death_seed);
		float v = clamp(grain * 0.35 + n * 0.75, 0.0, 1.1);
		c = dfx_rim(c, v - dfx_th(0.0, 1.1, 0.16), 0.16, 0.5);
		c.a *= 1.0 - burn * 0.35;
	} else if (death_mode == 11) {
		// coins: it turns to gold and breaks into coins that drop out, the bottom first
		vec3 gold = mix(vec3(0.45, 0.28, 0.08), vec3(1.0, 0.88, 0.5), smoothstep(0.1, 0.8, lum)) * (0.9 + 0.3 * n);
		c.rgb = mix(c.rgb, gold, pre * 0.9);
		vec2 cs = w / 13.0 + death_seed;
		float inside = 1.0 - smoothstep(0.36, 0.44, length(fract(cs) - 0.5));
		c.rgb *= mix(1.0, 0.55 + 0.6 * inside, pre);
		float v = clamp(hash(floor(cs)) * 0.55 + (1.0 - y) * 0.5 - (1.0 - inside) * 0.25 + 0.2, 0.0, 1.25);
		c = dfx_rim(c, v - dfx_th(0.0, 1.25, 0.08), 0.08, 0.6);
	}
	return c;
}
