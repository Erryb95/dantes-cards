extends SceneTree
## AI strength check: Normal against Easy with the starter decks, sides and decks swapped every game.
##   Godot --headless --path . -s res://tests/ai_duel.gd -- --games=200
## Deck balance (both sides Normal):
##   -- --matchup                 the two starter decks against each other, with per-card win rates
##   -- --decks=<a>,<b>           any two preconstructed decks (data/decks.json ids), with per-card win rates
##   -- --matrix                  every Pilgrim deck against every Ferryman deck (a table of the first deck's win rate)
## Deck games come in mirrored pairs: the same seed twice, with the decks in swapped seats.

const RunTests := preload("res://tests/run_tests.gd")


func _initialize() -> void:
	var games := 200
	var random_decks := false
	var matchup := false ## both sides Normal: reports the starter decks against each other instead
	var pair := []
	var matrix := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a == "--random":
			random_decks = true
		if a == "--matchup":
			pair = ["pilgrim", "ferry"]
		if a.begins_with("--decks="):
			pair = Array(a.substr(8).split(","))
		if a == "--matrix":
			matrix = true
	if matrix:
		_matrix(games)
		quit()
		return
	if pair.size() == 2:
		_report(pair[0], pair[1], _decks_duel(pair[0], pair[1], games))
		quit()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var normal_wins := 0
	var draws := 0
	var t0 := Time.get_ticks_msec()
	var decisions := 0
	var normal_ms := 0
	for g in games:
		var st := BattleState.new()
		var d0: Array[String] = RunTests.random_deck("pilgrim", rng) if random_decks else CardDB.deck_list("pilgrim")
		var d1: Array[String] = RunTests.random_deck("ferry", rng) if random_decks else CardDB.deck_list("ferry")
		st.start(d0, "dante", d1, "charon", 300 + g, false, -1)
		# Normal plays side g % 2; over the run it gets both decks and both seats.
		var ns := g % 2
		var ais := [BattleAI.new(0, BattleAI.Level.NORMAL if ns == 0 else BattleAI.Level.EASY),
			BattleAI.new(1, BattleAI.Level.NORMAL if ns == 1 else BattleAI.Level.EASY)]
		var steps := 0
		while st.winner == -1 and steps < 6000:
			steps += 1
			var t := Time.get_ticks_usec()
			var act: Dictionary = ais[st.current].next_action(st)
			if st.current == ns:
				normal_ms += Time.get_ticks_usec() - t
				decisions += 1
			if act.do == "end" or not BattleAI.apply(st, st.current, act):
				st.end_turn()
		if st.winner == ns:
			normal_wins += 1
		elif st.winner == 2:
			draws += 1
	print("AI DUEL: normal won %d of %d (%.0f%%), draws %d, %.1f ms per normal decision, %.1f s total" % [normal_wins,
		games, 100.0 * normal_wins / games, draws, normal_ms / 1000.0 / maxi(decisions, 1),
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## Plays `games` Normal-vs-Normal games between two preconstructed decks, in mirrored pairs (game 2k and 2k + 1
## share a seed and swap the seats). Returns {wins: [a, b], draws, plays: {card id: [games played, games won]},
## power: [a, b]}.
func _decks_duel(id_a: String, id_b: String, games: int) -> Dictionary:
	var da := CardDB.deck(id_a)
	var db := CardDB.deck(id_b)
	var out := {"wins": [0, 0], "draws": 0, "plays": {}, "power": [0, 0]}
	if da.is_empty() or db.is_empty():
		push_error("ai_duel: unknown deck %s or %s" % [id_a, id_b])
		return out
	for g in games:
		var swap := g % 2 == 1 # deck a sits in seat 1
		var decks := [da, db] if not swap else [db, da]
		var st := BattleState.new()
		st.start(CardDB.deck_list(decks[0].id), decks[0].hero, CardDB.deck_list(decks[1].id), decks[1].hero,
			300 + (g >> 1), false, -1)
		var ais := [BattleAI.new(0), BattleAI.new(1)]
		var seen := [{}, {}]
		var steps := 0
		while st.winner == -1 and steps < 6000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			var who := st.current if not swap else 1 - st.current # 0 = deck a
			if act.do == "play":
				for c in st.sides[st.current].hand:
					if c.uid == act.uid:
						seen[who][c.id] = true
			if act.do == "power":
				out.power[who] += 1
			if act.do == "end" or not BattleAI.apply(st, st.current, act):
				st.end_turn()
		var w := st.winner
		if w < 2 and swap:
			w = 1 - w
		if w < 2:
			out.wins[w] += 1
		else:
			out.draws += 1
		for side in 2:
			for id in seen[side]:
				var key := "%s:%s" % ["a" if side == 0 else "b", id]
				var p: Array = out.plays.get(key, [0, 0])
				p[0] += 1
				p[1] += int(w == side)
				out.plays[key] = p
	return out


func _report(id_a: String, id_b: String, r: Dictionary) -> void:
	var games: int = r.wins[0] + r.wins[1] + r.draws
	print("MATCHUP: %s %d / %s %d of %d (%.0f%%), draws %d, hero power uses %d / %d" % [id_a, r.wins[0], id_b,
		r.wins[1], games, 100.0 * r.wins[0] / maxi(games, 1), r.draws, r.power[0], r.power[1]])
	var rows := []
	for key in r.plays:
		rows.append([float(r.plays[key][1]) / r.plays[key][0], key, r.plays[key][0]])
	rows.sort()
	for row in rows:
		print("  %.2f  %-28s %4d" % [row[0], row[1], row[2]])


## Every Pilgrim deck against every Ferryman deck: the Pilgrim deck's win rate.
func _matrix(games: int) -> void:
	var ps := CardDB.class_decks("pilgrim")
	var fs := CardDB.class_decks("ferry")
	var head := "%-16s" % "pilgrim \\ ferry"
	for f in fs:
		head += " %14s" % f.id
	print(head)
	for p in ps:
		var line := "%-16s" % p.id
		for f in fs:
			var r := _decks_duel(p.id, f.id, games)
			line += " %13.0f%%" % (100.0 * r.wins[0] / maxi(games, 1))
		print(line)
