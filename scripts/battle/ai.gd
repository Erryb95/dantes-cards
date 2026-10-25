class_name BattleAI
extends RefCounted
## Greedy opponent: returns one action at a time so the view can animate between steps.
## Action: {"do": "play", "uid", "target", "index"} | {"do": "attack", "attacker", "target"} |
##         {"do": "power", "target"} | {"do": "end"}

var side := 1


func _init(p_side: int = 1) -> void:
	side = p_side


func next_action(st: BattleState) -> Dictionary:
	if st.winner != -1 or st.current != side:
		return {"do": "end"}
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
			"summon":
				if card.type == "spell" and me.board.size() >= BattleState.MAX_BOARD:
					return {}
			"heal":
				if card.type == "spell" and me.hand.size() >= 9:
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
