extends Node
## Visual check of the battle tooltips: the hero tip, a minion's inspect card with its keyword tips, and the coach
## bubble, saved as one screenshot.   Godot --path . res://tests/tip_preview.tscn -- --out=<file.png>

func _ready() -> void:
	var out := "user://tips.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var battle: Node = load(Game.BATTLE).instantiate()
	add_child(battle)
	while not battle._mull_waiting:
		await get_tree().process_frame
	battle._confirm_mulligan()
	await get_tree().create_timer(3.5).timeout
	battle._show_hero_tip(battle.heroes[1])
	var tips: Control = battle._tips
	var hero_tip := tips.get_child(0)
	tips.remove_child(hero_tip)
	var snap := {"uid": 9001, "id": "cd_capaneus", "side": 1, "is_hero": false, "attack": 4, "health": 5,
		"max_health": 5, "armor": 0, "keywords": ["guard"], "sleeping": false, "frozen": false, "silenced": false}
	var m := MinionView.new().setup(snap)
	battle.board_layer.add_child(m)
	m.home = Vector2(battle.V.x * 0.3, battle._board_y(1))
	m.position = m.home
	battle._show_inspect(m)
	var holder := Control.new()
	holder.position = Vector2(battle.V.x * 0.62, 120)
	battle.ui.add_child(holder)
	holder.add_child(hero_tip)
	battle._coach._show_text("Drag a card onto the board to play it. Minions can attack from your next turn.") \
		if battle._coach.has_method("_show_text") else null
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
