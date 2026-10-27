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
##   closes it.

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
	await _lesson_battle()
	await _collection_sort()
	await _drop_rates()
	await _painted_names()
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


## Painted card names: a card with one shows it when it is big enough to read and falls back to the gilded label when
## not (a long name at hand size), a card without one has only the label, and the painting is brightened.
func _painted_names() -> void:
	var painted: Array[String] = []
	var dir := DirAccess.open("res://assets/cards/names")
	for f in dir.get_files() if dir != null else PackedStringArray():
		if f.ends_with(".png"):
			painted.append(f.get_basename())
	if painted.is_empty():
		return
	# The legibility rule reads the card's size on screen: a headless window is 64 px wide, so give it the design size.
	var win := get_window()
	var keep_size := win.size
	win.size = Vector2i(1920, 1080)
	await _frames(2)
	for id in painted:
		var big := CardView.new().setup(id, -1, true)
		big.scale = Vector2.ONE * 1.9
		add_child(big)
		var tiny := CardView.new().setup(id, -1, true)
		tiny.scale = Vector2.ONE * 0.2
		add_child(tiny)
		await _frames(3)
		if big._name_painted == null or not big._name_shows_painted:
			_fail("%s zoomed shows no painted name" % id)
		elif float(big._name_painted.material.get_shader_parameter("name_gain")) <= 1.0:
			_fail("the painted name of %s is not brightened" % id)
		if tiny._name_shows_painted and tiny._name_painted_cap * 0.2 < CardView.NAME_MIN_CAP 				and tiny._name_painted_cap < tiny._name_label_cap:
			_fail("%s at 0.2 scale keeps a painted name too small to read" % id)
		# Growing a card switches it to the painted name, shrinking it back to the label, with no stale half-fade.
		tiny.scale = Vector2.ONE * 1.9
		await _frames(2)
		await get_tree().create_timer(0.3).timeout
		if not tiny._name_shows_painted or tiny._name_painted.modulate.a < 0.99 or tiny._name_label.modulate.a > 0.01:
			_fail("%s did not switch to its painted name when enlarged" % id)
		big.queue_free()
		tiny.queue_free()
	# A long name at hand size reads better as the gilded label; a card with no painted name never has a painting.
	var long_id := ""
	for id in painted:
		var w: float = CardDB.name_tex(id).get_width()
		if w > 1500.0:
			long_id = id
	if long_id != "":
		var hand := CardView.new().setup(long_id, -1, true)
		hand.scale = Vector2.ONE * 0.62
		add_child(hand)
		await _frames(3)
		if hand._name_shows_painted or hand._name_label.modulate.a < 0.99:
			_fail("%s at hand size keeps its too-small painted name" % long_id)
		hand.queue_free()
	var plain := ""
	for c in CardDB.all_cards():
		if CardDB.name_tex(str(c.id)) == null:
			plain = str(c.id)
			break
	if plain != "":
		var v := CardView.new().setup(plain, -1, true)
		add_child(v)
		await _frames(2)
		if v._name_painted != null or v._name_label == null or v._name_label.modulate.a < 0.99:
			_fail("%s has no painted name but is not drawn with the gilded label" % plain)
		v.queue_free()
	win.size = keep_size
	await _frames()


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
