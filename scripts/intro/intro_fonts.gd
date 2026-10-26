class_name IntroFonts
extends RefCounted
## Fonts of the cinematic (both SIL OFL, see assets/CREDITS.md): IM Fell English (17th-century
## engraver's type, for verses and the story card) and Cinzel (inscription / titles).

const BONE := Color(0.89, 0.83, 0.71)
const EMBER := Color(0.94, 0.47, 0.14)
const EMBER_HI := Color(1.0, 0.64, 0.27)

static var _body: Font
static var _italic: Font
static var _caps: Font


static func _load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	return ThemeDB.fallback_font


static func body() -> Font:
	if not _body:
		_body = _load("res://assets/fonts/IMFeENrm28P.ttf")
	return _body


static func italic() -> Font:
	if not _italic:
		_italic = _load("res://assets/fonts/IMFeENit28P.ttf")
	return _italic


static func caps() -> Font:
	if not _caps:
		var f := FontVariation.new()
		f.base_font = _load("res://assets/fonts/Cinzel.ttf")
		f.spacing_glyph = 4
		_caps = f
	return _caps


## Draws a tiny filled diamond centred on c.
static func diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
