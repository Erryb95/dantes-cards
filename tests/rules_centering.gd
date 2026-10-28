extends Node
## Optical centring of every card's rules text on its plate, measured on real pixels: each card is built by the game's
## own CardView at 1x, drawn as it looks (rules_look_<page>.png), then with everything but the rules text hidden and
## its letters pure white (rules_mask_<page>.png). The centre of the white ink's box is compared with the centre of
## the plate's visible parchment (inside the bronze rim on minions, between the scroll's ornament lines on spells).
##   Godot --path . res://tests/rules_centering.tscn --resolution 1920x1080 -- --out=<dir> [--max=2] [--only=a,b]
## Prints one line per card (dx, dy in px, the lines, "OVERFLOW" when the text needs more room than its box, "GEM n"
## when n of its ink px fall within 2 px of a minion's attack or health gem) and the worst; with --max=<px> it exits 1
## when one is further off, overflows or touches a gem. Needs a window.

## The visible parchment's centre on the card face (px at 1x), measured on the plate paintings: the minion
## cartouche's parchment runs 45..273 of its 315 px (at y 240, 104 px tall), the spell scroll's 69..255 of 285 (at
## y 240, 116 px tall). Written out, not read from CardView, so the same script measures an older build.
const MINION_CENTER := Vector2(125.0, 292.5)
const SPELL_CENTER := Vector2(125.0, 306.0)

var out := "user://rules_centering"
var max_px := -1.0
var only: PackedStringArray = []
var threshold := 0.5
var _gems: Array = [] ## [alpha image, rect on the card face] of the attack and health gems


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--max="):
			max_px = float(a.substr(6))
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	Game.intro_played = true
	# The gems as CardView lays them out (72 px at (28, H - 28) and (W - 28, H - 30)).
	for g in [["gem_attack", Vector2(28, CardView.H - 28)], ["gem_health", Vector2(CardView.W - 28, CardView.H - 30)]]:
		var img: Image = UiSkin.tex(g[0]).get_image()
		img.decompress()
		img.resize(72, 72)
		_gems.append([img, Rect2(g[1] - Vector2(36, 36), Vector2(72, 72))])
	var bg := ColorRect.new()
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var ids: Array = []
	for card in CardDB.all_cards():
		if only.is_empty() or only.has(card["id"]):
			ids.append(card["id"])
	var per_page := 14
	var lines: PackedStringArray = []
	var worst := 0.0
	var dys: Array = []
	var page := 0
	while page * per_page < ids.size():
		bg.color = Color(0.09, 0.07, 0.06)
		var holder := Node2D.new()
		add_child(holder)
		var samples: Array = [] # [id, card, text, cell rect, target]
		for i in mini(per_page, ids.size() - page * per_page):
			var id: String = ids[page * per_page + i]
			var at := Vector2(20 + (i % 7) * (CardView.W + 20), 20 + (i / 7) * (CardView.H + 40))
			var c := CardView.new().setup(id, -1, true)
			c.position = at + Vector2(CardView.W, CardView.H) / 2.0
			c.auto_tilt = false
			c.set_process(false)
			holder.add_child(c)
			var txt := _find_rules(c)
			if txt == null:
				continue
			var spell: bool = CardDB.card(id).get("type", "minion") == "spell"
			var target := at + (SPELL_CENTER if spell else MINION_CENTER)
			samples.append([id, c, txt, Rect2(at + Vector2(0, 228), Vector2(CardView.W, 120)), target, at, spell])
		await _frames(6)
		get_viewport().get_texture().get_image().save_png(out + "/rules_look_%d.png" % page)
		bg.color = Color.BLACK
		for s in samples:
			_isolate(s[1], s[2])
		await _frames(4)
		var img := get_viewport().get_texture().get_image()
		img.save_png(out + "/rules_mask_%d.png" % page)
		for s in samples:
			var txt: RichTextLabel = s[2]
			var ink := _ink_box(img, s[3])
			var over := txt.get_content_height() > txt.size.y + 0.5
			if ink.size.x <= 0:
				lines.append("%-26s no ink found" % s[0])
				worst = INF
				continue
			var d: Vector2 = ink.get_center() - s[4]
			dys.append(d.y)
			worst = maxf(worst, maxf(absf(d.x), absf(d.y)))
			var touch := 0 if s[6] else _gem_touch(img, s[3], s[5])
			if over or touch > 0:
				worst = INF
			lines.append("%-26s dx %+5.1f  dy %+5.1f  lines %d  size %d%s%s" % [s[0], d.x, d.y, txt.get_line_count(),
				txt.get_theme_font_size("normal_font_size"), "  OVERFLOW" if over else "",
				"  GEM %d" % touch if touch > 0 else ""])
		holder.queue_free()
		await _frames(2)
		page += 1
	for l in lines:
		print(l)
	var mean := 0.0
	for d in dys:
		mean += d / maxf(1.0, dys.size())
	print("RULES CENTRING: worst %.1f px, mean dy %+.1f px over %d cards" % [worst, mean, lines.size()])
	var f := FileAccess.open(out + "/rules_offsets.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nworst %.1f px, mean dy %+.1f\n" % [worst, mean])
	get_tree().quit(1 if max_px >= 0.0 and worst > max_px else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find_rules(n: Node) -> RichTextLabel:
	for c in n.get_children():
		if c is RichTextLabel:
			return c
		var r := _find_rules(c)
		if r != null:
			return r
	return null


## Hides everything of the card but its rules text, and draws that text pure white without the card's shader.
func _isolate(card: Node, txt: RichTextLabel) -> void:
	var line := {}
	var n: Node = txt
	while n != null and n != card.get_parent():
		line[n] = true
		n = n.get_parent()
	_hide_rest(card, line)
	txt.material = null
	txt.use_parent_material = false
	txt.modulate = Color.WHITE
	txt.self_modulate = Color.WHITE
	txt.add_theme_color_override("default_color", Color.WHITE)
	txt.add_theme_constant_override("outline_size", 0)
	# The tags keep their colour codes: drop them so every letter is white.
	txt.text = txt.text.replace("[color=", "[_c=")


func _hide_rest(x: Node, line: Dictionary) -> void:
	for c in x.get_children():
		if not (c is CanvasItem):
			continue
		if not line.has(c):
			(c as CanvasItem).visible = false
		else:
			(c as CanvasItem).material = null
			(c as CanvasItem).use_parent_material = false
			_hide_rest(c, line)
	if x is CanvasItem:
		(x as CanvasItem).material = null


## How many ink px in `cell` lie within 2 px of an opaque px of a gem (card face at `face`).
func _gem_touch(img: Image, cell: Rect2, face: Vector2) -> int:
	var n := 0
	var r := Rect2i(cell).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).v <= threshold:
				continue
			var p := Vector2(x, y) - face
			for g in _gems:
				var gr: Rect2 = g[1]
				if not gr.grow(2).has_point(p):
					continue
				var gi: Image = g[0]
				var hit := false
				for oy in range(-2, 3):
					for ox in range(-2, 3):
						var q := Vector2i(p - gr.position) + Vector2i(ox, oy)
						if q.x >= 0 and q.y >= 0 and q.x < 72 and q.y < 72 and gi.get_pixel(q.x, q.y).a > 0.5:
							hit = true
				if hit:
					n += 1
	return n


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
