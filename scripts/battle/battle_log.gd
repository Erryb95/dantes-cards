class_name BattleLog
extends RefCounted
## The match history (the battle log): BattleState events in, one entry per action out, each with what it caused.
## No nodes; the view (BattleLogView) shows the entries, the tests read them.
##
## An entry is one thing a player did or that happened to them: a card played, an attack, the hero power, a Start /
## End of Turn effect, fatigue, a card burned from a full hand, the match's end. Every event that follows it (damage,
## deaths, heals, summons, draws...) until the next such action is one of its results. The opening ("first": who
## goes first, the mulligan, Charon's Obol) is entry 0 of turn 0.
##
## Only what both players can see goes in: a card in the opponent's hand is never named (a draw is "draws a card",
## a mulligan only counts the cards); it is named once played, burned, or put on the board. Side 0 is always this
## player (online too: the events are local).
##
## Entry: {seq, kind, side, turn, turn_side, card (card id or ""), hero (hero id of `side`), target (ref or {}),
##   ruse, results: [{t, ...}], kills (minions and heroes it killed), strip (shown in the battle's icon strip)}.
## A ref (a unit named in an entry): {uid, id, hero, side}.

signal entry_added(e: Dictionary)
signal entry_changed(e: Dictionary)

const MAX_ENTRIES := 240 ## the oldest go first: a long match keeps its last ~30 turns
const MAX_RESULTS := 48 ## per entry; more are counted in "more" (a board wipe with Last Breaths stays far under it)

var entries: Array[Dictionary] = []
## How each side is called in the lines: the player's name online (or vs the AI when they set one), else the hero's
## short name. Set by the view; empty falls back to the hero.
var names: Array[String] = ["", ""]
var heroes: Array[String] = ["", ""]

var _seq := 0
var _cur: Dictionary = {} ## the entry the next results go to ({} between actions)
var _turn := 0
var _turn_side := 0
var _acted := false ## a card, attack or power this turn (tells a Start of Turn effect from an End of Turn one)
var _units := {} ## uid -> {id, hero, side}: every unit the log has seen (heroes from "start", minions from "summon")
var _armor := {} ## hero uid -> its Armor (the "armor" event gives the new total; the result shows the gain)
var _state := {} ## minion uid -> [frozen, silenced] (a "status" event logs only a freeze or silence it brings)
var _deck := [0, 0] ## cards left per deck: a hand card that leaves no gap in the deck was given, not drawn
var _swaps := [0, 0]
var _mulligan := false
var _skip_summon := {} ## uid of a minion just played (its own summon is the play), or "into" ids of a transform
var _skip_death := {} ## uid of a transformed minion (it leaves, it does not die)
var _skip_draws := 0 ## draws that are the hand side of a copy or a steal (already logged)
var _stolen: Array[String] = [] ## stolen cards whose "copy" event is still to come


# ---------------------------------------------------------------- events in

func feed(ev: Dictionary) -> void:
	match str(ev.get("t", "")):
		"start":
			for h in ev.heroes:
				_units[int(h.uid)] = {"id": str(h.id), "hero": true, "side": int(h.side)}
				_armor[int(h.uid)] = int(h.get("armor", 0))
				heroes[int(h.side)] = str(h.id)
			for i in 2:
				_deck[i] = int(ev.decks[i])
		"first":
			_cur = _new("first", int(ev.side), "", {}, false)
		"mulligan_begin":
			_mulligan = true
		"mulligan_swap":
			_swaps[int(ev.side)] += 1 # never the cards: the opponent's are secret
		"mulligan_end":
			if _mulligan and not _cur.is_empty():
				for s in 2:
					_add({"t": "mulligan", "side": s, "n": _swaps[s]})
		"turn":
			_turn = int(ev.turn)
			_turn_side = int(ev.side)
			_acted = false
			_cur = {}
		"turn_end":
			_cur = {}
		"play":
			_acted = true
			var side := int(ev.side)
			if str(ev.get("type", "")) == "minion":
				_skip_summon[int(ev.uid)] = true # the card's own summon (from_card = its hand uid)
			_cur = _new("play", side, str(ev.id), _ref(int(ev.get("target", -1))))
		"attack":
			_acted = true
			var a := _ref(int(ev.attacker))
			_cur = _new("attack", int(a.get("side", _turn_side)), str(a.get("id", "")), _ref(int(ev.target)))
			_cur["by"] = a
		"power":
			_acted = true
			_cur = _new("power", int(ev.side), "", _ref(int(ev.get("target", -1))))
		"trigger":
			var u := _ref(int(ev.uid))
			_cur = _new("trigger", int(u.get("side", _turn_side)), str(u.get("id", "")), {})
			_cur["phase"] = _phase(str(u.get("id", "")))
		"ruse":
			if not _cur.is_empty():
				_cur.ruse = true
				_changed()
		"fatigue":
			if not _cur.is_empty(): # in an action, or dealing an opening hand from a tiny deck (a lesson)
				_add({"t": "fatigue", "side": int(ev.side)})
			else:
				_cur = _new("fatigue", int(ev.side), "", {})
		"burn":
			_deck[int(ev.side)] = int(ev.deck)
			if _open():
				_add({"t": "burn", "side": int(ev.side), "id": str(ev.id)})
			else:
				_cur = _new("burn", int(ev.side), str(ev.id), {})
		"draw":
			_on_draw(ev)
		"summon":
			var u: Dictionary = ev.unit
			var uid := int(u.uid)
			_units[uid] = {"id": str(u.id), "hero": false, "side": int(u.side)}
			_state[uid] = [bool(u.get("frozen", false)), bool(u.get("silenced", false))]
			var from := int(ev.get("from_card", -1))
			if from != -1 and _skip_summon.has(from):
				_skip_summon.erase(from)
			elif _skip_summon.has("into:" + str(u.id)):
				_skip_summon.erase("into:" + str(u.id))
			elif _open():
				_add({"t": "summon", "to": _ref(uid)})
		"rebirth":
			# Its "summon" came just before: the same minion rising again, not a new one.
			var res: Array = _cur.get("results", [])
			for i in range(res.size() - 1, -1, -1):
				if res[i].t == "summon" and int(res[i].to.uid) == int(ev.uid):
					res[i].t = "rebirth"
					_changed()
					break
		"transform":
			_skip_death[int(ev.uid)] = true
			_skip_summon["into:" + str(ev.into)] = true
			_add({"t": "transform", "to": _ref(int(ev.uid)), "into": str(ev.into)})
		"damage":
			if _armor.has(int(ev.uid)):
				_armor[int(ev.uid)] = int(ev.get("armor", 0))
			if int(ev.amount) > 0:
				_add({"t": "damage", "to": _ref(int(ev.uid)), "amount": int(ev.amount)})
		"heal":
			if int(ev.amount) > 0:
				_add({"t": "heal", "to": _ref(int(ev.uid)), "amount": int(ev.amount)})
		"armor":
			var gain := int(ev.armor) - int(_armor.get(int(ev.uid), 0))
			_armor[int(ev.uid)] = int(ev.armor)
			if gain > 0:
				_add({"t": "armor", "to": _ref(int(ev.uid)), "amount": gain})
		"buff":
			_add({"t": "buff", "to": _ref(int(ev.uid)), "attack": int(ev.attack), "health": int(ev.health)})
		"status":
			var uid := int(ev.uid)
			var was: Array = _state.get(uid, [false, false])
			if bool(ev.frozen) and not was[0]:
				_add({"t": "freeze", "to": _ref(uid)})
			if bool(ev.silenced) and not was[1]:
				_add({"t": "silence", "to": _ref(uid)})
			_state[uid] = [bool(ev.frozen), bool(ev.silenced)]
		"ward_break":
			_add({"t": "ward", "to": _ref(int(ev.uid))})
		"frenzy":
			_add({"t": "frenzy", "to": _ref(int(ev.uid))})
		"fight":
			_add({"t": "fight", "to": _ref(int(ev.a)), "other": _ref(int(ev.b))})
		"bounce":
			_add({"t": "bounce", "to": _ref(int(ev.uid))})
		"death":
			var uid := int(ev.uid)
			if _skip_death.has(uid):
				_skip_death.erase(uid)
			else:
				_add({"t": "death", "to": _ref(uid)})
				_kill()
		"steal":
			var thief := int(ev.side)
			if ev.has("deck"):
				_deck[int(ev.from)] = int(ev.deck)
			# A card I take, or one taken from my own hand, I know; the top of my deck taken by the opponent I don't.
			var shown := thief == 0 or str(ev.get("zone", "")) == "hand"
			_add({"t": "steal", "side": thief, "id": str(ev.id) if shown else ""})
			_stolen.append(str(ev.id)) # its "copy" and "draw" into the thief's hand follow: the steal says it all
			_skip_draws += 1
		"copy":
			var side := int(ev.side)
			if str(ev.id) in _stolen:
				_stolen.erase(str(ev.id))
				return
			# A copy of a minion on the board is public; one of a card in my hand or deck made by the opponent is not.
			var shown := side == 0 or str(ev.get("from", "board")) == "board"
			_add({"t": "copy", "side": side, "id": str(ev.id) if shown else ""})
			_skip_draws += 1
		"game_over":
			var fallen: Array = ev.get("fallen", [])
			for f in fallen:
				_add({"t": "fall", "to": _ref(int(f.uid))})
				_kill()
			var w := int(ev.winner)
			_cur = _new("over", w if w == 0 or w == 1 else 2, "", {}, true)
			for f in fallen:
				_add({"t": "fall", "to": _ref(int(f.uid))})
			_cur = {}


func _on_draw(ev: Dictionary) -> void:
	var side := int(ev.side)
	var id := str(ev.id)
	var drawn := int(ev.deck) < int(_deck[side])
	_deck[side] = int(ev.deck)
	if _skip_draws > 0 and not drawn:
		_skip_draws -= 1 # the copy or stolen card arriving in the hand
		return
	if id == BattleState.COIN:
		# Charon's Obol is public: everyone knows the side going second gets it.
		if not _cur.is_empty():
			_add({"t": "gets", "side": side, "ids": [id]})
		return
	if not _open():
		return # the turn's own draw and the opening hand are not logged
	var t := "draw" if drawn else "gets"
	var res: Array = _cur.results
	if not res.is_empty() and res.back().t == t and int(res.back().side) == side:
		var last: Dictionary = res.back()
		last.n = int(last.n) + 1
		if side == 0:
			last.ids.append(id)
		_changed()
		return
	_add({"t": t, "side": side, "n": 1, "ids": [id] if side == 0 else []})


## True while an action is collecting its results (the opening entry only takes the mulligan and the Obol).
func _open() -> bool:
	return not _cur.is_empty() and _cur.kind != "first"


func _new(kind: String, side: int, card: String, target: Dictionary, strip: bool = true) -> Dictionary:
	_seq += 1
	var e := {"seq": _seq, "kind": kind, "side": side, "turn": _turn, "turn_side": _turn_side, "card": card,
		"hero": heroes[side] if side == 0 or side == 1 else "", "target": target, "ruse": false, "results": [],
		"kills": 0, "more": 0, "strip": strip and kind != "first"}
	entries.append(e)
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(e)
	return e


func _add(r: Dictionary) -> void:
	if _cur.is_empty():
		return
	if r.has("to") and (r.to as Dictionary).is_empty():
		return # a unit the log never saw (a test that put it in play before listening)
	if _cur.results.size() >= MAX_RESULTS:
		_cur.more = int(_cur.more) + 1
		return
	_cur.results.append(r)
	_changed()


func _kill() -> void:
	if not _cur.is_empty():
		_cur.kills = int(_cur.kills) + 1


func _changed() -> void:
	entry_changed.emit(_cur)


func _ref(uid: int) -> Dictionary:
	if uid == -1 or not _units.has(uid):
		return {}
	var u: Dictionary = _units[uid]
	return {"uid": uid, "id": u.id, "hero": u.hero, "side": u.side}


## "start" or "end" for a minion's turn effect: the one its card has, else by whether the player acted yet.
func _phase(id: String) -> String:
	var has := {}
	for e in CardDB.card(id).get("effects", []):
		has[str(e.get("on", ""))] = true
	if has.has("turn_start") and not has.has("turn_end"):
		return "start"
	if has.has("turn_end") and not has.has("turn_start"):
		return "end"
	return "end" if _acted else "start"


# ---------------------------------------------------------------- queries

## Every card id the log names (entries' cards, results, transforms): the tests check no secret is among them.
func ids_mentioned() -> Array:
	var out := {}
	for e in entries:
		if e.card != "":
			out[e.card] = true
		for r in e.results:
			for k in ["to", "other"]:
				if r.has(k) and not r[k].hero:
					out[r[k].id] = true
			for k in ["id", "into"]:
				if str(r.get(k, "")) != "":
					out[str(r[k])] = true
			for id in r.get("ids", []):
				out[str(id)] = true
	return out.keys()


## The entries in order, grouped by turn: [{turn, side, entries}] (turn 0: the opening).
func groups() -> Array:
	var out := []
	for e in entries:
		if out.is_empty() or int(out.back().turn) != int(e.turn):
			out.append({"turn": int(e.turn), "side": int(e.turn_side), "entries": []})
		out.back().entries.append(e)
	return out


## The last `n` entries shown in the battle's icon strip, newest first.
func recent(n: int) -> Array:
	var out := []
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].strip:
			out.append(entries[i])
			if out.size() >= n:
				break
	return out


# ---------------------------------------------------------------- text

## How side `side` is called: its name, else its hero's short name ("Dante", "Filippo Argenti").
func side_name(side: int) -> String:
	if side == 0 or side == 1:
		if names[side] != "":
			return names[side]
		return hero_name(heroes[side])
	return ""


static func hero_name(hero_id: String) -> String:
	return str(CardDB.hero(hero_id).get("name", hero_id)).get_slice(",", 0).strip_edges()


static func card_name(id: String) -> String:
	return str(CardDB.card(id).get("name", id))


static func ref_name(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	return hero_name(r.id) if r.hero else card_name(r.id)


static func power_name(hero_id: String) -> String:
	return str(CardDB.hero(hero_id).get("power", {}).get("name", ""))


## "Turn 7 — Enrico" (turn 0: the opening).
func turn_title(turn: int, side: int) -> String:
	if turn <= 0:
		return Loc.t("Start of the match")
	return Loc.t("Turn %d — %s") % [turn, side_name(side)]


## The entry's main line: "Charon plays Cerberus", "Cerberus attacks Ulysses"...
func headline(e: Dictionary) -> String:
	var who := side_name(int(e.side))
	var target := ref_name(e.target)
	match str(e.kind):
		"play":
			if target != "":
				return Loc.t("%s plays %s on %s") % [who, card_name(e.card), target]
			return Loc.t("%s plays %s") % [who, card_name(e.card)]
		"attack":
			return Loc.t("%s attacks %s") % [card_name(e.card), target]
		"power":
			if target != "":
				return Loc.t("%s uses %s on %s") % [who, power_name(e.hero), target]
			return Loc.t("%s uses %s") % [who, power_name(e.hero)]
		"trigger":
			return (Loc.t("%s: Start of Turn") if e.get("phase", "end") == "start" else Loc.t("%s: End of Turn")) \
				% card_name(e.card)
		"fatigue":
			return Loc.t("Fatigue: %s draws from an empty deck") % who
		"burn":
			return Loc.t("%s burns %s (hand full)") % [who, card_name(e.card)]
		"first":
			return Loc.t("%s goes first") % who
		"over":
			if int(e.side) == 2:
				return Loc.t("The match ends in a draw")
			return Loc.t("%s wins") % who
	return ""


## The entry's results as lines, alike ones merged ("2 damage to Cerberus, Minos").
func lines(e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var merged := {} ## key -> index in `groups_`
	var groups_ := [] ## [template key, [names]]
	for r in e.results:
		var key := ""
		var nm := ref_name(r.get("to", {}))
		match str(r.t):
			"damage", "heal", "armor":
				key = "%s:%d" % [r.t, r.amount]
			"death", "fall", "freeze", "silence", "ward", "frenzy", "summon", "rebirth", "bounce":
				key = str(r.t)
		if key != "":
			if not merged.has(key):
				merged[key] = groups_.size()
				groups_.append([key, [], r])
			if nm not in groups_[merged[key]][1]:
				groups_[merged[key]][1].append(nm)
			continue
		groups_.append(["", [], r])
	for g in groups_:
		var r: Dictionary = g[2]
		var list := " · ".join(PackedStringArray(g[1])) # a name may hold a comma ("Minos, Judge of the Damned")
		var many: bool = (g[1] as Array).size() > 1
		var line := ""
		match str(r.t):
			"damage":
				line = (Loc.t("1 damage to %s") % list) if int(r.amount) == 1 else (Loc.t("%d damage to %s") % [r.amount, list])
			"heal":
				line = Loc.t("+%d Health to %s") % [r.amount, list]
			"armor":
				line = Loc.t("+%d Armor to %s") % [r.amount, list]
			"death":
				line = (Loc.t("%s die") if many else Loc.t("%s dies")) % list
			"fall":
				line = Loc.t("%s falls") % list
			"freeze":
				line = Loc.t("Freeze: %s") % list
			"silence":
				line = Loc.t("Silence: %s") % list
			"ward":
				line = Loc.t("Ward breaks: %s") % list
			"frenzy":
				line = Loc.t("Frenzy: %s") % list
			"summon":
				line = Loc.t("Summon: %s") % list
			"rebirth":
				line = Loc.t("Rebirth: %s") % list
			"bounce":
				line = Loc.t("Back to hand: %s") % list
			"buff":
				line = Loc.t("%s becomes %d/%d") % [ref_name(r.to), r.attack, r.health]
			"transform":
				line = Loc.t("%s turns into %s") % [ref_name(r.to), card_name(r.into)]
			"fight":
				line = Loc.t("%s fights %s") % [ref_name(r.to), ref_name(r.other)]
			"draw", "gets":
				var who := side_name(int(r.side))
				var ids: Array = r.get("ids", [])
				if not ids.is_empty():
					var names_ := PackedStringArray(ids.map(func(id): return card_name(str(id))))
					line = (Loc.t("%s draws: %s") if r.t == "draw" else Loc.t("%s gets: %s")) % [who, " · ".join(names_)]
				elif int(r.get("n", 1)) == 1:
					line = (Loc.t("%s draws a card") if r.t == "draw" else Loc.t("%s gets a card")) % who
				else:
					line = (Loc.t("%s draws %d cards") if r.t == "draw" else Loc.t("%s gets %d cards")) % [who, r.n]
			"burn":
				line = Loc.t("Burn: %s (hand full)") % card_name(r.id)
			"fatigue":
				line = Loc.t("Fatigue: %s draws from an empty deck") % side_name(int(r.side))
			"steal":
				line = (Loc.t("%s steals %s") % [side_name(int(r.side)), card_name(r.id)]) if str(r.id) != "" \
					else Loc.t("%s steals a card") % side_name(int(r.side))
			"copy":
				line = (Loc.t("%s copies %s") % [side_name(int(r.side)), card_name(r.id)]) if str(r.id) != "" \
					else Loc.t("%s copies a card") % side_name(int(r.side))
			"mulligan":
				var n := int(r.n)
				if n == 0:
					line = Loc.t("%s keeps the starting hand") % side_name(int(r.side))
				elif n == 1:
					line = Loc.t("%s replaces 1 card") % side_name(int(r.side))
				else:
					line = Loc.t("%s replaces %d cards") % [side_name(int(r.side)), n]
		if line != "":
			out.append(line)
	if int(e.get("more", 0)) > 0:
		out.append(Loc.t("…and %d more") % int(e.more))
	return out


## The whole log as plain text (tests, and a quick look in the console).
func dump() -> String:
	var out := PackedStringArray()
	for g in groups():
		out.append("== " + turn_title(g.turn, g.side))
		for e in g.entries:
			out.append("  " + headline(e) + (" [%s]" % Loc.t("Ruse") if e.ruse else ""))
			for l in lines(e):
				out.append("    " + l)
	return "\n".join(out)
