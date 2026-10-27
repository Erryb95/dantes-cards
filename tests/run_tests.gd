extends SceneTree
## Headless rules tests + AI-vs-AI soak.
##   Godot --headless --path . -s res://tests/run_tests.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_data()
	_test_rules()
	_test_ulysses()
	_soak(120)
	_soak_classes(24)
	_soak_random(400)
	_soak_random_classes(120)
	_test_replay(20)
	_test_replay(8, "ulysses")
	print("TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


func _test_data() -> void:
	var deck_ids := {}
	for d in CardDB.decks():
		var list := CardDB.deck_list(d.id)
		var cls := CardDB.deck_class(d)
		ok(not deck_ids.has(d.id), "deck id %s is unique" % d.id)
		deck_ids[d.id] = true
		ok(cls in CardDB.classes(), "deck %s class %s" % [d.id, cls])
		ok(list.size() == 30, "deck %s has 30 cards (%d)" % [d.id, list.size()])
		ok(not CardDB.hero(d.hero).is_empty(), "deck %s hero exists" % d.id)
		ok(d.hero == CardDB.class_hero(cls), "deck %s hero matches its class" % d.id)
		ok(str(d.get("name", "")) != "" and str(d.get("text", "")) != "", "deck %s has a name and a plan" % d.id)
		ok(d.get("featured", []).size() == 3, "deck %s features 3 cards" % d.id)
		for id in d.get("featured", []):
			ok(id in list, "deck %s features its own card %s" % [d.id, id])
		for id in list:
			ok(not CardDB.card(id).is_empty(), "card %s exists" % id)
			ok(list.count(id) <= (1 if CardDB.card(id).get("rarity") == "legendary" else 2), "deck %s copies of %s" % [d.id, id])
			ok(CardDB.card(id).get("set") in [cls, "neutral"], "deck %s class of %s" % [d.id, id])
	ok(CardDB.classes().size() >= 2, "at least two classes")
	for cls in CardDB.classes():
		ok(CardDB.class_title(cls) != "" and CardDB.hero_class(CardDB.class_hero(cls)) == cls, "class %s has a hero" % cls)
		ok(not CardDB.class_decks(cls).is_empty() and CardDB.class_decks(cls)[0].get("starter", false),
			"the first %s deck is the starter" % cls)
		var hero := CardDB.hero(CardDB.class_hero(cls))
		ok(int(hero.get("health", 0)) == 30 and int(hero.get("power", {}).get("cost", 0)) == 2,
			"hero of %s: 30 health, 2-mana power" % cls)
		ok(ResourceLoader.exists("res://assets/ui/%s.png" % str(hero.get("power_icon", ""))), "hero of %s has a power icon" % cls)
		ok(str(hero.get("defeat_line", "")) != "" and str(hero.get("power", {}).get("text", "")) != "",
			"hero of %s has its lines" % cls)
		ok(CardDB.class_decks(cls).size() == 3, "%s has three preconstructed decks" % cls)
	for c in CardDB.all_cards():
		for e in c.get("effects", []):
			ok(e.do in ["damage", "heal", "draw", "buff", "summon", "bounce", "armor", "destroy", "freeze", "silence", "ramp", "give_card", "mana", "copy", "transform"], "%s effect %s" % [c.id, e.do])
			if e.do in ["summon", "give_card", "transform"]:
				ok(not CardDB.card(e.card).is_empty(), "%s summons a known card" % c.id)
		for k in c.get("keywords", []):
			ok(k in ["guard", "swift", "ward", "drain", "venom", "rebirth"], "%s keyword %s" % [c.id, k])
	ok(CardDB.arenas().size() >= 1, "at least one arena")
	_test_arenas()
	_test_vfx()


## data/vfx.json: every spell has a profile and every name in it is one Vfx knows.
func _test_vfx() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(VfxData.DATA))
	ok(d is Dictionary and d.has("cards"), "vfx.json parses")
	var cards: Dictionary = d.get("cards", {}) if d is Dictionary else {}
	for c in CardDB.all_cards():
		if c.type == "spell":
			ok(cards.has(c.id), "spell %s has a vfx profile" % c.id)
	for id in cards:
		var e: Dictionary = cards[id]
		ok(not CardDB.card(id).is_empty() or id.begins_with("power_") and not CardDB.hero(id.substr(6)).is_empty(),
			"vfx profile %s names a card" % id)
		ok(VfxData.SCHOOLS.has(e.get("school", "fire")), "vfx %s school" % id)
		ok(e.get("hit", "orb") in VfxData.HITS, "vfx %s hit" % id)
		ok(e.get("mass", "rain") in VfxData.MASSES or e.get("mass", "") in VfxData.HITS, "vfx %s mass" % id)
		ok(e.get("cast", "") in VfxData.CASTS, "vfx %s cast" % id)
	for name in VfxData.SCHOOLS:
		var s: Dictionary = VfxData.SCHOOLS[name]
		ok(s.hit in VfxData.HITS and (s.mass in VfxData.MASSES), "school %s default patterns" % name)
	for v in VfxData.CIRCLE_SCHOOL.values():
		ok(VfxData.SCHOOLS.has(v), "circle school %s" % v)


## Arena data: every entry is complete, its sounds exist, and the Acheron (the fallback) is always playable.
func _test_arenas() -> void:
	ok(CardDB.arena_ready("acheron"), "the Acheron board is installed (every missing board falls back to it)")
	for a in CardDB.arenas():
		for key in ["id", "name", "circle", "intro", "music", "board"]:
			ok(str(a.get(key, "")) != "", "arena %s has %s" % [a.get("id", "?"), key])
		ok(str(a.get("divider", {}).get("kind", "river")) in ["river", "stream", "wind", "embers", "frost"],
			"arena %s divider kind" % a.id)
		ok(str(a.get("ambient", "embers")) in ["embers", "embers_hot", "motes", "dust", "snow"], "arena %s ambient" % a.id)
		ok(str(a.get("ambience", "")) == "" or ResourceLoader.exists("res://assets/audio/sfx/" + str(a.ambience)),
			"arena %s ambience file" % a.id)
		ok(ResourceLoader.exists(str(a.get("scene", "res://scenes/arenas/standard.tscn"))), "arena %s scene" % a.id)
		ok(ResourceLoader.exists("res://assets/audio/music/%s/c1_0.ogg" % a.music), "arena %s music" % a.id)
		for p in a.get("props", []):
			ok(p.has("name") and p.get("pos", []).size() == 2, "arena %s prop entry %s" % [a.id, p.get("name", "?")])
			for key in ["sfx", "sfx2"]:
				if p.has(key):
					ok(_sfx_exists(str(p[key][0])), "arena %s prop %s sound %s" % [a.id, p.name, p[key][0]])


func _sfx_exists(name: String) -> bool:
	for f in [name + ".ogg", name + ".wav", name + "_0.ogg", name + "_0.wav"]:
		if ResourceLoader.exists("res://assets/audio/sfx/" + f):
			return true
	return false


## A fresh battle with empty hands/boards for unit tests.
func _blank() -> BattleState:
	var st := BattleState.new()
	var filler: Array[String] = []
	for i in 20:
		filler.append("lost_pilgrim")
	st.start(filler, "dante", filler.duplicate(), "charon", 7)
	for s in st.sides:
		s.hand.clear()
		s.mana = 10
		s.max_mana = 10
	return st


func _put(st: BattleState, side: int, id: String) -> BattleState.Unit:
	var u := st._summon(side, id)
	u.sleeping = false
	return u


func _give(st: BattleState, side: int, id: String) -> int:
	var c := {"uid": st._uid(), "id": id}
	st.sides[side].hand.append(c)
	return c.uid


func _test_rules() -> void:
	# Guard forces attacks onto it.
	var st := _blank()
	var a := _put(st, 0, "she_wolf")
	var g := _put(st, 1, "cerberus")
	ok(st.attack_targets(0) == [g.uid], "guard is the only attack target")
	ok(not st.attack(0, a.uid, st.sides[1].hero.uid), "cannot attack face past a guard")
	ok(st.attack(0, a.uid, g.uid), "can attack the guard")
	ok(g.health == 2 and a.dead, "trade damage applied both ways")

	# Ward absorbs one hit.
	st = _blank()
	var s := _put(st, 1, "paolo")
	var p := _put(st, 0, "phlegyas")
	st.attack(0, p.uid, s.uid)
	ok(s.health == 5 and not s.has("ward"), "ward absorbed the hit and broke")

	# Venom destroys whatever it damages.
	st = _blank()
	var h := _put(st, 0, "harpy")
	var big := _put(st, 1, "geryon")
	st.attack(0, h.uid, big.uid)
	ok(not st.units.has(big.uid), "venom destroyed the target")

	# Drain heals the owner's hero.
	st = _blank()
	st.sides[1].hero.health = 20
	var m := _put(st, 1, "plutus")
	st.current = 1
	m.sleeping = false
	st.attack(1, m.uid, st.sides[0].hero.uid)
	ok(st.sides[1].hero.health == 22, "drain healed 2 (%d)" % st.sides[1].hero.health)
	st.current = 0

	# Last Breath summons in place.
	st = _blank()
	var w := _put(st, 1, "stung_neutral")
	st.sides[0].mana = 10
	var oar := _give(st, 0, "centaur_arrows")
	ok(st.play_card(0, oar, w.uid), "spell with a target plays")
	ok(st.sides[1].board.size() == 1 and st.sides[1].board[0].id == "lost_soul", "last breath summoned a maggot")

	# Targeted spell without a target is refused; battlecry without targets is allowed.
	st = _blank()
	var hit := _give(st, 0, "oar_strike")
	ok(not st.can_play(0, hit), "minion-only spell needs a minion")
	var lucan := _give(st, 0, "chiron_centaurs")
	ok(st.play_card(0, lucan), "battlecry minion plays with no target")

	# Bounce returns the minion to its owner's hand.
	st = _blank()
	var e := _put(st, 0, "francesca")
	st.current = 1
	var ref := _give(st, 1, "turned_back")
	ok(st.play_card(1, ref, e.uid), "bounce plays")
	ok(st.sides[0].board.is_empty() and st.sides[0].hand.any(func(c): return c.id == "francesca"), "homer back in hand")
	st.current = 0

	# Armor soaks damage first.
	st = _blank()
	ok(st.use_power(0), "hero power usable")
	ok(st.sides[0].hero.armor == 2, "armor gained")
	st.current = 1
	st.sides[1].power_used = false
	ok(st.use_power(1), "toll hero power")
	ok(st.sides[0].hero.armor == 0 and st.sides[0].hero.health == 30, "armor soaked the toll")

	# Board clear + summon effects.
	st = _blank()
	_put(st, 0, "lost_pilgrim")
	_put(st, 0, "geryon")
	st.current = 1
	var q := _give(st, 1, "minotaur_rampage")
	st.play_card(1, q)
	ok(st.sides[0].board.size() == 1 and st.sides[0].board[0].health == 2, "earthquake killed the 2/1, hurt hector")
	st.sides[1].mana = 10
	var thr := _give(st, 1, "souls_of_the_styx")
	st.play_card(1, thr)
	ok(st.sides[1].board.size() == 3, "throng summoned two souls")

	# Minos destroys a random enemy minion.
	st = _blank()
	_put(st, 0, "geryon")
	st.current = 1
	var mi := _give(st, 1, "minos")
	st.play_card(1, mi)
	ok(st.sides[0].board.is_empty(), "minos destroyed the only enemy")

	# Mulligan swaps cards and starts the game once both sides confirm.
	st = BattleState.new()
	var deck := CardDB.deck_list("pilgrim")
	st.start(deck, "dante", CardDB.deck_list("ferry"), "charon", 3, true)
	ok(st.in_mulligan() and st.turn == 0, "waiting for mulligan")
	var first: int = st.sides[0].hand[0].uid
	st.finish_mulligan(0, [first])
	ok(st.sides[0].hand.size() == 3 and st.hand_card(0, first).is_empty(), "card replaced")
	ok(st.turn == 0, "still waiting for the other side")
	st.finish_mulligan(1, [])
	ok(st.turn == 1 and not st.in_mulligan(), "game started")
	ok(st.sides[0].deck.size() + st.sides[0].hand.size() == 30, "no card lost in the mulligan")

	# Fatigue.
	st = _blank()
	st.sides[0].deck.clear()
	st.draw(0, 2)
	ok(st.sides[0].hero.health == 27, "fatigue 1+2 (%d)" % st.sides[0].hero.health)


func _soak(games: int) -> void:
	var wins := [0, 0, 0]
	var turns := 0
	for g in games:
		var st := BattleState.new()
		var a := CardDB.deck("pilgrim")
		var b := CardDB.deck("ferry")
		var swap := g % 2 == 1
		var d0 := a if not swap else b
		var d1 := b if not swap else a
		st.start(CardDB.deck_list(d0.id), d0.hero, CardDB.deck_list(d1.id), d1.hero, 1000 + g)
		var ais := [BattleAI.new(0), BattleAI.new(1)]
		var steps := 0
		while st.winner == -1 and steps < 5000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			var done := false
			match act.do:
				"play":
					done = st.play_card(st.current, act.uid, act.target, act.index)
				"attack":
					done = st.attack(st.current, act.attacker, act.target)
				"power":
					done = st.use_power(st.current, act.target)
			if not done:
				st.end_turn()
			for s in st.sides:
				ok(s.board.size() <= BattleState.MAX_BOARD and s.hand.size() <= BattleState.MAX_HAND
					and s.mana >= 0 and s.mana <= BattleState.MAX_MANA, "invariants")
				for u in s.board:
					ok(u.health > 0 and u.health <= u.max_health, "minion hp sane")
		ok(st.winner != -1, "game %d finished" % g)
		var w := st.winner
		if w < 2 and swap:
			w = 1 - w
		wins[w] += 1
		turns += st.turn
	print("SOAK: pilgrim %d / ferry %d / draws %d, avg turns %.1f" % [wins[0], wins[1], wins[2], float(turns) / games])


## A random legal 30-card deck: class cards + neutrals, max 2 copies (1 for legendaries).
static func random_deck(cls: String, rng: RandomNumberGenerator) -> Array[String]:
	var pool := []
	for c in CardDB.all_cards():
		if c.get("set", "") in [cls, "neutral"]:
			pool.append(c)
	var out: Array[String] = []
	while out.size() < 30:
		var c: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if out.count(c.id) < (1 if c.rarity == "legendary" else 2):
			out.append(c.id)
	return out


## Random decks from the whole card pool, so every card (and its effects) gets played many times.
func _soak_random(games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var played := {}
	var wins := [0, 0, 0]
	for g in games:
		var st := BattleState.new()
		st.start(random_deck("pilgrim", rng), "dante", random_deck("ferry", rng), "charon", 5000 + g)
		var ais := [BattleAI.new(0, BattleAI.Level.EASY), BattleAI.new(1, BattleAI.Level.EASY)]
		var steps := 0
		while st.winner == -1 and steps < 6000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			var done := false
			match act.do:
				"play":
					for c in st.sides[st.current].hand:
						if c.uid == act.uid:
							played[c.id] = true
					done = st.play_card(st.current, act.uid, act.target, act.index)
				"attack":
					done = st.attack(st.current, act.attacker, act.target)
				"power":
					done = st.use_power(st.current, act.target)
			if not done:
				st.end_turn()
			for s in st.sides:
				ok(s.board.size() <= BattleState.MAX_BOARD and s.hand.size() <= BattleState.MAX_HAND
					and s.mana >= 0 and s.mana <= BattleState.MAX_MANA, "random invariants")
				for u in s.board:
					ok(u.health > 0 and u.health <= u.max_health, "random minion hp sane (%s)" % u.id)
		ok(st.winner != -1, "random game %d finished" % g)
		wins[st.winner] += 1
	var total := 0
	for c in CardDB.all_cards():
		if c.get("set", "") != "token":
			total += 1
	print("RANDOM SOAK: pilgrim %d / ferry %d / draws %d, %d of %d cards played" % [wins[0], wins[1], wins[2],
		played.size(), total])


## Determinism: the same decks, seed and list of moves must give the same battle, event for event. This is what
## replays, bug reports and a future authoritative multiplayer server rely on.
## `cls`: play that class against each other class in turn (default: Pilgrim against Ferryman).
func _test_replay(games: int, cls: String = "") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 if cls == "" else 32
	var c0 := "pilgrim" if cls == "" else cls
	var c1 := "ferry"
	for g in games:
		if cls != "":
			c1 = CardDB.other_classes(cls)[g % CardDB.other_classes(cls).size()]
		var d0 := random_deck(c0, rng)
		var d1 := random_deck(c1, rng)
		var h0 := CardDB.class_hero(c0)
		var h1 := CardDB.class_hero(c1)
		var st := BattleState.new()
		var log_a := []
		st.event.connect(func(ev): log_a.append(ev))
		st.start(d0, h0, d1, h1, 777 + g, false, -1)
		var ais := [BattleAI.new(0), BattleAI.new(1)]
		var moves := []
		var steps := 0
		while st.winner == -1 and steps < 4000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			if act.do == "end" or not BattleAI.apply(st, st.current, act):
				act = {"do": "end"}
				st.end_turn()
			moves.append(act)
		var rp := BattleState.new()
		var log_b := []
		rp.event.connect(func(ev): log_b.append(ev))
		rp.start(d0, h0, d1, h1, 777 + g, false, -1)
		for m in moves:
			if m.do == "end":
				rp.end_turn()
			else:
				BattleAI.apply(rp, rp.current, m)
		ok(rp.winner == st.winner and log_a.size() == log_b.size(), "replay %s %d ends the same" % [cls, g])
		ok(str(log_a) == str(log_b), "replay %s %d matches event for event" % [cls, g])


## Every pair of classes with their starter decks, Hard AI, each deal from both seats: rules invariants hold and
## every game ends.
func _soak_classes(games: int) -> void:
	var cls := CardDB.classes()
	var line := "CLASS SOAK:"
	for i in cls.size():
		for j in range(i + 1, cls.size()):
			var a: Dictionary = CardDB.class_decks(cls[i])[0]
			var b: Dictionary = CardDB.class_decks(cls[j])[0]
			var wins := [0, 0, 0]
			for g in games:
				var swap := g % 2 == 1
				var d0: Dictionary = a if not swap else b
				var d1: Dictionary = b if not swap else a
				var st := BattleState.new()
				st.start(CardDB.deck_list(d0.id), d0.hero, CardDB.deck_list(d1.id), d1.hero, 2000 + g)
				_play_out(st, [BattleAI.new(0), BattleAI.new(1)], "class soak")
				var w := st.winner
				if w < 2 and swap:
					w = 1 - w
				wins[w] += 1
			line += "  %s %d / %s %d / draws %d;" % [cls[i], wins[0], cls[j], wins[1], wins[2]]
	print(line)


## Random decks for every class other than Pilgrim and Ferryman (those two have their own soak), Easy AI, against
## each other class: every card of the newer classes gets played.
func _soak_random_classes(games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var played := {}
	var line := "RANDOM CLASS SOAK:"
	for cls in CardDB.classes():
		if cls in ["pilgrim", "ferry"]:
			continue
		var wins := [0, 0, 0]
		var others := CardDB.other_classes(cls)
		for g in games:
			var other: String = others[g % others.size()]
			var swap := (g / others.size()) % 2 == 1
			var c0: String = cls if not swap else other
			var c1: String = other if not swap else cls
			var st := BattleState.new()
			st.start(random_deck(c0, rng), CardDB.class_hero(c0), random_deck(c1, rng), CardDB.class_hero(c1), 6000 + g)
			_play_out(st, [BattleAI.new(0, BattleAI.Level.EASY), BattleAI.new(1, BattleAI.Level.EASY)],
				"random class soak", played)
			var w := st.winner
			if w < 2 and swap:
				w = 1 - w
			wins[w] += 1
		var total := 0
		var seen := 0
		for c in CardDB.all_cards():
			if c.get("set", "") == cls:
				total += 1
				seen += int(played.has(c.id))
		ok(seen == total, "every %s card got played in the random soak (%d of %d)" % [cls, seen, total])
		line += "  %s %d / others %d / draws %d, %d of %d class cards played;" % [cls, wins[0], wins[1], wins[2], seen,
			total]
	print(line)


## Plays a battle to the end with the given AIs, checking the invariants after every step.
func _play_out(st: BattleState, ais: Array, what: String, played: Dictionary = {}) -> void:
	var steps := 0
	while st.winner == -1 and steps < 6000:
		steps += 1
		var act: Dictionary = ais[st.current].next_action(st)
		if act.do == "play":
			for c in st.sides[st.current].hand:
				if c.uid == act.uid:
					played[c.id] = true
		if act.do == "end" or not BattleAI.apply(st, st.current, act):
			st.end_turn()
		for s in st.sides:
			ok(s.board.size() <= BattleState.MAX_BOARD and s.hand.size() <= BattleState.MAX_HAND
				and s.mana >= 0 and s.mana <= BattleState.MAX_MANA, what + " invariants")
			for u in s.board:
				ok(u.health > 0 and u.health <= u.max_health and st.units.get(u.uid) == u, what + " minion sane (%s)" % u.id)
	ok(st.winner != -1, what + " game finished")


## Ulysses' mechanics: Ruse, copy / steal, transform, Swift from a buff, the hero power.
func _test_ulysses() -> void:
	# Ruse: nothing as the first card of the turn, the bonus once another card was played; reset next turn.
	var st := _blank()
	var s1 := _give(st, 0, "ul_ithacan_sailor")
	ok(not st.ruse_active(0), "no Ruse before any card")
	st.play_card(0, s1)
	var sailor: BattleState.Unit = st.sides[0].board[0]
	ok(sailor.attack == 2 and sailor.health == 1, "Ruse does not fire on the first card")
	ok(st.ruse_active(0), "Ruse is active after a card")
	var s2 := _give(st, 0, "ul_ithacan_sailor")
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, s2)
	ok(st.sides[0].board[1].attack == 3 and st.sides[0].board[1].health == 2, "Ruse fires on the second card")
	ok(evs.any(func(ev): return ev.t == "ruse"), "a ruse event is emitted")
	st.end_turn()
	st.end_turn()
	ok(not st.ruse_active(0) and st.sides[0].played == 0, "Ruse resets each turn")

	# The hero power copies a card of the enemy deck and does not count as a card for Ruse.
	st = _blank()
	st.sides[0].hero_id = "ulysses"
	var foe_deck := st.sides[1].deck.size()
	ok(st.use_power(0), "Ulysses' power usable")
	ok(st.sides[0].hand.size() == 1 and st.sides[0].hand[0].id == "lost_pilgrim", "the power copies an enemy deck card")
	ok(st.sides[1].deck.size() == foe_deck, "a copy leaves the enemy deck as it was")
	ok(not st.ruse_active(0), "the hero power does not enable Ruse")

	# Ruse sharing the card's chosen target: Tongue of Flame deals 1, then 2 more.
	st = _blank()
	st.play_card(0, _give(st, 0, "ul_tongue_of_flame"), st.sides[1].hero.uid)
	ok(st.sides[1].hero.health == 29, "Tongue of Flame alone deals 1")
	st.play_card(0, _give(st, 0, "ul_tongue_of_flame"), st.sides[1].hero.uid)
	ok(st.sides[1].hero.health == 26, "Tongue of Flame with Ruse deals 3 (%d)" % st.sides[1].hero.health)

	# Copy from the enemy hand: the enemy keeps the card.
	st = _blank()
	_give(st, 1, "geryon")
	st.play_card(0, _give(st, 0, "ul_puccio"))
	ok(st.sides[0].hand.size() == 1 and st.sides[0].hand[0].id == "geryon" and st.sides[1].hand.size() == 1,
		"Puccio copies the enemy's card")
	# Steal from the hand: the card changes sides.
	st = _blank()
	var stolen_uid := _give(st, 1, "geryon")
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "ul_black_cherub"))
	ok(st.sides[1].hand.is_empty() and st.sides[0].hand.size() == 1 and st.sides[0].hand[0].id == "geryon",
		"the Black Cherub steals the card")
	ok(evs.any(func(ev): return ev.t == "steal" and ev.uid == stolen_uid and ev.from == 1), "a steal event names the card")
	# Steal from the deck.
	st = _blank()
	var deck_before := st.sides[1].deck.size()
	st.play_card(0, _give(st, 0, "ul_palladium"))
	ok(st.sides[1].deck.size() == deck_before - 2 and st.sides[0].hand.size() == 2, "the Palladium steals 2 deck cards")
	# Nothing is stolen into a full hand.
	st = _blank()
	var cherub := _give(st, 0, "ul_black_cherub")
	for i in 10:
		_give(st, 0, "lost_pilgrim")
	_give(st, 1, "geryon")
	st.play_card(0, cherub)
	ok(st.sides[0].hand.size() == 10 and st.sides[1].hand.size() == 1, "no steal into a full hand")
	# Copy a minion into the hand; copy an enemy minion onto the board.
	st = _blank()
	var gy := _put(st, 1, "geryon")
	ok(st.play_card(0, _give(st, 0, "ul_forged_will"), gy.uid), "Forged Will plays on a minion")
	ok(st.sides[0].hand.size() == 1 and st.sides[0].hand[0].id == "geryon", "Forged Will copies the minion")
	gy.health = 1
	st.play_card(0, _give(st, 0, "ul_capocchio"), gy.uid)
	ok(st.sides[0].board.size() == 2 and st.sides[0].board[1].id == "geryon" and st.sides[0].board[1].health == 5,
		"Capocchio summons a fresh copy next to him")

	# Transform: same place, no Last Breath, Ward does not stop it, printed stats of the new card.
	st = _blank()
	_put(st, 1, "lost_pilgrim")
	var w := _put(st, 1, "stung_neutral")
	w.keywords["ward"] = true
	w.attack = 9
	_put(st, 1, "lost_pilgrim")
	ok(st.play_card(0, _give(st, 0, "ul_circes_draught"), w.uid), "Circe's Draught plays")
	ok(st.sides[1].board.size() == 3 and st.sides[1].board[1].id == "ul_swine" and st.sides[1].board[1].attack == 1
		and not st.units.has(w.uid), "transformed in place into a 1/1")
	ok(not st.sides[1].board.any(func(u): return u.id == "lost_soul"), "no Last Breath on a transform")
	st.sides[0].mana = 10
	st.play_card(0, _give(st, 0, "ul_circe"))
	ok(st.sides[1].board.size() == 3 and st.sides[1].board.all(func(u): return u.id == "ul_swine"), "Circe turns all enemies")
	ok(st.sides[0].board.size() == 1 and st.sides[0].board[0].id == "ul_circe", "Circe spares her own side")

	# Gaining Swift wakes a minion played this turn (Griffolino with Ruse).
	st = _blank()
	st.play_card(0, _give(st, 0, "ul_ithacan_sailor"))
	st.play_card(0, _give(st, 0, "ul_griffolino"))
	var gr: BattleState.Unit = st.sides[0].board[1]
	ok(gr.has("swift") and st.can_attack(gr), "Swift from Ruse lets it attack at once")

	# Bounce and replay: Turn the Prow returns a friendly minion; the Distant Mountain returns every other minion.
	st = _blank()
	var pz := _put(st, 0, "ul_puccio")
	st.play_card(0, _give(st, 0, "ul_turn_the_prow"), pz.uid)
	ok(st.sides[0].board.is_empty() and st.sides[0].hand.any(func(c): return c.id == "ul_puccio"), "Turn the Prow")
	_put(st, 0, "geryon")
	_put(st, 1, "cerberus")
	_put(st, 1, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "ul_distant_mountain"))
	ok(st.sides[0].board.size() == 1 and st.sides[1].board.is_empty() and st.sides[1].hand.size() == 2,
		"the Distant Mountain returns every other minion")

	# Diomedes with Ruse summons a copy of himself; the copy does not repeat the Ruse (no loop).
	st = _blank()
	st.play_card(0, _give(st, 0, "ul_ithacan_sailor"))
	st.play_card(0, _give(st, 0, "ul_diomedes"))
	ok(st.sides[0].board.size() == 3 and st.sides[0].board[2].id == "ul_diomedes", "Diomedes doubles with Ruse")

	# Every Ulysses card resolves cleanly with and without Ruse.
	for c in CardDB.all_cards():
		if c.get("set", "") != "ulysses":
			continue
		for pre in 2:
			st = _blank()
			_put(st, 1, "geryon")
			_put(st, 1, "lost_pilgrim")
			_put(st, 0, "ul_puccio")
			_give(st, 1, "cerberus")
			if pre == 1:
				st.play_card(0, _give(st, 0, "obol_coin"))
			var uid := _give(st, 0, c.id)
			var tt := BattleState.target_type(c)
			var targets := st.valid_targets(0, tt) if tt != "" else ([] as Array[int])
			ok(st.play_card(0, uid, targets[0] if not targets.is_empty() else -1), "%s plays (ruse %d)" % [c.id, pre])
			for s in st.sides:
				ok(s.hand.size() <= BattleState.MAX_HAND and s.board.size() <= BattleState.MAX_BOARD, "%s keeps limits" % c.id)
