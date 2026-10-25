extends SceneTree
## Balance report: random-deck AI games, win rate of the side that played each card.
##   Godot --headless --path . -s res://tests/card_stats.gd -- --games=1000

const RunTests := preload("res://tests/run_tests.gd")


func _initialize() -> void:
	var games := 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.substr(8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var plays := {} ## id -> [games played in, games won]
	var class_wins := {"pilgrim": 0, "ferry": 0}
	for g in games:
		var st := BattleState.new()
		st.start(RunTests.random_deck("pilgrim", rng), "dante", RunTests.random_deck("ferry", rng), "charon", 9000 + g)
		var ais := [BattleAI.new(0), BattleAI.new(1)]
		var seen := [{}, {}]
		var steps := 0
		while st.winner == -1 and steps < 6000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			var done := false
			match act.do:
				"play":
					for c in st.sides[st.current].hand:
						if c.uid == act.uid:
							seen[st.current][c.id] = true
					done = st.play_card(st.current, act.uid, act.target, act.index)
				"attack":
					done = st.attack(st.current, act.attacker, act.target)
				"power":
					done = st.use_power(st.current, act.target)
			if not done:
				st.end_turn()
		if st.winner < 2:
			class_wins["pilgrim" if st.winner == 0 else "ferry"] += 1
		for side in 2:
			for id in seen[side]:
				var p: Array = plays.get(id, [0, 0])
				p[0] += 1
				p[1] += int(st.winner == side)
				plays[id] = p
	var rows := []
	for id in plays:
		if plays[id][0] >= 25:
			rows.append([float(plays[id][1]) / plays[id][0], id, plays[id][0]])
	rows.sort()
	print("CLASS: pilgrim %d / ferry %d" % [class_wins.pilgrim, class_wins.ferry])
	print("WEAKEST:")
	for r in rows.slice(0, 15):
		print("  %.2f  %-28s %4d  %s" % [r[0], r[1], r[2], CardDB.card(r[1]).get("text", "")])
	print("STRONGEST:")
	for r in rows.slice(rows.size() - 15):
		print("  %.2f  %-28s %4d  %s" % [r[0], r[1], r[2], CardDB.card(r[1]).get("text", "")])
	quit()
