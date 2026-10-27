extends "res://tests/ui_smoke.gd"
## Screenshots of the Wrath class on the real board, to review its looks: Filippo's portrait and power, minions
## raging (the ember aura) next to calm ones, Wrath waking, a fight in the mud, a Frenzy, and the inspect tips of a
## raging minion.
##   Godot --path . res://tests/wrath_shots.tscn --resolution 1920x1080 -- --out=<dir>

var out := "user://wrath_shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Game.player_hero = "filippo"
	Game.player_cards = CardDB.deck_list("wrath")
	Game.enemy_hero = "charon"
	Game.enemy_cards = CardDB.deck_list("ferry")
	battle = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	_shoot()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _settle(extra: float = 0.3) -> void:
	var t := 0.0
	while (battle.playing or not battle.queue.is_empty()) and t < 20.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(extra).timeout


func _shoot() -> void:
	await _idle()
	var st: BattleState = battle.st
	var mine := ["uh_wrathful_shade", "wr_stygian_brute", "uh_filippo_argenti", "wr_mud_wrestler", "wr_red_towers"]
	var theirs := ["geryon", "she_wolf", "cerberus"]
	var u := {}
	for id in mine:
		u[id] = st._summon(0, id)
	for id in theirs:
		u[id] = st._summon(1, id)
	await _settle(0.6)
	await _snap("calm")
	# Wrath wakes on three of them at once.
	for id in ["uh_wrathful_shade", "wr_stygian_brute", "uh_filippo_argenti"]:
		st._damage(u[id], 1, null)
	st._cleanup()
	await get_tree().create_timer(0.35).timeout
	await _snap("wrath_wakes")
	await _settle(0.8)
	await _snap("raging")
	# A fight in the mud.
	st._fight(u["wr_stygian_brute"], u["geryon"], "wr_marsh_champion")
	st._cleanup()
	await get_tree().create_timer(0.3).timeout
	await _snap("fight")
	await _settle()
	# A Frenzy.
	st._damage(u["wr_mud_wrestler"], 1, null)
	st._cleanup()
	await get_tree().create_timer(0.45).timeout
	await _snap("frenzy")
	await _settle(0.6)
	# The inspect card of a raging minion, with its tips.
	var view = battle.unit_views.get(u["uh_wrathful_shade"].uid)
	battle._show_inspect(view)
	await get_tree().create_timer(0.4).timeout
	await _snap("inspect_raging")
	battle._hide_inspect()
	print("WRATH SHOTS: done")
	get_tree().quit()
