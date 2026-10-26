shader_type canvas_item;
render_mode blend_add;
// Animated selection aura around a card (rounded rectangle) or a portrait (ellipse): soft glow, tongues of
// spectral fire licking outward along the edge, and a bright spark that runs around the rim. Drawn on a ColorRect
// larger than the shape (`margin` px on every side); nothing is drawn inside the shape.

uniform int shape = 0; // 0 rounded rectangle, 1 ellipse
uniform vec2 rect_size = vec2(330.0, 440.0); // the ColorRect's size in px
uniform float margin = 40.0;
uniform float corner = 18.0; // px, rounded rectangle only
uniform vec4 core_color : source_color = vec4(0.8, 1.0, 0.65, 1.0);
uniform vec4 edge_color : source_color = vec4(0.1, 0.85, 0.3, 1.0);
uniform float strength : hint_range(0.0, 1.5) = 1.0;
uniform float speed = 1.0;
uniform float seed = 0.0;
// Same fake-3D tilt as card_fx.gdshader, so a card's aura leans with the card (set by CardView).
uniform vec2 tilt = vec2(0.0);
uniform vec2 card_center = vec2(0.0);
uniform vec2 card_x = vec2(1.0, 0.0);
uniform vec2 card_y = vec2(0.0, 1.0);
uniform float half_h = 180.0;
uniform float cam_dist = 2.6;

void vertex() {
	if (tilt != vec2(0.0)) {
		vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		vec2 d = world - card_center;
		vec2 n = vec2(dot(d, card_x) / dot(card_x, card_x), dot(d, card_y) / dot(card_y, card_y)) / half_h;
		float z = -(n.x * sin(tilt.x) + n.y * sin(tilt.y));
		float w = cam_dist / (cam_dist - z);
		vec2 q = vec2(n.x * cos(tilt.x), n.y * cos(tilt.y)) * w * half_h;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(card_center + card_x * q.x + card_y * q.y, 0.0, 1.0)).xy;
	}
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 - 1.3) * 0.1;
}

// Signed distance (px) to the shape; > 0 outside.
float sdf(vec2 p) {
	vec2 half_shape = rect_size * 0.5 - vec2(margin);
	if (shape == 1) {
		float r = min(half_shape.x, half_shape.y);
		return (length(p / half_shape) - 1.0) * r;
	}
	vec2 q = abs(p) - half_shape + vec2(corner);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = sdf(p);
	if (d < -1.5) {
		COLOR = vec4(0.0);
	} else {
		float t = TIME * speed + seed * 13.0;
		// Position along the outline: the angle, scaled so the fire tongues keep a similar width on any size.
		float ang = atan(p.y, p.x);
		float perim = (rect_size.x + rect_size.y - 4.0 * margin) * 0.16;
		float u = ang / 6.28318 * perim;
		float x = max(d, 0.0) / margin; // 0 at the edge, 1 at the outer border of the rect
		// Flames: noise that scrolls outward, carved by height so tongues taper into wisps.
		float n = fbm(vec2(u * 0.9, x * 2.2 - t * 1.6));
		float tongues = smoothstep(0.0, 1.0, n * 1.35 - x * 1.15);
		float glow = exp(-x * 4.0) * 0.55;
		float rim = exp(-max(d, 0.0) * 0.35) * 0.9; // the bright line hugging the edge
		// A spark running around the rim, with a soft trail behind it.
		float run = fract(ang / 6.28318 - t * 0.18);
		float spark = pow(1.0 - run, 10.0) * exp(-max(d, 0.0) * 0.12) * 1.4;
		float a = clamp(glow + tongues * 0.95 + rim * (0.55 + 0.45 * sin(t * 3.0)) + spark, 0.0, 2.0);
		a *= smoothstep(1.0, 0.75, x) * smoothstep(-1.5, 0.5, d) * strength;
		vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(tongues * 0.6 + rim * 0.7 + spark, 0.0, 1.0));
		COLOR = vec4(col, a);
	}
}
