class_name Vfx
## Per-card spell and effect visuals, on top of the Fx primitives.
##
## Every card belongs to a school (fire, ice, venom, holy, soul ...): its colours, textures and sounds. Each card's
## profile (VfxData, data/vfx.json) also picks how its effect reaches a single target ("hit": orb, shard, beam,
## lash, seal ...) and how it covers the board ("mass": rain, gale, blizzard, quake ...). Each effect is staged the Hearthstone way: anticipation (a charge-up at the card), travel
## (a coloured missile with a trail), impact (flash, sparks, shake and, for heavy blows, a hit-stop) and aftermath
## (motes, smoke, frost).
##
## The battle view calls cast() when a spell is played, travel() for a targeted effect and mass() for a board-wide
## one. It calls heal(), armor(), buff() and hurt() for the results. Painted sprites from the image session
## (assets/vfx/vfx_*.png) are used when they exist; the Kenney particles stand in otherwise. Every function takes
## the battle view untyped (it has no class_name), for fx_layer, shake(), _speed() and friends.

# ================================================================ entry points

## Anticipation for a spell held up in front of the board: a rune opens under the card, motes are drawn into it
## and it glows; then it releases with the school's flash. Awaitable; the caller burns the card away after.
static func cast(view, c: Node2D, id: String, side: int = 0) -> void:
	var p := VfxData.profile(id)
	var s := VfxData.school(p)
	var k: float = view._speed()
	var fx: Node2D = view.fx_layer
	var pos := c.position
	Sfx.play(s.cast_sfx, -6.0, 0.9)
	Sfx.play("magic", -14.0, 0.8)
	if c.has_method("set_burn_colors"):
		c.set_burn_colors(s.color, s.hot) # the card burns away in its school's colours
	_rune(fx, pos + Vector2(0, 150), s, 420.0 + 160.0 * p.power, 0.9 / k)
	Fx.gather(fx, pos, s.hot, 230.0, 0.3 / k, 20 + int(p.power * 16))
	var glow := c.create_tween()
	glow.tween_property(c, "modulate", Color(1.35, 1.3, 1.2), 0.22 / k)
	glow.tween_property(c, "modulate", Color.WHITE, 0.25 / k)
	var trail := _motes(view, pos, s, 10, 90.0, 9.0, 0.6, 180.0, -80.0 if s.rise else 60.0)
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	trail.emission_rect_extents = Vector2(110, 150)
	await view._wait(0.3)
	# Release.
	_paint(fx, s.impact, pos, 380.0 + 120.0 * p.power, 0.6, _mid(s))
	FxLight.add(fx, pos, s, 520.0 + 200.0 * p.power, 1.3, 0.65 / k)
	Fx.flash(fx, "k_flare_01", pos, 420.0, 0.4, s.hot, 0.0)
	_motes(view, pos, s, 26 + int(p.power * 20), 320.0, 12.0, 0.9, 180.0, -60.0 if s.rise else 200.0)
	match p.cast:
		"coins":
			_coins(view, pos, 14)
		"pages":
			_pages(view, pos, s)
		"stars":
			_twinkle(view, pos, s, 230.0, 14)
		"mana":
			_mana_stream(view, pos, s, side)
	if p.big:
		view._screen_flash(s.color, 0.2)
		view.shake(6.0)
		Sfx.play("thunder", -14.0, 1.3)


## A targeted effect flying from `a` to `b`; awaitable, returns after the impact. kind: damage, buff, freeze,
## silence, destroy, bounce.
static func travel(view, a: Node2D, b: Node2D, id: String, kind: String) -> void:
	var p := VfxData.profile(id)
	var s := VfxData.school(p)
	var hit: String = p.hit
	if kind in ["buff"] and hit in VfxData.HARSH:
		hit = "wisp"
	elif kind == "destroy" and not VfxData.has_own(id, "hit"):
		hit = "smite"
	elif kind == "silence" and not VfxData.has_own(id, "hit"):
		hit = "seal"
	elif kind == "bounce" and not VfxData.has_own(id, "hit"):
		hit = "gust"
	Sfx.play("swish_long", -8.0, 0.8)
	await _hit(view, hit, a.position, b.position, s, p)
	if is_instance_valid(b):
		impact(view, b, s, kind, p)


## A board-wide effect. `follow` is true when the same card already swept the board this play (Medusa's Gaze
## damages, then freezes): the follow-up is a quick per-target touch instead of a second sweep.
static func mass(view, ev: Dictionary, follow: bool) -> void:
	var p := VfxData.profile(ev.id)
	var s := VfxData.school(p)
	var kind: String = ev.get("kind", "damage")
	var targets: Array[Node2D] = []
	for uid in ev.uids:
		var n = view.unit_views.get(uid)
		if n != null:
			targets.append(n)
	if targets.is_empty():
		return
	var origin: Node2D = _origin(view, ev)
	if follow:
		for i in targets.size():
			_after(view, 0.05 * i, Vfx._touch.bind(view, targets[i], s, kind, p))
		await view._wait(0.25 + 0.05 * targets.size())
		return
	var pattern: String = p.mass
	match pattern:
		"rain":
			await _rain(view, targets, s, kind, p)
		"nova":
			Fx.shockwave(view.fx_layer, origin.position, s.color, 1100.0, 0.6)
			_paint(view.fx_layer, s.impact, origin.position, 300.0, 0.5, s.hot)
			Sfx.play(s.cast_sfx, -6.0, 0.8)
			var last := 0.0
			for t in targets:
				var d: float = origin.position.distance_to(t.position) / 2400.0
				last = maxf(last, d)
				_after(view, d, Vfx.impact.bind(view, t, s, kind, p))
			await view._wait(last + 0.25)
		"gale", "wave":
			await _gale(view, targets, s, kind, p, origin)
		"blizzard":
			await _blizzard(view, targets, s, kind, p)
		"quake":
			await _quake(view, targets, s, kind, p)
		"radiance":
			view._screen_flash(s.hot, 0.35)
			await _each(view, targets, 0.08, "beam", s, kind, p)
		"seal", "spikes":
			await _each(view, targets, 0.07, pattern, s, kind, p)
		"claws":
			await _each(view, targets, 0.07, "claw", s, kind, p)
		"frost":
			await _frost(view, targets, s, kind, p)
		"wail":
			Sfx.play("wail", -8.0, 1.1)
			Fx.shockwave(view.fx_layer, origin.position, s.color, 900.0, 0.7)
			await _fan(view, origin.position, targets, "wisp", s, kind, p)
		"gaze":
			Sfx.play("wail", -10.0, 0.7)
			view._screen_flash(s.color, 0.45)
			Fx.shockwave(view.fx_layer, origin.position, s.color, 1200.0, 0.8)
			await _fan(view, origin.position, targets, "tether", s, kind, p)
		_:
			# Any single-target pattern, fired at every target at once.
			await _fan(view, origin.position, targets, pattern if pattern in VfxData.HITS else "orb", s, kind, p)


## Healing light in the healer's colours: a rune under the target and motes rising. Returns false for an unknown
## source, so the caller keeps its default look.
static func heal(view, v: Node2D, src: String) -> bool:
	if src == "":
		return false
	if src == "drain":
		# Life siphoned back to the hero: a red ribbon twisting up and blood-red motes drawn in.
		_rise(view, v.position + Vector2(0, 40), VfxData.SCHOOLS.blood, ["vfx_drain_siphon", "k_trace_03"], 240.0)
		Fx.gather(view.fx_layer, v.position, Color(1.0, 0.25, 0.2), 180.0, 0.3 / view._speed(), 18)
		return true
	var p := VfxData.profile(src)
	var s := VfxData.school(p)
	var fx: Node2D = view.fx_layer
	_rune(fx, v.position + Vector2(0, 60), s, 300.0, 0.9 / view._speed())
	var m := _motes(view, v.position + Vector2(0, 40), s, 22, 150.0, 18.0, 1.0, 50.0, -140.0, "k_star_06")
	m.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	m.emission_rect_extents = Vector2(70, 20)
	_paint(fx, ["vfx_heal_swirl"], v.position, 300.0, 0.8, Color.WHITE)
	FxLight.add(fx, v.position, s, 340.0, 0.8, 0.8, 0.15)
	if p.school == "holy":
		Fx.flash(fx, "holy_light", v.position, 300.0, 0.7, Color.WHITE, 0.2)
	else:
		Fx.flash(fx, "k_light_01", v.position, 280.0, 0.6, s.hot, 0.3)
	Fx.burst(fx, v.position, Color(0.4, 1.0, 0.4), 12, 140.0, 0.8, 18.0, -60.0, 180.0, "k_star_01")
	return true


static func armor(view, h: Node2D, src: String) -> bool:
	if src == "":
		return false
	var p := VfxData.profile(src)
	var s := VfxData.school(p)
	var fx: Node2D = view.fx_layer
	var at := h.position + Vector2(HeroView.W / 2, -60) if h is HeroView else h.position
	match p.school:
		"stone":
			Fx.smoke(fx, at, Color(0.35, 0.3, 0.25, 0.6), 200.0, 6)
			Fx._debris(fx, at + Vector2(0, 40), 60.0, 14)
			Sfx.play("rubble", -8.0)
		"holy", "soul", "word":
			_paint(fx, ["vfx_holy_shield", "ward_bubble"], h.position, 340.0, 0.7, s.hot)
		"gold":
			_coins(view, at, 10)
	Fx.flash(fx, "k_light_03", at, 220.0, 0.5, s.hot, 0.0)
	_motes(view, at, s, 18, 200.0, 10.0, 0.6, 180.0, 0.0)
	return true


static func buff(view, m: Node2D, src: String) -> bool:
	if src == "":
		return false
	var p := VfxData.profile(src)
	var s := VfxData.school(p)
	var fx: Node2D = view.fx_layer
	_rune(fx, m.position + Vector2(0, 70), s, 300.0, 0.9 / view._speed())
	Fx.flash(fx, "k_twirl_01", m.position, 300.0, 0.6, s.hot, 1.5)
	_paint(fx, s.impact, m.position, 240.0, 0.5, s.hot)
	var up := _motes(view, m.position + Vector2(0, 50), s, 26, 200.0, 14.0, 0.9, 40.0, -120.0)
	up.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	up.emission_rect_extents = Vector2(70, 20)
	_rise(view, m.position + Vector2(0, 30), s, ["vfx_buff_aura"], 260.0)
	if p.school == "holy":
		Fx.flash(fx, "holy_light", m.position, 320.0, 0.7, Color.WHITE, 0.3)
	return true


## A minion dying in its own school's way: the fire-born burn, ice shatters, souls rise, stone crumbles, venom
## melts... The dissolve's rim takes the school's colours; size grows with the minion's cost. The caller starts the
## dissolve (m.burn_away) after this.
static func death(view, m: Node2D, id: String) -> void:
	var p := VfxData.profile(id)
	var s := VfxData.school(p)
	var fx: Node2D = view.fx_layer
	var pos := m.position
	var big: float = 1.0 + 0.6 * p.power
	if m.has_method("set_burn_colors"):
		m.set_burn_colors(s.color, s.hot)
	var art: String = {"ice": "vfx_death_ice_shards", "stone": "vfx_death_stone", "venom": "vfx_death_venom",
		"fire": "vfx_death_ash", "pitch": "vfx_death_ash", "blood": "vfx_death_blood"}.get(p.school, "")
	if art != "" and UiSkin.has(art):
		_paint(fx, [art], pos, 300.0 * big, 0.8, Color.WHITE)
	elif p.school != "stone": # its painted impact is a glowing lava crack: a crumbling statue only raises dust
		_paint(fx, s.impact, pos, 260.0 * big, 0.6, _mid(s))
	match p.school:
		"fire", "pitch", "judgment":
			_paint(fx, ["vfx_fire_explosion", "fire_burst"] if p.big else ["fire_burst"], pos, 300.0 * big, 0.7,
				Color.WHITE)
			FxLight.add(fx, pos, s, 360.0 * big, 1.2, 0.9)
			Fx.burst(fx, pos, UI.EMBER, int(40 * big), 180.0, 1.4, 10.0, -140.0, 120.0)
			Fx.smoke(fx, pos, Color(0.2, 0.17, 0.15, 0.75) if p.school != "pitch" else Color(0.08, 0.06, 0.05, 0.85),
				220.0 * big)
		"ice":
			_sparks(view, pos, s, int(24 * big))
			var shards := _motes(view, pos, s, int(18 * big), 420.0, 26.0, 0.8, 180.0, 900.0,
				"vfx_ice_shard" if UiSkin.has("vfx_ice_shard") else "k_star_08")
			shards.angle_min = -180.0
			shards.angle_max = 180.0
			Sfx.play("glass", -6.0, 0.7)
			Sfx.play("ice", -8.0, 0.9)
		"soul", "shadow":
			_rise(view, pos, s, ["vfx_death_soul", "vfx_skull_wisp", "k_light_02"] if p.school == "soul"
				else ["vfx_death_shadow", "k_magic_05"], 220.0 * big)
			Fx.smoke(fx, pos, Color(s.color.r * 0.25, s.color.g * 0.25, s.color.b * 0.3, 0.7), 220.0 * big)
			_motes(view, pos, s, int(26 * big), 120.0, 14.0, 1.4, 60.0, -160.0)
			Sfx.play("wail" if p.school == "soul" else "sigh", -12.0, 1.2)
		"stone":
			Fx._debris(fx, pos + Vector2(0, 30), 70.0 * big, int(22 * big))
			Fx.dust(fx, pos + Vector2(0, 60), 180.0 * big, 30)
			Fx.smoke(fx, pos, Color(0.35, 0.3, 0.25, 0.6), 240.0 * big)
			Sfx.play("rubble", -6.0, 0.9)
		"gold":
			_coins(view, pos, int(14 * big))
		"venom", "water", "blood":
			_motes(view, pos, s, int(30 * big), 260.0, 16.0, 0.9, 120.0, 700.0)
			Sfx.play("splash", -8.0, 0.8)
		_:
			_motes(view, pos, s, int(30 * big), 220.0, 14.0, 1.1, 180.0, -100.0 if s.rise else 300.0)
			Fx.smoke(fx, pos, Color(s.color.r * 0.3, s.color.g * 0.3, s.color.b * 0.3, 0.6), 220.0 * big)
	if p.big:
		Fx.shockwave(fx, pos, s.color, 360.0 * big, 0.6)
		view.shake(6.0)


## A legendary's own entrance on top of the shared one (cut-in, golden circle): its signature sprite blooms
## behind it in its school's colours, with a shockwave, a screen tint and a school flourish.
static func legendary(view, m: Node2D, id: String) -> void:
	var p := VfxData.profile(id)
	var s := VfxData.school(p)
	var fx: Node2D = view.fx_layer
	var k: float = view._speed()
	var art: String = VfxData.LEGEND_ART.get(id, "")
	var sig := _sprite(fx, [art, "vfx_summon_pillar", s.impact[0]], m.position, 620.0, Color.WHITE, 3)
	if sig != null:
		var full := sig.scale
		sig.scale = full * 0.3
		sig.modulate.a = 0.0
		var t := sig.create_tween().set_parallel(true)
		t.tween_property(sig, "scale", full, 0.5 / k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(sig, "modulate:a", 1.0, 0.2 / k)
		t.tween_property(sig, "rotation", 0.25, 1.6 / k)
		t.tween_property(sig, "modulate:a", 0.0, 0.7 / k).set_delay(0.9 / k)
		t.chain().tween_callback(sig.queue_free)
	Fx.shockwave(fx, m.position, s.color, 700.0, 0.8)
	FxLight.add(fx, m.position, s, 640.0, 1.4, 1.2 / k, 0.2 / k)
	view._screen_flash(s.color, 0.3)
	_motes(view, m.position, s, 60, 520.0, 14.0, 1.3, 180.0, -120.0 if s.rise else 300.0)
	match p.school:
		"ice":
			_sparks(view, m.position, s, 30)
			Sfx.play("ice", -6.0, 0.7)
		"fire", "pitch":
			for i in 6:
				_after(view, 0.06 * i, Vfx._drop.bind(view, m.position + Vector2(randf_range(-260, 260),
					randf_range(-40, 60)), s, p, null, "damage"))
		"wind":
			Fx.flash(fx, "k_twirl_02", m.position, 520.0, 0.9, s.hot, 4.0)
			Sfx.play("gust", -4.0, 0.8)
		"holy", "word", "gold":
			_beam(view, m.position, s, 2.2)
		"stone", "blood":
			Fx.landing(view.bg_layer, m.position + Vector2(0, 40), s.color, 620.0, 1.0)
			view.shake(10.0)


## Keyword and trigger moments: a ward shattering, venom biting, a minion reborn, a turn effect waking, a card
## burned from a full hand.
static func keyword(view, n: Node2D, kind: String) -> void:
	if not is_instance_valid(n):
		return
	var fx: Node2D = view.fx_layer
	match kind:
		"ward":
			_paint(fx, ["vfx_ward_shatter"], n.position, 300.0, 0.5, Color.WHITE)
		"venom":
			_paint(fx, ["vfx_venom_fangs"], n.position, 220.0, 0.5, Color.WHITE)
		"rebirth":
			_rise(view, n.position + Vector2(0, 50), VfxData.SCHOOLS.holy, ["vfx_rebirth_flare", "k_flame_05"], 260.0)
			_motes(view, n.position + Vector2(0, 50), VfxData.SCHOOLS.holy, 30, 260.0, 12.0, 1.0, 50.0, -200.0)
			Sfx.play("magic", -8.0, 1.2)
		"trigger":
			_paint(fx, ["vfx_trigger_spark", "k_star_07"], n.position, 200.0, 0.4, UI.GOLD)
		"ruse":
			# A Ruse going off: a sharp golden glint, a spark of the two-horned flame and a few rising embers.
			_paint(fx, ["vfx_trigger_spark", "k_star_07"], n.position, 300.0, 0.5, UI.GOLD)
			Fx.flash(fx, "k_flare_01", n.position, 360.0, 0.35, Color(1.0, 0.85, 0.45), 0.0)
			Fx.flash(fx, "k_twirl_01", n.position, 280.0, 0.5, UI.GOLD, 2.0)
			_motes(view, n.position, VfxData.SCHOOLS.holy, 18, 220.0, 10.0, 0.7, 180.0, -120.0)
			Sfx.play("magic", -10.0, 1.35)
			Sfx.play("tick", -8.0, 1.2)
		"burn":
			_paint(fx, ["vfx_card_burn", "fire_burst"], n.position, 340.0, 0.7, Color.WHITE)


## A polymorph (Circe's swine): a swirl and a puff of smoke in the source card's colours, where the minion is
## swapped for its new form. `src` is the card that cast it; the caller shrinks the old view and pops the new one.
static func morph(view, pos: Vector2, src: String) -> void:
	var s := VfxData.school(VfxData.profile(src))
	var fx: Node2D = view.fx_layer
	Fx.flash(fx, "k_twirl_02", pos, 380.0, 0.6, s.hot, 5.0)
	Fx.flash(fx, "k_twirl_03", pos, 300.0, 0.5, _mid(s), -4.0)
	_paint(fx, ["smoke_puff", "k_smoke_05"], pos, 230.0, 0.55, _mid(s))
	Fx.smoke(fx, pos, Color(s.color.r * 0.35, s.color.g * 0.35, s.color.b * 0.35, 0.75), 240.0, 10)
	_motes(view, pos, s, 26, 260.0, 12.0, 0.8, 180.0, -80.0 if s.rise else 160.0)
	Sfx.play("magic", -8.0, 0.8)
	Sfx.play(s.cast_sfx, -12.0, 1.2)


## A card lifted from the enemy (a stolen or copied card): a wisp of shadow and a glint where it is taken.
static func pilfer(view, pos: Vector2) -> void:
	var s: Dictionary = VfxData.SCHOOLS.shadow
	var fx: Node2D = view.fx_layer
	Fx.flash(fx, "k_twirl_01", pos, 260.0, 0.45, _mid(s), 3.0)
	_paint(fx, ["vfx_shadow_burst", "k_magic_05"], pos, 220.0, 0.45, _mid(s))
	_motes(view, pos, s, 14, 160.0, 9.0, 0.6, 180.0, -60.0)
	Sfx.play("swish_long", -8.0, 1.1)


## A drawn card catching the light as it turns face up.
static func draw_glow(view, pos: Vector2) -> void:
	_paint(view.fx_layer, ["vfx_draw_glow"], pos, 340.0, 0.45, Color.WHITE)


## The losing hero bursting apart at the end of the match.
static func hero_death(view, h: Node2D) -> void:
	_paint(view.fx_layer, ["vfx_hero_death", "vfx_fire_explosion", "fire_burst"], h.position, 760.0, 1.2, Color.WHITE)


## The motes a minion's school throws while it drops onto the board (the landing itself keeps the rarity colour).
static func summon_tint(id: String) -> Color:
	return VfxData.school(VfxData.profile(id)).hot


## The attacker's colour on a melee hit (sparks and slash); an attack of 5+ hits harder.
static func strike(view, attacker: Node2D, target: Node2D, dir: Vector2, power: int) -> void:
	var id: String = attacker.card_id if attacker is MinionView else ""
	var s: Dictionary = VfxData.school(VfxData.profile(id)) if id != "" else VfxData.SCHOOLS.fire
	var fx: Node2D = view.fx_layer
	var k := clampf(0.8 + power * 0.08, 0.8, 1.6)
	_paint(fx, ["vfx_claw_rake", "claw_slash"], target.position, 260.0 * k, 0.35, Color.WHITE)
	Fx.slash(fx, target.position, dir, 320.0 * k, _mid(s))
	_sparks(view, target.position - dir * 40.0, s, int(18 * k))
	var p := Fx.burst(fx, (attacker.position + target.position) / 2, s.color, int(20 * k), 300.0, 0.4, 8.0, 200.0)
	p.color_ramp = _ramp(s)


## The school's casting circle lying flat on the table: its painted rune when there is one (untinted), else the
## Kenney circle in the school's colour.
static func _rune(fx: Node, pos: Vector2, s: Dictionary, size: float, duration: float) -> void:
	var art: String = VfxData.RUNE_ART.get(s.name, "")
	if art != "" and UiSkin.has(art):
		Fx.rune(fx, pos, Color(0.78, 0.78, 0.78), size, duration, art) # Fx.rune brightens by 1.3
	else:
		Fx.rune(fx, pos, s.color, size, duration, s.rune)


## A painted sprite lying flat on the table under a target (a fissure), fading out. Nothing when it is missing.
static func _flat(view, names: Array, pos: Vector2, size: float, duration: float) -> void:
	var n := _pick(names)
	if n == "":
		return
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(1.0, 0.45)
	holder.z_index = 3
	view.bg_layer.add_child(holder)
	var sp := _sprite(holder, [n], Vector2.ZERO, size, Color.WHITE, 0)
	var full := sp.scale
	sp.scale = full * 0.6
	var k: float = view._speed()
	var t := sp.create_tween().set_parallel(true)
	t.tween_property(sp, "scale", full, 0.15 / k).set_ease(Tween.EASE_OUT)
	t.tween_property(sp, "modulate:a", 0.0, duration * 0.5 / k).set_delay(duration * 0.5 / k)
	t.chain().tween_callback(holder.queue_free)


## A sprite floating up and fading (a soul leaving its body).
static func _rise(view, pos: Vector2, s: Dictionary, names: Array, size: float) -> void:
	var g := _sprite(view.fx_layer, names, pos, size, s.hot, 68)
	if g == null:
		return
	var k: float = view._speed()
	g.modulate.a = 0.0
	var t := g.create_tween().set_parallel(true)
	t.tween_property(g, "modulate:a", 0.9, 0.2 / k)
	t.tween_property(g, "position:y", pos.y - 220.0, 1.3 / k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(g, "scale", g.scale * 1.3, 1.3 / k)
	t.tween_property(g, "modulate:a", 0.0, 0.7 / k).set_delay(0.6 / k)
	t.chain().tween_callback(g.queue_free)


## Effect damage landing in the source's colours (frost, scorch, venom...) instead of the default blood splat.
static func hurt(view, v: Node2D, src: String, amount: int) -> bool:
	if src == "":
		return false
	var s := VfxData.school(VfxData.profile(src))
	var fx: Node2D = view.fx_layer
	_paint(fx, s.impact, v.position, 150.0 + amount * 22.0, 0.45, _mid(s))
	_motes(view, v.position, s, 8 + amount * 3, 260.0, 10.0, 0.6, 180.0, 300.0)
	return true


## The hit itself: flash, sparks, motes and shake scaled with the card's power, plus the kind's aftermath.
static func impact(view, target, s: Dictionary, kind: String, p: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	var fx: Node2D = view.fx_layer
	var pos: Vector2 = target.position
	var friendly := kind == "buff"
	Fx.flash(fx, "k_flare_01", pos, 320.0, 0.35, s.hot, 0.0)
	FxLight.add(fx, pos, s, 380.0 + 180.0 * p.power, 0.9 if friendly else 1.5, 0.5)
	_paint(fx, s.impact, pos, 200.0 + 100.0 * p.power, 0.45, _mid(s))
	_motes(view, pos, s, 20 + int(p.power * 20), 300.0, 11.0, 0.6, 180.0, -100.0 if s.rise else 260.0)
	Sfx.play(s.hit_sfx, -6.0, randf_range(0.9, 1.1))
	if not friendly:
		_sparks(view, pos, s, 14 + int(p.power * 12))
		view.shake(3.0 + 7.0 * p.power)
		if "home" in target:
			view._push(target, Vector2(0, -14.0 if target.position.y < view.V.y / 2 else 14.0))
	match kind:
		"freeze":
			_freeze(view, target)
		"silence":
			_seal_stamp(view, target, s, 0.6)
		"destroy":
			Fx.shockwave(fx, pos, s.color, 420.0, 0.5)
			Fx.smoke(fx, pos, Color(s.color.r * 0.3, s.color.g * 0.3, s.color.b * 0.3, 0.6), 220.0, 6)
			view.shake(12.0)
			view._hit_stop(0.08)
			Sfx.play("thunder", -10.0, 1.2)
		"bounce":
			Fx.flash(fx, "k_twirl_02", pos, 320.0, 0.5, s.hot, 3.0)
			Sfx.play("gust", -8.0)
	if p.big and not friendly and kind != "destroy":
		view._hit_stop(0.06)


# ================================================================ single-target patterns

static func _hit(view, hit: String, from: Vector2, to: Vector2, s: Dictionary, p: Dictionary) -> void:
	var k: float = view._speed()
	var dur := 0.38 / k
	match hit:
		"shard":
			await _missile(view, from, to, s, dur * 0.7, 0.08, 0.0, 120.0, true)
		"serpent":
			await _missile(view, from, to, s, dur * 1.15, 0.2, 55.0, 90.0, true)
		"wisp":
			await _missile(view, from, to, s, dur * 1.2, 0.5, 30.0, 150.0, false, 0.0)
		"gust":
			Sfx.play("gust", -8.0, 1.2)
			await _missile(view, from, to, s, dur * 0.8, 0.05, 0.0, 190.0, false, 9.0)
		"volley":
			for i in 3:
				var off := Vector2(randf_range(-30, 30), randf_range(-20, 20))
				if i < 2:
					_missile(view, from + off, to + off, s, dur * 0.55, 0.15, 0.0, 70.0, true, 0.0, ["vfx_flaming_arrow", "k_trace_05"])
					_after(view, 0.12 * (i + 1), func(): Sfx.play("swish", -10.0, 1.3))
					await view._wait(0.09)
				else:
					await _missile(view, from + off, to, s, dur * 0.55, 0.15, 0.0, 70.0, true, 0.0, ["vfx_flaming_arrow", "k_trace_05"])
		"fall":
			var top := to + Vector2(randf_range(-140, 140), -760)
			await _missile(view, top, to, s, dur * 0.9, 0.0, 0.0, 120.0, true)
		"beam":
			await _beam(view, to, s, 1.0)
		"bolt":
			await _bolt(view, from, to, s)
		"lash":
			await _line(view, from, to, s, "k_trace_03", 0.12, 0.15, 26.0)
			Fx.slash(view.fx_layer, to, (to - from).normalized(), 340.0, s.hot)
			Sfx.play("blade", -6.0, 1.2)
		"tether":
			Sfx.play("chain", -8.0)
			await _line(view, from, to, s, "k_trace_01", 0.2, 0.35, 34.0)
		"seal":
			await _seal_stamp(view, null, s, 1.0, to)
		"crack":
			await _crack(view, to, s, p)
		"spikes":
			await _spikes(view, to, s)
		"geyser":
			await _geyser(view, to, s)
		"smite":
			_rune(view.fx_layer, to + Vector2(0, 60), s, 420.0, 1.1 / k)
			await view._wait(0.15)
			await _beam(view, to, s, 2.0)
		"slash":
			await view._wait(0.05)
			var d := (to - from).normalized()
			Fx.slash(view.fx_layer, to, d, 420.0, s.hot)
			Fx.slash(view.fx_layer, to, d.rotated(1.3), 360.0, s.color)
			Sfx.play("blade", -4.0, 0.9)
		"claw":
			_paint(view.fx_layer, ["vfx_claw_rake", "claw_slash"], to, 300.0, 0.4, Color.WHITE)
			for i in 3:
				Fx.flash(view.fx_layer, "k_scratch_01", to + Vector2(-30 + 30 * i, 0), 230.0, 0.35, s.hot, 0.0)
			Sfx.play("growl", -10.0, 1.1)
			await view._wait(0.08)
		_:
			await _missile(view, from, to, s, dur, 0.35, 0.0, 120.0, false)


## A glowing head with a particle trail along an arc (`arc`: how high it bows, as a fraction of the distance),
## optionally weaving (`wobble` px) and stretched along its path. Awaitable; returns on arrival.
static func _missile(view, from: Vector2, to: Vector2, s: Dictionary, dur: float, arc: float, wobble: float,
		size: float, stretch: bool, spin: float = 1.5, core: Array = []) -> void:
	var fx: Node2D = view.fx_layer
	var orb := Node2D.new()
	orb.z_index = 70
	orb.position = from
	fx.add_child(orb)
	var picked := _pick(core if not core.is_empty() else s.core)
	var head := _sprite(orb, [picked], Vector2.ZERO, size, s.hot)
	if head != null and stretch:
		# Kenney blobs are squeezed into a streak; painted shards and arrows are already drawn along +x.
		var base := head.scale.x
		if picked.begins_with("k_trace"):
			head.rotation = PI / 2
			head.scale = Vector2(base * 0.9, base * 1.9)
		elif picked.begins_with("k_"):
			head.scale = Vector2(base * 1.7, base * 0.6)
		else:
			head.scale = Vector2(base * 1.5, base * 1.5)
	var glow := _sprite(orb, ["k_light_01"], Vector2.ZERO, size * 1.6, Color(s.color.r, s.color.g, s.color.b, 0.6))
	var lamp = FxLight.add(orb, Vector2.ZERO, s, 140.0 + size * 1.4, 0.9, 0.0, 0.1) # rides the missile
	var trail := CPUParticles2D.new()
	trail.texture = Fx._tex(s.trail)
	trail.amount = 50
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 50.0
	trail.spread = 180.0
	trail.gravity = Vector2(0, -40 if s.rise else 60)
	var dot := trail.texture == UI.dot_texture()
	trail.scale_amount_min = 0.25 if dot else 0.06 * size / 110.0
	trail.scale_amount_max = 0.6 if dot else 0.18 * size / 110.0
	trail.angle_min = -180.0
	trail.angle_max = 180.0
	trail.color_ramp = _ramp(s)
	trail.material = _add()
	orb.add_child(trail)
	var mid := (from + to) / 2 + Vector2(0, -minf(260.0, from.distance_to(to) * arc))
	var t := orb.create_tween()
	t.tween_method(Vfx._fly.bind(orb, from, mid, to, wobble, stretch), 0.0, 1.0, dur) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	if head != null and spin != 0.0 and not stretch:
		head.create_tween().tween_property(head, "rotation", TAU * spin, dur)
	await t.finished
	if head != null:
		head.visible = false
	if glow != null:
		glow.visible = false
	FxLight.release(lamp, 0.12)
	trail.emitting = false
	view.get_tree().create_timer(0.6).timeout.connect(orb.queue_free)


static func _fly(k: float, node: Node2D, a: Vector2, m: Vector2, b: Vector2, wobble: float, stretch: bool) -> void:
	var pos := a.lerp(m, k).lerp(m.lerp(b, k), k)
	var tangent := (2.0 * (1.0 - k) * (m - a) + 2.0 * k * (b - m)).normalized()
	if wobble != 0.0:
		pos += tangent.orthogonal() * sin(k * TAU * 2.0) * wobble * (1.0 - k)
	node.position = pos
	if stretch:
		node.rotation = tangent.angle()


## A column of light coming down onto `to` from above the screen. Awaitable (returns when it strikes).
static func _beam(view, to: Vector2, s: Dictionary, weight: float) -> void:
	var fx: Node2D = view.fx_layer
	var k: float = view._speed()
	var golden: bool = s.name in ["holy", "judgment", "gold"]
	var col := _sprite(fx, ["vfx_light_beam", "k_trace_06"] if golden else ["k_trace_06", "k_trace_07"],
		Vector2.ZERO, 64.0, s.hot, 68)
	if col == null:
		return
	var h := col.texture.get_size().y
	var height := to.y + 120.0
	col.position = Vector2(to.x, to.y - height / 2)
	var w := col.texture.get_size().x
	col.scale = Vector2(0.0, height / h * 1.1)
	var halo := _sprite(fx, ["k_light_01"], to, 260.0 * weight, s.color, 67)
	if halo != null:
		halo.modulate.a = 0.0
	FxLight.add(fx, to, s, 360.0 * weight + 120.0, 1.7, 0.6 / k, 0.14 / k)
	Sfx.play("magic", -8.0, 1.2)
	var t := col.create_tween()
	t.tween_property(col, "scale:x", 300.0 * weight / w, 0.14 / k).set_ease(Tween.EASE_OUT)
	if halo != null:
		t.parallel().tween_property(halo, "modulate:a", 0.9, 0.14 / k)
	await t.finished
	_motes(view, to + Vector2(0, -200), s, 14, 80.0, 10.0, 0.6, 30.0, 500.0)
	var out := col.create_tween().set_parallel(true)
	out.tween_property(col, "scale:x", 0.0, 0.35 / k).set_delay(0.08)
	out.tween_property(col, "modulate:a", 0.0, 0.35 / k).set_delay(0.08)
	if halo != null:
		out.tween_property(halo, "modulate:a", 0.0, 0.4 / k)
		out.chain().tween_callback(halo.queue_free)
	out.chain().tween_callback(col.queue_free)


## A forked lightning bolt flickering between two points.
static func _bolt(view, from: Vector2, to: Vector2, s: Dictionary) -> void:
	var fx: Node2D = view.fx_layer
	Sfx.play("thunder", -10.0, 1.5)
	FxLight.flicker(fx, from.lerp(to, 0.7), {"name": "holy", "color": s.color, "hot": Color(0.85, 0.9, 1.0)},
		from.distance_to(to) * 0.5 + 260.0, 1.8)
	for i in 3:
		var b := _sprite(fx, ["vfx_lightning", "k_spark_05", "k_spark_06"], (from + to) / 2, 64.0, s.hot, 69)
		if b == null:
			return
		var sz := b.texture.get_size()
		b.rotation = (to - from).angle() - PI / 2
		b.scale = Vector2(120.0 / sz.x * randf_range(0.8, 1.2), from.distance_to(to) / sz.y * 1.05)
		b.flip_h = randf() < 0.5
		view.get_tree().create_timer(0.06).timeout.connect(b.queue_free)
		await view._wait(0.05)
	view._screen_flash(s.hot, 0.15)


## A line drawn out from `from` to `to` (a whip, a rope, a gaze), held for `hold` seconds, then faded.
static func _line(view, from: Vector2, to: Vector2, s: Dictionary, tex: String, grow: float, hold: float,
		width: float) -> void:
	if not UiSkin.has(tex):
		return
	var k: float = view._speed()
	var holder := Node2D.new()
	holder.position = from
	holder.rotation = (to - from).angle() - PI / 2
	holder.z_index = 68
	view.fx_layer.add_child(holder)
	var l := Sprite2D.new()
	l.texture = UiSkin.tex(tex)
	l.material = _add()
	l.modulate = s.hot
	l.centered = false
	var sz := l.texture.get_size()
	l.offset = Vector2(-sz.x / 2, 0)
	l.scale = Vector2(width * 8.0 / sz.x, 0.0)
	holder.add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "scale:y", from.distance_to(to) / sz.y, grow / k).set_ease(Tween.EASE_OUT)
	await t.finished
	var out := l.create_tween()
	out.tween_property(l, "modulate", s.color, hold / k)
	out.tween_property(l, "modulate:a", 0.0, 0.2 / k)
	out.tween_callback(holder.queue_free)


## A glyph that appears large over the target, spins and stamps down onto it. With `at` and no target it only
## plays at that point. Awaitable.
static func _seal_stamp(view, target: Node2D, s: Dictionary, size: float, at: Vector2 = Vector2.ZERO) -> void:
	var pos := target.position if target != null else at
	var k: float = view._speed()
	var g := _sprite(view.fx_layer, ["vfx_glyph_ring", s.rune, "k_magic_01"], pos, 520.0 * size, s.hot, 72)
	if g == null:
		return
	var end := g.scale * 0.45
	g.modulate.a = 0.0
	var t := g.create_tween().set_parallel(true)
	t.tween_property(g, "modulate:a", 1.0, 0.1 / k)
	t.tween_property(g, "rotation", PI * 0.9, 0.3 / k)
	t.tween_property(g, "scale", end, 0.28 / k).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	await t.finished
	Sfx.play("lock", -6.0)
	Fx.flash(view.fx_layer, "k_flare_01", pos, 280.0 * size, 0.3, s.hot, 0.0)
	if UiSkin.has("vfx_silence_lock"):
		Fx.flash(view.fx_layer, "vfx_silence_lock", pos, 260.0 * size, 0.55, Color.WHITE, 0.3)
	var out := g.create_tween()
	out.tween_property(g, "modulate:a", 0.0, 0.3 / k)
	out.tween_callback(g.queue_free)


## The earth opening under the target: glowing cracks on the table, stone chips and dust.
static func _crack(view, to: Vector2, s: Dictionary, p: Dictionary) -> void:
	Sfx.play("quake_rumble", -8.0, 1.3, 0.0)
	Sfx.play("rubble", -6.0)
	Fx.landing(view.bg_layer, to + Vector2(0, 40), s.color, 420.0 + 120.0 * p.power, 0.6 + 0.4 * p.power)
	_flat(view, ["vfx_ground_fissure"], to + Vector2(0, 50), 380.0 + 100.0 * p.power, 1.1)
	Fx.dust(view.fx_layer, to + Vector2(0, 70), 200.0, 30)
	view.shake(8.0)
	await view._wait(0.12)


## Thorns (or blood-red spikes) shooting up under the target and pulling back.
static func _spikes(view, to: Vector2, s: Dictionary) -> void:
	var k: float = view._speed()
	Sfx.play("blade", -6.0, 0.8)
	for i in 5:
		var sp := _sprite(view.fx_layer, ["vfx_thorn_spike", "k_flame_06", "k_muzzle_05"], Vector2.ZERO, 120.0, s.color,
			66)
		if sp == null:
			break
		var x := -80.0 + 40.0 * i + randf_range(-10, 10)
		sp.rotation = x / 300.0 + randf_range(-0.15, 0.15)
		sp.centered = false
		var sz := sp.texture.get_size()
		sp.offset = Vector2(-sz.x / 2, -sz.y)
		sp.position = to + Vector2(x, 70)
		var full := sp.scale
		sp.scale = Vector2(full.x, 0.0)
		var t := sp.create_tween()
		t.tween_interval(0.03 * i / k)
		t.tween_property(sp, "scale", full * Vector2(1.0, randf_range(1.1, 1.6)), 0.08 / k).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.12 / k)
		t.tween_property(sp, "scale:y", 0.0, 0.2 / k).set_ease(Tween.EASE_IN)
		t.tween_callback(sp.queue_free)
	await view._wait(0.14)


## A column of liquid or fire bursting up from under the target.
static func _geyser(view, to: Vector2, s: Dictionary) -> void:
	var k: float = view._speed()
	Sfx.play(s.hit_sfx, -4.0, 0.8)
	var column: String = {"blood": "vfx_blood_column", "water": "vfx_water_column", "venom": "vfx_water_column"}.get(
		s.name, "")
	var g := _sprite(view.fx_layer, [column, "k_muzzle_01", "k_muzzle_03"], Vector2.ZERO, 260.0, s.hot, 66)
	if g != null:
		g.centered = false
		var sz := g.texture.get_size()
		g.offset = Vector2(-sz.x / 2, -sz.y)
		g.position = to + Vector2(0, 90)
		var full := g.scale
		g.scale = Vector2(full.x * 0.6, 0.0)
		var t := g.create_tween()
		t.tween_property(g, "scale", full * Vector2(1.0, 1.5), 0.12 / k).set_ease(Tween.EASE_OUT)
		t.tween_property(g, "modulate:a", 0.0, 0.35 / k)
		t.tween_callback(g.queue_free)
	var up := _motes(view, to + Vector2(0, 80), s, 30, 620.0, 14.0, 0.9, 25.0, 900.0)
	up.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	up.emission_rect_extents = Vector2(50, 10)
	await view._wait(0.12)


# ================================================================ board-wide patterns

## Fire, coins or pitch falling over the targets' row: a few strays miss, one drop lands on every target.
static func _rain(view, targets: Array[Node2D], s: Dictionary, kind: String, p: Dictionary) -> void:
	Sfx.play(s.cast_sfx, -6.0, 0.8)
	Sfx.play("swish_long", -10.0, 0.6)
	var row := 0.0
	for t in targets:
		row += t.position.y
	row /= targets.size()
	for i in 10:
		var x: float = view.V.x * randf_range(0.18, 0.82)
		var at := Vector2(x, row + randf_range(-40, 60))
		_after(view, randf_range(0.0, 0.35), Vfx._drop.bind(view, at, s, p, null, kind))
	var last := 0.0
	for i in targets.size():
		var d := 0.1 + 0.07 * i
		last = d
		_after(view, d, Vfx._drop.bind(view, targets[i].position, s, p, targets[i], kind))
	await view._wait(last + 0.45)


static func _drop(view, at: Vector2, s: Dictionary, p: Dictionary, target, kind: String) -> void:
	var top := at + Vector2(randf_range(-160, 60), -800)
	await _missile(view, top, at, s, 0.34 / view._speed(), 0.0, 0.0, 90.0, true)
	if target != null and is_instance_valid(target):
		impact(view, target, s, kind, p)
	else:
		_motes(view, at, s, 8, 200.0, 8.0, 0.5, 120.0, 400.0)
		Fx.flash(view.fx_layer, "k_flare_01", at, 160.0, 0.25, s.hot, 0.0)


## A gust (or wave) sweeping across the board from the caster's side, hitting each target as it passes.
static func _gale(view, targets: Array[Node2D], s: Dictionary, kind: String, p: Dictionary, origin: Node2D) -> void:
	var k: float = view._speed()
	var width: float = view.V.x
	var row := 0.0
	for t in targets:
		row += t.position.y
	row /= targets.size()
	var ltr := origin.position.x <= width / 2
	var x0 := -150.0 if ltr else width + 150.0
	var x1 := width + 150.0 if ltr else -150.0
	var sweep := 0.55 / k
	Sfx.play("gust", -4.0, 0.8)
	Sfx.play(s.cast_sfx, -8.0)
	for i in 9:
		var streak := _pick(["vfx_wind_ribbon", s.trail, "k_trace_02"] if s.name == "wind" else [s.trail, "k_trace_02"])
		var names: Array = s.core if i % 3 == 0 else [streak]
		var sp := _sprite(view.fx_layer, names, Vector2(x0, row + randf_range(-110, 110)),
			randf_range(140.0, 260.0), s.hot if i % 2 == 0 else s.color, 69)
		if sp == null:
			continue
		if i % 3 != 0 and streak.begins_with("k_"):
			sp.rotation = PI / 2
			sp.scale.y *= 2.5
		var t := sp.create_tween().set_parallel(true)
		t.tween_property(sp, "position:x", x1, sweep * randf_range(0.85, 1.1)).set_delay(randf_range(0.0, 0.1))
		if i % 3 == 0:
			t.tween_property(sp, "rotation", TAU * 3.0 * (1.0 if ltr else -1.0), sweep)
		t.tween_property(sp, "modulate:a", 0.0, 0.15).set_delay(sweep * 0.85)
		t.chain().tween_callback(sp.queue_free)
	var band := _motes(view, Vector2(x0, row), s, 40, 120.0, 12.0, 0.8, 60.0, 0.0)
	band.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	band.emission_rect_extents = Vector2(20, 120)
	band.create_tween().tween_property(band, "position:x", x1, sweep)
	var last := 0.0
	for t in targets:
		var d: float = absf(t.position.x - x0) / absf(x1 - x0) * 0.55
		last = maxf(last, d)
		_after(view, d, Vfx.impact.bind(view, t, s, kind, p))
	await view._wait(last + 0.2)


## Snow driven across the targets' half of the board, then frost on each target.
static func _blizzard(view, targets: Array[Node2D], s: Dictionary, kind: String, p: Dictionary) -> void:
	Sfx.play("gust", -4.0, 0.7)
	Sfx.play("ice", -6.0, 0.8)
	var row := 0.0
	for t in targets:
		row += t.position.y
	row /= targets.size()
	var w: float = view.V.x
	var snow := CPUParticles2D.new()
	snow.position = Vector2(w / 2, row - 320.0)
	snow.texture = Fx._tex("vfx_snowflake" if UiSkin.has("vfx_snowflake") else "k_star_06")
	snow.amount = 160
	snow.lifetime = 0.9
	snow.explosiveness = 0.4
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(w * 0.55, 40)
	snow.direction = Vector2(0.5, 1.0)
	snow.spread = 12.0
	snow.gravity = Vector2(0, 300)
	snow.initial_velocity_min = 500.0
	snow.initial_velocity_max = 800.0
	snow.scale_amount_min = 0.04
	snow.scale_amount_max = 0.14
	snow.angle_min = -180.0
	snow.angle_max = 180.0
	snow.color_ramp = _ramp(s)
	snow.material = _add()
	snow.z_index = 64
	view.fx_layer.add_child(snow)
	snow.emitting = true
	view._screen_flash(s.hot, 0.3)
	view.get_tree().create_timer(0.55 / view._speed()).timeout.connect(func(): snow.emitting = false)
	view.get_tree().create_timer(1.8).timeout.connect(snow.queue_free)
	for i in targets.size():
		_after(view, 0.3 + 0.05 * i, Vfx.impact.bind(view, targets[i], s, kind, p))
	await view._wait(0.45 + 0.05 * targets.size())


## The ground heaving: a heavy shake, glowing cracks under every target, dust rolling along the rows.
static func _quake(view, targets: Array[Node2D], s: Dictionary, kind: String, p: Dictionary) -> void:
	Sfx.play("quake_rumble", -2.0, 1.0, 0.0)
	Sfx.play("thunder", -6.0, 0.8)
	view._screen_flash(s.color, 0.5)
	view.shake(22.0 + 6.0 * p.power)
	for t in targets:
		Fx.landing(view.bg_layer, t.position + Vector2(0, 40), s.color, 460.0, 0.8)
		_flat(view, ["vfx_ground_fissure"], t.position + Vector2(0, 50), 420.0, 1.2)
		Fx.dust(view.fx_layer, t.position + Vector2(0, 70), 260.0, 30)
	await view._wait(0.35)
	view.shake(16.0)
	for i in targets.size():
		_after(view, 0.04 * i, Vfx.impact.bind(view, targets[i], s, kind, p))
	await view._wait(0.15 + 0.04 * targets.size())


## Ice spreading over the table under every target.
static func _frost(view, targets: Array[Node2D], s: Dictionary, kind: String, p: Dictionary) -> void:
	Sfx.play("ice", -4.0, 0.9)
	Sfx.play("glass", -8.0, 0.7)
	for i in targets.size():
		var t := targets[i]
		Fx.landing(view.bg_layer, t.position + Vector2(0, 40), s.color, 420.0, 0.5)
		_after(view, 0.06 * i + 0.1, Vfx.impact.bind(view, t, s, kind, p))
	await view._wait(0.3 + 0.06 * targets.size())


## One single-target pattern per target, started `gap` seconds apart. Awaits the last impact.
static func _each(view, targets: Array[Node2D], gap: float, hit: String, s: Dictionary, kind: String,
		p: Dictionary) -> void:
	for i in targets.size():
		var t := targets[i]
		_after(view, gap * i, Vfx._hit_then_impact.bind(view, hit, t.position, t, s, kind, p))
	await view._wait(gap * targets.size() + 0.35)


## The same pattern fired from one point at every target at once.
static func _fan(view, from: Vector2, targets: Array[Node2D], hit: String, s: Dictionary, kind: String,
		p: Dictionary) -> void:
	for i in targets.size():
		var t := targets[i]
		_after(view, 0.03 * i, Vfx._hit_then_impact.bind(view, hit, from, t, s, kind, p))
	await view._wait(0.03 * targets.size() + 0.5)


static func _hit_then_impact(view, hit: String, from: Vector2, t, s: Dictionary, kind: String,
		p: Dictionary) -> void:
	if not is_instance_valid(t):
		return
	await _hit(view, hit, from, t.position, s, p)
	impact(view, t, s, kind, p)


## The quick per-target follow-up of a second sweep (Medusa's freeze after her damage).
static func _touch(view, t, s: Dictionary, kind: String, p: Dictionary) -> void:
	if not is_instance_valid(t):
		return
	match kind:
		"freeze":
			_freeze(view, t)
		"silence":
			_seal_stamp(view, t, s, 0.6)
		_:
			impact(view, t, s, kind, p)


# ================================================================ aftermath and helpers

## Ice closing over a target: a frost star, glass shards and a cold blue flash.
static func _freeze(view, t: Node2D) -> void:
	var fx: Node2D = view.fx_layer
	var ice: Dictionary = VfxData.SCHOOLS.ice
	_paint(fx, ice.impact, t.position, 260.0, 0.6, _mid(ice))
	_paint(fx, ["vfx_ice_encase", "k_star_07"], t.position, 240.0, 0.8, Color(0.6, 0.85, 1.0))
	_sparks(view, t.position, ice, 10)
	Sfx.play("glass", -8.0, 0.8)
	Sfx.play("ice", -8.0)
	if t.has_method("flash"):
		t.flash(Color(0.55, 0.85, 1.0))


static func _coins(view, pos: Vector2, amount: int) -> void:
	var c := Fx.burst(view.fx_layer, pos, Color(1.0, 0.8, 0.3), amount, 380.0, 1.1, 22.0, 900.0, 60.0,
		"vfx_gold_coin" if UiSkin.has("vfx_gold_coin") else "k_star_07")
	c.color_ramp = _ramp(VfxData.SCHOOLS.gold)
	Sfx.play("coins", -8.0)


static func _pages(view, pos: Vector2, s: Dictionary) -> void:
	for i in 4:
		var pg := _sprite(view.fx_layer, ["vfx_page_glow", "k_window_03"], pos, 90.0, s.hot, 66)
		if pg == null:
			return
		var t := pg.create_tween().set_parallel(true)
		t.tween_property(pg, "position", pos + Vector2(randf_range(-200, 200), randf_range(-260, -120)), 0.9)
		t.tween_property(pg, "rotation", randf_range(-1.5, 1.5), 0.9)
		t.tween_property(pg, "modulate:a", 0.0, 0.5).set_delay(0.4)
		t.chain().tween_callback(pg.queue_free)
	Sfx.play("page", -6.0)


static func _twinkle(view, pos: Vector2, s: Dictionary, radius: float, amount: int) -> void:
	for i in amount:
		var at := pos + Vector2(randf_range(-radius, radius), randf_range(-radius, radius) * 0.8)
		_after(view, randf_range(0.0, 0.5), func(): Fx.flash(view.fx_layer, "k_star_06", at, randf_range(60, 120),
			0.5, s.hot, 0.6))


## Motes streaming from the card to its owner's mana tray (ramp spells).
static func _mana_stream(view, pos: Vector2, s: Dictionary, side: int) -> void:
	var tray = view.mana_views[side]
	var to: Vector2 = tray.position if tray != null else pos + Vector2(0, 300)
	_after(view, 0.4, func(): _paint(view.fx_layer, ["vfx_mana_burst"], to, 260.0, 0.6, Color.WHITE))
	for i in 3:
		_after(view, 0.08 * i, func(): _missile(view, pos, to, s, 0.4 / view._speed(), 0.3, 20.0, 60.0, false))


## The view's origin for a sweep: the source minion when it is still on the board, else its hero.
static func _origin(view, ev: Dictionary) -> Node2D:
	var side: int = ev.side
	if ev.id == "furies" and not view.board_views[side].is_empty():
		return view.board_views[side].back()
	return view.heroes[side]


static func _sparks(view, pos: Vector2, s: Dictionary, amount: int) -> void:
	var p := Fx.burst(view.fx_layer, pos, s.color, amount, 520.0, 0.45, 26.0, 700.0, 180.0, "k_spark_04")
	p.particle_flag_align_y = true
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.damping_min = 10.0
	p.damping_max = 40.0
	p.color_ramp = _ramp(s)


static func _motes(view, pos: Vector2, s: Dictionary, amount: int, speed: float, size: float, life: float = 0.8,
		spread: float = 180.0, gravity: float = 0.0, tex: String = "") -> CPUParticles2D:
	var p := Fx.burst(view.fx_layer, pos, s.color, amount, speed, life, size, gravity, spread,
		tex if tex != "" else s.mote)
	p.color_ramp = _ramp(s)
	return p


static func _ramp(s: Dictionary) -> Gradient:
	var g := Gradient.new()
	var hot: Color = s.hot
	var col: Color = s.color
	g.set_color(0, Color(hot.r * 1.2, hot.g * 1.2, hot.b * 1.2, 1.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.35, col)
	return g


## Between the colour and its white-hot core: tints big Kenney glows without washing them out to white.
static func _mid(s: Dictionary) -> Color:
	return (s.color as Color).lerp(s.hot, 0.35)


static func _add() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED # it is light itself: FxLight must not brighten it again
	return m


## The first texture of `names` that exists, or "".
static func _pick(names: Array) -> String:
	for n in names:
		if n != "" and UiSkin.has(n):
			return n
	return ""


## An additive sprite `size` px wide. Grey Kenney textures are tinted; painted ones keep their own colours.
static func _sprite(parent: Node, names: Array, pos: Vector2, size: float, tint: Color, z: int = 66) -> Sprite2D:
	var n := _pick(names)
	if n == "":
		return null
	var s := Sprite2D.new()
	s.texture = UiSkin.tex(n)
	s.material = Fx.live(n)
	s.modulate = Color(tint.r * 1.3, tint.g * 1.3, tint.b * 1.3, tint.a) if n.begins_with("k_") \
		else Color(1, 1, 1, tint.a)
	s.position = pos
	s.scale = Vector2.ONE * size / s.texture.get_size().x
	s.z_index = z
	parent.add_child(s)
	return s


## A popping flash of the first available texture (painted sprites untinted, Kenney ones tinted).
static func _paint(fx: Node, names: Array, pos: Vector2, size: float, duration: float, tint: Color) -> void:
	var n := _pick(names)
	if n != "":
		Fx.flash(fx, n, pos, size, duration, tint * 1.3 if n.begins_with("k_") else Color.WHITE, 0.4)


## Calls `f` after `delay` seconds of animation time.
static func _after(view, delay: float, f: Callable) -> void:
	if delay <= 0.0:
		f.call()
		return
	view.get_tree().create_timer(delay / view._speed()).timeout.connect(f)
