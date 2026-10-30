extends Node
## Menu behaviour checks (headless, nothing is saved: a debug run). Run:
##   Godot --headless --path . res://tests/menu_smoke.tscn
## - the deck builder asks before Back drops unsaved changes, and Esc (Game.back) closes that question;
## - Delete asks first, and "Keep it" keeps the deck;
## - Back with no changes asks nothing;
## - buying a pack while one is bursting open still reveals the opened pack (it used to sweep the cards away and hang);
## - a deck problem names the class by its title;
## - Choose your path: picking a deck shows it (without starting a battle), the class plaque's "i" opens the class
##   guide and Esc closes it, View cards lists the deck and Esc closes a zoomed card before the list, a key card
##   shown big closes on Esc without leaving the screen;
## - the collection shows the class strip on a class filter (a note on Neutral, nothing on All), and its Class guide
##   button opens the guide;
## - Virgil's lessons: a plaque per lesson, How to Play opens from it with every chapter (the classes as their guides)
##   and Esc closes it; the first-launch question marks itself asked; every lesson played as Virgil teaches is won
##   through the battle's own input (taps, presses, aims) (a wrong move refused) and ends on its result; a lesson's pause menu restarts, skips or leaves it;
##   The Trial's hero choice has a plaque per hero, picks a non-default one, deals that class's starter deck, and the Trial is played through with it.
## - the profile: the name rules (length, characters, spaces cleaned); the title screen has the
##   player plaque and Virgil's medallion; the plaque opens the profile, an invalid name is refused with a red error,
##   a valid one saves (cleaned) with the avatar picked and redraws the plaque, Back and Esc close without saving.

const LessonDriver := preload("res://tests/lesson_driver.gd")
## - the collection's sort plaque cycles through the orders (cost, rarity high / low, name, owned), keeps
##   the choice in the settings, orders the cards as it says, and puts a divider per rarity when sorted by rarity;
## - the pack screen's Drop rates plaque opens the odds sheet (numbers from Collection.ODDS, the pity counter) and Esc
##   closes it;
## - the title screen's showcase rotates through the epic and legendary cards: a rotation tick (instant and animated, both
##   transitions) puts new ids in, always epic or legendary, unique, always three, never a card the pointer is on,
##   at least one legendary on show, and no card comes round again before the whole pool has been shown.
## - optical centring: card names, stat numbers, banner headings, ribbons, plaques, notes and plate buttons have their
##   letters' ink on their frame's centre, and the painted card names are gone.

var fails := 0


func _ready() -> void:
	Settings.fast_animations = true
	Game.intro_played = true
	await _builder_leave()
	await _builder_delete()
	await _pack_buy_while_opening()
	_problem_text()
	await _deck_select()
	await _collection_class()
	await _lessons_screen()
	await _lesson_hero_choice()
	await _lesson_offer()
	_profile_rules()
	await _profile()
	await _showcase_rotation()
	await _lesson_battle()
	await _collection_sort()
	await _drop_rates()
	await _ink_centring()
	await _menu_grid()
	print("MENU SMOKE: %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	printerr("MENU FAIL: " + msg)


func _open(path: String) -> Node:
	var s: Node = load(path).instantiate()
	add_child(s)
	return s


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _owned_id(cls: String) -> String:
	for c in CardDB.all_cards():
		if c.get("set", "") != "token" and Collection.fits_class(c.id, cls) and Collection.copies(c.id) > 0:
			return str(c.id)
	return ""


func _builder_leave() -> void:
	Game.edit_deck = -1
	Game.new_deck_cls = "pilgrim"
	var s := _open(Game.DECK_BUILDER)
	await _frames()
	# Unchanged: Back asks nothing (it would leave the scene, so only the question is checked here).
	if not s.deck.recursive_equal(s._saved, 4):
		_fail("a new deck counts as changed before anything was done")
	s._add(_owned_id("pilgrim"))
	s._leave()
	await _frames()
	if s.get_node_or_null("Dialog") == null:
		_fail("Back with an unsaved card did not ask")
	if not UI.cancel_dialog(s):
		_fail("Esc did not close the leave question")
	await _frames()
	if s.get_node_or_null("Dialog") != null and not s.get_node("Dialog").is_queued_for_deletion():
		_fail("the leave question stayed open after Esc")
	s.queue_free()
	await _frames()


func _builder_delete() -> void:
	Collection.decks.append({"name": "Smoke Deck", "cls": "pilgrim", "cards": {}})
	var n := Collection.decks.size()
	Game.edit_deck = n - 1
	var s := _open(Game.DECK_BUILDER)
	await _frames()
	s._delete()
	await _frames()
	var d: Node = s.get_node_or_null("Dialog")
	if d == null:
		_fail("Delete did not ask")
	else:
		(d.get_meta("cancel") as Button).pressed.emit() # "Keep it"
		await _frames()
	if Collection.decks.size() != n:
		_fail("Keep it removed the deck")
	Collection.decks.pop_back()
	s.queue_free()
	await _frames()


func _pack_buy_while_opening() -> void:
	Collection.packs = 1
	Collection.obols = Collection.PACK_PRICE
	var s := _open(Game.PACKS)
	await get_tree().create_timer(0.6).timeout
	s._open() # bursts the pack open (awaits its own tweens)
	await get_tree().create_timer(0.7).timeout # the pack is gone, the cards are in flight
	if s._state != "opening":
		_fail("expected the pack to be opening, got %s" % s._state)
	s._buy()
	await get_tree().create_timer(1.2).timeout
	if s._state != "reveal" or s._cards.size() != Collection.PACK_SIZE:
		_fail("buying during the opening left state %s with %d cards" % [s._state, s._cards.size()])
	for c in s._cards:
		s._reveal(c)
	await get_tree().create_timer(0.8).timeout
	if s._state != "done":
		_fail("revealing every card did not finish the pack (%s)" % s._state)
	s.queue_free()
	await _frames()


func _problem_text() -> void:
	var off := ""
	for c in CardDB.all_cards():
		if c.get("set", "") not in ["token", "neutral", "pilgrim"]:
			off = str(c.id)
			break
	var cards := {off: 1}
	for c in CardDB.all_cards():
		if Collection.deck_count(cards) >= Collection.DECK_SIZE:
			break
		if c.get("set", "") == "pilgrim":
			cards[c.id] = mini(2, Collection.DECK_SIZE - Collection.deck_count(cards))
	var p := Collection.deck_problem({"name": "x", "cls": "pilgrim", "cards": cards})
	if not p.ends_with("not a %s card" % CardDB.class_title("pilgrim")):
		_fail("deck problem does not name the class title: '%s'" % p)


func _guide_open(scene: Node) -> bool:
	var d := scene.get_node_or_null("Dialog")
	return d != null and not d.is_queued_for_deletion() and d.find_child("ClassGuide", true, false) != null


func _deck_select() -> void:
	Settings.deck_choice = {}
	var s := _open(Game.DECK_SELECT)
	await _frames(4)
	var decks := s.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("key"))
	if decks.size() < 2 * CardDB.classes().size():
		_fail("Choose your path shows %d decks" % decks.size())
		s.queue_free()
		return
	var pick: Button = decks[1]
	pick.pressed.emit()
	await _frames()
	if s._selected != str(pick.get_meta("key")):
		_fail("picking a deck did not show it (%s)" % s._selected)
	if not s.is_inside_tree() or get_tree().current_scene != self:
		_fail("picking a deck left the screen")
	# Every class has its plaque, and its "i" opens that class's guide.
	var strips := s.find_children("ClassStrip", "", true, false)
	if strips.size() != CardDB.classes().size():
		_fail("expected a class plaque per class, got %d" % strips.size())
	if not strips.is_empty():
		(strips[0].find_child("GuideButton", true, false) as Button).pressed.emit()
		await _frames()
		if not _guide_open(s):
			_fail("the class plaque's i did not open the class guide")
		if not UI.cancel_dialog(s):
			_fail("Esc did not close the class guide")
		await _frames()
		if _guide_open(s):
			_fail("the class guide stayed open after Esc")
	# View cards: the whole list; a zoomed card closes first on Esc, then the list.
	s._cards_btn.pressed.emit()
	await _frames()
	var d: Node = s.get_node_or_null("Dialog")
	if d == null:
		_fail("View cards did not open the deck list")
	else:
		var e: Dictionary = s._find(s._selected)
		var slots := d.find_children("*", "CardView", true, false)
		if slots.size() != e.cards.size():
			_fail("the deck list shows %d cards, the deck has %d" % [slots.size(), e.cards.size()])
		CardZoom.open(d, str(e.cards.keys()[0]))
		await _frames()
		UI.cancel_dialog(s)
		await _frames()
		if d.is_queued_for_deletion() or d.get_node_or_null("CardZoom") != null:
			_fail("Esc on a zoomed card did not close just the zoom")
		UI.cancel_dialog(s)
		await _frames()
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			_fail("Esc did not close the deck list")
	# A key card shown big (hover / tap) closes on Esc, and the screen stays.
	var c: CardView = s._cards.get_children().filter(func(n): return n is CardView)[0]
	s._peek_card(c.card_id, c)
	await _frames()
	if s._peek == null:
		_fail("a key card was not shown big")
	s.go_back()
	await _frames()
	if s._peek != null or not s.is_inside_tree():
		_fail("Esc did not close the key card, or left the screen")
	s.queue_free()
	await _frames()


func _collection_class() -> void:
	var s := _open(Game.COLLECTION)
	await _frames()
	var cls: String = CardDB.classes()[0]
	s._set_filter(cls)
	await _frames()
	var strip := s.find_child("ClassStrip", true, false)
	if strip == null:
		_fail("no class strip on the %s filter" % cls)
	else:
		(strip.find_child("GuideButton", true, false) as Button).pressed.emit()
		await _frames()
		if not _guide_open(s):
			_fail("Class guide did not open the guide in the collection")
		UI.cancel_dialog(s)
		await _frames()
	s._set_filter("neutral")
	await _frames()
	if s.find_children("ClassStrip", "", true, false).filter(func(n): return not n.is_queued_for_deletion()).size() != 1:
		_fail("Neutral shows no note (or more than one strip)")
	s._set_filter("all")
	await _frames()
	if not s.find_children("ClassStrip", "", true, false).filter(func(n): return not n.is_queued_for_deletion()).is_empty():
		_fail("All shows a class strip")
	s.queue_free()
	await _frames()


func _lessons_screen() -> void:
	var s := _open(Game.LESSONS)
	await _frames()
	for l in Lessons.all():
		if s.find_child("Lesson_%s" % l.id, true, false) == null:
			_fail("the lessons screen has no plaque for %s" % l.id)
	(s.find_child("HowToPlay", true, false) as Button).pressed.emit()
	await _frames()
	var how := s.find_children("*", "HowToPlayPanel", true, false)
	if how.size() != 1:
		_fail("How to Play did not open from the lessons screen")
	else:
		var h: HowToPlayPanel = how[0]
		for i in HowToPlayPanel.CHAPTERS.size():
			h.show_chapter(i)
			await _frames(2)
			var pages := h._list.get_children().filter(func(n): return not n.is_queued_for_deletion())
			if pages.is_empty():
				_fail("How to Play chapter %s is empty" % HowToPlayPanel.CHAPTERS[i])
		h.show_chapter(HowToPlayPanel.CHAPTERS.find("Classes"))
		await _frames(2)
		var guides := h.find_children("ClassGuide", "", true, false).filter(func(n): return not n.is_queued_for_deletion())
		if guides.size() != CardDB.classes().size():
			_fail("How to Play shows %d class guides for %d classes" % [guides.size(), CardDB.classes().size()])
		Game.back() # Esc / the back gesture: the panel closes, the screen stays
		await _frames()
		if is_instance_valid(h) and not h.is_queued_for_deletion():
			_fail("Esc did not close How to Play")
		if not s.is_inside_tree():
			_fail("Esc on How to Play left the lessons screen")
	s.queue_free()
	await _frames()


## The hero choice before The Trial: one plaque per hero of the class registry, a press picks one, and the match then
## has that hero's class with its starter deck against another class; the whole Trial is played with a non-default
## hero and finishes.
func _lesson_hero_choice() -> void:
	var trial: Dictionary = {}
	for l in Lessons.all():
		if Lessons.chooses_hero(l):
			trial = l
	if trial.is_empty():
		_fail("no lesson lets the player choose a hero")
		return
	Game.lesson_choice = str(trial.id)
	Game.lesson_hero = ""
	var s := _open(Game.LESSON_HERO)
	await _frames(3)
	var heroes := Lessons.pickable_heroes()
	var plaques := s.find_children("Hero_*", "Button", true, false)
	if plaques.size() != heroes.size() or heroes.size() < 2:
		_fail("the hero choice has %d plaques for %d heroes" % [plaques.size(), heroes.size()])
		s.queue_free()
		return
	var default_hero := str(trial.player.hero)
	if s.pick != default_hero:
		_fail("the hero choice starts on %s, not the lesson's hero %s" % [s.pick, default_hero])
	var other := ""
	for h in heroes:
		if h != default_hero:
			other = h
	var cls := CardDB.hero_class(other)
	var btn := s.find_child("Hero_%s" % cls, true, false) as Button
	if btn == null:
		_fail("no plaque for the %s hero" % cls)
		s.queue_free()
		return
	btn.pressed.emit()
	await _frames()
	if s.pick != other:
		_fail("a press on the %s plaque did not pick %s (picked %s)" % [cls, other, s.pick])
	if not (btn.get_node("Chosen") as Control).visible:
		_fail("the picked plaque shows no 'Your hero' ribbon")
	var guide := btn.find_child("Guide", true, false) as Button
	if guide == null:
		_fail("a hero plaque has no class guide button")
	else:
		guide.pressed.emit()
		await _frames()
		if s.get_node_or_null("Dialog") == null:
			_fail("the class guide did not open from the hero choice")
		UI.cancel_dialog(s)
		await _frames(2)
	s.queue_free()
	await _frames()
	Game.prepare_lesson(str(trial.id), other)
	if Game.player_hero != other or Game.player_deck != cls:
		_fail("the Trial did not start as %s (%s / %s)" % [other, Game.player_hero, Game.player_deck])
	if Game.player_cards != CardDB.deck_list(str(CardDB.class_decks(cls)[0].id)):
		_fail("the Trial did not deal the %s starter deck" % cls)
	if Game.enemy_deck == cls:
		_fail("the Trial's opponent plays the player's own class")
	if Game.lesson_hero != other:
		_fail("the chosen hero was not remembered")
	await _play_lesson(str(trial.id), other)


func _lesson_offer() -> void:
	Settings.lessons_offered = false
	var m := _open(Game.MENU)
	await _frames()
	m.offer_lessons()
	await _frames()
	if m.get_node_or_null("Dialog") == null:
		_fail("the first-launch question did not open")
	if not Settings.lessons_offered:
		_fail("the first-launch question was not marked as asked")
	UI.cancel_dialog(m) # "Not now"
	await _frames()
	var d := m.get_node_or_null("Dialog")
	if d != null and not d.is_queued_for_deletion():
		_fail("Esc did not close the first-launch question")
	m.queue_free()
	await _frames()


func _is_showcase_rarity(id: String) -> bool:
	return str(CardDB.card(id).get("rarity", "")) in ["epic", "legendary"]


func _showcase_check(m: Node, what: String) -> void:
	var ids: Array[String] = m.showcase_ids()
	if ids.size() != 3:
		_fail("showcase %s: %d cards on show, not 3" % [what, ids.size()])
	var seen := {}
	var legend := false
	for id in ids:
		if seen.has(id):
			_fail("showcase %s: %s is on show twice" % [what, id])
		seen[id] = true
		if not _is_showcase_rarity(id):
			_fail("showcase %s: %s is %s" % [what, id, CardDB.card(id).get("rarity", "?")])
		legend = legend or ShowcaseDeck.is_legendary(id)
	if not legend:
		_fail("showcase %s: no legendary on show (%s)" % [what, ids])
	var views := 0
	for c in m.get_children():
		if c is CardView:
			views += 1
	if views != 3:
		_fail("showcase %s: %d CardViews alive, not 3 (old ones not freed)" % [what, views])


func _showcase_rotation() -> void:
	var pool := CardDB.showcase_ids()
	if pool.size() < 6:
		_fail("showcase pool too small: %d" % pool.size())
	var kinds := {}
	for id in pool:
		kinds[str(CardDB.card(id).get("type", ""))] = true
		if not _is_showcase_rarity(id):
			_fail("showcase pool holds %s (%s)" % [id, CardDB.card(id).get("rarity", "?")])
	if not (kinds.has("minion") and kinds.has("spell")):
		_fail("showcase pool lacks minions or spells: %s" % [kinds.keys()])
	# The order: a full cycle shows every card once, and a new cycle never puts one on screen twice.
	var deck := ShowcaseDeck.new(pool, 1234)
	var shown := {}
	var on: Array = []
	for i in pool.size():
		var id := deck.take(on, false)
		if shown.has(id):
			_fail("showcase deck repeated %s inside one cycle" % id)
		shown[id] = true
		on = [id]
	if shown.size() != pool.size():
		_fail("showcase deck showed %d of %d cards in a cycle" % [shown.size(), pool.size()])
	var m := _open(Game.MENU)
	await _frames()
	_showcase_check(m, "at launch")
	var before: Array[String] = m.showcase_ids()
	var history := {}
	for i in before:
		history[i] = true
	# Instant ticks: each changes exactly its slot, to a card that was not on show.
	for step in 12:
		var prev: Array[String] = m.showcase_ids()
		var slot: int = m.rotate_now(-1, true)
		if slot < 0:
			_fail("showcase: the rotation tick %d did nothing" % step)
			continue
		var now: Array[String] = m.showcase_ids()
		for i in 3:
			if (i == slot) == (now[i] == prev[i]):
				_fail("showcase tick %d: slot %d (swapped %d): %s -> %s" % [step, i, slot, prev[i], now[i]])
		if history.has(now[slot]) and history.size() < pool.size():
			_fail("showcase tick %d: %s came round again before the pool was done" % [step, now[slot]])
		history[now[slot]] = true
		_showcase_check(m, "after tick %d" % step)
	# Animated, both transitions: one at a time, finished with the new card in place.
	for style in ["burn", "flip"]:
		var prev: Array[String] = m.showcase_ids()
		var slot: int = m.rotate_now(-1, false, style)
		if slot < 0:
			_fail("showcase: the %s swap did not start" % style)
			continue
		if m.rotate_now(-1, true) != -1:
			_fail("showcase: a second swap started during the %s transition" % style)
		var s: int = await m.swapped
		if s != slot:
			_fail("showcase %s: finished slot %d, started %d" % [style, s, slot])
		await _frames()
		var now: Array[String] = m.showcase_ids()
		if now[slot] == prev[slot]:
			_fail("showcase %s: the card did not change" % style)
		_showcase_check(m, "after the %s swap" % style)
	m.queue_free()
	await _frames()


func _profile_rules() -> void:
	for bad in ["", "ab", "  ab  ", "Seventeen chars xx", "Dante!", "a.b.c", "x@y"]:
		if Profile.valid(bad):
			_fail("the name '%s' was accepted" % bad)
	for good in ["Dan", "Niccolò", "Pier_della-Vigna", "Assassin 9", "Nazione", "Troia", "Sixteen chars ab"]:
		if not Profile.valid(good):
			_fail("the name '%s' was refused: %s" % [good, Profile.problem(good)])
	if Profile.clean("  Beatrice   Portinari ") != "Beatrice Portinari":
		_fail("names are not trimmed to single spaces: '%s'" % Profile.clean("  Beatrice   Portinari "))
	if not Profile.valid(Profile.suggestion()):
		_fail("the suggested name %s breaks the rules" % Profile.suggestion())
	if Profile.avatars().size() != CardDB.classes().size():
		_fail("expected an avatar per class, got %d" % Profile.avatars().size())


func _profile() -> void:
	var keep_name := Settings.player_name
	var keep_avatar := Settings.player_avatar
	Settings.player_name = ""
	var m := _open(Game.MENU)
	await _frames()
	if m.find_child("LearnToPlay", true, false) == null:
		_fail("the title screen has no Learn to Play medallion")
	var plaque: Button = m.find_child("ProfilePlaque", true, false)
	if plaque == null:
		_fail("the title screen has no profile plaque")
		m.queue_free()
		return
	plaque.pressed.emit()
	await _frames()
	var p := m.get_node_or_null("Dialog") as ProfilePanel
	if p == null:
		_fail("the profile plaque did not open the profile")
		m.queue_free()
		return
	if not Profile.valid(p.field.text):
		_fail("a new player was not offered a valid name: '%s'" % p.field.text)
	# Invalid: refused, the red error shown, nothing saved.
	p.field.text = "x!"
	p.field.text_changed.emit(p.field.text)
	if p.save():
		_fail("an invalid name was saved")
	if Settings.player_name != "" or not is_instance_valid(p) or p.is_queued_for_deletion():
		_fail("an invalid name changed the profile or closed it")
	var hint: Label = p.find_child("Hint", true, false)
	if hint == null or hint.text == ProfilePanel.HINT:
		_fail("an invalid name shows no error")
	# Valid: cleaned, saved with the avatar picked, the panel closes and the plaque shows the name.
	var hero: String = Profile.avatars()[-1]
	p.pick(hero)
	p.field.text = "  Smoke   Shade "
	p.field.text_changed.emit(p.field.text)
	if not p.save():
		_fail("a valid name was refused: %s" % hint.text)
	await _frames()
	if Settings.player_name != "Smoke Shade" or Settings.player_avatar != hero:
		_fail("the profile saved '%s' / %s" % [Settings.player_name, Settings.player_avatar])
	if is_instance_valid(p) and not p.is_queued_for_deletion():
		_fail("Save did not close the profile")
	var shown: Node = m.find_child("ProfilePlaque", true, false)
	if shown == null or (shown.find_child("Name", true, false) as Label).text != "Smoke Shade":
		_fail("the plaque does not show the saved name")
	# Back and Esc close without saving.
	for how in ["back", "esc"]:
		p = m.open_profile()
		await _frames()
		p.field.text = "Other Name"
		if how == "back":
			(p.find_child("Back", true, false) as Button).pressed.emit()
		elif not UI.cancel_dialog(m):
			_fail("Esc found no profile to close")
		await _frames()
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			_fail("%s did not close the profile" % how)
		if Settings.player_name != "Smoke Shade":
			_fail("%s saved the name" % how)
	Settings.player_name = keep_name
	Settings.player_avatar = keep_avatar
	m.queue_free()
	await _frames()


func _lesson_battle() -> void:
	for l in Lessons.all():
		await _play_lesson(str(l.id))
	var first := str(Lessons.all()[0].id)
	# The pause menu of a lesson: no Concede, but Restart, Skip and Leave.
	Game.prepare_lesson(first)
	var b: Node2D = _open(Game.BATTLE)
	await _frames(30)
	b._open_pause()
	await _frames()
	var names: Array = []
	if b._pause_dim != null:
		names = b._pause_dim.find_children("*", "Button", true, false).map(func(n): return n.text)
	for want in ["Restart Lesson", "Skip Lesson", "Leave Lesson", "How to Play"]:
		if not want in names:
			_fail("a lesson's pause menu has no %s (%s)" % [want, names])
	if "Concede" in names:
		_fail("a lesson's pause menu offers Concede")
	b.queue_free()
	Game.lesson = ""


func _collection_sort() -> void:
	Settings.collection_sort = "cost"
	var s := _open(Game.COLLECTION)
	await _frames()
	var btn := s.find_child("SortButton", true, false) as Button
	if btn == null:
		_fail("the collection has no sort plaque")
		return
	var seen := []
	for k in s.SORTS.size() + 1:
		seen.append(s._sort)
		if not btn.text.begins_with("Sort: "):
			_fail("the sort plaque says '%s'" % btn.text)
		btn.pressed.emit()
		await _frames()
	if seen.size() != s.SORTS.size() + 1 or seen[0] != seen[-1] or seen.slice(0, s.SORTS.size()).has("") 			or seen.slice(0, s.SORTS.size()).size() != _unique(seen.slice(0, s.SORTS.size())).size():
		_fail("the sort plaque did not cycle through every order and back: %s" % str(seen))
	if Settings.collection_sort != s._sort:
		_fail("the sort was not kept in the settings")
	# Rarity: legendaries first, a divider per rarity; low first reverses the rarities.
	s._sort = "rarity"
	s._fill()
	await _frames()
	var cards: Array = s._visible_cards()
	var order := []
	for c in cards:
		if c.set != "token" and not order.has(c.rarity):
			order.append(c.rarity)
	if order != Collection.RARITY_ORDER:
		_fail("sorted by rarity the order was %s" % str(order))
	var dividers := s.find_children("Divider_*", "", true, false).filter(func(n): return not n.is_queued_for_deletion())
	if dividers.size() < 4:
		_fail("sorted by rarity there are %d dividers" % dividers.size())
	s._sort = "rarity_asc"
	if s._visible_cards()[0].rarity != "common":
		_fail("rarity, low first did not start with a common")
	s._sort = "name"
	var names: Array = s._visible_cards().filter(func(c): return c.set != "token").map(func(c): return str(c.name).to_lower())
	var sorted_names := names.duplicate()
	sorted_names.sort()
	if names != sorted_names:
		_fail("sorted by name the cards are not in A-Z order")
	s._sort = "owned"
	var seen_unowned := false
	for c in s._visible_cards():
		if c.set == "token":
			continue
		if Collection.copies(c.id) == 0:
			seen_unowned = true
		elif seen_unowned:
			_fail("owned first: an owned card comes after an unowned one (%s)" % c.id)
			break
	s._sort = "cost"
	s._set_filter("all")
	await _frames()
	if not s.find_children("Divider_*", "", true, false).filter(func(n): return not n.is_queued_for_deletion()).is_empty():
		_fail("cost order shows rarity dividers")
	s.queue_free()
	await _frames()
	Settings.collection_sort = "cost"


func _unique(a: Array) -> Array:
	var out := []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


func _drop_rates() -> void:
	Collection.packs_since_legendary = 7
	var s := _open(Game.PACKS)
	await get_tree().create_timer(0.6).timeout
	var btn := s.find_child("DropRatesButton", true, false) as Button
	if btn == null:
		_fail("the pack screen has no Drop rates plaque")
		s.queue_free()
		return
	btn.pressed.emit()
	await _frames()
	if s.get_node_or_null("Dialog") == null:
		_fail("Drop rates did not open the sheet")
	else:
		var rows := DropRatesPanel.rows()
		var total := 0.0
		for row in rows:
			total += float(row[1])
			if row[0] != "common" and not is_equal_approx(float(row[1]), float(Collection.ODDS[row[0]])):
				_fail("the %s row is not Collection.ODDS" % row[0])
		if not is_equal_approx(total, 1.0) or rows.size() != Collection.RARITY_ORDER.size():
			_fail("the drop-rate rows do not add up to 100%% (%f)" % total)
		for r in Collection.RARITY_ORDER:
			var l := s.find_child("Rate_" + r, true, false) as Label
			var want := Collection.percent_text(Collection.drop_rates()[r])
			if l == null or l.text != want:
				_fail("the %s rate shows '%s', wanted '%s'" % [r, l.text if l != null else "nothing", want])
		var pity := s.find_child("Pity", true, false) as Label
		if pity == null or pity.text != "Packs since your last Legendary: 7 / %d" % Collection.PITY_LEGENDARY:
			_fail("the pity counter shows '%s'" % (pity.text if pity != null else "nothing"))
		if not UI.cancel_dialog(s):
			_fail("Esc did not close the drop-rates sheet")
		await _frames()
		await _frames()
		var d := s.get_node_or_null("Dialog")
		if d != null and not d.is_queued_for_deletion():
			_fail("the drop-rates sheet stayed open after Esc")
	s.queue_free()
	await _frames()


## Lesson `id` played as Virgil teaches it, through the battle's own input (taps, presses, aims): it must be won.
func _play_lesson(id: String, hero := "") -> void:
	if not Game.prepare_lesson(id, hero):
		_fail("lesson %s could not be prepared" % id)
		return
	var b: Node2D = _open(Game.BATTLE)
	if hero != "" and Game.player_hero != hero:
		_fail("lesson %s was not played as %s" % [id, hero])
	var r: Dictionary = await LessonDriver.run(get_tree(), b, Callable(), 240.0)
	# A lesson that ends in free play (The Trial) is finished by the AI for the player: it may lose that match.
	var free: bool = Lessons.get_lesson(id).steps.any(func(st): return str(st.get("until", "")) == "win")
	if not (r.over if free else r.won):
		_fail("lesson %s was not %s as taught: %s" % [id, "finished" if free else "won", r])
	var taps: bool = Lessons.get_lesson(id).steps.any(func(st): return str(st.get("wait", "")) == "tap")
	if taps and not r.refused: # a lesson of free play only (The Trial) has no line to talk over
		_fail("lesson %s let End Turn through while Virgil was talking" % id)
	var wait := 0.0 # the result follows the death throes of the last hero
	while b.find_child("LessonResult", true, false) == null and wait < 10.0:
		await get_tree().process_frame
		wait += get_process_delta_time()
	if b.find_child("LessonResult", true, false) == null:
		_fail("lesson %s ended without its result" % id)
	b.queue_free()
	await _frames()


## Optical centring (UI.center_ink), checked headless from the glyph outlines and the Labels' own layout
## (get_character_bounds: where Godot really sets the line): the ink of card names, stat numbers, banner headings,
## ribbons, plaques and notes is centred on its frame within INK_TOL px; a plate button keeps its size; painted words
## are centred by their opaque part; the cards have no painted names left. tests/ink_centering.tscn measures the
## same on drawn pixels.
const INK_TOL := 0.75


func _ink_centring() -> void:
	var db_funcs: Array = (load("res://scripts/core/card_db.gd") as Script).get_script_method_list().map(func(m): return m.name)
	if "name_tex" in db_funcs or DirAccess.dir_exists_absolute("res://assets/cards/names"):
		_fail("painted card names are back (CardDB.name_tex / assets/cards/names)")
	var holder := Control.new()
	add_child(holder)
	# Card names on the ribbon's band, stat numbers on the gems' visual centres, also after the values change.
	for id in ["minos", "francesca", "pj_beatrice", "lost_pilgrim", "harpy"]:
		var c := CardView.new().setup(id, -1, true)
		c.position = Vector2(400, 300)
		holder.add_child(c)
		await _frames(2)
		var face := c.position - Vector2(CardView.W, CardView.H) / 2.0
		var name_l: Label = c.find_child("Name", true, false)
		if name_l == null:
			_fail("%s has no gilded name label" % id)
			continue
		if name_l.material == null or (name_l.material as ShaderMaterial).get_shader_parameter("gild") != true:
			_fail("%s's name is not gilded" % id)
		_check_ink("%s name" % id, name_l, face + Vector2(CardView.W / 2.0, 190.0 + 54.0 * (0.5 + UI.RIBBON_BAND)))
		var is_spell: bool = CardDB.card(id).get("type", "minion") == "spell"
		_check_ink("%s cost" % id, c._cost_label, face + Vector2(28, 28))
		if not is_spell:
			c.set_stats(10, 1, 30)
			await _frames(1)
			_check_ink("%s attack 10" % id, c._atk_label, face + Vector2(28, CardView.H - 28) + UI.GEM_CENTER.gem_attack * 74.0)
			_check_ink("%s health 1" % id, c._hp_label, face + Vector2(CardView.W - 28, CardView.H - 30) + UI.GEM_CENTER.gem_health * 74.0)
		c.queue_free()
	# Banner headings (in the font) on the charred band, name ribbons on their band.
	for t in ["Choose Your Hero", "Options", "DISCONNECTED"]:
		var ban := UI.banner(t, 54, UI.GOLD, 0.0, 0.0, 1.8)
		ban.position = Vector2(50, 50)
		holder.add_child(ban)
		await _frames(2)
		var h := roundf(54 * 1.8)
		var band := UI.BANNER_BAND * h if UiSkin.has("turn_banner") else 0.0
		_check_ink("banner " + t, ban.get_node("Text"), ban.get_global_rect().get_center() + Vector2(0, band))
		ban.queue_free()
	for r in [["Start here", 230.0, 28], ["The Pilgrim's Way", 700.0, 40]]:
		var rib := UI.ribbon(r[0], r[1], r[2])
		holder.add_child(rib)
		rib.position = Vector2(100, 100)
		await _frames(2)
		var h: float = float(r[1]) * 144.0 / 768.0
		_check_ink("ribbon " + r[0], rib.get_node("Text"), rib.get_global_rect().get_center() + Vector2(0, UI.RIBBON_BAND * h))
		rib.queue_free()
	# Plaques and parchment notes: on the panel's middle, the panel no bigger than its text needs.
	for p in [UI.plaque_label("Wrath", 30, "title", UI.EMBER), UI.parchment_label("Not enough mana", 30, "title", UI.INK_RED),
			UI.parchment_label("Your opponent left.\nYou win the duel.", 30, "italic"), UI.plaque_label("v0.8.2", 20, "body")]:
		holder.add_child(p)
		p.position = Vector2(80, 80)
		await _frames(2)
		p.reset_size()
		await _frames(1)
		var l: Label = p.get_node("Text")
		_check_ink("plate '%s'" % l.text.replace("\n", " / "), l, p.get_global_rect().get_center())
		var sb: StyleBox = p.get_theme_stylebox("panel")
		var base: Array = sb.get_meta("_ink_base", [])
		if base.size() == 4 and absf(sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) - base[0] - base[1]) > 0.01:
			_fail("plate '%s' changed its height to centre its text" % l.text)
		p.queue_free()
	# A plate button: its letters moved by trading its margins, so it keeps its size; refitted text re-centres.
	var b := UI.button("Sign in with Google", 300, 84)
	holder.add_child(b)
	await _frames(2)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st)
		var base: Array = sb.get_meta("_ink_base", [])
		if base.size() != 4 or absf(sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) - base[0] - base[1]) > 0.01:
			_fail("button %s margins do not keep their sum" % st)
	var want := UI.ink_offset(b)
	var nb := b.get_theme_stylebox("normal")
	var nbase: Array = nb.get_meta("_ink_base")
	var moved: float = (nb.get_margin(SIDE_TOP) - nb.get_margin(SIDE_BOTTOM) - (float(nbase[0]) - float(nbase[1]))) / 2.0
	if absf(moved + want.y) > 0.01:
		_fail("button text moved %.2f px, its ink needs %.2f" % [moved, -want.y])
	b.queue_free()
	# Painted words: their opaque part on the given centre.
	var word := UI.word_tex("YOUR TURN")
	if word != null:
		var wr := UI.word_rect(word, Vector2(700, 72))
		UI.place_word(wr, Vector2(500, 300))
		var o := UI.opaque_rect(word)
		var k := wr.size / word.get_size()
		var ctr := wr.position + (o.position + o.size / 2.0) * k
		if ctr.distance_to(Vector2(500, 300)) > 0.01:
			_fail("painted words centred at %s, not on (500, 300)" % ctr)
		wr.free()
	holder.queue_free()
	await _frames()


## `l`'s ink centre, from where Godot sets its first line (its character bounds) and the glyph outlines, against
## `want` (global px).
func _check_ink(what: String, l: Label, want: Vector2) -> void:
	var f := l.get_theme_font("font")
	var lay := UI.text_layout(f, l.get_theme_font_size("font_size"), l.text, -1.0, l.get_theme_constant("line_spacing"),
		l.get_theme_constant("paragraph_spacing"))
	var ink: Rect2 = lay["ink"]
	var block: Vector2 = lay["block"]
	var first := l.get_character_bounds(0)
	# ink_rect is relative to the block's centre, its first line starting at x = -(that line's width) / 2: with one line
	# the block's width; a block of lines is checked up and down only.
	var line_w := f.get_string_size(l.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
	var local := first.position + Vector2(line_w / 2.0, block.y / 2.0) + ink.get_center()
	var got := l.get_global_transform() * local
	var d := got - want
	if int(lay["lines"]) > 1:
		d.x = 0.0
	if is_nan(want.x): # a left-aligned label: only its height is centred
		d.x = 0.0
	if absf(d.x) > INK_TOL or absf(d.y) > INK_TOL:
		_fail("%s: its letters sit (%+.2f, %+.2f) px off their frame's centre" % [what, d.x, d.y])


## The title screen and its Options on one grid: the menu plates evenly spaced (Virgil's medallion beside Play does not
## widen its gap); in Options every row of both columns ROW_H tall and level with its neighbour across, every control
## of a column on the same left and right edges, every label's letters centred on its row.
func _menu_grid() -> void:
	var m := _open(Game.MENU)
	await _frames(3)
	var plates: Array[Rect2] = []
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text in ["Play", "Collection", "Options", "Quit"] or (b as Button).text.begins_with("Open Packs"):
			plates.append((b as Button).get_global_rect())
	plates.sort_custom(func(a: Rect2, b: Rect2): return a.position.y < b.position.y)
	for i in range(1, plates.size() - 1):
		var g0 := plates[i].position.y - plates[i - 1].end.y
		var g1 := plates[i + 1].position.y - plates[i].end.y
		if absf(g0 - g1) > 0.5:
			_fail("title screen plates unevenly spaced: %.1f px, then %.1f px" % [g0, g1])
	var o := OptionsPanel.new()
	m.add_child(o)
	await _frames(3)
	var cols: Array = [o.find_child("Left", true, false), o.find_child("Right", true, false)]
	if cols.has(null):
		_fail("the options panel has no Left / Right columns")
		m.queue_free()
		return
	var tops: Array = [[], []]
	for ci in 2:
		var edges := Vector2(-1, -1)
		for row in (cols[ci] as Control).get_children():
			var r := (row as Control).get_global_rect()
			tops[ci].append(r.position.y)
			if absf(r.size.y - OptionsPanel.ROW_H) > 0.01:
				_fail("options row %s is %.1f px tall, not %.0f" % [row.get_child(0).text, r.size.y, OptionsPanel.ROW_H])
			var ctl := (row as Control).get_child(-1) as Control
			var e := Vector2(ctl.get_global_rect().position.x, ctl.get_global_rect().end.x)
			if edges.x < 0.0:
				edges = e
			elif e.distance_to(edges) > 0.01:
				_fail("options control in row '%s' spans %s, the column's others %s" % [row.get_child(0).text, e, edges])
			var l := (row as Control).get_child(0) as Label
			if l.text != "":
				_check_ink("options label " + l.text, l, Vector2(NAN, r.get_center().y))
	for i in mini(tops[0].size(), tops[1].size()):
		if absf(tops[0][i] - tops[1][i]) > 0.01:
			_fail("options row %d is not level across the columns (%.1f, %.1f)" % [i, tops[0][i], tops[1][i]])
	# Check for updates: outside an exported game it says so (no request is made).
	var upd := o.find_child("CheckUpdates", true, false) as Button
	if upd == null:
		_fail("the options panel has no Check for updates")
	else:
		upd.pressed.emit()
		await _frames(2)
		if o.get_node_or_null("Dialog") == null:
			_fail("Check for updates answered nothing")
	m.queue_free()
	await _frames()
