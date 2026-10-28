extends Node
## Optical centring, measured on real pixels: card names on their ribbon, stat numbers on their gems, banner
## headings, name ribbons, plate buttons, plaques and parchment notes, each built by the game's own code at 1x.
## Every sample is drawn twice: as it looks (ink_look.png, for review), then with everything but its letters made
## invisible and the letters pure white (ink_mask.png). The centre of the white ink's box is compared with the centre
## of the frame it should sit in (the ribbon's band, the gem's visual centre, the plate's middle...).
##   Godot --path . res://tests/ink_centering.tscn --resolution 1920x1080 -- --out=<dir> [--max=2]
## Prints one line per sample (dx, dy in px) and the worst; with --max=<px> it exits 1 when one is further off.
## Needs a window (headless runs draw nothing): menu_smoke checks the same layout from the glyph outlines instead.
## Only uses code that the game had before optical centring too, so the same script measures an older build.

var out := "user://ink_centering"
var max_px := -1.0
var threshold := 0.5 ## a pixel is ink when it is brighter than this
var samples: Array = [] ## [name, node, frame centre (global px, or a Callable giving it), cell rect]
var _cell := Vector2.ZERO
var _row_h := 0.0
var _pos := Vector2(20, 20)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--max="):
			max_px = float(a.substr(6))
		elif a.begins_with("--threshold="):
			threshold = float(a.substr(12))
	DirAccess.make_dir_recursive_absolute(out)
	Game.intro_played = true
	var bg := ColorRect.new()
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var worst := 0.0
	var lines: PackedStringArray = []
	if OS.get_cmdline_user_args().has("--probe"):
		await _probe(bg)
	for page in 2:
		bg.color = Color(0.09, 0.07, 0.06)
		samples.clear()
		var holder := Node2D.new()
		add_child(holder)
		_build(page, holder)
		await _frames(6)
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(out + "/ink_look_%d.png" % page)
		bg.color = Color.BLACK
		_whiten(holder)
		await _frames(4)
		var img := get_viewport().get_texture().get_image()
		img.save_png(out + "/ink_mask_%d.png" % page)
		for s in samples:
			var ink := _ink_box(img, s[3])
			if ink.size.x <= 0:
				lines.append("%-34s no ink found" % s[0])
				worst = INF
				continue
			var ctr: Vector2 = s[2].call() if s[2] is Callable else s[2]
			var d: Vector2 = ink.get_center() - ctr
			worst = maxf(worst, maxf(absf(d.x), absf(d.y)))
			var extra := ""
			if OS.get_cmdline_user_args().has("--probe") and s[1] is Label:
				var sb: StyleBox = (s[1] as Label).get_theme_stylebox("normal")
				extra = "  size %s margins l %.2f r %.2f t %.2f b %.2f" % [(s[1] as Label).size, sb.get_margin(SIDE_LEFT),
					sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_TOP), sb.get_margin(SIDE_BOTTOM)]
				var lab := s[1] as Label
				var lay := UI.text_layout(lab.get_theme_font("font"), lab.get_theme_font_size("font_size"), lab.text)
				extra += "  char0 %s last %s block %s" % [lab.get_character_bounds(0), lab.get_character_bounds(lab.text.length() - 1), lay["block"]]
			lines.append("%-34s dx %+5.1f  dy %+5.1f   ink %s%s" % [s[0], d.x, d.y, ink, extra])
		holder.queue_free()
		await _frames(2)
	for l in lines:
		print(l)
	print("INK CENTRING: worst %.1f px over %d samples" % [worst, lines.size()])
	var f := FileAccess.open(out + "/ink_offsets.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("
".join(lines) + "
worst %.1f px
" % worst)
	get_tree().quit(1 if max_px >= 0.0 and worst > max_px else 0)


## Debug: big letters (240 px) drawn at a known origin, their drawn box against their outlines' (UI.ink_rect).
func _probe(bg: ColorRect) -> void:
	bg.color = Color.BLACK
	var plain := FontFile.new() # the title face drawn from plain outlines (no MSDF), for comparison
	plain.data = (UI.font("title") as FontFile).data
	for set in [["title", "HxgQ"], ["body", "Hxpg"], ["plain", "Hx"]]:
		var holder := Node2D.new()
		add_child(holder)
		var probes := []
		var x := 30.0
		for ch in set[1]:
			var l := UI.label(ch, 240, "title" if set[0] == "plain" else set[0], Color.WHITE)
			if set[0] == "plain":
				l.add_theme_font_override("font", plain)
			l.position = Vector2(x, 300)
			holder.add_child(l)
			probes.append([ch, l])
			x += 330
		await _frames(4)
		var img := get_viewport().get_texture().get_image()
		for p in probes:
			var l: Label = p[1]
			var f := l.get_theme_font("font")
			var ib := UI.ink_rect(f, 240, p[0])
			var adv := f.get_string_size(p[0], 0, -1, 240).x
			# ink_rect is centred on the block: back to the glyph origin (left end of the line, on the baseline).
			var o := Rect2(ib.position + Vector2(adv / 2.0, f.get_height(240) / 2.0 - f.get_ascent(240)), ib.size)
			var origin := l.position + Vector2(0, f.get_ascent(240))
			var d := _ink_box(img, Rect2(l.position - Vector2(20, 20), Vector2(320, 420)))
			d.position -= origin
			print("probe %s '%s': outline x %.1f..%.1f y %.1f..%.1f | drawn x %.1f..%.1f y %.1f..%.1f | k %.3f x %.3f" % [
				set[0], p[0], o.position.x, o.end.x, o.position.y, o.end.y, d.position.x, d.end.x, d.position.y, d.end.y,
				d.size.y / o.size.y, d.size.x / o.size.x])
		holder.queue_free()
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Starts a new row of samples `h` px tall.
func _row(h: float) -> void:
	_pos = Vector2(20, _pos.y + _row_h + 14)
	_row_h = h


func _cell_at(w: float) -> Vector2:
	if _pos.x + w > 1900:
		_row(_row_h)
	var at := _pos
	_pos.x += w + 14
	return at


func _add(name: String, n: CanvasItem, frame_center: Variant, cell: Rect2) -> void:
	samples.append([name, n, frame_center, cell])


func _build(page: int, holder: Node) -> void:
	_row_h = 0.0
	_pos = Vector2(20, 6)
	if page == 1:
		_build_frames(holder)
		return
	# Card names and stat numbers on full cards (scale 1: 250 x 360).
	_row(CardView.H)
	for id in ["minos", "francesca", "pj_beatrice", "harpy", "lost_pilgrim", "ugolino", "charon_ferry"]:
		if CardDB.card(id).is_empty():
			continue
		var at := _cell_at(CardView.W)
		var c := CardView.new().setup(id, -1, true)
		c.position = at + Vector2(CardView.W, CardView.H) / 2.0
		c.auto_tilt = false
		c.set_process(false)
		holder.add_child(c)
		var face := at
		var name_l := _find_name(c)
		var band := Vector2(CardView.W / 2.0, 196.0 - 6.0 + 54.0 * 0.479)
		_add("card name " + id, name_l, face + band, Rect2(face + Vector2(0, band.y - 28), Vector2(CardView.W, 56)))
		var is_spell: bool = CardDB.card(id).get("type", "minion") == "spell"
		var gems := [["cost", c._cost_label, Vector2(28, 28), "gem_mana", 76.0]]
		if not is_spell:
			gems.append(["attack", c._atk_label, Vector2(28, CardView.H - 28), "gem_attack", 74.0])
			gems.append(["health", c._hp_label, Vector2(CardView.W - 28, CardView.H - 30), "gem_health", 74.0])
		for g in gems:
			var ctr: Vector2 = face + g[2] + UI.GEM_CENTER.get(g[3], Vector2.ZERO) * float(g[4])
			_add("card %s %s (%s)" % [g[0], id, (g[1] as Label).text], g[1], ctr, Rect2(ctr - Vector2(36, 34), Vector2(72, 68)))
	# Numbers that change: a card's cost and stats set to every width of value.
	_row(CardView.H)
	for v in [[1, 1, 1], [7, 10, 4], [10, 12, 30]]:
		var at := _cell_at(CardView.W)
		var c := CardView.new().setup("lost_pilgrim", -1, true)
		c.position = at + Vector2(CardView.W, CardView.H) / 2.0
		c.auto_tilt = false
		c.set_process(false)
		holder.add_child(c)
		c.set_cost(v[0])
		c.set_stats(v[1], v[2], 30)
		var gems := [["cost", c._cost_label, Vector2(28, 28), "gem_mana", 76.0],
			["attack", c._atk_label, Vector2(28, CardView.H - 28), "gem_attack", 74.0],
			["health", c._hp_label, Vector2(CardView.W - 28, CardView.H - 30), "gem_health", 74.0]]
		for g in gems:
			var ctr: Vector2 = at + g[2] + UI.GEM_CENTER.get(g[3], Vector2.ZERO) * float(g[4])
			_add("set %s %s" % [g[0], (g[1] as Label).text], g[1], ctr, Rect2(ctr - Vector2(36, 34), Vector2(72, 68)))


## Page 2: banner headings, ribbons, plate buttons, plaques and notes.
func _build_frames(holder: Node) -> void:
	# Banner headings set in the font (the ones with painted words are pictures, centred by their opaque box).
	_row(110)
	for b in [["Choose Your Hero", 48, 1.8], ["Options", 54, 1.8], ["Online duel", 58, 1.8], ["DISCONNECTED", 60, 2.0],
			["Sign in with Google", 50, 1.8]]:
		var ban := UI.banner(b[0], b[1], UI.GOLD, 0.0, 0.0, b[2])
		var at := _cell_at(ban.custom_minimum_size.x)
		ban.position = at
		holder.add_child(ban)
		var l: Label = ban.get_node("Text")
		var h := roundf(float(b[1]) * float(b[2]))
		var ctr := at + ban.custom_minimum_size / 2.0 + Vector2(0, 0.031 * h if UiSkin.has("turn_banner") else 0.0)
		_add("banner " + b[0], l, ctr, Rect2(at, ban.custom_minimum_size))
	# Name ribbons.
	_row(140)
	for r in [["Start here", 230.0, 28], ["Virgil", 300.0, 40], ["The Pilgrim's Way", 700.0, 40], ["Your hero", 230.0, 30]]:
		var rib := UI.ribbon(r[0], r[1], r[2])
		var at := _cell_at(r[1])
		var h: float = float(r[1]) * 144.0 / 768.0
		rib.position = at
		holder.add_child(rib)
		var ctr := at + Vector2(r[1], h) / 2.0 + Vector2(0, -0.021 * h)
		_add("ribbon " + r[0], rib.get_node("Text"), ctr, Rect2(at, Vector2(r[1], h)))
	# Plate buttons (their content box is the plate's middle).
	_row(90)
	for b in [["Play", 420.0, 84.0], ["How to Play", 330.0, 84.0], ["Back", 260.0, 84.0], ["Menu", 150.0, 56.0],
			["Quit", 420.0, 84.0], ["Sign in with Google", 420.0, 84.0]]:
		var btn := UI.button(b[0], b[1], b[2])
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE # the pointer may rest anywhere: no hover sink
		btn.focus_mode = Control.FOCUS_NONE
		var at := _cell_at(b[1])
		btn.position = at
		btn.size = Vector2(b[1], b[2])
		holder.add_child(btn)
		# A plate grows past its asked height when its letters need it: the frame is the button as laid out.
		_add("button " + b[0], btn, _rect_centre.bind(btn), Rect2(at - Vector2(0, 6), Vector2(b[1], b[2] + 18)))
	# The end-turn seal's words as the battle sets them: blank first, then each turn's words refitted in the same box.
	for words in [["END TURN", 28], ["ENEMY TURN", 24]]:
		var room := Vector2(236, 150) * Vector2(0.56, 0.5)
		var el := UI.engraved(UI.label("END TURN", 28, "title"))
		var at := _cell_at(room.x + 20)
		el.size = room
		el.position = at
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var ui_script := load("res://scripts/ui/ui.gd") as Script # (an older build has no center_ink: then as it was)
		var has_ink := ui_script.get_script_method_list().any(func(m): return m.name == "center_ink")
		if has_ink:
			ui_script.call("center_ink", el)
		holder.add_child(el)
		el.text = ""
		el.text = words[0]
		el.add_theme_font_size_override("font_size", words[1])
		UI.fit_label(el, room.x, 16) # as _set_end_button shrinks them into the field
		el.size = room
		el.position = at
		if has_ink:
			ui_script.call("center_ink", el)
		_add("end seal " + words[0], el, at + room / 2.0, Rect2(at - Vector2(10, 10), room + Vector2(20, 20)))
	# Plaques, parchment notes and toasts (PanelContainers sized around their text).
	_row(110)
	var plates := [
		["plaque Wrath", UI.plaque_label("Wrath", 30, "title", UI.EMBER, 0.0, 30, 10)],
		["plaque 120 / 296 cards", UI.plaque_label("120 / 296 cards", 28, "title", UI.BONE, 0.0, 24, 8)],
		["plaque Dante (name plate)", UI.plaque_label("Dante", 26, "title", UI.GOLD, 300.0, 22, 6)],
		["plaque v0.8.2", UI.plaque_label("v0.8.2", 20, "body", UI.BONE, 0.0, 16, 4)],
		["note Not enough mana", UI.parchment_label("Not enough mana", 30, "title", UI.INK_RED, 0.0, 34, 12)],
		["note It counts as a loss.", UI.parchment_label("It counts as a loss.", 30, "italic", UI.INK, 0.0, 40, 12)],
		["note two lines", UI.parchment_label("Your opponent left.\nYou win the duel.", 30, "italic", UI.INK, 0.0, 30, 14)],
		["note Typing quietly", UI.parchment_label("Typing quietly, dying gently", 24, "italic", UI.INK, 0.0, 30, 14)],
	]
	for p in plates:
		var pc: PanelContainer = p[1]
		holder.add_child(pc)
		pc.reset_size()
		var sz := pc.get_combined_minimum_size()
		var at := _cell_at(sz.x)
		pc.position = at
		_add(p[0], pc.get_node("Text"), _rect_centre.bind(pc), Rect2(at, sz))


func _rect_centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## The card's name label (the gilded one on the ribbon).
func _find_name(c: CardView) -> Label:
	var best: Label = null
	for l in c.find_children("*", "Label", true, false):
		if l.material is ShaderMaterial and (l.material as ShaderMaterial).get_shader_parameter("gild") == true:
			best = l
	return best


## Everything on the page but the samples' letters becomes invisible; the letters go pure white, no outline or shadow.
## The branches beside a sample are hidden, its ancestors keep their place but draw nothing of their own.
func _whiten(holder: Node) -> void:
	var keep := {}
	var line := {holder: true}
	for s in samples:
		keep[s[1]] = true
		var n: Node = s[1]
		while n != holder and n != null:
			line[n] = true
			n = n.get_parent()
	_hide_all(holder, keep, line)


func _hide_all(x: Node, keep: Dictionary, line: Dictionary) -> void:
	if x is CanvasItem and not line.has(x):
		(x as CanvasItem).visible = false
		return
	if x is CanvasItem:
		var ci := x as CanvasItem
		if keep.has(x):
			ci.self_modulate = Color.WHITE
			ci.modulate = Color.WHITE
			ci.material = null
			ci.use_parent_material = false
			var c := x as Control
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
				c.add_theme_color_override(k, Color.WHITE)
			c.add_theme_constant_override("outline_size", 0)
			c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			c.add_theme_constant_override("shadow_outline_size", 0)
			if x is Button:
				for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
					var sb := c.get_theme_stylebox(st)
					var e := StyleBoxEmpty.new()
					for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
						e.set_content_margin(side, sb.get_margin(side) if sb != null else 0.0)
					c.add_theme_stylebox_override(st, e)
		else:
			ci.self_modulate = Color(1, 1, 1, 0)
			ci.material = null
	for ch in x.get_children(true):
		_hide_all(ch, keep, line)


## The white ink's box inside `cell` (pixels brighter than half).
func _ink_box(img: Image, cell: Rect2) -> Rect2:
	var r := Rect2i(cell).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).v > threshold:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2()
	return Rect2(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
