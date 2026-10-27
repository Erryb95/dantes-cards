extends Control
## Choose your path: pick a deck from the library on the right, see it in the showcase on the left, then Play. The
## opponent plays a random preconstructed deck of another class.
##
## The library shows each deck as a physical deck: a stack of cards whose gilded edges show under the face (its key
## card's painting), a corner tag (Starter, Premade or Custom) and the name on an engraved plaque with the card
## count. Decks are grouped by class under a class plaque (hero, class name, tagline, the "i" disc that opens the
## class guide: ClassInfoPanel), with a New deck slot at the end of each class. The selected deck lifts and burns
## with a gold aura. The library scrolls (wheel, drag, the bronze discs step a class or a row at a time), so any
## number of decks and classes fits.
##
## The showcase holds the hero between their hero power and the deck's mana curve, the name on the red ribbon, the
## class's tagline and the deck's plan on parchment, the three key cards (hover or tap one to see it big), View cards
## (the whole list, each card zoomable), Class guide, Play, and Edit for the player's own decks.

const SHOW_W := 640.0 ## the showcase panel
const LIB_COLS := 4
const DECK_W := 180.0 ## a deck's cell in the library
const DECK_GAP := 18.0
const DECK_H_MIN := 196.0 ## a deck cell's height range (_library sizes it from the room the screen gives)
const DECK_H_MAX := 250.0
const STACK := 12.0 ## how far the cards under the face show (right, and a little down)
const PLAQUE_H := 52.0 ## the name plaque at the foot of a deck
const HEAD_H := 62.0 ## a class plaque over its decks
const SECTION_GAP := 18.0
const FRAME_PAD := 64.0 ## room the bronze frame's ornament takes on each side of a big panel
const ARROW_SIZE := 62.0
const PLAQUE_TEXT_H := 100.0 ## tagline + plan text inside the showcase's parchment
const FEATURED_SCALE := 0.34 ## the three featured cards in the showcase, on a 1080 px tall screen
const FEATURED_SCALE_MAX := 0.5 ## the most they grow on a taller screen (three still fit the showcase's width)
const FEATURED_TILT := 0.12 ## radians the two side cards fan out
const PEEK_SCALE := 1.2 ## a key card shown big beside the showcase (on a 1080 px tall screen)
const INK := UI.INK
const INK_RED := UI.INK_RED
const SHADE := Color(0.04, 0.01, 0.01)
const TAGS := {"starter": ["Starter", Color(0.98, 0.78, 0.4)], "premade": ["Premade", Color(0.9, 0.85, 0.76)],
	"custom": ["Custom", Color(1.0, 0.55, 0.3)]}

var _entries: Array = [] ## every deck the library can show (see _all_entries)
var _selected := "" ## key of the deck in the showcase
var _filter := "all"
var _list: VBoxContainer ## the library's sections (one per class shown)
var _scroll: ScrollContainer
var _tabs := {}
var _scroll_btns: Array = []
var _cell := Vector2(DECK_W, 214) ## a deck's cell, set by _library from the room the screen gives
var _feat_scale := FEATURED_SCALE ## the featured cards' scale, set by _showcase from the room the screen gives
# Showcase parts, refilled by _show().
var _portrait: Control
var _hero: HeroView
var _power: Control
var _curve: ManaCurve
var _name: Label
var _who: Label
var _txt: Label
var _cards: Control
var _play: Button
var _edit_btn: Button
var _cards_btn: Button
var _guide_btn: Button
var _peek: Control ## a key card shown big (hover or tap), null when none
var _peek_pinned := false ## opened by a tap: stays until the next press


func _ready() -> void:
	Sfx.play_ambience("") # menus play the music alone (an ambience loop would leak in from the battle)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	_entries = _all_entries()
	_filter = str(Settings.deck_choice.get("filter", "all"))
	if _filter != "all" and not _filter in CardDB.classes():
		_filter = "all"
	_selected = str(Settings.deck_choice.get("selected", ""))
	if _find(_selected).is_empty():
		_selected = str(_entries[0].key) if not _entries.is_empty() else ""
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(UI.banner("Choose your path", 46, UI.GOLD, 0.0, 0.0, 1.8)) # the heading on the charred banner
	root.add_child(_header())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	row.custom_minimum_size = Vector2(0, _row_height())
	root.add_child(row)
	row.add_child(_showcase())
	row.add_child(_library())
	var back := UI.button("Back", 280, 62)
	back.pressed.connect(func(): Game.go(Game.MENU))
	var bc := CenterContainer.new()
	bc.add_child(back)
	root.add_child(bc)
	_refill()
	_show(_find(_selected), 0)
	if Game.online_requeue: # "Find another duel" on an online result: search again with the same deck
		Game.online_requeue = false
		OnlineOverlay.open.call_deferred(self, Game.player_deck, Game.player_cards.duplicate())


## Height of the showcase / library row: what the screen leaves under the title banner and header and above Back
## (those and the gaps take 285 px, so a 1080 px screen keeps a few px of margin). The showcase needs about 780; a
## taller screen (4:3, 16:10) gets up to 1000, which shows bigger decks and featured cards.
func _row_height() -> float:
	return minf(1000.0, get_viewport_rect().size.y - 300.0)


# --- Decks -------------------------------------------------------------------------------------------------------

## Every deck as one shape, by class (the order of CardDB.classes()): the starter, the premade decks in file order,
## then the player's own decks of that class.
func _all_entries() -> Array:
	var out := []
	for cls in CardDB.classes():
		var decks: Array = CardDB.class_decks(cls)
		var ordered := decks.filter(func(d): return d.get("starter", false))
		ordered.append_array(decks.filter(func(d): return not d.get("starter", false)))
		for d in ordered:
			var cards: Dictionary = d.get("cards", {})
			out.append({"key": "pre:" + str(d.id), "own": false, "id": str(d.id), "cls": cls, "name": str(d.name),
				"hero": str(d.hero), "text": str(d.get("text", "")), "featured": d.get("featured", []), "problem": "",
				"starter": bool(d.get("starter", false)), "cards": cards, "count": Collection.deck_count(cards)})
		for i in Collection.decks.size():
			var d: Dictionary = Collection.decks[i]
			if str(d.cls) != cls:
				continue
			out.append({"key": "own:%d" % i, "own": true, "index": i, "cls": cls, "name": str(d.name),
				"hero": CardDB.class_hero(cls), "text": _own_text(d), "featured": _own_featured(d),
				"problem": Collection.deck_problem(d), "starter": false, "cards": d.cards,
				"count": Collection.deck_count(d.cards)})
	return out


func _find(key: String) -> Dictionary:
	for e in _entries:
		if e.key == key:
			return e
	return {}


## A line about a deck the player built: its minions and spells, and average cost.
func _own_text(d: Dictionary) -> String:
	var n := Collection.deck_count(d.cards)
	if n == 0:
		return "An empty deck. Open it in the editor to fill it."
	var spells := 0
	var cost := 0
	for id in d.cards:
		var c := CardDB.card(id)
		var k := int(d.cards[id])
		cost += int(c.get("cost", 0)) * k
		if c.get("type", "minion") == "spell":
			spells += k
	return "Your own deck: %d minions and %d spells, average cost %.1f." % [n - spells, spells, float(cost) / n]


## The three showpiece cards of a deck the player built: the rarest, then the most expensive.
func _own_featured(d: Dictionary) -> Array:
	var rank := {"legendary": 3, "epic": 2, "rare": 1}
	var ids: Array = d.cards.keys()
	ids.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		var ra: int = rank.get(ca.get("rarity", "common"), 0)
		var rb: int = rank.get(cb.get("rarity", "common"), 0)
		if ra != rb:
			return ra > rb
		return int(ca.get("cost", 0)) > int(cb.get("cost", 0)))
	return ids.slice(0, 3)


func _play_entry(e: Dictionary) -> void:
	if e.is_empty() or e.problem != "":
		return
	Sfx.play("ui_confirm", -4.0)
	if e.own:
		var d: Dictionary = Collection.decks[e.index]
		Game.start_with(Collection.deck_cards(d.cards), e.hero)
	else:
		Game.start_battle(e.id)


func _remember() -> void:
	Settings.deck_choice["selected"] = _selected
	Settings.deck_choice["filter"] = _filter
	if not Game.debug_run(): # snapshots and tests never touch the player's settings
		Settings.save()


## What kind of deck `e` is: "starter", "premade" or "custom" (a key of TAGS).
func _kind(e: Dictionary) -> String:
	return "custom" if e.own else "starter" if e.starter else "premade"


# --- Header ------------------------------------------------------------------------------------------------------

## The next arena on an engraved plaque, beside the opponent's strength (a click steps Easy > Medium > Hard, saved
## at once). The arena is drawn now (a different one from last match), so the player knows where the fight will be.
func _header() -> Control:
	var arena := CardDB.arena(Game.pick_arena())
	var where := str(arena.get("name", ""))
	if str(arena.get("circle", "")) != "":
		where += "  ·  " + str(arena.circle)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 24)
	var plaque := PanelContainer.new()
	var sb := UI.frame_box("deck_row", 10, 0, UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 2, 8))
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	plaque.add_theme_stylebox_override("panel", sb)
	UI.add_field(plaque)
	var sub := UI.label("Next arena:  " + where, 26, "italic", UI.BONE, 4, Color.BLACK)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fit_label(sub, 760.0, 18)
	plaque.add_child(sub)
	head.add_child(plaque)
	var diff := UI.button("Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty], 400, 60)
	diff.add_theme_font_size_override("font_size", 30)
	diff.pressed.connect(func():
		Settings.difficulty = (Settings.difficulty + 1) % Settings.DIFFICULTY_NAMES.size()
		Settings.save()
		diff.text = "Opponent: " + Settings.DIFFICULTY_NAMES[Settings.difficulty]
		diff.add_theme_font_size_override("font_size", 30)
		UI.fit_text(diff))
	head.add_child(diff)
	# Online: the selected deck against another player (OnlineOverlay searches, then the battle opens).
	var online := UI.button("Play online", 300, 60)
	online.name = "PlayOnline"
	online.add_theme_font_size_override("font_size", 30)
	online.pressed.connect(func(): _play_online(_find(_selected)))
	head.add_child(online)
	return head


## Searches for an online duel with deck `e` (a deck that cannot be played says why instead).
func _play_online(e: Dictionary) -> void:
	if e.is_empty():
		return
	if e.problem != "":
		UI.dialog(self, "This deck cannot be played", str(e.problem), [["Close", null]])
		return
	Sfx.play("ui_confirm", -4.0)
	var cards: Array = Collection.deck_cards(Collection.decks[e.index].cards) if e.own else CardDB.deck_list(e.id)
	OnlineOverlay.open(self, e.cls, cards)


# --- Showcase ----------------------------------------------------------------------------------------------------

## A big bronze-framed panel `w` px wide.
func _big_panel(w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(w, 0)
	var s := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.08, 0.04, 0.035, 0.9), UI.GOLD_DARK, 3, 18, Color(0, 0, 0, 0.6), 24))
	s.content_margin_left = FRAME_PAD
	s.content_margin_right = FRAME_PAD
	s.content_margin_top = 40
	s.content_margin_bottom = 44
	p.add_theme_stylebox_override("panel", s)
	return p


## The selected deck: the hero between their hero power and the mana curve, name on the ribbon, tagline and plan on
## parchment, the key cards, View cards and Class guide, Play (and Edit for the player's own decks).
func _showcase() -> Control:
	var inner := SHOW_W - 2.0 * FRAME_PAD
	# A taller screen (4:3, 16:10) gives the row more height: the featured cards take it.
	_feat_scale = clampf(FEATURED_SCALE + (_row_height() - 800.0) / CardView.H, FEATURED_SCALE, FEATURED_SCALE_MAX)
	var p := _big_panel(SHOW_W)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	# The hero in the middle, the hero power on the left, the deck's mana curve on the right.
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(inner, 172)
	v.add_child(_portrait)
	var side := (inner - 176.0) / 2.0
	_power = Control.new()
	_power.size = Vector2(side, 172)
	_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.add_child(_power)
	var cap := ClassInfoPanel.gilded("Mana curve", 17, side)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size = Vector2(side, cap.custom_minimum_size.y)
	cap.position = Vector2(inner - side, 172 - cap.size.y)
	_portrait.add_child(cap)
	_curve = ManaCurve.new()
	_curve.gem = 21.0
	_curve.position = Vector2(inner - side + 2, 14)
	_curve.size = Vector2(side - 2, 172 - 14 - cap.size.y - 2)
	_portrait.add_child(_curve)
	# The deck's name on the painted ribbon; the text stays inside the ribbon's flat middle.
	var ribbon := Control.new()
	ribbon.custom_minimum_size = Vector2(inner, 76)
	v.add_child(ribbon)
	var rw := inner + 40.0
	var rh := rw * 144.0 / 768.0
	if UiSkin.has("name_ribbon"):
		ribbon.add_child(UiSkin.rect("name_ribbon", Vector2(rw, rh), Vector2(-20, -2)))
	_name = UI.label("", 36, "title", UI.BONE, 6, Color(0.12, 0.02, 0.02))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.size = Vector2(inner, rh * 0.78)
	_name.position = Vector2(0, -2)
	_name.set_meta("room", rw * 0.64) ## the ribbon's flat middle, between its folded tails
	ribbon.add_child(_name)
	# The class's tagline and the deck's plan, inked on parchment.
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", UI.parchment_box(36, 22))
	plaque.custom_minimum_size = Vector2(0, 144)
	v.add_child(plaque)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 4)
	plaque.add_child(pv)
	var room := inner - 84.0 ## the parchment's margins
	_who = UI.label("", 22, "italic", INK_RED)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_who.custom_minimum_size = Vector2(room, 0)
	pv.add_child(_who)
	_txt = UI.label("", 24, "body", INK)
	_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_txt.custom_minimum_size = Vector2(room, 0)
	pv.add_child(_txt)
	_cards = Control.new()
	# Tall enough for the tilted side cards (see _show), so they never reach down onto the buttons.
	_cards.custom_minimum_size = Vector2(inner, ceilf(_featured_y(1) + _featured_half_h(1)) + 2.0)
	v.add_child(_cards)
	var links := HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 14)
	v.add_child(links)
	_cards_btn = UI.button("View cards", 236, 54)
	_cards_btn.pressed.connect(func(): _open_list(_find(_selected)))
	links.add_child(_cards_btn)
	_guide_btn = UI.button("Class guide", 236, 54)
	_guide_btn.pressed.connect(func():
		var e := _find(_selected)
		if not e.is_empty():
			ClassInfoPanel.open(self, e.cls))
	links.add_child(_guide_btn)
	for b in [_cards_btn, _guide_btn]:
		b.add_theme_font_size_override("font_size", 25)
	UI.even_text([_cards_btn, _guide_btn])
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)
	_play = UI.button("Play", 280, 64)
	_play.add_theme_font_size_override("font_size", 38)
	_play.pressed.connect(func(): _play_entry(_find(_selected)))
	buttons.add_child(_play)
	_edit_btn = UI.button("Edit", 170, 64)
	_edit_btn.add_theme_font_size_override("font_size", 28)
	_edit_btn.pressed.connect(func():
		var e := _find(_selected)
		if not e.is_empty() and e.own:
			_edit(e.index, e.cls))
	buttons.add_child(_edit_btn)
	return p


## Where a featured card's centre sits in the cards row: the middle one (`side` 0) just clear of the plaque above,
## the tilted side ones (`side` 1) a little lower, fanned.
func _featured_y(side: int) -> float:
	return _featured_half_h(0) + 2.0 + side * 5.0


## Half the height a featured card takes on screen, the side ones tilted.
func _featured_half_h(side: int) -> float:
	var a := side * FEATURED_TILT
	return _feat_scale * (CardView.H / 2.0 * cos(a) + CardView.W / 2.0 * sin(a))


## Puts deck `e` in the showcase: hero and hero power, mana curve, name (shrunk to fit the ribbon), tagline and plan
## (shrunk to fit), the featured cards (they slide in from the side the selection moved toward).
func _show(e: Dictionary, step: int) -> void:
	_unpeek()
	if e.is_empty():
		_play.disabled = true
		_edit_btn.visible = false
		_cards_btn.disabled = true
		return
	var inner := _portrait.custom_minimum_size.x
	var hero := CardDB.hero(e.hero)
	if _hero == null or str(_hero.get_meta("id", "")) != e.hero:
		if _hero != null:
			_hero.queue_free()
		_hero = HeroView.new().setup({"uid": -1, "side": 0, "id": e.hero, "health": hero.get("health", 30)})
		_hero.set_meta("id", e.hero)
		_hero.position = Vector2(inner / 2, 92)
		_hero.scale = Vector2(0.84, 0.84)
		_hero.power.visible = false
		_portrait.add_child(_hero)
		_fill_power(e.cls)
	_curve.counts = ManaCurve.counts_of(e.cards)
	_name.text = e.name
	_name.add_theme_font_size_override("font_size", 36)
	_fit_label(_name, float(_name.get_meta("room")), 22)
	UI.gild(_name, UI.GOLD, _name.size.y)
	var info := CardDB.class_info(e.cls)
	var room := _who.custom_minimum_size.x
	_who.text = "%s  ·  %s" % [info.title, info.tagline]
	_who.add_theme_font_size_override("font_size", 22)
	_fit_wrapped(_who, room, 2, 16)
	_txt.text = e.text if e.problem == "" else "Incomplete: %s. Open it in the editor to finish it." % e.problem
	_txt.add_theme_color_override("font_color", INK if e.problem == "" else INK_RED)
	_txt.add_theme_font_size_override("font_size", 24)
	_fit_wrapped(_txt, room, 3, 17)
	# Both lines share the parchment's fixed height: a long tagline and a long plan shrink together, so it never
	# grows into the featured cards and the buttons.
	while _text_h(_who, room) + _text_h(_txt, room) > PLAQUE_TEXT_H:
		var wp := _who.get_theme_font_size("font_size")
		var tp := _txt.get_theme_font_size("font_size")
		if tp > 16 and tp >= wp:
			_txt.add_theme_font_size_override("font_size", tp - 1)
		elif wp > 15:
			_who.add_theme_font_size_override("font_size", wp - 1)
		else:
			break
	for c in _cards.get_children():
		c.queue_free()
	var ids: Array = e.featured
	var mid := inner / 2
	for i in ids.size():
		var c := CardView.new().setup(ids[i], -1, true)
		c.scale = Vector2.ONE * _feat_scale
		var at := Vector2(mid + (i - 1) * 120.0 * _feat_scale / FEATURED_SCALE, _featured_y(absi(i - 1)))
		c.position = at
		c.rotation = (i - 1) * FEATURED_TILT
		c.set_meta("home", at)
		_cards.add_child(c)
		_cards.add_child(_featured_hit(c, str(ids[i]), at))
		if step != 0:
			c.position = at + Vector2(90 * step, 0)
			c.modulate.a = 0.0
			var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(c, "position", at, 0.28).set_delay(0.04 * i)
			t.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.04 * i)
	_play.disabled = e.problem != ""
	_edit_btn.visible = e.own
	_cards_btn.disabled = e.count == 0


## The hero power of class `cls` in the left of the hero row: its disc, its name in gold, its text under it.
func _fill_power(cls: String) -> void:
	for c in _power.get_children():
		c.queue_free()
	var info := CardDB.class_info(cls)
	var w := _power.size.x
	var disc := ClassInfoPanel.power_disc(info, 66.0)
	disc.position = Vector2((w - 66.0) / 2.0, 12)
	disc.size = disc.custom_minimum_size
	disc.mouse_filter = Control.MOUSE_FILTER_STOP
	disc.tooltip_text = "Hero power: %s (%d mana). %s" % [info.power.get("name", ""), int(info.power.get("cost", 2)),
		info.power.get("text", "")]
	_power.add_child(disc)
	var n := ClassInfoPanel.gilded(str(info.power.get("name", "")), 19, w)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.size = Vector2(w, n.custom_minimum_size.y)
	n.position = Vector2(0, 84)
	_power.add_child(n)
	var t := UI.label(str(info.power.get("text", "")), 17, "italic", UI.BONE, 3, SHADE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size = Vector2(w, 60)
	t.position = Vector2(0, 84 + n.size.y)
	_fit_wrapped(t, w, 3, 13)
	_power.add_child(t)


# --- Key cards up close ------------------------------------------------------------------------------------------

## The pointer area over a featured card (the card itself is a Node2D): hovering it lifts the card and shows it big
## beside the showcase; a tap (touch) or a click keeps it shown until the next press.
func _featured_hit(c: CardView, id: String, at: Vector2) -> Control:
	var hit := Control.new()
	hit.size = Vector2(CardView.W, CardView.H) * _feat_scale
	hit.pivot_offset = hit.size / 2
	hit.position = at - hit.size / 2
	hit.rotation = c.rotation
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.set_meta("card", id)
	hit.mouse_entered.connect(func():
		Sfx.play("tick", -14.0)
		_lift(c, true)
		if not _peek_pinned:
			_peek_card(id, c))
	hit.mouse_exited.connect(func():
		_lift(c, false)
		if not _peek_pinned:
			_unpeek())
	hit.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_peek_card(id, c)
			_peek_pinned = true
			hit.accept_event())
	return hit


func _lift(c: CardView, up: bool) -> void:
	if not is_instance_valid(c):
		return
	var home: Vector2 = c.get_meta("home", c.position)
	var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position", home + (Vector2(0, -14) if up else Vector2.ZERO), 0.1)
	t.tween_property(c, "scale", Vector2.ONE * _feat_scale * (1.1 if up else 1.0), 0.1)
	c.z_index = 2 if up else 0


## Shows card `id` big just right of the showcase (over the library), level with the small card `from`, with its
## keyword tips beside it. While shown by a tap, a press anywhere closes it.
func _peek_card(id: String, from: CardView) -> void:
	_unpeek()
	var vs := get_viewport_rect().size
	var k := PEEK_SCALE * clampf(vs.y / 1080.0, 1.0, 1.25)
	var panel: Control = _portrait.get_parent().get_parent()
	var r := panel.get_global_rect()
	var half := Vector2(CardView.W, CardView.H) * k / 2.0
	var at := Vector2(r.end.x + 24.0 + half.x, from.global_position.y - 60.0)
	at.y = clampf(at.y, half.y + 12.0, vs.y - half.y - 12.0)
	_peek = Control.new()
	_peek.name = "PeekLayer"
	_peek.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_peek.z_index = 60
	add_child(_peek)
	# Under the card, a catcher that closes a tapped card on the next press (it takes no input while hovering).
	var catcher := Control.new()
	catcher.name = "Catcher"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			catcher.accept_event()
			_unpeek())
	_peek.add_child(catcher)
	CardZoom.peek(_peek, id, at, k, 1)
	_peek.set_meta("card", id)
	(func():
		if is_instance_valid(catcher) and _peek_pinned:
			catcher.mouse_filter = Control.MOUSE_FILTER_STOP).call_deferred()


func _unpeek() -> void:
	_peek_pinned = false
	if _peek != null and is_instance_valid(_peek):
		_peek.queue_free()
	_peek = null


# --- The whole deck ----------------------------------------------------------------------------------------------

## Every card of deck `e` on the big bronze panel over a dim veil: its name on the ribbon, then the cards by cost
## (copies on a bronze disc), each one hovered lifts and a press shows it big (CardZoom). View only. Esc, the back
## gesture, Close or a press outside the panel closes it (a card shown big closes first).
func _open_list(e: Dictionary) -> void:
	if e.is_empty() or e.count == 0:
		return
	_unpeek()
	var vs := get_viewport_rect().size
	var d := Control.new()
	d.name = "Dialog"
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	d.z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
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
	s.content_margin_left = 80
	s.content_margin_right = 80
	s.content_margin_top = 44
	s.content_margin_bottom = 52
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	# The name on the red ribbon, the class and count under it.
	var title := Control.new()
	title.custom_minimum_size = Vector2(700, 100)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rib := UI.ribbon(str(e.name), 700, 40)
	rib.position = Vector2(0, 0)
	title.add_child(rib)
	var tc := CenterContainer.new()
	tc.add_child(title)
	v.add_child(tc)
	var info := CardDB.class_info(e.cls)
	var sub := UI.plaque_label("%s  ·  %s deck  ·  %d cards" % [info.title, TAGS[_kind(e)][0], e.count], 24)
	sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sub)
	# The cards, as big as the room allows: as many rows as give the largest cards.
	var ids: Array = e.cards.keys()
	ids.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		return [int(ca.get("cost", 0)), str(ca.get("name", ""))] < [int(cb.get("cost", 0)), str(cb.get("name", ""))])
	var gap := 16.0
	var aw := minf(1640.0, vs.x - 200.0) - 160.0
	var ah := vs.y - 420.0
	var best := [0.0, 1]
	for rows in range(1, ids.size() + 1):
		var cols := ceili(float(ids.size()) / rows)
		var k := minf((aw - (cols - 1) * gap) / cols / CardView.W, (ah - (rows - 1) * gap) / rows / CardView.H)
		if k > best[0]:
			best = [k, cols]
	var k: float = minf(best[0], 0.62)
	var grid := GridContainer.new()
	grid.columns = best[1]
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	for id in ids:
		grid.add_child(_list_slot(d, str(id), int(e.cards[id]), k))
	var close := UI.button("Close", 260, 62)
	close.add_theme_font_size_override("font_size", 30)
	close.pressed.connect(func():
		var z := d.get_node_or_null("CardZoom")
		if z != null and not z.is_queued_for_deletion():
			z.queue_free() # a card shown big closes first
		else:
			d.queue_free())
	var cc := CenterContainer.new()
	cc.add_child(close)
	v.add_child(cc)
	d.set_meta("cancel", close)
	d.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and not panel.get_global_rect().has_point(ev.global_position):
			d.queue_free())
	add_child(d)
	d.modulate.a = 0.0
	d.create_tween().tween_property(d, "modulate:a", 1.0, 0.15)
	Sfx.play("page", -6.0)


## One card of the deck list at scale `k`, its copies on a bronze disc at its top-right corner.
func _list_slot(d: Control, id: String, copies: int, k: float) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CardView.W, CardView.H) * k
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := CardView.new().setup(id, -1, true)
	v.scale = Vector2.ONE * k
	v.position = slot.custom_minimum_size / 2
	slot.add_child(v)
	if copies > 1:
		var badge := Control.new()
		badge.size = Vector2(46, 46)
		badge.position = Vector2(slot.custom_minimum_size.x - 34, -12)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiSkin.has("power_disc"):
			badge.add_child(UiSkin.rect("power_disc", badge.size))
		var count := UI.label("x%d" % copies, 20, "title", UI.GOLD, 5, Color.BLACK)
		if UiSkin.has("power_disc"):
			UI.engraved(count)
		count.size = badge.size
		count.position.y = 1
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(count)
		slot.add_child(badge)
	slot.mouse_entered.connect(func():
		v.z_index = 2
		v.create_tween().tween_property(v, "scale", Vector2.ONE * k * 1.08, 0.1)
		Sfx.play("tick", -16.0))
	slot.mouse_exited.connect(func():
		v.z_index = 0
		v.create_tween().tween_property(v, "scale", Vector2.ONE * k, 0.1))
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			slot.accept_event()
			var old := d.get_node_or_null("CardZoom")
			if old != null:
				old.queue_free()
			CardZoom.open(d, id))
	return slot


# --- Library -----------------------------------------------------------------------------------------------------

## The deck library: class filters on engraved plates, then the scrolling sections (a class plaque over its decks
## and its New deck slot), then the bronze discs that scroll it.
func _library() -> Control:
	var inner := LIB_COLS * DECK_W + (LIB_COLS - 1) * DECK_GAP
	var p := _big_panel(inner + 2.0 * FRAME_PAD)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	# One filter per class after "All"; the plates narrow as classes are added so the row fits the panel, and once a
	# name would no longer fit, the class plates show the class's emblem (its hero power icon) instead.
	var filters := [["all", "All"]] # as in the collection; "All decks" set the whole row's letters smallest
	for cls in CardDB.classes():
		filters.append([cls, CardDB.class_title(cls)])
	var fw := minf(210.0, (inner - 12.0 * (filters.size() - 1)) / filters.size())
	var emblems := fw < 128.0
	for f in filters:
		var b := UI.button(f[1], fw, 56)
		b.add_theme_font_size_override("font_size", 24)
		if emblems and f[0] != "all":
			var icon := str(CardDB.class_info(f[0]).power_icon)
			if UiSkin.has(icon):
				b.text = ""
				b.icon = UI.scaled_tex(icon, 34)
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.tooltip_text = str(f[1])
		b.pressed.connect(func():
			_filter = f[0]
			_remember()
			_refill())
		_tabs[f[0]] = b
		top.add_child(b)
	UI.even_text(_tabs.values().filter(func(b): return b.text != ""))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # wheel, drag and the bronze discs scroll it
	# The room the panel leaves (frame margins, filters, discs, the gaps between them and the scroll's own 8 px). The
	# decks are sized so that two classes (plaque + one row of decks) fill it on a 1080 px screen; a taller screen
	# makes them bigger, up to DECK_H_MAX.
	var room := _row_height() - 84.0 - 56.0 - ARROW_SIZE - 24.0 - 8.0
	var h := floorf((room - 10.0 - SECTION_GAP - 2.0 * (HEAD_H + 10.0)) / 2.0)
	_cell = Vector2(DECK_W, clampf(h, DECK_H_MIN, DECK_H_MAX))
	_scroll.custom_minimum_size = Vector2(inner + 12.0, room)
	v.add_child(_scroll)
	var pad := MarginContainer.new() # room for a lifted deck and its aura at the top, and for the frame's edge
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 6)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = inner
	_list.add_theme_constant_override("separation", int(SECTION_GAP))
	pad.add_child(_list)
	# Bronze discs to scroll a long library, shown only when it overflows.
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 24)
	nav.custom_minimum_size = Vector2(0, ARROW_SIZE)
	v.add_child(nav)
	for dir in [-1, 1]:
		var a := _arrow_button(dir)
		a.rotation = PI / 2 # containers reset rotation, so the disc sits in a plain holder
		var holder := Control.new()
		holder.custom_minimum_size = a.size
		a.pressed.connect(_step_scroll.bind(dir))
		holder.add_child(a)
		nav.add_child(holder)
		_scroll_btns.append(a)
	_scroll.resized.connect(_update_scroll_btns)
	return p


## Rebuilds the library for the current filter: a section per class shown.
func _refill() -> void:
	_unpeek()
	for f in _tabs:
		var on: bool = f == _filter
		(_tabs[f] as Button).modulate = Color(1.15, 1.05, 0.85) if on else Color(0.72, 0.66, 0.6)
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	for cls in CardDB.classes():
		if _filter != "all" and _filter != cls:
			continue
		var sec := VBoxContainer.new()
		sec.name = "Section_" + cls
		sec.set_meta("cls", cls)
		sec.add_theme_constant_override("separation", 10)
		_list.add_child(sec)
		sec.add_child(ClassInfoPanel.strip(cls, _list.custom_minimum_size.x))
		var grid := GridContainer.new()
		grid.name = "Decks"
		grid.columns = LIB_COLS
		grid.add_theme_constant_override("h_separation", int(DECK_GAP))
		grid.add_theme_constant_override("v_separation", 14)
		sec.add_child(grid)
		for e in _entries:
			if e.cls == cls:
				grid.add_child(_deck(e))
		grid.add_child(_new_deck(cls))
	_scroll.scroll_vertical = 0
	_update_scroll_btns.call_deferred()
	_reveal_selected.call_deferred()


## The y (in the library's scroll) of every place a step of the discs may stop at: each class plaque and each row
## of decks under the first.
func _stops() -> Array:
	var out := [0.0]
	var top := _list.position.y
	for sec in _list.get_children():
		if sec.is_queued_for_deletion():
			continue
		out.append(top + sec.position.y)
		var grid: GridContainer = sec.get_node("Decks")
		var rows := ceili(float(grid.get_child_count()) / LIB_COLS)
		for r in range(1, rows):
			out.append(top + sec.position.y + grid.position.y + r * (_cell.y + 14.0) - 10.0)
	out.sort()
	return out


## A disc press: scrolls to the next stop at least half a view away in direction `dir`.
func _step_scroll(dir: int) -> void:
	var cur := float(_scroll.scroll_vertical)
	var view := _scroll.size.y
	var max_y := maxf(0.0, _list.get_parent().size.y - view)
	var target := 0.0 if dir < 0 else max_y
	var stops := _stops()
	if dir > 0:
		for y in stops:
			if y > cur + view * 0.4:
				target = minf(y, max_y)
				break
	else:
		stops.reverse()
		for y in stops:
			if y < cur - view * 0.4:
				target = y
				break
	var t := _scroll.create_tween()
	t.tween_property(_scroll, "scroll_vertical", int(target), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Brings the selected deck into view (after a rebuild, e.g. on opening with a saved choice far down the list).
func _reveal_selected() -> void:
	var b := _deck_button(_selected)
	if b == null:
		return
	var sec: Control = b.get_parent().get_parent()
	var y: float = _list.position.y + sec.position.y + (b.get_parent() as Control).position.y + b.position.y
	if y + _cell.y > _scroll.scroll_vertical + _scroll.size.y:
		_scroll.scroll_vertical = int(_list.position.y + sec.position.y)


func _deck_button(key: String) -> Button:
	for sec in _list.get_children():
		for b in sec.get_node("Decks").get_children():
			if b.get_meta("key", "") == key:
				return b
	return null


func _update_scroll_btns() -> void:
	if _list == null:
		return
	var overflow: bool = _list.get_parent().get_combined_minimum_size().y > _scroll.size.y + 1.0
	for b in _scroll_btns:
		b.modulate.a = 1.0 if overflow else 0.0
		b.disabled = not overflow
		# A hidden disc neither takes the pointer nor shows its tooltip.
		b.mouse_filter = Control.MOUSE_FILTER_STOP if overflow else Control.MOUSE_FILTER_IGNORE
		b.tooltip_text = ("Scroll up" if b == _scroll_btns[0] else "Scroll down") if overflow else ""


# --- A deck ------------------------------------------------------------------------------------------------------

## Where a deck's face (its top card) sits in its cell: as tall as the cell allows over the cards under it, at the
## card's shape, centred with the stack's edge.
func _face_rect() -> Rect2:
	var fh := _cell.y - 10.0 - STACK * 0.5 - 8.0
	var fw := fh * CardView.W / CardView.H
	if fw > _cell.x - STACK - 24.0:
		fw = _cell.x - STACK - 24.0
		fh = fw * CardView.H / CardView.W
	return Rect2(Vector2(roundf((_cell.x - fw - STACK) / 2.0), 10.0), Vector2(fw, fh))


## A deck's empty body: a flat button the size of the cell whose painted parts sit on the child "Body", which lifts
## when the deck is hovered or selected; a soft shadow under where the stack stands.
func _deck_base() -> Button:
	var b := Button.new()
	b.custom_minimum_size = _cell
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var face := _face_rect()
	var shadow := TextureRect.new()
	shadow.texture = UI.dot_texture()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.modulate = Color(0, 0, 0, 0.75)
	shadow.position = Vector2(face.position.x - 14.0, face.end.y + STACK - 22.0)
	shadow.size = Vector2(face.size.x + STACK + 28.0, 40.0)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(shadow)
	var body := Control.new()
	body.name = "Body"
	body.size = _cell
	body.pivot_offset = Vector2(_cell.x / 2.0, _cell.y)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(body)
	# The selection's aura, around the stack.
	var ah := Control.new()
	ah.position = face.get_center() + Vector2(STACK, STACK) / 2.0
	ah.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(ah)
	var aura := Aura.make(face.size + Vector2(STACK, STACK), false, 24.0, 10.0)
	aura.name = "Aura"
	aura.colors(Aura.SELECTED)
	ah.add_child(aura)
	b.set_meta("aura", aura)
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -12.0)
		b.set_meta("hover", true)
		_pose(b))
	b.mouse_exited.connect(func():
		b.set_meta("hover", false)
		_pose(b))
	return b


## A card in the stack (`k` cards under the face; 0 is the face's frame): the painted back in the carved border,
## darker the deeper it lies.
func _stack_card(body: Control, face: Rect2, k: int) -> void:
	var off := Vector2(k * STACK / 4.0, k * STACK / 8.0)
	if ResourceLoader.exists("res://assets/cards/card_back.jpg"):
		var back := TextureRect.new()
		back.texture = load("res://assets/cards/card_back.jpg")
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.position = face.position + off + Vector2(3, 3)
		back.size = face.size - Vector2(6, 6)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.modulate = Color(1, 1, 1) * (0.8 - 0.1 * k)
		back.modulate.a = 1.0
		body.add_child(back)
	_border(body, face.position + off, face.size, Color(1, 1, 1) * (0.95 - 0.12 * k))


## The carved bronze card border around `size` at `pos`, tinted `tint`.
func _border(body: Control, pos: Vector2, size: Vector2, tint: Color) -> void:
	if UiSkin.has("card_border_minion"):
		var r := UiSkin.rect("card_border_minion", size, pos)
		r.modulate = Color(tint.r, tint.g, tint.b, 1.0)
		body.add_child(r)
	else:
		var p := UI.panel(size, UI.box(Color(0, 0, 0, 0), UI.GOLD_DARK, 3, 8), pos)
		p.modulate = Color(tint.r, tint.g, tint.b, 1.0)
		body.add_child(p)


## The plaque at the foot of a deck: the name in engraved gold, on two lines when long.
func _name_plaque(body: Control, title: String) -> Control:
	var p := PanelContainer.new()
	p.name = "Plaque"
	p.add_theme_stylebox_override("panel", UI.plaque_box(10, 2))
	UI.add_field(p)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = Vector2(1, _cell.y - PLAQUE_H - 1)
	p.size = Vector2(_cell.x - 2, PLAQUE_H)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var room := _cell.x - 26.0
	var f := UI.font("title")
	var lines: Array = [title]
	var px := 20
	if f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > room:
		lines = _split_name(title)
		px = 18
	for t in lines:
		var l := ClassInfoPanel.gilded(str(t), px, room)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	body.add_child(p)
	return p


## The deck's card count engraved on a bronze disc pinned to the face's top-left corner; red when the deck is not
## ready to play (too few cards, or a card it may not hold).
func _count_disc(body: Control, face: Rect2, count: int, bad: bool) -> void:
	var d := Control.new()
	d.name = "Count"
	d.size = Vector2(40, 40)
	d.position = face.position - Vector2(12, 12)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if UiSkin.has("power_disc"):
		d.add_child(UiSkin.rect("power_disc", d.size))
	var l := UI.label(str(count), 20 if count < 100 else 16, "title", UI.GOLD, 4, SHADE)
	if UiSkin.has("power_disc"):
		UI.engraved(l, Color(0.55, 0.06, 0.03) if bad else Color(0.2, 0.08, 0.03))
	l.size = d.size
	l.position.y = 1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.add_child(l)
	body.add_child(d)


## A long deck name on two lines, broken at the space that makes the longer line shortest.
func _split_name(t: String) -> Array:
	var words := t.split(" ")
	if words.size() < 2:
		return [t]
	var f := UI.font("title")
	var best := [t, ""]
	var best_w := INF
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var w := maxf(f.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x,
			f.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
		if w < best_w:
			best_w = w
			best = [a, b]
	return best


## The corner tag of a deck: Starter, Premade or Custom on a small engraved plaque hung over the face's top edge.
func _tag(body: Control, face: Rect2, kind: String) -> void:
	var p := PanelContainer.new()
	p.name = "Tag"
	p.add_theme_stylebox_override("panel", UI.plaque_box(9, 1))
	UI.add_field(p, 4.0, Color(0.42, 0.34, 0.3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(str(TAGS[kind][0]).to_upper(), 13, "title", TAGS[kind][1], 3, SHADE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	body.add_child(p)
	p.reset_size()
	p.position = Vector2(face.end.x - p.size.x + 12.0, face.position.y - 9.0)


## One deck in the library. A click shows it in the showcase; a click on the deck already shown plays it.
func _deck(e: Dictionary) -> Button:
	var b := _deck_base()
	b.set_meta("key", e.key)
	var body: Control = b.get_node("Body")
	var face := _face_rect()
	# The stack: up to four cards' edges under the face, fewer for a thin deck.
	var layers := 0 if e.count == 0 else clampi(ceili(e.count / 8.0), 1, 4)
	for k in range(layers, 0, -1):
		_stack_card(body, face, k)
	# The face: the key card's painting (the hero for an empty deck) in the carved border.
	var art := TextureRect.new()
	var key_card := str(e.featured[0]) if not e.featured.is_empty() else ""
	art.texture = CardDB.art_framed(key_card, face.size.x / face.size.y, 0.4) if key_card != "" \
		else CardDB.hero_art(e.hero)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = face.position + Vector2(4, 4)
	art.size = face.size - Vector2(8, 8)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim: bool = e.problem != ""
	art.modulate = Color(0.5, 0.46, 0.44) if dim else Color(0.92, 0.9, 0.88)
	art.name = "Art"
	body.add_child(art)
	_border(body, face.position, face.size, Color(1.0, 0.95, 0.85) if not dim else Color(0.6, 0.55, 0.5))
	_tag(body, face, _kind(e))
	_count_disc(body, face, int(e.count), dim)
	_name_plaque(body, e.name)
	b.tooltip_text = "%s deck, %d cards" % [TAGS[_kind(e)][0], e.count] if e.problem == "" 		else "Incomplete: %s" % e.problem
	b.pressed.connect(func():
		if _selected == e.key:
			_play_entry(e)
			return
		var before := _entries.find(_find(_selected))
		_selected = e.key
		_remember()
		_show(e, 1 if _entries.find(e) > before else -1)
		_mark_selected())
	b.set_meta("on", e.key == _selected)
	_pose(b, true)
	return b


## The "New deck" slot of a class: an empty card outline with a gilded "+", opening the deck editor on an empty deck.
func _new_deck(cls: String) -> Button:
	var b := _deck_base()
	b.set_meta("new", cls)
	var body: Control = b.get_node("Body")
	var face := _face_rect()
	var well := Panel.new()
	well.position = face.position + Vector2(4, 4)
	well.size = face.size - Vector2(8, 8)
	well.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.add_field(well, 0.0, Color(0.36, 0.3, 0.27))
	body.add_child(well)
	_border(body, face.position, face.size, Color(0.62, 0.56, 0.5))
	var plus := UI.label("+", 76, "title", UI.GOLD, 6, SHADE)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.size = Vector2(face.size.x, face.size.y - PLAQUE_H + 20.0)
	plus.position = face.position
	UI.gild(plus, UI.GOLD, plus.size.y)
	body.add_child(plus)
	_name_plaque(body, "New deck")
	b.tooltip_text = "Build a new %s deck" % CardDB.class_title(cls)
	b.pressed.connect(_edit.bind(-1, cls))
	b.set_meta("on", false)
	_pose(b, true)
	return b


## A deck's pose: lifted and burning gold when selected, lifted a little and brighter when hovered, else resting.
func _pose(b: Button, instant: bool = false) -> void:
	var on: bool = b.get_meta("on", false)
	var hover: bool = b.get_meta("hover", false)
	var body: Control = b.get_node("Body")
	var y := -8.0 if on else -5.0 if hover else 0.0
	var k := 1.04 if on else 1.02 if hover else 1.0
	var tint := Color(1.12, 1.06, 0.95) if on or hover else Color(0.9, 0.86, 0.82)
	var aura: Aura = b.get_meta("aura")
	aura.set_on(on)
	if instant:
		body.position.y = y
		body.scale = Vector2.ONE * k
		body.modulate = tint
		return
	var t := body.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(body, "position:y", y, 0.12)
	t.tween_property(body, "scale", Vector2.ONE * k, 0.12)
	t.tween_property(body, "modulate", tint, 0.12)


## Re-marks the selected deck without rebuilding the library (keeps the scroll position).
func _mark_selected() -> void:
	for sec in _list.get_children():
		for b in sec.get_node("Decks").get_children():
			if b.has_meta("key"):
				b.set_meta("on", b.get_meta("key") == _selected)
				_pose(b)


# --- Helpers -----------------------------------------------------------------------------------------------------

## A round button: the painted bronze disc with an engraved arrow (-1 = previous / up, 1 = next / down).
func _arrow_button(dir: int) -> Button:
	var b := Button.new()
	b.text = "‹" if dir < 0 else "›"
	b.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.custom_minimum_size = b.size
	b.pivot_offset = b.size / 2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 48)
	b.add_theme_color_override("font_color", Color(0.22, 0.09, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.12, 0.04, 0.02))
	b.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.62, 0.35))
	b.add_theme_constant_override("shadow_offset_y", 2)
	for st in [["normal", Color(0.95, 0.9, 0.82)], ["hover", Color(1.2, 1.08, 0.9)], ["pressed", Color(0.75, 0.62, 0.5)],
			["disabled", Color(0.95, 0.9, 0.82)]]:
		b.add_theme_stylebox_override(st[0], UI.frame_box("power_disc", 0, 0,
			UI.box(Color(0.1, 0.04, 0.03, 0.88), UI.GOLD_DARK, 3, int(ARROW_SIZE / 2)), st[1]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -10.0))
	b.pressed.connect(func(): Sfx.play("ui_confirm", -8.0))
	return b


## Shrinks a one-line label until its text fits `room` px.
func _fit_label(l: Label, room: float, min_size: int) -> void:
	var f := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	while px > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		px -= 1
	l.add_theme_font_size_override("font_size", px)


## The height a wrapping label's text takes at `room` px wide.
func _text_h(l: Label, room: float) -> float:
	return l.get_theme_font("font").get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, room,
		l.get_theme_font_size("font_size")).y


## Shrinks a wrapping label until its text takes at most `lines` lines of `room` px.
func _fit_wrapped(l: Label, room: float, lines: int, min_size: int) -> void:
	var f := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	while px > min_size:
		var h := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, room, px).y
		if h <= f.get_height(px) * lines + 2.0:
			break
		px -= 1
	l.add_theme_font_size_override("font_size", px)


## Esc / the back gesture (Game.back, after it closed any open dialog): closes a key card shown big, else like Back.
func go_back() -> void:
	if _peek != null:
		_unpeek()
		return
	Game.go(Game.MENU)


func _edit(index: int, cls: String) -> void:
	Game.edit_deck = index
	Game.new_deck_cls = cls
	Game.go(Game.DECK_BUILDER)
