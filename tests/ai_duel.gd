extends SceneTree
## AI strength check: Normal against Easy with the starter decks, sides and decks swapped every game.
##   Godot --headless --path . -s res://tests/ai_duel.gd -- --games=200

const RunTests := preload("res://tests/run_tests.gd")


func _initialize() -> void:
	var games := 200
	var random_decks := false
	var matchup := false ## both sides Normal: reports the starter decks against each other instead
	var pilgrim_wins := 0
	var plays := {} ## matchup: card id -> [games it was played in, games its side won]
	var power_uses := [0, 0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a == "--random":
			random_decks = true
		if a == "--matchup":
			matchup = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var normal_wins := 0
	var draws := 0
	var t0 := Time.get_ticks_msec()
	var decisions := 0
	var normal_ms := 0
	for g in games:
		var st := BattleState.new()
		var a := CardDB.deck("pilgrim")
		var b := CardDB.deck("ferry")
		var d0: Array[String] = RunTests.random_deck("pilgrim", rng) if random_decks else CardDB.deck_list(a.id)
		var d1: Array[String] = RunTests.random_deck("ferry", rng) if random_decks else CardDB.deck_list(b.id)
		st.start(d0, "dante", d1, "charon", 300 + g, false, -1)
		# Normal plays side g % 2; over the run it gets both decks and both seats.
		var ns := g % 2
		var ais := [BattleAI.new(0, BattleAI.Level.NORMAL if ns == 0 or matchup else BattleAI.Level.EASY),
			BattleAI.new(1, BattleAI.Level.NORMAL if ns == 1 or matchup else BattleAI.Level.EASY)]
		var steps := 0
		var seen := [{}, {}]
		while st.winner == -1 and steps < 6000:
			steps += 1
			var t := Time.get_ticks_usec()
			var act: Dictionary = ais[st.current].next_action(st)
			if matchup and act.do == "play":
				for c in st.sides[st.current].hand:
					if c.uid == act.uid:
						seen[st.current][c.id] = true
			if matchup and act.do == "power":
				power_uses[st.current] += 1
			if st.current == ns:
				normal_ms += Time.get_ticks_usec() - t
				decisions += 1
			if act.do == "end" or not BattleAI.apply(st, st.current, act):
				st.end_turn()
		if st.winner == 0:
			pilgrim_wins += 1
		for side in 2:
			for id in seen[side]:
				var p: Array = plays.get(id, [0, 0])
				p[0] += 1
				p[1] += int(st.winner == side)
				plays[id] = p
		if st.winner == ns:
			normal_wins += 1
		elif st.winner == 2:
			draws += 1
	if matchup:
		print("MATCHUP: pilgrim %d / ferry %d of %d, hero power uses %d / %d" % [pilgrim_wins,
			games - pilgrim_wins - draws, games, power_uses[0], power_uses[1]])
		var rows := []
		for id in plays:
			rows.append([float(plays[id][1]) / plays[id][0], id, plays[id][0]])
		rows.sort()
		for r in rows:
			print("  %.2f  %-26s %4d" % [r[0], r[1], r[2]])
		quit()
		return
	print("AI DUEL: normal won %d of %d (%.0f%%), draws %d, %.1f ms per normal decision, %.1f s total" % [normal_wins,
		games, 100.0 * normal_wins / games, draws, normal_ms / 1000.0 / maxi(decisions, 1),
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit()
