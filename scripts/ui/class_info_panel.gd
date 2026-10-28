class_name ClassInfoPanel
## What a class is about, painted, from CardDB.class_info (the one source of class text; refine it in
## data/cards.json, never here):
## - strip(): a plaque one row tall (hero portrait, class name, tagline; on wide screens the hero power and the
##   keyword chips too) with a button that opens the whole guide;
## - guide(): the whole guide (portrait, tagline, hero power, playstyle, the keywords with their help, tips);
## - open(): the guide as a modal over a dim veil, named "Dialog" so Esc / the Android back gesture close it
##   (Game.back → UI.cancel_dialog), as do its Close plate and a press outside the panel.
## Keyword chips show their help on a painted tip plate when hovered or tapped.
## Neutral and token cards have no class: note_strip() explains them in a line (NOTES).

const NOTES := {
	"neutral": ["Neutral", "Neutral cards fit in a deck of any class."],
	"token": ["Tokens", "Tokens are made by other cards during a match. You can't collect them or put them in a deck."],
}
const INK := UI.INK ## dark ink on parchment
const SHADE := Color(0.04, 0.01, 0.01) ## the dark edge of bone letters on the iron field
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")


# --- Pieces ------------------------------------------------------------------------------------------------------

## The hero's face in an oval with the gilded ring, `size` px (the ring overhangs it a little). A plain control,
## so containers can lay it out.
static func portrait(hero_id: String, size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.texture = CardDB.hero_art(hero_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.size = size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CARD_FX
	m.set_shader_parameter("mask_mode", 1)
	art.material = m
	c.add_child(art)
	if UiSkin.has("oval_ring"):
		c.add_child(UiSkin.rect("oval_ring", size * Vector2(1.2, 1.16), -size * Vector2(0.1, 0.08)))
	return c


## The hero power's painted disc (its icon on the bronze disc) with its cost on a mana gem, `px` wide.
static func power_disc(info: Dictionary, px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := str(info.get("power_icon", ""))
	var framed := UiSkin.has("class_emblem_frame")
	if UiSkin.has("power_disc"):
		# Under the painted emblem frame (art_src/deck_ui_art.json) the bronze disc only fills its open centre.
		var d := px * (0.66 if framed else 1.0)
		c.add_child(UiSkin.rect("power_disc", Vector2(d, d), Vector2(px - d, px - d) / 2.0))
	if UiSkin.has(icon):
		var k := px * 0.57
		var r := UiSkin.rect(icon, Vector2(k, k), Vector2(px - k, px - k) / 2.0)
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		c.add_child(r)
	if framed:
		var f := UiSkin.rect("class_emblem_frame", Vector2(px, px) * 1.12, -Vector2(px, px) * 0.06)
		f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		c.add_child(f)
	var g := px * 0.42
	var gem := Control.new()
	gem.size = Vector2(g, g)
	gem.position = Vector2(px - g * 0.8, -g * 0.2)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if UiSkin.has("gem_mana"):
		gem.add_child(UiSkin.rect("gem_mana", gem.size))
	var fs := roundi(g * 0.55)
	var cost := UI.raised(UI.label(str(int(info.get("power", {}).get("cost", 2))), fs, "title", UI.NUMBER, 4,
		Color(0, 0.02, 0.08)))
	cost.size = gem.size
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.center_ink(cost) # the number's ink on the gem's middle
	gem.add_child(cost)
	c.add_child(gem)
	return c


## A one-line heading in engraved gold, `px` tall letters, shrunk to `room` px when given.
static func gilded(text: String, px: int, room: float = 0.0, color: Color = UI.GOLD) -> Label:
	var l := UI.label(text, px, "title", color, maxi(3, px / 8), SHADE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if room > 0.0:
		UI.fit_label(l, room, maxi(13, px - 12))
	var h := l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")) + 4.0
	l.custom_minimum_size.y = h
	UI.gild(l, color, h)
	return l


## A wrapping text line, `room` px wide.
static func text(t: String, px: int, kind: String, color: Color, room: float, outline: int = 3) -> Label:
	var l := UI.label(t, px, kind, color, outline, SHADE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(room, 0)
	return l


## A small heading over a section of the guide: gilded capitals over a thin bronze rod.
static func section(title: String, room: float) -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.add_child(gilded(title.to_upper(), 22, room))
	if UiSkin.has("slider_track"):
		var rod := UiSkin.rect("slider_track", Vector2(room, 7))
		rod.custom_minimum_size = Vector2(room, 7)
		rod.modulate = Color(0.85, 0.75, 0.6)
		v.add_child(rod)
	return v


## A keyword as a small engraved plaque; hovering or tapping it shows the keyword's help on a tip plate under it.
static func chip(kw: String, px: int = 20) -> Button:
	var help: Array = UI.KEYWORD_HELP.get(kw, [kw.capitalize(), ""])
	var b := Button.new()
	b.text = str(help[0])
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", UI.GOLD)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.9, 0.6))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", SHADE)
	for st in [["normal", Color.WHITE], ["hover", Color(1.4, 1.2, 0.9)], ["pressed", Color(1.4, 1.2, 0.9)]]:
		b.add_theme_stylebox_override(st[0], UI.plaque_box(16, 5, st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_field(b)
	b.set_meta("keyword", kw)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -14.0)
		show_tip(b))
	b.mouse_exited.connect(func(): hide_tip(b))
	b.pressed.connect(func(): # a tap (touch has no hover) shows it too, and a second tap hides it
		if b.get_node_or_null("Tip") != null and b.has_meta("tapped"):
			hide_tip(b)
		else:
			show_tip(b)
			b.set_meta("tapped", true))
	return b


## Shows `chip`'s keyword help on the painted tip plate just under it (above it near the bottom of the screen).
static func show_tip(c: Control) -> void:
	if c.get_node_or_null("Tip") != null:
		return
	var help: Array = UI.KEYWORD_HELP.get(str(c.get_meta("keyword", "")), ["", ""])
	if str(help[1]) == "":
		return
	var tip := UI.tip_plate(str(help[0]), str(help[1]), 340.0)
	tip.name = "Tip"
	tip.top_level = true
	tip.z_index = 120
	c.add_child(tip)
	tip.reset_size()
	var r := c.get_global_rect()
	var vs := c.get_viewport_rect().size
	var at := Vector2(r.get_center().x - tip.size.x / 2.0, r.end.y + 4.0)
	if at.y + tip.size.y > vs.y - 8.0:
		at.y = r.position.y - tip.size.y - 4.0
	at.x = clampf(at.x, 8.0, vs.x - tip.size.x - 8.0)
	tip.global_position = at
	tip.modulate.a = 0.0
	tip.create_tween().tween_property(tip, "modulate:a", 1.0, 0.1)


static func hide_tip(c: Control) -> void:
	var tip := c.get_node_or_null("Tip")
	if tip != null:
		tip.queue_free()
		c.remove_child(tip)
	c.remove_meta("tapped")


## A round bronze disc with an engraved "i" (`tip` as its tooltip), `px` wide.
static func info_button(px: float = 52.0, tip: String = "Class guide") -> Button:
	var b := Button.new()
	b.text = "i"
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(px, px)
	b.size = b.custom_minimum_size
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("body")) # a lower-case "i" with its dot (Cinzel has capitals only)
	b.add_theme_font_size_override("font_size", roundi(px * 0.66))
	b.add_theme_color_override("font_color", Color(0.22, 0.09, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
	b.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.62, 0.35))
	b.add_theme_constant_override("shadow_offset_y", 2)
	for st in [["normal", Color(0.95, 0.9, 0.82)], ["hover", Color(1.2, 1.08, 0.9)], ["pressed", Color(0.75, 0.62, 0.5)]]:
		b.add_theme_stylebox_override(st[0], UI.frame_box("power_disc", 0, 0,
			UI.box(Color(0.1, 0.04, 0.03, 0.88), UI.GOLD_DARK, 3, int(px / 2)), st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -10.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.08, 0.08))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


# --- The strip ---------------------------------------------------------------------------------------------------

## A plaque `width` px wide about class `cls`: portrait, gilded class name and tagline, then (`full`) the hero power
## and the keyword chips, and a button that opens the whole guide (a "Class guide" plate when `full`, else the "i"
## disc). The parts that do not fit the width are left out, the guide button never.
static func strip(cls: String, width: float, full: bool = false) -> PanelContainer:
	var info := CardDB.class_info(cls)
	var tall := 96.0 if full else 62.0
	var p := UI.plaque(18, 6)
	p.name = "ClassStrip"
	p.custom_minimum_size = Vector2(width, tall)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16 if full else 12)
	p.add_child(row)
	var ph := tall - 20.0
	row.add_child(portrait(str(info.hero), Vector2(ph * 0.8, ph)))
	var guide_w := 240.0 if full else 46.0
	var room := width - 36.0 - ph * 0.8 - guide_w - 2.0 * row.get_theme_constant("separation")
	var name_v := VBoxContainer.new()
	name_v.alignment = BoxContainer.ALIGNMENT_CENTER
	name_v.add_theme_constant_override("separation", 0)
	name_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_v)
	if full:
		var head_w := minf(room, 420.0)
		name_v.custom_minimum_size.x = head_w
		name_v.add_child(gilded(str(info.title), 32, head_w))
		var tag := UI.label(str(info.tagline), 22, "italic", Color(0.95, 0.82, 0.55), 3, SHADE)
		UI.fit_label(tag, head_w, 16)
		name_v.add_child(tag)
		room -= head_w + 16.0
		# The hero power: its disc, then its name over its text.
		if room > 360.0:
			var pw := minf(room, 460.0)
			var power := HBoxContainer.new()
			power.add_theme_constant_override("separation", 10)
			power.mouse_filter = Control.MOUSE_FILTER_IGNORE
			power.custom_minimum_size.x = pw
			row.add_child(power)
			var pc := CenterContainer.new()
			pc.add_child(power_disc(info, 58.0))
			power.add_child(pc)
			var pv := VBoxContainer.new()
			pv.alignment = BoxContainer.ALIGNMENT_CENTER
			pv.add_theme_constant_override("separation", 0)
			power.add_child(pv)
			var hp: Dictionary = info.power
			pv.add_child(gilded("Hero power: %s" % hp.get("name", ""), 21, pw - 80.0))
			# One line when it fits (down to 16 px), else two smaller ones.
			var pt := text(str(hp.get("text", "")), 20, "body", UI.BONE, pw - 80.0)
			var pf := pt.get_theme_font("font")
			var ps := 20
			while ps > 16 and pf.get_string_size(pt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x > pw - 82.0:
				ps -= 1
			pt.add_theme_font_size_override("font_size", ps)
			pv.add_child(pt)
			room -= pw + 16.0
		# The keyword chips, as many as fit.
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 8)
		chips.alignment = BoxContainer.ALIGNMENT_CENTER
		var used := 0.0
		for kw in info.keywords:
			var c := chip(str(kw))
			var cw := c.get_combined_minimum_size().x
			if used + cw > room:
				c.queue_free()
				break
			used += cw + 8.0
			chips.add_child(c)
		if chips.get_child_count() > 0:
			row.add_child(chips)
		else:
			chips.queue_free()
	else:
		name_v.custom_minimum_size.x = room
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_v.add_child(line)
		var t := gilded(str(info.title), 28, room * 0.45)
		line.add_child(t)
		var tag := UI.label(str(info.tagline), 20, "italic", Color(0.95, 0.82, 0.55), 3, SHADE)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UI.fit_label(tag, room - t.get_combined_minimum_size().x - 14.0, 14)
		line.add_child(tag)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var b: Button
	if full:
		b = UI.button("Class guide", guide_w, 58)
		b.add_theme_font_size_override("font_size", 26)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		b = info_button(46.0, "%s class guide" % info.title)
	b.name = "GuideButton"
	b.pressed.connect(func(): open(p, cls))
	row.add_child(b)
	return p


## A plaque `width` px wide with the note about neutral or token cards (`what` is a key of NOTES).
static func note_strip(what: String, width: float) -> PanelContainer:
	var note: Array = NOTES.get(what, [what.capitalize(), ""])
	var p := UI.plaque(28, 8)
	p.name = "ClassStrip"
	p.custom_minimum_size = Vector2(width, 64)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(row)
	row.add_child(gilded(str(note[0]), 30))
	var t := UI.label(str(note[1]), 23, "italic", UI.BONE, 3, SHADE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.fit_label(t, width - 300.0, 16)
	row.add_child(t)
	return p


# --- The guide ---------------------------------------------------------------------------------------------------

## The whole guide to class `cls`, `width` px wide, in two columns: who (portrait, name, hero, tagline), the hero
## power and the playstyle on the left; the keywords with their help and the tips on the right.
static func guide(cls: String, width: float) -> Control:
	var info := CardDB.class_info(cls)
	var cols := HBoxContainer.new()
	cols.name = "ClassGuide"
	cols.add_theme_constant_override("separation", 48)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lw := floorf((width - 48.0) * 0.5)
	var rw := width - 48.0 - lw
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.custom_minimum_size.x = lw
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = rw
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right)
	# Who: the hero's portrait beside the class name, the hero, the tagline.
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 26)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(who)
	var pc := MarginContainer.new() # room for the ring, which overhangs the oval
	for side in ["left", "right"]:
		pc.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		pc.add_theme_constant_override("margin_" + side, 10)
	pc.add_child(portrait(str(info.hero), Vector2(112, 140)))
	who.add_child(pc)
	var wv := VBoxContainer.new()
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.add_theme_constant_override("separation", 2)
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(wv)
	var tw := lw - 136.0 - 26.0
	wv.add_child(gilded(str(info.title), 46, tw))
	var hn := UI.label(str(info.hero_name), 24, "italic", UI.BONE, 3, SHADE)
	UI.fit_label(hn, tw, 16)
	wv.add_child(hn)
	wv.add_child(text(str(info.tagline), 27, "italic", Color(0.95, 0.8, 0.5), tw))
	# The hero power.
	left.add_child(section("Hero power", lw))
	var hp: Dictionary = info.power
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 18)
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(prow)
	var dc := MarginContainer.new()
	dc.add_theme_constant_override("margin_top", 12)
	dc.add_child(power_disc(info, 78.0))
	prow.add_child(dc)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prow.add_child(pv)
	pv.add_child(gilded("%s  (%d mana)" % [hp.get("name", ""), int(hp.get("cost", 2))], 26, lw - 100.0))
	pv.add_child(text(str(hp.get("text", "")), 24, "body", UI.BONE, lw - 100.0))
	# The playstyle, inked on parchment.
	left.add_child(section("How it plays", lw))
	var parch := PanelContainer.new()
	parch.add_theme_stylebox_override("panel", UI.parchment_box(46, 30))
	parch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UI.label(str(info.style), 24, "body", INK)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(lw - 92.0, 0)
	parch.add_child(st)
	left.add_child(parch)
	# The keywords, each with its help.
	right.add_child(section("Keywords", rw))
	for kw in info.keywords:
		var help: Array = UI.KEYWORD_HELP.get(str(kw), [str(kw).capitalize(), ""])
		var kr := HBoxContainer.new()
		kr.add_theme_constant_override("separation", 14)
		kr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(kr)
		var c := chip(str(kw), 20)
		c.custom_minimum_size.x = 150.0
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE # its help is already beside it
		kr.add_child(c)
		var h := text(str(help[1]), 22, "body", UI.BONE, rw - 164.0)
		h.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kr.add_child(h)
	# The tips, each after a small ember gem.
	right.add_child(section("Tips", rw))
	for t in info.tips:
		var tip_row := HBoxContainer.new()
		tip_row.add_theme_constant_override("separation", 12)
		tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(tip_row)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(20, 28)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiSkin.has("rarity_legendary"):
			dot.add_child(UiSkin.rect("rarity_legendary", Vector2(18, 18), Vector2(1, 7)))
		tip_row.add_child(dot)
		tip_row.add_child(text(str(t), 22, "italic", UI.BONE, rw - 32.0))
	return cols


## The guide to class `cls` in a modal over a dim veil, added to the screen that holds `from` (its first ancestor
## with go_back(), so Esc and the back gesture find it), with a Close plate. Returns the modal.
static func open(from: Node, cls: String) -> Control:
	var scene: Node = from
	while scene.get_parent() != null and not scene.has_method("go_back"):
		scene = scene.get_parent()
	var old := scene.get_node_or_null("Dialog")
	if old != null:
		old.queue_free()
		scene.remove_child(old)
	var d := Control.new()
	d.name = "Dialog"
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d.z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(center)
	var panel := PanelContainer.new()
	var s := UI.frame_box("panel_frame_filled", 96, 0, UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14,
		Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = 84
	s.content_margin_right = 84
	s.content_margin_top = 74
	s.content_margin_bottom = 72
	panel.add_theme_stylebox_override("panel", s)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var vs := from.get_viewport().get_visible_rect().size if from.is_inside_tree() else Vector2(1920, 1080)
	v.add_child(guide(cls, minf(1400.0, vs.x - 340.0)))
	var close := UI.button("Close", 260, 64)
	close.add_theme_font_size_override("font_size", 30)
	close.pressed.connect(func(): d.queue_free())
	var cc := CenterContainer.new()
	cc.add_child(close)
	v.add_child(cc)
	d.set_meta("cancel", close)
	d.gui_input.connect(func(e): # a press on the veil, outside the panel, closes it too
		if e is InputEventMouseButton and e.pressed and not panel.get_global_rect().has_point(e.global_position):
			d.queue_free())
	scene.add_child(d)
	d.modulate.a = 0.0
	d.create_tween().tween_property(d, "modulate:a", 1.0, 0.15)
	Sfx.play("page", -6.0)
	return d
