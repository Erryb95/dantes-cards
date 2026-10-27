shader_type canvas_item;
// Gilded letters for headings set in a font (names, arenas: the ones with no painted words): the fill turns to
// engraved gold metal, pale at the top of the capitals, a dark burnished band under their middle and a warm lower
// half, with fine horizontal hatching like an engraving. The dark outline is left as it is.

uniform float cap_top = 0.0; // the capitals' top and the baseline, in the label's own pixels
uniform float baseline = 64.0;
uniform vec4 tint : source_color = vec4(1.0); // the heading's colour: gold stays gold, ember names go copper

varying vec2 local;

void vertex() {
	local = VERTEX;
}

vec3 ramp(float t) {
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

void fragment() {
	vec4 c = COLOR;
	float lum = max(c.r, max(c.g, c.b));
	float t = clamp((local.y - cap_top) / max(1.0, baseline - cap_top), 0.0, 1.0);
	float hatch = 0.92 + 0.08 * sin(local.y * 2.4 + local.x * 0.35);
	vec3 metal = ramp(t) * hatch * mix(vec3(1.0), tint.rgb / max(0.001, max(tint.r, max(tint.g, tint.b))), 0.55);
	c.rgb = mix(c.rgb, metal, smoothstep(0.3, 0.55, lum)); // only the bright fill, not the dark outline
	COLOR = c;
}
