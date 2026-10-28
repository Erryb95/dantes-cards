extends SceneTree
## Headless rules tests + AI-vs-AI soak.
##   Godot --headless --path . -s res://tests/run_tests.gd
## `-- --only=lessons` runs just the lesson checks (quick, while writing lessons).

const SaveFileScript := preload("res://scripts/core/save_file.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	if "--only=lessons" in OS.get_cmdline_user_args():
		_test_lessons()
		print("TESTS: %d checks, %d failures" % [checks, failures])
		quit(1 if failures > 0 else 0)
		return
	if "--only=online" in OS.get_cmdline_user_args():
		_test_online_mirror(12)
		print("TESTS: %d checks, %d failures" % [checks, failures])
		quit(1 if failures > 0 else 0)
		return
	_test_data()
	_test_export_presets()
	_test_class_info()
	_test_rules()
	_test_freeze()
	_test_silence_ai()
	_test_first_match()
	_test_ulysses()
	_test_wrath()
	_test_limits()
	_test_transform_edges()
	_test_ruse_edges()
	_test_death_order()
	_test_game_end()
	_test_damage_edges()
	_test_copy_state()
	_test_rebirth()
	_test_killers()
	_test_variety()
	_test_ai_edges()
	_test_easy_guard()
	_test_saves()
	_test_lessons()
	_test_drop_rates()
	_soak(120)
	_soak_classes(24)
	_soak_random(400)
	_soak_random_classes(120)
	_test_replay(20)
	_test_replay(8, "ulysses")
	_test_replay(8, "wrath")
	_test_online_mirror(24)
	print("DEATHS: %d in soaks, replays and duels, %d with no killer" % [_deaths[0], _deaths[1]])
	print("TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


## The exports ship what online play needs: the server config, and on Android the network permissions (without
## INTERNET the phone refuses every connection: no duel, no Google sign-in, no cloud save).
func _test_export_presets() -> void:
	var cf := ConfigFile.new()
	ok(cf.load("res://export_presets.cfg") == OK, "export_presets.cfg loads")
	var android := 0
	for sec in cf.get_sections():
		if not sec.ends_with(".options") and cf.has_section_key(sec, "platform"):
			var opts := sec + ".options"
			ok(str(cf.get_value(sec, "include_filter", "")).contains("config/*.cfg"),
				"export preset %s ships config/*.cfg" % cf.get_value(sec, "name"))
			if str(cf.get_value(sec, "platform")) == "Android":
				android += 1
				ok(cf.get_value(opts, "permissions/internet", false) == true, "the Android export asks for INTERNET")
				ok(cf.get_value(opts, "permissions/access_network_state", false) == true,
					"the Android export asks for ACCESS_NETWORK_STATE")
	ok(android > 0, "there is an Android export preset")


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
			ok(e.do in ["damage", "heal", "draw", "buff", "summon", "bounce", "armor", "destroy", "freeze", "silence", "ramp", "give_card", "mana", "copy", "transform", "fight"], "%s effect %s" % [c.id, e.do])
			if e.do in ["summon", "give_card", "transform"]:
				ok(not CardDB.card(e.card).is_empty(), "%s summons a known card" % c.id)
		for k in c.get("keywords", []):
			ok(k in ["guard", "swift", "ward", "drain", "venom", "rebirth"], "%s keyword %s" % [c.id, k])
	ok(CardDB.arenas().size() >= 1, "at least one arena")
	_test_arenas()
	_test_vfx()
	_test_living_art()


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


## Living art (data/living_art.json, ArtLiving): every entry names a card with its painting and mask, the config loads
## into the card shader's uniforms, and a card without an entry is left exactly as it was.
func _test_living_art() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/living_art.json"))
	ok(d is Dictionary and d.get("cards") is Dictionary, "living_art.json parses")
	var cards: Dictionary = d.get("cards", {}) if d is Dictionary else {}
	for id in cards:
		ok(not CardDB.card(id).is_empty(), "living art %s names a card" % id)
		ok(ArtLiving.has(id), "living art %s has its painting and mask" % id)
		for key in cards[id]:
			ok(key == "mask" or ArtLiving.PARAMS.has(key), "living art %s: known key %s" % [id, key])
	ok(cards.has("francesca") and not CardDB.living("francesca").is_empty(), "francesca has living art")
	var u := ArtLiving.params(CardDB.living("francesca"))
	ok(u.size() == ArtLiving.PARAMS.size(), "living params: one uniform per key")
	ok(u.living_swirl > 0.0 and u.living_vortex is Vector2 and u.living_ember_color is Color, "living params typed")
	ok(ArtLiving.params({}).living_swirl == 0.0, "living params: defaults for missing keys")
	ok(CardDB.art_loop("francesca") == null, "a card with living art never plays its Wan loop")
	var shader: Shader = load("res://assets/shaders/card_fx.gdshader")
	var keep := ArtLiving.forced
	ArtLiving.forced = ArtLiving.FULL
	var m := ShaderMaterial.new()
	m.shader = shader
	ok(ArtLiving.setup_card(m, "francesca", 0.686, 0.42), "francesca's living art sets up")
	ok(m.get_shader_parameter("living_level") == ArtLiving.FULL and m.get_shader_parameter("living_mask") != null,
		"francesca's material is alive")
	for id in ["ugolino", "minos", "cd_guy_montfort"]:
		var plain := ShaderMaterial.new()
		plain.shader = shader
		ok(CardDB.living(id).is_empty() and not ArtLiving.setup_card(plain, id, 0.686, 0.42), "%s has no living art" % id)
		ok(plain.get_shader_parameter("living_level") in [null, 0] and plain.get_shader_parameter("living_mask") == null,
			"%s's material is untouched" % id)
	ArtLiving.forced = ArtLiving.OFF
	var off := ShaderMaterial.new()
	off.shader = shader
	ok(not ArtLiving.setup_card(off, "francesca", 0.686, 0.42) and off.get_shader_parameter("living_level") in [null, 0],
		"living art switched off keeps the still painting")
	ArtLiving.forced = keep


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


## Freeze costs a minion one attack: it thaws at the end of its owner's turn only once the freeze has taken an attack
## from it (awake, attack unused); frozen after attacking or while asleep, it stays frozen through its next turn.
func _test_freeze() -> void:
	# Frozen on the enemy's turn: no attack on the owner's next turn, thawed at its end.
	var st := _blank()
	var m := _put(st, 0, "she_wolf")
	st.end_turn()
	var chill := _give(st, 1, "uh_bitter_chill")
	ok(st.play_card(1, chill, m.uid) and m.frozen, "Bitter Chill freezes")
	st.end_turn()
	ok(m.frozen and not st.can_attack(m), "frozen minion cannot attack on its owner's next turn")
	st.end_turn()
	ok(not m.frozen, "it thaws at the end of the turn it lost")

	# Ruggieri's Last Breath on the attacker's own turn (the QA case): the freeze must last through the next turn.
	st = _blank()
	var att := _put(st, 0, "geryon")
	var idle := _put(st, 0, "she_wolf")
	var fresh := st._summon(0, "lost_pilgrim") # played this turn: still asleep
	var r := _put(st, 1, "mc_ruggieri")
	r.health = 1
	r.attack = 0
	ok(st.attack(0, att.uid, r.uid) and r.dead, "Ruggieri dies to the attack")
	ok(att.frozen and idle.frozen and fresh.frozen, "Ruggieri's Last Breath freezes every enemy minion")
	ok(not st.can_attack(idle), "a minion frozen before it attacked loses this turn's attack")
	st.end_turn()
	ok(att.frozen, "frozen after attacking: still frozen after its owner's turn ends")
	ok(fresh.frozen, "frozen while asleep: still frozen after its owner's turn ends")
	ok(not idle.frozen, "frozen before attacking: thaws at the end of that turn (the freeze cost it the attack)")
	st.end_turn()
	ok(att.frozen and not st.can_attack(att), "the attacker misses its next turn")
	ok(fresh.frozen and not st.can_attack(fresh), "the sleeper misses its first awake turn")
	ok(st.can_attack(idle), "the thawed minion attacks again")
	st.end_turn()
	ok(not att.frozen and not fresh.frozen, "both thaw at the end of the turn they lost")

	# Cassius killed by a spell after the minion attacked: the same.
	st = _blank()
	var w := _put(st, 0, "she_wolf")
	var cassius := _put(st, 1, "mc_cassius")
	cassius.health = 1
	ok(st.attack(0, w.uid, st.sides[1].hero.uid), "she-wolf attacks the hero")
	var strike := _give(st, 0, "oar_strike")
	ok(st.play_card(0, strike, cassius.uid) and w.frozen, "Cassius' Last Breath freezes the she-wolf")
	st.end_turn()
	st.end_turn()
	ok(w.frozen and not st.can_attack(w), "Cassius' freeze holds through the she-wolf's next turn")
	st.end_turn()
	ok(not w.frozen, "and thaws after it")

	# The search AI's copies keep the state the rule needs (sleeping, attacks made).
	st = _blank()
	var c := _put(st, 0, "she_wolf")
	c.frozen = true
	c.attacks_made = 1
	var cl := st.clone(5)
	cl.end_turn()
	ok(cl.units[c.uid].frozen, "a clone keeps a freeze set after the attack")


## Silence keeps stat changes and does not thaw, so the AI does not count buffs as something Silence removes.
func _test_silence_ai() -> void:
	var st := _blank()
	var u := _put(st, 1, "she_wolf")
	var ai := BattleAI.new(0)
	var before: float = ai._silence_value(u)
	u.attack += 5
	u.health += 5
	u.max_health += 5
	ok(is_equal_approx(ai._silence_value(u), before), "the AI's Silence value ignores buffs")
	u.frozen = true
	st._resolve({"do": "silence", "target": "choose_enemy_minion"}, 0, null, u.uid, "test")
	ok(u.silenced and u.attack == 8 and u.max_health == 7 and u.frozen, "Silence keeps buffs and the freeze")


## The first match follows the intro ("At the river Acheron, Charon is waiting."): on a fresh profile the arena is
## the Acheron and the opponent Charon's starter deck.
func _test_first_match() -> void:
	var g: Node = root.get_node_or_null("Game")
	ok(g != null, "Game autoload present")
	if g == null:
		return
	var saved: Dictionary = g.stats.duplicate()
	var saved_last: String = g.last_arena
	var saved_enemy: String = g.enemy_deck_id
	var foe_cls := CardDB.hero_class("charon")
	var starter: String = CardDB.class_decks(foe_cls)[0].id
	g.stats = {"wins": 0, "losses": 0}
	g.last_arena = "acheron" # even right after an Acheron match
	g.enemy_deck_id = starter # and right after facing the starter
	ok(g.first_match(), "a fresh profile is the first match")
	for i in 5:
		ok(g.pick_arena() == "acheron", "the first match is at the Acheron")
	for cls in CardDB.other_classes(foe_cls):
		ok(g.pick_enemy_class(cls) == foe_cls, "the first opponent of a %s is Charon's class" % cls)
	ok(g.pick_enemy_class(foe_cls) != foe_cls, "a Charon player still faces another class")
	ok(g.pick_enemy_deck(foe_cls) == starter and CardDB.deck(starter).hero == "charon",
		"the first opponent plays Charon's starter")
	g.stats = {"wins": 0, "losses": 1}
	ok(not g.first_match(), "one finished match ends the first-match rule")
	var ready := CardDB.arenas().filter(func(a): return CardDB.arena_ready(a.id))
	if ready.size() > 1:
		ok(g.pick_arena() != "acheron", "later matches draw another arena")
	g.stats = saved
	g.last_arena = saved_last
	g.enemy_deck_id = saved_enemy
	g.arena_picked = false


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
		_watch_deaths(st, "soak")
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
		_watch_deaths(st, "random soak")
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
		for ev in log_a:
			_check_death(ev, "replay %s %d" % [cls, g])
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
	_watch_deaths(st, what)
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
				ok(_wrath_sane(u), what + " Wrath matches the damage (%s)" % u.id)
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

	# The hero power (Searing Word) hits minions only and does not count as a card for Ruse.
	st = _blank()
	st.sides[0].hero_id = "ulysses"
	ok(not st.can_use_power(0), "Searing Word needs a minion to hit")
	var pm := _put(st, 1, "geryon")
	ok(not st.use_power(0, st.sides[1].hero.uid), "Searing Word cannot hit a hero")
	ok(st.use_power(0, pm.uid) and pm.health == 4, "Searing Word deals 1 to a minion")
	ok(not st.ruse_active(0), "the hero power does not enable Ruse")
	# Copying from the enemy deck leaves it as it was.
	st = _blank()
	var foe_deck := st.sides[1].deck.size()
	st.play_card(0, _give(st, 0, "ul_spoils_of_troy"))
	ok(st.sides[0].hand.size() == 2 and st.sides[0].hand.all(func(c): return c.id == "lost_pilgrim"), "Spoils of Troy copies 2")
	ok(st.sides[1].deck.size() == foe_deck, "a copy leaves the enemy deck as it was")

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
	ok(st.sides[0].board.size() == 2 and st.sides[0].board[1].id == "geryon" and st.sides[0].board[1].health == 1
		and st.sides[0].board[1].max_health == 5, "Capocchio summons a copy as it is now (damaged) next to him")

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


## Hand and board limits: an overdraw and a card made for a full hand burn (and the view is told), nothing is stolen
## without room for it, the last card of a deck can be stolen, "2 random cards" are two different cards, and summons,
## copies and Last Breaths stop at 7 minions.
func _test_limits() -> void:
	# Overdraw: the card leaves the deck and burns.
	var st := _blank()
	for i in 10:
		_give(st, 0, "lost_pilgrim")
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	var deck0 := st.sides[0].deck.size()
	st.draw(0, 1)
	ok(st.sides[0].hand.size() == 10 and st.sides[0].deck.size() == deck0 - 1, "overdraw: the card leaves the deck")
	ok(evs.any(func(ev): return ev.t == "burn" and ev.side == 0 and not ev.get("made", false)), "overdraw shows a burn")

	# An added card for a full hand burns: Orpheus adds two Shades with one free slot.
	st = _blank()
	var orpheus := _give(st, 0, "uh_orpheus")
	for i in 9:
		_give(st, 0, "lost_pilgrim")
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	ok(st.play_card(0, orpheus), "Orpheus plays from a full hand")
	ok(st.sides[0].hand.size() == 10 and st.sides[0].hand.filter(func(c): return c.id == "uh_limbo_shade").size() == 1,
		"one Shade fits in the hand")
	ok(evs.filter(func(ev): return ev.t == "burn" and ev.get("made", false) and ev.id == "uh_limbo_shade").size() == 1,
		"the other Shade is shown burning")

	# A copy for a full hand burns too (Envoy to Troy copies two different cards, one slot left).
	st = _blank()
	_give(st, 1, "geryon")
	_give(st, 1, "cerberus")
	var envoy := _give(st, 0, "ul_envoy_to_troy")
	for i in 9:
		_give(st, 0, "lost_pilgrim")
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, envoy)
	var got: Array = st.sides[0].hand.filter(func(c): return c.id in ["geryon", "cerberus"]).map(func(c): return c.id)
	var burnt: Array = evs.filter(func(ev): return ev.t == "burn" and ev.get("made", false)).map(func(ev): return ev.id)
	ok(st.sides[0].hand.size() == 10 and got.size() == 1 and burnt.size() == 1 and got[0] != burnt[0],
		"Envoy: one copy kept, the other burns (%s / %s)" % [got, burnt])
	ok(st.sides[1].hand.size() == 2, "copies leave the enemy hand as it was")

	# "2 random cards" are two different cards: one card in the enemy hand gives one copy, not two.
	st = _blank()
	_give(st, 1, "geryon")
	st.play_card(0, _give(st, 0, "ul_envoy_to_troy"))
	ok(st.sides[0].hand.size() == 1, "Envoy copies the only enemy card once (%d)" % st.sides[0].hand.size())
	st = _blank()
	st.sides[1].deck.assign(["geryon", "cerberus"])
	st.play_card(0, _give(st, 0, "ul_spoils_of_troy"))
	var ids: Array = st.sides[0].hand.map(func(c): return c.id)
	ids.sort()
	ok(ids == ["cerberus", "geryon"], "Spoils of Troy copies two different deck cards (%s)" % [ids])

	# Steal with room for one card: only one leaves the enemy deck, nothing burns.
	st = _blank()
	var pal := _give(st, 0, "ul_palladium")
	for i in 9:
		_give(st, 0, "lost_pilgrim")
	var foe_deck := st.sides[1].deck.size()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, pal)
	ok(st.sides[0].hand.size() == 10 and st.sides[1].deck.size() == foe_deck - 1, "the Palladium steals only what fits")
	ok(not evs.any(func(ev): return ev.t == "burn"), "a stolen card never burns")

	# Steal the last card of the enemy deck: the deck is empty and the enemy's next draw is fatigue.
	st = _blank()
	st.sides[1].deck.assign(["geryon"])
	st.play_card(0, _give(st, 0, "ul_palladium"))
	ok(st.sides[1].deck.is_empty() and st.sides[0].hand.size() == 1 and st.sides[0].hand[0].id == "geryon",
		"the last deck card is stolen")
	st.end_turn()
	ok(st.sides[1].hero.health == 29 and st.sides[1].fatigue == 1, "the robbed side takes fatigue on its next draw")

	# Full board: summons and copies stop at 7, without errors.
	st = _blank()
	for i in 7:
		_put(st, 0, "lost_pilgrim")
	ok(st.play_card(0, _give(st, 0, "harpies_flock")) and st.sides[0].board.size() == 7, "a summon spell on a full board")
	ok(not st.can_play(0, _give(st, 0, "geryon")), "no minion fits on a full board")
	st = _blank()
	for i in 6:
		_put(st, 0, "lost_pilgrim")
	_put(st, 1, "geryon")
	st.play_card(0, _give(st, 0, "ul_capocchio"), st.sides[1].board[0].uid)
	ok(st.sides[0].board.size() == 7 and not st.sides[0].board.any(func(u): return u.id == "geryon"),
		"Capocchio takes the last slot: no copy")
	st = _blank()
	for i in 5:
		_put(st, 0, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "ul_night_raid"))
	ok(st.sides[0].board.size() == 7, "Night Raid fills the board")
	st.play_card(0, _give(st, 0, "ul_night_raid"))
	ok(st.sides[0].board.size() == 7, "a second Night Raid on a full board summons nothing")
	st = _blank()
	for i in 5:
		_put(st, 0, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "obol_coin"))
	st.play_card(0, _give(st, 0, "ul_diomedes"))
	ok(st.sides[0].board.size() == 7 and st.sides[0].board[6].id == "ul_diomedes", "Diomedes' copy takes the 7th slot")
	# Last Breath summons on a full board: the Trojan Horse dies and only one Raider fits, in its place.
	st = _blank()
	for i in 3:
		_put(st, 1, "lost_pilgrim")
	var horse := _put(st, 1, "ul_trojan_horse")
	for i in 3:
		_put(st, 1, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "cd_furys_lash"), horse.uid)
	ok(st.sides[1].board.size() == 7 and st.sides[1].board[3].id == "ul_achaean_raider"
		and st.sides[1].board.filter(func(u): return u.id == "ul_achaean_raider").size() == 1,
		"the Horse's Raiders stop at 7 minions, in its place")
	# Circe on a full enemy board: seven Swine in the same places.
	st = _blank()
	for i in 7:
		_put(st, 1, "geryon" if i % 2 == 0 else "harpy")
	st.play_card(0, _give(st, 0, "ul_circe"))
	ok(st.sides[1].board.size() == 7 and st.sides[1].board.all(func(u): return u.id == "ul_swine"),
		"Circe transforms a full board")


## Transform makes a fresh minion: buffs, Freeze, Silence and keywords are gone; Silence then works on the new form.
func _test_transform_edges() -> void:
	for id in ["cerberus", "paolo", "harpy", "ih_whip_demon", "she_wolf"]:
		for what in ["plain", "buffed", "frozen", "silenced"]:
			var st := _blank()
			var u := _put(st, 1, id)
			match what:
				"buffed":
					u.attack += 3
					u.health += 3
					u.max_health += 3
				"frozen":
					u.frozen = true
				"silenced":
					st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, u.uid, "test")
			ok(st.play_card(0, _give(st, 0, "ul_circes_draught"), u.uid), "Circe's Draught on a %s %s" % [what, id])
			var s: BattleState.Unit = st.sides[1].board[0] if st.sides[1].board.size() == 1 else null
			ok(s != null and s.id == "ul_swine" and s.attack == 1 and s.health == 1 and s.max_health == 1
				and s.keywords.is_empty() and not s.frozen and not s.silenced and not st.units.has(u.uid),
				"a %s %s becomes a plain 1/1 Swine" % [what, id])
			if s == null:
				continue
			st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, s.uid, "test")
			ok(s.silenced and s.attack == 1 and s.health == 1, "the Swine can be silenced")
	# Rebirth does not bring back a transformed minion (it did not die).
	var st2 := _blank()
	var whip := _put(st2, 1, "ih_whip_demon")
	st2.play_card(0, _give(st2, 0, "ul_circes_draught"), whip.uid)
	st2.play_card(0, _give(st2, 0, "cd_burning_sand"), st2.sides[1].board[0].uid)
	ok(st2.sides[1].board.is_empty(), "the Swine of a Rebirth minion dies for good")
	# A friendly minion turned into a Swine cannot attack this turn.
	st2 = _blank()
	var mine := _put(st2, 0, "she_wolf")
	st2.play_card(0, _give(st2, 0, "ul_circes_draught"), mine.uid)
	ok(st2.sides[0].board[0].id == "ul_swine" and not st2.can_attack(st2.sides[0].board[0]), "a new Swine is asleep")


## Ruse counts cards, whatever they cost: a 0-mana card sets it up, the hero power does not (Ruse: "after another card").
func _test_ruse_edges() -> void:
	var st := _blank()
	var mate := _put(st, 0, "lost_pilgrim")
	ok(st.play_card(0, _give(st, 0, "ul_turn_the_prow"), mate.uid) and st.ruse_active(0), "a 0-mana card sets up Ruse")
	st.play_card(0, _give(st, 0, "ul_oarsmen"))
	ok(st.sides[0].board[0].attack == 4 and st.sides[0].board[0].health == 3, "Oarsmen get their Ruse after it")
	st = _blank()
	st.sides[0].hero_id = "ulysses"
	var target := _put(st, 1, "geryon")
	ok(st.use_power(0, target.uid) and not st.ruse_active(0), "the hero power is not a card")
	st.play_card(0, _give(st, 0, "ul_oarsmen"))
	ok(st.sides[0].board[0].attack == 3 and st.sides[0].board[0].health == 2, "no Ruse after the hero power alone")


## Index of the first event that `f` accepts (-1 when none).
static func _event_at(evs: Array, f: Callable) -> int:
	for i in evs.size():
		if f.call(evs[i]):
			return i
	return -1


## Minions that die together leave in one go (the side whose turn it is first, each side in board order), then their
## Last Breaths resolve in that same order.
func _test_death_order() -> void:
	var st := _blank()
	st.sides[1].hero.health = 20
	var a := _put(st, 0, "uh_shore_soul") # Last Breath: draw a card
	var b := _put(st, 0, "ih_barbed_imp") # Last Breath: 1 damage to the enemy hero
	var c := _put(st, 1, "pj_trembling_pilgrim") # Last Breath: summon a Lost Shade
	var d := _put(st, 1, "pj_swoon_of_pity") # Last Breath: restore 2 Health to its hero
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "minotaur_rampage"))
	var deaths: Array = evs.filter(func(ev): return ev.t == "death").map(func(ev): return ev.uid)
	ok(deaths == [a.uid, b.uid, c.uid, d.uid], "deaths in order: current side first, board order (%s)" % [deaths])
	var last_death := _event_at(evs, func(ev): return ev.t == "death" and ev.uid == d.uid)
	var hero1: int = st.sides[1].hero.uid
	var i_draw := _event_at(evs, func(ev): return ev.t == "draw" and ev.side == 0)
	var i_hit := _event_at(evs, func(ev): return ev.t == "damage" and ev.uid == hero1)
	var i_shade := _event_at(evs, func(ev): return ev.t == "summon" and ev.unit.id == "pj_lost_shade")
	var i_heal := _event_at(evs, func(ev): return ev.t == "heal" and ev.uid == hero1)
	ok(last_death < i_draw and i_draw < i_hit and i_hit < i_shade and i_shade < i_heal,
		"Last Breaths resolve after all the deaths, in the same order (%d %d %d %d %d)" % [last_death, i_draw, i_hit,
		i_shade, i_heal])
	ok(st.sides[1].hero.health == 21 and st.sides[1].board.size() == 1, "every Last Breath resolved")


## How a game ends: both heroes at 0 together is a draw; nothing happens after "game_over" (fatigue at the start of a
## turn skips the Start of Turn effects; a lethal effect stops the rest of the card).
func _test_game_end() -> void:
	# Simultaneous hero death: Barbed Imp and Filippo Argenti die to the same Rampage and their Last Breaths kill both.
	var st := _blank()
	st.sides[0].hero.health = 2
	st.sides[1].hero.health = 1
	_put(st, 0, "ih_barbed_imp")
	var fil := _put(st, 1, "uh_filippo_argenti")
	fil.health = 3
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "minotaur_rampage"))
	ok(st.winner == 2, "both heroes die at once: a draw (%d)" % st.winner)
	ok(evs.filter(func(ev): return ev.t == "game_over").size() == 1 and evs.back().t == "game_over",
		"one game_over, the last event")

	# Fatigue kills at the start of a turn: the Start of Turn effects do not fire after the game ended.
	st = _blank()
	st.sides[1].deck.clear()
	st.sides[1].hero.health = 1
	_put(st, 1, "mc_tiresias") # Start of Turn: draw a card (more fatigue)
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.end_turn()
	ok(st.winner == 0 and evs.back().t == "game_over", "fatigue ends the game; nothing follows game_over")
	ok(not evs.any(func(ev): return ev.t == "trigger"), "no Start of Turn trigger after the game ended")

	# A lethal first effect stops the card: the Two-Horned Flame's Ruse does not hit a dead hero.
	st = _blank()
	st.sides[1].hero.health = 3
	st.play_card(0, _give(st, 0, "obol_coin"))
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "ul_two_horned_flame"), st.sides[1].hero.uid)
	ok(st.winner == 0 and st.sides[1].hero.health == 0 and evs.back().t == "game_over",
		"a card stops resolving once the game is over (hp %d)" % st.sides[1].hero.health)
	ok(not st.play_card(0, _give(st, 0, "cd_burning_sand"), st.sides[1].hero.uid), "no card can be played after the end")


var _deaths := [0, 0] ## death events seen in the soaks, replays and duels; of them, sourceless ones


func _watch_deaths(st: BattleState, what: String) -> void:
	st.event.connect(func(ev): _check_death(ev, what))


## Every death (and every fallen hero) says what killed it, or is explicitly sourceless (killer "", how "none").
func _check_death(ev: Dictionary, what: String) -> void:
	var infos: Array = []
	if ev.t == "death":
		infos.append(ev)
	elif ev.t == "game_over":
		ok(ev.has("fallen"), what + ": game_over lists the fallen heroes")
		infos.append_array(ev.get("fallen", []))
	for e in infos:
		_deaths[0] += 1
		var known: bool = e.has("killer") and e.has("how") and e.has("by")
		var sourceless: bool = known and str(e.killer) == "" and e.how == "none"
		if sourceless:
			_deaths[1] += 1
		if not (known and (str(e.killer) != "" or sourceless)):
			ok(false, "%s: a death without its killer (%s)" % [what, e])
		elif str(e.killer) != "" and not DeathStyle.STYLE_OF.has(DeathStyle.school_for(e, "lost_pilgrim")):
			ok(false, "%s: the killer %s has no death style" % [what, e.killer])


## The killer of every death (view only: DeathFx stages a death in the killer's school). It changes no rule and no
## checksum; every school has a death style and the styles' sounds exist.
func _test_killers() -> void:
	for name in VfxData.SCHOOLS:
		ok(DeathStyle.STYLE_OF.has(name) and DeathStyle.STYLES.has(DeathStyle.STYLE_OF.get(name, "")),
			"school %s has a death style" % name)
	for sty in DeathStyle.STYLES:
		var d: Dictionary = DeathStyle.STYLES[sty]
		ok(int(d.mode) > 0 and float(d.pre) > 0.0 and float(d.pre) < 0.6, "death style %s timing" % sty)
		for a in d.sfx + d.late:
			ok(_sfx_exists(a[0]), "death style %s sound %s" % [sty, a[0]])
	for sc in DeathStyle.SCHOOL_SFX:
		ok(VfxData.SCHOOLS.has(sc), "death sound school %s" % sc)
		for a in DeathStyle.SCHOOL_SFX[sc]:
			ok(_sfx_exists(a[0]), "death sound %s for %s" % [a[0], sc])
	for cls in CardDB.classes():
		var h := CardDB.class_hero(cls)
		ok(VfxData.has_own("power_" + h, "school"), "hero %s power has a school (its attacks and defeats)" % h)
		ok(DeathStyle.killer_school(h, "attack") == VfxData.profile("power_" + h).school, "a hero kills with its power")
	ok(DeathStyle.killer_school("she_wolf", "attack") == "blood", "a neutral body strikes a plain blow")
	ok(DeathStyle.killer_school("farinata", "attack") == "fire", "a fire minion's blow burns")
	ok(DeathStyle.killer_school("harpy", "venom") == "venom", "Venom kills with venom")
	ok(DeathStyle.killer_school("power_charon", "effect") == VfxData.profile("power_charon").school, "a hero power's school")
	ok(DeathStyle.killer_school("fatigue", "fatigue") == "shadow", "fatigue kills with shadow")
	ok(DeathStyle.killer_school("", "none") == "", "a sourceless death has no killer school")
	ok(DeathStyle.school_for({"killer": "", "how": "none"}, "ih_ephialtes") == "ice", "sourceless: the victim's own school")
	ok(DeathStyle.style_for(DeathStyle.school_for({"killer": "cd_burning_sand", "how": "effect"}, "ih_ephialtes")) == "burn",
		"an ice giant killed by fire burns")
	for c in CardDB.all_cards():
		ok(DeathStyle.STYLE_OF.has(DeathStyle.killer_school(c.id, "attack" if c.type == "minion" else "effect")),
			"%s kills in a known style" % c.id)

	# A trade: each minion dies to the other's blow.
	var st := _blank()
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	var a := _put(st, 0, "phlegyas") # 4/4
	var b := _put(st, 1, "ih_briareus") # 4/4
	var before := st.checksum()
	st.attack(0, a.uid, b.uid)
	var da := _death_of(evs, a.uid)
	var db := _death_of(evs, b.uid)
	ok(da.get("killer") == b.id and da.get("how") == "attack" and int(da.get("by", 0)) == b.uid,
		"a trade: the attacker dies to the defender (%s)" % da)
	ok(db.get("killer") == a.id and db.get("how") == "attack" and int(db.get("by", 0)) == a.uid,
		"a trade: the defender dies to the attacker (%s)" % db)
	ok(before != st.checksum(), "the attack changed the game")

	# A spell, a board-wide spell (several hits: the last one counts), a destroy, Venom.
	st = _blank()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	var w := _put(st, 1, "she_wolf") # 3/2
	st.play_card(0, _give(st, 0, "cd_burning_sand"), w.uid)
	ok(_death_of(evs, w.uid).get("killer") == "cd_burning_sand" and _death_of(evs, w.uid).get("how") == "effect",
		"a spell kills with its own card")
	var w2 := _put(st, 1, "she_wolf")
	w2.health = 1
	st._damage(w2, 1, null, "cd_burning_sand")
	st._damage(w2, 1, null, "minotaur_rampage")
	st._cleanup()
	ok(_death_of(evs, w2.uid).get("killer") == "minotaur_rampage", "the last hit is the killer")
	var g := _put(st, 1, "cerberus")
	st.play_card(0, _give(st, 0, "cd_furys_lash"), g.uid)
	ok(_death_of(evs, g.uid).get("killer") == "cd_furys_lash" and _death_of(evs, g.uid).get("how") == "destroy",
		"a destroy names its card")
	var hv := _put(st, 0, "harpy")
	var big := _put(st, 1, "cerberus")
	st.attack(0, hv.uid, big.uid)
	ok(_death_of(evs, big.uid).get("how") == "venom" and _death_of(evs, big.uid).get("killer") == "harpy",
		"Venom kills with its minion")

	# Heroes: a hero power's blow, fatigue.
	st = _blank()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.sides[0].hero.health = 2
	st._resolve({"do": "damage", "target": "enemy_hero", "amount": 2}, 1, null, -1, "power_charon")
	st._cleanup()
	var fallen: Array = evs.back().get("fallen", []) if evs.back().t == "game_over" else []
	ok(fallen.size() == 1 and fallen[0].killer == "power_charon" and int(fallen[0].uid) == st.sides[0].hero.uid,
		"the fallen hero names the hero power that killed it (%s)" % [fallen])
	st = _blank()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.sides[1].deck.clear()
	st.sides[1].hero.health = 1
	st.end_turn()
	fallen = evs.back().get("fallen", []) if evs.back().t == "game_over" else []
	ok(fallen.size() == 1 and fallen[0].killer == "fatigue" and fallen[0].how == "fatigue", "fatigue kills a hero")

	# The killer is view only: the checksum and the snapshots never see it.
	var ck := st.checksum()
	for u in st.units.values():
		u.killer = "somebody"
		u.kill_how = "attack"
		u.kill_by = 99
	ok(st.checksum() == ck, "the killer fields are not in the checksum")
	ok(not st.sides[0].hero.snapshot().has("killer"), "the killer fields are not in a snapshot")


static func _death_of(evs: Array, uid: int) -> Dictionary:
	for ev in evs:
		if ev.t == "death" and ev.uid == uid:
			return ev
	return {}


## The variety pass (2026-10-27): cards that combine existing effects in an order that matters.
func _test_variety() -> void:
	# Demon's Lash: 1 damage, and only a survivor goes back to the hand.
	var st := _blank()
	var small := _put(st, 1, "lost_pilgrim")
	var big := _put(st, 1, "geryon")
	ok(st.play_card(0, _give(st, 0, "ih_demons_lash"), small.uid) and st.sides[1].board.size() == 1
		and not st.sides[1].hand.any(func(c): return c.id == "lost_pilgrim"), "Demon's Lash kills a 1-health minion")
	ok(st.play_card(0, _give(st, 0, "ih_demons_lash"), big.uid) and st.sides[1].board.is_empty()
		and st.sides[1].hand.any(func(c): return c.id == "geryon"), "Demon's Lash returns a survivor")
	# Ulysses, the Schemer: the Ruse copies the minion before it is sent back.
	st = _blank()
	big = _put(st, 1, "geryon")
	ok(st.play_card(0, _give(st, 0, "mc_ulysses"), big.uid), "Ulysses plays without a Ruse")
	ok(st.sides[1].hand.size() == 1 and st.sides[0].hand.is_empty(), "no Ruse: only the bounce")
	st = _blank()
	big = _put(st, 1, "geryon")
	st.sides[0].played = 1
	ok(st.play_card(0, _give(st, 0, "mc_ulysses"), big.uid) and st.sides[1].board.is_empty(), "Ulysses with a Ruse")
	ok(st.sides[1].hand.any(func(c): return c.id == "geryon") and st.sides[0].hand.any(func(c): return c.id == "geryon"),
		"Ruse: the bounced minion's copy goes to Ulysses' hand")
	# Cut the Thread: silenced first, so no Last Breath.
	st = _blank()
	var horse := _put(st, 1, "ul_trojan_horse")
	ok(st.play_card(0, _give(st, 0, "uh_cut_the_thread"), horse.uid) and st.sides[1].board.is_empty(),
		"Cut the Thread: the Horse leaves no Raiders")
	# Burning Rain: three 1-damage hits among the enemies.
	st = _blank()
	big = _put(st, 1, "geryon")
	ok(st.play_card(0, _give(st, 0, "ih_burning_rain")), "Burning Rain needs no target")
	ok(st.sides[1].hero.health + big.health == 30 + 5 - 3, "Burning Rain deals 3 in all")
	# Earth Swallows the Seer: 2 to the target, then 1 to every enemy minion.
	st = _blank()
	big = _put(st, 1, "geryon")
	small = _put(st, 1, "lost_pilgrim")
	ok(st.play_card(0, _give(st, 0, "mc_earth_swallows"), big.uid) and big.health == 2 and small.dead,
		"Earth Swallows: 3 to the target, 1 to the rest")
	# Sinon's Lie: pay 1, get 2 this turn.
	st = _blank()
	st.sides[0].mana = 3
	ok(st.play_card(0, _give(st, 0, "mc_sinons_lie")) and st.sides[0].mana == 4 and st.sides[0].max_mana == 10,
		"Sinon's Lie: +1 mana net, no crystal")
	# Winter of Cocytus: the board clear leaves two Frozen Shades.
	st = _blank()
	_put(st, 1, "lost_pilgrim")
	ok(st.play_card(0, _give(st, 0, "ih_cocytus_winter")) and st.sides[1].board.is_empty()
		and st.sides[0].board.size() == 2 and st.sides[0].board.all(func(u): return u.id == "mc_frozen_shade"),
		"Winter of Cocytus summons two Frozen Shades")


## Damage details: Drain at full health, Drain into Ward, Armor (partial soak, fatigue), Venom against Ward, and Rebirth
## given back after a Silence.
func _test_damage_edges() -> void:
	var st := _blank()
	var p := _put(st, 0, "plutus")
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st.attack(0, p.uid, st.sides[1].hero.uid)
	ok(st.sides[0].hero.health == 30 and not evs.any(func(ev): return ev.t == "heal"), "Drain at full health heals nothing")
	st = _blank()
	st.sides[0].hero.health = 29
	p = _put(st, 0, "plutus")
	st.attack(0, p.uid, st.sides[1].hero.uid)
	ok(st.sides[0].hero.health == 30, "Drain never heals above full")
	st = _blank()
	st.sides[0].hero.health = 20
	p = _put(st, 0, "plutus")
	var w := _put(st, 1, "paolo")
	st.attack(0, p.uid, w.uid)
	ok(st.sides[0].hero.health == 20 and not w.has("ward"), "Drain into a Ward heals nothing")

	# Armor soaks first, the rest hits Health; it also soaks fatigue.
	st = _blank()
	st.sides[0].hero.armor = 3
	st._damage(st.sides[0].hero, 5, null)
	ok(st.sides[0].hero.armor == 0 and st.sides[0].hero.health == 28, "Armor soaks 3 of 5")
	st.sides[0].hero.armor = 2
	st.sides[0].deck.clear()
	st.draw(0, 1)
	ok(st.sides[0].hero.armor == 1 and st.sides[0].hero.health == 28, "Armor soaks fatigue")

	# Venom does not get through a Ward.
	st = _blank()
	var h := _put(st, 0, "harpy")
	w = _put(st, 1, "paolo")
	st.attack(0, h.uid, w.uid)
	ok(st.units.has(w.uid) and w.health == 5 and not w.has("ward"), "Ward stops Venom")

	# Rebirth given back after a Silence works (Absolved in Advance); a silenced Rebirth minion stays dead.
	st = _blank()
	var wolf := _put(st, 0, "she_wolf")
	st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, wolf.uid, "test")
	ok(st.play_card(0, _give(st, 0, "ul_absolved_in_advance"), wolf.uid) and wolf.has("rebirth"), "Rebirth given back")
	st.play_card(0, _give(st, 0, "centaur_arrows"), wolf.uid)
	ok(st.sides[0].board.size() == 1 and st.sides[0].board[0].id == "she_wolf" and st.sides[0].board[0].health == 1
		and not st.sides[0].board[0].has("rebirth"), "a silenced minion given Rebirth returns once")
	st = _blank()
	var demon := _put(st, 0, "ih_whip_demon")
	st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, demon.uid, "test")
	st.play_card(0, _give(st, 0, "cd_burning_sand"), demon.uid)
	ok(st.sides[0].board.is_empty(), "a silenced Rebirth minion stays dead")


## A minion copied onto the board (Capocchio) keeps the original's state the Hearthstone way: buffs and damage, the
## keywords it has now, Silence, Freeze; it is still a new minion (asleep unless Swift). A copy into the hand is the
## printed card.
## Every class explains itself (CardDB.class_info): the collection, Choose your path and How to play show this text.
func _test_class_info() -> void:
	var help: Dictionary = load("res://scripts/ui/ui.gd").KEYWORD_HELP
	for cls in CardDB.classes():
		var i := CardDB.class_info(cls)
		ok(i.title != "" and i.hero != "" and i.tagline != "" and i.style.length() > 40, "class %s has a title, tagline and style" % cls)
		ok(not i.keywords.is_empty() and i.keywords.all(func(k): return help.has(k)), "class %s keywords all have help" % cls)
		ok(i.tips.size() >= 2 and str(i.power.get("text", "")) != "", "class %s has tips and a hero power" % cls)


func _test_copy_state() -> void:
	var st := _blank()
	var gy := _put(st, 1, "geryon") # 4/5 Guard
	st._resolve({"do": "buff", "target": "choose_minion", "attack": 2, "health": 2, "keywords": ["venom"]}, 1, null,
		gy.uid, "test")
	st._damage(gy, 3, null)
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "ul_capocchio"), gy.uid)
	var c: BattleState.Unit = st.sides[0].board[1]
	ok(c.id == "geryon" and c.side == 0 and c.uid != gy.uid, "the copy is a new minion on Capocchio's side")
	ok(c.attack == 6 and c.health == 4 and c.max_health == 7, "the copy keeps buffs and damage (%d/%d of %d)" % [
		c.attack, c.health, c.max_health])
	ok(c.has("guard") and c.has("venom"), "the copy keeps printed and gained keywords")
	ok(c.sleeping and c.attacks_made == 0 and not c.frozen and not c.silenced, "the copy is asleep, not frozen or silenced")
	var sm: Array = evs.filter(func(ev): return ev.t == "summon" and ev.unit.id == "geryon")
	ok(sm.size() == 1 and sm[0].unit.health == 4 and sm[0].unit.max_health == 7 and sm[0].unit.attack == 6,
		"the summon event carries the copied numbers (the view shows a damaged, buffed minion)")
	st._resolve({"do": "heal", "target": "choose_minion", "amount": 9}, 0, null, c.uid, "test")
	ok(c.health == 7, "a damaged copy heals up to the original's max Health")
	ok(gy.health == 4 and gy.attack == 6, "the original is unchanged")

	# Keywords lost stay lost: a broken Ward, a used Rebirth.
	st = _blank()
	var pa := _put(st, 1, "paolo")
	st._damage(pa, 2, null)
	ok(not pa.has("ward") and pa.health == 5, "Paolo's Ward broke")
	st.play_card(0, _give(st, 0, "ul_capocchio"), pa.uid)
	ok(st.sides[0].board[1].id == "paolo" and not st.sides[0].board[1].has("ward"), "a broken Ward is not copied")
	st = _blank()
	var demon := _put(st, 1, "ih_whip_demon")
	st._damage(demon, 1, null)
	st._cleanup()
	var back: BattleState.Unit = st.sides[1].board[0]
	ok(back.id == "ih_whip_demon" and not back.has("rebirth"), "the Whip Demon came back without Rebirth")
	st.play_card(0, _give(st, 0, "ul_capocchio"), back.uid)
	var dc: BattleState.Unit = st.sides[0].board[1]
	ok(not dc.has("rebirth") and dc.health == 1 and dc.max_health == 1, "a used Rebirth is not copied")
	st._damage(dc, 1, null)
	st._cleanup()
	ok(not st.sides[0].board.any(func(u): return u.id == "ih_whip_demon"), "the copy of a reborn minion dies for good")

	# Wrath: a raging original is copied raging, once (the rage is already in its Attack); a silenced one stays calm.
	st = _blank()
	var sh := _put(st, 1, "uh_wrathful_shade")
	var base: int = sh.attack
	st._damage(sh, 1, null)
	st._cleanup()
	ok(sh.rage == sh.wrath and sh.wrath > 0 and sh.attack == base + sh.wrath, "the Shade rages when damaged")
	st.play_card(0, _give(st, 0, "ul_capocchio"), sh.uid)
	st._cleanup()
	var shc: BattleState.Unit = st.sides[0].board[1]
	ok(shc.attack == sh.attack and shc.rage == sh.rage, "a raging copy has the same Attack, the Wrath counted once (%d)" 		% shc.attack)
	st._resolve({"do": "heal", "target": "choose_minion", "amount": 9}, 0, null, shc.uid, "test")
	ok(shc.attack == base and shc.rage == 0, "healed to full, the copy calms down to its base Attack")
	st = _blank()
	sh = _put(st, 1, "uh_wrathful_shade")
	st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, sh.uid, "test")
	st._damage(sh, 1, null)
	st._cleanup()
	st.play_card(0, _give(st, 0, "ul_capocchio"), sh.uid)
	st._cleanup()
	shc = st.sides[0].board[1]
	ok(shc.wrath == 0 and shc.attack == base, "a silenced Shade's copy has no Wrath")

	# Silence is copied: no keywords, no Last Breath.
	st = _blank()
	var stung := _put(st, 1, "stung_neutral")
	st._resolve({"do": "silence", "target": "choose_minion"}, 0, null, stung.uid, "test")
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "ul_capocchio"), stung.uid)
	var sc: BattleState.Unit = st.sides[0].board[1]
	ok(sc.silenced and sc.keywords.is_empty(), "the copy of a silenced minion is silenced")
	ok(evs.any(func(ev): return ev.t == "status" and ev.uid == sc.uid and ev.silenced), "a status event shows the Silence")
	st._damage(sc, 5, null)
	st._cleanup()
	ok(st.sides[0].board.size() == 1, "the silenced copy has no Last Breath")

	# Freeze is copied, and the copy (frozen while asleep) stays frozen through its owner's next turn.
	st = _blank()
	var gy2 := _put(st, 1, "geryon")
	st._resolve({"do": "freeze", "target": "choose_minion"}, 0, null, gy2.uid, "test")
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	st.play_card(0, _give(st, 0, "ul_capocchio"), gy2.uid)
	var fc: BattleState.Unit = st.sides[0].board[1]
	ok(fc.frozen, "the copy of a frozen minion is frozen")
	ok(evs.any(func(ev): return ev.t == "status" and ev.uid == fc.uid and ev.frozen), "a status event shows the Freeze")
	st.end_turn()
	ok(fc.frozen, "the frozen copy stays frozen through the enemy turn")
	st.end_turn()
	ok(fc.frozen and not st.can_attack(fc), "the frozen copy loses its owner's next attack")
	st.end_turn()
	ok(not fc.frozen, "then it thaws")

	# Swift: the copy of a Swift minion can attack at once, even if the original already attacked.
	st = _blank()
	var ph := _put(st, 1, "phlegyas")
	ph.attacks_made = 1
	st.play_card(0, _give(st, 0, "ul_capocchio"), ph.uid)
	ok(st.can_attack(st.sides[0].board[1]), "a Swift copy can attack the turn it is summoned")

	# Into the hand a copy is the printed card (Forged Will), whatever happened to the minion.
	st = _blank()
	gy = _put(st, 1, "geryon")
	st._damage(gy, 3, null)
	st.play_card(0, _give(st, 0, "ul_forged_will"), gy.uid)
	ok(st.sides[0].hand.size() == 1 and st.sides[0].hand[0].keys().size() == 2, "a copy into the hand is the plain card")
	st.play_card(0, st.sides[0].hand[0].uid)
	var hc: BattleState.Unit = st.sides[0].board[0]
	ok(hc.health == 5 and hc.max_health == 5, "the hand copy enters with printed stats")


## Rebirth, the Hearthstone Reborn way: a new minion with 1 Health and 1 max Health (not a damaged one), its printed
## Attack and keywords minus Rebirth, no buffs; the view gets one summon with those numbers.
## The drop rates players see come from Collection.ODDS (the panel's own rows are checked in menu_smoke, which can
## load it: this runner has no autoload names at compile time): common is whatever the others leave, best rarity first.
func _test_drop_rates() -> void:
	var col: Node = root.get_node("Collection")
	var rates: Dictionary = col.drop_rates()
	ok(rates.keys() == col.RARITY_ORDER, "a drop rate per rarity, best first: %s" % str(rates.keys()))
	var sum := 0.0
	for r in rates:
		sum += float(rates[r])
		if r != "common":
			ok(is_equal_approx(float(rates[r]), float(col.ODDS[r])), "%s rate comes from Collection.ODDS" % r)
	ok(is_equal_approx(sum, 1.0), "the drop rates add up to 100%% (%f)" % sum)
	var others := float(col.ODDS.legendary) + float(col.ODDS.epic) + float(col.ODDS.rare)
	ok(is_equal_approx(float(rates.common), 1.0 - others), "common is 1 minus the other chances")
	ok(col.percent_text(0.015) == "1.5%" and col.percent_text(0.21) == "21%" and col.percent_text(0.72) == "72%",
		"percent text drops a useless .0")


func _test_rebirth() -> void:
	var st := _blank()
	var stat := _put(st, 0, "pj_statius") # 3/5 Rebirth
	st._resolve({"do": "buff", "target": "choose_minion", "attack": 2, "health": 2, "keywords": ["guard"]}, 0, null,
		stat.uid, "test")
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	st._damage(stat, 9, null)
	st._cleanup()
	ok(st.sides[0].board.size() == 1, "Rebirth brings the minion back")
	var r: BattleState.Unit = st.sides[0].board[0]
	ok(r.id == "pj_statius" and r.uid != stat.uid, "it is a new minion")
	ok(r.health == 1 and r.max_health == 1, "it returns with 1 Health and 1 max Health (%d of %d)" % [r.health,
		r.max_health])
	ok(r.attack == 3 and not r.has("guard") and not r.has("rebirth"), "printed Attack; buffs and Rebirth gone")
	ok(r.sleeping, "it returns asleep")
	var sm: Array = evs.filter(func(ev): return ev.t == "summon")
	ok(sm.size() == 1 and sm[0].unit.health == 1 and sm[0].unit.max_health == 1,
		"the summon event shows a clean 1-Health minion")
	ok(not evs.any(func(ev): return ev.t == "status" and ev.uid == r.uid), "no damaged-state update follows")
	var rb: Array = evs.filter(func(ev): return ev.t == "rebirth")
	ok(rb.size() == 1 and rb[0].uid == r.uid and evs.find(rb[0]) > evs.find(sm[0]), "the rebirth flame plays on it")
	evs.clear()
	st._resolve({"do": "heal", "target": "choose_minion", "amount": 5}, 0, null, r.uid, "test")
	ok(r.health == 1 and not evs.any(func(ev): return ev.t == "heal"), "healing a reborn minion does nothing")
	st._resolve({"do": "buff", "target": "choose_minion", "health": 2}, 0, null, r.uid, "test")
	ok(r.health == 3 and r.max_health == 3, "a buff raises it like any minion")
	# Typhon: Rebirth keeps the printed body (8/8 -> 8/1) and does not replay On Play.
	st = _blank()
	var ty := _put(st, 1, "ih_typhon")
	var foe := _put(st, 0, "lost_soul")
	st._resolve({"do": "destroy", "target": "choose_minion"}, 0, null, ty.uid, "test")
	st._cleanup()
	ok(st.sides[1].board.size() == 1 and st.sides[1].board[0].attack == 8 and st.sides[1].board[0].health == 1
		and st.sides[1].board[0].max_health == 1 and not foe.frozen, "Typhon returns 8/1 without its On Play")


## Easy behind a Guard: it does not throw a minion that dies without killing the Guard (a 1/1 into a 6/9), but it still
## makes that hit when its other attackers can then finish the Guard and that pays: a Venom or Drain Guard, or lethal
## behind it. It still kills a Guard it can and chips one when its minion survives.
func _test_easy_guard() -> void:
	var st := _blank()
	st.sides[0].power_used = true
	var small := _put(st, 0, "lost_soul")
	_put(st, 1, "cd_old_man_crete") # 6/9 Guard
	var act := BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "end", "Easy keeps a 1/1 away from a 6/9 Guard (%s)" % act)

	# A Guard it can kill, or survive: it attacks.
	st = _blank()
	st.sides[0].power_used = true
	var big := _put(st, 0, "paolo")
	var g := _put(st, 1, "cerberus")
	act = BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "attack" and act.attacker == big.uid and act.target == g.uid, "Easy still kills a Guard it can")
	st = _blank()
	st.sides[0].power_used = true
	var tank := _put(st, 0, "cd_old_man_crete")
	_put(st, 1, "cd_old_man_crete")
	act = BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "attack" and act.attacker == tank.uid, "Easy chips a Guard when its minion survives")

	# Two minions, one hopeless: only the useful one attacks.
	st = _blank()
	st.sides[0].power_used = true
	small = _put(st, 0, "lost_soul")
	big = _put(st, 0, "paolo")
	_put(st, 1, "cerberus")
	_put(st, 1, "cd_old_man_crete")
	act = BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "attack" and act.attacker == big.uid, "Easy skips the hopeless 1/1 and attacks with Paolo")

	# A Venom Guard the others can finish: the hopeless hit is worth it.
	st = _blank()
	st.sides[0].power_used = true
	for i in 3:
		_put(st, 0, "lost_pilgrim") # 2/1
	g = _put(st, 1, "cerberus") # 3/5 Guard
	g.keywords["venom"] = true
	act = BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "attack" and act.target == g.uid, "Easy gangs up on a Venom Guard")
	_ai_turn(st, BattleAI.new(0, BattleAI.Level.EASY))
	ok(not st.units.has(g.uid), "and kills it")
	# The same Guard without Venom and nothing behind it: nobody suicides, even at 2 Health when all three are needed
	# to break it (none would be left for the face).
	st = _blank()
	st.sides[0].power_used = true
	for i in 3:
		_put(st, 0, "lost_pilgrim")
	_put(st, 1, "cerberus")
	st.sides[1].hero.health = 2
	act = BattleAI.new(0, BattleAI.Level.EASY).next_action(st)
	ok(act.do == "end", "Easy does not trade 2/1s into a plain 3/5 Guard (%s)" % act)
	# A fourth attacker makes it lethal: it goes through.
	_put(st, 0, "lost_pilgrim")
	_ai_turn(st, BattleAI.new(0, BattleAI.Level.EASY))
	ok(st.winner == 0, "Easy breaks a Guard when lethal follows")


## Lets `ai` play its whole turn on `st`; returns the ids of the cards it played. Every move it picks must be legal.
func _ai_turn(st: BattleState, ai: BattleAI) -> Array:
	var played := []
	for i in 30:
		var act := ai.next_action(st)
		if act.do == "end":
			break
		if act.do == "play":
			played.append(str(st.hand_card(st.current, act.uid).get("id", "")))
		var legal := BattleAI.apply(st, st.current, act)
		ok(legal, "the AI only picks legal moves (%s)" % act)
		ok(st.sides[0].board.size() <= BattleState.MAX_BOARD, "the AI keeps the board limit")
		if not legal:
			break
	return played


## The AI at every level: it passes when it has nothing to do, plays legal moves with a full board, does not spend a
## removal spell on a token but does use it on a real threat, and uses its hero power.
func _test_ai_edges() -> void:
	for lvl in [BattleAI.Level.EASY, BattleAI.Level.MEDIUM, BattleAI.Level.HARD]:
		var st := _blank()
		st.sides[0].mana = 0
		ok(BattleAI.new(0, lvl).next_action(st).do == "end", "AI %d with no legal move ends its turn" % lvl)

		st = _blank()
		for i in 7:
			_put(st, 0, "lost_soul")
		_give(st, 0, "geryon")
		_give(st, 0, "harpies_flock")
		_put(st, 1, "cerberus")
		_ai_turn(st, BattleAI.new(0, lvl))

		st = _blank()
		st.sides[0].power_used = true
		_give(st, 0, "uh_cut_the_thread")
		_put(st, 1, "lost_soul")
		ok(not "uh_cut_the_thread" in _ai_turn(st, BattleAI.new(0, lvl)), "AI %d keeps its Destroy from a 1/1 token" % lvl)
		st = _blank()
		st.sides[0].power_used = true
		_give(st, 0, "uh_cut_the_thread")
		_put(st, 1, "cd_old_man_crete")
		ok("uh_cut_the_thread" in _ai_turn(st, BattleAI.new(0, lvl)), "AI %d destroys a 6/9" % lvl)

		if lvl != BattleAI.Level.MEDIUM: # Medium's scoring noise may pass on a small gain, by design
			st = _blank()
			_ai_turn(st, BattleAI.new(0, lvl))
			ok(st.sides[0].power_used and st.sides[0].hero.armor == 2, "AI %d uses its hero power" % lvl)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func _mtime(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1


## Saves: the collection (with custom decks), progress and settings survive a round trip; a missing, damaged or
## hand-edited file loads defaults without a crash; and a test run never writes the player's real files.
func _test_saves() -> void:
	var col: Node = root.get_node_or_null("Collection")
	var game: Node = root.get_node_or_null("Game")
	var prefs: Node = root.get_node_or_null("Settings")
	ok(col != null and game != null and prefs != null, "save autoloads present")
	if col == null or game == null or prefs == null:
		return
	var real := ["user://collection.cfg", "user://progress.cfg", "user://settings.cfg"]
	var real_times := real.map(func(p): return _mtime(p))
	var tmp := OS.get_temp_dir().path_join("dv_save_test_%d.cfg" % OS.get_process_id())
	var keep_col := [col.owned.duplicate(true), col.obols, col.packs, col.packs_since_legendary, col.opened_total,
		col.decks.duplicate(true)]

	# Round trip.
	col.owned = {"geryon": 2, "ul_circe": 1}
	col.obols = 345
	col.packs = 2
	col.packs_since_legendary = 7
	col.opened_total = 11
	col.decks = [{"name": "Test", "cls": "ulysses", "cards": {"ul_circe": 1, "geryon": 2}}]
	col.save_to(tmp)
	col.owned = {}
	col.obols = 0
	col.decks = []
	col.load_from(tmp)
	ok(col.obols == 345 and col.packs == 2 and col.packs_since_legendary == 7 and col.opened_total == 11,
		"collection numbers round-trip")
	ok(col.copies("ul_circe") == 1 and col.copies("geryon") == 2, "owned cards round-trip")
	ok(col.decks.size() == 1 and col.decks[0].name == "Test" and col.decks[0].cls == "ulysses"
		and col.decks[0].cards == {"ul_circe": 1, "geryon": 2}, "a custom deck round-trips")

	# Missing file: a first run, with the starter cards and three packs.
	DirAccess.remove_absolute(tmp)
	col.load_from(tmp)
	ok(col.packs == col.START_PACKS and col.decks.is_empty() and col.obols == 0,
		"a missing collection is a first run")
	var starter: Array[String] = CardDB.deck_list(CardDB.class_decks("pilgrim")[0].id)
	ok(starter.all(func(id): return col.copies(id) > 0), "the starter cards are owned")

	# Damaged file: no crash, a fresh collection, and in a test run it is not even copied aside.
	_write(tmp, "[collection\nowned = {{{ broken")
	col.load_from(tmp)
	ok(col.packs == col.START_PACKS and col.decks.is_empty(), "a damaged collection loads as a fresh one")
	ok(not FileAccess.file_exists(tmp + ".bad"), "a test run never copies a damaged file aside")

	# Values of the wrong type and broken decks are dropped, the rest is kept.
	_write(tmp, '[collection]\nowned=5\nobols="lots"\npacks=2.0\ndecks=[1, {"cls": "nobody", "cards": {}}, ' +
		'{"name": "Ok", "cls": "pilgrim", "cards": {"geryon": 2, "bad": "x"}}]\n')
	col.load_from(tmp)
	ok(col.obols == 0 and col.packs == 2 and col.owned is Dictionary, "wrong types fall back to the defaults")
	ok(col.decks.size() == 1 and col.decks[0].cards == {"geryon": 2}, "malformed decks and entries are dropped")

	# The real game copies a damaged file aside, so the next save cannot destroy it.
	_write(tmp, "[run\nstats = ???")
	var cfg: ConfigFile = SaveFileScript.open(tmp, true)
	ok(cfg.get_sections().is_empty() and FileAccess.file_exists(tmp + ".bad"), "a damaged file is copied aside")
	DirAccess.remove_absolute(tmp + ".bad")

	# Progress: hand-edited stats load as defaults and the result screen can still count the win.
	var keep_stats: Dictionary = game.stats.duplicate()
	var keep_arena: String = game.last_arena
	var keep_winner: int = game.last_winner
	_write(tmp, '[run]\nstats={"wins": "many"}\nlast_arena=3\n')
	game.load_progress(tmp)
	ok(game.stats.wins == 0 and game.stats.losses == 0 and game.last_arena == "", "bad progress loads the defaults")
	game.record_result(0)
	ok(game.stats.wins == 1, "a win is counted after a bad progress file")
	game.stats = keep_stats
	game.last_arena = keep_arena
	game.last_winner = keep_winner

	# Settings: values of the wrong type keep their defaults, numbers are clamped.
	var keep_prefs := [prefs.music_volume, prefs.sfx_volume, prefs.difficulty, prefs.coach_seen.duplicate(),
		prefs.intro_seen]
	_write(tmp, '[audio]\nmusic="loud"\nsfx=1\n[game]\ndifficulty=9\ncoach_seen=3\nintro_seen="yes"\n')
	prefs.load_settings(tmp)
	ok(prefs.music_volume == keep_prefs[0] and prefs.sfx_volume == 1.0 and prefs.difficulty == 2
		and prefs.coach_seen is Array and prefs.intro_seen == keep_prefs[4], "bad settings load safely")
	prefs.music_volume = keep_prefs[0]
	prefs.sfx_volume = keep_prefs[1]
	prefs.difficulty = keep_prefs[2]
	prefs.coach_seen = keep_prefs[3]

	# A test run never writes the player's files.
	col.save()
	prefs.save()
	game._save_progress("stats", game.stats)
	ok(real.map(func(p): return _mtime(p)) == real_times, "a test run never writes the real save files")
	DirAccess.remove_absolute(tmp)
	col.owned = keep_col[0]
	col.obols = keep_col[1]
	col.packs = keep_col[2]
	col.packs_since_legendary = keep_col[3]
	col.opened_total = keep_col[4]
	col.decks = keep_col[5]


# ---------------------------------------------------------------- the Wrathful (Filippo Argenti)

## Wrath is consistent: the bonus in a minion's Attack is its Wrath exactly while it is damaged.
static func _wrath_sane(u: BattleState.Unit) -> bool:
	return u.rage == (u.wrath if u.health < u.max_health else 0)


## Filippo Argenti's mechanics: Wrath on and off with damage and healing; its interplay with Silence, transform,
## copy, Rebirth, Freeze, Ward and Venom; Frenzy (once, after the blow, never when it dies or is silenced); fights;
## the hero power; the class's legendaries; every card of the class plays.
func _test_wrath() -> void:
	# The test subjects' base Attack is read from the data, so a balance pass does not break the rules checks.
	var sa := int(CardDB.card("uh_wrathful_shade").get("attack", 0)) # Wrathful Shade, Wrath: +3 Attack
	var rsa := int(CardDB.card("wr_rancorous_shade").get("attack", 0)) # Rancorous Shade, Wrath: +3 Attack
	# Damage turns Wrath on, a full heal turns it off; a partial heal or a health buff keeps it.
	var st := _blank()
	var evs := []
	st.event.connect(func(ev): evs.append(ev))
	var sh := _put(st, 0, "uh_wrathful_shade") # x/3, Wrath: +3 Attack
	ok(sh.wrath == 3 and sh.attack == sa and sh.rage == 0, "Wrath is idle while undamaged")
	st._resolve({"do": "damage", "target": "choose_minion", "amount": 2}, 0, null, sh.uid, "test")
	ok(sh.health == 1 and sh.attack == sa + 3 and sh.rage == 3, "damage turns Wrath on (%d attack)" % sh.attack)
	ok(evs.any(func(ev): return ev.t == "wrath" and ev.uid == sh.uid and ev.on and ev.attack == sa + 3), "a wrath event")
	st._heal(sh, 1, "test")
	ok(sh.health == 2 and sh.attack == sa + 3, "a partial heal keeps Wrath on")
	st._resolve({"do": "buff", "target": "choose_minion", "attack": 1, "health": 2}, 0, null, sh.uid, "test")
	ok(sh.health == 4 and sh.max_health == 5 and sh.attack == sa + 4 and _wrath_sane(sh), "a buff keeps Wrath and adds to it")
	st._heal(sh, 9, "test")
	ok(sh.health == 5 and sh.attack == sa + 1 and sh.rage == 0, "healed to full, Wrath goes off (buff kept)")
	ok(evs.any(func(ev): return ev.t == "wrath" and ev.uid == sh.uid and not ev.on and ev.attack == sa + 1), "wrath off event")

	# Silence takes the Wrath away, raging or not; stat changes stay.
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	st._resolve({"do": "buff", "target": "choose_minion", "attack": 2}, 0, null, sh.uid, "test")
	st._damage(sh, 1, null)
	ok(sh.attack == sa + 5, "buffed and raging: base + 2 + 3")
	st.play_card(0, _give(st, 0, "pj_veil_of_stillness"), sh.uid)
	ok(sh.attack == sa + 2 and sh.wrath == 0 and sh.rage == 0 and sh.silenced, "Silence removes the Wrath bonus only")
	st._damage(sh, 1, null)
	ok(sh.attack == sa + 2, "a silenced minion has no Wrath any more")

	# Transform: the new form is fresh (no Wrath of the old one); a copy into the hand is played fresh.
	st = _blank()
	var foe := _put(st, 1, "uh_wrathful_shade")
	st._damage(foe, 1, null)
	st.play_card(0, _give(st, 0, "ul_circes_draught"), foe.uid)
	var swine: BattleState.Unit = st.sides[1].board[0]
	ok(swine.id == "ul_swine" and swine.attack == 1 and swine.wrath == 0 and swine.rage == 0, "transform drops the Wrath")
	st = _blank()
	foe = _put(st, 1, "uh_wrathful_shade")
	st._damage(foe, 2, null)
	st.play_card(0, _give(st, 0, "ul_forged_will"), foe.uid)
	st.play_card(0, st.sides[0].hand[0].uid)
	var copy: BattleState.Unit = st.sides[0].board[0]
	ok(copy.id == "uh_wrathful_shade" and copy.attack == sa and copy.health == 3 and copy.rage == 0,
		"a copy from the hand comes in fresh and calm")
	# A copy summoned onto the board (Capocchio) has a consistent Wrath, whatever it keeps of the original.
	st = _blank()
	foe = _put(st, 1, "uh_wrathful_shade")
	st._damage(foe, 2, null)
	st.play_card(0, _give(st, 0, "ul_capocchio"), foe.uid)
	ok(st.sides[0].board.size() == 2 and st.sides[0].board[1].id == "uh_wrathful_shade" and _wrath_sane(st.sides[0].board[1]),
		"Capocchio's copy of a raging minion is consistent")

	# Rebirth: it comes back with 1 Health; if that is below its max Health it is damaged and rages at once.
	st = _blank()
	var rs := _put(st, 0, "wr_rancorous_shade") # x/5 Rebirth, Wrath: +3 Attack
	st.play_card(0, _give(st, 0, "centaur_arrows"), rs.uid) # 3 damage: raging
	ok(rs.attack == rsa + 3, "Rancorous Shade rages")
	st.play_card(0, _give(st, 0, "centaur_arrows"), rs.uid)
	var back: BattleState.Unit = st.sides[0].board[0]
	ok(back.id == "wr_rancorous_shade" and back.health == 1 and not back.has("rebirth") and _wrath_sane(back),
		"a reborn Wrath minion: Wrath matches its health (%d/%d, %d attack)" % [back.health, back.max_health, back.attack])
	ok(back.health == back.max_health or back.attack == rsa + 3, "reborn damaged, it rages")
	# Erichtho gives Rebirth.
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	st.play_card(0, _give(st, 0, "wr_erichtho"), sh.uid)
	ok(sh.has("rebirth"), "Erichtho gives a friendly minion Rebirth")

	# Freeze: a raging minion keeps its Attack frozen, but cannot attack.
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	_put(st, 1, "geryon")
	st._damage(sh, 1, null)
	sh.frozen = true
	ok(sh.attack == sa + 3 and not st.can_attack(sh), "a frozen raging minion keeps its Attack and cannot attack")

	# Ward blocks the damage: no Wrath, no Frenzy.
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	var mw := _put(st, 0, "wr_mud_wrestler") # 2/3, Frenzy: Gain +2/+2
	sh.keywords["ward"] = true
	mw.keywords["ward"] = true
	st.play_card(0, _give(st, 0, "wr_stirring_the_mud"))
	ok(sh.rage == 0 and sh.attack == sa and not sh.has("ward"), "Ward blocks the damage, so no Wrath")
	ok(mw.attack == 2 and not mw.frenzied, "Ward blocks the damage, so no Frenzy")

	# Venom: the minion dies, so no Wrath and no Frenzy.
	st = _blank()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	var serpent := _put(st, 1, "ih_thief_serpent") # 1/2 Venom
	mw = _put(st, 0, "wr_mud_wrestler")
	sh = _put(st, 0, "uh_wrathful_shade")
	st.attack(0, mw.uid, serpent.uid)
	ok(not st.units.has(mw.uid) and not evs.any(func(ev): return ev.t == "frenzy"), "Venom kills: no Frenzy")
	evs.clear()
	serpent = _put(st, 1, "ih_thief_serpent")
	st.attack(0, sh.uid, serpent.uid)
	ok(not st.units.has(sh.uid) and not evs.any(func(ev): return ev.t == "wrath"), "Venom kills: no Wrath")

	# Frenzy: once, after the damage has resolved; never when the blow kills or after a Silence.
	st = _blank()
	evs = []
	st.event.connect(func(ev): evs.append(ev))
	mw = _put(st, 0, "wr_mud_wrestler")
	var choked := _put(st, 0, "wr_choked_soul") # 1/3, Frenzy: Draw a card
	var lp := _put(st, 1, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "wr_stirring_the_mud"))
	ok(mw.frenzied and mw.attack == 4 and mw.health == 4 and mw.max_health == 5, "Frenzy: +2/+2 after 1 damage")
	ok(st.sides[0].hand.size() == 1, "Mud-Choked Soul's Frenzy draws")
	var i_last_hit := _event_at(evs, func(ev): return ev.t == "damage" and ev.uid == lp.uid)
	var i_frenzy := _event_at(evs, func(ev): return ev.t == "frenzy")
	ok(i_last_hit != -1 and i_frenzy > i_last_hit, "Frenzy fires after the whole blow has resolved")
	st.play_card(0, _give(st, 0, "wr_stirring_the_mud"))
	ok(mw.attack == 4 and st.sides[0].hand.size() == 1, "Frenzy fires only once")
	ok(choked.health == 1, "the soul took both hits")
	st = _blank()
	mw = _put(st, 0, "wr_mud_wrestler")
	st.play_card(0, _give(st, 0, "centaur_arrows"), mw.uid)
	ok(not st.units.has(mw.uid), "a lethal blow sets off no Frenzy")
	st = _blank()
	mw = _put(st, 0, "wr_mud_wrestler")
	st.play_card(0, _give(st, 0, "pj_veil_of_stillness"), mw.uid)
	st._damage(mw, 1, null)
	st._cleanup()
	ok(mw.attack == 2 and not mw.frenzied, "a silenced minion has no Frenzy")
	# Frenzy summons next to the minion; Marsh Warden's Frenzy armors the hero.
	st = _blank()
	var md := _put(st, 0, "wr_mud_dweller")
	var warden := _put(st, 0, "wr_marsh_warden")
	st.play_card(0, _give(st, 0, "wr_stirring_the_mud"))
	ok(st.sides[0].board.size() == 3 and st.sides[0].board[1].id == "wr_mud_soul" and st.sides[0].hero.armor == 2,
		"Mud Dweller summons a Mud Soul beside it; Marsh Warden gives 2 Armor")
	ok(md.health == 3 and warden.health == 3, "both took the blow")

	# Fights: both strike at once (the Wrath set off by the fight adds nothing to it), Venom and Drain apply, no attack
	# is used and Guard does not matter.
	st = _blank()
	var guard := _put(st, 1, "cerberus") # 3/5 Guard
	var other := _put(st, 1, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "wr_marsh_champion"), other.uid) # 4/4 fights the 2/1 behind the Guard
	var champ: BattleState.Unit = st.sides[0].board[0]
	ok(not st.units.has(other.uid) and champ.health == 2 and guard.health == 5, "a fight ignores Guard")
	ok(champ.sleeping and champ.attacks_made == 0, "a fight is not an attack")
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	var pl := _put(st, 1, "plutus") # 2/4 Drain
	st.sides[1].hero.health = 20
	st.play_card(0, _give(st, 0, "wr_butting_heads"), sh.uid) # +1 Attack, then fights the only enemy
	ok(pl.health == 4 - (sa + 1) and sh.health == 1 and sh.attack == sa + 4, "both blows land together; Wrath rages after (%d, %d, %d)" % [
		pl.health, sh.health, sh.attack])
	ok(st.sides[1].hero.health == 22, "Drain works in a fight")
	st = _blank()
	serpent = _put(st, 1, "ih_thief_serpent")
	st.play_card(0, _give(st, 0, "wr_marsh_champion"), serpent.uid)
	ok(st.sides[0].board.is_empty() and st.sides[1].board.is_empty(), "Venom works in a fight")
	st = _blank()
	ok(st.play_card(0, _give(st, 0, "wr_black_guelph")), "a fighter can be played with no enemy to fight")
	ok(st.play_card(0, _give(st, 0, "wr_butting_heads"), st.sides[0].board[0].uid), "Butting Heads with no enemy")
	# The Mob Turns: one at a time, until the target is dead.
	st = _blank()
	var gy := _put(st, 1, "geryon") # 4/5
	var mb := _put(st, 0, "wr_mud_brawler")
	var brute := _put(st, 0, "wr_stygian_brute")
	var knight := _put(st, 0, "wr_drowned_knight")
	st.play_card(0, _give(st, 0, "wr_mob_turns"), gy.uid)
	ok(not st.units.has(gy.uid), "the mob kills Geryon")
	ok(not st.units.has(mb.uid) and not st.units.has(brute.uid) and st.units.has(knight.uid) and knight.health == 1
		and knight.attack == 5, "one at a time: the knight finishes it and rages")
	# Tydeus: his On Play fight sets off his Frenzy, a second fight.
	st = _blank()
	var p1 := _put(st, 1, "lost_pilgrim")
	var p2 := _put(st, 1, "lost_pilgrim")
	st.play_card(0, _give(st, 0, "wr_tydeus"), p1.uid)
	var ty: BattleState.Unit = st.sides[0].board[0]
	ok(not st.units.has(p1.uid) and not st.units.has(p2.uid) and ty.health == 2, "Tydeus fights twice")

	# The hero power, Spite: 1 damage and +1 Attack; it kills a 1-Health enemy; no heroes.
	st = _blank()
	st.sides[0].hero_id = "filippo"
	ok(not st.can_use_power(0), "Spite needs a minion")
	sh = _put(st, 0, "uh_wrathful_shade")
	ok(not st.use_power(0, st.sides[1].hero.uid), "Spite cannot target a hero")
	ok(st.use_power(0, sh.uid) and sh.health == 2 and sh.attack == sa + 4, "Spite on a Wrath minion: base + 1 + 3")
	st = _blank()
	st.sides[0].hero_id = "filippo"
	lp = _put(st, 1, "lost_pilgrim")
	ok(st.use_power(0, lp.uid) and not st.units.has(lp.uid), "Spite kills a 1-Health enemy")

	# The legendaries.
	st = _blank()
	var fil := _put(st, 0, "uh_filippo_argenti") # 3/6, Wrath: +3, End of Turn: 1 damage to himself
	st.end_turn()
	ok(fil.health == fil.max_health - 1 and fil.attack == 6, "Filippo bites himself at the end of the turn and rages")
	st = _blank()
	fil = _put(st, 0, "uh_filippo_argenti")
	st._damage(fil, 9, null)
	st._cleanup()
	ok(st.sides[1].hero.health == 28, "Filippo's Last Breath hits the enemies")
	st = _blank()
	var towers := _put(st, 0, "wr_red_towers") # 0/6 Guard, Wrath: +4, End of Turn: 1 damage to all minions
	var lp2 := _put(st, 1, "lost_pilgrim")
	st.end_turn()
	ok(towers.health == 5 and towers.attack == 4 and not st.units.has(lp2.uid), "the Red Towers burn everyone, themselves too")
	st = _blank()
	_put(st, 1, "she_wolf")
	st.play_card(0, _give(st, 0, "wr_athamas"))
	var ath: BattleState.Unit = st.sides[0].board[0]
	ok(ath.health == 6 and ath.attack == 8 and st.sides[1].board.is_empty(), "Athamas hurts everyone, himself too")
	st = _blank()
	st.play_card(0, _give(st, 0, "wr_alberti_brothers"))
	ok(st.sides[0].board.size() == 2 and st.sides[0].board.all(func(u): return u.id == "wr_alberti_brothers"),
		"the Alberti Brothers come in pairs")
	st = _blank()
	st.play_card(0, _give(st, 0, "wr_self_gnawing_shade"))
	ok(st.sides[0].board[0].health == 3 and st.sides[0].board[0].attack == 3, "Self-Gnawing Shade enters raging")
	st = _blank()
	_put(st, 0, "wr_mud_brawler")
	_put(st, 0, "wr_stygian_brute")
	st.play_card(0, _give(st, 0, "wr_boiling_spring"))
	ok(st.sides[0].board.size() == 2 and st.sides[0].board[1].attack == 5, "the Boiling Spring: 1 damage, +1 Attack")

	# The AI's look-ahead copy keeps every Wrath and Frenzy detail.
	st = _blank()
	sh = _put(st, 0, "uh_wrathful_shade")
	mw = _put(st, 0, "wr_mud_wrestler")
	st._damage(sh, 1, null)
	st._damage(mw, 1, null)
	st._cleanup()
	var cl := st.clone(5)
	var csh: BattleState.Unit = cl.units[sh.uid]
	var cmw: BattleState.Unit = cl.units[mw.uid]
	ok(csh.wrath == 3 and csh.rage == 3 and csh.attack == sa + 3 and cmw.frenzied, "clone keeps Wrath and Frenzy state")

	# Every card of the class resolves cleanly, with enemies on the board and without.
	for c in CardDB.all_cards():
		if c.get("set", "") != "wrath":
			continue
		for crowd in 2:
			st = _blank()
			_put(st, 0, "uh_wrathful_shade")
			if crowd == 1:
				_put(st, 1, "geryon")
				_put(st, 1, "lost_pilgrim")
				_put(st, 1, "ih_thief_serpent")
			var uid := _give(st, 0, c.id)
			var tt := BattleState.target_type(c)
			var targets := st.valid_targets(0, tt) if tt != "" else ([] as Array[int])
			if c.type == "spell" and tt != "" and targets.is_empty():
				ok(not st.can_play(0, uid), "%s needs a target" % c.id)
				continue
			ok(st.play_card(0, uid, targets.back() if not targets.is_empty() else -1), "%s plays (%d)" % [c.id, crowd])
			st.end_turn()
			for s in st.sides:
				ok(s.hand.size() <= BattleState.MAX_HAND and s.board.size() <= BattleState.MAX_BOARD, "%s keeps limits" % c.id)
				for u in s.board:
					ok(u.health > 0 and _wrath_sane(u), "%s leaves a sane board (%s)" % [c.id, u.id])


# ---------------------------------------------------------------- Virgil's lessons

const LESSON_ACTS := ["play", "attack", "power", "end", "inspect"]
const LESSON_UNTIL := ["end_turn", "win", "act", "mulligan"]
const LESSON_POINTS := ["my_hero", "foe_hero", "power", "end", "mana"]


## data/lessons.json is complete; every scripted lesson is won by doing exactly what Virgil says (each "do" step can be
## done when it comes, and the guide accepts that very action), its opponent follows its script without skipping an
## intent, and against any play (random moves) the scripted opponent never makes an illegal move or stalls. The
## progress and the rewards: a lesson pays the first time it is won, never again.
func _test_lessons() -> void:
	ok(Lessons.all().size() >= 2, "lessons load")
	var ids := {}
	for l in Lessons.all():
		var id := str(l.get("id", ""))
		ok(id != "" and not ids.has(id), "lesson id '%s' is unique" % id)
		ids[id] = true
		ok(str(l.get("title", "")) != "" and str(l.get("learn", "")) != "" and str(l.get("outro", "")) != "",
			"lesson %s has its title, its lesson line and its closing line" % id)
		ok(ResourceLoader.exists("res://assets/ui/%s.png" % str(l.get("icon", ""))), "lesson %s icon" % id)
		ok(str(l.get("arena", "")) == "" or CardDB.arena_ready(str(l.arena)), "lesson %s arena is installed" % id)
		ok(Lessons.reward_text(l) != "", "lesson %s has a reward" % id)
		var lu := Lessons.line_up(l)
		for side in ["player", "enemy"]:
			var hero := str(lu[side + "_hero"])
			ok(not CardDB.hero(hero).is_empty(), "lesson %s %s hero %s" % [id, side, hero])
			ok(lu[side + "_cards"].size() >= 10, "lesson %s %s deck is long enough" % [id, side])
			for c in lu[side + "_cards"]:
				ok(not CardDB.card(c).is_empty(), "lesson %s card %s exists" % [id, c])
		ok(CardDB.hero_class(lu.player_hero) != CardDB.hero_class(lu.enemy_hero), "lesson %s: two classes" % id)
		for s in l.get("steps", []):
			var ends := int(s.has("do")) + int(s.has("until")) + int(s.has("wait"))
			ok(ends == 1, "lesson %s step '%s' ends one way" % [id, str(s.get("say", "")).left(30)])
			if s.has("do"):
				ok(str(s.do.get("act", "")) in LESSON_ACTS, "lesson %s step act %s" % [id, s.do.get("act", "")])
			if s.has("until"):
				ok(str(s.until) in LESSON_UNTIL, "lesson %s step until %s" % [id, s.until])
			for key in ["point", "mark"]:
				if s.has(key):
					var p := str(s[key])
					ok(p in LESSON_POINTS or p.begins_with("hand:") or p.begins_with("mine:") or p.begins_with("foe:"),
						"lesson %s step %s %s" % [id, key, p])
					if ":" in p:
						ok(not CardDB.card(p.split(":")[1]).is_empty(), "lesson %s points at a real card %s" % [id, p])
		if l.has("script"):
			_play_lesson(l)
			_soak_lesson(l, 12)
		if Lessons.chooses_hero(l):
			_test_lesson_hero_choice(l)
	_test_lesson_progress()


## A lesson that lets the player choose (The Trial): every hero of the class registry can be picked, deals its class's
## starter deck against another class, and an Easy AI match of that hero finishes; a bad pick falls back to the default.
func _test_lesson_hero_choice(l: Dictionary) -> void:
	var heroes := Lessons.pickable_heroes()
	ok(heroes.size() == CardDB.classes().filter(func(c): return not CardDB.class_decks(c).is_empty()).size(),
		"every class with a deck has a hero to choose")
	ok(str(l.player.hero) in heroes, "lesson %s: its default hero is one of the choices" % l.id)
	for h in heroes:
		var cls := CardDB.hero_class(h)
		var lu := Lessons.line_up(l, h)
		ok(lu.player_hero == h, "lesson %s: the pick %s is the player's hero" % [l.id, h])
		ok(lu.player_cards == CardDB.deck_list(str(CardDB.class_decks(cls)[0].id)), "lesson %s: %s plays its starter deck" % [l.id, cls])
		ok(CardDB.hero_class(lu.enemy_hero) != cls, "lesson %s: %s faces another class" % [l.id, cls])
		var st := Lessons.start_state(l, 7, h)
		var foe: BattleAI = Lessons.make_ai(l)
		var me := BattleAI.new(0, BattleAI.Level.EASY)
		var guard := 0
		while st.winner == -1 and guard < 400:
			guard += 1
			if st.current == 1:
				var m := foe.next_action(st)
				if m.do == "end" or not BattleAI.apply(st, 1, m):
					st.end_turn()
			else:
				var m := me.next_action(st)
				if m.do == "end" or not BattleAI.apply(st, 0, m):
					st.end_turn()
		ok(st.winner != -1, "lesson %s as %s: the match ends" % [l.id, h])
	ok(Lessons.line_up(l, "nobody").player_hero == str(l.player.hero), "lesson %s: an unknown hero falls back" % l.id)
	var fixed := Lessons.get_lesson("ferryman")
	ok(Lessons.line_up(fixed, heroes[-1]).player_hero == str(fixed.player.hero), "a fixed lesson ignores a hero pick")


## Plays lesson `l` the taught way: every step in order, free steps played out by the Hard AI for the player.
func _play_lesson(l: Dictionary) -> void:
	var st := Lessons.start_state(l, 11)
	var foe: LessonAI = Lessons.make_ai(l)
	var me := BattleAI.new(0, BattleAI.Level.HARD)
	var steps: Array = l.steps
	var i := 0
	var guard := 0
	while st.winner == -1 and guard < 600:
		guard += 1
		if st.current == 1:
			if not _lesson_enemy_turn(st, foe, l.id):
				return
			continue
		if i >= steps.size() or str(steps[i].get("until", "")) == "win":
			var m := me.next_action(st)
			if m.do == "end" or not BattleAI.apply(st, 0, m):
				st.end_turn()
			continue
		var s: Dictionary = steps[i]
		i += 1
		if s.has("do"):
			if str(s.do.act) == "inspect":
				continue
			var m := Lessons.resolve(s.do, st)
			ok(not m.is_empty(), "lesson %s step %d (%s) can be done when it comes" % [l.id, i, s.do])
			if m.is_empty():
				return
			ok(Lessons.matches(s.do, _lesson_action(m, st), st), "lesson %s step %d: the guide accepts %s" % [l.id, i, m])
			if m.do == "end":
				st.end_turn()
			else:
				ok(BattleAI.apply(st, 0, m), "lesson %s step %d is legal" % [l.id, i])
		elif str(s.get("until", "")) == "end_turn":
			st.end_turn()
	ok(st.winner == 0, "lesson %s is won by following the steps (winner %d, turn %d)" % [l.id, st.winner, st.turn])
	ok(i == steps.size() or (i == steps.size() - 1 and str(steps[-1].get("until", "")) == "win"),
		"lesson %s reached its last step (%d of %d)" % [l.id, i, steps.size()])
	ok(foe.skipped.is_empty(), "lesson %s: the opponent followed its script (skipped %s)" % [l.id, foe.skipped])
	# The taught path is short: won within a turn or two of the last scripted enemy turn.
	ok(st.turn <= 2 * l.get("script", []).size() + 3, "lesson %s is short (won on turn %d)" % [l.id, st.turn])


## The player action LessonGuide sees for a BattleAI move ({act, card, target}).
func _lesson_action(m: Dictionary, st: BattleState) -> Dictionary:
	match m.do:
		"play":
			return {"act": "play", "card": str(st.hand_card(0, m.uid).get("id", "")), "target": m.target}
		"attack":
			return {"act": "attack", "card": str(st.units[m.attacker].id), "target": m.target}
		"power":
			return {"act": "power", "target": m.target}
	return {"act": "end"}


## The scripted opponent's whole turn: every move legal, and the turn ends (false when it stalled).
func _lesson_enemy_turn(st: BattleState, foe: BattleAI, id: String) -> bool:
	for k in 40:
		if st.winner != -1:
			return true
		var m := foe.next_action(st)
		if m.do == "end":
			st.end_turn()
			return true
		if not BattleAI.apply(st, 1, m):
			ok(false, "lesson %s: the opponent picked an illegal move %s" % [id, m])
			st.end_turn()
			return true
	ok(false, "lesson %s: the opponent's turn never ended" % id)
	return false


## Random play against the scripted opponent: whatever the player does, the opponent stays legal and never stalls.
func _soak_lesson(l: Dictionary, games: int) -> void:
	var rng := RandomNumberGenerator.new()
	for g in games:
		rng.seed = 900 + g
		var st := Lessons.start_state(l, 100 + g)
		var foe: LessonAI = Lessons.make_ai(l)
		var me := BattleAI.new(0, BattleAI.Level.EASY)
		var guard := 0
		while st.winner == -1 and guard < 2000:
			guard += 1
			if st.current == 1:
				if not _lesson_enemy_turn(st, foe, l.id):
					return
				continue
			var moves := me._moves(st)
			if moves.is_empty() or rng.randf() < 0.25:
				st.end_turn()
			else:
				BattleAI.apply(st, 0, moves[rng.randi() % moves.size()])
		ok(st.winner != -1, "lesson %s random game %d ends" % [l.id, g])


## Progress: a lesson pays its reward once; a skipped lesson can still be won for it; the recommended lesson moves on.
func _test_lesson_progress() -> void:
	var col: Node = root.get_node_or_null("Collection")
	var prefs: Node = root.get_node_or_null("Settings")
	var keep: Dictionary = prefs.lessons.duplicate()
	var obols: int = col.obols
	var packs: int = col.packs
	prefs.lessons = {}
	var first := str(Lessons.all()[0].id)
	ok(Lessons.recommended() == first, "a new player is pointed at the first lesson")
	Lessons.skip(first)
	ok(Lessons.status(first) == Lessons.SKIPPED and Lessons.recommended() == first, "a skipped lesson is still the next one")
	var paid: Dictionary = Lessons.complete(first)
	ok(not paid.is_empty() and Lessons.status(first) == Lessons.DONE, "winning a lesson pays its reward")
	ok(col.obols - obols == int(paid.get("obols", 0)) and col.packs - packs == int(paid.get("packs", 0)),
		"the reward reaches the collection")
	ok(Lessons.complete(first).is_empty(), "a lesson pays only once")
	Lessons.skip(first)
	ok(Lessons.status(first) == Lessons.DONE, "skipping a won lesson keeps it won")
	ok(Lessons.recommended() == Lessons.next_after(first), "the next lesson is recommended after a win")
	ok(not Lessons.offer_due(), "tests never get the first-launch question")
	prefs.lessons = keep
	col.obols = obols
	col.packs = packs


# ---------------------------------------------------------------- online duels

var _mseq := 0 ## the fake server's seq counter (_mirror_send)
var _mlog: Array[String] = [] ## the fake server's event log (what a RESYNC lists)


## Online duels: two clients, one players[0] and one players[1] (its state flipped, so it sees itself as side 0), get
## the same server stream (START, the mulligans, TURN, ACTION) through DuelSync. Their games must stay identical:
## the same checksum after every message, the same events once sides are put back in canonical order, the same end.
func _test_online_mirror(games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var classes := CardDB.classes()
	var ids := ["user-a", "user-b"]
	for g in games:
		var c0: String = classes[g % classes.size()]
		var c1: String = classes[rng.randi_range(0, classes.size() - 1)]
		var start := {"seed": 90000 + g * 7919, "players": ids, "names": ["Ann", "Bob"], "first": ids[g % 2],
			"turn": 0, "phase": "mulligan", "turn_ms": 75000, "rope_ms": 15000,
			"decks": [DuelSync.deck_metadata(c0, random_deck(c0, rng), "Ann").deck,
				DuelSync.deck_metadata(c1, random_deck(c1, rng), "Bob").deck]}
		var cl: Array[DuelSync] = [DuelSync.new(), DuelSync.new()]
		var logs := [[], []]
		for k in 2:
			ok(cl[k].setup(start, ids[k]), "online %d: client %d reads START" % [g, k])
			var lg: Array = logs[k]
			cl[k].build(func(ev): lg.append(ev))
		ok(cl[0].st.flip == 0 and cl[1].st.flip == 1, "online %d: players[1] plays a flipped state" % g)
		ok(cl[0].st.checksum() == cl[1].st.checksum(), "online %d: the same opening on both clients" % g)
		ok(cl[1].st.sides[0].hero_id == cl[1].heroes[1], "online %d: the flipped client sees itself at the bottom" % g)
		_mseq = 0
		_mlog.clear()
		for k in 2: # the mulligans, each chosen by the client from its own view
			var pick := BattleAI.new(0, BattleAI.Level.EASY).mulligan_choice(cl[k].st)
			_mirror_send(cl, DuelSync.S_MULLIGAN, {"from": ids[k], "data": cl[k].mulligan_payload(pick)})
		_mirror_send(cl, DuelSync.S_TURN, {"turn": 1, "active": ids[cl[0].st.current], "reason": "start"})
		var steps := 0
		while cl[0].st.winner == -1 and steps < 3000:
			steps += 1
			var a := cl[0].st.current # canonical side to act (client 0 is not flipped)
			var mine := cl[a] # the acting client, on its own (local side 0) view
			var bot := BattleAI.new(0, BattleAI.Level.EASY)
			var act: Dictionary = bot.next_action(mine.st)
			var probe := mine.st.clone(1)
			if act.do == "end" or not BattleAI.apply(probe, 0, act):
				_mirror_send(cl, DuelSync.S_TURN, {"turn": mine.st.turn + 1, "active": ids[1 - a],
					"reason": "timeout" if steps % 9 == 0 else "end_turn"})
				continue
			var data := {}
			match act.do:
				"play":
					data = mine.play_payload(act.uid, act.target, act.index)
				"attack":
					data = mine.attack_payload(act.attacker, act.target)
				"power":
					data = mine.power_payload(act.target)
			_mirror_send(cl, DuelSync.S_ACTION, {"turn": mine.st.turn, "from": ids[a], "data": data})
		ok(cl[0].st.winner != -1, "online %d: the duel ends" % g)
		ok(cl[0].winner_id() == cl[1].winner_id(), "online %d: both clients report the same winner" % g)
		ok(cl[0].desyncs.is_empty() and cl[1].desyncs.is_empty(),
			"online %d: no desync (%s / %s)" % [g, cl[0].desyncs, cl[1].desyncs])
		var same: bool = logs[0].size() == logs[1].size()
		if same:
			for i in logs[0].size():
				if JSON.stringify(_canon_event(logs[0][i], 0)) != JSON.stringify(_canon_event(logs[1][i], 1)):
					same = false
					printerr("online %d: event %d differs: %s / %s" % [g, i, logs[0][i], logs[1][i]])
					break
		ok(same, "online %d: identical events in canonical order (%d / %d)" % [g, logs[0].size(), logs[1].size()])
		# A rejoin: a fresh client rebuilt from START and the server's event log (JSON text, as RESYNC carries it,
		# numbers turned to floats) must reach the live game exactly.
		var resync := {"start": start, "events": _mlog.map(func(j): return JSON.parse_string(j)), "seq": _mseq,
			"phase": "play", "remaining_ms": 0}
		for k in 2:
			var fresh := DuelSync.new()
			fresh.setup(JSON.parse_string(JSON.stringify(start)), ids[k])
			fresh.build()
			for e in DuelSync.resync_events(resync):
				fresh.push(e[0], e[1])
			while fresh.pending():
				var m := fresh.pop()
				fresh.apply(m[0], m[1])
			ok(fresh.st.checksum() == cl[k].st.checksum() and fresh.desyncs.is_empty(),
				"online %d: client %d rebuilt from RESYNC matches the live game (%s)" % [g, k, fresh.desyncs])
		for ev in logs[1]:
			_check_death(ev, "online %d" % g)
	# Out-of-order delivery is held back until its turn; a replayed (old) seq is dropped.
	var ds := DuelSync.new()
	ds.push(DuelSync.S_TURN, {"seq": 2})
	ds.push(DuelSync.S_TURN, {"seq": 1})
	ok(int(ds.pop()[1].seq) == 1 and int(ds.pop()[1].seq) == 2 and ds.pop().is_empty(), "online: seq order")
	ds.push(DuelSync.S_TURN, {"seq": 2})
	ok(ds.pop().is_empty(), "online: an old seq is dropped")
	ok(DuelSync.parse_deck("{\"cls\":\"nobody\",\"cards\":[]}").is_empty(), "online: an unknown class is refused")
	_test_progress_merge()
	# Chat text is plain: no control characters, no BBCode tags, at most 120 characters.
	ok(ChatText.clean("hi\u0007 [b]there[/b]\n[color=red]x[/color]") == "hi there x", "chat: control chars and BBCode go")
	ok(ChatText.clean("a".repeat(300)).length() == ChatText.MAX_LEN, "chat: 120 characters at most")
	ok(ChatText.clean("  [3 cards] ok ") == "[3 cards] ok", "chat: brackets that are not tags stay")
	var t0 := Time.get_ticks_msec()
	ok(ChatText.clean("x".repeat(200000)).length() == ChatText.MAX_LEN and Time.get_ticks_msec() - t0 < 500,
		"chat: a flood is cut before it is cleaned (%d ms)" % (Time.get_ticks_msec() - t0))
	_test_online_net()
	_test_deck_tombs()


## The online session's message handling and clocks, without a server.
func _test_online_net() -> void:
	# RESYNC: remaining_ms already includes the rope (the client used to add 15 s on top).
	var rs := {"_rx": 1000, "remaining_ms": 50000, "roped": false, "phase": "play", "over": false}
	ok(DuelSync.resync_clock(rs) == [51000, false], "online: a RESYNC's clock is remaining_ms, rope included")
	rs.roped = true
	rs.remaining_ms = 9000
	ok(DuelSync.resync_clock(rs) == [10000, true], "online: a RESYNC in the rope keeps the rope lit")
	ok(DuelSync.resync_clock({"_rx": 1000, "remaining_ms": 20000, "roped": false, "phase": "mulligan"}) == [21000, false],
		"online: a RESYNC in the mulligan runs to its end")
	ok(DuelSync.resync_clock({"_rx": 1000, "remaining_ms": 0}) == [0, false], "online: no remaining time, no clock")
	# A TURN replayed from that RESYNC keeps the RESYNC's clock; a live TURN counts turn + rope from its arrival.
	rs.events = [{"seq": 1, "from": "a", "data": {"replace": []}}, {"seq": 2, "from": "b", "data": {"replace": [1]}},
		{"seq": 3, "turn": 1, "active": "a", "reason": "start", "turn_ms": 75000, "rope_ms": 15000},
		{"seq": 4, "turn": 1, "from": "a", "data": {"t": "power", "target": -1}}]
	var evs := DuelSync.resync_events(rs)
	ok(evs.size() == 4 and evs[0][0] == DuelSync.S_MULLIGAN and evs[2][0] == DuelSync.S_TURN
		and evs[3][0] == DuelSync.S_ACTION, "online: RESYNC events are told apart by their fields")
	ok(DuelSync.turn_clock(evs[2][1]) == [10000, true], "online: a replayed TURN keeps the RESYNC's clock")
	ok(DuelSync.turn_clock({"_rx": 2000, "turn_ms": 75000, "rope_ms": 15000}) == [92000, false],
		"online: a live TURN runs turn_ms + rope_ms from its arrival")
	# Server errors in plain words; the mulligan the server already decided says nothing.
	ok(DuelSync.error_text("already_sent") == "" and DuelSync.error_text("not_in_mulligan") == ""
		and DuelSync.error_text("not_your_turn").begins_with("Too late"), "online: server errors in plain words")
	# END: the server's winner is final, as a local side.
	var ds := DuelSync.new()
	ds.players = ["user-a", "user-b"]
	ds.me = 1
	ok(ds.end_side({"winner": "user-b"}) == 0 and ds.end_side({"winner": "user-a"}) == 1
		and ds.end_side({"winner": "", "reason": "desync"}) == 2, "online: END's winner as a local side")
	# Joins and links refused, said plainly. (OnlineSession uses autoloads: loaded at run time, its State by number:
	# 0 IDLE, 3 JOINING.)
	var sess_script: GDScript = load("res://scripts/net/online_session.gd")
	ok(sess_script.join_error_text({"error": "Match not found", "code": 4}) == "That duel has already ended."
		and sess_script.join_error_text({"error": "match is over", "code": 5}) == "That duel has already ended.",
		"online: joining a finished duel says so")
	ok(sess_script.link_taken({"error": "Google ID is already in use.", "code": 409})
		and not sess_script.link_taken({"error": "The server did not answer (timed out)."}),
		"online: only an identity taken by another account moves the install there")
	# The session's match inbox: only the match it joins or plays, and END while joining fails the search at once.
	var s: Node = sess_script.new(950)
	var got := {"ready": 0, "failed": []}
	s.match_ready.connect(func(_st): got.ready += 1)
	s.failed.connect(func(m): got.failed.append(m))
	s.state = 0
	s.match_id = "m1"
	s._on_match_data(DuelSync.S_START, {"_mid": "m1", "players": ["a", "b"]})
	ok(got.ready == 0 and s.state == 0, "online: a START after a cancelled join starts nothing")
	s.state = 3
	s._on_match_data(DuelSync.S_START, {"_mid": "m2", "players": ["a", "b"]})
	ok(got.ready == 0 and s.state == 3, "online: another match's START is ignored")
	s._on_match_data(DuelSync.S_END, {"_mid": "m1", "winner": "", "reason": "no_show"})
	ok(s.state == 0 and s.match_id == "" and got.failed.size() == 1
		and str(got.failed[0]).contains("never arrived"), "online: END no_show while joining fails the search")
	s.state = 3
	s.match_id = "m1"
	s._on_match_data(DuelSync.S_START, {"_mid": "m1", "players": ["a", "b"]})
	ok(got.ready == 1 and s.in_match(), "online: the joined match's START starts the duel")
	s._on_match_data(DuelSync.S_ACTION, {"_mid": "m2", "seq": 5})
	s._on_match_data(DuelSync.S_ACTION, {"_mid": "m1", "seq": 5})
	ok(s.inbox.size() == 1 and int(s.inbox[0][1].seq) == 5, "online: only this match's moves reach the inbox")
	s.free()


## Deleted decks stay deleted across devices (tombstones in the cloud save), and nothing else is lost.
func _test_deck_tombs() -> void:
	var a := {"name": "Wrath", "cls": "pilgrim", "cards": {"x": 2}}
	var b := {"name": "Ferry", "cls": "ferry", "cards": {"y": 2}, "saved_ms": 7000}
	var tombs := {"pilgrim|Wrath": 5000}
	var m := ProgressMerge.merge_decks([b], [a], tombs)
	ok(m.size() == 1 and m[0].name == "Ferry", "decks: a deck deleted here does not come back from the other save")
	var again := a.duplicate(true)
	again["saved_ms"] = 6000
	ok(ProgressMerge.merge_decks([again], [a], tombs).size() == 1, "decks: a deck made again after the deletion stays")
	var edited := b.duplicate(true)
	edited.cards = {"y": 1, "z": 1}
	edited.saved_ms = 9000
	m = ProgressMerge.merge_decks([b], [edited], {})
	ok(m.size() == 1 and m[0].cards.has("z"), "decks: the copy saved last wins, even from the older save")
	ok(ProgressMerge.merge_decks([a, a.duplicate()], [], {}).size() == 2, "decks: two decks of the same name both stay")
	ok(ProgressMerge.merge_tombs({"k": 3, "j": 1}, {"k": 9}) == {"k": 9, "j": 1}, "decks: tombstones keep the later time")
	# Through the whole merge, both directions, and an upload that keeps another device's tombstones.
	var col := func(decks: Array, t: Dictionary) -> Dictionary:
		return {"owned": {}, "obols": 5, "packs": 0, "pity": 0, "opened": 1, "decks": decks, "deleted_decks": t}
	var here := ProgressMerge.blob({"collection": col.call([b], tombs), "record": {"wins": 1}}, 8000)
	var there := ProgressMerge.blob({"collection": col.call([a, b], {}), "record": {"wins": 1}}, 9000)
	for pair in [[here, there], [there, here]]:
		var mm := ProgressMerge.merge(pair[0], pair[1])
		ok(mm.data.collection.decks.size() == 1 and mm.data.collection.deleted_decks.has("pilgrim|Wrath"),
			"decks: the merge drops the deleted deck and keeps its tombstone")
	var up := ProgressMerge.keep_foreign(ProgressMerge.blob({"collection": col.call([], {})}, 1), here,
		func(_id: String) -> bool: return true, func(_c: String) -> bool: return true)
	ok(up.data.collection.deleted_decks.has("pilgrim|Wrath"), "decks: an upload keeps the account's tombstones")
	# The collection stamps saves, buries renames and deletions.
	var coll: Node = root.get_node_or_null("Collection")
	if coll == null:
		return
	var keep := [coll.decks.duplicate(true), coll.deck_tombs.duplicate()]
	var d := {"name": "Old name", "cls": "pilgrim", "cards": {}}
	coll.stamp_deck(d)
	ok(int(d.get("saved_ms", 0)) > 0, "decks: a saved deck carries its time")
	var renamed := d.duplicate(true)
	renamed.name = "New name"
	coll.stamp_deck(renamed, d)
	ok(coll.deck_tombs.has("pilgrim|Old name"), "decks: a rename buries the old name")
	coll.decks = [renamed]
	coll.delete_deck(0)
	ok(coll.decks.is_empty() and coll.deck_tombs.has("pilgrim|New name"), "decks: a deletion leaves a tombstone")
	coll.decks = keep[0]
	coll.deck_tombs = keep[1]


## The cloud save's merge rules (ProgressMerge): pure functions, no network.
func _test_progress_merge() -> void:
	var fresh := ProgressMerge.blob({"collection": {"owned": {"a": 2}, "obols": 0, "packs": 3, "pity": 0, "opened": 0,
		"decks": []}, "record": {"wins": 0, "losses": 0}, "online": {}, "profile": {"name": ""}, "settings": {}}, 100)
	var played := ProgressMerge.blob({"collection": {"owned": {"a": 2, "b": 1}, "obols": 300, "packs": 1, "pity": 7,
		"opened": 5, "decks": [{"name": "Mine", "cls": "pilgrim", "cards": {"a": 2}}]},
		"record": {"wins": 4, "losses": 2, "class_games": {"pilgrim": 6}}, "online": {"wins": 1, "losses": 0, "draws": 0},
		"profile": {"name": "Enrico", "avatar": "dante"},
		"settings": {"lessons": {"l1": "done", "l2": "skipped"}, "coach_seen": ["play"]}}, 5000)
	ok(ProgressMerge.is_fresh(fresh) and not ProgressMerge.is_fresh(played), "save: fresh means the starter state")
	ok(ProgressMerge.same(ProgressMerge.merge(played, {}), played), "save: an empty account takes this install's")
	ok(ProgressMerge.same(ProgressMerge.merge(fresh, played), played), "save: a fresh install takes the account's")
	ok(ProgressMerge.same(ProgressMerge.merge(played, fresh), played), "save: a fresh account never wipes progress")
	# Both played: the newer wins field by field, nothing earned is lost.
	var other := ProgressMerge.blob({"collection": {"owned": {"a": 1, "c": 2}, "obols": 40, "packs": 4, "pity": 2,
		"opened": 9, "decks": [{"name": "Phone deck", "cls": "ferry", "cards": {"c": 2}}]},
		"record": {"wins": 2, "losses": 5, "class_games": {"ferry": 7}}, "online": {"wins": 0, "losses": 3, "draws": 1},
		"profile": {"name": "Enrico", "avatar": "charon"},
		"settings": {"lessons": {"l2": "done", "l3": "skipped"}, "coach_seen": ["attack"]}}, 9000)
	var m := ProgressMerge.merge(played, other)
	var c: Dictionary = m.data.collection
	ok(int(c.owned.a) == 2 and int(c.owned.b) == 1 and int(c.owned.c) == 2, "save: owned cards are united (most copies)")
	ok(int(c.packs) == 4 and int(c.pity) == 7 and int(c.opened) == 9, "save: packs, pity and opened keep the larger")
	ok(int(c.obols) == 40, "save: Obols follow the newer save")
	ok(c.decks.size() == 2, "save: custom decks are united")
	ok(int(m.data.record.wins) == 4 and int(m.data.record.losses) == 5 and int(m.data.record.class_games.pilgrim) == 6
		and int(m.data.record.class_games.ferry) == 7, "save: the AI record only grows")
	ok(int(m.data.online.wins) == 1 and int(m.data.online.losses) == 3, "save: the online record only grows")
	ok(m.data.settings.lessons == {"l1": "done", "l2": "done", "l3": "skipped"}, "save: lessons are united, done wins")
	ok(m.data.settings.coach_seen.size() == 2, "save: coach tips seen are united")
	ok(str(m.data.profile.avatar) == "charon" and int(m.saved_at_ms) == 9000, "save: the newer profile and time")
	ok(ProgressMerge.same(ProgressMerge.merge(other, played), m), "save: the merge does not depend on the side")
	ok(ProgressMerge.same(JSON.parse_string(JSON.stringify(m)), m), "save: a server round trip reads the same")
	# An older build uploading keeps what it cannot show (cards "c", the "ferry" class), and nothing else comes back.
	var kept := ProgressMerge.keep_foreign(played, other, func(id: String) -> bool: return id != "c",
		func(cls: String) -> bool: return cls != "ferry")
	var kc: Dictionary = kept.data.collection
	ok(int(kc.owned.get("c", 0)) == 2 and int(kc.owned.a) == 2 and kc.decks.size() == 2 and int(kc.obols) == 300,
		"save: an upload keeps the account's cards and decks this build does not know")
	var none := ProgressMerge.keep_foreign(played, other, func(_id: String) -> bool: return true,
		func(_cls: String) -> bool: return true)
	ok(ProgressMerge.same(none, played), "save: an upload with nothing unknown is this install's progress")


## The fake server: stamps the next seq and hands the message to both clients, which apply all they can; then the
## two games must match.
func _mirror_send(cl: Array[DuelSync], op: int, data: Dictionary) -> void:
	_mseq += 1
	data["seq"] = _mseq
	_mlog.append(JSON.stringify(data)) # the server keeps each event as its JSON text, without the op code
	for k in 2:
		cl[k].push(op, data.duplicate(true))
		while true:
			var m := cl[k].pop()
			if m.is_empty():
				break
			var why := cl[k].apply(m[0], m[1])
			if why != "":
				ok(false, "online: client %d refused seq %d: %s" % [k, _mseq, why])
	if cl[0].st.checksum() != cl[1].st.checksum():
		ok(false, "online: checksums differ after seq %d (op %d)" % [_mseq, op])


## An event with its sides put back in canonical order (`flip` of the client that saw it).
static func _canon_event(ev: Dictionary, flip: int) -> Dictionary:
	var e := ev.duplicate(true)
	if flip == 0:
		return e
	if e.has("side") and (e.side is int or e.side is float):
		e.side = int(e.side) ^ 1
	if e.get("t") == "game_over" and int(e.winner) in [0, 1]:
		e.winner = int(e.winner) ^ 1
	if e.get("t") == "steal":
		e.from = int(e.from) ^ 1
	for k in ["heroes", "decks"]:
		if e.has(k):
			var arr: Array = e[k]
			arr.reverse()
	var snaps: Array = e.get("heroes", []).duplicate()
	if e.has("unit"):
		snaps.append(e.unit)
	for snap in snaps:
		snap.side = int(snap.side) ^ 1
	return e
