class_name DuelSync
extends RefCounted
## The shared game of an online duel. The server ("dantes_match") only relays and orders the players' moves; each
## client runs the rules itself. DuelSync builds the same canonical BattleState on both machines from the match's
## START (seed, players, first player, decks) and applies the server's ordered stream to it: MULLIGAN (108), TURN
## (103) and ACTION (102), strictly by `seq`. The local player is always side 0 of the state (`BattleState.flip`), so
## the battle view needs no mirroring. No nodes and no network here: the battle view and the tests feed it.
##
## An action payload (op 1) is {t: "play", hand_uid, target, index} | {t: "attack", attacker, target} |
## {t: "power", target}, plus `ck`: the sender's state checksum just before the action. The receiver compares it with
## its own, so a desync is noticed at the first action after it.

const OP_ACTION := 1
const OP_END_TURN := 2
const OP_CONCEDE := 3
const OP_RESULT := 4
const OP_RESYNC := 5
const OP_MULLIGAN := 6
const S_START := 101
const S_ACTION := 102
const S_TURN := 103
const S_ROPE := 104
const S_STATUS := 105
const S_END := 106
const S_RESYNC := 107
const S_MULLIGAN := 108
const S_ERROR := 199

var st: BattleState
var start_msg := {}
var players: Array = ["", ""] ## user ids, canonical order
var names: Array = ["", ""]
var decks: Array = [[], []] ## canonical: Array[String] card ids
var heroes: Array = ["", ""]
var classes: Array = ["", ""]
var me := 0 ## my canonical side (0 or 1)
var first := 0 ## canonical side that plays first
var seed_value := 1
var turn_ms := 75000
var rope_ms := 15000
var next_seq := -1 ## the next seq to apply (-1 until the first one arrives)
var last_seq := 0 ## the last seq applied
var _held := {} ## seq -> [op, data] received ahead of their turn
var desyncs: Array[String] = [] ## what went wrong, for the log and the screen
var error := "" ## START could not be read


## Reads the START payload. False (with `error`) when it is unusable (unknown player, bad deck).
func setup(start: Dictionary, my_user_id: String) -> bool:
	start_msg = start
	players = start.get("players", [])
	if players.size() != 2:
		error = Loc.t("The match has no two players.")
		return false
	names = start.get("names", ["", ""])
	if names.size() != 2:
		names = ["", ""]
	me = players.find(my_user_id)
	if me == -1:
		error = Loc.t("This match is not yours.")
		return false
	var f: Variant = start.get("first", 0)
	first = players.find(f) if f is String else int(f)
	if first < 0 or first > 1:
		first = 0
	seed_value = int(start.get("seed", 1)) & 0x7fffffffffffffff
	if seed_value == 0:
		seed_value = 1 # 0 would make BattleState pick a random seed of its own
	turn_ms = int(start.get("turn_ms", turn_ms))
	rope_ms = int(start.get("rope_ms", rope_ms))
	var raw: Array = start.get("decks", [])
	if raw.size() != 2:
		error = Loc.t("The server sent no decks.")
		return false
	for c in 2:
		var d := parse_deck(raw[c])
		if d.is_empty():
			error = Loc.t("A deck could not be read.")
			return false
		classes[c] = d.cls
		heroes[c] = CardDB.class_hero(d.cls)
		var list: Array[String] = []
		list.assign(d.cards)
		decks[c] = list
	return true


## A deck as the server relays it: the JSON string of the join metadata, or that object. {cls, cards} or {}.
static func parse_deck(raw: Variant) -> Dictionary:
	var d: Variant = JSON.parse_string(raw) if raw is String else raw
	if not (d is Dictionary) or not d.has("cards") or not (d.cards is Array):
		return {}
	var cls := str(d.get("cls", ""))
	if not cls in CardDB.classes():
		return {}
	var cards: Array[String] = []
	for id in d.cards:
		if CardDB.card(str(id)).is_empty():
			return {}
		cards.append(str(id))
	return {"cls": cls, "cards": cards}


## The join metadata for a deck: Nakama wants a map of strings.
static func deck_metadata(cls: String, cards: Array, display_name: String) -> Dictionary:
	return {"deck": JSON.stringify({"cls": cls, "cards": cards}), "name": display_name}


## Builds the state (flipped when I am players[1]). `on_event` is connected before the first event.
func build(on_event: Callable = Callable()) -> BattleState:
	st = BattleState.new()
	st.flip = me
	if on_event.is_valid():
		st.event.connect(on_event)
	st.start(decks[0], heroes[0], decks[1], heroes[1], seed_value, true, first)
	return st


## A canonical side as seen locally (0 = me, at the bottom).
func local(canon: int) -> int:
	return canon ^ me


func side_of(user: String) -> int:
	var c := players.find(user)
	return -1 if c == -1 else local(c)


func opponent_id() -> String:
	return str(players[1 - me])


func opponent_name() -> String:
	return str(names[1 - me])


func my_name() -> String:
	return str(names[me])


## The user id to report as the winner (op 4), "" for a draw.
func winner_id() -> String:
	if st == null or st.winner < 0 or st.winner > 1:
		return ""
	return str(players[st.winner ^ me])


# ---------------------------------------------------------------- the ordered stream

## Holds a sequenced message (ACTION, TURN or MULLIGAN) until its turn. Old ones (a resync replaying what was already
## applied) are dropped.
func push(op: int, data: Dictionary) -> void:
	if not data.has("seq"):
		return
	var seq := int(data.seq)
	if seq <= last_seq and next_seq != -1:
		return
	_held[seq] = [op, data]


## The next message in seq order, or [] when it has not arrived yet.
func pop() -> Array:
	if _held.is_empty():
		return []
	if next_seq == -1:
		var keys := _held.keys()
		keys.sort()
		next_seq = int(keys[0])
	if not _held.has(next_seq):
		return []
	var m: Array = _held[next_seq]
	_held.erase(next_seq)
	last_seq = next_seq
	next_seq += 1
	return m


## The running clock from a RESYNC (107) that arrived at `_rx` (Time.get_ticks_msec()): [ends_at_ms, roped], or
## [0, false] when it has none. The server's `remaining_ms` runs to the very end of the turn, the rope included (in
## the mulligan phase: to the end of the mulligan), so the rope is never added on top of it.
static func resync_clock(resync: Dictionary) -> Array:
	var rem := int(resync.get("remaining_ms", 0))
	if rem <= 0 or bool(resync.get("over", false)):
		return [0, false]
	var rx := int(resync.get("_rx", Time.get_ticks_msec()))
	return [rx + rem, bool(resync.get("roped", false)) and str(resync.get("phase", "")) == "play"]


## The turn clock a TURN (103) starts when it is applied: [ends_at_ms, roped]. A live TURN counts turn_ms + rope_ms
## from its arrival (`_rx`). A TURN replayed from a RESYNC began long ago: it carries the RESYNC's clock instead
## (`_end_ms`, `_roped`, see resync_events), else a rejoin showed a full 90 s turn and a late rope.
static func turn_clock(turn: Dictionary, def_turn_ms := 75000, def_rope_ms := 15000) -> Array:
	if turn.has("_end_ms"):
		return [int(turn._end_ms), bool(turn.get("_roped", false))]
	var rx := int(turn.get("_rx", Time.get_ticks_msec()))
	return [rx + int(turn.get("turn_ms", def_turn_ms)) + int(turn.get("rope_ms", def_rope_ms)), false]


## The sequenced messages inside a RESYNC (107) as [op, payload] pairs, oldest first. An event is the payload the
## server broadcast, tagged with its op ("op" or "op_code"; a payload under "data"/"payload" is accepted too).
## Without a tag, its fields tell: `active` + `reason` is a TURN, `data.replace` a MULLIGAN, else an ACTION.
## Each TURN carries the RESYNC's clock (`_end_ms`, `_roped`; see turn_clock): only the last one matters, the earlier
## ones are replaced by the next TURN at once.
static func resync_events(resync: Dictionary) -> Array:
	var clock := resync_clock(resync)
	var out := []
	for e in resync.get("events", []):
		if not (e is Dictionary):
			continue
		var op := int(e.get("op", e.get("op_code", 0)))
		var body: Dictionary = e
		for k in ["payload", "msg"]:
			if e.get(k) is Dictionary:
				body = e[k]
		if op == 0:
			var d: Variant = body.get("data")
			if body.has("active") and body.has("reason"):
				op = S_TURN
			elif d is Dictionary and d.has("replace"):
				op = S_MULLIGAN
			else:
				op = S_ACTION
		if op in [S_ACTION, S_TURN, S_MULLIGAN]:
			var p := body.duplicate()
			if not p.has("seq") and e.has("seq"):
				p["seq"] = e.seq
			if op == S_TURN and int(clock[0]) > 0:
				p["_end_ms"] = clock[0]
				p["_roped"] = clock[1]
			out.append([op, p])
	return out


## A server ERROR (199) said plainly for the player, or "" when it needs no word (a mulligan the server had already
## decided, on a timeout).
static func error_text(code: String) -> String:
	match code:
		"already_sent", "not_in_mulligan":
			return ""
		"not_your_turn":
			return Loc.t("Too late: the turn has passed.")
		"not_started":
			return Loc.t("The duel has not started yet.")
		"too_many_actions":
			return Loc.t("Too many moves this turn.")
		"bad_payload":
			return Loc.t("The server could not read that move.")
	return Loc.t("The server refused that (%s).") % code.replace("_", " ")


## Who won by the server's END (106), as a local side: 0 me, 1 the opponent, 2 nobody (a draw, a desync, a lost
## connection). The server's word is final: a desync ends without a winner even when this client's rules found one.
func end_side(end: Dictionary) -> int:
	var w := str(end.get("winner", ""))
	if w == "":
		return 2
	var s := side_of(w)
	return s if s != -1 else 2


## The next message in order without taking it ([] when none is ready).
func peek() -> Array:
	if not pending():
		return []
	if next_seq == -1:
		var keys := _held.keys()
		keys.sort()
		return _held[keys[0]]
	return _held[next_seq]


## True when a MULLIGAN from `user` is already waiting (a rejoin: that choice was made before the restart).
func mulligan_held_from(user: String) -> bool:
	for v in _held.values():
		if v[0] == S_MULLIGAN and str(v[1].get("from", "")) == user:
			return true
	return false


func pending() -> bool:
	return not _held.is_empty() and (next_seq == -1 or _held.has(next_seq))


## Applies one message to the state. "" when it went through, else what went wrong (also kept in `desyncs`).
func apply(op: int, data: Dictionary) -> String:
	var why := ""
	match op:
		S_MULLIGAN:
			why = _apply_mulligan(data)
		S_TURN:
			why = _apply_turn(data)
		S_ACTION:
			why = _apply_action(data)
	if why != "":
		desyncs.append(why)
	return why


func _apply_mulligan(data: Dictionary) -> String:
	var side := side_of(str(data.get("from", "")))
	if side == -1:
		return "mulligan from an unknown player"
	if not st.in_mulligan():
		return "" # a late duplicate: nothing to do
	var d: Variant = data.get("data", {})
	var idx: Array = d.get("replace", []) if d is Dictionary else []
	var hand := st.sides[side].hand
	var uids := []
	for i in idx:
		var k := int(i)
		if k >= 0 and k < hand.size() and not uids.has(hand[k].uid):
			uids.append(hand[k].uid)
	st.finish_mulligan(side, uids)
	return ""


func _apply_turn(data: Dictionary) -> String:
	var active := side_of(str(data.get("active", "")))
	turn_ms = int(data.get("turn_ms", turn_ms))
	rope_ms = int(data.get("rope_ms", rope_ms))
	if st.winner != -1:
		return ""
	if str(data.get("reason", "")) == "start":
		if st.in_mulligan():
			return "turn 1 began before both mulligans"
		return "" if active == st.current else "first player differs"
	if st.in_mulligan():
		return "turn ended during the mulligan"
	st.end_turn()
	if st.winner == -1 and active != -1 and active != st.current:
		return "turn order differs (turn %d)" % st.turn
	return ""


func _apply_action(data: Dictionary) -> String:
	var side := side_of(str(data.get("from", "")))
	var a: Variant = data.get("data", {})
	if side == -1 or not (a is Dictionary):
		return "action from an unknown player"
	if st.winner != -1:
		return ""
	if a.has("ck") and str(a.ck) != st.checksum():
		desyncs.append("checksum differs before seq %d" % int(data.get("seq", 0)))
	var done := false
	match str(a.get("t", "")):
		"play":
			done = st.play_card(side, int(a.get("hand_uid", -1)), int(a.get("target", -1)), int(a.get("index", -1)))
		"attack":
			done = st.attack(side, int(a.get("attacker", -1)), int(a.get("target", -1)))
		"power":
			done = st.use_power(side, int(a.get("target", -1)))
	return "" if done else "an action was refused (%s)" % str(a.get("t", "?"))


# ---------------------------------------------------------------- outgoing payloads

func play_payload(hand_uid: int, target: int = -1, index: int = -1) -> Dictionary:
	return {"t": "play", "hand_uid": hand_uid, "target": target, "index": index, "ck": st.checksum()}


func attack_payload(attacker: int, target: int) -> Dictionary:
	return {"t": "attack", "attacker": attacker, "target": target, "ck": st.checksum()}


func power_payload(target: int = -1) -> Dictionary:
	return {"t": "power", "target": target, "ck": st.checksum()}


## The mulligan as hand indices (the server checks they are unique, 0-4).
func mulligan_payload(replace_uids: Array) -> Dictionary:
	var idx := []
	var hand := st.sides[0].hand
	for i in hand.size():
		if replace_uids.has(hand[i].uid):
			idx.append(i)
	return {"replace": idx}
