extends SceneTree
## Headless rules tests + AI-vs-AI soak.
##   Godot --headless --path . -s res://tests/run_tests.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_data()
	_test_rules()
	_soak(300)
	print("TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


func _test_data() -> void:
	for d in CardDB.decks():
		var list := CardDB.deck_list(d.id)
		ok(list.size() == 20, "deck %s has 20 cards (%d)" % [d.id, list.size()])
		ok(not CardDB.hero(d.hero).is_empty(), "deck %s hero exists" % d.id)
		for id in list:
			ok(not CardDB.card(id).is_empty(), "card %s exists" % id)
	for c in CardDB.all_cards():
		for e in c.get("effects", []):
			ok(e.do in ["damage", "heal", "draw", "buff", "summon", "bounce", "armor", "destroy"], "%s effect %s" % [c.id, e.do])
			if e.do == "summon":
				ok(not CardDB.card(e.card).is_empty(), "%s summons a known card" % c.id)
		for k in c.get("keywords", []):
			ok(k in ["guard", "swift", "ward", "drain", "venom"], "%s keyword %s" % [c.id, k])
	ok(CardDB.arenas().size() >= 1, "at least one arena")


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
	var a := _put(st, 0, "eager_soul")
	var g := _put(st, 1, "gatekeeper_demon")
	ok(st.attack_targets(0) == [g.uid], "guard is the only attack target")
	ok(not st.attack(0, a.uid, st.sides[1].hero.uid), "cannot attack face past a guard")
	ok(st.attack(0, a.uid, g.uid), "can attack the guard")
	ok(g.health == 2 and a.dead, "trade damage applied both ways")

	# Ward absorbs one hit.
	st = _blank()
	var s := _put(st, 1, "saladin")
	var p := _put(st, 0, "aeneas")
	st.attack(0, p.uid, s.uid)
	ok(s.health == 5 and not s.has("ward"), "ward absorbed the hit and broke")

	# Venom destroys whatever it damages.
	st = _blank()
	var h := _put(st, 0, "hornet")
	var big := _put(st, 1, "hector")
	st.attack(0, h.uid, big.uid)
	ok(not st.units.has(big.uid), "venom destroyed the target")

	# Drain heals the owner's hero.
	st = _blank()
	st.sides[1].hero.health = 20
	var m := _put(st, 1, "mud_drinker")
	st.current = 1
	m.sleeping = false
	st.attack(1, m.uid, st.sides[0].hero.uid)
	ok(st.sides[1].hero.health == 22, "drain healed 2 (%d)" % st.sides[1].hero.health)
	st.current = 0

	# Last Breath summons in place.
	st = _blank()
	var w := _put(st, 1, "worm_fed_shade")
	st.sides[0].mana = 10
	var oar := _give(st, 0, "light_of_reason")
	ok(st.play_card(0, oar, w.uid), "spell with a target plays")
	ok(st.sides[1].board.size() == 1 and st.sides[1].board[0].id == "maggot", "last breath summoned a maggot")

	# Targeted spell without a target is refused; battlecry without targets is allowed.
	st = _blank()
	var hit := _give(st, 0, "oar_strike")
	ok(not st.can_play(0, hit), "minion-only spell needs a minion")
	var lucan := _give(st, 0, "lucan")
	ok(st.play_card(0, lucan), "battlecry minion plays with no target")

	# Bounce returns the minion to its owner's hand.
	st = _blank()
	var e := _put(st, 0, "homer")
	st.current = 1
	var ref := _give(st, 1, "great_refusal")
	ok(st.play_card(1, ref, e.uid), "bounce plays")
	ok(st.sides[0].board.is_empty() and st.sides[0].hand.any(func(c): return c.id == "homer"), "homer back in hand")
	st.current = 0

	# Armor soaks damage first.
	st = _blank()
	ok(st.use_power(0), "hero power usable")
	ok(st.sides[0].hero.armor == 2, "armor gained")
	st.current = 1
	st.sides[1].power_used = false
	ok(st.use_power(1), "toll hero power")
	ok(st.sides[0].hero.armor == 1 and st.sides[0].hero.health == 30, "armor soaked the toll")

	# Board clear + summon effects.
	st = _blank()
	_put(st, 0, "lost_pilgrim")
	_put(st, 0, "hector")
	st.current = 1
	var q := _give(st, 1, "earthquake")
	st.play_card(1, q)
	ok(st.sides[0].board.size() == 1 and st.sides[0].board[0].health == 2, "earthquake killed the 2/1, hurt hector")
	st.sides[1].mana = 10
	var thr := _give(st, 1, "shoreline_throng")
	st.play_card(1, thr)
	ok(st.sides[1].board.size() == 3, "throng summoned two souls")

	# Minos destroys a random enemy minion.
	st = _blank()
	_put(st, 0, "hector")
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
	ok(st.sides[0].deck.size() + st.sides[0].hand.size() == 20, "no card lost in the mulligan")

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
