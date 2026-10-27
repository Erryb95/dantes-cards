class_name BattleAI
extends RefCounted
## The opponent: returns one action at a time so the view can animate between steps.
## Action: {"do": "play", "uid", "target", "index"} | {"do": "attack", "attacker", "target"} |
##         {"do": "power", "target"} | {"do": "end"}
## Levels (Settings.difficulty uses the same numbers):
## - EASY follows fixed rules (the most expensive card first, simple trades; no minion thrown away on a Guard).
## - HARD tries every legal move on a copy of the battle, then plays the best few out to the end of the turn and
##   keeps the line that leaves the best position (see `evaluate`).
## - MEDIUM runs the same search shallower and noisier: fewer lines played out and a random error on how it scores
##   them, so it misses some good turns. It never misses a win that a single move gives it.
## It reads only what a player could see: its own hand, the board, counts.

enum Level { EASY, MEDIUM, HARD }

const ROLLOUTS := 8 ## Hard: candidate first moves that get played out to the end of the turn
const MEDIUM_ROLLOUTS := 2
const MEDIUM_NOISE := 1.5 ## Medium: standard deviation of the error added to each line's score
const WASTE_FLOOR := 5.0 ## Easy: the least `_value` a minion needs to be worth a destroy card (about a 2/3)
const WASTE_WEIGHT := 1.5 ## Search: removal spells want a target worth this many points per mana (see `_waste`)

var side := 1
var level := Level.HARD
var rollouts := ROLLOUTS ## 0: score each move one step ahead only
var noise := 0.0
var abort := false ## set from the main thread to stop a search early (the battle is closing)
var _seed := 0 ## seeds each simulated copy, so the worker thread never touches the global RNG
var _rng := RandomNumberGenerator.new() ## Medium's scoring error; reseeded from the battle on every decision


func _init(p_side: int = 1, p_level: Level = Level.HARD) -> void:
	side = p_side
	level = p_level
	if level == Level.MEDIUM:
		rollouts = MEDIUM_ROLLOUTS
		noise = MEDIUM_NOISE


func next_action(st: BattleState) -> Dictionary:
	if st.winner != -1 or st.current != side:
		return {"do": "end"}
	if level == Level.EASY:
		return _rules(st)
	_seed = int(st.rng.state)
	_rng.seed = _seed
	return _search(st)


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
		var w := _waste(st, m)
		scored.append([evaluate(b) - w, m, b, w])
	if scored.is_empty():
		return {"do": "end"}
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var best: Dictionary = {}
	var best_v := base + 0.25
	for i in scored.size() if rollouts == 0 else mini(rollouts, scored.size()):
		var v: float = scored[i][0] if rollouts == 0 else _rollout(scored[i][2]) - scored[i][3]
		if noise > 0.0:
			v += _rng.randfn(0.0, noise)
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
	var spent := 0.0 ## removal wasted along the line (see `_waste`)
	for step in 12:
		if st.winner != -1 or abort:
			break
		var next: BattleState = null
		var next_v := cur + 0.25
		var next_w := 0.0
		for m in _moves(st):
			var b := _copy(st)
			if not apply(b, side, m):
				continue
			var w := _waste(st, m)
			var v := evaluate(b) - w
			if v > next_v:
				next_v = v
				next = b
				next_w = w
		if next == null:
			break
		st = next
		cur = next_v + next_w
		spent += next_w
	return cur - spent


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
			if e.get("on", "play") != "play" and not (e.get("on", "") == "frenzy" and u.frenzied):
				v += 2.0
	# Wrath: an undamaged minion's bonus is a threat in waiting (one ping away); a raging one already counts it in
	# its Attack. Healthier ragers keep raging longer, so the latent part grows with health.
	if u.wrath > 0 and u.rage == 0:
		v += 0.35 * u.wrath + 0.05 * u.wrath * mini(u.health, 6)
	if u.frozen:
		v -= 0.5 * u.attack
	return v


## The search's penalty for a removal spell (destroy or transform on a chosen enemy minion) spent on a target worth less
## than the card: `evaluate` counts every card in hand the same, so without it a 6-mana Destroy on a 1/1 token looked
## like a gain and the AI had nothing left for the real threat. `st` is the position before the move. A target that
## endangers the hero is still removed: the danger term of `evaluate` outweighs this.
func _waste(st: BattleState, m: Dictionary) -> float:
	if m.do != "play" or not st.units.has(m.target):
		return 0.0
	var card := CardDB.card(str(st.hand_card(side, m.uid).get("id", "")))
	if card.get("type", "") != "spell" or not _is_removal(card):
		return 0.0
	var t = st.units[m.target]
	if t.is_hero or t.side == side:
		return 0.0
	return maxf(0.0, WASTE_WEIGHT * float(card.cost) - _unit_value(t))


## A card that destroys or transforms a minion the player picks (Fury's Lash, Circe's Draught...).
static func _is_removal(card: Dictionary) -> bool:
	for e in card.get("effects", []):
		if e.do in ["destroy", "transform"] and str(e.get("target", "")).begins_with("choose_"):
			return true
	return false


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
		var pw: Array = CardDB.hero(me.hero_id).power.effects
		var t := _goad_target(st, 1, tt) if _goads(pw) else _best_damage_target(st, 1, tt, true)
		if t != -1:
			return {"do": "power", "target": t}

	# 4. Attacks: kill guards, take good trades, otherwise go face. A minion that would only die on a Guard stays home
	# (see `_attack_choice`).
	for u in me.board:
		if not st.can_attack(u):
			continue
		var t := _attack_choice(st, u, st.attack_targets(side))
		if t != -1:
			return {"do": "attack", "attacker": u.uid, "target": t}
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
	var ruse := st.ruse_active(side)
	var effects: Array = card.get("effects", [])
	var fight_alone := false
	if not ruse and effects.any(func(e): return e.get("ruse", false)):
		# Ruse: play something else first when there is anything else to play.
		for o in me.hand:
			if o.uid != c.uid and st.can_play(side, o.uid) and int(CardDB.card(o.id).cost) + int(card.cost) <= me.mana:
				score -= 40.0
				break
	for e in effects:
		if e.get("on", "play") != "play":
			continue
		if e.get("ruse", false) and not ruse:
			continue
		match e.do:
			"damage" when e.get("target", "") == "own_hero":
				# Self-wounding (Wrath class): never pay with the last of our health.
				if int(e.amount) >= me.hero.health + me.hero.armor:
					return {}
			"damage" when tt == "choose_friendly_minion" or (tt == "choose_minion" and _goads(effects)):
				# Hurting our own minion on purpose (Wrath, Frenzy), or Spite-like "1 damage and +2 Attack".
				target = _goad_target(st, int(e.amount), tt)
				if target == -1 and card.type == "spell":
					return {}
			"fight":
				if tt == "choose_enemy_minion":
					var mob: bool = e.get("with", "self") == "all_friendly_minions"
					var power := 0
					for u in me.board:
						power += u.attack if mob else 0
					if not mob:
						power = int(card.get("attack", 0))
					target = _best_fight(st, power, 99 if mob else int(card.get("health", 0)))
					if target == -1:
						if card.type == "spell":
							return {}
						fight_alone = true # a fighter with nothing worth fighting is played without a target
				elif card.type == "spell" and foe.board.is_empty():
					return {}
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
				if tt != "" and target == -1: # a "damage, then buff" card already picked its minion
					target = _best_friend(st)
					if target == -1 and card.type == "spell":
						return {}
				elif e.target == "other_friendly_minions" and me.board.size() < 2:
					score -= 15.0
			"bounce" when tt == "choose_friendly_minion":
				# Bounce to replay: the friendly minion with the best On Play effect.
				var best := -1
				var best_cost := 0
				for u in me.board:
					var uc := CardDB.card(u.id)
					var replay: bool = uc.get("effects", []).any(func(x): return x.get("on", "play") == "play")
					if replay and int(uc.cost) > best_cost and int(uc.cost) <= me.mana - int(card.cost):
						best_cost = int(uc.cost)
						best = u.uid
				if best == -1:
					return {}
				target = best
				score = best_cost * 10.0 + 5.0
			"bounce" when tt == "":
				# Board-wide bounce: only when it costs the enemy more than us.
				var mine := 0.0
				var theirs := 0.0
				for u in me.board:
					mine += _value(u)
				for u in foe.board:
					theirs += _value(u)
				if e.target in ["all_enemy_minions", "random_enemy_minion"]:
					if foe.board.is_empty() and card.type == "spell":
						return {}
				elif theirs < mine + 6.0:
					return {}
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
				# Charon's Obol, Sinon's Lie: only when the extra mana (after paying for this card) unlocks a card that is
				# not playable now.
				var unlock := 0
				for o in me.hand:
					var oc := CardDB.card(o.id)
					if o.uid != c.uid and int(oc.cost) == me.mana - int(card.cost) + int(e.amount) \
							and int(oc.cost) > me.mana:
						unlock = maxi(unlock, int(oc.cost))
				if unlock == 0:
					if card.type == "spell" and effects.size() == 1:
						return {}
				else:
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
			"destroy":
				# Hard removal is kept for a minion worth it, never spent on a token (Easy used to pick any target).
				if tt != "":
					target = _best_destroy(st, tt)
					if target == -1 and card.type == "spell":
						return {}
			"transform":
				if tt != "":
					target = _best_transform(st, str(e.card))
					if target == -1 and card.type == "spell":
						return {}
				elif card.type == "spell":
					var worth := 0.0
					for u in foe.board:
						worth += _value(u)
					if worth < 10.0:
						return {}
			"copy":
				if tt == "choose_enemy_minion" or tt == "choose_minion":
					target = _best_copy(st, tt, e.get("to", "hand") == "board")
					if target == -1 and card.type == "spell":
						return {}
				elif card.type == "spell" and me.hand.size() >= 9:
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
	if tt != "" and target == -1 and not fight_alone:
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


## How much a minion loses when silenced: its keywords and card effects. Silence keeps stat changes (buffs stay)
## and does not thaw a Frozen minion, so neither counts here.
func _silence_value(u) -> float:
	if u.silenced:
		return 0.0
	var c := CardDB.card(u.id)
	return 2.0 * u.keywords.size() + 3.0 * c.get("effects", []).size()


func _best_silence(st: BattleState) -> int:
	var best := -1
	var best_v := 2.5
	for u in st.sides[1 - side].board:
		var v: float = _silence_value(u)
		if v > best_v:
			best_v = v
			best = u.uid
	return best


## The enemy minion most worth turning into `into` (the biggest gap in value), if worth a card.
func _best_transform(st: BattleState, into: String) -> int:
	var c := CardDB.card(into)
	var base := float(c.get("attack", 0)) * 1.2 + float(c.get("health", 1))
	var best := -1
	var best_v := 4.0
	for u in st.sides[1 - side].board:
		var v := _value(u) - base + (_silence_value(u) * 0.5)
		if v > best_v:
			best_v = v
			best = u.uid
	return best


## The enemy minion most worth destroying (the highest value, Ward does not matter), or -1 when none is worth a removal
## card (WASTE_FLOOR: a 1/1 token is not).
func _best_destroy(st: BattleState, tt: String) -> int:
	var valid := st.valid_targets(side, tt)
	var best := -1
	var best_v := WASTE_FLOOR - 0.01
	for u in st.sides[1 - side].board:
		if valid.has(u.uid) and _value(u) > best_v:
			best_v = _value(u)
			best = u.uid
	return best


## The minion most worth copying. Into the hand the copy is the printed card: the most expensive one. Onto the board
## it is the minion as it is now (buffs, damage, Silence...): the one worth most on the board.
func _best_copy(st: BattleState, tt: String, to_board: bool = false) -> int:
	var best := -1
	var best_v := -INF
	for uid in st.valid_targets(side, tt):
		var u = st.units[uid]
		var v: float = _value(u) if to_board else float(CardDB.card(u.id).get("cost", 0))
		if v > best_v:
			best_v = v
			best = uid
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


## Easy's target for attacker `a`, or -1 when it should not attack: it is behind a Guard and every attack it has
## would be hopeless (it dies and the Guard lives), unless that hit still pays (`_hopeless_pays`).
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
			if kills or survives or t.attack <= 0:
				v = 1.0 + _value(t) * 0.1
			elif _hopeless_pays(st, a, t):
				v = 0.5
		if v > best_v:
			best_v = v
			best = uid
	if targets.has(foe.hero.uid) and best_v < 10.0:
		return foe.hero.uid
	return best


## A hopeless hit on a Guard (the attacker dies, the Guard lives) is still worth it when the attackers ready this turn
## can then finish the Guard and either it is a Venom or Drain threat or its death opens the way to lethal.
func _hopeless_pays(st: BattleState, a, t) -> bool:
	var others := 0
	var venom := false
	for u in st.sides[side].board:
		if u != a and st.can_attack(u):
			others += u.attack
			venom = venom or u.has("venom")
	# `a` hits first: it breaks a Ward or takes its Attack off the Guard's Health.
	var left: int = t.health if t.has("ward") else t.health - a.attack
	if not (venom or others >= left):
		return false
	return t.has("venom") or t.has("drain") or _lethal_through_guards(st)


## Easy's rough lethal check through Guards: the ready attackers, smallest first, are spent on the Guards (a Ward takes
## one hit, Venom kills in one, overkill is lost) and the ones left must reach the enemy hero.
func _lethal_through_guards(st: BattleState) -> bool:
	var foe := st.sides[1 - side]
	var ready: Array = st.sides[side].board.filter(func(u): return st.can_attack(u))
	ready.sort_custom(func(x, y): return x.attack < y.attack)
	for g in foe.board:
		if not g.has("guard"):
			continue
		var hp: int = g.health
		var ward: bool = g.has("ward")
		while hp > 0:
			if ready.is_empty():
				return false
			var u = ready.pop_front()
			if ward:
				ward = false
			elif u.has("venom"):
				hp = 0
			else:
				hp -= u.attack
	var left := 0
	for u in ready:
		left += u.attack
	return left >= foe.hero.health + foe.hero.armor


# ---------------------------------------------------------------- Wrath class (Easy rules)

## True when the effects hurt a chosen minion and then buff that same minion ("Deal 1 damage to a minion and give it
## +2 Attack": Spite, the Rabble-Rouser), so the target should be a friend, unless the blow kills an enemy.
static func _goads(effects: Array) -> bool:
	return effects.any(func(e): return e.do == "buff" and str(e.get("target", "")).begins_with("choose_"))


## Easy: where to aim "hurt a minion (and maybe buff it)". An enemy the blow kills first (choose_minion only); then the
## friend that gains the most from being hurt (Wrath not yet raging, a Frenzy still to fire) and survives it; then
## any friend that survives it. -1 when there is none.
func _goad_target(st: BattleState, amount: int, tt: String) -> int:
	var valid := st.valid_targets(side, tt)
	var best := -1
	var best_v := -INF
	for u in st.sides[1 - side].board:
		if valid.has(u.uid) and u.health <= amount and not u.has("ward") and _value(u) > best_v:
			best_v = _value(u)
			best = u.uid
	if best != -1:
		return best
	best_v = -INF
	for u in st.sides[side].board:
		if not valid.has(u.uid) or u.health <= amount or u.has("ward"):
			continue
		var v := 0.1 * u.health
		if u.wrath > 0 and u.rage == 0:
			v += 2.0 * u.wrath
		if not u.frenzied and not u.silenced \
				and CardDB.card(u.id).get("effects", []).any(func(e): return e.get("on", "") == "frenzy"):
			v += 4.0
		if v > best_v:
			best_v = v
			best = u.uid
	return best


## Easy: the enemy minion most worth a fight with `power` Attack and `toughness` Health: one that dies to it, best of
## all one that dies and leaves the fighter alive. Ward shrugs the blow off, so it is skipped. -1 when none dies.
func _best_fight(st: BattleState, power: int, toughness: int) -> int:
	var best := -1
	var best_v := -INF
	for u in st.sides[1 - side].board:
		if u.has("ward") or u.health > power:
			continue
		var v := _value(u) + (6.0 if u.attack < toughness and not u.has("venom") else 0.0)
		if v > best_v:
			best_v = v
			best = u.uid
	return best
