extends RefCounted
## Plays a lesson's battle scene the way a new player following Virgil would: each tap-to-continue line is tapped,
## each "do" step is done through the battle's own seams (the rules call plus the guide's _did, as the input code does),
## free play is left to the AI (the battle's autoplay). Used by menu_smoke (the flow) and screen_audit (the shots).
##   var r = await LessonDriver.run(tree, battle, on_step)
## `on_step(index, step)` is awaited on every new line Virgil shows, before it is answered (a screenshot hook).
## Returns {"won": bool, "over": whether the match ended, "steps": how many lines were shown, "refused": whether a
## wrong action was turned away}.


static func run(tree: SceneTree, battle: Node2D, on_step: Callable = Callable(), max_time: float = 300.0) -> Dictionary:
	var g: LessonGuide = battle.guide
	var t := 0.0
	var seen := -1
	var shown := 0
	var refused := false
	while not battle.over and t < max_time:
		await tree.process_frame
		t += tree.root.get_process_delta_time()
		if battle._mull_waiting:
			if g._shown and seen != g.index:
				seen = g.index
				shown += 1
				if on_step.is_valid():
					await on_step.call(g.index, g.current())
			battle._confirm_mulligan()
			continue
		if battle.autoplay or not battle._my_turn() or not g._shown or g._complete:
			continue
		var s: Dictionary = g.current()
		if seen != g.index:
			seen = g.index
			shown += 1
			if on_step.is_valid():
				await on_step.call(g.index, s)
			if not battle._my_turn():
				continue
		var st: BattleState = battle.st
		if str(s.get("wait", "")) == "tap":
			# A wrong move first, once: End Turn while Virgil is talking must not end the turn.
			if not refused:
				var turn := st.turn
				battle._end_turn()
				refused = st.turn == turn and st.current == 0
			battle._on_press(Vector2(-4000, -4000)) # a tap anywhere, through the battle's own input path
		elif s.has("do"):
			var want: Dictionary = s.do
			if str(want.act) == "inspect":
				battle._did({"act": "inspect", "card": str(want.card)})
				continue
			if str(want.act) == "end":
				battle._end_turn()
				continue
			var m := Lessons.resolve(want, st)
			if m.is_empty():
				push_error("lesson driver: step %d cannot be done: %s" % [g.index, want])
				return {"won": false, "steps": shown, "refused": refused}
			var action := {"act": str(want.act), "target": int(m.get("target", -1))}
			if m.do == "play":
				action.card = str(st.hand_card(0, m.uid).id)
			elif m.do == "attack":
				action.card = str(st.units[m.attacker].id)
			if not battle._allowed(action):
				push_error("lesson driver: the guide refused its own step %d: %s" % [g.index, action])
				return {"won": false, "steps": shown, "refused": refused}
			if m.do == "attack":
				# As a player does it: press the minion (it must take aim), then pick the target.
				var a = battle.unit_views.get(int(m.attacker))
				var tv = battle.unit_views.get(int(m.target))
				if a == null or tv == null:
					push_error("lesson driver: step %d has no view for its attacker or target" % g.index)
					return {"won": false, "steps": shown, "refused": refused}
				battle._on_press(a.global_position)
				if battle.mode != battle.Mode.AIM_ATTACK:
					push_error("lesson driver: pressing %s at step %d did not take aim" % [action.card, g.index])
					return {"won": false, "steps": shown, "refused": refused}
				battle._finish_aim(tv.global_position)
				continue
			var hit: bool = g.hits(action)
			if BattleAI.apply(st, 0, m):
				battle._did(action, hit)
		elif str(s.get("until", "")) == "end_turn":
			battle._end_turn()
		elif str(s.get("until", "")) == "act":
			g.on_press()
		elif str(s.get("until", "")) == "win":
			battle.autoplay = true # free play: the AI finishes the match for the player
	return {"won": battle.st.winner == 0, "over": battle.over, "steps": shown, "refused": refused}
