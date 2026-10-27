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
	var path: String = {"title": "res://assets/fonts/CinzelTitle.ttf", "body": "res://assets/fonts/IMFeENrm28P.ttf",
		"italic": "res://assets/fonts/IMFeENit28P.ttf"}.get(kind, "res://assets/fonts/IMFeENrm28P.ttf")
	# The title face is Cinzel at a real 600 weight with merged outlines (tools/ui/make_title_font.py): the
	# variable font's overlapping contours drew spikes and specks in MSDF, and a fake bold smeared the serifs.
	var f: FontFile = load(path)
	f.generate_mipmaps = true
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 12
	f.msdf_size = 64
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


## Warm white of the stat numbers (white reads as pasted on top of the painted gems).
const NUMBER := Color(1.0, 0.95, 0.84)


## Stat numbers: a dark outline plus a soft drop shadow, so they sit on the gem like raised metal.
static func raised(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l


## Text cut into a painted metal plate: dark ink, no outline, a thin light edge below like an engraving.
static func engraved(l: Label, ink: Color = Color(0.2, 0.08, 0.03)) -> Label:
	l.add_theme_color_override("font_color", ink)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.62, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 0)
	return l


## Where a stat number's label centre goes, relative to the centre of its painted gem `px` wide: on the gem's
## visual centre (the shield's disc sits a little high, the drop's stone low), corrected for Cinzel's digits,
## whose ink sits 0.0625 em above the centre of the line box.
const GEM_CENTER := {"gem_attack": Vector2(0, -0.04), "gem_health": Vector2(0, 0.045), "gem_mana": Vector2.ZERO,
	"gem_armor": Vector2(0, -0.03)}
static func gem_number_offset(gem: String, px: float, font_size: int) -> Vector2:
	return GEM_CENTER.get(gem, Vector2.ZERO) * px + Vector2(0, 0.0625 * font_size)


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
		b.add_theme_stylebox_override("disabled", plate(Color(0.6, 0.56, 0.52), 0, small)) # greyed, label still legible
		b.add_theme_color_override("font_color", Color(0.2, 0.08, 0.03))
		b.add_theme_color_override("font_hover_color", Color(0.3, 0.04, 0.02))
		b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
		b.add_theme_color_override("font_disabled_color", Color(0.17, 0.13, 0.1, 0.9))
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
	if sb is StyleBoxTexture:
		# Keep the label off the painted scrollwork ends, which reach past the content margins.
		room = minf(room, b.custom_minimum_size.x - 1.25 * (sb.texture_margin_left + sb.texture_margin_right) + 8.0)
	while size > 16 and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	b.add_theme_font_size_override("font_size", size)


## One letter size for a row of plates (filter tabs): each label fitted to its plate, then all set to the smallest,
## so "All" does not shout beside a long class name squeezed small.
static func even_text(buttons: Array) -> void:
	var px := 1000
	for b in buttons:
		fit_text(b)
		px = mini(px, (b as Button).get_theme_font_size("font_size"))
	for b in buttons:
		(b as Button).add_theme_font_size_override("font_size", px)


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


## The painted tooltip plate (dark field inside a bronze frame). Its content margins clear the frame's scrollwork
## (about 40 px of ornament per side), so text always sits on the dark field, never on the border.
static func tip_box() -> StyleBox:
	var s := frame_box("tooltip_frame_filled", 40, 0, box(Color(0.08, 0.05, 0.04, 0.94), GOLD_DARK, 2, 8))
	if s is StyleBoxTexture:
		s.content_margin_left = 50
		s.content_margin_right = 50
		s.content_margin_top = 38
		s.content_margin_bottom = 40
	return s


static var _parchment: Texture2D


## The painted parchment plate (a pale sheet inside a thin bronze rule) as a 9-slice style, `pad` px of room inside
## it left / right and `pad_y` above / below: set dark ink on it (descriptions, a class's playstyle).
## The painting is used at half size, so its bronze rule sits about 15 px inside the edge and short plates keep room
## for text.
static func parchment_box(pad: float = 30.0, pad_y: float = 18.0) -> StyleBox:
	if not UiSkin.has("plate_parchment_wide"):
		var flat := box(Color(0.82, 0.7, 0.5), GOLD_DARK, 2, 6)
		flat.content_margin_left = pad
		flat.content_margin_right = pad
		flat.content_margin_top = pad_y
		flat.content_margin_bottom = pad_y
		return flat
	if _parchment == null:
		var img := UiSkin.tex("plate_parchment_wide").get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		_parchment = ImageTexture.create_from_image(img)
	var s := StyleBoxTexture.new()
	s.texture = _parchment
	s.set_texture_margin_all(18)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## Tint of the painted field (assets/ui/panel_bg.jpg) inside plaques: dark enough for bone text.
const FIELD := Color(0.55, 0.45, 0.4)


## Lays the painted field (the dark iron panel) behind `c`'s own drawing, `inset` px inside its edges, so a thin
## bronze frame drawn by `c` (a deck_row stylebox) reads as a plaque. The field is an internal child: containers
## never lay it out, and it never takes the mouse.
static func add_field(c: Control, inset: float = 5.0, tint: Color = FIELD) -> void:
	if not ResourceLoader.exists("res://assets/ui/panel_bg.jpg"):
		return
	var bg := TextureRect.new()
	bg.name = "Field"
	bg.texture = load("res://assets/ui/panel_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = inset
	bg.offset_top = inset
	bg.offset_right = -inset
	bg.offset_bottom = -inset
	bg.show_behind_parent = true
	bg.clip_contents = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = tint
	c.add_child(bg, false, Node.INTERNAL_MODE_FRONT)
	# A container fits every child, internal ones too, into its content rect (inside the frame's text margins), which
	# left the field a dark box behind the text only: put it back over the whole plaque after each sort.
	if c is Container:
		c.sort_children.connect(func() -> void:
			bg.position = Vector2(inset, inset)
			bg.size = c.size - Vector2(inset, inset) * 2.0)


## The thin bronze plaque frame (deck_row) as a style with room for text: `pad` px inside it left / right and
## `pad_y` px above / below.
static func plaque_box(pad: float = 30.0, pad_y: float = 10.0, tint: Color = Color.WHITE) -> StyleBox:
	var s := frame_box("deck_row", 10, 0, box(Color(0.08, 0.04, 0.035, 0.9), GOLD_DARK, 2, 8), tint)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y + 2.0
	return s


## An engraved plaque: the bronze frame around the painted dark field. Add the text (or a row of icon + text) as its
## child; the plaque sizes itself around it.
static func plaque(pad: float = 30.0, pad_y: float = 10.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plaque_box(pad, pad_y))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_field(p)
	return p


## A text line set on a plaque: bone (or `color`) letters with a dark edge, shrunk to `room` px when given.
static func plaque_label(text: String, size: int, kind: String = "italic", color: Color = BONE,
		room: float = 0.0, pad: float = 30.0, pad_y: float = 10.0) -> PanelContainer:
	var p := plaque(pad, pad_y)
	var l := label(text, size, kind, color, 4, Color(0.04, 0.01, 0.01))
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if room > 0.0:
		fit_label(l, room, maxi(14, size - 12))
	p.add_child(l)
	return p


## The red name ribbon `width` px wide with `text` in its flat middle (about 64% of the width, between the folded
## tails), shrunk to fit. The ribbon is centred on (0, 0) of the returned control, so it can hang on a Node2D.
static func ribbon(text: String, width: float, size: int, color: Color = BONE) -> Control:
	var h := width * 144.0 / 768.0
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(width, h)
	c.position = -c.size / 2
	if UiSkin.has("name_ribbon"):
		c.add_child(UiSkin.rect("name_ribbon", c.size))
	var l := label(text, size, "title", color, 6 if UiSkin.has("name_ribbon") else 8, Color(0.12, 0.02, 0.02))
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(width, h * 0.78) # the ribbon's band sits a little above its middle (the tails hang below)
	fit_label(l, width * 0.62, maxi(14, size - 16))
	gild(l, color if color != BONE else GOLD, l.size.y)
	c.add_child(l)
	return c


## A heading on the charred banner (the painted ribbon of the turn banner): `text` set in the banner's dark band,
## the ribbon stretched only in its middle so the folded tails keep their shape. The banner is `k` x the font size
## tall and as wide as the text needs (or `width`). The returned control is that size for containers (or
## `layout_h` tall, the ribbon then overhanging it, centred); its label is the child "Text". Without the painting the
## heading is a plain label with a dark edge.
static func banner(text: String, size: int, color: Color = GOLD, width: float = 0.0, layout_h: float = 0.0,
		k: float = 2.0) -> Control:
	var h := roundf(size * k)
	var tail := h * 0.96 ## the folded tail at each end, in px: the band of the ribbon lies between them
	var word := word_tex(text)
	var word_h := size * WORD_K
	var tw := font("title").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if word != null:
		tw = word_h * word.get_width() / word.get_height()
	var w := width if width > 0.0 else tw + 2.0 * tail + 40.0
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size = Vector2(w, layout_h if layout_h > 0.0 else h)
	c.size = c.custom_minimum_size
	var painted := UiSkin.has("turn_banner")
	if painted:
		var r := NinePatchRect.new()
		r.name = "Ribbon"
		r.texture = _banner_tex(int(h))
		r.patch_margin_left = int(tail)
		r.patch_margin_right = int(tail)
		r.anchor_right = 1.0
		r.anchor_top = 0.5
		r.anchor_bottom = 0.5
		r.offset_top = -h / 2
		r.offset_bottom = h / 2
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.use_parent_material = true
		c.add_child(r)
	var l := label(text, size, "title", color, maxi(6, size / 8) if painted else maxi(8, size / 7),
		Color(0.1, 0.02, 0.0))
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The band's middle sits a little below the ribbon's; Cinzel's letters sit high in their line box.
	var dy := 0.02 * h + 0.06 * size
	l.offset_top = dy
	l.offset_bottom = dy
	l.use_parent_material = true
	if painted:
		fit_label(l, w - 2.0 * tail + 10.0, maxi(14, size - 20))
		if word == null:
			gild(l, color, c.custom_minimum_size.y)
	c.add_child(l)
	if word != null: # the painted words take the label's place (it stays, hidden, for code that reads its text)
		l.visible = false
		var room := minf(tw, w - 2.0 * tail + 10.0)
		var wr := word_rect(word, Vector2(room, room * word.get_height() / word.get_width()))
		wr.position = (c.size - wr.size) / 2.0 + Vector2(0, dy * 0.5)
		wr.use_parent_material = true
		c.add_child(wr)
	return c


static var _gilded: Shader


## Engraved gold for a heading set in a font (one with no painted words, like a card or arena name): `l` is one
## line, vertically centred in a box `box_h` px tall; `color` tints the gold (an ember name goes copper).
static func gild(l: Label, color: Color, box_h: float) -> void:
	if _gilded == null:
		_gilded = load("res://assets/shaders/gilded_text.gdshader")
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var baseline := (box_h - f.get_height(fs)) / 2.0 + f.get_ascent(fs)
	var m := ShaderMaterial.new()
	m.shader = _gilded
	m.set_shader_parameter("baseline", baseline)
	m.set_shader_parameter("cap_top", baseline - fs * 0.7) # Cinzel's capitals stand about 0.7 em
	m.set_shader_parameter("tint", color)
	l.use_parent_material = false
	l.material = m


## How tall painted words stand on a banner, in font sizes: inside the band between its gilded trims.
const WORD_K := 0.86


## Painted lettering for a heading: the words painted on the GPU in gilded capitals on a transparent ground, in
## assets/ui/words/<slug>.png, the slug being the text lower-cased with its words joined by "_" ("YOUR TURN" →
## your_turn, "Concede this match?" → concede_this_match). Null when that heading has no painting (a font is used).
static func word_tex(text: String) -> Texture2D:
	var slug := ""
	for ch in text.to_lower().strip_edges():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			slug += ch
		elif ch == " " and not slug.ends_with("_"):
			slug += "_"
	var path := "res://assets/ui/words/%s.png" % slug.trim_suffix("_")
	return load(path) if ResourceLoader.exists(path) else null


## Painted words `tex` scaled to fit `box` (keeping their shape), centred in a control of their scaled size.
static func word_rect(tex: Texture2D, box: Vector2) -> TextureRect:
	var k := minf(box.x / tex.get_width(), box.y / tex.get_height())
	var r := TextureRect.new()
	r.name = "Word"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = Vector2(tex.get_width(), tex.get_height()) * k
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # shrunk many times: no shimmering hatching
	# A soft dark copy just below: the gold letters stand off the grey ribbon like raised metal.
	var sh := TextureRect.new()
	sh.name = "Shadow"
	sh.texture = tex
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sh.size = r.size
	sh.position = Vector2(0, maxf(1.5, r.size.y * 0.04))
	sh.modulate = Color(0, 0, 0, 0.55)
	sh.show_behind_parent = true
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.texture_filter = r.texture_filter
	r.add_child(sh)
	return r


static func _banner_tex(h: int) -> Texture2D:
	var key := "turn_banner@h%d" % h
	if not _scaled.has(key):
		var img := UiSkin.tex("turn_banner").get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(maxi(1, roundi(img.get_width() * float(h) / img.get_height())), h, Image.INTERPOLATE_LANCZOS)
		_scaled[key] = ImageTexture.create_from_image(img)
	return _scaled[key]


## The painted look for what Godot draws on its own: tooltips sit on the bronze tooltip plate in the body face.
## Written into the engine's default theme (Game does it once), the fallback every control's tooltip looks up.
static func paint_tooltips() -> void:
	var t := ThemeDB.get_default_theme()
	var tip := frame_box("tooltip_frame_filled", 40, 0, box(Color(0.08, 0.05, 0.04, 0.94), GOLD_DARK, 2, 8))
	if tip is StyleBoxTexture:
		tip.content_margin_left = 46
		tip.content_margin_right = 46
		tip.content_margin_top = 30
		tip.content_margin_bottom = 32
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", 24)
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_color("font_outline_color", "TooltipLabel", Color(0.04, 0.01, 0.01))
	t.set_constant("outline_size", "TooltipLabel", 3)
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))


## Shrinks a one-line label until its text fits `room` px.
static func fit_label(l: Label, room: float, min_size: int) -> void:
	var f := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	while px > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		px -= 1
	l.add_theme_font_size_override("font_size", px)


## Paints a scroll container's vertical bar: the bronze rod of the slider as its track and a gilded plate (the menu
## plate turned upright, its scrollwork at both ends) as the thumb. Wheel and drag scroll as before.
static func paint_scroll(scroll: ScrollContainer, width: int = 26) -> void:
	var bar := scroll.get_v_scroll_bar()
	if not (UiSkin.has("slider_track") and UiSkin.has("menu_plate")):
		bar.add_theme_stylebox_override("scroll", box(Color(0.08, 0.04, 0.035, 0.7), GOLD_DARK, 1, 8))
		bar.add_theme_stylebox_override("grabber", box(GOLD_DARK, GOLD, 1, 8))
		return
	var track := StyleBoxTexture.new()
	track.texture = upright_tex("slider_track", width)
	track.texture_margin_top = width * 0.6
	track.texture_margin_bottom = width * 0.6
	track.content_margin_left = width / 2.0
	track.content_margin_right = width / 2.0
	track.modulate_color = Color(0.8, 0.72, 0.65)
	for st in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(st, track)
	for st in [["grabber", Color(0.9, 0.85, 0.78)], ["grabber_highlight", Color(1.15, 1.05, 0.88)],
			["grabber_pressed", Color(1.25, 1.1, 0.85)]]:
		var g := StyleBoxTexture.new()
		g.texture = upright_tex("menu_plate", width)
		g.texture_margin_top = width * 0.8
		g.texture_margin_bottom = width * 0.8
		g.content_margin_top = width * 0.8
		g.content_margin_bottom = width * 0.8
		g.modulate_color = st[1]
		bar.add_theme_stylebox_override(st[0], g)
	bar.custom_minimum_size.x = width


## A painted strip turned upright (rotated a quarter turn) and scaled to `px` wide, for vertical bars.
static func upright_tex(name: String, px: int) -> Texture2D:
	var key := "%s@up%d" % [name, px]
	if not _scaled.has(key):
		var img := UiSkin.tex(name).get_image()
		if img.is_compressed():
			img.decompress()
		img.rotate_90(CLOCKWISE)
		img.resize(px, maxi(1, roundi(img.get_height() * float(px) / img.get_width())), Image.INTERPOLATE_LANCZOS)
		_scaled[key] = ImageTexture.create_from_image(img)
	return _scaled[key]


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
## The largest font size (max_size down to min_size) at which `plain` text wraps inside width x height, for a
## RichTextLabel (bold keywords run a little wider, so the width keeps a 6% margin).
static func fit_rules_size(plain: String, width: float, height: float, max_size: int, min_size: int = 12) -> int:
	var f := font("body")
	var s := max_size
	while s > min_size:
		var box := f.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_CENTER, width * 0.94, s)
		if box.y <= height:
			break
		s -= 1
	return s


static func rules_bbcode(text: String) -> String:
	var t := text
	for k in ["On Play:", "Last Breath:", "End of Turn:", "Start of Turn:", "Ruse:", "Wrath:", "Frenzy:", "Guard", "Swift",
			"Ward", "Drain", "Venom", "Rebirth", "Freeze", "Silence"]:
		t = t.replace(k, "[b]" + k + "[/b]")
	return "[center]" + t + "[/center]"


const KEYWORD_HELP := {
	"guard": ["Guard", "Enemies must attack this minion first."],
	"swift": ["Swift", "Can attack the turn it is played."],
	"ward": ["Ward", "The first damage it would take is blocked."],
	"drain": ["Drain", "Damage it deals also heals your hero."],
	"venom": ["Venom", "Destroys any minion it damages."],
	"rebirth": ["Rebirth", "The first time it dies, it returns as a new minion with 1 Health."],
	"turn_end": ["End of Turn", "Does something at the end of your turn."],
	"turn_start": ["Start of Turn", "Does something at the start of your turn."],
	"death": ["Last Breath", "Does something when it dies."],
	"play": ["On Play", "Does something when you play it from your hand."],
	"ruse": ["Ruse", "A bonus when you play it after another card this turn."],
	"freeze": ["Freeze", "A frozen minion loses its next attack, then thaws."],
	"silence": ["Silence", "Removes its card text and keywords. Stat changes and Freeze stay."],
	"frozen": ["Frozen", "It loses its next attack, then thaws."],
	"silenced": ["Silenced", "Its card text and keywords are gone. Stat changes stay."],
	"wrath": ["Wrath", "While this minion is damaged, it has the extra Attack."],
	"frenzy": ["Frenzy", "Does something the first time it takes damage and survives."],
	"fight": ["Fight", "Two minions deal damage equal to their Attack to each other."],
}

## Keyword words a rules text can mention (a token it summons, a keyword it gives), and the tip each one opens.
const _TEXT_KEYWORDS := ["Guard", "Swift", "Ward", "Drain", "Venom", "Rebirth", "Freeze", "Silence"]
static var _text_kw: RegEx


## The keyword tips for a card, as [title, text] pairs in reading order: its status (a live unit), its keywords, its
## triggers (minions), then the keywords its effects or its text mention. A live unit goes in as the card dictionary
## with its current "keywords" and the flags "frozen" / "silenced" (a silenced minion has no text or triggers left).
## `on_board`: the minion is already in play, so its "On Play" is history and gets no tip.
static func card_tips(card: Dictionary, on_board: bool = false) -> Array:
	var keys: Array[String] = []
	var add := func(k: String) -> void:
		if KEYWORD_HELP.has(k) and not keys.has(k):
			keys.append(k)
	if card.get("frozen", false):
		add.call("frozen")
	var silenced: bool = card.get("silenced", false)
	if silenced:
		add.call("silenced")
	for k in card.get("keywords", []):
		add.call(str(k))
	if not silenced:
		if int(card.get("wrath", 0)) > 0: # a live unit carries its current Wrath (0 once silenced)
			add.call("wrath")
		var minion: bool = card.get("type", "minion") == "minion"
		for e in card.get("effects", []):
			# A Ruse bonus is an On Play effect too, but its tip explains the Ruse.
			var on: String = "ruse" if e.get("ruse", false) else str(e.get("on", ""))
			# Triggers belong to minions; a spell's Ruse bonus gets its tip too.
			if (minion or on == "ruse") and on in ["death", "play", "turn_end", "turn_start", "ruse", "frenzy"] \
					and not (on_board and on == "play"):
				add.call(on)
			if on_board and str(e.get("on", "")) == "play":
				continue # what it did when played is history: no Freeze / Silence / keyword tips for it
			var does := str(e.get("do", ""))
			if does == "freeze" or does == "silence" or does == "fight":
				add.call(does)
			for k in e.get("keywords", []):
				add.call(str(k))
			if e.has("card"): # a token it summons or a card it gives, with that card's keywords
				for k in CardDB.card(str(e.card)).get("keywords", []):
					add.call(str(k))
				if int(CardDB.card(str(e.card)).get("wrath", 0)) > 0:
					add.call("wrath")
		if not on_board: # the text may name a keyword the effects only imply
			if _text_kw == null:
				_text_kw = RegEx.create_from_string("\\b(" + "|".join(_TEXT_KEYWORDS) + ")\\b")
			for m in _text_kw.search_all(str(card.get("text", ""))):
				add.call(m.get_string(1).to_lower())
	var out := []
	for k in keys:
		out.append(KEYWORD_HELP[k])
	return out


## One keyword tip on the painted tip plate: the keyword in gold over its explanation.
static func tip_plate(title: String, text: String, width: float = 320.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", tip_box())
	p.custom_minimum_size = Vector2(width, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(label(title, 24, "title", GOLD))
	var b := label(text, 22, "body", BONE)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(width - 20.0, 0)
	v.add_child(b)
	return p


## A column of keyword tips for a card (see card_tips), or null when it has none.
static func tip_column(card: Dictionary, on_board: bool = false, width: float = 320.0) -> VBoxContainer:
	var tips := card_tips(card, on_board)
	if tips.is_empty():
		return null
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	for t in tips:
		col.add_child(tip_plate(t[0], t[1], width))
	return col


## A modal question on the big bronze-framed panel over a dim veil: `title` in gold, `text` under it, then one plate
## per choice ([label, callable]; the callable may be null). Any choice closes the dialog first; Esc / the Android back
## gesture picks the last choice (keep it the harmless one, e.g. "Keep it"). Returns the dialog (added to `parent`).
static func dialog(parent: Node, title: String, text: String, choices: Array) -> Control:
	var d := Control.new()
	d.name = "Dialog"
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d.z_index = 100 # above the scenes' Node2D layers (cards)
	var dim := ColorRect.new() # the veil, like the options panel's
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.add_child(center)
	var panel := PanelContainer.new()
	var s := frame_box("panel_frame_filled", 96, 0, box(Color(0.09, 0.05, 0.04, 0.97), GOLD, 3, 14, Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = 100
	s.content_margin_right = 100
	s.content_margin_top = 80
	s.content_margin_bottom = 84
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	var t := label(title, 50, "title", GOLD, 8, Color.BLACK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fit_label(t, 760.0, 30)
	v.add_child(t)
	if text != "":
		var b := label(text, 28, "italic", BONE, 3, Color.BLACK)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(minf(760.0, maxf(420.0, t.get_minimum_size().x)), 0)
		v.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var buttons: Array[Button] = []
	for c in choices:
		# Each plate as wide as its label needs past the scrollwork ends (within reason); one letter size for the row.
		var tw := font("title").get_string_size(str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var btn := button(str(c[0]), clampf(tw + 190.0, 260.0, 400.0), 76)
		btn.add_theme_font_size_override("font_size", 30)
		var act: Variant = c[1]
		btn.pressed.connect(func():
			d.queue_free()
			if act is Callable:
				(act as Callable).call())
		row.add_child(btn)
		buttons.append(btn)
	even_text(buttons)
	d.set_meta("cancel", buttons[-1])
	parent.add_child(d)
	d.modulate.a = 0.0
	d.create_tween().tween_property(d, "modulate:a", 1.0, 0.15)
	return d


## Esc / the Android back gesture inside a scene with an open dialog: presses its last (harmless) choice. True when
## a dialog took it.
static func cancel_dialog(scene: Node) -> bool:
	var d := scene.get_node_or_null("Dialog")
	if d == null or d.is_queued_for_deletion():
		return false
	(d.get_meta("cancel") as Button).pressed.emit()
	return true


## A touch screen phone or tablet (the hints say "Tap" / "Touch" there, "Click" / "mouse" on a desktop).
static func touch_ui() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


## "Tap" on a touch screen, "Click" with a mouse.
static func tap_word() -> String:
	return "Tap" if touch_ui() else "Click"
