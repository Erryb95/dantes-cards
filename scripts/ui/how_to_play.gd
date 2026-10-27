class_name HowToPlayPanel
extends Control
## How to Play: the rules at a glance, every keyword (UI.KEYWORD_HELP, each beside a minion that has it), what each
## class does (CardDB.class_info) and how decks, packs and the collection work. A modal over any screen: opened from
## the lessons screen, Options and the battle's pause menu. Chapters on painted plates down the left, the chapter's
## pages in a painted scroll on the right; Esc / the Android back gesture closes it (Game.back, the pause menu).

const CHAPTERS := ["The Goal", "Your Turn", "Combat", "Keywords", "Classes", "Decks"]
## The keywords in the order the Keywords chapter shows them, under three headings.
const KEYWORD_GROUPS := [
	["Keywords", ["guard", "swift", "ward", "drain", "venom", "rebirth"]],
	["Triggers", ["play", "death", "turn_start", "turn_end", "ruse", "frenzy"]],
	["Effects", ["wrath", "fight", "freeze", "silence"]],
]

static var last_chapter := 0 ## reopens where the player left it


## The "How to Play" plate for the Options panel `host`: opens the reference over it (like CreditsPanel.open_button).
static func open_button(host: Control) -> Button:
	var b := UI.button("How to Play", 300)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): host.get_parent().add_child(HowToPlayPanel.new()))
	return b

var _list: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Array[Button] = []
var _w := 1000.0 ## width of a page in the scroll


func _ready() -> void:
	name = "HowToPlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110 # above the options panel and the battle's pause menu
	var vs := get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var s := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14, Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = 76
	s.content_margin_right = 76
	s.content_margin_top = 48
	s.content_margin_bottom = 56
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(UI.banner("How to Play", 44, UI.GOLD, 0.0, 0.0, 1.8))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	v.add_child(body)
	# The chapters, one plate each, down the left.
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	body.add_child(tabs)
	for i in CHAPTERS.size():
		var b := UI.button(CHAPTERS[i], 320, 68)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(show_chapter.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	UI.even_text(_tabs)
	# The pages in the room the screen leaves (a phone at 1080 px high, a 4:3 tablet taller).
	_w = clampf(vs.x - 2.0 * 76.0 - 300.0 - 26.0 - 30.0 - 120.0, 760.0, 1240.0)
	var h := clampf(vs.y - 48.0 - 56.0 - 80.0 - 14.0 - 76.0 - 14.0 - 60.0, 560.0, 900.0)
	_scroll = ScrollContainer.new()
	_scroll.name = "Pages"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(_w + 30.0, h)
	UI.paint_scroll(_scroll, 22)
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	var done := UI.button("Done", 300, 76)
	done.pressed.connect(_close)
	var dc := CenterContainer.new()
	dc.add_child(done)
	v.add_child(dc)
	show_chapter(clampi(last_chapter, 0, CHAPTERS.size() - 1))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _close() -> void:
	queue_free()


## Fills the scroll with chapter `i` and lights its plate.
func show_chapter(i: int) -> void:
	last_chapter = i
	for k in _tabs.size():
		_tabs[k].modulate = Color(1.15, 1.05, 0.85) if k == i else Color(0.72, 0.66, 0.62)
	for c in _list.get_children():
		c.queue_free()
	match i:
		0:
			_page("Win the match", "Two heroes face each other across the board, each with 30 Health. Bring the enemy hero's Health to 0 and you win.")
			_page("Cards", "Your deck holds 30 cards. Minions stay on the board and fight. Spells do their work once and are gone. A card's mana cost is the blue number in its top corner.")
			_page("Reading a minion", "Attack is the number on the left, Health on the right. Damage stays: a minion whose Health reaches 0 is destroyed. A number turns green when it is raised and red when the minion is hurt.")
			_page("Learn by playing", "Virgil's lessons (Learn to Play, on the title screen) teach all of this in a few short matches, one idea at a time.")
		1:
			_page("Mana", "You start with 1 mana crystal and gain one more every turn, up to %d. Your crystals refill when your turn begins. Spend them on cards and on your hero power." % BattleState.MAX_MANA)
			_page("Drawing", "You draw a card at the start of each turn. You can hold %d cards: a card drawn into a full hand burns. Once your deck is empty, every draw deals Fatigue damage to your hero, 1 more each time." % BattleState.MAX_HAND)
			_page("Playing a card", "Drag a card up from your hand onto the board. A card that needs a target becomes an arrow: aim it and let go. Cards you can play now glow green.")
			_page("Hero power", "Every hero has a power beside the portrait: 2 mana, once per turn. %s it to use it." % UI.tap_word())
			_page("Ending your turn", "When you are done, press End Turn. The seal lights up when you have nothing left to do.")
			_page("Your opening hand", "You start with 3 cards, or 4 if you go second. Before the first turn you may swap any of them. The player going second also gets Charon's Obol: a free card that gives 1 extra mana for one turn.")
		2:
			_page("Attacking", "Drag from one of your minions to an enemy minion or to the enemy hero. Each minion attacks once per turn; the ones that can attack glow.")
			_page("Trading blows", "When two minions fight, each deals its Attack as damage to the other. A hero who is attacked does not strike back.")
			_page("Asleep", "A minion cannot attack on the turn it is played: it sleeps until your next turn, unless it has Swift.")
			_page("Guard", "While an enemy minion with Guard stands, your minions must attack it first. Spells can still hit any target.")
			_page("Armor", "Armor sits on top of a hero's Health and takes damage first. It stays until it is used up.")
			_page("The board", "Each side holds up to %d minions." % BattleState.MAX_BOARD)
			if UI.touch_ui():
				_page("On a touch screen", "Drag with your finger, or tap a minion and then its target. Hold a card over your hand to read it at full size. Tap a minion to see its card and keywords.")
			else:
				_page("With a mouse", "Drag to play and to attack, or click a minion and then its target. Right-click cancels. Rest the pointer on a card or a minion to read it and its keywords.")
		3:
			_page("", "Keywords are the bold words on a card. Rest the pointer on a card, or hold it, to see what its keywords mean.")
			for g in KEYWORD_GROUPS:
				_list.add_child(_group_title(g[0]))
				var grid := GridContainer.new()
				grid.columns = 2 if _w >= 900.0 else 1
				grid.add_theme_constant_override("h_separation", 10)
				grid.add_theme_constant_override("v_separation", 10)
				_list.add_child(grid)
				for k in g[1]:
					if UI.KEYWORD_HELP.has(k):
						grid.add_child(_keyword(k, (_w - 10.0) / grid.columns))
		4:
			_page("", "Every hero leads a class with its own cards and hero power. A deck holds cards of its class and neutral cards.")
			for cls in CardDB.classes():
				_list.add_child(_class_page(cls))
		5:
			_page("Decks", "A deck has exactly %d cards: cards of its class plus neutral cards, at most 2 copies of a card and 1 of a legendary." % Collection.DECK_SIZE)
			_page("Choose your path", "Play opens Choose your path. Pick one of the ready-made decks of any class, or a deck you built yourself. The opponent's strength (Easy, Medium or Hard) is set there and in Options.")
			_page("Obols and packs", "Every match pays Obols: %d for a win, %d for a loss. A pack costs %d Obols and holds %d cards, at least one of them rare or better." % [Collection.WIN_REWARD, Collection.LOSS_REWARD, Collection.PACK_PRICE, Collection.PACK_SIZE])
			_page("Your collection", "Collection shows every card you own. Build your own decks from the cards you own; Auto-fill completes a deck along a sensible mana curve. Copies beyond what a deck can use turn into Obols.")
	_scroll.scroll_vertical = 0


## One page: its heading in gold (none when "") over the text, on the framed dark tip plate.
func _page(title: String, text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.tip_box())
	p.custom_minimum_size = Vector2(_w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	if title != "":
		col.add_child(UI.label(title, 30, "title", UI.GOLD, 4, Color(0.04, 0.01, 0.01)))
	var body := UI.label(text, 26, "body" if title != "" else "italic", UI.BONE, 3, Color(0.04, 0.01, 0.01))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(_w - 110.0, 0)
	col.add_child(body)
	_list.add_child(p)


## A heading inside a chapter, on an engraved plaque.
func _group_title(text: String) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(_w, 0)
	c.add_child(UI.plaque_label(text, 30, "title", UI.GOLD, 0.0, 40, 8))
	return c


## A keyword's plate: a minion that has it on the left (when the card pool has one), its name and meaning on the right.
func _keyword(k: String, w: float) -> PanelContainer:
	var help: Array = UI.KEYWORD_HELP[k]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.tip_box())
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var ex := example_card(k)
	var text_w := w - 110.0
	if ex != "":
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(110, 150)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := CardDB.card(ex)
		var m := MinionView.new().setup({"uid": -1, "id": ex, "side": 0, "attack": int(card.get("attack", 0)),
			"health": int(card.get("health", 1)), "max_health": int(card.get("health", 1)), "keywords": card.get("keywords", []),
			"sleeping": false, "frozen": k == "freeze", "silenced": false, "rage": 0})
		m.scale = Vector2(0.78, 0.78)
		m.position = Vector2(55, 78)
		holder.add_child(m)
		if k == "freeze":
			m.set_frozen(true)
		row.add_child(holder)
		text_w -= 128.0
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(UI.label(str(help[0]), 28, "title", UI.GOLD, 4, Color(0.04, 0.01, 0.01)))
	var body := UI.label(str(help[1]), 24, "body", UI.BONE, 3, Color(0.04, 0.01, 0.01))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(maxf(200.0, text_w), 0)
	col.add_child(body)
	if ex != "":
		var who := UI.label(str(CardDB.card(ex).get("name", "")), 20, "italic", Color(0.8, 0.72, 0.6), 3, Color.BLACK)
		col.add_child(who)
	return p


## The cheapest painted minion that shows keyword or trigger `k` ("" when none does, or for Fight, which is an effect):
## by its keywords, its trigger ("on"), its Wrath, or an effect that freezes or silences.
static func example_card(k: String) -> String:
	var best := ""
	var best_cost := 99
	for c in CardDB.all_cards():
		if c.get("type", "") != "minion" or c.get("set", "") == "token" or not CardDB.has_art(str(c.id)):
			continue
		var has := false
		match k:
			"wrath":
				has = int(c.get("wrath", 0)) > 0
			"freeze", "silence", "fight":
				has = k == "freeze" and c.get("keywords", []).is_empty() and c.get("effects", []).is_empty()
			"play", "death", "turn_start", "turn_end", "frenzy":
				has = c.get("effects", []).any(func(e): return str(e.get("on", "")) == k and not e.get("ruse", false))
			"ruse":
				has = c.get("effects", []).any(func(e): return e.get("ruse", false))
			_:
				has = k in c.get("keywords", []) and c.get("keywords", []).size() == 1
		var cost := int(c.get("cost", 0))
		if has and (cost < best_cost or cost == best_cost and str(c.id) < best):
			best = str(c.id)
			best_cost = cost
	return best


## A class's page: its hero's portrait, the class and hero names, its tagline, how it plays, its hero power, the
## keywords it leans on and a few tips (CardDB.class_info: the one source of class text).
func _class_page(cls: String) -> PanelContainer:
	var info := CardDB.class_info(cls)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.tip_box())
	p.custom_minimum_size = Vector2(_w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 190)
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hero := HeroView.new().setup({"uid": -1, "side": 0, "id": str(info.hero), "health": 30, "max_health": 30})
	hero.scale = Vector2(0.72, 0.72)
	hero.position = Vector2(70, 92)
	hero.set_process(false)
	if hero.power != null:
		hero.power.visible = false
	holder.add_child(hero)
	row.add_child(holder)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var tw := _w - 110.0 - 176.0
	col.add_child(UI.label("%s  ·  %s" % [info.title, info.hero_name], 30, "title", UI.GOLD, 4, Color(0.04, 0.01, 0.01)))
	for part in [[str(info.tagline), "italic", Color(0.98, 0.82, 0.55)], [str(info.style), "body", UI.BONE]]:
		if part[0] == "":
			continue
		var l := UI.label(part[0], 25, part[1], part[2], 3, Color(0.04, 0.01, 0.01))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(tw, 0)
		col.add_child(l)
	var pw: Dictionary = info.get("power", {})
	if not pw.is_empty():
		var l := UI.label("Hero power: %s (%d mana). %s" % [pw.get("name", ""), int(pw.get("cost", 2)), pw.get("text", "")],
			24, "body", Color(0.85, 0.9, 1.0), 3, Color(0.04, 0.01, 0.01))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(tw, 0)
		col.add_child(l)
	var kws: Array[String] = []
	for k in info.get("keywords", []):
		if UI.KEYWORD_HELP.has(k):
			kws.append(str(UI.KEYWORD_HELP[k][0]))
	if not kws.is_empty():
		var l := UI.label("Leans on: " + ", ".join(kws), 24, "italic", Color(0.95, 0.78, 0.45), 3, Color(0.04, 0.01, 0.01))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(tw, 0)
		col.add_child(l)
	for tip in info.get("tips", []):
		var l := UI.label("·  " + str(tip), 23, "body", Color(0.9, 0.85, 0.76), 3, Color(0.04, 0.01, 0.01))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(tw, 0)
		col.add_child(l)
	return p
