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
##   and Esc closes it; the first-launch question marks itself asked; a lesson played as Virgil teaches is won through
##   the battle scene (a wrong move refused) and ends on its result; a lesson's pause menu restarts, skips or leaves it.
## - the profile: the name rules (length, characters, spaces cleaned); the title screen has the
##   player plaque and Virgil's medallion; the plaque opens the profile, an invalid name is refused with a red error,
##   a valid one saves (cleaned) with the avatar picked and redraws the plaque, Back and Esc close without saving.

const LessonDriver := preload("res://tests/lesson_driver.gd")

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
	await _lesson_offer()
	_profile_rules()
	await _profile()
	await _lesson_battle()
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
	var first := str(Lessons.all()[0].id)
	if not Game.prepare_lesson(first):
		_fail("the first lesson could not be prepared")
		return
	var b: Node2D = _open(Game.BATTLE)
	var r: Dictionary = await LessonDriver.run(get_tree(), b, Callable(), 240.0)
	if not r.won:
		_fail("lesson %s was not won as taught: %s" % [first, r])
	if not r.refused:
		_fail("lesson %s let End Turn through while Virgil was talking" % first)
	var wait := 0.0 # the result follows the death throes of the last hero
	while b.find_child("LessonResult", true, false) == null and wait < 10.0:
		await get_tree().process_frame
		wait += get_process_delta_time()
	if b.find_child("LessonResult", true, false) == null:
		_fail("lesson %s ended without its result" % first)
	b.queue_free()
	await _frames()
	# The pause menu of a lesson: no Concede, but Restart, Skip and Leave.
	Game.prepare_lesson(first)
	b = _open(Game.BATTLE)
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
	await _frames()
