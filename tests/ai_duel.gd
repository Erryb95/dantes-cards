extends SceneTree
## AI strength check: one level against another with the starter decks. Every deal is played twice with the seats
## (and so the decks) swapped, so luck of the draw cancels out.
##   Godot --headless --path . -s res://tests/ai_duel.gd -- --games=200 [--levels=2,0] [--random] [--first=0]
## --levels=A,B: the levels that meet (0 Easy, 1 Medium, 2 Hard); the report is A's win rate. Default Hard vs Easy.
## --medium=R,N: overrides Medium's rollouts and noise (tuning). --first=N: start at deal N (split a run in shards).
## --matchup: both sides Hard; reports the starter decks against each other instead.

const RunTests := preload("res://tests/run_tests.gd")
const NAMES := ["easy", "medium", "hard"]


func _initialize() -> void:
	var games := 200
	var first := 0
	var random_decks := false
	var matchup := false
	var levels := [2, 0]
	var medium := []
	var pilgrim_wins := 0
	var plays := {} ## matchup: card id -> [games it was played in, games its side won]
	var power_uses := [0, 0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a.begins_with("--first="):
			first = int(a.substr(8))
		if a.begins_with("--levels="):
			levels = Array(a.substr(9).split(",")).map(func(x): return int(x))
		if a.begins_with("--medium="):
			medium = Array(a.substr(9).split(",")).map(func(x): return float(x))
		if a == "--random":
			random_decks = true
		if a == "--matchup":
			matchup = true
	if matchup:
		levels = [2, 2]
	var a_wins := 0
	var draws := 0
	var t0 := Time.get_ticks_msec()
	var decisions := 0
	var a_ms := 0
	for g in range(first * 2, (first * 2) + games):
		var deal := g / 2
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + deal
		var st := BattleState.new()
		var d0: Array[String] = RunTests.random_deck("pilgrim", rng) if random_decks else CardDB.deck_list("pilgrim")
		var d1: Array[String] = RunTests.random_deck("ferry", rng) if random_decks else CardDB.deck_list("ferry")
		st.start(d0, "dante", d1, "charon", 300 + deal, false, -1)
		# Level A plays side g % 2: each deal is played from both seats.
		var aside := g % 2
		var ais := []
		for s in 2:
			var ai := BattleAI.new(s, levels[0] if s == aside else levels[1])
			if not medium.is_empty() and ai.level == BattleAI.Level.MEDIUM:
				ai.rollouts = int(medium[0])
				ai.noise = medium[1]
			ais.append(ai)
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
			if st.current == aside:
				a_ms += Time.get_ticks_usec() - t
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
		if st.winner == aside:
			a_wins += 1
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
	print("AI DUEL: %s won %d of %d against %s (%.0f%%), draws %d, %.1f ms per %s decision, %.1f s total" % [
		NAMES[levels[0]], a_wins, games, NAMES[levels[1]], 100.0 * a_wins / games, draws,
		a_ms / 1000.0 / maxi(decisions, 1), NAMES[levels[0]], (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
