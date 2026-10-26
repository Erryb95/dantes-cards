extends Node
## Visual check of board VFX and auras: loads a battle, fires summoning circles, lights the hero auras and saves a
## screenshot.   Godot --path . res://tests/fx_preview.tscn -- --out=<file.png> [--at=<seconds after the effects>]

func _ready() -> void:
	var out := "user://fx.png"
	var at := 0.35
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--at="):
			at = float(a.substr(5))
	var battle: Node = load(Game.BATTLE).instantiate()
	add_child(battle)
	await get_tree().create_timer(4.0).timeout
	var v: Vector2 = battle.V
	# Minion landings: a cheap common, a mid rare, a big epic; then the legendary circle on the right.
	Fx.landing(battle.fx_layer, Vector2(v.x * 0.22, v.y * 0.62), UI.EMBER, 350.0, 0.0)
	Fx.landing(battle.fx_layer, Vector2(v.x * 0.42, v.y * 0.62), UI.RARITY.rare, 420.0, 0.5)
	Fx.landing(battle.fx_layer, Vector2(v.x * 0.62, v.y * 0.62), UI.RARITY.epic, 470.0, 1.0)
	Fx.summon(battle.fx_layer, Vector2(v.x * 0.84, v.y * 0.6), UI.GOLD, 680.0, 1.8, 1.0)
	battle.heroes[1].set_targeted(true)
	battle.heroes[0].power_ready = true
	battle.heroes[0]._refresh_power()
	battle._end_glow.set_on(true)
	battle.arrow.from = battle.heroes[0].position + Vector2(0, -60)
	battle.arrow.to = battle.heroes[1].position
	battle.arrow.valid = true
	battle.arrow.visible = true
	await get_tree().create_timer(at).timeout
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
