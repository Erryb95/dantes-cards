extends SceneTree
## Card-flow probe: does a preconstructed deck run out of cards? Hard vs Hard, every cross-class pair of decks
## (each deal played from both seats, the same deals as ai_duel.gd's --decks), and for every deck it reports:
## the hand size at the start of each of its turns (after the draw), the first turn it starts with 0-1 cards, the
## share of its turns from turn 6 on that start with 0-1 cards, the mana it leaves unspent from turn 5 on (and how
## often it leaves 2+ mana unspent while still holding a card it could play), fatigue, game length, the cards it
## drew and was given, and its win rate against the other classes.
##   Godot --headless --path . -s res://tests/card_flow.gd -- --games=40 [--deck=<id>,... | --decks=<a>,<b>]
##         [--shard=<i>/<k>] [--out=<file.json>] [--patch=<file.json>]
##   Godot --headless --path . -s res://tests/card_flow.gd -- --merge=<a.json>,<b.json>,... [--deck=<id>,...]
## --games: games per pair of decks (even: both seats). --deck: only the pairs with one of those decks (and only
## those decks in the report). --shard=i/k: pair i, i + k, i + 2k... (run k processes, write each with --out, then
## --merge to sum them). "Turn" is the deck's own turn number.
## --cards adds, per deck, each card's games in hand, play rate, win rate when played and how often it was stuck in hand.
## --patch (tuning without touching data/): {"decks": {"<deck id>": {"<card id>": +/-copies}}, "cards": {"<card id>":
## {"cost": 3, ...}}} changes the loaded decks and cards for this run only.

const TURNS := 15
const LATE_FROM := 6 ## "late game" for the 0-1 card share
const MANA_FROM := 5 ## unspent mana counted from this own turn on


func _initialize() -> void:
	var games := 40
	var only := PackedStringArray()
	var pair := PackedStringArray()
	var shard := [0, 1]
	var out := ""
	var merge := PackedStringArray()
	var show_cards := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		elif a.begins_with("--deck="):
			only = a.substr(7).split(",")
		elif a.begins_with("--patch="):
			_patch(a.substr(8))
		elif a.begins_with("--decks="):
			pair = a.substr(8).split(",")
		elif a.begins_with("--shard="):
			var p := a.substr(8).split("/")
			shard = [int(p[0]), int(p[1])]
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--cards":
			show_cards = true
		elif a.begins_with("--merge="):
			merge = a.substr(8).split(",")
	var acc := {}
	if not merge.is_empty():
		for path in merge:
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				push_error("card_flow: cannot read %s" % path)
				continue
			_add(acc, JSON.parse_string(f.get_as_text()))
		_print_report(acc, only, show_cards)
		quit()
		return
	var pairs := []
	if pair.size() == 2:
		pairs.append([pair[0], pair[1]])
	else:
		var all := CardDB.decks()
		for i in all.size():
			for j in range(i + 1, all.size()):
				if CardDB.deck_class(all[i]) == CardDB.deck_class(all[j]):
					continue
				if not only.is_empty() and not (all[i].id in only or all[j].id in only):
					continue
				pairs.append([all[i].id, all[j].id])
	var t0 := Time.get_ticks_msec()
	for k in pairs.size():
		if k % int(shard[1]) != int(shard[0]):
			continue
		for g in games:
			_game(pairs[k][0], pairs[k][1], g, acc)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(acc))
		f.close()
	_print_report(acc, only, show_cards)
	print("card_flow: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


## Applies a tuning patch to the loaded data (CardDB hands out its own dictionaries, so the change holds for the run).
func _patch(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("card_flow: cannot read %s" % path)
		return
	var p: Dictionary = JSON.parse_string(f.get_as_text())
	for id in p.get("cards", {}):
		var c := CardDB.card(id)
		for k in p.cards[id]:
			c[k] = p.cards[id][k]
	for id in p.get("decks", {}):
		var cards: Dictionary = CardDB.deck(id).cards
		for c in p.decks[id]:
			var n := int(cards.get(c, 0)) + int(p.decks[id][c])
			if n > 0:
				cards[c] = n
			else:
				cards.erase(c)
		if CardDB.deck_list(id).size() != 30:
			push_error("card_flow: patched deck %s has %d cards" % [id, CardDB.deck_list(id).size()])


func _blank() -> Dictionary:
	var z := []
	z.resize(TURNS + 1)
	z.fill(0)
	return {"games": 0, "wins": 0, "draws": 0, "hand": z.duplicate(), "hand_end": z.duplicate(), "hand_n": z.duplicate(),
		"low_games": 0, "low_turn": 0, "late_turns": 0, "late_low": 0, "mana_turns": 0, "unspent": 0, "floated": 0,
		"late_power": 0, "fatigue_games": 0, "fatigue_dmg": 0, "turns": 0, "own_turns": 0, "drawn": 0, "made": 0,
		"burned": 0, "vs": {}, "cards": {}}


## Adds one shard's numbers (or one game's) into `acc`.
func _add(acc: Dictionary, part: Dictionary) -> void:
	for id in part:
		if not acc.has(id):
			acc[id] = _blank()
		var a: Dictionary = acc[id]
		var p: Dictionary = part[id]
		for k in p:
			if p[k] is Array:
				for i in p[k].size():
					a[k][i] += int(p[k][i])
			elif p[k] is Dictionary:
				for c in p[k]:
					var v: Array = a[k].get(c, [])
					v.resize(p[k][c].size())
					for i in v.size():
						v[i] = int(v[i] if v[i] != null else 0) + int(p[k][c][i])
					a[k][c] = v
			else:
				a[k] += int(p[k])


## One game between decks a and b; game g: deal g >> 1, deck a in seat (g & 1).
func _game(id_a: String, id_b: String, g: int, acc: Dictionary) -> void:
	var swap := g % 2 == 1
	var ids := [id_a, id_b] if not swap else [id_b, id_a] # by seat
	var decks := [CardDB.deck(ids[0]), CardDB.deck(ids[1])]
	var st := BattleState.new()
	var rec := [_blank(), _blank()] # by seat
	var deck_n := [30, 30]
	var low := [0, 0] ## first own turn that started with 0-1 cards
	var fatigued := [false, false]
	var seen := [{}, {}] ## card ids that reached the hand (drawn or given)
	var played := [{}, {}]
	st.event.connect(_on_event.bind(rec, deck_n, fatigued, seen))
	st.start(CardDB.deck_list(decks[0].id), decks[0].hero, CardDB.deck_list(decks[1].id), decks[1].hero,
		300 + (g >> 1), false, -1)
	var ais := [BattleAI.new(0, BattleAI.Level.HARD), BattleAI.new(1, BattleAI.Level.HARD)]
	var own := [0, 0]
	var seen_turn := -1
	var steps := 0
	while st.winner == -1 and steps < 6000:
		steps += 1
		var cur := st.current
		var me := st.sides[cur]
		if st.turn != seen_turn:
			seen_turn = st.turn
			own[cur] += 1
			var t: int = own[cur]
			if t <= TURNS:
				rec[cur].hand[t] += me.hand.size()
				rec[cur].hand_n[t] += 1
			if t >= LATE_FROM:
				rec[cur].late_turns += 1
				rec[cur].late_low += int(me.hand.size() <= 1)
			if me.hand.size() <= 1 and low[cur] == 0:
				low[cur] = t
		var act: Dictionary = ais[cur].next_action(st)
		if act.do == "play":
			played[cur][str(st.hand_card(cur, act.uid).get("id", ""))] = true
		if act.do == "end" or not BattleAI.apply(st, cur, act):
			if st.winner != -1:
				break
			var t: int = own[cur]
			if t <= TURNS:
				rec[cur].hand_end[t] += me.hand.size()
			if t >= MANA_FROM:
				rec[cur].mana_turns += 1
				rec[cur].unspent += me.mana
				rec[cur].late_power += int(me.power_used)
				if me.mana >= 2:
					for c in me.hand:
						if st.can_play(cur, c.uid):
							rec[cur].floated += 1
							break
			st.end_turn()
	for s in 2:
		var r: Dictionary = rec[s]
		r.games = 1
		r.wins = int(st.winner == s)
		r.draws = int(st.winner == 2)
		r.turns = st.turn
		r.own_turns = own[s]
		r.fatigue_games = int(fatigued[s])
		if low[s] > 0:
			r.low_games = 1
			r.low_turn = low[s]
		r.vs = {CardDB.deck_class(decks[1 - s]): [r.wins, 1]}
		# Per card: [games it reached the hand, games it was played, of those won, games it was still in hand at the end]
		var held := {}
		for c in st.sides[s].hand:
			held[c.id] = true
		for id in seen[s]:
			r.cards[id] = [1, int(played[s].has(id)), int(played[s].has(id) and st.winner == s), int(held.has(id))]
		_add(acc, {ids[s]: r})


## Counts the cards each side draws (its deck shrinks), is given (it does not), burns, and its fatigue. It reads only
## the events, never the battle, so the battle and its listener do not keep each other alive.
func _on_event(ev: Dictionary, rec: Array, deck_n: Array, fatigued: Array, seen: Array) -> void:
	match ev.t:
		"draw":
			var s: int = ev.side
			seen[s][str(ev.id)] = true
			if int(ev.deck) < deck_n[s]:
				rec[s].drawn += 1
			elif str(ev.id) != BattleState.COIN:
				rec[s].made += 1
			deck_n[s] = int(ev.deck)
		"burn":
			rec[ev.side].burned += 1
			deck_n[ev.side] = int(ev.deck)
		"steal":
			if ev.get("zone", "") == "deck":
				deck_n[ev.from] = int(ev.deck)
		"fatigue":
			fatigued[ev.side] = true
			rec[ev.side].fatigue_dmg += int(ev.amount)


func _print_report(acc: Dictionary, only := PackedStringArray(), show_cards := false) -> void:
	var ids := []
	for d in CardDB.decks():
		if acc.has(d.id) and (only.is_empty() or d.id in only):
			ids.append(d.id)
	print("CARD FLOW (Hard vs Hard; own turns; hand = cards at the start of the turn, after the draw)")
	print("%-15s %5s %5s %6s %6s %5s %6s %5s %6s %5s %5s %5s %5s %5s" % ["deck", "games", "win%", "rounds",
		"low@", "low%", "late01", "mana", "float%", "pow%", "fatg%", "drawn", "made", "burn"])
	for id in ids:
		var a: Dictionary = acc[id]
		var n := maxf(1.0, a.games)
		print("%-15s %5d %5.1f %6.1f %6.1f %5.0f %5.0f%% %5.2f %5.0f%% %4.0f%% %4.0f%% %5.1f %5.1f %5.2f" % [id, a.games,
			100.0 * a.wins / n, a.turns / n / 2.0, float(a.low_turn) / maxf(1.0, a.low_games), 100.0 * a.low_games / n,
			100.0 * a.late_low / maxf(1.0, a.late_turns), float(a.unspent) / maxf(1.0, a.mana_turns),
			100.0 * a.floated / maxf(1.0, a.mana_turns), 100.0 * a.late_power / maxf(1.0, a.mana_turns),
			100.0 * a.fatigue_games / n, a.drawn / n, a.made / n, a.burned / n])
	print("  low@ = mean first turn starting with 0-1 cards (in the low% of games where it happens); late01 = turns")
	print("  from %d on starting with 0-1 cards; mana = unspent mana per turn from turn %d on; float%% = those turns" % [
		LATE_FROM, MANA_FROM])
	print("  ending with 2+ mana and a playable card in hand; pow% = hero power used on them; fatg% = games with fatigue")
	var head := "%-15s" % "hand by turn"
	for t in range(1, TURNS + 1):
		head += " %4d" % t
	print(head)
	for id in ids:
		var a: Dictionary = acc[id]
		var line := "%-15s" % id
		var line_end := "%-15s" % "  (end of turn)"
		for t in range(1, TURNS + 1):
			var k := maxf(1.0, a.hand_n[t])
			line += " %4.1f" % (a.hand[t] / k)
			line_end += " %4.1f" % (a.hand_end[t] / k)
		print(line)
		print(line_end)
	var reach := "%-15s" % "games reaching"
	print("share of games still running at the deck's turn N (first deck shown):")
	if not ids.is_empty():
		for t in range(1, TURNS + 1):
			reach += " %3.0f%%" % (100.0 * acc[ids[0]].hand_n[t] / maxf(1.0, acc[ids[0]].games))
		print(reach)
	if show_cards:
		for id in ids:
			var a: Dictionary = acc[id]
			print("cards of %s: in hand (games) / played %% of those / won %% when played / still in hand at the end %%" % id)
			var rows := []
			for c in a.cards:
				var v: Array = a.cards[c]
				rows.append([float(v[2]) / maxf(1.0, v[1]), c, v])
			rows.sort()
			for row in rows:
				var v: Array = row[2]
				print("  %-26s %5d %5.0f%% %5.1f%% %5.0f%%" % [row[1], v[0], 100.0 * v[1] / maxf(1.0, v[0]), 100.0 * row[0],
					100.0 * v[3] / maxf(1.0, v[0])])
	print("win rate by opponent class:")
	for id in ids:
		var a: Dictionary = acc[id]
		var line := "%-15s" % id
		for c in a.vs:
			line += "  %s %.1f%% (%d)" % [c, 100.0 * a.vs[c][0] / maxf(1.0, a.vs[c][1]), a.vs[c][1]]
		print(line)
