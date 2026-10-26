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

	func has(k: String) -> bool:
		return keywords.has(k)

	func snapshot() -> Dictionary:
		return {"uid": uid, "id": id, "side": side, "is_hero": is_hero, "attack": attack, "health": health,
			"max_health": max_health, "armor": armor, "keywords": keywords.keys(), "sleeping": sleeping,
			"frozen": frozen, "silenced": silenced}


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


var sides: Array[SideState] = []
var current := 0
var turn := 0
var winner := -1 ## -1 running, 0 / 1 that side won, 2 draw
var rng := RandomNumberGenerator.new()
var units := {} ## uid -> Unit, heroes and minions in play
var _next_uid := 10


# ---------------------------------------------------------------- setup

## With wait_mulligan the opening hands are dealt and the game waits for finish_mulligan() from both sides.
## `first`: the side that takes the first turn (-1 = coin flip); the other side opens with one more card and
## Charon's Obol after the mulligan.
func start(deck_a: Array[String], hero_a: String, deck_b: Array[String], hero_b: String, seed_value: int = 0,
		wait_mulligan: bool = false, first: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	sides.clear()
	for i in 2:
		var s := SideState.new()
		s.hero_id = hero_a if i == 0 else hero_b
		s.deck = (deck_a if i == 0 else deck_b).duplicate()
		_shuffle(s.deck)
		var h := Unit.new()
		h.uid = HERO_UIDS[i]
		h.id = s.hero_id
		h.side = i
		h.is_hero = true
		h.health = int(CardDB.hero(s.hero_id).get("health", 30))
		h.max_health = h.health
		s.hero = h
		units[h.uid] = h
		sides.append(s)
	_emit({"t": "start", "heroes": [sides[0].hero.snapshot(), sides[1].hero.snapshot()],
		"decks": [sides[0].deck.size(), sides[1].deck.size()]})
	if wait_mulligan:
		_emit({"t": "mulligan_begin"})
	current = first if first != -1 else rng.randi() % 2
	_emit({"t": "first", "side": current})
	for i in 2:
		draw(i, START_HAND[0] if i == current else START_HAND[1])
	if wait_mulligan:
		_mulligan_pending = [true, true]
		_emit({"t": "mulligan_wait"})
	else:
		_give_coin()
		_begin_turn()


const COIN := "obol_coin"


func _give_coin() -> void:
	_resolve({"do": "give_card", "card": COIN, "count": 1}, 1 - current, null, -1, "coin")


var _mulligan_pending := [false, false]


func in_mulligan() -> bool:
	return _mulligan_pending[0] or _mulligan_pending[1]


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
	if winner != -1:
		return
	_fire_turn_triggers(current, "turn_end")
	if winner != -1:
		return
	# Frozen minions thaw at the end of their owner's turn.
	for u in sides[current].board:
		if u.frozen:
			u.frozen = false
			_emit_status(u)
	_emit({"t": "turn_end", "side": current})
	current = 1 - current
	if turn >= TURN_LIMIT:
		winner = 2
		_emit({"t": "game_over", "winner": 2})
		return
	_begin_turn()


func _fire_turn_triggers(side: int, trigger: String) -> void:
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


func _uid() -> int:
	_next_uid += 1
	return _next_uid


# ---------------------------------------------------------------- queries

func hand_card(side: int, hand_uid: int) -> Dictionary:
	for c in sides[side].hand:
		if c.uid == hand_uid:
			return c
	return {}


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
	if winner != -1 or side != current:
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
	if winner != -1 or side != current or sides[side].power_used:
		return false
	var h := CardDB.hero(sides[side].hero_id)
	if int(h.power.cost) > sides[side].mana:
		return false
	var tt := power_target_type(h)
	return tt == "" or not valid_targets(side, tt).is_empty()


func can_attack(u: Unit) -> bool:
	return u != null and not u.is_hero and not u.dead and u.side == current and winner == -1 \
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
	_emit({"t": "play", "side": side, "uid": hand_uid, "id": c.id, "type": card.type, "target": target_uid})
	_emit({"t": "mana", "side": side, "mana": s.mana, "max": s.max_mana})
	var source: Unit = null
	if card.type == "minion":
		source = _summon(side, c.id, index, hand_uid)
	for e in card.get("effects", []):
		if e.get("on", "play") == "play":
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
	var s := sides[side]
	if s.board.size() >= MAX_BOARD:
		return null
	var card := CardDB.card(id)
	var u := Unit.new()
	u.uid = _uid()
	u.id = id
	u.side = side
	u.attack = int(card.get("attack", 0))
	u.health = int(card.get("health", 1))
	u.max_health = u.health
	for k in card.get("keywords", []):
		u.keywords[k] = true
	u.sleeping = not u.has("swift")
	if index < 0 or index > s.board.size():
		index = s.board.size()
	s.board.insert(index, u)
	units[u.uid] = u
	_emit({"t": "summon", "side": side, "unit": u.snapshot(), "index": index, "from_card": from_card})
	return u


func _resolve(e: Dictionary, side: int, source: Unit, chosen: int, from_id: String) -> void:
	var ttype: String = e.get("target", "")
	var targets := _targets(ttype, side, source, chosen)
	var origin := source.uid if source != null else sides[side].hero.uid
	match e.do:
		"damage":
			if ttype.begins_with("choose_") or ttype.begins_with("random_"):
				for t in targets:
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "damage"})
			elif not targets.is_empty():
				_emit({"t": "aoe", "side": side, "id": from_id, "uids": targets.map(func(t): return t.uid)})
			for t in targets:
				_damage(t, int(e.amount), null)
		"heal":
			for t in targets:
				_heal(t, int(e.amount))
		"draw":
			draw(side, int(e.get("amount", 1)))
		"armor":
			for t in targets:
				t.armor += int(e.amount)
				_emit({"t": "armor", "uid": t.uid, "armor": t.armor})
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
				_emit({"t": "buff", "uid": t.uid, "attack": t.attack, "health": t.health,
					"max_health": t.max_health, "keywords": t.keywords.keys()})
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
				_bounce(t)
		"freeze":
			for t in targets:
				if ttype.begins_with("choose_"):
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "freeze"})
				t.frozen = true
				_emit_status(t)
		"silence":
			for t in targets:
				if t.is_hero:
					continue
				if ttype.begins_with("choose_"):
					_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "silence"})
				t.keywords.clear()
				t.silenced = true
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
					break
				var gc := {"uid": _uid(), "id": e.card}
				gs.hand.append(gc)
				_emit({"t": "draw", "side": side, "uid": gc.uid, "id": e.card, "deck": gs.deck.size()})
		"destroy":
			for t in targets:
				_emit({"t": "projectile", "from": origin, "to": t.uid, "id": from_id, "kind": "destroy"})
				t.dead = true


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


func _damage(t: Unit, amount: int, source: Unit) -> int:
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
	_emit({"t": "damage", "uid": t.uid, "amount": amount, "hp": t.health, "armor": t.armor,
		"source": source.uid if source != null else -1})
	if source != null:
		if source.has("venom") and not t.is_hero and t.health > 0:
			t.dead = true
			_emit({"t": "venom", "uid": t.uid, "source": source.uid})
		if source.has("drain"):
			_heal(sides[source.side].hero, amount)
	return amount


func _heal(t: Unit, amount: int) -> void:
	var real := mini(amount, t.max_health - t.health)
	if real <= 0:
		return
	t.health += real
	_emit({"t": "heal", "uid": t.uid, "amount": real, "hp": t.health})


func _bounce(t: Unit) -> void:
	if t.is_hero:
		return
	var owner := sides[t.side]
	owner.board.erase(t)
	units.erase(t.uid)
	if owner.hand.size() >= MAX_HAND:
		_emit({"t": "death", "uid": t.uid, "side": t.side})
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
			_emit({"t": "death", "uid": u.uid, "side": u.side})
		for d in died:
			var u: Unit = d[0]
			if u.has("rebirth") and not u.silenced:
				var r := _summon(u.side, u.id, mini(int(d[1]), sides[u.side].board.size()))
				if r != null:
					r.keywords.erase("rebirth")
					r.health = 1
					_emit_status(r)
			if u.silenced:
				continue
			for e in CardDB.card(u.id).get("effects", []):
				if e.get("on", "") == "death":
					if e.do == "summon":
						var at := mini(int(d[1]), sides[u.side].board.size())
						for i in int(e.get("count", 1)):
							if _summon(u.side, e.card, at) != null:
								at += 1
					else:
						_resolve(e, u.side, null, -1, u.id)
	_check_end()


func _check_end() -> void:
	if winner != -1:
		return
	var d0 := sides[0].hero.health <= 0
	var d1 := sides[1].hero.health <= 0
	if d0 or d1:
		winner = 2 if (d0 and d1) else (1 if d0 else 0)
		_emit({"t": "game_over", "winner": winner})
