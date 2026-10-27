extends Node
## Films each card's effect (scripts/battle/vfx.gd) on a staged board: a few frames per card, saved as
## <out>/<card id>_<nn>.png at half size, for tools/vfx/contact_sheet.py to lay out side by side.
##   Godot --path . res://tests/vfx_preview.tscn -- --out=<dir> [--cards=id1,id2 | --spells] [--deaths] [--enemy]
## --deaths films the listed minions dying (and attacking) instead of their effects. Copy, steal and transform
## effects and Ruse flashes go through the battle view's own event handlers (steal, copy, draw, transform...);
## --enemy has the enemy cast them, so a card is copied or stolen from your hand and deck.

const FRAME_GAP := 0.08

var out := "user://vfx_preview"
var battle: Node
var foes: Array[Node2D] = []
var friend: Node2D
var deaths := false
var caster := 0
var _uid := 9500


func _ready() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cards="):
			ids = Array(a.substr(8).split(","))
		elif a == "--deaths":
			deaths = true
		elif a == "--enemy":
			caster = 1
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
		battle.board_views[side].append(m)
		if side == 1:
			foes.append(m)
		else:
			friend = m


func _film(id: String) -> void:
	var done := [false]
	_play(id, done)
	var n := 0
	var tail := 3
	while tail > 0 and n < 40:
		await get_tree().create_timer(FRAME_GAP).timeout
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png("%s/%s_%02d.png" % [out, id, n])
		n += 1
		if done[0]:
			tail -= 1
	await get_tree().create_timer(0.6).timeout


func _play(id: String, done: Array) -> void:
	if deaths:
		await _die(id)
		done[0] = true
		return
	var card := CardDB.card(id)
	var hero: Node2D = battle.heroes[0]
	var ruse: bool = card.get("effects", []).any(func(e): return e.get("ruse", false))
	if card.get("type") == "spell":
		var c := CardView.new().setup(id, -1, true)
		c.position = Vector2(battle.V.x / 2 - 380, battle.V.y * 0.47)
		c.scale = Vector2(0.85, 0.85)
		battle.hand_layer.add_child(c)
		if ruse:
			battle._show_ruse(c) # as the battle view shows a spell's Ruse: on the card while it is cast
		await Vfx.cast(battle, c, id, 0)
		c.burn_away(0.9)
	battle._last_aoe = ""
	var src: Node2D = hero if card.get("type") == "spell" else friend
	if ruse and card.get("type") == "minion":
		await battle._show_ruse(friend)
	for e in card.get("effects", []):
		var tt: String = e.get("target", "")
		match e.do:
			"copy":
				await _copy(id, e)
			"transform":
				var targets: Array[Node2D] = [foes[1]]
				if not tt.begins_with("choose_"):
					targets.assign(foes)
				for t in targets:
					if tt.begins_with("choose_"):
						await Vfx.travel(battle, src, t, id, "silence")
					await _transform(t, id, str(e.card))
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


## A copy / steal effect as the engine emits it (steal, copy, draw), played through the battle view.
func _copy(id: String, e: Dictionary) -> void:
	var victim := 1 - caster
	var from: String = e.get("from", "")
	var ids: Array[String] = []
	for i in int(e.get("count", 1)):
		var got := ""
		if from == "enemy_hand":
			if battle.hand_views[victim].is_empty():
				break
			var hc: CardView = battle.hand_views[victim][0 if victim == 1 else battle.hand_views[victim].size() - 1]
			got = hc.card_id
			if e.get("steal", false):
				await battle._present({"t": "steal", "side": caster, "from": victim, "uid": hc.uid, "id": got,
					"zone": "hand"})
		elif from == "enemy_deck":
			got = str(battle.st.sides[victim].deck[i])
			if e.get("steal", false):
				await battle._present({"t": "steal", "side": caster, "from": victim, "uid": -1, "id": got,
					"zone": "deck", "deck": battle.st.sides[victim].deck.size() - 1 - i})
		else:
			got = foes[1].card_id if caster == 0 else friend.card_id
		ids.append(got)
	# As the engine emits them: every steal first, then a copy + draw pair per card.
	for got in ids:
		_uid += 1
		await battle._present({"t": "copy", "side": caster, "id": got, "src": id, "from": from if from != "" else "board"})
		await battle._present({"t": "draw", "side": caster, "uid": _uid, "id": got,
			"deck": battle.st.sides[caster].deck.size()})


## A transform as the engine emits it: transform, death, then the new form's summon in the same slot.
func _transform(t: Node2D, id: String, into: String) -> void:
	var c := CardDB.card(into)
	var side: int = t.side
	var idx: int = battle.board_views[side].find(t)
	var k := foes.find(t) # before the old view is freed
	await battle._present({"t": "transform", "uid": t.uid, "side": side, "into": into, "src": id})
	await battle._present({"t": "death", "uid": t.uid, "side": side})
	_uid += 1
	var snap := {"uid": _uid, "id": into, "side": side, "is_hero": false, "attack": int(c.attack),
		"health": int(c.health), "max_health": int(c.health), "armor": 0, "keywords": [], "sleeping": true,
		"frozen": false, "silenced": false}
	await battle._present({"t": "summon", "side": side, "unit": snap, "index": idx, "from_card": -1})
	if k != -1:
		foes[k] = battle.unit_views[_uid]


## A fresh copy of minion `id` strikes an enemy, then dies in its school's way.
func _die(id: String) -> void:
	var c := CardDB.card(id)
	var snap := {"uid": 9100, "id": id, "side": 0, "is_hero": false, "attack": int(c.get("attack", 1)),
		"health": int(c.get("health", 1)), "max_health": int(c.get("health", 1)), "armor": 0, "keywords": [],
		"sleeping": false, "frozen": false, "silenced": false}
	var m := MinionView.new().setup(snap)
	battle.board_layer.add_child(m)
	m.home = friend.home + Vector2(MinionView.W + 60.0, 0)
	m.position = m.home
	await get_tree().create_timer(0.2).timeout
	Vfx.strike(battle, m, foes[2], (foes[2].position - m.position).normalized(), m.attack)
	await get_tree().create_timer(0.3).timeout
	Vfx.death(battle, m, id)
	await m.burn_away(0.85)
	m.queue_free()
