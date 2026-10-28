extends Node
## Review of the deaths in the killer's school (scripts/battle/death_fx.gd): one kill per killer school on a staged
## board, played through the battle view's real event queue (projectile / attack, damage, death...), with a caption
## per segment; then an ice giant killed by fire, a trade, Venom, a Rebirth, a board-wide clear (full and lite) and
## a hero's defeat. Film it with the movie maker:
##   Godot --path . res://tests/death_preview.tscn --resolution 1280x720 --write-movie <file.avi> --fixed-fps 30
##   [-- --only=<segment index,...>] [--fast]

var battle: Node
var caption: Label
var _uid := 9600
var only: Array = []

## [caption, killer card, how the kill reaches the victim, victim card]. "spell": a projectile from the hero;
## "attack": the killer is a minion on your side and attacks; "destroy": a minion's destroy (Minos).
const KILLS := [
	["Fire burns from the edges", "cd_burning_sand", "spell", "pj_lost_shade"],
	["Pitch: black, sticky, smouldering", "mc_boiling_pitch", "spell", "lost_pilgrim"],
	["Judgment (Minos)", "minos", "destroy", "she_wolf"],
	["Ice freezes, then shatters", "ih_cocytus_winter", "spell", "phlegyas"],
	["Venom melts it down", "ih_serpents_kiss", "spell", "cerberus"],
	["Soul (Charon's power) draws it up", "power_charon", "spell", "paolo"],
	["Shadow pulls it into smoke", "wr_gate_slams_shut", "spell", "lost_pilgrim"],
	["Stone petrifies and crumbles", "mc_earth_swallows", "spell", "she_wolf"],
	["Wind tears it away", "uh_gale_of_the_lustful", "spell", "cerberus"],
	["Water sinks it", "oar_strike", "spell", "phlegyas"],
	["Blood splits it open", "cd_bleeding_branch", "spell", "pj_lost_shade"],
	["A plain blow (neutral attacker)", "she_wolf", "attack", "lost_pilgrim"],
	["Thorn rends it", "uh_thorn_jab", "spell", "paolo"],
	["Holy light washes it out", "pj_saint_lucy", "spell", "cerberus"],
	["The word unwrites it", "virgils_counsel", "spell", "she_wolf"],
	["Gold turns it to coins", "cd_usurers_purse", "spell", "lost_pilgrim"],
	["An ice giant killed by fire: it burns, with blue steam", "cd_burning_sand", "spell", "ih_ephialtes"],
]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.substr(7).split(",")).map(func(x): return int(x))
		elif a == "--fast":
			Settings.fast_animations = true
	battle = load(Game.BATTLE).instantiate()
	add_child(battle)
	while not battle._mull_waiting:
		await get_tree().process_frame
	battle._confirm_mulligan()
	battle.over = true # the opponent never moves: only the staged events play
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	caption = UI.label("", 34, "title", UI.GOLD, 5, Color.BLACK)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size = Vector2(battle.V.x, 60)
	caption.position = Vector2(0, battle.V.y * 0.44)
	layer.add_child(caption)
	await _drain()
	await _sec(2.5)
	var seg := 0
	for k in KILLS:
		if only.is_empty() or seg in only:
			await _kill(k[0], k[1], k[2], k[3])
		seg += 1
	if only.is_empty() or seg in only:
		await _trade()
	seg += 1
	if only.is_empty() or seg in only:
		await _venom()
	seg += 1
	if only.is_empty() or seg in only:
		await _rebirth()
	seg += 1
	if only.is_empty() or seg in only:
		await _mass("A board-wide clear: staggered, one shared budget", "cd_rain_of_fire", DeathStyle.FULL)
	seg += 1
	if only.is_empty() or seg in only:
		await _mass("The same clear at the phone (lite) level", "ih_cocytus_winter", DeathStyle.LITE)
	seg += 1
	if only.is_empty() or seg in only:
		await _hero_defeat()
	get_tree().quit()


func _sec(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Waits until the battle view has played everything queued.
func _drain() -> void:
	await get_tree().process_frame
	while not battle.queue.is_empty() or battle.playing:
		await get_tree().process_frame


func _say(text: String) -> void:
	caption.text = text
	caption.modulate.a = 0.0
	caption.create_tween().tween_property(caption, "modulate:a", 1.0, 0.2)


## A minion view on `side`, outside the rules (view only), laid out with the others.
func _stage(side: int, id: String) -> MinionView:
	var c := CardDB.card(id)
	_uid += 1
	var snap := {"uid": _uid, "id": id, "side": side, "is_hero": false, "attack": int(c.get("attack", 1)),
		"health": int(c.get("health", 1)), "max_health": int(c.get("health", 1)), "armor": 0,
		"keywords": c.get("keywords", []), "sleeping": false, "frozen": false, "silenced": false}
	var m := MinionView.new().setup(snap)
	battle.board_layer.add_child(m)
	battle.board_views[side].append(m)
	battle.unit_views[m.uid] = m
	battle._layout_board(side)
	m.position = m.home
	return m


func _push(evs: Array) -> void:
	for e in evs:
		battle.queue.append(e)
	await _drain()


func _hit(v: MinionView, src: String, source: int = -1) -> Dictionary:
	return {"t": "damage", "uid": v.uid, "amount": maxi(1, v.health), "hp": 0, "armor": 0, "source": source,
		"src": src}


func _kill(text: String, killer: String, how: String, victim: String) -> void:
	_say(text)
	var v := _stage(1, victim)
	await _sec(0.35)
	match how:
		"spell":
			await _push([{"t": "projectile", "from": battle.heroes[0].uid, "to": v.uid, "id": killer, "kind": "damage"},
				_hit(v, killer), {"t": "death", "uid": v.uid, "side": 1, "killer": killer, "how": "effect", "by": -1}])
		"destroy":
			var a := _stage(0, killer)
			await _sec(0.2)
			await _push([{"t": "projectile", "from": a.uid, "to": v.uid, "id": killer, "kind": "destroy"},
				{"t": "death", "uid": v.uid, "side": 1, "killer": killer, "how": "destroy", "by": -1}])
			await _sec(0.6)
			await _remove(a)
		"attack":
			var a := _stage(0, killer)
			await _sec(0.2)
			await _push([{"t": "attack", "attacker": a.uid, "target": v.uid}, _hit(v, "", a.uid),
				{"t": "death", "uid": v.uid, "side": 1, "killer": killer, "how": "attack", "by": a.uid}])
			await _sec(0.6)
			await _remove(a)
	await _sec(0.7)


## Takes a staged attacker off quietly (it did not die).
func _remove(m: MinionView) -> void:
	battle.board_views[m.side].erase(m)
	battle.unit_views.erase(m.uid)
	var t := m.create_tween()
	t.tween_property(m, "modulate:a", 0.0, 0.2)
	await t.finished
	m.queue_free()
	battle._layout_board(m.side)


## Both minions die to each other's school: a fire minion and an ice giant trade.
func _trade() -> void:
	_say("A trade: each dies in the other's school")
	var a := _stage(0, "farinata")
	var b := _stage(1, "ih_briareus")
	await _sec(0.4)
	await _push([{"t": "attack", "attacker": a.uid, "target": b.uid}, _hit(b, "", a.uid), _hit(a, "", b.uid),
		{"t": "death", "uid": a.uid, "side": 0, "killer": b.card_id, "how": "attack", "by": b.uid},
		{"t": "death", "uid": b.uid, "side": 1, "killer": a.card_id, "how": "attack", "by": a.uid}])
	await _sec(0.9)


func _venom() -> void:
	_say("Venom: whatever the attacker, it melts")
	var a := _stage(0, "harpy")
	var b := _stage(1, "cerberus")
	await _sec(0.4)
	await _push([{"t": "attack", "attacker": a.uid, "target": b.uid}, {"t": "damage", "uid": b.uid, "amount": 1,
		"hp": 4, "armor": 0, "source": a.uid, "src": ""}, {"t": "venom", "uid": b.uid, "source": a.uid},
		{"t": "death", "uid": b.uid, "side": 1, "killer": "harpy", "how": "venom", "by": a.uid}])
	await _sec(0.6)
	await _remove(a)
	await _sec(0.5)


## Rebirth: it dies (to fire), then comes back in the same slot.
func _rebirth() -> void:
	_say("Rebirth: the death plays out, then it rises")
	var v := _stage(1, "cd_nameless_bush")
	await _sec(0.4)
	_uid += 1
	var c := CardDB.card("cd_nameless_bush")
	var snap := {"uid": _uid, "id": "cd_nameless_bush", "side": 1, "is_hero": false, "attack": int(c.attack),
		"health": 1, "max_health": 1, "armor": 0, "keywords": [], "sleeping": true, "frozen": false, "silenced": false}
	await _push([{"t": "projectile", "from": battle.heroes[0].uid, "to": v.uid, "id": "cd_burning_sand",
		"kind": "damage"}, _hit(v, "cd_burning_sand"),
		{"t": "death", "uid": v.uid, "side": 1, "killer": "cd_burning_sand", "how": "effect", "by": -1},
		{"t": "summon", "side": 1, "unit": snap, "index": 0, "from_card": -1}, {"t": "rebirth", "uid": _uid}])
	await _sec(1.0)
	var back = battle.unit_views.get(_uid)
	if back is MinionView:
		await _remove(back)


## Six minions die to one board-wide spell, at the given quality level.
func _mass(text: String, spell: String, lv: int) -> void:
	_say(text)
	DeathStyle.forced = lv
	var ids := ["she_wolf", "ih_antaeus", "paolo", "lost_pilgrim", "cerberus", "phlegyas"]
	var vs: Array[MinionView] = []
	for id in ids:
		vs.append(_stage(1, id))
	await _sec(0.5)
	var evs: Array = [{"t": "aoe", "side": 0, "id": spell, "kind": "damage", "uids": vs.map(func(m): return m.uid)}]
	for m in vs:
		evs.append(_hit(m, spell))
	for m in vs:
		evs.append({"t": "death", "uid": m.uid, "side": 1, "killer": spell, "how": "effect", "by": -1})
	battle._last_aoe = ""
	await _push(evs)
	await _sec(1.1)
	DeathStyle.forced = -1


func _hero_defeat() -> void:
	_say("A hero falls: the killer's school, grander")
	var h: HeroView = battle.heroes[1]
	await _sec(0.3)
	await _push([{"t": "projectile", "from": battle.heroes[0].uid, "to": h.uid, "id": "ih_cocytus_winter",
		"kind": "damage"}, {"t": "damage", "uid": h.uid, "amount": h.health, "hp": 0, "armor": 0, "source": -1,
		"src": "ih_cocytus_winter"}])
	battle.queue.append({"t": "game_over", "winner": 0, "fallen": [{"uid": h.uid, "killer": "ih_cocytus_winter",
		"how": "effect", "by": -1}]})
	# The result screen follows the defeat: give it a moment on film.
	await _sec(3.2)
