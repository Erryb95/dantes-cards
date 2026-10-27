extends SceneTree
## Balance report: random-deck AI games, win rate of the side that played each card.
##   Godot --headless --path . -s res://tests/card_stats.gd -- --games=1000 [--first=0] [--raw] [--class=<cls>]
## Every game deals its own decks, so a long run can be split in shards (--first=N starts at game N); --raw also
## prints one "RAW id played won" line per card for summing shards. Game g plays the class pair g % pairs (every
## pair of classes in turn, seats alternating); --class=<cls> keeps only the pairs with that class.

const RunTests := preload("res://tests/run_tests.gd")


func _initialize() -> void:
	var games := 1000
	var first := 0
	var raw := false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class="):
			only = a.substr(8)
		if a.begins_with("--games="):
			games = int(a.substr(8))
		if a.begins_with("--first="):
			first = int(a.substr(8))
		if a == "--raw":
			raw = true
	var rng := RandomNumberGenerator.new()
	var plays := {} ## id -> [games played in, games won]
	var decked := {} ## id -> [games in the deck, games won]
	var class_wins := {}
	var pairs := []
	var cls := CardDB.classes()
	for i in cls.size():
		class_wins[cls[i]] = 0
		for j in range(i + 1, cls.size()):
			if only == "" or only in [cls[i], cls[j]]:
				pairs.append([cls[i], cls[j]])
	for g in range(first, first + games):
		rng.seed = 4242 + g
		var pair: Array = pairs[g % pairs.size()]
		if (g / pairs.size()) % 2 == 1:
			pair = [pair[1], pair[0]]
		var st := BattleState.new()
		var decks := [RunTests.random_deck(pair[0], rng), RunTests.random_deck(pair[1], rng)]
		st.start(decks[0], CardDB.class_hero(pair[0]), decks[1], CardDB.class_hero(pair[1]), 9000 + g, false, -1)
		var ais := [BattleAI.new(0), BattleAI.new(1)]
		var seen := [{}, {}]
		var steps := 0
		while st.winner == -1 and steps < 6000:
			steps += 1
			var act: Dictionary = ais[st.current].next_action(st)
			if act.do == "play":
				for c in st.sides[st.current].hand:
					if c.uid == act.uid:
						seen[st.current][c.id] = true
			if act.do == "end" or not BattleAI.apply(st, st.current, act):
				st.end_turn()
		if g % 100 == 99:
			print("  ... %d games" % (g + 1))
		if st.winner < 2:
			class_wins[pair[st.winner]] += 1
		for side in 2:
			for id in seen[side]:
				var p: Array = plays.get(id, [0, 0])
				p[0] += 1
				p[1] += int(st.winner == side)
				plays[id] = p
			var counted := {}
			for id in decks[side]:
				if counted.has(id):
					continue
				counted[id] = true
				var d: Array = decked.get(id, [0, 0])
				d[0] += 1
				d[1] += int(st.winner == side)
				decked[id] = d
	if raw:
		for id in decked:
			var p: Array = plays.get(id, [0, 0])
			print("RAW %s %d %d %d %d" % [id, p[0], p[1], decked[id][0], decked[id][1]])
	var rows := []
	for id in plays:
		if plays[id][0] >= 25:
			rows.append([float(plays[id][1]) / plays[id][0], id, plays[id][0]])
	rows.sort()
	print("CLASS: " + " / ".join(class_wins.keys().map(func(k): return "%s %d" % [k, class_wins[k]])))
	print("WEAKEST:")
	for r in rows.slice(0, 15):
		print("  %.2f  %-28s %4d  %s" % [r[0], r[1], r[2], CardDB.card(r[1]).get("text", "")])
	print("STRONGEST:")
	for r in rows.slice(rows.size() - 15):
		print("  %.2f  %-28s %4d  %s" % [r[0], r[1], r[2], CardDB.card(r[1]).get("text", "")])
	quit()
