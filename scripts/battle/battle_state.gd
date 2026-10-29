class_name BattleState
extends RefCounted
## Pure game rules (no nodes, no animation). Every change is reported through `event` with the values that
## result from it, so the view can replay the battle one step at a time without reading live state.

signal event(ev: Dictionary)

const MAX_BOARD := 7
const MAX_HAND := 10
const MAX_MANA := 10
const START_HAND := [3, 4]
const TURN_LIMIT := 90
const HERO_UIDS := [1, 2]


class Unit:
	var uid := 0
	var id := ""
	var side := 0
	var is_hero := false
	var attack := 0
	var health := 0
	var max_health := 0
	var armor := 0
	var keywords := {}
	var sleeping := true
	var attacks_made := 0
	var dead := false
	var frozen := false
	var silenced := false
	var wrath := 0 ## Wrath: the Attack it gains while damaged (0: none; Silence takes it away)
	var rage := 0 ## the Wrath bonus included in `attack` right now (0 while undamaged)
	var frenzied := false ## its Frenzy already went off (it fires once)
	# The last blow (view only: it picks the look of the death). Never read by the rules, never in the checksum or a
	# snapshot, so it changes nothing an online duel or a replay compares. See `_mark`.
	var killer := "" ## card id (a minion, a spell, "power_<hero>"), or "fatigue"; "" when nothing has hit it
	var kill_how := "" ## attack (a blow or a fight), venom, effect, destroy, transform, bounce, fatigue
	var kill_by := -1 ## uid of the unit that struck the blow (attack / venom), else -1

	func has(k: String) -> bool:
		return keywords.has(k)

	func snapshot() -> Dictionary:
		return {"uid": uid, "id": id, "side": side, "is_hero": is_hero, "attack": attack, "health": health,
			"max_health": max_health, "armor": armor, "keywords": keywords.keys(), "sleeping": sleeping,
			"frozen": frozen, "silenced": silenced, "rage": rage}


class SideState:
	var hero: Unit
	var hero_id := ""
	var deck: Array[String] = []
	var hand: Array[Dictionary] = []
	var board: Array[Unit] = []
	var mana := 0
	var max_mana := 0
	var power_used := false
	var fatigue := 0
	var played := 0 ## cards played this turn (Ruse effects need one played before them)


var sides: Array[SideState] = []
var current := 0
var turn := 0
var winner := -1 ## -1 running, 0 / 1 that side won, 2 draw
var rng := RandomNumberGenerator.new()
var units := {} ## uid -> Unit, heroes and minions in play
var _next_uid := 10

# Lesson setup (Virgil's lessons, scripts/tutorial/lessons.gd): set these before start(). The defaults are the real game.
var stacked := false ## the decks are dealt in list order, the first card first (no shuffle)
var opening := [-1, -1] ## per side: the opening hand's size (-1: START_HAND, by who goes first)
var coin := true ## the side going second gets Charon's Obol
var hero_health := [0, 0] ## per side: the hero's Health and max Health (0: the hero's own)
var hero_wounds := [0, 0] ## per side: damage the hero has already taken when the game starts
var start_mana := [0, 0] ## per side: the empty mana crystals it starts with (its first turn adds one)
var start_board: Array = [[], []] ## per side: minion card ids already in play when the game starts (awake)

## Online duels: both players build the same canonical game (side 0 = the match's players[0]), but each one sees
## itself at the bottom as side 0. With `flip` 1 (this player is players[1]) `sides` keeps the local order (sides[0]
## is this player) while everything in `start` that uses the random stream or hands out uids runs in canonical order,
## so uids, shuffles and random picks match on both machines. Every rule after `start` only uses sides relative to the
## acting one, so nothing else depends on it. Set before start(). Canonical side = local side ^ flip.
var flip := 0


# ---------------------------------------------------------------- setup

## With wait_mulligan the opening hands are dealt and the game waits for finish_mulligan() from both sides.
## `first`: the side that takes the first turn (-1 = coin flip); the other side opens with one more card and
## Charon's Obol after the mulligan.
## Online (`flip` 1): the arguments and `first` are canonical sides (deck_a belongs to players[0]); see `flip`.
func start(deck_a: Array[String], hero_a: String, deck_b: Array[String], hero_b: String, seed_value: int = 0,
		wait_mulligan: bool = false, first: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	sides.clear()
	sides.resize(2)
	for c in 2: # canonical order: the shuffles, hero uids and opening draws match whichever side is local
		var i := c ^ flip
		var s := SideState.new()
		s.hero_id = hero_a if c == 0 else hero_b
		s.deck = (deck_a if c == 0 else deck_b).duplicate()
		if stacked:
			s.deck.reverse() # cards are drawn from the back: the list's first card comes first
		else:
			_shuffle(s.deck)
		var h := Unit.new()
		h.uid = HERO_UIDS[c]
		h.id = s.hero_id
		h.side = i
		h.is_hero = true
		h.max_health = int(hero_health[i]) if int(hero_health[i]) > 0 else int(CardDB.hero(s.hero_id).get("health", 30))
		h.health = maxi(1, h.max_health - int(hero_wounds[i]))
		s.hero = h
		s.max_mana = clampi(int(start_mana[i]), 0, MAX_MANA - 1)
		units[h.uid] = h
		sides[i] = s
	_emit({"t": "start", "heroes": [sides[0].hero.snapshot(), sides[1].hero.snapshot()],
		"decks": [sides[0].deck.size(), sides[1].deck.size()]})
	for c in 2:
		var i := c ^ flip
		for id in start_board[i]:
			var u := _summon(i, str(id))
			if u != null:
				u.sleeping = false
		if not sides[i].board.is_empty():
			_emit({"t": "wake", "side": i, "uids": sides[i].board.map(func(u): return u.uid)})
		if sides[i].max_mana > 0:
			_emit({"t": "mana", "side": i, "mana": 0, "max": sides[i].max_mana})
	if wait_mulligan:
		_emit({"t": "mulligan_begin"})
	current = (first ^ flip) if first != -1 else rng.randi() % 2
	_emit({"t": "first", "side": current})
	for c in 2:
		var i := c ^ flip
		var n := int(opening[i])
		draw(i, n if n >= 0 else (START_HAND[0] if i == current else START_HAND[1]))
	if wait_mulligan:
		_mulligan_pending = [true, true]
		_emit({"t": "mulligan_wait"})
	else:
		if coin:
			_give_coin()
		_begin_turn()


const COIN := "obol_coin"


func _give_coin() -> void:
	_resolve({"do": "give_card", "card": COIN, "count": 1}, 1 - current, null, -1, "coin")


var _mulligan_pending := [false, false]


## A deep copy for look-ahead (the AI tries moves on it). It has no listeners; its random stream starts from `seed`
## and both decks are reshuffled, so a search cannot peek at how random effects or draws will fall.
func clone(seed: int) -> BattleState:
	var b := BattleState.new()
	b.current = current
	b.turn = turn
	b.winner = winner
	b._next_uid = _next_uid
	b._mulligan_pending = _mulligan_pending.duplicate()
	b.flip = flip
	b.rng.seed = seed
	for s in sides:
		var n := SideState.new()
		n.hero_id = s.hero_id
		n.deck = s.deck.duplicate()
		# The copy must not know the real draw order: shuffle it with its own RNG (Fisher-Yates).
		for k in range(n.deck.size() - 1, 0, -1):
			var j := b.rng.randi_range(0, k)
			var tmp = n.deck[k]
			n.deck[k] = n.deck[j]
			n.deck[j] = tmp
		for c in s.hand:
			n.hand.append(c.duplicate())
		n.mana = s.mana
		n.max_mana = s.max_mana
		n.power_used = s.power_used
		n.fatigue = s.fatigue
		n.played = s.played
		n.hero = _copy_unit(s.hero)
		b.units[n.hero.uid] = n.hero
		for u in s.board:
			var cu := _copy_unit(u)
			n.board.append(cu)
			b.units[cu.uid] = cu
		b.sides.append(n)
	return b


static func _copy_unit(u: Unit) -> Unit:
	var c := Unit.new()
	c.uid = u.uid
	c.id = u.id
	c.side = u.side
	c.is_hero = u.is_hero
	c.attack = u.attack
	c.health = u.health
	c.max_health = u.max_health
	c.armor = u.armor
	c.keywords = u.keywords.duplicate()
	c.sleeping = u.sleeping
	c.attacks_made = u.attacks_made
	c.dead = u.dead
	c.frozen = u.frozen
	c.silenced = u.silenced
	c.wrath = u.wrath
	c.rage = u.rage
	c.frenzied = u.frenzied
	c.killer = u.killer
	c.kill_how = u.kill_how
	c.kill_by = u.kill_by
	return c


func in_mulligan() -> bool:
	return _mulligan_pending[0] or _mulligan_pending[1]


## A fingerprint of the whole game in canonical side order (see `flip`), the random stream included: two machines
## playing the same online duel must get the same value after every action, so a mismatch is a desync.
func checksum() -> String:
	var parts := PackedStringArray([str(turn), str(current ^ flip), str(winner if winner > 1 or winner < 0 else winner ^ flip),
		str(rng.state), str(_next_uid), str(_mulligan_pending[flip]), str(_mulligan_pending[1 - flip])])
	for c in 2:
		var s := sides[c ^ flip]
		parts.append("|%s,%d,%d,%s,%d,%d" % [s.hero_id, s.mana, s.max_mana, s.power_used, s.fatigue, s.played])
		parts.append(_unit_print(s.hero))
		parts.append(",".join(s.deck))
		for h in s.hand:
			parts.append("%d:%s" % [h.uid, h.id])
		for u in s.board:
			parts.append(_unit_print(u))
	return "%08x" % ("/".join(parts).hash() & 0xffffffff)


static func _unit_print(u: Unit) -> String:
	var kw: Array = u.keywords.keys()
	kw.sort()
	return "%d:%s:%d/%d/%d/%d:%s:%s%d%s%s%d%s" % [u.uid, u.id, u.attack, u.health, u.max_health, u.armor,
		",".join(PackedStringArray(kw)), u.sleeping, u.attacks_made, u.frozen, u.silenced, u.rage, u.frenzied]


## Shuffles the chosen opening cards back and draws replacements; the game starts once both sides are done.
func finish_mulligan(side: int, replace_uids: Array) -> void:
	if not _mulligan_pending[side]:
		return
	_mulligan_pending[side] = false
	var s := sides[side]
	var back: Array[String] = []
	for uid in replace_uids:
		var c := hand_card(side, uid)
		if c.is_empty():
			continue
		var i := s.hand.find(c)
		var id: String = s.deck.pop_back()
		var fresh := {"uid": _uid(), "id": id}
		s.hand[i] = fresh
		back.append(c.id)
		_emit({"t": "mulligan_swap", "side": side, "old": uid, "uid": fresh.uid, "id": id})
	for id in back:
		s.deck.insert(rng.randi_range(0, s.deck.size()), id)
	if not in_mulligan():
		_emit({"t": "mulligan_end"})
		_give_coin()
		_begin_turn()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _emit(ev: Dictionary) -> void:
	event.emit(ev)


# ---------------------------------------------------------------- turns

func _begin_turn() -> void:
	turn += 1
	var s := sides[current]
	s.max_mana = mini(MAX_MANA, s.max_mana + 1)
	s.mana = s.max_mana
	s.power_used = false
	s.played = 0
	for u in s.board:
		u.sleeping = false
		u.attacks_made = 0
	_emit({"t": "turn", "side": current, "turn": turn})
	_emit({"t": "mana", "side": current, "mana": s.mana, "max": s.max_mana})
	_emit({"t": "wake", "side": current, "uids": s.board.map(func(u): return u.uid)})
	draw(current, 1)
	_cleanup()
	_fire_turn_triggers(current, "turn_start")


func end_turn() -> void:
	if winner != -1 or in_mulligan():
		return # nothing ends a turn while the opening hands are still being chosen
	_fire_turn_triggers(current, "turn_end")
	if winner != -1:
		return
	# Freeze costs a minion one attack (Hearthstone rule). At the end of its owner's turn a frozen minion thaws only
	# if the freeze took this turn's attack from it: it was awake and had not attacked. One frozen after it attacked
	# (a Last Breath set off by its own attack) or while it was still asleep stays frozen through its next turn.
	for u in sides[current].board:
		if u.frozen and _freeze_spent(u):
			u.frozen = false
			_emit_status(u)
	_emit({"t": "turn_end", "side": current})
	current = 1 - current
	if turn >= TURN_LIMIT:
		winner = 2
		_emit({"t": "game_over", "winner": 2, "fallen": []})
		return
	_begin_turn()


## True when a frozen minion has lost an attack to the freeze this turn: awake and with its attack unused, so it
## thaws at the end of its owner's turn. Otherwise the freeze still has to cost it its next turn's attack.
static func _freeze_spent(u: Unit) -> bool:
	return not u.sleeping and u.attacks_made == 0


func _fire_turn_triggers(side: int, trigger: String) -> void:
	if winner != -1:
		return # the game already ended (fatigue at the start of the turn): nothing may follow "game_over"
	for u in sides[side].board.duplicate():
		if u.dead or u.silenced:
			continue
		for e in CardDB.card(u.id).get("effects", []):
			if e.get("on", "") == trigger:
				_emit({"t": "trigger", "uid": u.uid})
				_resolve(e, side, u, -1, u.id)
				_cleanup()
				if winner != -1:
					return


func _emit_status(u: Unit) -> void:
	_emit({"t": "status", "uid": u.uid, "frozen": u.frozen, "silenced": u.silenced, "keywords": u.keywords.keys(),
		"attack": u.attack, "health": u.health, "max_health": u.max_health})


func draw(side: int, n: int) -> void:
	var s := sides[side]
	for i in n:
		if s.deck.is_empty():
			s.fatigue += 1
			_emit({"t": "fatigue", "side": side, "amount": s.fatigue})
			_damage(s.hero, s.fatigue, null)
			continue
		var id: String = s.deck.pop_back()
		if s.hand.size() >= MAX_HAND:
			_emit({"t": "burn", "side": side, "id": id, "deck": s.deck.size()})
			continue
		var c := {"uid": _uid(), "id": id}
		s.hand.append(c)
		_emit({"t": "draw", "side": side, "uid": c.uid, "id": id, "deck": s.deck.size()})


## A card made for a full hand (an added card or a copy) burns like an overdraw, so the player sees it was lost.
## `made`: the view shows it appearing, not leaving the deck pile (the deck count is unchanged).
func _burn_made(side: int, id: String) -> void:
	_emit({"t": "burn", "side": side, "id": id, "deck": sides[side].deck.size(), "made": true})


func _uid() -> int:
	_next_uid += 1
	return _next_uid


# ---------------------------------------------------------------- queries

func hand_card(side: int, hand_uid: int) -> Dictionary:
	for c in sides[side].hand:
		if c.uid == hand_uid:
			return c
	return {}


## Ruse: a card's "ruse" effects resolve only when its owner already played another card this turn (the hero power
## does not count). The view can use this to light up Ruse cards in hand.
func ruse_active(side: int) -> bool:
	return side == current and sides[side].played > 0


## The "choose_*" target of the card's play effects ("" when it needs none).
static func target_type(card: Dictionary) -> String:
	for e in card.get("effects", []):
		if e.get("on", "play") == "play" and str(e.get("target", "")).begins_with("choose_"):
			return e.target
	return ""


static func power_target_type(hero_def: Dictionary) -> String:
	for e in hero_def.get("power", {}).get("effects", []):
		if str(e.get("target", "")).begins_with("choose_"):
			return e.target
	return ""


func valid_targets(side: int, ttype: String) -> Array[int]:
	var out: Array[int] = []
	var me := sides[side]
	var foe := sides[1 - side]
	match ttype:
		"choose_any":
			out.append(me.hero.uid)
			out.append(foe.hero.uid)
			for u in me.board + foe.board:
				out.append(u.uid)
		"choose_enemy":
			out.append(foe.hero.uid)
			for u in foe.board:
				out.append(u.uid)
		"choose_minion":
			for u in me.board + foe.board:
				out.append(u.uid)
		"choose_enemy_minion":
			for u in foe.board:
				out.append(u.uid)
		"choose_friendly_minion":
			for u in me.board:
				out.append(u.uid)
	return out


func can_play(side: int, hand_uid: int) -> bool:
	if winner != -1 or side != current or in_mulligan():
		return false
	var c := hand_card(side, hand_uid)
	if c.is_empty():
		return false
	var card := CardDB.card(c.id)
	if int(card.cost) > sides[side].mana:
		return false
	if card.type == "minion":
		return sides[side].board.size() < MAX_BOARD
	var tt := target_type(card)
	return tt == "" or not valid_targets(side, tt).is_empty()


func can_use_power(side: int) -> bool:
	if winner != -1 or side != current or sides[side].power_used or in_mulligan():
		return false
	var h := CardDB.hero(sides[side].hero_id)
	if int(h.power.cost) > sides[side].mana:
		return false
	var tt := power_target_type(h)
	return tt == "" or not valid_targets(side, tt).is_empty()


func can_attack(u: Unit) -> bool:
	return u != null and not u.is_hero and not u.dead and u.side == current and winner == -1 and not in_mulligan() \
		and u.attack > 0 and not u.sleeping and u.attacks_made < 1 and not u.frozen


func attack_targets(side: int) -> Array[int]:
	var foe := sides[1 - side]
	var out: Array[int] = []
	for u in foe.board:
		if u.has("guard"):
			out.append(u.uid)
	if out.is_empty():
		out.append(foe.hero.uid)
		for u in foe.board:
			out.append(u.uid)
	return out


# ---------------------------------------------------------------- actions

func play_card(side: int, hand_uid: int, target_uid: int = -1, index: int = -1) -> bool:
	if not can_play(side, hand_uid):
		return false
	var s := sides[side]
	var c := hand_card(side, hand_uid)
	var card := CardDB.card(c.id)
	var tt := target_type(card)
	if tt != "":
		var valid := valid_targets(side, tt)
		if target_uid == -1 and card.type == "spell":
			return false
		if target_uid != -1 and not valid.has(target_uid):
			return false
	s.mana -= int(card.cost)
	s.hand.erase(c)
	var ruse := s.played > 0
	s.played += 1
	_emit({"t": "play", "side": side, "uid": hand_uid, "id": c.id, "type": card.type, "target": target_uid})
	_emit({"t": "mana", "side": side, "mana": s.mana, "max": s.max_mana})
	var source: Unit = null
	if card.type == "minion":
		source = _summon(side, c.id, index, hand_uid)
	var ruse_shown := false
	for e in card.get("effects", []):
		if winner != -1:
			break # an earlier effect ended the game: nothing may follow "game_over"
		if e.get("on", "play") == "play":
			if e.get("ruse", false):
				if not ruse:
					continue
				if not ruse_shown:
					ruse_shown = true
					# View hint: the Ruse goes off (a flash on the minion, or on the spell being cast).
					_emit({"t": "ruse", "side": side, "id": c.id, "uid": source.uid if source != null else -1})
			_resolve(e, side, source, target_uid, c.id)
			_cleanup()
	_cleanup()
	return true


func attack(side: int, attacker_uid: int, target_uid: int) -> bool:
	var a: Unit = units.get(attacker_uid)
	if not can_attack(a) or a.side != side or not attack_targets(side).has(target_uid):
		return false
	var t: Unit = units[target_uid]
	a.attacks_made += 1
	_emit({"t": "attack", "attacker": a.uid, "target": t.uid})
	var back := t.attack if not t.is_hero else 0
	_damage(t, a.attack, a)
	if back > 0:
		_damage(a, back, t)
	_cleanup()
	return true


func use_power(side: int, target_uid: int = -1) -> bool:
	if not can_use_power(side):
		return false
	var s := sides[side]
	var h := CardDB.hero(s.hero_id)
	var tt := power_target_type(h)
	if tt != "" and not valid_targets(side, tt).has(target_uid):
		return false
	s.mana -= int(h.power.cost)
	s.power_used = true
	_emit({"t": "power", "side": side, "target": target_uid})
	_emit({"t": "mana", "side": side, "mana": s.mana, "max": s.max_mana})
	for e in h.power.effects:
		_resolve(e, side, null, target_uid, "power_" + s.hero_id)
	_cleanup()
	return true


# ---------------------------------------------------------------- effects

func _summon(side: int, id: String, index: int = -1, from_card: int = -1) -> Unit:
	return _place(_new_unit(side, id), index, from_card)


## A minion of card `id` as printed, not on the board yet (no uid until `_place`).
func _new_unit(side: int, id: String) -> Unit:
	var card := CardDB.card(id)
	var u := Unit.new()
	u.id = id
	u.side = side
	u.attack = int(card.get("attack", 0))
	u.health = int(card.get("health", 1))
	u.max_health = u.health
	for k in card.get("keywords", []):
		u.keywords[k] = true
	u.wrath = int(card.get("wrath", 0))
	u.sleeping = not u.has("swift")
	return u


## Puts a new minion on its owner's board at `index` (the end when -1) and reports it with the values it enters with;
## null when the board is full.
func _place(u: Unit, index: int = -1, from_card: int = -1) -> Unit:
	var s := sides[u.side]
	if s.board.size() >= MAX_BOARD:
		return null
	u.uid = _uid()
	if index < 0 or index > s.board.size():
		index = s.board.size()
	s.board.insert(index, u)
	units[u.uid] = u
	_emit({"t": "summon", "side": u.side, "unit": u.snapshot(), "index": index, "from_card": from_card})
	return u


## A copy of minion `t` for `side`, the Hearthstone way: it keeps the original's current state (Attack, Health and
## max Health, so buffs, debuffs and damage; the keywords it has now, so a broken Ward or a used Rebirth stays gone;
## Silence; Freeze; its Wrath and the rage already in its Attack; a Frenzy already spent) but it is a new minion: asleep unless it has Swift, no attack made. A frozen copy is frozen
## while asleep, so it stays frozen through its owner's next turn (see `_freeze_spent`).
func _unit_copy(side: int, t: Unit) -> Unit:
	var u := _new_unit(side, t.id)
	u.attack = t.attack
	u.health = t.health
	u.max_health = t.max_health
	u.keywords = t.keywords.duplicate()
	u.frozen = t.frozen
	u.silenced = t.silenced
	u.wrath = t.wrath
	u.rage = t.rage
	u.frenzied = t.frenzied
	u.sleeping = not u.has("swift")
	return u


func _resolve(e: Dictionary, side: int, source: Unit, chosen: int, from_id: String) -> void:
	var ttype: String = e.get("target", "")
	var targets := _targets(ttype, side, source, chosen)
	var origin := source.uid if source != null else sides[side].hero.uid
	match e.do:
		"damage":
			if ttype.begins_with("choose_") or ttype.begins_with("random_") or ttype == "enemy_hero":
				for t in targets:
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "damage"})
			elif not targets.is_empty():
				_emit({"t": "aoe", "side": side, "id": from_id, "kind": "damage",
					"uids": targets.map(func(t): return t.uid)})
			for t in targets:
				_damage(t, int(e.amount), null, from_id)
		"heal":
			for t in targets:
				_heal(t, int(e.amount), from_id)
		"draw":
			draw(side, int(e.get("amount", 1)))
		"armor":
			for t in targets:
				t.armor += int(e.amount)
				_emit({"t": "armor", "uid": t.uid, "armor": t.armor, "src": from_id})
		"buff":
			if ttype.begins_with("choose_"):
				for t in targets:
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "buff"})
			for t in targets:
				t.attack += int(e.get("attack", 0))
				t.health += int(e.get("health", 0))
				t.max_health += int(e.get("health", 0))
				for k in e.get("keywords", []):
					t.keywords[k] = true
				# Gaining Swift wakes a minion that came into play this turn.
				if t.has("swift") and not t.is_hero and t.attacks_made == 0:
					t.sleeping = false
				_emit({"t": "buff", "uid": t.uid, "attack": t.attack, "health": t.health,
					"max_health": t.max_health, "keywords": t.keywords.keys(), "src": from_id})
				_update_wrath(t)
		"summon":
			var at := -1
			if source != null and sides[side].board.has(source):
				at = sides[side].board.find(source) + 1
			for i in int(e.get("count", 1)):
				var u := _summon(side, e.card, at)
				if u != null and at != -1:
					at += 1
		"bounce":
			for t in targets:
				if ttype.begins_with("choose_") and not t.is_hero:
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "bounce"})
				_bounce(t, from_id)
		"freeze":
			_emit_spread(ttype, side, targets, from_id, "freeze")
			for t in targets:
				if ttype.begins_with("choose_") or ttype.begins_with("random_"):
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "freeze"})
				t.frozen = true
				_emit_status(t)
		"silence":
			_emit_spread(ttype, side, targets, from_id, "silence")
			for t in targets:
				if t.is_hero:
					continue
				if ttype.begins_with("choose_") or ttype.begins_with("random_"):
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "silence"})
				t.keywords.clear()
				t.silenced = true
				t.wrath = 0 # Silence takes the Wrath away, and the bonus with it
				_update_wrath(t)
				_emit_status(t)
		"ramp":
			var rs := sides[side]
			rs.max_mana = mini(MAX_MANA, rs.max_mana + int(e.get("amount", 1)))
			_emit({"t": "mana", "side": side, "mana": rs.mana, "max": rs.max_mana})
		"mana":
			var ms := sides[side]
			ms.mana = mini(MAX_MANA, ms.mana + int(e.get("amount", 1)))
			_emit({"t": "mana", "side": side, "mana": ms.mana, "max": ms.max_mana})
		"give_card":
			var gs := sides[side]
			for i in int(e.get("count", 1)):
				if gs.hand.size() >= MAX_HAND:
					_burn_made(side, str(e.card))
					continue
				var gc := {"uid": _uid(), "id": e.card}
				gs.hand.append(gc)
				_emit({"t": "draw", "side": side, "uid": gc.uid, "id": e.card, "deck": gs.deck.size()})
		"destroy":
			for t in targets:
				_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "destroy"})
				t.dead = true
				_mark(t, from_id, "destroy")
		"copy":
			_copy(e, side, source, targets, ttype, from_id)
		"transform":
			for t in targets:
				if t.is_hero or t.dead:
					continue
				if ttype.begins_with("choose_") or ttype.begins_with("random_"):
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "silence"})
				_transform(t, str(e.card), from_id)
		"fight":
			# A brawl in the mud (Wrath class): each target fights each of the minions named by "with" ("self", the
			# minion that has the effect, by default), one pair at a time, until one of the pair is dead.
			var fighters := _targets(str(e.get("with", "self")), side, source, chosen)
			for t in targets:
				for f in fighters:
					_fight(f, t, from_id)


## Two minions deal damage equal to their Attack to each other at once (a fight is not an attack: it uses no attack
## and ignores Guard). Venom and Drain work as in combat; Ward blocks the hit. Heroes never fight.
func _fight(a: Unit, b: Unit, from_id: String) -> void:
	if a == null or b == null or a == b or a.is_hero or b.is_hero or a.dead or b.dead or a.health <= 0 \
			or b.health <= 0 or not units.has(a.uid) or not units.has(b.uid):
		return
	_emit({"t": "fight", "a": a.uid, "b": b.uid, "src": from_id}) # view hint: the two clash in the mud
	var to_b := a.attack # both blows land together: neither one's Wrath, set off by this fight, adds to it
	var to_a := b.attack
	_damage(b, to_b, a)
	_damage(a, to_a, b)


## Copies cards into your hand (or onto your board with "to": "board"). Source: "from" = "enemy_hand" / "enemy_deck"
## (random cards; with "steal" they leave the enemy instead), or else the effect's target minions. Hand limit applies.
## As in Hearthstone, a minion copied onto the board keeps its current state (`_unit_copy`: Capocchio), while a copy
## into the hand is the printed card (Forged Will, like Zola's copy: a card in hand has no damage or buffs here).
func _copy(e: Dictionary, side: int, source: Unit, targets: Array[Unit], ttype: String, from_id: String) -> void:
	var me := sides[side]
	var foe := sides[1 - side]
	var from: String = e.get("from", "")
	var steal: bool = e.get("steal", false)
	var ids: Array[String] = []
	var minions: Array[Unit] = [] ## the copied minions when the copy is of target minions (same order as `ids`)
	if from == "enemy_hand" or from == "enemy_deck":
		# "Copy 2 random cards": two different cards (positions) of the hand or deck, never one card twice.
		var pool: Array[int] = []
		if not steal:
			for k in (foe.hand.size() if from == "enemy_hand" else foe.deck.size()):
				pool.append(k)
		for i in int(e.get("count", 1)):
			# Nothing is stolen without room for it: the cards taken so far are not in the hand yet.
			if steal and me.hand.size() + ids.size() >= MAX_HAND:
				break
			if from == "enemy_hand":
				if steal:
					if foe.hand.is_empty():
						break
					var k := rng.randi_range(0, foe.hand.size() - 1)
					var hc: Dictionary = foe.hand[k]
					foe.hand.remove_at(k)
					_emit({"t": "steal", "side": side, "from": 1 - side, "uid": hc.uid, "id": hc.id, "zone": "hand"})
					ids.append(str(hc.id))
				else:
					if pool.is_empty():
						break
					ids.append(str(foe.hand[pool.pop_at(rng.randi_range(0, pool.size() - 1))].id))
			else:
				if steal:
					if foe.deck.is_empty():
						break
					var top: String = foe.deck.pop_back()
					ids.append(top)
					_emit({"t": "steal", "side": side, "from": 1 - side, "uid": -1, "id": top, "zone": "deck",
						"deck": foe.deck.size()})
				else:
					if pool.is_empty():
						break
					ids.append(foe.deck[pool.pop_at(rng.randi_range(0, pool.size() - 1))])
	else:
		for t in targets:
			if not t.is_hero:
				if ttype.begins_with("choose_"):
					_emit({"t": "projectile", "from": source.uid if source != null else me.hero.uid, "to": t.uid,
						"id": from_id, "kind": "buff"})
				ids.append(t.id)
				minions.append(t)
	if e.get("to", "hand") == "board":
		var at := -1
		if source != null and me.board.has(source):
			at = me.board.find(source) + 1
		for i in ids.size():
			if CardDB.card(ids[i]).get("type", "") != "minion":
				continue
			# A minion on the board is copied as it is now (`_unit_copy`); a card from a hand or deck as printed.
			var u := _place(_unit_copy(side, minions[i]) if i < minions.size() else _new_unit(side, ids[i]), at)
			if u == null:
				continue
			if u.frozen or u.silenced:
				_emit_status(u) # the view builds a minion from its numbers and keywords; this shows the rest
			if at != -1:
				at += 1
		return
	for id in ids:
		if me.hand.size() >= MAX_HAND:
			_burn_made(side, id) # a copy (never a stolen card: nothing is stolen into a full hand) burns
			continue
		var gc := {"uid": _uid(), "id": id}
		me.hand.append(gc)
		# View hint first (where the copy comes from), then the usual card-to-hand event.
		_emit({"t": "copy", "side": side, "id": id, "src": from_id, "from": from if from != "" else "board"})
		_emit({"t": "draw", "side": side, "uid": gc.uid, "id": id, "deck": me.deck.size()})


## Turns a minion into another card (Circe's swine): it leaves without a Last Breath and the new minion takes its
## place, with the new card's printed stats and keywords. Ward does not stop it.
func _transform(t: Unit, into: String, from_id: String) -> void:
	var owner := sides[t.side]
	var idx := owner.board.find(t)
	if idx == -1 or CardDB.card(into).is_empty():
		return
	_emit({"t": "transform", "uid": t.uid, "side": t.side, "into": into, "src": from_id}) # view hint
	owner.board.erase(t)
	units.erase(t.uid)
	t.dead = true
	_mark(t, from_id, "transform")
	_emit_death(t)
	_summon(t.side, into, idx) # a fresh minion: it cannot attack this turn unless it has Swift


## A board-wide freeze or silence: one "aoe" event so the view can show it sweeping over every target (only a
## view hint; the units' new state follows in their "status" events).
func _emit_spread(ttype: String, side: int, targets: Array[Unit], from_id: String, kind: String) -> void:
	if targets.is_empty() or ttype.begins_with("choose_") or ttype.begins_with("random_"):
		return
	_emit({"t": "aoe", "side": side, "id": from_id, "kind": kind, "uids": targets.map(func(t): return t.uid)})


func _targets(ttype: String, side: int, source: Unit, chosen: int) -> Array[Unit]:
	var out: Array[Unit] = []
	var me := sides[side]
	var foe := sides[1 - side]
	if ttype.begins_with("choose_"):
		if units.has(chosen) and valid_targets(side, ttype).has(chosen):
			out.append(units[chosen])
		return out
	match ttype:
		"own_hero":
			out.append(me.hero)
		"enemy_hero":
			out.append(foe.hero)
		"all_enemy_minions":
			out.assign(foe.board.filter(func(u): return not u.dead))
		"all_minions":
			out.assign((me.board + foe.board).filter(func(u): return not u.dead))
		"all_other_minions":
			out.assign((me.board + foe.board).filter(func(u): return u != source and not u.dead))
		"other_friendly_minions":
			out.assign(me.board.filter(func(u): return u != source and not u.dead))
		"random_enemy_minion":
			var alive := foe.board.filter(func(u): return not u.dead)
			if not alive.is_empty():
				out.append(alive[rng.randi_range(0, alive.size() - 1)])
		"random_enemy":
			var pool: Array = foe.board.filter(func(u): return not u.dead)
			pool.append(foe.hero)
			out.append(pool[rng.randi_range(0, pool.size() - 1)])
		"random_friendly_minion":
			var mine: Array = me.board.filter(func(u): return not u.dead and u != source)
			if not mine.is_empty():
				out.append(mine[rng.randi_range(0, mine.size() - 1)])
		"all_enemies":
			out.assign(foe.board.filter(func(u): return not u.dead))
			out.append(foe.hero)
		"all_friendly_minions":
			out.assign(me.board.filter(func(u): return not u.dead))
		"self":
			if source != null and not source.dead:
				out.append(source)
	return out


## `src` is the card or power behind effect damage (view only: it picks the hit's look).
func _damage(t: Unit, amount: int, source: Unit, src: String = "") -> int:
	if amount <= 0 or t == null:
		return 0
	if t.has("ward"):
		t.keywords.erase("ward")
		_emit({"t": "ward_break", "uid": t.uid})
		return 0
	var to_hp := amount
	if t.armor > 0:
		var soak := mini(t.armor, amount)
		t.armor -= soak
		to_hp -= soak
	t.health -= to_hp
	if to_hp > 0:
		if source != null:
			_mark(t, source.id, "attack", source.uid)
		elif src != "":
			_mark(t, src, "effect")
		else:
			_mark(t, "fatigue", "fatigue") # the only damage with neither a unit nor a card behind it
	_emit({"t": "damage", "uid": t.uid, "amount": amount, "hp": t.health, "armor": t.armor,
		"source": source.uid if source != null else -1, "src": src})
	if source != null:
		if source.has("venom") and not t.is_hero and t.health > 0:
			t.dead = true
			_mark(t, source.id, "venom", source.uid)
			_emit({"t": "venom", "uid": t.uid, "source": source.uid})
		if source.has("drain"):
			_heal(sides[source.side].hero, amount, "drain")
	if not t.is_hero:
		_hurt(t)
	return amount


func _heal(t: Unit, amount: int, src: String = "") -> void:
	var real := mini(amount, t.max_health - t.health)
	if real <= 0:
		return
	t.health += real
	_emit({"t": "heal", "uid": t.uid, "amount": real, "hp": t.health, "src": src})
	_update_wrath(t)


# ---------------------------------------------------------------- Wrath and Frenzy (Filippo Argenti's class)

var _frenzy_queue: Array[Unit] = [] ## minions whose Frenzy goes off at the next cleanup


## A minion took damage and is still standing: its Wrath wakes, and its Frenzy (once) is queued for the cleanup,
## so it fires after the blow that set it off has fully resolved.
func _hurt(t: Unit) -> void:
	if t.dead or t.health <= 0:
		return
	_update_wrath(t)
	if t.frenzied or t.silenced:
		return
	if CardDB.card(t.id).get("effects", []).any(func(e): return e.get("on", "") == "frenzy"):
		t.frenzied = true
		_frenzy_queue.append(t)


## Wrath: while a minion with Wrath is damaged (health below its max), its Attack includes the bonus; healed to full,
## silenced or buffed back to full health, it loses it. A dying minion keeps what it has (it is leaving anyway).
func _update_wrath(u: Unit) -> void:
	if u == null or u.is_hero or u.dead or u.health <= 0:
		return
	var want := u.wrath if u.health < u.max_health else 0
	if want == u.rage:
		return
	u.attack += want - u.rage
	u.rage = want
	_emit({"t": "wrath", "uid": u.uid, "on": want > 0, "attack": u.attack})


## Every minion's Wrath brought up to date after a cleanup (deaths, heals and buffs all move Health against max Health).
func _refresh_wrath() -> void:
	for s in sides:
		for u in s.board:
			_update_wrath(u)


## Resolves the queued Frenzies, oldest first. A minion that died, left the board or was silenced since does nothing.
func _fire_frenzies() -> void:
	while not _frenzy_queue.is_empty() and winner == -1:
		var u: Unit = _frenzy_queue.pop_front()
		if u.dead or u.silenced or u.health <= 0 or not sides[u.side].board.has(u):
			continue
		_emit({"t": "frenzy", "uid": u.uid}) # view hint: the minion flares up before its effect
		for e in CardDB.card(u.id).get("effects", []):
			if e.get("on", "") == "frenzy" and winner == -1:
				_resolve(e, u.side, u, -1, u.id)
		_cleanup()


func _bounce(t: Unit, from_id: String = "") -> void:
	if t.is_hero:
		return
	var owner := sides[t.side]
	owner.board.erase(t)
	units.erase(t.uid)
	if owner.hand.size() >= MAX_HAND:
		_mark(t, from_id, "bounce") # no room in the hand: it is lost, to the card that sent it back
		_emit_death(t)
		return
	var c := {"uid": _uid(), "id": t.id}
	owner.hand.append(c)
	_emit({"t": "bounce", "uid": t.uid, "side": t.side, "card_uid": c.uid, "id": t.id})


## Removes dead minions (in board order), fires their Last Breath effects, and repeats until stable.
func _cleanup() -> void:
	var guard := 0
	while guard < 20:
		guard += 1
		var died: Array = []
		for i in [current, 1 - current]:
			var s := sides[i]
			for u in s.board:
				if u.health <= 0 or u.dead:
					died.append([u, s.board.find(u)])
		if died.is_empty():
			break
		for d in died:
			var u: Unit = d[0]
			u.dead = true
			sides[u.side].board.erase(u)
			units.erase(u.uid)
			_emit_death(u)
		for d in died:
			var u: Unit = d[0]
			# Silence already took the keyword away; one given back afterwards (Absolved in Advance) still works.
			# Like Hearthstone's Reborn it comes back as a fresh minion with 1 Health and 1 max Health (not a damaged
			# one: healing cannot raise it), its printed Attack and keywords minus Rebirth, no buffs.
			if u.has("rebirth"):
				var r := _new_unit(u.side, u.id)
				r.keywords.erase("rebirth")
				r.health = 1
				r.max_health = 1
				if _place(r, mini(int(d[1]), sides[u.side].board.size())) != null:
					_emit({"t": "rebirth", "uid": r.uid}) # view only: the rising flame
			_last_breath(u, int(d[1]))
	_check_end()
	_refresh_wrath()
	_fire_frenzies()


## Resolves the Last Breath effects of minion `u`, which died at board index `at` (a silenced one has none). Called
## once per death in `_cleanup`; a minion that leaves by transform or a bounce into a full hand never gets here.
func _last_breath(u: Unit, at: int) -> void:
	if u.silenced:
		return
	for e in CardDB.card(u.id).get("effects", []):
		if e.get("on", "") == "death":
			if e.do == "summon":
				var i0 := mini(at, sides[u.side].board.size())
				for i in int(e.get("count", 1)):
					if _summon(u.side, e.card, i0) != null:
						i0 += 1
			else:
				_resolve(e, u.side, null, -1, u.id)


## Records the blow that would kill `t` (view only, see Unit.killer): the last one wins, so with several hits at
## once the death follows the one that landed last.
static func _mark(t: Unit, id: String, how: String, by: int = -1) -> void:
	t.killer = id
	t.kill_how = how
	t.kill_by = by


## The killer fields of a death or a fallen hero: `killer` (card id, "power_<hero>" or "fatigue"), `how`, `by`
## (uid of the striking unit, or -1). A unit nothing has marked is explicitly sourceless: killer "", how "none".
static func _kill_info(u: Unit) -> Dictionary:
	if u.killer == "":
		return {"uid": u.uid, "killer": "", "how": "none", "by": -1}
	return {"uid": u.uid, "killer": u.killer, "how": u.kill_how, "by": u.kill_by}


## The "death" event. Its killer fields are a view hint only (the look of the death).
func _emit_death(u: Unit) -> void:
	var ev := _kill_info(u)
	ev.t = "death"
	ev.side = u.side
	_emit(ev)


func _check_end() -> void:
	if winner != -1:
		return
	var d0 := sides[0].hero.health <= 0
	var d1 := sides[1].hero.health <= 0
	if d0 or d1:
		winner = 2 if (d0 and d1) else (1 if d0 else 0)
		# View only: the fallen heroes and what struck each last blow (hero uids are the same on both online clients).
		var fallen := []
		for s in sides:
			if s.hero.health <= 0:
				fallen.append(_kill_info(s.hero))
		_emit({"t": "game_over", "winner": winner, "fallen": fallen})
