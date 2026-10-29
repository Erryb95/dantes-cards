extends SceneTree
## Rules fuzzer: AI-vs-AI and random-move games with the rules checked after every action.
##   Godot --headless --path . -s res://tests/fuzz_rules.gd -- --games=200 [--first=0] [--levels=0,1,3] [--hard=0.1]
##     [--replay=1] [--probe=0.15] [--game=N] [--verbose] [--cards]
## Game g (from --first, --games of them) is built from g alone, so a run can be split in shards and any game rerun with
## --game=g: random legal decks of every class or the preconstructed decks, a random seed, mulligan or not, a set or
## random first player, and per side an AI level from --levels (0 Easy, 1 Medium, 2 Hard, 3 random legal moves); --hard
## is the chance a side plays Hard instead (it is slow). Checked after every action: board, hand and mana limits,
## Health within max Health, no dead or 0-Health minion left, Wrath matching the damage, every uid in its place, the
## event stream telling the whole story (a mirror built only from events must match the state: stats, keywords,
## Freeze, Silence, hands, mana), Last Breath once per death (never after a transform or a bounce into a full hand),
## Rebirth (1/1, printed Attack and keywords, no Rebirth), Freeze thawing only when it cost an attack, Silenced minions
## never triggering, Frenzy once, no event after game_over, every game ending before the turn cap, the AI never
## changing the state while it thinks, never choosing a move the rules refuse and never looping. With --probe the
## random player also tries random (mostly illegal) actions: the engine must refuse exactly the ones the rules forbid,
## and a refused action must change nothing. Every --replay-th game is replayed from its seed and action log, as
## itself and flipped (the other online client's view), and must give the same checksum after every action; a
## clone() must print the same as its original but for the random stream and the deck order. Script errors are caught.
## --cards: instead plays every card in odd positions (empty and full boards, full hand, empty deck, a minion dying
## mid-effect, silenced / frozen / damaged / buffed targets, Last Breath and Rebirth minions killed, transformed,
## bounced into a full hand and copied) with the same checks.
## Output: one FUZZ line with the totals and one BUG line (with up to 3 examples) per kind of problem found.

const RunTests := preload("res://tests/run_tests.gd")
const KEYWORDS := ["guard", "swift", "ward", "drain", "venom", "rebirth"]
const MONKEY := 3
const LEVEL_NAMES := ["easy", "medium", "hard", "random"]
const TURN_ACTIONS := 80 ## more actions than this in one turn: someone is stuck in a loop


## The rules with two counters the checks need (no rule changes).
class FuzzState extends BattleState:
	var lb := {} ## uid -> times its Last Breath step ran
	var place_fails := 0 ## minions that found the board full

	func _last_breath(u: Unit, at: int) -> void:
		lb[u.uid] = int(lb.get(u.uid, 0)) + 1
		super(u, at)

	func _place(u: Unit, index: int = -1, from_card: int = -1) -> Unit:
		var r := super(u, index, from_card)
		if r == null:
			place_fails += 1
		return r


## Collects engine errors (script errors, push_error) so a game that hit one is reported.
class ErrLog extends Logger:
	var lines: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		lines.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		pass


var bugs := {} ## kind -> {n, ex: [up to 3 examples]}
var games_run := 0
var actions := 0
var probes := 0
var replays := 0
var draws := 0
var verbose := false
var probe_rate := 0.15
var _g := 0 ## the game being played (bug examples)
var _st: FuzzState
var _evs: Array = [] ## this game's events
var _over := false ## game_over was emitted
var _mirror := {} ## uid -> {attack, health, max_health, armor, kw: {}, frozen, silenced, side}
var _hands := [{}, {}] ## hand uids per side, from events
var _mana := [[0, 0], [0, 0]] ## [mana, max] per side, from events
var _act_deaths: Array = [] ## death events of the current action: [ev, had rebirth, id, side]
var _act_rebirths := {} ## "side:id" -> rebirth events in this action
var _dead := {} ## uids that died
var _frenzied := {} ## uids whose Frenzy went off
var _log: ErrLog


func _initialize() -> void:
	_log = ErrLog.new()
	OS.add_logger(_log)
	var games := 100
	var first := 0
	var levels: Array = [0, 1, 3]
	var hard := 0.1
	var replay_every := 1
	var only := -1
	var cards := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		elif a.begins_with("--first="):
			first = int(a.substr(8))
		elif a.begins_with("--levels="):
			levels = Array(a.substr(9).split(",")).map(func(x): return int(x))
		elif a.begins_with("--hard="):
			hard = float(a.substr(7))
		elif a.begins_with("--replay="):
			replay_every = int(a.substr(9))
		elif a.begins_with("--probe="):
			probe_rate = float(a.substr(8))
		elif a.begins_with("--game="):
			only = int(a.substr(7))
		elif a == "--verbose":
			verbose = true
		elif a == "--cards":
			cards = true
	var t0 := Time.get_ticks_msec()
	if cards:
		_card_sweep()
	elif only >= 0:
		_game(only, levels, hard, true)
	else:
		for g in range(first, first + games):
			_game(g, levels, hard, replay_every > 0 and g % replay_every == 0)
			if (g - first) % 50 == 49:
				print("  ... %d games, %d actions, %d bug kinds" % [g - first + 1, actions, bugs.size()])
	print("FUZZ: %d games, %d actions, %d probes, %d replays, %d turn-cap draws, %.0f s; %d kinds of bug" % [games_run,
		actions, probes, replays, draws, (Time.get_ticks_msec() - t0) / 1000.0, bugs.size()])
	var keys := bugs.keys()
	keys.sort()
	for k in keys:
		print("BUG %s (%d): %s" % [k, bugs[k].n, " || ".join(bugs[k].ex)])
	quit(1 if not bugs.is_empty() else 0)


func bug(kind: String, detail: String = "") -> void:
	var b: Dictionary = bugs.get(kind, {"n": 0, "ex": []})
	b.n += 1
	if b.ex.size() < 3:
		b.ex.append("g%d t%d %s" % [_g, _st.turn if _st != null else -1, detail])
	bugs[kind] = b
	if verbose:
		print("BUG %s: g%d %s" % [kind, _g, detail])


# ---------------------------------------------------------------- one game

func _game(g: int, levels: Array, hard: float, replay: bool) -> void:
	_g = g
	games_run += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5eed0000 + g * 7919
	var cfg := {}
	for s in 2:
		var precon := (g % 3 == 1) or (g % 3 == 2 and s == 1)
		if precon:
			var d: Dictionary = CardDB.decks()[rng.randi_range(0, CardDB.decks().size() - 1)]
			cfg["d%d" % s] = CardDB.deck_list(d.id)
			cfg["h%d" % s] = str(d.hero)
			cfg["n%d" % s] = str(d.id)
		else:
			var cls: String = CardDB.classes()[rng.randi_range(0, CardDB.classes().size() - 1)]
			cfg["d%d" % s] = RunTests.random_deck(cls, rng)
			cfg["h%d" % s] = CardDB.class_hero(cls)
			cfg["n%d" % s] = "random " + cls
		var lv: int = levels[rng.randi_range(0, levels.size() - 1)]
		if rng.randf() < hard:
			lv = BattleAI.Level.HARD
		cfg["l%d" % s] = lv
	# Every fifth game is chaos: decks of any 30 cards of the whole pool (tokens too, every class mixed) and a few
	# minions already in play, so cross-class combinations the real decks never meet get played.
	cfg.board = [[], []]
	if g % 5 == 4:
		var pool: Array = CardDB.all_cards().filter(func(c): return str(c.get("type", "")) in ["minion", "spell"])
		var minions: Array = pool.filter(func(c): return c.type == "minion")
		for s in 2:
			var d: Array[String] = []
			for i in 30:
				d.append(str(pool[rng.randi_range(0, pool.size() - 1)].id))
			cfg["d%d" % s] = d
			cfg["h%d" % s] = CardDB.class_hero(CardDB.classes()[rng.randi_range(0, CardDB.classes().size() - 1)])
			cfg["n%d" % s] = "chaos " + cfg["h%d" % s]
			for i in rng.randi_range(0, 3):
				cfg.board[s].append(str(minions[rng.randi_range(0, minions.size() - 1)].id))
	cfg.wait = rng.randf() < 0.5
	cfg.first = [-1, 0, 1][rng.randi_range(0, 2)]
	cfg.seed = rng.randi_range(1, 0x7fffffff)
	var mrng := RandomNumberGenerator.new() ## the random player's choices
	mrng.seed = cfg.seed ^ 0x2545F491
	if verbose:
		print("game %d: %s (%s) vs %s (%s), seed %d, mulligan %s, first %d" % [g, cfg.n0, LEVEL_NAMES[cfg.l0], cfg.n1,
			LEVEL_NAMES[cfg.l1], cfg.seed, cfg.wait, cfg.first])
	var errs0 := _log.lines.size()
	_st = FuzzState.new()
	_st.start_board = cfg.board.duplicate(true)
	var st := _st
	_reset_watch()
	st.event.connect(_on_event)
	st.start(cfg.d0, cfg.h0, cfg.d1, cfg.h1, cfg.seed, cfg.wait, cfg.first)
	var log: Array = [] ## every action that went through, with its side: replays apply them in order
	var cks: Array[String] = [st.checksum()] ## the checksum at the start and after each logged action
	_after_action(st, "start")
	var ais: Array = [BattleAI.new(0, cfg.l0 if cfg.l0 != MONKEY else 0), BattleAI.new(1, cfg.l1 if cfg.l1 != MONKEY else 0)]
	if st.in_mulligan():
		var order := [0, 1] if mrng.randf() < 0.5 else [1, 0]
		for s in order:
			for k in 3:
				_probe(st, s, mrng, log, cks) # nothing but the mulligan may happen now
			var uids: Array = []
			if cfg["l%d" % s] == MONKEY:
				for c in st.sides[s].hand:
					if mrng.randf() < 0.4:
						uids.append(c.uid)
				if mrng.randf() < 0.2:
					uids.append(st.sides[1 - s].hero.uid) # junk: not a hand card
				if not uids.is_empty() and mrng.randf() < 0.2:
					uids.append(uids[0]) # junk: twice the same card
			else:
				uids = ais[s].mulligan_choice(st)
			var hand0 := st.sides[s].hand.size()
			var total0: int = st.sides[s].hand.size() + st.sides[s].deck.size()
			st.finish_mulligan(s, uids)
			log.append({"do": "mull", "side": s, "uids": uids})
			cks.append(st.checksum())
			if st.in_mulligan() or st.turn > 0:
				var after: int = st.sides[s].hand.size() + st.sides[s].deck.size()
				if st.turn == 0 and (st.sides[s].hand.size() != hand0 or after != total0):
					bug("mulligan changes the card count", "%d+%d" % [hand0, total0])
			_after_action(st, "mulligan")
	var turn_acts := 0
	var turn_seen := st.turn
	var steps := 0
	while st.winner == -1 and steps < 20000:
		steps += 1
		var side := st.current
		if st.turn != turn_seen:
			turn_seen = st.turn
			turn_acts = 0
		var lv: int = cfg["l%d" % side]
		if lv == MONKEY and probe_rate > 0.0 and mrng.randf() < probe_rate:
			_probe(st, side, mrng, log, cks)
			if st.winner != -1:
				break
		var act: Dictionary
		if lv == MONKEY:
			act = _monkey(st, side, mrng)
		else:
			var ck := st.checksum()
			var n := _evs.size()
			act = ais[side].next_action(st)
			if st.checksum() != ck or _evs.size() != n:
				bug("the AI changed the battle while thinking", LEVEL_NAMES[lv])
		turn_acts += 1
		if turn_acts > TURN_ACTIONS and act.do != "end":
			bug("stuck: too many actions in one turn", "%s %s" % [LEVEL_NAMES[lv], act])
			act = {"do": "end"}
		var what := ""
		if act.do == "end":
			st.end_turn()
			log.append({"do": "end", "side": side})
			what = "end"
		else:
			var legal := _legal(st, side, act)
			var ck := st.checksum()
			var n := _evs.size()
			var done := BattleAI.apply(st, side, act)
			if not done:
				bug("%s chose a move the engine refused" % LEVEL_NAMES[lv], "%s legal-by-rules %s" % [act, legal])
				if st.checksum() != ck or _evs.size() != n:
					bug("a refused move changed the state", str(act))
				st.end_turn()
				log.append({"do": "end", "side": side})
				what = "end"
			else:
				if not legal:
					bug("the engine accepted a move the rules forbid", "%s %s" % [LEVEL_NAMES[lv], act])
				var la := act.duplicate()
				la.side = side
				log.append(la)
				what = str(act.do)
		cks.append(st.checksum())
		actions += 1
		_after_action(st, what)
		if actions % 23 == 0:
			_check_clone(st)
	if st.winner == -1:
		bug("game never ended", "%d steps" % steps)
	elif st.winner == 2:
		var dead0 := st.sides[0].hero.health <= 0
		var dead1 := st.sides[1].hero.health <= 0
		if not (dead0 and dead1):
			draws += 1
			bug("turn cap reached (a 90-turn draw)", "%s vs %s, %s/%s" % [cfg.n0, cfg.n1, LEVEL_NAMES[cfg.l0],
				LEVEL_NAMES[cfg.l1]])
	if _log.lines.size() > errs0:
		bug("engine error", "%s: %s" % [cfg.n0 + " vs " + cfg.n1, _log.lines[errs0]])
	if replay:
		_replay(cfg, log, cks, 0)
		if cfg.first != -1:
			_replay(cfg, log, cks, 1)


## Replays the game from its seed and log (flip 1: as the other online client builds it) and compares the checksums.
func _replay(cfg: Dictionary, log: Array, cks: Array[String], flip: int) -> void:
	replays += 1
	var rp := BattleState.new()
	rp.flip = flip
	rp.start_board = [cfg.board[flip], cfg.board[1 - flip]] # per local side
	var evs: Array = []
	if flip == 0:
		rp.event.connect(func(ev): evs.append(ev))
	rp.start(cfg.d0, cfg.h0, cfg.d1, cfg.h1, cfg.seed, cfg.wait, cfg.first)
	if rp.checksum() != cks[0]:
		bug("replay checksum differs at the start", "flip %d" % flip)
		return
	for i in log.size():
		var a: Dictionary = log[i]
		var s: int = int(a.side) ^ flip
		match a.do:
			"mull":
				rp.finish_mulligan(s, a.uids)
			"end":
				rp.end_turn()
			"end_probe":
				rp.end_turn()
			_:
				if not BattleAI.apply(rp, s, a):
					bug("replay refused a logged move", "flip %d step %d %s" % [flip, i, a])
					return
		if rp.checksum() != cks[i + 1]:
			bug("replay checksum differs", "flip %d step %d of %d (%s)" % [flip, i, log.size(), a])
			return
	if flip == 0 and str(evs) != str(_evs):
		bug("replay events differ", "%d vs %d events" % [evs.size(), _evs.size()])


## A clone prints the same as its original but for the random stream and the deck order (it reshuffles them), and
## making it changes nothing in the original.
func _check_clone(st: BattleState) -> void:
	var ck := st.checksum()
	var b := st.clone(int(st.rng.state) ^ 77)
	if _struct(b) != _struct(st):
		bug("clone differs from its original", "")
	if st.checksum() != ck:
		bug("clone changed its original", "")


static func _struct(st: BattleState) -> String:
	var parts := PackedStringArray([str(st.turn), str(st.current), str(st.winner), str(st._next_uid)])
	for s in st.sides:
		parts.append("|%s,%d,%d,%s,%d,%d" % [s.hero_id, s.mana, s.max_mana, s.power_used, s.fatigue, s.played])
		parts.append(BattleState._unit_print(s.hero))
		var deck := s.deck.duplicate()
		deck.sort()
		parts.append(",".join(deck))
		for h in s.hand:
			parts.append("%d:%s" % [h.uid, h.id])
		for u in s.board:
			parts.append(BattleState._unit_print(u))
	return "/".join(parts)


# ---------------------------------------------------------------- players

## A random legal move (end turn now and then).
func _monkey(st: BattleState, side: int, r: RandomNumberGenerator) -> Dictionary:
	var moves := _legal_moves(st, side, r)
	if moves.is_empty() or r.randf() < 0.07:
		return {"do": "end"}
	return moves[r.randi_range(0, moves.size() - 1)]


## Every legal move by the rules as written (not the engine's own can_* helpers), minions at a random board slot.
func _legal_moves(st: BattleState, side: int, r: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := st.sides[side]
	var foe := st.sides[1 - side]
	for c in me.hand:
		var card := CardDB.card(c.id)
		var tt := _ttype(card)
		var targets: Array = [-1]
		if tt != "":
			targets = _valid(st, side, tt)
			if card.type == "minion":
				targets.append(-1)
		for t in targets:
			var m := {"do": "play", "uid": c.uid, "target": t, "index": r.randi_range(-1, me.board.size())}
			if _legal(st, side, m):
				out.append(m)
	for u in me.board:
		for t in [foe.hero] + foe.board:
			var m := {"do": "attack", "attacker": u.uid, "target": t.uid}
			if _legal(st, side, m):
				out.append(m)
	var ptt := _power_ttype(me.hero_id)
	for t in ([-1] if ptt == "" else _valid(st, side, ptt)):
		var m := {"do": "power", "target": t}
		if _legal(st, side, m):
			out.append(m)
	return out


## A random action, legal or not: the engine must take it exactly when the rules allow it, and change nothing when
## it refuses. During the mulligan nothing at all may happen (an end of turn included).
func _probe(st: FuzzState, side: int, r: RandomNumberGenerator, log: Array, cks: Array[String]) -> void:
	probes += 1
	var s := side if r.randf() < 0.8 else 1 - side
	var pool: Array = [-1, 0, 3, 999999]
	for c in st.sides[0].hand + st.sides[1].hand:
		pool.append(c.uid)
	pool.append_array(st.units.keys())
	var a := {}
	match r.randi_range(0, 3):
		0:
			var hand: Array = st.sides[s].hand if r.randf() < 0.85 or st.sides[1 - s].hand.is_empty() else st.sides[1 - s].hand
			var uid: int = hand[r.randi_range(0, hand.size() - 1)].uid if not hand.is_empty() else 12345
			a = {"do": "play", "uid": uid, "target": pool[r.randi_range(0, pool.size() - 1)], "index": r.randi_range(-3, 9)}
		1:
			a = {"do": "attack", "attacker": pool[r.randi_range(0, pool.size() - 1)], "target": pool[r.randi_range(0, pool.size() - 1)]}
		2:
			a = {"do": "power", "target": pool[r.randi_range(0, pool.size() - 1)]}
		3:
			if not st.in_mulligan():
				return
			a = {"do": "end"}
	var legal := _legal(st, s, a)
	var ck := st.checksum()
	var n := _evs.size()
	var done := false
	if a.do == "end":
		st.end_turn()
		done = st.checksum() != ck
	else:
		done = BattleAI.apply(st, s, a)
	if done != legal:
		bug("probe: the engine %s a move the rules %s" % ["took" if done else "refused", "forbid" if done else "allow"],
			"%s side %d mulligan %s" % [a, s, st.in_mulligan()])
	if not done and (st.checksum() != ck or _evs.size() != n):
		bug("probe: a refused move changed the state", str(a))
	if done:
		var la := a.duplicate()
		la.side = s
		log.append(la)
		cks.append(st.checksum())
		actions += 1
		_after_action(st, "probe")


# ---------------------------------------------------------------- the rules as written (docs/DESIGN.md "Rules")

static func _ttype(card: Dictionary) -> String:
	for e in card.get("effects", []):
		if e.get("on", "play") == "play" and str(e.get("target", "")).begins_with("choose_"):
			return str(e.target)
	return ""


static func _power_ttype(hero_id: String) -> String:
	for e in CardDB.hero(hero_id).get("power", {}).get("effects", []):
		if str(e.get("target", "")).begins_with("choose_"):
			return str(e.target)
	return ""


static func _valid(st: BattleState, side: int, tt: String) -> Array:
	var me := st.sides[side]
	var foe := st.sides[1 - side]
	var out: Array = []
	if tt in ["choose_any"]:
		out.append(me.hero.uid)
	if tt in ["choose_any", "choose_enemy"]:
		out.append(foe.hero.uid)
	if tt in ["choose_any", "choose_minion", "choose_friendly_minion"]:
		for u in me.board:
			out.append(u.uid)
	if tt in ["choose_any", "choose_minion", "choose_enemy", "choose_enemy_minion"]:
		for u in foe.board:
			out.append(u.uid)
	return out


static func _legal(st: BattleState, side: int, a: Dictionary) -> bool:
	if st.winner != -1 or st.in_mulligan() or side != st.current:
		return false
	var me := st.sides[side]
	var foe := st.sides[1 - side]
	match a.do:
		"play":
			var c := {}
			for h in me.hand:
				if h.uid == int(a.uid):
					c = h
			if c.is_empty():
				return false
			var card := CardDB.card(c.id)
			if int(card.cost) > me.mana:
				return false
			if card.type == "minion" and me.board.size() >= BattleState.MAX_BOARD:
				return false
			var tt := _ttype(card)
			if tt == "":
				return true
			var valid := _valid(st, side, tt)
			if card.type == "spell":
				return valid.has(int(a.target))
			return int(a.target) == -1 or valid.has(int(a.target))
		"attack":
			var u = null
			for m in me.board:
				if m.uid == int(a.attacker):
					u = m
			if u == null or u.sleeping or u.attacks_made > 0 or u.frozen or u.attack <= 0:
				return false
			var guards: Array = foe.board.filter(func(m): return m.has("guard"))
			for m in foe.board:
				if m.uid == int(a.target):
					return guards.is_empty() or m.has("guard")
			return int(a.target) == foe.hero.uid and guards.is_empty()
		"power":
			var h := CardDB.hero(me.hero_id)
			if me.power_used or int(h.power.cost) > me.mana:
				return false
			var tt := _power_ttype(me.hero_id)
			return tt == "" or _valid(st, side, tt).has(int(a.target))
	return false


# ---------------------------------------------------------------- the event stream

func _reset_watch() -> void:
	_evs = []
	_over = false
	_mirror = {}
	_hands = [{}, {}]
	_mana = [[0, 0], [0, 0]]
	_act_deaths = []
	_act_rebirths = {}
	_dead = {}
	_frenzied = {}


func _mirror_unit(snap: Dictionary) -> void:
	var kw := {}
	for k in snap.keywords:
		kw[str(k)] = true
	_mirror[int(snap.uid)] = {"attack": int(snap.attack), "health": int(snap.health), "max_health": int(snap.max_health),
		"armor": int(snap.armor), "kw": kw, "frozen": bool(snap.frozen), "silenced": bool(snap.silenced),
		"side": int(snap.side), "id": str(snap.id)}


func _on_event(ev: Dictionary) -> void:
	_evs.append(ev)
	var st := _st
	if _over:
		bug("an event after game_over", str(ev.t))
	match str(ev.t):
		"start":
			for h in ev.heroes:
				_mirror_unit(h)
		"summon":
			_mirror_unit(ev.unit)
			var u: Dictionary = ev.unit
			if int(u.health) <= 0 or int(u.health) > int(u.max_health):
				bug("a minion entered with bad Health", str(u))
		"damage", "heal":
			var m: Dictionary = _mirror.get(int(ev.uid), {})
			if m.is_empty():
				bug("%s on an unknown unit" % ev.t, str(ev))
			else:
				m.health = int(ev.hp)
				if ev.t == "damage":
					m.armor = int(ev.armor)
		"armor":
			if _mirror.has(int(ev.uid)):
				_mirror[int(ev.uid)].armor = int(ev.armor)
		"buff", "status":
			var m: Dictionary = _mirror.get(int(ev.uid), {})
			if m.is_empty():
				bug("%s on an unknown unit" % ev.t, str(ev))
			else:
				if ev.t == "status":
					var u: BattleState.Unit = st.units.get(int(ev.uid))
					if bool(ev.silenced) and not m.silenced:
						# Silence keeps the stats (but the Wrath bonus, already reported) and keeps a Frozen minion frozen.
						if bool(ev.frozen) != m.frozen and not bool(ev.frozen):
							bug("Silence thawed a minion", str(ev))
						if int(ev.attack) != m.attack or int(ev.health) != m.health or int(ev.max_health) != m.max_health:
							bug("Silence changed the stats", "%s mirror %s" % [ev, m])
						if u != null and (u.wrath != 0 or u.rage != 0):
							bug("Silence left the Wrath", u.id)
					if bool(m.silenced) and not bool(ev.silenced):
						bug("a minion lost its Silence", str(ev))
					if m.frozen and not bool(ev.frozen) and u != null \
							and (u.side != st.current or u.sleeping or u.attacks_made != 0):
						bug("a minion thawed before the freeze cost it an attack", "%s asleep %s attacks %d" % [u.id,
							u.sleeping, u.attacks_made])
					m.frozen = bool(ev.frozen)
					m.silenced = bool(ev.silenced)
				m.attack = int(ev.attack)
				m.health = int(ev.health)
				m.max_health = int(ev.max_health)
				var kw := {}
				for k in ev.keywords:
					kw[str(k)] = true
				m.kw = kw
		"wrath":
			if _mirror.has(int(ev.uid)):
				_mirror[int(ev.uid)].attack = int(ev.attack)
		"ward_break":
			var m: Dictionary = _mirror.get(int(ev.uid), {})
			if m.is_empty() or not m.kw.has("ward"):
				bug("a Ward broke that was not there", str(ev))
			else:
				m.kw.erase("ward")
		"death":
			var uid := int(ev.uid)
			if _dead.has(uid):
				bug("a minion died twice", str(ev))
			_dead[uid] = true
			if st.units.has(uid):
				bug("a dead minion is still in play", str(ev))
			var m: Dictionary = _mirror.get(uid, {})
			_act_deaths.append([ev, not m.is_empty() and m.kw.has("rebirth"), str(m.get("id", "")), int(ev.side)])
			_mirror.erase(uid)
		"bounce":
			_mirror.erase(int(ev.uid))
			_hands[int(ev.side)][int(ev.card_uid)] = true
		"rebirth":
			var u: BattleState.Unit = st.units.get(int(ev.uid))
			if u == null:
				bug("Rebirth of a unit not in play", str(ev))
			else:
				var key := "%d:%s" % [u.side, u.id]
				_act_rebirths[key] = int(_act_rebirths.get(key, 0)) + 1
				var card := CardDB.card(u.id)
				var want: Array = card.get("keywords", []).filter(func(k): return k != "rebirth")
				var have: Array = u.keywords.keys()
				want.sort()
				have.sort()
				if u.health != 1 or u.max_health != 1 or u.attack != int(card.get("attack", 0)) or want != have \
						or u.silenced or u.frozen:
					bug("Rebirth brought back the wrong minion", "%s %d/%d/%d %s" % [u.id, u.attack, u.health,
						u.max_health, have])
		"trigger":
			var u: BattleState.Unit = st.units.get(int(ev.uid))
			if u == null or u.dead or u.silenced or not st.sides[u.side].board.has(u):
				bug("a trigger from a minion not in play or silenced", str(ev))
		"frenzy":
			var u: BattleState.Unit = st.units.get(int(ev.uid))
			if u == null or u.dead or u.silenced or u.health <= 0 or not st.sides[u.side].board.has(u):
				bug("Frenzy from a minion dead, gone or silenced", str(ev))
			if _frenzied.has(int(ev.uid)):
				bug("Frenzy went off twice", str(ev))
			_frenzied[int(ev.uid)] = true
		"draw":
			_hands[int(ev.side)][int(ev.uid)] = true
		"play":
			if not _hands[int(ev.side)].has(int(ev.uid)):
				bug("played a card the events never put in the hand", str(ev))
			_hands[int(ev.side)].erase(int(ev.uid))
		"steal":
			if str(ev.zone) == "hand":
				if not _hands[int(ev.from)].has(int(ev.uid)):
					bug("stole a hand card the events never showed", str(ev))
				_hands[int(ev.from)].erase(int(ev.uid))
		"mulligan_swap":
			_hands[int(ev.side)].erase(int(ev.old))
			_hands[int(ev.side)][int(ev.uid)] = true
		"mana":
			_mana[int(ev.side)] = [int(ev.mana), int(ev.max)]
		"turn":
			var s := st.sides[int(ev.side)]
			if s.mana != s.max_mana or s.power_used or s.played != 0:
				bug("a turn began without full mana / a fresh hero power", "")
			for u in s.board:
				if u.sleeping or u.attacks_made != 0:
					bug("a minion did not wake at the start of its turn", u.id)
		"turn_end":
			# Freeze costs one attack: a minion still frozen at the end of its owner's turn is one the freeze has not
			# taken an attack from yet (asleep, or it attacked before it was frozen).
			for u in st.sides[int(ev.side)].board:
				if u.frozen and not u.sleeping and u.attacks_made == 0:
					bug("a frozen minion did not thaw after losing its attack", u.id)
		"game_over":
			_over = true


## Checks run after every action: the state itself, and the state against what the events said.
func _after_action(st: FuzzState, what: String) -> void:
	var seen := {}
	var count := 0
	for i in 2:
		var s := st.sides[i]
		if s.board.size() > BattleState.MAX_BOARD:
			bug("board over 7")
		if s.hand.size() > BattleState.MAX_HAND:
			bug("hand over 10")
		if s.mana < 0 or s.mana > BattleState.MAX_MANA or s.max_mana < 0 or s.max_mana > BattleState.MAX_MANA:
			bug("mana out of range", "%d/%d" % [s.mana, s.max_mana])
		var h := s.hero
		if st.units.get(h.uid) != h or h.side != i or not h.is_hero:
			bug("hero out of place")
		if h.health > h.max_health or h.armor < 0:
			bug("hero Health or Armor out of range", "%d/%d %d" % [h.health, h.max_health, h.armor])
		if st.winner == -1 and h.health <= 0:
			bug("a hero at 0 Health but the game goes on", what)
		count += 1
		for u in s.board:
			count += 1
			if seen.has(u.uid):
				bug("a uid twice on the boards")
			seen[u.uid] = true
			if u.dead or u.health <= 0:
				bug("a dead minion left on the board", "%s after %s" % [u.id, what])
			if u.health > u.max_health:
				bug("minion Health above its max", "%s %d/%d" % [u.id, u.health, u.max_health])
			if u.attack < 0:
				bug("negative Attack", u.id)
			if st.units.get(u.uid) != u or u.side != i or u.is_hero:
				bug("minion out of place", u.id)
			if u.attacks_made > 1:
				bug("a minion attacked twice", u.id)
			if not RunTests._wrath_sane(u):
				bug("Wrath does not match the damage", "%s rage %d wrath %d %d/%d" % [u.id, u.rage, u.wrath, u.health,
					u.max_health])
			if u.silenced and (u.wrath != 0 or u.rage != 0):
				bug("a silenced minion keeps its Wrath", u.id)
			for k in u.keywords:
				if not k in KEYWORDS:
					bug("unknown keyword", k)
			if CardDB.card(u.id).get("type", "") != "minion":
				bug("a non-minion on the board", u.id)
		for c in s.hand:
			if seen.has(c.uid):
				bug("a uid used twice", str(c))
			seen[c.uid] = true
			if CardDB.card(c.id).is_empty():
				bug("an unknown card in hand", str(c.id))
		var hk := {}
		for c in s.hand:
			hk[c.uid] = true
		if hk != _hands[i]:
			bug("the events do not match the hand", "side %d after %s" % [i, what])
			_hands[i] = hk
		if _mana[i] != [s.mana, s.max_mana] and not (s.max_mana == 0 and s.mana == 0):
			bug("the events do not match the mana", "side %d %s vs %d/%d after %s" % [i, _mana[i], s.mana, s.max_mana,
				what])
			_mana[i] = [s.mana, s.max_mana]
	if st.units.size() != count:
		bug("units holds minions not on a board", "%d vs %d" % [st.units.size(), count])
	# The view rebuilds every unit from the events alone.
	for uid in st.units:
		var u: BattleState.Unit = st.units[uid]
		var m: Dictionary = _mirror.get(uid, {})
		if m.is_empty():
			bug("a unit the events never showed", u.id)
			continue
		var kw := {}
		for k in u.keywords:
			kw[k] = true
		if m.attack != u.attack or m.health != u.health or m.max_health != u.max_health or m.kw != kw \
				or (not u.is_hero and (m.frozen != u.frozen or m.silenced != u.silenced)) or (u.is_hero and m.armor != u.armor):
			bug("the events do not match a unit", "%s after %s: events %s state %d/%d/%d %s fr %s si %s ar %d" % [u.id, what,
				m, u.attack, u.health, u.max_health, kw.keys(), u.frozen, u.silenced, u.armor])
			_mirror_unit(u.snapshot())
	if _mirror.size() != st.units.size():
		bug("the events show units that are gone", "%d vs %d after %s" % [_mirror.size(), st.units.size(), what])
		_mirror = {}
		for uid in st.units:
			_mirror_unit(st.units[uid].snapshot())
	# Last Breath once per death; never for a transform or a minion lost to a full hand; Rebirth for each that had it.
	var want_rb := {}
	for d in _act_deaths:
		var ev: Dictionary = d[0]
		var how := str(ev.how)
		var n := int(st.lb.get(int(ev.uid), 0))
		if how in ["transform", "bounce"]:
			if n != 0:
				bug("Last Breath after a %s" % how, str(d[2]))
		else:
			if n != 1:
				bug("Last Breath ran %d times" % n, str(d[2]))
			if d[1]:
				var key := "%d:%s" % [d[3], d[2]]
				want_rb[key] = int(want_rb.get(key, 0)) + 1
	for key in want_rb.keys() + _act_rebirths.keys():
		var got := int(_act_rebirths.get(key, 0))
		var want := int(want_rb.get(key, 0))
		if got > want or (got < want and st.place_fails == 0):
			bug("Rebirth count wrong", "%s: %d of %d after %s" % [key, got, want, what])
	_act_deaths = []
	_act_rebirths = {}
	st.place_fails = 0


# ---------------------------------------------------------------- every card in odd positions

## A battle with empty hands and boards, 10 mana each, `deck` cards in each deck (0: fatigue), side 0 to play.
func _blank(deck: int = 20) -> FuzzState:
	var st := FuzzState.new()
	_st = st
	_reset_watch()
	st.event.connect(_on_event)
	var filler: Array[String] = []
	for i in 20:
		filler.append("lost_pilgrim")
	st.start(filler, "dante", filler.duplicate(), "charon", 7, false, 0)
	for s in 2:
		var side := st.sides[s]
		for c in side.hand.duplicate():
			_hands[s].erase(c.uid)
		side.hand.clear()
		side.mana = 10
		side.max_mana = 10
		_mana[s] = [10, 10]
		if deck == 0:
			side.deck.clear()
	return st


func _put(st: FuzzState, side: int, id: String) -> BattleState.Unit:
	var u := st._summon(side, id)
	if u != null:
		u.sleeping = false
	return u


func _give(st: FuzzState, side: int, id: String) -> int:
	var c := {"uid": st._uid(), "id": id}
	st.sides[side].hand.append(c)
	_hands[side][c.uid] = true
	return c.uid


## Odd minions to fill boards with: Ward, Guard, Rebirth, Last Breath, Frenzy, Wrath, Venom, turn triggers.
const CROWD := ["paolo", "cerberus", "cd_nameless_bush", "stung_neutral", "wr_mud_wrestler", "uh_wrathful_shade",
	"harpy", "cd_nessus", "ul_trojan_horse", "wr_brawling_shade", "mc_agnello", "cd_epicurus", "wr_tydeus",
	"uh_filippo_argenti"]


## The scenario `k` for playing card `id` from side 0: what is on the boards and in the hands.
func _scenario(k: int, id: String) -> FuzzState:
	var st := _blank(0 if k == 4 else 20)
	var crowd := func(side: int, n: int, off: int) -> void:
		for i in n:
			_put(st, side, CROWD[(i + off) % CROWD.size()])
	match k:
		0: # empty boards
			pass
		1: # my board full but one (a minion card) / full (a spell)
			crowd.call(0, 6 if CardDB.card(id).type == "minion" else 7, 0)
			_put(st, 1, "she_wolf")
		2: # the enemy board full of odd minions
			crowd.call(1, 7, 3)
			_put(st, 0, "geryon")
		3: # a full hand (draws and added cards burn)
			crowd.call(0, 3, 5)
			crowd.call(1, 3, 8)
			for i in 9:
				_give(st, 0, "cd_burning_sand")
			for i in 10:
				_give(st, 1, "lost_pilgrim")
		4: # empty decks: fatigue
			crowd.call(0, 2, 1)
			crowd.call(1, 2, 2)
		5: # damaged, buffed, silenced, frozen minions on both sides; Ruse on
			crowd.call(0, 4, 4)
			crowd.call(1, 5, 9)
			for s in 2:
				for u in st.sides[s].board:
					match u.uid % 4:
						0:
							st._damage(u, 1, null, "fuzz")
						1:
							st._resolve({"do": "buff", "target": "self", "attack": 2, "health": 2}, s, u, -1, "fuzz")
						2:
							st._resolve({"do": "silence", "target": "self"}, s, u, -1, "fuzz")
						3:
							st._resolve({"do": "freeze", "target": "self"}, s, u, -1, "fuzz")
			st._cleanup()
			st.sides[0].played = 1
		6: # both heroes nearly dead: the game may end mid-effect
			crowd.call(0, 3, 6)
			crowd.call(1, 3, 2)
			st.sides[0].hero.health = 2
			st.sides[1].hero.health = 2
			_mirror[st.sides[0].hero.uid].health = 2
			_mirror[st.sides[1].hero.uid].health = 2
	st.place_fails = 0
	_act_deaths = []
	return st


func _card_sweep() -> void:
	var ids: Array = []
	for c in CardDB.all_cards():
		if str(c.get("type", "")) in ["minion", "spell"]:
			ids.append(str(c.id))
	ids.sort()
	var errs0 := _log.lines.size()
	for id in ids:
		_g = ids.find(id)
		var card := CardDB.card(id)
		for k in 7:
			# Every target the card can take here (and none), each in a fresh copy of the scenario.
			var probe := _scenario(k, id)
			var targets: Array = [-1]
			var tt := _ttype(card)
			if tt != "":
				targets = _valid(probe, 0, tt)
				if card.type == "minion" or targets.is_empty():
					targets.append(-1)
			for t in targets:
				var st := _scenario(k, id)
				var uid := _give(st, 0, id)
				var legal := _legal(st, 0, {"do": "play", "uid": uid, "target": t, "index": -1})
				var ck := st.checksum()
				var done := st.play_card(0, uid, t)
				games_run += 1
				if done != legal:
					bug("card sweep: play %s" % ("taken against the rules" if done else "refused"), "%s scen %d target %d" % [id,
						k, t])
				if not done and st.checksum() != ck:
					bug("card sweep: a refused play changed the state", id)
				_after_action(st, "%s scen %d" % [id, k])
				actions += 1
				# Then two turn ends: its turn triggers fire on both sides.
				for i in 2:
					if st.winner != -1:
						break
					st.end_turn()
					_after_action(st, "%s scen %d end %d" % [id, k, i])
					actions += 1
		if card.type == "minion":
			_minion_fates(id)
		if _log.lines.size() > errs0:
			bug("engine error", "%s: %s" % [id, _log.lines[errs0]])
			errs0 = _log.lines.size()


## A minion of card `id` on the board meets every way out: killed (with and without Silence), destroyed, killed while
## its board is full (Last Breath summons and Rebirth find no room), transformed, bounced into a full hand, copied
## after being damaged and buffed (Capocchio), fought, and killed by the end of its own turn.
func _minion_fates(id: String) -> void:
	var fates := ["kill", "silence_kill", "destroy", "full_board_kill", "transform", "bounce_full", "copy", "fight",
		"frozen_copy", "venom", "attacked"]
	for f in fates:
		var st := _scenario(0, id)
		var u := _put(st, 1, id)
		var wolf := _put(st, 0, "she_wolf" if f != "attacked" else "cd_old_man_crete")
		var spell := ""
		var target := u.uid
		match f:
			"kill":
				spell = "wr_eternal_fire" # 5 damage
				st._damage(u, maxi(0, u.health - 3), null, "fuzz")
				st._cleanup()
			"silence_kill":
				st._resolve({"do": "silence", "target": "self"}, 1, u, -1, "fuzz")
				spell = "cd_furys_lash"
			"destroy":
				spell = "cd_furys_lash"
			"full_board_kill":
				for i in 6:
					_put(st, 1, "lost_soul")
				spell = "cd_furys_lash"
			"transform":
				spell = "ul_circes_draught"
			"bounce_full":
				for i in 10:
					_give(st, 1, "lost_pilgrim")
				spell = "turned_back"
			"copy":
				st._damage(u, 1, null, "fuzz")
				st._resolve({"do": "buff", "target": "self", "attack": 1, "health": 2}, 1, u, -1, "fuzz")
				st._cleanup()
				spell = "ul_capocchio"
			"fight":
				spell = "wr_marsh_champion"
			"frozen_copy":
				st._resolve({"do": "freeze", "target": "self"}, 1, u, -1, "fuzz")
				spell = "ul_capocchio"
			"venom", "attacked":
				if f == "attacked" and u.health > 1:
					st._damage(u, u.health - 1, null, "fuzz") # the wolf's blow kills it: a Last Breath may freeze the wolf
					st._cleanup()
		st.place_fails = 0
		_act_deaths = []
		if not st.units.has(target):
			_after_action(st, "%s %s setup" % [id, f])
			continue
		_after_action(st, "%s %s setup" % [id, f])
		if f == "venom" or f == "attacked":
			var h := _put(st, 0, "harpy") if f == "venom" else wolf
			if not st.attack(0, h.uid, target) and st.attack_targets(0).has(target):
				bug("fates: attack refused", id)
		else:
			var hu := _give(st, 0, spell)
			var ok := st.play_card(0, hu, target)
			if not ok and st.valid_targets(0, _ttype(CardDB.card(spell))).has(target):
				bug("fates: %s refused" % spell, id)
		_after_action(st, "%s %s" % [id, f])
		actions += 1
		games_run += 1
		for i in 2:
			if st.winner != -1:
				break
			st.end_turn()
			_after_action(st, "%s %s end %d" % [id, f, i])
			actions += 1
		if f == "copy" and st.winner == -1 and not id in ["she_wolf", "ul_capocchio"]:
			for c in st.sides[0].board:
				if c.id == id and c.uid != target and st.units.has(target):
					var o: BattleState.Unit = st.units[target]
					if c.max_health != o.max_health:
						bug("fates: the copy lost the buffs", id)
