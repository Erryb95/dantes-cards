class_name ManaCurve
extends Control
## A deck's mana curve: for each cost (0 to 7+) a bronze rod as tall as the copies at that cost, the count engraved
## above it, standing on the mana gem of that cost. Used by the deck builder and the Choose your path showcase.
## Set `counts` (see counts_of) and the curve redraws itself; `gem` is the gem size in px.

var counts: Array = [0, 0, 0, 0, 0, 0, 0, 0]:
	set(v):
		counts = v
		queue_redraw()
var gem := 36.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	paint(self, size, counts, gem)


## The copies of a deck's cards ({id: count}) at each cost 0..6, and 7+ in the last slot.
static func counts_of(cards: Dictionary) -> Array:
	var out := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in cards:
		out[clampi(int(CardDB.card(id).get("cost", 0)), 0, 7)] += int(cards[id])
	return out


## Draws the curve on `ci` in a box of `box` px: the rods on the bars' strips of the gilded button plate turned
## upright (its gold field between the bronze rims), the counts in bone above them, the gems along the bottom.
static func paint(ci: CanvasItem, box: Vector2, counts: Array, gem: float = 36.0) -> void:
	var top: int = maxi(4, counts.max())
	var w := box.x / 8.0
	var f := UI.font("title")
	var fs := maxi(13, roundi(gem * 0.53)) ## the digits' size on the gems and above the rods (never below 13 px)
	var rod_w := roundf(gem * 0.61)
	var base := box.y - gem ## the rods stand on the gems
	var tall := base - fs - 5.0 ## room left for the count above the tallest rod
	var rod: Texture2D = UI.upright_tex("menu_plate", 22) if UiSkin.has("menu_plate") else null
	for i in 8:
		var cx := i * w + w / 2
		if counts[i] > 0:
			var h: float = maxf(gem * 0.28, tall * counts[i] / float(top))
			var r := Rect2(cx - rod_w / 2, base - h + 2, rod_w, h)
			if rod != null:
				var src := Rect2(0, 24, 22, rod.get_height() - 48) # the plain middle, without the scrollwork ends
				ci.draw_texture_rect_region(rod, r, src)
				ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1.0, 0.85, 0.5, 0.8)) # the cut top edge
			else:
				ci.draw_rect(r, UI.GOLD.darkened(0.2))
			# The count's ink centred on the rod, its foot 5 px above the rod's top.
			var ink := UI.ink_rect(f, fs, str(counts[i]))
			_ink_string(ci, f, str(counts[i]), Vector2(cx, r.position.y - 5.0 - ink.end.y + ink.get_center().y), fs,
				4, Color(0.04, 0.01, 0.01), UI.BONE)
		var g := Rect2(cx - gem / 2, base, gem, gem)
		if UiSkin.has("gem_mana"):
			ci.draw_texture_rect(UiSkin.tex("gem_mana"), g, false,
				Color.WHITE if counts[i] > 0 else Color(0.55, 0.55, 0.62))
		# The digit's ink on the gem's middle; the last gem is "7+": the digit a little left and a bold drawn "+"
		# (Cinzel's own is a hairline).
		_ink_string(ci, f, str(i), g.get_center() - Vector2(gem * 0.11 if i == 7 else 0.0, 0.0), fs,
			maxi(3, roundi(gem / 7.0)), Color(0, 0.02, 0.08), UI.NUMBER)
		if i == 7:
			draw_plus(ci, g.get_center() + Vector2(gem * 0.2, 0), gem / 9.0, maxf(1.5, gem / 18.0), maxf(1.0, gem / 24.0))


## Draws `text` with the middle of its ink (UI.ink_rect: the letters themselves, not their line box) at `c`.
static func _ink_string(ci: CanvasItem, f: Font, text: String, c: Vector2, fs: int, outline: int, edge: Color,
		color: Color) -> void:
	var ink := UI.ink_rect(f, fs, text)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# ink_rect is measured from the middle of the text's line box: put that middle where the ink lands on `c`.
	var at := c - ink.get_center() + Vector2(-w / 2.0, f.get_ascent(fs) - f.get_height(fs) / 2.0)
	ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, edge)
	ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## A bold "+" centred at `c` (arms `arm` px from the centre, `thick` px wide) in the gem digits' colour, ringed in
## their dark outline: Cinzel's own "+" is too thin to read on a small gem.
static func draw_plus(ci: CanvasItem, c: Vector2, arm: float, thick: float, rim: float) -> void:
	for pass_ in [[rim, Color(0, 0.02, 0.08)], [0.0, UI.NUMBER]]:
		var o: float = pass_[0]
		ci.draw_rect(Rect2(c.x - arm - o, c.y - thick / 2 - o, 2 * (arm + o), thick + 2 * o), pass_[1])
		ci.draw_rect(Rect2(c.x - thick / 2 - o, c.y - arm - o, thick + 2 * o, 2 * (arm + o)), pass_[1])
