class_name IntroSubtitleStyle
extends RefCounted
## Look of the intro subtitles: the verse serif in warm bone, a soft dark outline, and a feathered dark pool behind
## the words (radial, no edges, no rectangles).

const TEXT := Color(1.0, 0.95, 0.84)
const OUTLINE := Color(0.03, 0.02, 0.015, 0.78)

static var _pool: GradientTexture2D


## Feathered dark ellipse: dark centre fading smoothly to nothing. Stretch it behind a text block.
static func pool() -> GradientTexture2D:
	if _pool == null:
		_pool = GradientTexture2D.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.8, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.14), Color(0, 0, 0, 0)])
		_pool.gradient = g
		_pool.fill = GradientTexture2D.FILL_RADIAL
		_pool.fill_from = Vector2(0.5, 0.5)
		_pool.fill_to = Vector2(1.0, 0.5)
		_pool.width = 256
		_pool.height = 256
	return _pool


## Draws one centred line on a CanvasItem: soft wide outline pass, then the bone text.
static func draw_line_centered(ci: CanvasItem, font: Font, text: String, cx: float, baseline: float, fs: int,
		color: Color, alpha: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(cx - w * 0.5, baseline)
	var ow := maxi(int(fs * 0.16), 3)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, Color(OUTLINE, OUTLINE.a * alpha * 0.7))
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(ow / 2, 2), Color(OUTLINE, OUTLINE.a * alpha))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, alpha))
