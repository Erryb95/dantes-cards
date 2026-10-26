extends SceneTree
## Headless rules tests + AI-vs-AI soak.
##   Godot --headless --path . -s res://tests/run_tests.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_data()
	_test_rules()
	_soak(120)
	_soak_random(400)
	_test_replay(20)
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
		ok(cls in ["pilgrim", "ferry"], "deck %s class %s" % [d.id, cls])
		ok(list.size() == 30, "deck %s has 30 cards (%d)" % [d.id, list.size()])
		ok(not CardDB.hero(d.hero).is_empty(), "deck %s hero exists" % d.id)
		ok(d.hero == {"pilgrim": "dante", "ferry": "charon"}.get(cls, ""), "deck %s hero matches its class" % d.id)
		ok(str(d.get("name", "")) != "" and str(d.get("text", "")) != "", "deck %s has a name and a plan" % d.id)
		ok(d.get("featured", []).size() == 3, "deck %s features 3 cards" % d.id)
		for id in d.get("featured", []):
			ok(id in list, "deck %s features its own card %s" % [d.id, id])
		for id in list:
			ok(not CardDB.card(id).is_empty(), "card %s exists" % id)
			ok(list.count(id) <= (1 if CardDB.card(id).get("rarity") == "legendary" else 2), "deck %s copies of %s" % [d.id, id])
			ok(CardDB.card(id).get("set") in [cls, "neutral"], "deck %s class of %s" % [d.id, id])
	for cls in ["pilgrim", "ferry"]:
		ok(not CardDB.class_decks(cls).is_empty() and CardDB.class_decks(cls)[0].get("starter", false),
			"the first %s deck is the starter" % cls)
	for c in CardDB.all_cards():
		for e in c.get("effects", []):
			ok(e.do in ["damage", "heal", "draw", "buff", "summon", "bounce", "armor", "destroy", "freeze", "silence", "ramp", "give_card", "mana"], "%s effect %s" % [c.id, e.do])
			if e.do in ["summon", "give_card"]:
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
func _test_replay(games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for g in games:
		var d0 := random_deck("pilgrim", rng)
		var d1 := random_deck("ferry", rng)
		var st := BattleState.new()
		var log_a := []
		st.event.connect(func(ev): log_a.append(ev))
		st.start(d0, "dante", d1, "charon", 777 + g, false, -1)
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
		rp.start(d0, "dante", d1, "charon", 777 + g, false, -1)
		for m in moves:
			if m.do == "end":
				rp.end_turn()
			else:
				BattleAI.apply(rp, rp.current, m)
		ok(rp.winner == st.winner and log_a.size() == log_b.size(), "replay %d ends the same" % g)
		ok(str(log_a) == str(log_b), "replay %d matches event for event" % g)
