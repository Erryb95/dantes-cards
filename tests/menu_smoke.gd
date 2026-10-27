extends Node
## Menu behaviour checks (headless, nothing is saved: a debug run). Run:
##   Godot --headless --path . res://tests/menu_smoke.tscn
## - the deck builder asks before Back drops unsaved changes, and Esc (Game.back) closes that question;
## - Delete asks first, and "Keep it" keeps the deck;
## - Back with no changes asks nothing;
## - buying a pack while one is bursting open still reveals the opened pack (it used to sweep the cards away and hang);
## - a deck problem names the class by its title.

var fails := 0


func _ready() -> void:
	Settings.fast_animations = true
	Game.intro_played = true
	await _builder_leave()
	await _builder_delete()
	await _pack_buy_while_opening()
	_problem_text()
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
