class_name DropRatesPanel
## The pack odds, shown to the player on a painted parchment sheet (dark ink, never a dark box) under a "Drop rates"
## banner. Every number comes from Collection (ODDS, PACK_SIZE, PITY_LEGENDARY, REFUND, packs_since_legendary), so
## the panel can never say something the pack roll does not do.
## - rows(): the per-slot chance of each rarity, best first, as [rarity, chance, "1.5%"];
## - sheet(): the parchment with the odds, the pack rules and the pity counter;
## - open(): the sheet as a modal over a dim veil with a Close plate. The modal is a CanvasLayer named "Dialog", so
##   Esc / the Android back gesture close it (Game.back -> UI.cancel_dialog), as do Close and a press outside the sheet.

const INK := ClassInfoPanel.INK ## dark ink on parchment
const TRACK := Color(0.32, 0.2, 0.1, 0.28) ## the groove of a bar, a darker stain in the parchment


## [[rarity, chance, text]] for one card slot, best first. A common is whatever the others leave.
static func rows() -> Array:
	var out := []
	var rates := Collection.drop_rates()
	for r in Collection.RARITY_ORDER:
		out.append([r, rates[r], Collection.percent_text(rates[r])])
	return out


## The pity counter as the sheet words it.
static func pity_text() -> String:
	return Loc.t("Packs since your last Legendary: %d / %d") % [mini(Collection.packs_since_legendary, Collection.PITY_LEGENDARY),
		Collection.PITY_LEGENDARY]


static func _ink(text: String, px: int, kind: String = "body") -> Label:
	var l := UI.label(text, px, kind, INK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A groove with `ratio` (0..1) of it filled with `color`: the share of a rarity, or the progress to the pity pack.
static func _bar(ratio: float, color: Color, h: float = 14.0) -> Control:
	var track := Panel.new() # a plain panel: a container would stretch the fill over the whole groove
	track.custom_minimum_size = Vector2(0, h)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_theme_stylebox_override("panel", UI.box(TRACK, Color(0.3, 0.18, 0.08, 0.5), 1, int(h / 2)))
	var fill := ColorRect.new()
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	track.resized.connect(func():
		fill.position = Vector2(1, 1)
		fill.size = Vector2(maxf(3.0, (track.size.x - 2.0) * clampf(ratio, 0.0, 1.0)), track.size.y - 2.0))
	return track


## The ink sheet, `width` px wide: the chance of each rarity per card, the pack rules, the pity counter.
static func sheet(width: float) -> PanelContainer:
	var parch := PanelContainer.new()
	parch.name = "DropRates"
	parch.add_theme_stylebox_override("panel", UI.parchment_box(56, 34))
	parch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := width - 112.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size.x = inner
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parch.add_child(v)
	var intro := _ink(Loc.t("Each of the %d cards in a pack has this chance:") % Collection.PACK_SIZE, 26, "italic")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	for row in rows():
		var r: String = row[0]
		var h := HBoxContainer.new()
		h.name = "Row_" + r
		h.add_theme_constant_override("separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var gem := Control.new()
		gem.custom_minimum_size = Vector2(36, 36)
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiSkin.has("rarity_" + r):
			gem.add_child(UiSkin.rect("rarity_" + r, Vector2(34, 34), Vector2(1, 1)))
		h.add_child(gem)
		var name_l := _ink(r.capitalize(), 30, "title")
		name_l.custom_minimum_size.x = 200.0
		UI.fit_label(name_l, 200.0, 22) # a longer translated name ("Leggendaria") shrinks instead of pushing its bar
		h.add_child(name_l)
		var share: Color = UI.RARITY.get(r, UI.GOLD).darkened(0.3)
		h.add_child(_bar(float(row[1]), share))
		var pct := _ink(str(row[2]), 32, "title")
		pct.name = "Rate_" + r
		pct.custom_minimum_size.x = 104.0
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pct)
	v.add_child(_rod(inner))
	for t in [
		"Every pack holds at least one Rare or better.",
		Loc.t("A Legendary is guaranteed within %d packs.") % Collection.PITY_LEGENDARY,
	]:
		var line := _ink(t, 26)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = inner
		v.add_child(line)
	# The pity counter, with its progress to the pack that must hold a Legendary.
	var pity := _ink(pity_text(), 26, "title")
	pity.name = "Pity"
	pity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pity)
	var pb := _bar(float(Collection.packs_since_legendary) / float(Collection.PITY_LEGENDARY), UI.RARITY.legendary.darkened(0.2), 18.0)
	v.add_child(pb)
	# What a spare copy is worth.
	var refunds := []
	for r in ["common", "rare", "epic", "legendary"]:
		refunds.append("%s %d" % [Loc.t(r.capitalize()), int(Collection.REFUND[r])])
	var spare := _ink(Loc.t("Spare copies turn into Obols: %s.") % ", ".join(refunds), 22, "italic")
	spare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spare.custom_minimum_size.x = inner
	v.add_child(spare)
	return parch


## A thin bronze rod across the sheet.
static func _rod(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 7)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if UiSkin.has("slider_track"):
		var rod := UiSkin.rect("slider_track", Vector2(w, 7))
		rod.modulate = Color(0.85, 0.7, 0.5)
		c.add_child(rod)
	return c


## The sheet in a modal over a dim veil, with a Close plate, added to the scene that holds `from` (its first ancestor
## with go_back(), so Esc and the back gesture find it). A layer of its own, so it also sits right over a Node2D scene
## whose camera shakes. Returns the modal.
static func open(from: Node) -> CanvasLayer:
	var scene: Node = from
	while scene.get_parent() != null and not scene.has_method("go_back"):
		scene = scene.get_parent()
	var old := scene.get_node_or_null("Dialog")
	if old != null:
		old.queue_free()
		scene.remove_child(old)
	var layer := CanvasLayer.new()
	layer.name = "Dialog"
	layer.layer = 40
	var d := Control.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(d)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82) # dark enough that the pack and its "Click to open" ribbon behind do not read
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_STOP # a press on the sheet or the banner does not close it
	center.add_child(col)
	var vs := from.get_viewport().get_visible_rect().size if from.is_inside_tree() else Vector2(1920, 1080)
	var banner := UI.banner("Drop rates", 46)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(banner)
	col.add_child(sheet(minf(820.0, vs.x - 120.0)))
	var close := UI.button("Close", 260, 64)
	close.add_theme_font_size_override("font_size", 30)
	close.pressed.connect(func(): layer.queue_free())
	var cc := CenterContainer.new()
	cc.add_child(close)
	col.add_child(cc)
	layer.set_meta("cancel", close)
	d.gui_input.connect(func(e): # a press on the veil, outside the sheet, closes it too
		if e is InputEventMouseButton and e.pressed and not col.get_global_rect().has_point(e.global_position):
			layer.queue_free())
	scene.add_child(layer)
	d.modulate.a = 0.0
	d.create_tween().tween_property(d, "modulate:a", 1.0, 0.15)
	Sfx.play("page", -6.0)
	return layer
