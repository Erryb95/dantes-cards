class_name BattleAI
extends RefCounted
## The opponent: returns one action at a time so the view can animate between steps.
## Action: {"do": "play", "uid", "target", "index"} | {"do": "attack", "attacker", "target"} |
##         {"do": "power", "target"} | {"do": "end"}
## Levels: EASY follows fixed rules (the most expensive card first, simple trades); NORMAL tries every legal move
## on a copy of the battle, then plays the best few out to the end of the turn and keeps the line that leaves the
## best position (see `evaluate`). It reads only what a player could see: its own hand, the board, counts.

enum Level { EASY, NORMAL }

const ROLLOUTS := 8 ## candidate first moves that get played out to the end of the turn

var side := 1
var level := Level.NORMAL
var abort := false ## set from the main thread to stop a search early (the battle is closing)
var _seed := 0 ## seeds each simulated copy, so the worker thread never touches the global RNG


func _init(p_side: int = 1, p_level: Level = Level.NORMAL) -> void:
	side = p_side
	level = p_level


func next_action(st: BattleState) -> Dictionary:
	if st.winner != -1 or st.current != side:
		return {"do": "end"}
	if level == Level.NORMAL:
		_seed = int(st.rng.state)
		return _search(st)
	return _rules(st)


# ---------------------------------------------------------------- search

## Every legal move right now (end turn excluded).
func _moves(st: BattleState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := st.sides[side]
	for c in me.hand:
		if not st.can_play(side, c.uid):
			continue
		var card := CardDB.card(c.id)
		var tt := BattleState.target_type(card)
		var targets := st.valid_targets(side, tt) if tt != "" else ([] as Array[int])
		if targets.is_empty():
			out.append({"do": "play", "uid": c.uid, "target": -1, "index": -1})
		for t in targets:
			out.append({"do": "play", "uid": c.uid, "target": t, "index": -1})
	for u in me.board:
		if st.can_attack(u):
			for t in st.attack_targets(side):
				out.append({"do": "attack", "attacker": u.uid, "target": t})
	if st.can_use_power(side):
		var tt := BattleState.power_target_type(CardDB.hero(me.hero_id))
		if tt == "":
			out.append({"do": "power", "target": -1})
		else:
			for t in st.valid_targets(side, tt):
				out.append({"do": "power", "target": t})
	return out


static func apply(st: BattleState, side: int, m: Dictionary) -> bool:
	match m.do:
		"play":
			return st.play_card(side, m.uid, m.target, m.index)
		"attack":
			return st.attack(side, m.attacker, m.target)
		"power":
			return st.use_power(side, m.target)
	return false


## Scores each move one step ahead, plays the best few out greedily to the end of the turn, and returns the first
## move of the best line, or "end" when no line beats passing.
func _search(st: BattleState) -> Dictionary:
	var base := evaluate(st)
	var scored := []
	for m in _moves(st):
		if abort:
			return {"do": "end"}
		var b := _copy(st)
		if not apply(b, side, m):
			continue
		if b.winner == side:
			return m
		scored.append([evaluate(b), m, b])
	if scored.is_empty():
		return {"do": "end"}
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var best: Dictionary = {}
	var best_v := base + 0.25
	for i in mini(ROLLOUTS, scored.size()):
		var v := _rollout(scored[i][2])
		if v > best_v:
			best_v = v
			best = scored[i][1]
	return best if not best.is_empty() else {"do": "end"}


func _copy(st: BattleState) -> BattleState:
	_seed += 1
	return st.clone(_seed)


## Greedy continuation: keep taking the best one-step move until none improves the position.
func _rollout(st: BattleState) -> float:
	var cur := evaluate(st)
	for step in 12:
		if st.winner != -1 or abort:
			break
		var next: BattleState = null
		var next_v := cur + 0.25
		for m in _moves(st):
			var b := _copy(st)
			if not apply(b, side, m):
				continue
			var v := evaluate(b)
			if v > next_v:
				next_v = v
				next = b
		if next == null:
			break
		st = next
		cur = next_v
	return cur


## How good the position is for this AI. Heroes count more as they get low; minions by stats and abilities;
## cards in hand as options; and a heavy penalty when the enemy board can kill us next turn.
func evaluate(st: BattleState) -> float:
	if st.winner == side:
		return 100000.0
	if st.winner == 1 - side:
		return -100000.0
	var me := st.sides[side]
	var foe := st.sides[1 - side]
	var v := _hero_value(me.hero) - _hero_value(foe.hero)
	var my_power := 0
	for u in me.board:
		v += _unit_value(u)
		my_power += u.attack
	var their_hit := 0
	var guards := 0
	for u in foe.board:
		v -= _unit_value(u)
		if not u.frozen:
			their_hit += u.attack
	for u in me.board:
		if u.has("guard"):
			guards += u.health
	v += 2.5 * mini(me.hand.size(), 8) - 2.5 * mini(foe.hand.size(), 8)
	# Danger: what reaches my face next turn (guards soak some of it).
	var reach := maxi(0, their_hit - guards)
	if reach >= me.hero.health + me.hero.armor:
		v -= 60.0
	# Pressure: our board threatens lethal next turn.
	var their_guards := foe.board.filter(func(u): return u.has("guard")).size()
	if their_guards == 0 and my_power >= foe.hero.health + foe.hero.armor:
		v += 25.0
	return v


func _hero_value(h) -> float:
	var hp := float(h.health + h.armor)
	# Each point matters more when low: 30 hp ~ 30, 10 hp ~ 14.5 short of linear.
	return hp + 12.0 * (1.0 - exp(-hp / 6.0)) * 2.0


func _unit_value(u) -> float:
	var v: float = 1.3 * u.attack + 1.0 * u.health + 1.0
	if u.has("guard"):
		v += 1.0 + 0.3 * u.health
	if u.has("ward"):
		v += 0.8 * u.attack + 1.0
	if u.has("venom"):
		v += 2.5
	if u.has("drain"):
		v += 0.6 * u.attack
	if not u.silenced:
		for e in CardDB.card(u.id).get("effects", []):
			if e.get("on", "play") != "play":
				v += 2.0
	if u.frozen:
		v -= 0.5 * u.attack
	return v


# ---------------------------------------------------------------- rules (Easy)

func _rules(st: BattleState) -> Dictionary:
	var me := st.sides[side]
	var foe := st.sides[1 - side]

	# 1. Lethal: everything to the face when it is enough.
	var face_dmg := 0
	var guards := foe.board.filter(func(u): return u.has("guard"))
	if guards.is_empty():
		for u in me.board:
			if st.can_attack(u):
				face_dmg += u.attack
	if face_dmg >= foe.hero.health + foe.hero.armor:
		for u in me.board:
			if st.can_attack(u):
				return {"do": "attack", "attacker": u.uid, "target": foe.hero.uid}

	# 2. Cards: the most expensive useful play first.
	var best := {}
	var best_score := -INF
	for c in me.hand:
		if not st.can_play(side, c.uid):
			continue
		var plan := _plan_card(st, c)
		if plan.is_empty():
			continue
		if plan.score > best_score:
			best_score = plan.score
			best = plan
	if not best.is_empty():
		return {"do": "play", "uid": best.uid, "target": best.target, "index": -1}

	# 3. Hero power with spare mana.
	if st.can_use_power(side):
		var tt := BattleState.power_target_type(CardDB.hero(me.hero_id))
		if tt == "":
			return {"do": "power", "target": -1}
		var t := _best_damage_target(st, 1, tt, true)
		if t != -1:
			return {"do": "power", "target": t}

	# 4. Attacks: kill guards, take good trades, otherwise go face.
	for u in me.board:
		if not st.can_attack(u):
			continue
		var targets := st.attack_targets(side)
		return {"do": "attack", "attacker": u.uid, "target": _attack_choice(st, u, targets)}
	return {"do": "end"}


## Opening hand: throw back anything that costs 4 or more.
func mulligan_choice(st: BattleState) -> Array:
	var out := []
	for c in st.sides[side].hand:
		if int(CardDB.card(c.id).cost) >= 4:
			out.append(c.uid)
	return out


func _value(u) -> float:
	return u.attack * 1.2 + u.health + (2.0 if u.has("guard") else 0.0) + (2.0 if u.has("ward") else 0.0) \
		+ (1.5 if u.has("venom") else 0.0)


func _plan_card(st: BattleState, c: Dictionary) -> Dictionary:
	var me := st.sides[side]
	var foe := st.sides[1 - side]
	var card := CardDB.card(c.id)
	var score := float(card.cost) * 10.0
	var target := -1
	var tt := BattleState.target_type(card)
	for e in card.get("effects", []):
		if e.get("on", "play") != "play":
			continue
		match e.do:
			"damage":
				if tt != "":
					target = _best_damage_target(st, int(e.amount), tt, card.type == "minion")
					if target == -1 and card.type == "spell":
						return {}
				elif e.target == "all_enemy_minions":
					if card.type == "spell" and foe.board.size() < 2:
						return {}
				elif e.target == "all_minions":
					var mine := 0.0
					var theirs := 0.0
					for u in me.board:
						mine += _value(u) if u.health <= int(e.amount) else 0.0
					for u in foe.board:
						theirs += _value(u) if u.health <= int(e.amount) else 0.0
					if theirs < mine + 6.0:
						return {}
			"buff":
				if tt != "":
					target = _best_friend(st)
					if target == -1 and card.type == "spell":
						return {}
				elif e.target == "other_friendly_minions" and me.board.size() < 2:
					score -= 15.0
			"bounce":
				var best := -1
				var best_cost := 2
				for u in foe.board:
					if int(CardDB.card(u.id).cost) > best_cost:
						best_cost = int(CardDB.card(u.id).cost)
						best = u.uid
				if best == -1:
					return {}
				target = best
			"mana":
				# Charon's Obol: only when the extra crystal unlocks a card that is not playable now.
				var unlock := 0
				for o in me.hand:
					var oc := CardDB.card(o.id)
					if o.uid != c.uid and int(oc.cost) == me.mana + int(e.amount):
						unlock = maxi(unlock, int(oc.cost))
				if unlock == 0:
					return {}
				score = unlock * 10.0 - 1.0
			"summon":
				if card.type == "spell" and me.board.size() >= BattleState.MAX_BOARD:
					return {}
			"heal":
				if card.type == "spell" and (me.hand.size() >= 9
						or e.get("target", "") == "own_hero" and me.hero.max_health - me.hero.health < int(e.amount)):
					return {}
			"freeze":
				if tt != "":
					target = _best_freeze(st)
					if target == -1 and card.type == "spell":
						return {}
				elif card.type == "spell" and e.target in ["all_enemy_minions", "all_enemies"]:
					var threat := 0
					for u in foe.board:
						threat += u.attack
					if threat < 5:
						return {}
			"silence":
				if tt != "":
					target = _best_silence(st)
					if target == -1 and card.type == "spell":
						return {}
				elif card.type == "spell" and e.target == "all_enemy_minions":
					var worth := 0.0
					for u in foe.board:
						worth += _silence_value(u)
					if worth < 6.0:
						return {}
	if tt != "" and target == -1:
		if tt.contains("friendly"):
			target = _best_friend(st)
		else:
			target = _best_damage_target(st, 0, tt, card.type == "minion")
		if target == -1 and card.type == "spell":
			return {}
	return {"uid": c.uid, "target": target, "score": score}


## Prefers enemy minions that die to `amount`, the biggest first; falls back to the enemy hero when allowed.
func _best_damage_target(st: BattleState, amount: int, tt: String, optional: bool) -> int:
	var valid := st.valid_targets(side, tt)
	var foe := st.sides[1 - side]
	var best := -1
	var best_v := -INF
	for u in foe.board:
		if not valid.has(u.uid):
			continue
		var v := _value(u)
		if u.has("ward"):
			v = 1.0
		elif u.health <= amount:
			v += 10.0
		else:
			v -= 6.0
		if v > best_v:
			best_v = v
			best = u.uid
	if best != -1 and best_v > 0.0:
		return best
	if valid.has(foe.hero.uid):
		return foe.hero.uid
	return best if not optional else -1


## The enemy minion most worth freezing: the hardest hitter, if it hits hard enough to matter.
func _best_freeze(st: BattleState) -> int:
	var best := -1
	var best_a := 2
	for u in st.sides[1 - side].board:
		if not u.frozen and u.attack > best_a:
			best_a = u.attack
			best = u.uid
	return best


## How much a minion loses when silenced (keywords, card effects, buffs above its printed stats).
func _silence_value(u) -> float:
	if u.silenced:
		return 0.0
	var c := CardDB.card(u.id)
	var v: float = 2.0 * u.keywords.size() + 3.0 * c.get("effects", []).size()
	v += maxf(0.0, u.attack - int(c.get("attack", 0))) + maxf(0.0, u.max_health - int(c.get("health", 0)))
	return v


func _best_silence(st: BattleState) -> int:
	var best := -1
	var best_v := 2.5
	for u in st.sides[1 - side].board:
		var v: float = _silence_value(u)
		if v > best_v:
			best_v = v
			best = u.uid
	return best


func _best_friend(st: BattleState) -> int:
	var best := -1
	var best_v := -INF
	for u in st.sides[side].board:
		var v := _value(u)
		if v > best_v:
			best_v = v
			best = u.uid
	return best


func _attack_choice(st: BattleState, a, targets: Array[int]) -> int:
	var foe := st.sides[1 - side]
	var best := -1
	var best_v := -INF
	for uid in targets:
		var t = st.units[uid]
		if t.is_hero:
			continue
		var kills: bool = (a.attack >= t.health or a.has("venom")) and not t.has("ward")
		var survives: bool = (t.attack < a.health and not t.has("venom")) or a.has("ward")
		var v := -INF
		if kills and survives:
			v = 20.0 + _value(t)
		elif kills and _value(t) >= _value(a):
			v = 10.0 + _value(t) - _value(a)
		elif t.has("ward") and survives:
			v = 6.0
		elif t.has("venom") and kills:
			v = 8.0
		elif t.has("guard"):
			v = 1.0 + _value(t) * 0.1
		if v > best_v:
			best_v = v
			best = uid
	if targets.has(foe.hero.uid) and best_v < 10.0:
		return foe.hero.uid
	return best if best != -1 else targets[0]
