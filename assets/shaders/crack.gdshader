shader_type canvas_item;
render_mode blend_add; // pure light, added on top of the crack painted in the board
// A jagged crack across the middle band of the board: the ember rift of Dis or the frost crack of Cocytus.
// The band is a ColorRect; the crack wanders around UV.y = 0.5. Light flows along it, sparse glints twinkle on it,
// and up to 4 touch flares (flares[i] = vec4(x, y, start_time, strength) in UV space) run out from a finger.

uniform vec4 core_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 rime_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float aspect = 12.0;        // band width / height
uniform float core_width = 0.03;    // in band heights
uniform float glow_width = 0.12;
uniform float wander = 0.4;         // how far the crack strays from the centre line
uniform float flow_speed = 0.35;    // light pulses running along the crack
uniform float glint_amount = 0.0;   // 0..1 twinkling points on the crack
uniform float rime_amount = 0.0;    // 0..1 frosty fringe
uniform float intensity = 1.0;
uniform float seed = 0.0;           // a different crack per arena
uniform float angular = 0.0;        // 0 = wandering rift, 1 = straight ice fractures
uniform vec4 flares[4];
uniform float now = 0.0;

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

// Centre line of a crack (in UV.y) at band x (in band heights).
float path(float x, float s) {
	s += seed;
	float big = (noise(vec2(x * 0.22, s)) - 0.5) * 1.6 + (noise(vec2(x * 0.9, s + 7.0)) - 0.5) * 0.7;
	float jag = (noise(vec2(x * 4.5, s + 3.0)) - 0.5) * 0.45 + (noise(vec2(x * 13.0, s + 5.0)) - 0.5) * 0.18;
	// Ice splits in straight runs: a polyline through random points, blended in by `angular`.
	float c = floor(x * 0.7);
	float k = fract(x * 0.7);
	float poly = (mix(hash(vec2(c, s)), hash(vec2(c + 1.0, s)), k) - 0.5) * 1.4;
	float c2 = floor(x * 3.0);
	poly += (mix(hash(vec2(c2, s + 1.0)), hash(vec2(c2 + 1.0, s + 1.0)), fract(x * 3.0)) - 0.5) * 0.3;
	return clamp(0.5 + mix(big + jag, poly, angular) * wander, 0.24, 0.76);
}

void fragment() {
	float x = UV.x * aspect;
	float y = UV.y;
	float t = TIME;
	// Main crack and a fainter branch that splits off and rejoins.
	float d = abs(y - path(x, 1.7));
	float branch_on = smoothstep(0.55, 0.75, noise(vec2(x * 0.5, 9.0)));
	float d2 = abs(y - path(x + 3.1, 5.3) * 0.9 - 0.05) + (1.0 - branch_on) * 0.5;
	float w = core_width * (0.6 + 0.8 * noise(vec2(x * 1.3, 2.0)));
	float core = smoothstep(w, w * 0.25, d) + 0.55 * smoothstep(w * 0.6, w * 0.1, d2);
	float glow = exp(-d / glow_width) + 0.5 * exp(-d2 / (glow_width * 0.6));
	// Molten / cold light pulsing along the crack.
	float flow = 0.55 + 0.45 * noise(vec2(x * 0.8 - t * flow_speed, t * 0.15));
	flow *= 0.85 + 0.15 * sin(t * 1.7 + x * 0.6);
	// Touch flares: a bright front running out along the crack from the finger.
	float fl = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 r = flares[i];
		float age = now - r.z;
		if (age > 0.0 && age < 1.8 && r.w > 0.0) {
			float dx = abs(UV.x - r.x) * aspect;
			float front = exp(-abs(dx - age * 3.0) * 2.5) + exp(-dx * 1.2) * (1.0 - age / 1.8);
			fl += front * (1.0 - age / 1.8) * r.w;
		}
	}
	float k = flow * intensity * (1.0 + fl * 1.6);
	vec3 col = glow_color.rgb * glow_color.a * glow * k + core_color.rgb * core_color.a * core * k;
	// Glints: sparse cells along the crack that flash like stars.
	if (glint_amount > 0.0) {
		float cx = floor(x * 3.0);
		float h = hash(vec2(cx, 0.0));
		float on = step(1.0 - glint_amount * 0.6, h);
		float tw = pow(max(0.0, sin(t * (1.2 + h * 2.5) + h * 40.0)), 24.0);
		vec2 c = vec2((cx + 0.5) / 3.0, path((cx + 0.5) / 3.0, 1.7));
		vec2 q = vec2(x - c.x, y - c.y);
		float star = exp(-abs(q.x) * 60.0) * exp(-abs(q.y) * 10.0) + exp(-abs(q.y) * 60.0) * exp(-abs(q.x) * 10.0);
		star = star * 0.8 + exp(-length(q) * 40.0);
		col += vec3(1.0) * star * tw * on * (1.0 + fl * 2.0);
	}
	// Rime: a frosty, crystalline fringe that hugs the crack.
	if (rime_amount > 0.0) {
		float fr = fbm(vec2(x * 3.0, y * 9.0)) * exp(-d / (glow_width * 2.2));
		col += rime_color.rgb * rime_color.a * smoothstep(0.25, 0.6, fr) * rime_amount;
	}
	// Fade out at the band's top, bottom and the screen edges.
	float edge = smoothstep(0.0, 0.18, y) * smoothstep(1.0, 0.82, y) * smoothstep(0.0, 0.03, UV.x) * smoothstep(1.0, 0.97, UV.x);
	COLOR = vec4(col, edge);
}
