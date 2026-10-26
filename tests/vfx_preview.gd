extends Node
## Films each card's effect (scripts/battle/vfx.gd) on a staged board: a few frames per card, saved as
## <out>/<card id>_<nn>.png at half size, for tools/vfx/contact_sheet.py to lay out side by side.
##   Godot --path . res://tests/vfx_preview.tscn -- --out=<dir> [--cards=id1,id2 | --spells]

const FRAME_GAP := 0.08

var out := "user://vfx_preview"
var battle: Node
var foes: Array[Node2D] = []
var friend: Node2D


func _ready() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cards="):
			ids = Array(a.substr(8).split(","))
		elif a == "--spells":
			for c in CardDB.all_cards():
				if c.type == "spell":
					ids.append(c.id)
	DirAccess.make_dir_recursive_absolute(out)
	battle = load(Game.BATTLE).instantiate()
	add_child(battle)
	while not battle._mull_waiting:
		await get_tree().process_frame
	battle._confirm_mulligan()
	await get_tree().create_timer(4.0).timeout
	_stage_board()
	await get_tree().create_timer(1.0).timeout
	for id in ids:
		await _film(id)
	get_tree().quit()


## Four enemy minions and one friend, outside the rules (view only).
func _stage_board() -> void:
	var pool: Array = CardDB.all_cards().filter(func(c): return c.type == "minion" and c.get("rarity") == "common")
	for i in 5:
		var c: Dictionary = pool[(i * 7) % pool.size()]
		var side := 1 if i < 4 else 0
		var snap := {"uid": 9001 + i, "id": c.id, "side": side, "is_hero": false, "attack": int(c.attack),
			"health": int(c.health), "max_health": int(c.health), "armor": 0, "keywords": [], "sleeping": false,
			"frozen": false, "silenced": false}
		var m := MinionView.new().setup(snap)
		battle.board_layer.add_child(m)
		var x: float = battle.V.x / 2 + ((i - 1.5) * (MinionView.W + 40.0) if side == 1 else 0.0)
		m.home = Vector2(x, battle._board_y(side))
		m.position = m.home
		battle.unit_views[m.uid] = m
		if side == 1:
			foes.append(m)
		else:
			friend = m


func _film(id: String) -> void:
	var done := [false]
	_play(id, done)
	var n := 0
	var tail := 3
	while tail > 0 and n < 24:
		await get_tree().create_timer(FRAME_GAP).timeout
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png("%s/%s_%02d.png" % [out, id, n])
		n += 1
		if done[0]:
			tail -= 1
	await get_tree().create_timer(0.6).timeout


func _play(id: String, done: Array) -> void:
	var card := CardDB.card(id)
	var hero: Node2D = battle.heroes[0]
	if card.get("type") == "spell":
		var c := CardView.new().setup(id, -1, true)
		c.position = Vector2(battle.V.x / 2 - 380, battle.V.y * 0.47)
		c.scale = Vector2(0.85, 0.85)
		battle.hand_layer.add_child(c)
		await Vfx.cast(battle, c, id, 0)
		c.burn_away(0.9)
	battle._last_aoe = ""
	var src: Node2D = hero if card.get("type") == "spell" else friend
	for e in card.get("effects", []):
		var tt: String = e.get("target", "")
		match e.do:
			"heal":
				Vfx.heal(battle, hero, id)
			"armor":
				Vfx.armor(battle, hero, id)
			"buff":
				await Vfx.travel(battle, src, friend, id, "buff")
				Vfx.buff(battle, friend, id)
			"damage", "freeze", "silence", "destroy", "bounce":
				if tt.begins_with("choose_") or tt.begins_with("random_") or tt == "enemy_hero":
					var to: Node2D = battle.heroes[1] if tt == "enemy_hero" else foes[1]
					await Vfx.travel(battle, src, to, id, e.do)
				else:
					var ev := {"side": 0, "id": id, "kind": e.do, "uids": foes.map(func(f): return f.uid)}
					await battle._on_aoe(ev)
	done[0] = true
