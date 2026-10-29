class_name Lessons
## Virgil's lessons: the guided matches that teach the game (data/lessons.json). Static access to the data, the
## player's progress (Settings.lessons), the setup of a lesson's battle and the rules its steps follow. Used by the
## lessons screen (scripts/ui/lessons.gd), the battle (LessonGuide, LessonAI) and the tests.

const DATA := "res://data/lessons.json"
const DONE := "done"
const SKIPPED := "skipped"

static var _lessons: Array = []


# The autoloads, looked up on the tree: the headless tests (`-s`) compile this script without autoload names.
static func _prefs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Settings")


static func _collection() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Collection")


static func _game() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Game")


static func all() -> Array:
	if _lessons.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_lessons = d.get("lessons", []).map(func(l): return Loc.localize("lessons", str(l.id), l))
	return _lessons


## Reads the data again on next use (the language changed).
static func reload() -> void:
	_lessons = []


static func get_lesson(id: String) -> Dictionary:
	for l in all():
		if l.id == id:
			return l
	return {}


static func index_of(id: String) -> int:
	for i in all().size():
		if all()[i].id == id:
			return i
	return -1


## The lesson after `id` ("" after the last one).
static func next_after(id: String) -> String:
	var i := index_of(id)
	return str(all()[i + 1].id) if i != -1 and i + 1 < all().size() else ""


# ---------------------------------------------------------------- progress

## "done" (won at least once), "skipped" or "" (not played yet).
static func status(id: String) -> String:
	return str(_prefs().lessons.get(id, ""))


## The lesson to play next: the first one not won yet ("" when every lesson is done).
static func recommended() -> String:
	for l in all():
		if status(l.id) != DONE:
			return str(l.id)
	return ""


static func done_count() -> int:
	var n := 0
	for l in all():
		if status(l.id) == DONE:
			n += 1
	return n


## The lesson's reward as a line of text ("50 Obols", "1 pack"), "" when it has none.
static func reward_text(l: Dictionary) -> String:
	var r: Dictionary = l.get("reward", {})
	if int(r.get("packs", 0)) > 0:
		return Loc.t("%d pack") % r.packs if int(r.packs) == 1 else Loc.t("%d packs") % r.packs
	if int(r.get("obols", 0)) > 0:
		return Loc.t("%d Obols") % r.obols
	return ""


## A won lesson: marked done (saved), and its reward paid the first time only. Returns what was paid ({} after the
## first win). Debug runs keep it all in memory (Settings / Collection never write there).
static func complete(id: String) -> Dictionary:
	var first := status(id) != DONE
	_prefs().lessons[id] = DONE
	_prefs().save()
	if not first:
		return {}
	var r: Dictionary = get_lesson(id).get("reward", {})
	if int(r.get("obols", 0)) > 0:
		_collection().obols += int(r.obols)
	if int(r.get("packs", 0)) > 0:
		_collection().packs += int(r.packs)
	if not r.is_empty():
		_collection().save()
	return r


## The player skipped a lesson (from its pause menu): it stops being the recommended one only if nothing better is
## on record; it can still be played and won later, for its reward.
static func skip(id: String) -> void:
	if status(id) == "":
		_prefs().lessons[id] = SKIPPED
		_prefs().save()


## The first-launch question ("Shall I show you the way?") is due: a fresh profile that has played no lesson and no
## match and was never asked. Never in tests or tooling runs, unless `-- --offer-lessons` asks for it.
static func offer_due() -> bool:
	if "--offer-lessons" in OS.get_cmdline_user_args():
		return true
	if _game().debug_run() or _prefs().lessons_offered:
		return false
	return _prefs().lessons.is_empty() and _game().first_match()


# ---------------------------------------------------------------- battle setup

## The cards and heroes of a lesson's match: {player_cards, player_hero, enemy_cards, enemy_hero, enemy_deck_id}.
## "deck": "starter" deals the hero's class starter; enemy hero "random" picks a hero of another class.
## `pick`: the hero the player chose, for a lesson that lets them choose ("choose": true on its player, see `chooses_hero`).
static func line_up(l: Dictionary, pick: String = "") -> Dictionary:
	var p: Dictionary = l.get("player", {})
	var e: Dictionary = l.get("enemy", {})
	var hero := str(p.get("hero", "dante"))
	if pick != "" and chooses_hero(l) and pick in pickable_heroes():
		hero = pick
	var foe := str(e.get("hero", "charon"))
	if foe == "random":
		var pool := CardDB.other_classes(CardDB.hero_class(hero)).filter(func(c): return not CardDB.class_decks(c).is_empty())
		foe = CardDB.class_hero(pool.pick_random()) if not pool.is_empty() else hero
	var out := {"player_hero": hero, "enemy_hero": foe, "enemy_deck_id": ""}
	out.player_cards = _cards_of(p, hero)
	out.enemy_cards = _cards_of(e, foe)
	if str(e.get("deck", "")) == "starter":
		out.enemy_deck_id = str(CardDB.class_decks(CardDB.hero_class(foe))[0].id)
	return out


## The lesson lets the player choose their hero ("choose": true on its player: The Trial); its "hero" is the default.
static func chooses_hero(l: Dictionary) -> bool:
	return bool(l.get("player", {}).get("choose", false))


## The heroes a player can choose from: one per class of the registry that has a preconstructed deck (never a fixed
## count: new classes and heroes join CardDB.classes()).
static func pickable_heroes() -> Array[String]:
	var out: Array[String] = []
	for c in CardDB.classes():
		if not CardDB.class_decks(c).is_empty() and CardDB.class_hero(c) != "":
			out.append(CardDB.class_hero(c))
	return out


static func _cards_of(side: Dictionary, hero: String) -> Array[String]:
	var out: Array[String] = []
	if str(side.get("deck", "")) == "starter":
		var decks := CardDB.class_decks(CardDB.hero_class(hero))
		if not decks.is_empty():
			out = CardDB.deck_list(str(decks[0].id))
	else:
		for id in side.get("cards", []):
			out.append(str(id))
	return out


## Sets a battle up as lesson `l` before its start(): dealing order, opening hands, the Obol, heroes' Health, mana
## and minions already in play.
static func configure(st: BattleState, l: Dictionary) -> void:
	st.stacked = bool(l.get("stacked", false))
	st.coin = bool(l.get("coin", true))
	var sides := [l.get("player", {}), l.get("enemy", {})]
	for i in 2:
		var s: Dictionary = sides[i]
		st.opening[i] = int(s.get("opening", -1))
		st.hero_health[i] = int(s.get("health", 0))
		st.hero_wounds[i] = int(s.get("wounds", 0))
		st.start_mana[i] = int(s.get("mana", 0))
		st.start_board[i] = s.get("board", []).duplicate()


## The lesson's opponent: the Easy AI for a real match ("ai": "easy"), else its scripted turns.
static func make_ai(l: Dictionary) -> BattleAI:
	if str(l.get("ai", "")) == "easy":
		return BattleAI.new(1, BattleAI.Level.EASY)
	return LessonAI.new(l.get("script", []), str(l.get("after", "easy")))


## A fresh battle for lesson `l`, set up and started (the tests drive it; the battle screen uses configure()).
static func start_state(l: Dictionary, seed_value: int = 1, pick: String = "") -> BattleState:
	var lu := line_up(l, pick)
	var st := BattleState.new()
	configure(st, l)
	st.start(lu.player_cards, lu.player_hero, lu.enemy_cards, lu.enemy_hero, seed_value, bool(l.get("mulligan", false)),
		int(l.get("first", 0)))
	return st


# ---------------------------------------------------------------- steps

## True when `action` is what step-action `want` ({act, card?, target?}) asks for. `action`: {act, card, target}
## with the target's uid (-1 none); a partial action (no "target" key: the aim has not ended yet) matches on act and card.
static func matches(want: Dictionary, action: Dictionary, st: BattleState) -> bool:
	if str(want.get("act", "")) != str(action.get("act", "")):
		return false
	if want.has("card") and str(want.card) != str(action.get("card", "")):
		return false
	if want.has("target") and action.has("target"):
		return is_target(str(want.target), int(action.target), st)
	return true


## Whether unit `uid` is the one a step names: foe_hero, my_hero, foe:<card id>, mine:<card id>.
static func is_target(spec: String, uid: int, st: BattleState) -> bool:
	var u = st.units.get(uid)
	if u == null:
		return false
	match spec:
		"foe_hero":
			return u.is_hero and u.side == 1
		"my_hero":
			return u.is_hero and u.side == 0
	var parts := spec.split(":")
	if parts.size() != 2 or u.is_hero:
		return false
	return u.id == parts[1] and u.side == (1 if parts[0] == "foe" else 0)


## The first unit a target spec names (uid), or -1.
static func find_target(spec: String, st: BattleState) -> int:
	for uid in st.units:
		if is_target(spec, uid, st):
			return uid
	return -1


## The concrete action that does step-action `want` in `st` for the player (side 0), or {} when it cannot be done:
## {"do": play|attack|power|end, ...} in BattleAI.apply's shape (the tests replay a lesson with it).
static func resolve(want: Dictionary, st: BattleState) -> Dictionary:
	var tgt := find_target(str(want.target), st) if want.has("target") else -1
	match str(want.get("act", "")):
		"play":
			for c in st.sides[0].hand:
				if c.id == str(want.get("card", "")) and st.can_play(0, c.uid):
					return {"do": "play", "uid": c.uid, "target": tgt, "index": -1}
		"attack":
			for u in st.sides[0].board:
				if u.id == str(want.get("card", "")) and st.can_attack(u) and st.attack_targets(0).has(tgt):
					return {"do": "attack", "attacker": u.uid, "target": tgt}
		"power":
			if st.can_use_power(0):
				return {"do": "power", "target": tgt}
		"end":
			return {"do": "end"}
	return {}
