shader_type canvas_item;
// Dark side of a minion's landing: the crushed hollow, the cracks as dark seams and the dust ring rolling outward.
#include "res://assets/shaders/landing.gdshaderinc"

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float fade = 1.0 - smoothstep(0.55, 1.0, t);
	// The hollow pressed into the ground under the minion.
	float hollow = exp(-r * r * 14.0) * 0.45 * (1.0 - smoothstep(0.2, 0.9, t));
	float seams = cracks(p) * 0.9 * fade;
	// Dust ring: a soft, lumpy band that races out and thins.
	float k = 1.0 - pow(1.0 - t, 3.0);
	float rr = mix(0.12, 0.98, k);
	float band = 0.05 + 0.16 * k;
	float lump = 0.55 + 0.45 * vnoise(vec2(a * 5.0, t * 3.0));
	float lump2 = vnoise(vec2(a * 11.0 + 3.0, r * 6.0 - t * 2.0));
	float dust = exp(-pow((r - rr) / band, 2.0)) * lump * (0.4 + 0.6 * lump2) * 0.38 * (1.0 - smoothstep(0.2, 1.0, t));
	vec3 dust_col = vec3(0.36, 0.31, 0.27);
	vec3 dark = vec3(0.05, 0.03, 0.02);
	float a_dark = clamp(hollow + seams, 0.0, 1.0);
	float alpha = clamp(a_dark + dust, 0.0, 0.9) * (1.0 - smoothstep(0.92, 1.0, r));
	vec3 col = mix(dust_col, dark, a_dark / max(a_dark + dust, 0.001));
	COLOR = vec4(col, alpha);
}
