shader_type canvas_item;
render_mode blend_add;
// Bright side of a minion's landing: hellfire glowing up through the fresh cracks, cooling from white-hot to the
// minion's rarity colour and out, plus a brief flash at the point of impact.
#include "res://assets/shaders/landing.gdshaderinc"

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float heat = 1.0 - smoothstep(0.1, 0.85, t);
	float c = cracks(p);
	// Wide soft bloom around the seams: the fire lights the stone around each crack.
	float bloom = 0.0;
	// Five taps keep it cheap enough for phones (each tap walks every crack).
	for (int i = 0; i < 5; i++) {
		float ang = float(i) * 1.2566 + 0.3;
		bloom += cracks(p + vec2(cos(ang), sin(ang)) * 0.035);
	}
	bloom *= 0.2;
	float k = (0.8 + 0.5 * power) * heat;
	// Pulsing embers along the seams as they cool.
	float pulse = 0.8 + 0.2 * sin(t * 40.0 + r * 30.0);
	// Hellfire core in every seam (white-hot, then orange), the rarity colour as the halo around it.
	vec3 core = mix(vec3(0.95, 0.3, 0.04), vec3(1.0, 0.68, 0.25), heat * heat);
	vec3 halo = mix(vec3(1.0, 0.4, 0.08), glow.rgb, 0.55);
	vec3 col = core * c * 1.5 * k * pulse + halo * bloom * 0.9 * k;
	float flash = exp(-r * r * 30.0) * (1.0 - smoothstep(0.0, 0.18, t)) * 1.4;
	col += vec3(1.0, 0.8, 0.5) * flash;
	COLOR = vec4(col, 1.0);
}
