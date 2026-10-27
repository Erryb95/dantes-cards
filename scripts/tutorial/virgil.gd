class_name Virgil
## Virgil, the guide of the lessons: his framed portrait (the oval gold ring around his painting, his name on the red
## ribbon) and his painted question box. The portrait is the painted `assets/ui/virgil_portrait` when it exists, else
## the art of his card (Virgil, the Guide) cropped to the oval.

const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")
const RING := Vector2(1.3, 1.27) ## the oval ring around a portrait, as a multiple of the portrait's size


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
	row.add_theme_constant_override("separation", 56)
	panel.add_child(row)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(250, 0)
	holder.add_child(portrait(Vector2(210, 268)))
	row.add_child(holder)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	for l in col.get_children():
		if l is Label:
			(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	(col.get_child(-1) as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
	return d
