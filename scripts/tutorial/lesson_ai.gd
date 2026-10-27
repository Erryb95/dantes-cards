class_name LessonAI
extends BattleAI
## The opponent of a scripted lesson: its first turns follow the lesson's script exactly (data/lessons.json "script"),
## so the lesson plays out as Virgil tells it; afterwards it plays as the Easy AI ("after": "easy") or passes ("pass").
## Like BattleAI it returns one legal action per call, then "end": an intent that cannot be done now (its card is not in
## hand, its target is gone) is skipped and noted in `skipped`, so the opponent never stalls.
##
## Intents: {"play": card id, "target"?}, {"attack": card id | "all", "target": "hero" | card id},
## {"power": true, "target"?}. A target names a minion by card id (the player's first, then its own) or "hero"
## (the player's hero; a friendly effect's own hero for "own_hero" powers needs no target).

var script_turns: Array = []
var after := "easy"
var skipped: Array[String] = [] ## intents that could not be carried out (the tests check the taught path skips none)
var _turn := -1 ## the battle turn the cursor belongs to
var _n := 0 ## how many of its own turns have begun
var _cursor := 0


func _init(p_script: Array = [], p_after: String = "easy") -> void:
	super(1, Level.EASY)
	script_turns = p_script
	after = p_after


func next_action(st: BattleState) -> Dictionary:
	if st.winner != -1 or st.current != side:
		return {"do": "end"}
	if st.turn != _turn:
		_turn = st.turn
		_n += 1
		_cursor = 0
	if _n > script_turns.size():
		return super.next_action(st) if after == "easy" else {"do": "end"}
	var intents: Array = script_turns[_n - 1]
	while _cursor < intents.size():
		var it: Dictionary = intents[_cursor]
		var m := _resolve(st, it)
		if m.is_empty():
			if not (it.has("attack") and str(it.attack) == "all" and _done_any):
				skipped.append("turn %d: %s" % [_n, JSON.stringify(it)])
			_cursor += 1
			_done_any = false
			continue
		if not (it.has("attack") and str(it.attack) == "all"):
			_cursor += 1 # "attack all" stays until no attacker is left
		else:
			_done_any = true
		return m
	return {"do": "end"}


var _done_any := false ## an "attack all" intent has sent at least one attacker


## The legal move an intent stands for right now, or {}.
func _resolve(st: BattleState, it: Dictionary) -> Dictionary:
	var me := st.sides[side]
	if it.has("play"):
		for c in me.hand:
			if c.id != str(it.play) or not st.can_play(side, c.uid):
				continue
			var tt := BattleState.target_type(CardDB.card(c.id))
			var t := -1
			if tt != "":
				var valid := st.valid_targets(side, tt)
				t = _target(st, str(it.get("target", "")), valid)
				if t == -1 and not valid.is_empty():
					t = valid[0] if CardDB.card(c.id).type == "spell" else -1
				if CardDB.card(c.id).type == "spell" and t == -1:
					return {}
			return {"do": "play", "uid": c.uid, "target": t, "index": -1}
		return {}
	if it.has("attack"):
		var targets := st.attack_targets(side)
		var t := _target(st, str(it.get("target", "hero")), targets)
		if t == -1:
			return {}
		for u in me.board:
			if (str(it.attack) == "all" or u.id == str(it.attack)) and st.can_attack(u):
				return {"do": "attack", "attacker": u.uid, "target": t}
		return {}
	if it.has("power"):
		if not st.can_use_power(side):
			return {}
		var tt := BattleState.power_target_type(CardDB.hero(me.hero_id))
		if tt == "":
			return {"do": "power", "target": -1}
		var t := _target(st, str(it.get("target", "")), st.valid_targets(side, tt))
		return {"do": "power", "target": t} if t != -1 else {}
	return {}


## The uid a target name stands for among `valid` ("hero": the player's hero; a card id: the player's minion of that
## card first, then this side's own), or -1.
func _target(st: BattleState, name: String, valid: Array) -> int:
	if name == "":
		return -1
	if name == "hero":
		var h := st.sides[1 - side].hero.uid
		return h if valid.has(h) else -1
	for s in [1 - side, side]:
		for u in st.sides[s].board:
			if u.id == name and valid.has(u.uid):
				return u.uid
	return -1
