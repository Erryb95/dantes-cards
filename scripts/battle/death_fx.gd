class_name DeathFx
## Deaths in the killer's school. A minion (or a fallen hero) dies the way whatever struck the last blow kills:
## burnt by fire, shattered by ice, melted by venom, drawn up by souls and shadows, turned to crumbling stone, torn
## away by the wind, sunk by water, split open by a blade or claws, washed out by light, turned to falling coins.
## The victim's own school is only an accent: a thin line in the rim and a few of its motes (an ice giant killed by
## fire burns, with a little blue steam).
##
## The killer comes with the rules' "death" event (BattleState._kill_info: killer, how, by) and only picks the look.
## Each death is staged like the hits in Vfx: the killer's impact has just landed (the damage event), the piece
## takes the killer's colours in a pre phase (char, frost, tar, sickness, pallor, stone, gold, a white wash), then
## its dissolve (death_fx.gdshaderinc, through card_fx) runs in the killer's shape while the style's particles and
## sound play. About 0.9 s at normal speed; everything follows the battle view's _speed().
##
## Which style, the timing, the sounds, the quality level and the particle budget: DeathStyle. A board-wide clear
## shares one budget, and the quality level halves it on phones and at a 30 fps frame limit, as ArtLiving does.

# ================================================================ staging

## Stages one death on piece `m` (a MinionView, or a HeroView with `hero`). `victim_id`: the piece's card (a hero
## passes "power_<hero id>", its school). `ev`: the death event (killer, how, by); "from" (a Vector2 in the view)
## may say where the blow came from. `n` / `i`: the size of the batch of deaths played back to back and this one's
## place in it. Returns the seconds (real time, speed already applied) until the piece is gone; the caller frees it.
static func play(view, m: Node2D, victim_id: String, ev: Dictionary, n: int = 1, i: int = 0, hero: bool = false) -> float:
	var school := DeathStyle.school_for(ev, victim_id)
	var style := DeathStyle.style_for(school)
	var st: Dictionary = DeathStyle.STYLES[style]
	var s: Dictionary = VfxData.SCHOOLS[school]
	var vschool: String = VfxData.profile(victim_id).school
	var vs: Dictionary = VfxData.SCHOOLS[vschool]
	var k: float = view._speed()
	var total: float = DeathStyle.HERO_TIME if hero else DeathStyle.TIME
	var lead: float = DeathStyle.LEAD * (1.5 if hero else 1.0)
	var pre: float = total * float(st.pre)
	var dir := _blow_dir(view, m, ev)
	var lv := DeathStyle.level()
	var q := DeathStyle.budget(n)
	if hero:
		q = 0.0 if lv == DeathStyle.OFF else (0.8 if lv == DeathStyle.LITE else 1.5)
	var sz: float = 2.0 if hero else 1.0 + 0.5 * float(VfxData.profile(victim_id).power)
	var c := {"view": view, "fx": view.fx_layer, "s": s, "school": school, "pos": m.position, "dir": dir, "sz": sz,
		"q": q, "pre": pre, "total": total, "first": i == 0, "light": lv == DeathStyle.FULL and i < 2, "hero": hero,
		"half": _size(m) * 0.5}
	_shade(m, style, s, vs, school != vschool, dir, lead / k, pre / k, total / k)
	_move(m, style, dir, lead / k, pre / k, total / k)
	if q > 0.0:
		Vfx._after(view, lead * 0.5, func(): _hit(c, style))
		Vfx._after(view, lead + pre, func(): _break(c, style))
		Vfx._after(view, lead + total * 0.7, func(): _remains(c, style))
		if school != vschool:
			Vfx._after(view, lead + pre + total * 0.15, func(): _accent(c, vs))
	if i < 2:
		var pitch := 0.85 if hero else 1.0
		var loud := 4.0 if hero else 0.0
		for a in DeathStyle.SCHOOL_SFX.get(school, st.sfx):
			Vfx._after(view, lead * 0.5, func(): Sfx.play(a[0], a[1] + loud, a[2] * pitch))
		for a in st.late:
			Vfx._after(view, lead + pre, func(): Sfx.play(a[0], a[1] + loud, a[2] * pitch))
	return (lead + total) / k


## Where the blow came from, as a direction in the view (killer to victim): the striking unit for an attack or
## Venom, else the enemy hero (who cast it), else straight across the river.
static func _blow_dir(view, m: Node2D, ev: Dictionary) -> Vector2:
	var from = ev.get("from", null)
	var by := int(ev.get("by", -1))
	if from == null and by != -1:
		var u = view.unit_views.get(by)
		if u != null and is_instance_valid(u):
			from = u.position
		else:
			from = view.get("_dead_pos").get(by, null) if view.get("_dead_pos") != null else null
	if from == null and "side" in m and view.get("heroes") != null:
		var h = view.heroes[1 - int(m.side)]
		if h != null and is_instance_valid(h) and h != m:
			from = h.position
	if from is Vector2 and (m.position - from).length() > 4.0:
		return (m.position - from).normalized()
	return Vector2(0, -1) if m.position.y < view.V.y / 2 else Vector2(0, 1)


## The dissolve: the shader's death mode in the killer's colours, the victim's accent in the rim, the pre phase,
## then the cut. Times in real seconds.
static func _shade(m: Node2D, style: String, s: Dictionary, vs: Dictionary, accent: bool, dir: Vector2,
		lead: float, pre: float, total: float) -> void:
	var rim := _rim(style, s)
	if m.has_method("dying"):
		m.dying(minf(0.2, lead + pre))
	m.set_fx("burn_edge", rim[0])
	m.set_fx("burn_hot", rim[1])
	m.set_fx("death_mode", int(DeathStyle.STYLES[style].mode))
	m.set_fx("death_pre", 0.0)
	m.set_fx("burn", 0.0)
	m.set_fx("death_dir", dir)
	m.set_fx("death_hit", -dir * 0.55)
	m.set_fx("death_seed", randf() * 40.0)
	var a: Color = vs.hot
	m.set_fx("death_accent", Color(a.r, a.g, a.b, 0.7 if accent else 0.0))
	_place(m)
	# The killer's colours creep in under its impact (the lead), then the dissolve takes over.
	var t := m.create_tween()
	t.tween_method(func(v: float): _drive(m, "death_pre", v), 0.0, 1.0, maxf(lead + pre, 0.01))
	var start := lead + pre * 0.75
	var b := m.create_tween()
	b.tween_interval(maxf(start, 0.001))
	b.tween_method(func(v: float): _drive(m, "burn", v), 0.0, 1.0, maxf(lead + total - start, 0.05)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


static func _drive(m: Node2D, param: String, v: float) -> void:
	if is_instance_valid(m):
		m.set_fx(param, v)
		_place(m)


## The piece's centre and half size in canvas space (where card_fx measures `world`), kept up to date while it moves.
static func _place(m: Node2D) -> void:
	m.set_fx("death_center", m.global_position)
	m.set_fx("death_half", _size(m) * 0.5 * m.global_scale.abs())


static func _size(m: Node2D) -> Vector2:
	if m is HeroView:
		return Vector2(HeroView.W, HeroView.H)
	return Vector2(MinionView.W, MinionView.H)


## The rim colours: [outer, white-hot cut]. Mostly the school's own; tar, stone and blood get darker rims.
static func _rim(style: String, s: Dictionary) -> Array:
	match style:
		"tar":
			return [Color(0.55, 0.14, 0.02), Color(1.0, 0.55, 0.15)]
		"crumble":
			return [Color(0.42, 0.36, 0.3), Color(0.8, 0.72, 0.6)]
		"shatter":
			return [s.color, Color(0.92, 0.98, 1.0)]
		"rend":
			if s.name == "blood":
				return [Color(0.4, 0.01, 0.01), Color(1.0, 0.3, 0.18)]
	return [s.color, s.hot]


## Small moves that sell the style: a tremble before ice and stone give way, a drop as water takes it, a lift as a
## soul is drawn up, a slide down the wind. Times in real seconds.
static func _move(m: Node2D, style: String, dir: Vector2, lead: float, pre: float, total: float) -> void:
	var p0: Vector2 = m.home if "home" in m else m.position
	var t := m.create_tween()
	t.tween_interval(maxf(lead, 0.001))
	match style:
		"shatter", "crumble":
			for j in 4:
				t.tween_property(m, "position", p0 + Vector2(randf_range(-3, 3), randf_range(-2, 2)), pre / 5.0)
			t.tween_property(m, "position", p0 + (Vector2(0, 10) if style == "crumble" else Vector2.ZERO), pre / 5.0)
		"sink":
			t.tween_property(m, "position", p0 + Vector2(0, 26), total).set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN)
		"spirit":
			t.tween_property(m, "position", p0 + Vector2(0, -16), total).set_trans(Tween.TRANS_SINE)
			t.parallel().tween_property(m, "scale", m.scale * 1.04, total)
		"shred":
			t.tween_property(m, "position", p0 + dir * 30.0, total).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(m, "rotation", m.rotation + clampf(dir.x, -1.0, 1.0) * 0.12, total)
		"coins", "melt":
			t.tween_interval(pre)
			t.tween_property(m, "position", p0 + Vector2(0, 8), total - pre).set_ease(Tween.EASE_IN)
		"fade":
			t.tween_property(m, "scale", m.scale * 1.05, total).set_trans(Tween.TRANS_SINE)
		_:
			t.tween_interval(0.01)


# ================================================================ particles

static func _n(x: float, c: Dictionary) -> int:
	return maxi(1, int(round(x * float(c.q))))


## Normal blend (ash, tar, blood, grit darken the board; additive would make them vanish).
static func _matte(p: CPUParticles2D, col: Color) -> CPUParticles2D:
	p.material = null
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.7, Color(col.r, col.g, col.b, col.a * 0.85))
	p.color_ramp = g
	return p


## Spread a burst over the piece instead of one point, and let it stream (`stream` 0: all at once, 1: evenly).
static func _over(p: CPUParticles2D, c: Dictionary, k: float = 0.42, stream: float = 0.0) -> CPUParticles2D:
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = c.half * float(c.sz) * k
	p.explosiveness = 1.0 - stream * 0.8
	return p


## The opening beat, as the killer's impact fades: the first particles of the style, kept off the piece itself (the
## dissolve is what must read), and for a hero the shockwave.
static func _hit(c: Dictionary, style: String) -> void:
	var view = c.view
	var fx: Node2D = c.fx
	if not is_instance_valid(fx):
		return
	var s: Dictionary = c.s
	var pos: Vector2 = c.pos
	var sz: float = c.sz
	var dir: Vector2 = c.dir
	if c.light:
		FxLight.add(fx, pos, s, 300.0 * sz, 1.0, c.total)
	if c.hero:
		Fx.shockwave(fx, pos, s.color, 1400.0, 1.0)
		var b := Fx.burst(fx, pos, s.color, _n(80, c), 700.0, 1.6, 16.0, 200.0)
		b.color_ramp = Vfx._ramp(s)
	match style:
		"burn":
			# Embers lick up from the edges as they char.
			var e := _over(Vfx._motes(view, pos, s, _n(30, c), 170.0, 9.0 * sqrt(sz), 1.3, 60.0, -170.0, "k_flame_05"),
				c, 0.48, 0.8)
			e.direction = Vector2.UP
		"tar":
			var d := _over(Fx.burst(fx, pos, Color.BLACK, _n(14, c), 60.0, 1.0, 12.0 * sqrt(sz), 650.0, 15.0,
				"k_circle_05"), c, 0.42, 0.7)
			d.direction = Vector2.DOWN
			_matte(d, Color(0.04, 0.03, 0.025, 0.95))
		"shatter":
			# Frost crystals glint as the cold spreads.
			_over(Vfx._motes(view, pos, s, _n(12, c), 60.0, 9.0, 0.8, 180.0, 40.0, "k_star_06"), c, 0.5, 0.6)
		"melt":
			Fx.smoke(fx, pos + Vector2(0, -c.half.y * sz), Color(0.25, 0.55, 0.15, 0.4), 160.0 * sz, _n(5, c) + 1)
			_over(Vfx._motes(view, pos, s, _n(12, c), 70.0, 7.0, 1.0, 180.0, -90.0, "k_circle_05"), c, 0.45, 0.8)
		"spirit":
			var w := _over(Fx.burst(fx, pos, s.color, _n(18, c), 260.0, 1.0, 22.0 * sqrt(sz), -260.0, 14.0,
				"k_trace_02"), c, 0.42, 0.7)
			w.particle_flag_align_y = true
			w.angle_min = 0.0
			w.angle_max = 0.0
			w.color_ramp = Vfx._ramp(s)
		"crumble":
			_matte(_over(Fx.burst(fx, pos, Color.GRAY, _n(10, c), 120.0, 0.5, 5.0, 900.0, 60.0), c, 0.45),
				Color(0.55, 0.5, 0.42, 1.0))
		"shred":
			_streak(c, ["vfx_gust_streak", "vfx_wind_ribbon", "k_trace_02"], pos - dir * 90.0, 320.0 * sz, 0.45)
		"sink":
			Vfx._motes(view, pos + Vector2(0, c.half.y * sz), s, _n(22, c), 420.0, 9.0, 0.9, 50.0, 1100.0, "k_circle_05")
			Fx.shockwave(fx, pos + Vector2(0, c.half.y * 0.9 * sz), s.color, 150.0 * sz, 0.6)
		"rend":
			var thorn: bool = s.name == "thorn"
			var b := Fx.burst(fx, pos - dir * 30.0, Color.RED, _n(26, c), 560.0, 0.8, 9.0 * sqrt(sz), 1000.0, 35.0,
				"k_scratch_01" if thorn else "k_circle_05")
			b.direction = dir
			_matte(b, Color(0.3, 0.32, 0.12, 1.0) if thorn else Color(0.5, 0.02, 0.02, 1.0))
		"fade":
			Vfx._twinkle(view, pos, s, 60.0 * sz, _n(4, c))
		"coins":
			Vfx._twinkle(view, pos, s, 60.0 * sz, _n(4, c))


## The break: the piece gives way (the dissolve is under way) and the style's main particles fly out of it.
static func _break(c: Dictionary, style: String) -> void:
	var view = c.view
	var fx: Node2D = c.fx
	if not is_instance_valid(fx):
		return
	var s: Dictionary = c.s
	var pos: Vector2 = c.pos
	var sz: float = c.sz
	var dir: Vector2 = c.dir
	match style:
		"burn":
			var ash := _over(Fx.burst(fx, pos, Color.BLACK, _n(22, c), 110.0, 1.6, 7.0 * sqrt(sz), -50.0, 80.0,
				"k_dirt_02"), c, 0.45, 0.5)
			_matte(ash, Color(0.16, 0.14, 0.13, 0.9))
			Fx.smoke(fx, pos + Vector2(0, -c.half.y * 0.5 * sz), Color(0.18, 0.15, 0.13, 0.6), 220.0 * sz, _n(7, c) + 1)
			if s.name == "judgment":
				Vfx._sparks(view, pos, s, _n(14, c))
		"tar":
			Fx.smoke(fx, pos + Vector2(0, -c.half.y * 0.5 * sz), Color(0.05, 0.04, 0.035, 0.8), 240.0 * sz,
				_n(8, c) + 1)
			_over(Vfx._motes(view, pos, s, _n(18, c), 120.0, 8.0, 1.2, 90.0, -120.0, "k_scorch_01"), c, 0.45, 0.6)
		"shatter":
			var shards := Vfx._motes(view, pos, s, _n(22, c), 520.0, 26.0 * sqrt(sz), 0.85, 75.0, 1000.0,
				"vfx_ice_shard" if UiSkin.has("vfx_ice_shard") else "k_star_08")
			shards.direction = dir
			shards.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			shards.emission_sphere_radius = 40.0 * sz
			shards.angular_velocity_min = -400.0
			shards.angular_velocity_max = 400.0
			Vfx._sparks(view, pos, s, _n(16, c))
			_over(Vfx._motes(view, pos, s, _n(16, c), 90.0, 6.0, 1.3, 180.0, 120.0, "k_star_06"), c, 0.45, 0.4)
			if c.first:
				view.shake(4.0 * sz)
		"melt":
			var d := Vfx._motes(view, pos + Vector2(0, 0.6 * c.half.y * sz), s, _n(26, c), 90.0, 8.0, 0.9, 12.0,
				900.0, "k_circle_05")
			d.direction = Vector2.DOWN
			d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			d.emission_rect_extents = Vector2(c.half.x * 0.85 * sz, 8.0)
			d.explosiveness = 0.2
			Fx.smoke(fx, pos + Vector2(0, -c.half.y * 0.5 * sz), Color(0.2, 0.45, 0.12, 0.35), 200.0 * sz,
				_n(5, c) + 1)
		"spirit":
			Vfx._rise(view, pos + Vector2(0, -c.half.y * sz), s, ["vfx_death_soul", "k_light_02"] if s.name == "soul"
				else ["vfx_death_shadow", "k_smoke_04"], 200.0 * sz)
			Fx.smoke(fx, pos + Vector2(0, -c.half.y * 0.6 * sz), Color(s.color.r * 0.25, s.color.g * 0.25,
				s.color.b * 0.3, 0.6), 200.0 * sz, _n(6, c) + 1)
			_over(Vfx._motes(view, pos, s, _n(24, c), 120.0, 12.0, 1.4, 60.0, -180.0), c, 0.45, 0.6)
		"crumble":
			Fx._debris(fx, pos + Vector2(0, c.half.y * 0.5 * sz), 60.0 * sz, _n(20, c))
			var chunks := _over(Fx.burst(fx, pos, Color.GRAY, _n(14, c), 120.0, 0.9, 16.0 * sqrt(sz), 1300.0, 60.0,
				"k_dirt_03"), c, 0.42, 0.4)
			_matte(chunks, Color(0.5, 0.45, 0.38, 1.0))
			Fx.dust(fx, pos + Vector2(0, c.half.y * sz), 200.0 * sz, _n(30, c), Color(0.55, 0.5, 0.42, 0.55))
			if c.first:
				view.shake(5.0 * sz)
		"shred":
			# Strips of the card carried off down the wind, and the gust's own twirls with them.
			var strips := _over(Fx.burst(fx, pos, Color.WHITE, _n(26, c), 560.0, 0.9, 7.0, 60.0, 28.0), c, 0.42, 0.5)
			strips.texture = null
			strips.scale_amount_min = 4.0 * sz
			strips.scale_amount_max = 11.0 * sz
			strips.direction = dir
			strips.angular_velocity_min = -600.0
			strips.angular_velocity_max = 600.0
			_matte(strips, Color(0.6, 0.5, 0.42, 1.0).lerp(s.hot, 0.2))
			var tw := Vfx._motes(view, pos, s, _n(14, c), 420.0, 14.0, 0.8, 30.0, 0.0, "k_twirl_03")
			tw.direction = dir
			_streak(c, ["vfx_wind_ribbon", "vfx_gust_streak", "k_trace_02"], pos, 300.0 * sz, 0.5)
		"sink":
			_over(Vfx._motes(view, pos, s, _n(16, c), 60.0, 7.0, 1.2, 180.0, -160.0, "k_circle_05"), c, 0.42, 0.7)
		"rend":
			_over(Vfx._motes(view, pos, s, _n(14, c), 200.0, 10.0, 0.7, 180.0, 400.0), c, 0.35)
			var drops := Fx.burst(fx, pos, Color.RED, _n(12, c), 220.0, 0.9, 7.0 * sqrt(sz), 900.0, 50.0, "k_circle_05")
			_matte(drops, Color(0.42, 0.02, 0.02, 1.0) if s.name == "blood" else Color(0.3, 0.32, 0.12, 1.0))
		"fade":
			_over(Vfx._motes(view, pos, s, _n(40, c), 120.0, 10.0, 1.5, 180.0, -110.0, "k_star_06"), c, 0.45, 0.4)
			if s.name == "word" and float(c.q) >= 0.5:
				Vfx._pages(view, pos, s)
		"coins":
			var coins := _over(Fx.burst(fx, pos, Color(1.0, 0.8, 0.3), _n(18, c), 140.0, 1.0, 20.0 * sqrt(sz), 1300.0,
				70.0, "vfx_gold_coin" if UiSkin.has("vfx_gold_coin") else "k_star_07"), c, 0.42, 0.5)
			coins.color_ramp = Vfx._ramp(s)
			_over(Vfx._motes(view, pos, s, _n(20, c), 80.0, 6.0, 1.1, 180.0, 300.0, "k_star_07"), c, 0.42, 0.5)


## What is left where it was, once it is mostly gone: the style's painted remains (ash, shards, rubble, a pool of
## venom, blood, a last splash...), a soft glow for light and souls.
static func _remains(c: Dictionary, style: String) -> void:
	var fx: Node2D = c.fx
	if not is_instance_valid(fx):
		return
	var s: Dictionary = c.s
	var pos: Vector2 = c.pos
	var sz: float = c.sz * (1.4 if c.hero else 1.0)
	var art: Array = {
		"burn": ["vfx_death_ash"], "tar": ["vfx_pitch_splash", "k_scorch_03"], "shatter": ["vfx_death_ice_shards"],
		"melt": ["vfx_death_venom", "venom_drops"], "spirit": [], "crumble": ["vfx_death_stone"], "shred": [],
		"sink": ["vfx_water_splash"], "fade": ["k_light_02"], "coins": ["coin_glint"],
		"rend": ["vfx_thorn_vines", "k_scratch_01"] if s.name == "thorn" else ["vfx_death_blood", "blood_splat"],
	}.get(style, [])
	if not art.is_empty():
		var tint: Color = Vfx._mid(s) if (art[0] as String).begins_with("k_") else Color.WHITE
		Vfx._paint(fx, art, pos + (Vector2(0, c.half.y * 0.5 * sz) if style in ["melt", "sink"] else Vector2.ZERO),
			240.0 * sz, 0.7, tint)
	if style == "sink":
		Vfx._motes(c.view, pos + Vector2(0, c.half.y * 0.5 * sz), s, _n(14, c), 360.0, 8.0, 0.8, 40.0, 1100.0,
			"k_circle_05")
	if c.hero and style in ["burn", "tar"]:
		Vfx._paint(fx, ["vfx_hero_death", "vfx_fire_explosion"], pos, 700.0, 1.0, Color.WHITE)


## The victim's own school, small: a few of its motes (steam for ice and water).
static func _accent(c: Dictionary, vs: Dictionary) -> void:
	var fx: Node2D = c.fx
	var pos: Vector2 = c.pos
	if vs.name in ["ice", "water"]:
		Fx.smoke(fx, pos + Vector2(0, -10), Color(0.75, 0.88, 1.0, 0.35), 170.0 * float(c.sz), _n(4, c) + 1)
	_over(Vfx._motes(c.view, pos, vs, _n(8, c) + 1, 150.0, 9.0, 0.9, 180.0, -90.0 if vs.rise else 200.0), c, 0.35)


## A painted streak along the blow's direction (a gust), stretching and fading as it crosses the piece.
static func _streak(c: Dictionary, names: Array, at: Vector2, size: float, duration: float) -> void:
	var sp := Vfx._sprite(c.fx, names, at, size, c.s.hot, 66)
	if sp == null:
		return
	var dir: Vector2 = c.dir
	sp.rotation = dir.angle()
	var k: float = c.view._speed()
	var base := sp.scale
	sp.scale = base * Vector2(0.4, 0.8)
	var t := sp.create_tween().set_parallel(true)
	t.tween_property(sp, "position", at + dir * 160.0, duration / k).set_ease(Tween.EASE_OUT)
	t.tween_property(sp, "scale", base * Vector2(1.2, 1.0), duration / k)
	t.tween_property(sp, "modulate:a", 0.0, duration * 0.6 / k).set_delay(duration * 0.4 / k)
	t.chain().tween_callback(sp.queue_free)
