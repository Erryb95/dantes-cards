class_name Virgil
## Virgil, the guide of the lessons: his framed portrait (the oval gold ring around his painting, his name on the red
## ribbon) and his question box, in dark ink on parchment. The portrait is the painted `assets/ui/virgil_portrait`
## when it exists, else the art of his card (Virgil, the Guide) cropped to the oval.

const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")
const RING := Vector2(1.3, 1.27) ## the oval ring around a portrait, as a multiple of the portrait's size
const RED_INK := Color(0.45, 0.1, 0.04) ## headings and hints in red ink on parchment (the body text is UI.INK)


## The portrait's painting: the dedicated portrait when it is painted, else the card art cropped around his face.
static func art(aspect: float) -> Texture2D:
	if UiSkin.has("virgil_portrait"):
		return UiSkin.tex("virgil_portrait")
	return CardDB.art_framed("virgil_guide", aspect, 0.3)


## Virgil's portrait `size` px (the oval inside the ring; the ring reaches about 15% beyond it on each side), with his
## name on the ribbon across its foot when `named`. The returned control is the oval's size, the ring overhanging it.
static func portrait(size: Vector2, named: bool = true) -> Control:
	var c := Control.new()
	c.name = "Virgil"
	c.custom_minimum_size = size
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := TextureRect.new() # warm lamplight behind the frame
	glow.texture = UI.dot_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = size * 1.9
	glow.position = (size - glow.size) / 2.0
	glow.modulate = Color(1.0, 0.62, 0.25, 0.32)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(glow)
	var pic := TextureRect.new()
	pic.name = "Art"
	pic.texture = art(size.x / size.y)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size = size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CARD_FX
	m.set_shader_parameter("mask_mode", 1)
	pic.material = m
	c.add_child(pic)
	if UiSkin.has("oval_ring"):
		var ring := UiSkin.rect("oval_ring", size * RING)
		ring.name = "Ring"
		ring.position = (size - ring.size) / 2.0
		ring.use_parent_material = false
		c.add_child(ring)
	if named:
		var rib := UI.ribbon("Virgil", size.x * 1.45, int(clampf(size.x * 0.2, 22.0, 40.0)))
		rib.name = "Name"
		rib.position += Vector2(size.x / 2.0, size.y * 1.02)
		c.add_child(rib)
	return c


## How wide the painted part of a `portrait` is: its ring and its ribbon without their transparent edges (the glow
## behind is not counted).
static func painted_width(p: Control) -> float:
	var w := p.size.x
	for t in p.find_children("*", "TextureRect", true, false):
		var tr := t as TextureRect
		if tr.texture == null or tr.texture == UI.dot_texture() or tr.name == "Art":
			continue
		w = maxf(w, tr.size.x * UI.opaque_rect(tr.texture).size.x / tr.texture.get_size().x)
	return w


## A question from Virgil: his portrait beside `title` and `text` on the big bronze-framed panel over a dim veil, then
## one plate per choice ([label, callable or null]). Built like UI.dialog (named "Dialog", the last choice is the one
## Esc / the Android back gesture picks), so Game.back and UI.cancel_dialog treat it the same way.
static func dialog(parent: Node, title: String, text: String, choices: Array) -> Control:
	var d := UI.dialog(parent, title, text, choices)
	# The portrait goes to the left of the panel's words: the column of title, text and buttons becomes a row.
	var panel := d.find_children("*", "PanelContainer", true, false)[0] as PanelContainer
	var col := panel.get_child(0) as VBoxContainer
	panel.remove_child(col)
	var row := HBoxContainer.new()
	panel.add_child(row)
	# The holder is as wide as the portrait's painted part (the ring or the name ribbon, whichever reaches further),
	# so the panel's margin is the same on its left (from the paint) as on its right (from the text and buttons).
	var pic := portrait(Vector2(210, 268))
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(maxf(210.0, painted_width(pic)), 0)
	row.add_theme_constant_override("separation", int(56.0 - (holder.custom_minimum_size.x - 250.0) / 2.0))
	holder.add_child(pic)
	row.add_child(holder)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	# The heading as painted words when they exist (assets/ui/words, art_src/tutorial_art.json), else the set title.
	var word := UI.word_tex(title)
	if word != null and col.get_child(0) is Label:
		var old := col.get_child(0)
		var w := UI.word_rect(word, Vector2(640, 92))
		w.custom_minimum_size = w.size
		w.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(w)
		col.move_child(w, 0)
		col.remove_child(old)
		old.queue_free()
	# Virgil speaks in dark ink on parchment, like every info box: the title in red ink, the words in black.
	panel.add_theme_stylebox_override("panel", UI.parchment_box(84, 60))
	for l in col.get_children():
		if l is Label:
			(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.add_theme_color_override("font_color", RED_INK if l.get_index() == 0 else UI.INK)
			l.add_theme_constant_override("outline_size", 0)
	(col.get_child(-1) as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
	return d
