class_name UI
## Shared look: fonts, palette, stylebox and label helpers.

const GOLD := Color(0.93, 0.74, 0.38)
const GOLD_DARK := Color(0.45, 0.30, 0.12)
const CRIMSON := Color(0.55, 0.06, 0.05)
const EMBER := Color(1.0, 0.5, 0.15)
const BONE := Color(0.94, 0.89, 0.78)
const INK := Color(0.06, 0.04, 0.035)
const MANA := Color(0.25, 0.55, 1.0)
const HEAL := Color(0.45, 1.0, 0.45)
const PLAYABLE := Color(0.35, 1.0, 0.45)
const RARITY := {
	"common": Color(0.75, 0.72, 0.68), "rare": Color(0.35, 0.6, 1.0), "epic": Color(0.75, 0.4, 1.0),
	"legendary": Color(1.0, 0.62, 0.15), "token": Color(0.5, 0.45, 0.4)}

static var _fonts := {}


## "title" = Cinzel (headings, names), "body" = IM Fell English (rules text), "italic" = IM Fell italic.
static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = {"title": "res://assets/fonts/Cinzel.ttf", "body": "res://assets/fonts/IMFeENrm28P.ttf",
		"italic": "res://assets/fonts/IMFeENit28P.ttf"}.get(kind, "res://assets/fonts/IMFeENrm28P.ttf")
	var f: FontFile = load(path)
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 12
	f.msdf_size = 64
	f.generate_mipmaps = true
	if kind == "title":
		var v := FontVariation.new()
		v.base_font = f
		v.variation_embolden = 0.6
		_fonts[kind] = v
		return v
	_fonts[kind] = f
	return f


static func label(text: String, size: int, kind: String = "body", color: Color = BONE, outline: int = 0,
		outline_color: Color = Color.BLACK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 12,
		shadow: Color = Color.TRANSPARENT, shadow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.2
	s.corner_detail = 12
	return s


static func panel(size: Vector2, style: StyleBox, pos: Vector2 = Vector2.ZERO) -> Panel:
	var p := Panel.new()
	p.size = size
	p.position = pos
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A big themed button (menus).
static func button(text: String, width: float = 420.0, height: float = 84.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, height)
	b.add_theme_font_override("font", font("title"))
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.7))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.4))
	b.add_theme_stylebox_override("normal", box(Color(0.13, 0.05, 0.04, 0.92), GOLD_DARK, 3, 10,
		Color(0, 0, 0, 0.6), 8))
	b.add_theme_stylebox_override("hover", box(Color(0.32, 0.08, 0.05, 0.95), GOLD, 3, 10, Color(1.0, 0.45, 0.1, 0.45), 18))
	b.add_theme_stylebox_override("pressed", box(Color(0.45, 0.1, 0.05, 1.0), GOLD, 4, 10, Color(1.0, 0.5, 0.1, 0.6), 22))
	b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.07, 0.06, 0.8), Color(0.3, 0.25, 0.2), 2, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if height >= 50.0 and width >= 120.0 and UiSkin.has("menu_plate"):
		# The painted bronze plate (ComfyUI UI pass): dark ink on gold. Narrow buttons use a half-size plate so the
		# scrollwork ends leave room for the label.
		var small := width < 260.0
		b.add_theme_stylebox_override("normal", plate(Color(0.92, 0.88, 0.82), 0, small))
		b.add_theme_stylebox_override("hover", plate(Color(1.15, 1.05, 0.9), -2, small))
		b.add_theme_stylebox_override("pressed", plate(Color(0.75, 0.62, 0.5), 4, small))
		b.add_theme_stylebox_override("disabled", plate(Color(0.4, 0.38, 0.36), 0, small))
		b.add_theme_color_override("font_color", Color(0.2, 0.08, 0.03))
		b.add_theme_color_override("font_hover_color", Color(0.3, 0.04, 0.02))
		b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
		b.add_theme_color_override("font_disabled_color", Color(0.22, 0.2, 0.18))
	b.ready.connect(fit_text.bind(b))
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -10.0))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -6.0))
	# Physical depth: the plate rises toward the pointer and sinks when pressed.
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.mouse_entered.connect(_press_depth.bind(b, 1.04))
	b.mouse_exited.connect(_press_depth.bind(b, 1.0))
	b.button_down.connect(_press_depth.bind(b, 0.96))
	b.button_up.connect(func(): _press_depth(b, 1.04 if b.is_hovered() else 1.0))
	return b


## Shrinks the label's font until it fits inside the button's content area (long labels on narrow plates).
static func fit_text(b: Button) -> void:
	var font := b.get_theme_font("font")
	var size := b.get_theme_font_size("font_size")
	var sb := b.get_theme_stylebox("normal")
	var room := b.custom_minimum_size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 6.0
	while size > 16 and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	b.add_theme_font_size_override("font_size", size)


static func _press_depth(b: Button, s: float) -> void:
	if b.disabled and s > 1.0:
		return
	b.create_tween().tween_property(b, "scale", Vector2.ONE * s, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The painted button plate as a nine-patch: the scrollwork ends keep their shape at any width.
static var _small_plate: Texture2D
static func plate(tint: Color, sink: int = 0, small: bool = false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	var k := 0.5 if small else 1.0
	if small:
		if _small_plate == null:
			var img := UiSkin.tex("menu_plate").get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
			_small_plate = ImageTexture.create_from_image(img)
		s.texture = _small_plate
	else:
		s.texture = UiSkin.tex("menu_plate")
	s.texture_margin_left = 70 * k
	s.texture_margin_right = 70 * k
	s.texture_margin_top = 22 * k
	s.texture_margin_bottom = 22 * k
	s.content_margin_left = 40 * k + (6 if small else 0)
	s.content_margin_right = 40 * k + (6 if small else 0)
	s.content_margin_top = 22 * k + sink
	s.content_margin_bottom = 22 * k - sink
	s.modulate_color = tint
	return s


## The painted frame around an oval portrait of `size` (minions, heroes): the dedicated minion frames when they
## exist, else the ornate oval ring. The art keeps its own oval mask; the frame overlaps its outer edge. Null when
## no painted frame exists.
static func portrait_frame(size: Vector2, legendary: bool = false) -> Sprite2D:
	var name := "minion_frame_legendary" if legendary and UiSkin.has("minion_frame_legendary") else "minion_frame"
	var k := Vector2(1.24, 1.22)
	if not UiSkin.has(name):
		name = "oval_ring"
		k = Vector2(1.3, 1.28)
	if not UiSkin.has(name):
		return null
	var s := UiSkin.sprite(name, size * k)
	if legendary and name == "oval_ring":
		s.modulate = Color(1.2, 0.95, 0.65)
	return s


## A painted frame (assets/ui/<name>.png) as a 9-slice style; `fallback` is used when the painting is missing.
static func frame_box(name: String, tex_margin: float, content_margin: float, fallback: StyleBox,
		tint: Color = Color.WHITE) -> StyleBox:
	if not UiSkin.has(name):
		return fallback
	var s := StyleBoxTexture.new()
	s.texture = UiSkin.tex(name)
	s.set_texture_margin_all(tex_margin)
	s.set_content_margin_all(content_margin)
	s.modulate_color = tint
	return s


## A copy of a painted texture scaled to `px` (for theme icons, which Godot never scales).
static var _scaled := {}
static func scaled_tex(name: String, px: int) -> Texture2D:
	var key := "%s@%d" % [name, px]
	if not _scaled.has(key):
		var img := UiSkin.tex(name).get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_scaled[key] = ImageTexture.create_from_image(img)
	return _scaled[key]


## Soft round particle sprite (generated once).
static var _dot: Texture2D
static func dot_texture() -> Texture2D:
	if _dot == null:
		var g := GradientTexture2D.new()
		g.width = 64
		g.height = 64
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.35, Color(1, 1, 1, 0.55))
		g.gradient = gr
		_dot = g
	return _dot


## Keywords are shown in bold in rules text.
static func rules_bbcode(text: String) -> String:
	var t := text
	for k in ["On Play:", "Last Breath:", "End of Turn:", "Start of Turn:", "Guard", "Swift", "Ward", "Drain",
			"Venom", "Rebirth", "Freeze", "Silence"]:
		t = t.replace(k, "[b]" + k + "[/b]")
	return "[center]" + t + "[/center]"


const KEYWORD_HELP := {
	"guard": ["Guard", "Enemies must attack this minion first."],
	"swift": ["Swift", "Can attack the turn it is played."],
	"ward": ["Ward", "The first damage it would take is blocked."],
	"drain": ["Drain", "Damage it deals also heals your hero."],
	"venom": ["Venom", "Destroys any minion it damages."],
	"rebirth": ["Rebirth", "The first time it dies, it returns with 1 Health."],
	"turn_end": ["End of Turn", "Does something at the end of your turn."],
	"turn_start": ["Start of Turn", "Does something at the start of your turn."],
	"death": ["Last Breath", "Does something when it dies."],
	"play": ["On Play", "Does something when you play it from your hand."],
}
