extends Node2D
## The battle screen: builds the arena, replays BattleState events as animations, and turns pointer / touch
## input into actions. The rules live in BattleState; this script never changes game values itself.
##
## Debug: `-- --autoplay` lets the AI play both sides, `-- --shots=<dir>` saves screenshots and quits.

const HAND_SCALE := 0.62
const ENEMY_HAND_SCALE := 0.42
const HOVER_SCALE := 1.12
const MINION_GAP := 40.0
const PLAY_LINE := 0.70 ## releasing a dragged card above this fraction of the screen height plays it

enum Mode { IDLE, DRAG_CARD, AIM_SPELL, AIM_BATTLECRY, AIM_ATTACK, AIM_POWER }

const DECK_SHEETS := 10
var _first_side := 0 ## who takes the first turn (coin flip)
var st: BattleState
var ai: BattleAI
var ai_self: BattleAI ## autoplay only
var autoplay := false
var shots_dir := ""
var _shot_i := 0
var _shot_t := 0.0
var _shot_every := 3.0
var _shots_after_over := 0

var queue: Array[Dictionary] = []
var playing := false
var over := false
var V := Vector2(1920, 1080)
var ky := 1.0

var hand_views: Array = [[], []]
var board_views: Array = [[], []]
var heroes: Array = [null, null]
var unit_views := {}
var _pending_card := {} ## hand uid -> CardView waiting for its summon

var cam: Camera2D
var bg_layer: Node2D
var board_layer: Node2D
var hand_layer: Node2D
var fx_layer: Node2D
var ui: CanvasLayer
var arrow: TargetArrow
var river: ColorRect
var _river_mat: ShaderMaterial
var _ripple_i := 0
var _ripples: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _wisps: Array[Sprite2D] = []
var props: ArenaAcheron
var arena_scene: ArenaScene ## editor-placed sockets (scenes/arenas/*.tscn)
var mana_views: Array = [null, null]
var deck_views: Array = [null, null]
var end_btn: Node2D
var _end_seal: Sprite2D
var _painted_board := false
var _parallax := Vector2.ZERO ## the table (board, units, fx) drifts against the pointer; the hand stays put
var _parallax_t := 0.0
var _end_label: Label
var _end_glow: Aura
var _end_disc: Shapes
var banner: Label
var inspect: CardView
var _tips: VBoxContainer
var _flash_rect: ColorRect

var mode := Mode.IDLE
var drag_card: CardView
var aim_source := Vector2.ZERO
var aim_index := -1
var aim_card_uid := -1
var aim_attacker := -1
var hover_card: CardView
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _pressed := false
var _sticky := false
var _gap_index := -1
var _shake := 0.0
var _ai_delay := 0.0
var _highlight_dirty := true
var _hover_unit_t := 0.0
var _hover_unit: Node2D
var _in_mulligan := false
var _mull_waiting := false
var _mull_marks := {} ## card uid -> "replace" label
var _mull_ui: Control
signal mulligan_confirmed


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
			autoplay = true
		elif a == "--fast":
			Settings.fast_animations = true
		elif a.begins_with("--shot-every="):
			_shot_every = float(a.substr(13))
	V = get_viewport_rect().size
	ky = minf(V.y / 1080.0, V.x / 1920.0) # the 16:9 layout fits inside any screen (letterboxed on 16:10)
	_build_scene()
	get_viewport().size_changed.connect(_on_resize)
	var arena := CardDB.arena(Game.arena_id)
	Sfx.play_music(arena.get("music", "music_combat"))
	Sfx.play_ambience(arena.get("ambience", ""), -16.0)
	st = BattleState.new()
	st.event.connect(func(ev): queue.append(ev))
	ai = BattleAI.new(1)
	ai_self = BattleAI.new(0)
	_intro(arena)
	st.start(Game.player_cards, Game.player_hero, Game.enemy_cards, Game.enemy_hero, 0, true, -1)


func _on_resize() -> void:
	V = get_viewport_rect().size
	ky = minf(V.y / 1080.0, V.x / 1920.0) # the 16:9 layout fits inside any screen (letterboxed on 16:10)
	cam.position = V / 2
	_layout_static()
	_layout_hand(0)
	_layout_hand(1)
	_layout_board(0)
	_layout_board(1)


# ================================================================ scene

func _build_scene() -> void:
	cam = Camera2D.new()
	cam.position = V / 2
	add_child(cam)
	bg_layer = Node2D.new()
	add_child(bg_layer)
	board_layer = Node2D.new()
	add_child(board_layer)
	hand_layer = Node2D.new()
	hand_layer.z_index = 20
	add_child(hand_layer)
	fx_layer = Node2D.new()
	fx_layer.z_index = 40
	add_child(fx_layer)
	arrow = TargetArrow.new()
	arrow.z_index = 90
	arrow.visible = false
	add_child(arrow)
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var arena := CardDB.arena(Game.arena_id)
	var back := Sprite2D.new()
	back.name = "Backdrop"
	var path := "res://assets/arenas/" + str(arena.get("backdrop", ""))
	if ResourceLoader.exists(path):
		back.texture = load(path)
	else:
		var g := GradientTexture2D.new()
		g.width = 256
		g.height = 144
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.45)
		g.fill_to = Vector2(1.2, 1.2)
		var gr := Gradient.new()
		gr.set_color(0, Color(0.22, 0.09, 0.05))
		gr.set_color(1, Color(0.02, 0.01, 0.01))
		g.gradient = gr
		back.texture = g
	back.modulate = Color(0.78, 0.74, 0.72)
	back.light_mask = ArenaAcheron.LIGHT_MASK
	# A painted board (ARENA_BRIEF.md) replaces the landscape: same coordinates as the layout, 2560x1440.
	var board_path := "res://assets/arenas/" + str(arena.get("board", ""))
	_painted_board = arena.has("board") and ResourceLoader.exists(board_path)
	bg_layer.add_child(back)
	if _painted_board:
		# The landscape stays underneath, darkened, for the side bands of screens wider than the board.
		back.modulate = Color(0.35, 0.32, 0.3)
		var board := Sprite2D.new()
		board.name = "Board"
		board.texture = load(board_path)
		var normal_path := "res://assets/arenas/" + str(arena.get("normal", ""))
		if arena.has("normal") and ResourceLoader.exists(normal_path):
			# The blockout's normals let the lantern and brazier light the painted rocks and water.
			var ct := CanvasTexture.new()
			ct.diffuse_texture = board.texture
			ct.normal_texture = load(normal_path)
			board.texture = ct
		board.light_mask = ArenaAcheron.LIGHT_MASK
		bg_layer.add_child(board)

	# Two shore beds where the minions stand, the river between them.
	for i in 2:
		var bed := Panel.new()
		bed.name = "Bed%d" % i
		bed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bed.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.02, 0.015, 0.42), Color(0.9, 0.7, 0.4, 0.16), 2, 90,
			Color(0, 0, 0, 0.25), 30))
		bg_layer.add_child(bed)
	river = ColorRect.new()
	river.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_river_mat = ShaderMaterial.new()
	_river_mat.shader = preload("res://assets/shaders/river.gdshader")
	river.material = _river_mat
	river.light_mask = ArenaAcheron.LIGHT_MASK
	bg_layer.add_child(river)

	if _painted_board:
		river.modulate.a = 0.45
		for i in 2:
			bg_layer.get_node("Bed%d" % i).visible = false
		for layer in ["mist", "frame"]:
			var lp := "res://assets/arenas/" + str(arena.get(layer, ""))
			if arena.has(layer) and ResourceLoader.exists(lp):
				var s := Sprite2D.new()
				s.name = "Board_" + layer
				s.texture = load(lp)
				if layer == "mist":
					s.material = CanvasItemMaterial.new()
					(s.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
					s.modulate = Color(1, 1, 1, 0.35)
				bg_layer.add_child(s)

	var scene_path := str(arena.get("scene", ""))
	if scene_path != "" and ResourceLoader.exists(scene_path):
		arena_scene = load(scene_path).instantiate()
		bg_layer.add_child(arena_scene)
	if Game.arena_id == "acheron":
		props = ArenaAcheron.new().setup(self)
		bg_layer.add_child(props)

	var embers := CPUParticles2D.new()
	embers.name = "Embers"
	embers.texture = UI.dot_texture()
	embers.amount = 70
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2.UP
	embers.spread = 25.0
	embers.gravity = Vector2(8, -12)
	embers.initial_velocity_min = 20.0
	embers.initial_velocity_max = 70.0
	embers.scale_amount_min = 0.06
	embers.scale_amount_max = 0.2
	embers.orbit_velocity_min = -0.004
	embers.orbit_velocity_max = 0.004
	var er := Gradient.new()
	er.set_color(0, Color(1.0, 0.55, 0.15, 0.0))
	er.add_point(0.2, Color(1.0, 0.6, 0.2, 0.9))
	er.set_color(er.get_point_count() - 1, Color(0.8, 0.2, 0.05, 0.0))
	embers.color_ramp = er
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = add
	bg_layer.add_child(embers)

	for i in 7:
		var w := Sprite2D.new()
		w.texture = UI.dot_texture()
		w.material = add
		w.modulate = Color(0.55, 0.75, 1.0, 0.55)
		w.scale = Vector2.ONE * randf_range(0.35, 0.6)
		w.set_meta("seed", randf() * 100.0)
		w.set_meta("flee", Vector2.ZERO)
		bg_layer.add_child(w)
		_wisps.append(w)

	var fog := ColorRect.new()
	fog.name = "Fog"
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://assets/shaders/fog.gdshader")
	fog.material = fm
	bg_layer.add_child(fog)

	_build_end_button()
	for i in 2:
		mana_views[i] = _build_mana(i)
		_set_mana(i, 0, 0)
		deck_views[i] = _build_deck(i)

	banner = UI.label("", 96, "title", UI.BONE, 14, Color(0.15, 0.02, 0.0))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	ui.add_child(banner)
	if UiSkin.has("turn_banner"):
		# The painted ribbon behind the banner text.
		var ribbon := TextureRect.new()
		ribbon.texture = UiSkin.tex("turn_banner")
		ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon.stretch_mode = TextureRect.STRETCH_SCALE
		ribbon.set_anchors_preset(Control.PRESET_CENTER)
		ribbon.offset_left = -560
		ribbon.offset_right = 560
		ribbon.offset_top = -104
		ribbon.offset_bottom = 104
		ribbon.show_behind_parent = true
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(ribbon)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 0.2, 0.05, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_flash_rect)
	_tips = VBoxContainer.new()
	_tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tips.add_theme_constant_override("separation", 8)
	ui.add_child(_tips)

	var menu := UI.button("Menu", 150, 56)
	menu.add_theme_font_size_override("font_size", 24)
	menu.name = "MenuButton"
	menu.pressed.connect(_open_pause)
	ui.add_child(menu)
	_layout_static()


func _build_end_button() -> void:
	end_btn = Node2D.new()
	board_layer.add_child(end_btn)
	# Lights up (gold fire) when nothing is left to play.
	_end_glow = Aura.make(Vector2(232, 100), true, 34.0)
	_end_glow.colors(Aura.SELECTED)
	end_btn.add_child(_end_glow)
	_end_disc = Shapes.make(Shapes.Kind.ELLIPSE, Vector2(220, 88), Color(0.38, 0.1, 0.05), UI.GOLD, 5.0)
	_end_disc.use_parent_material = false
	end_btn.add_child(_end_disc)
	if UiSkin.has("end_turn_seal"):
		_end_disc.visible = false
		_end_seal = UiSkin.sprite("end_turn_seal", Vector2(260, 130))
		_end_seal.use_parent_material = false
		end_btn.add_child(_end_seal)
	_end_label = UI.label("END TURN", 28, "title", UI.BONE, 6, Color.BLACK)
	_end_label.size = Vector2(220, 88)
	_end_label.position = Vector2(-110, -44)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_btn.add_child(_end_label)
	# Blank and dim until the first turn starts (the mulligan is not a turn).
	_end_label.text = ""
	end_btn.modulate = Color(0.55, 0.52, 0.5)


func _build_mana(side: int) -> Node2D:
	var n := Node2D.new()
	n.z_index = 25 # above the hand, so the crystals always read
	board_layer.add_child(n)
	var l := UI.label("0/0", 34, "title", Color(0.75, 0.88, 1.0), 7, Color(0, 0.02, 0.08))
	l.name = "Label"
	l.size = Vector2(110, 50)
	l.position = Vector2(-230, -25)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.add_child(l)
	for i in BattleState.MAX_MANA:
		var g: Node2D
		if UiSkin.has("gem_mana"):
			# Painted crystals: lit when full, smoky when spent, near black while still locked.
			g = UiSkin.sprite("gem_mana", Vector2(48, 48))
		else:
			g = Shapes.make(Shapes.Kind.DIAMOND, Vector2(24, 32), Color(0.1, 0.1, 0.14), Color(0.4, 0.5, 0.7), 2.0)
		g.use_parent_material = false
		g.name = "Gem%d" % i
		g.position = Vector2(i * 26 - 88, 0)
		g.set_meta("base", g.scale)
		n.add_child(g)
	n.visible = true
	return n


func _set_mana(side: int, mana: int, max_mana: int) -> void:
	var n: Node2D = mana_views[side]
	(n.get_node("Label") as Label).text = "%d/%d" % [mana, max_mana]
	for i in BattleState.MAX_MANA:
		var g: Node2D = n.get_node("Gem%d" % i)
		var base: Vector2 = g.get_meta("base")
		var full := i < mana
		var owned := i < max_mana
		if g is Shapes:
			g.set_fill(UI.MANA if full else (Color(0.12, 0.16, 0.28) if owned else Color(0.08, 0.07, 0.08)))
			g.set_line(Color(0.75, 0.88, 1.0) if full else Color(0.3, 0.35, 0.45))
		else:
			g.modulate = Color(1.15, 1.15, 1.2) if full else (Color(0.32, 0.34, 0.42) if owned else Color(0.12, 0.11, 0.12, 0.8))
		var was_full: bool = g.get_meta("full", false)
		g.set_meta("full", full)
		if full and not was_full:
			g.scale = base * 0.6
			g.create_tween().tween_property(g, "scale", base, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Fx.flash(fx_layer, "k_star_04", n.position + g.position, 70.0, 0.35, Color(0.6, 0.8, 1.0), 0.8)
		elif not full:
			g.scale = base * 0.85


func _build_deck(side: int) -> Node2D:
	var n := Node2D.new()
	board_layer.add_child(n)
	# A real pile: one sheet per three cards, each a little higher and lighter, so the stack thins as it is drawn.
	for i in DECK_SHEETS:
		var c := CardView.new().setup("lost_pilgrim", -1, false)
		c.scale = Vector2(0.36, 0.36)
		c.position = Vector2(i * 1.1, -i * 2.2)
		c.rotation = PI / 2
		var k := 0.55 + 0.45 * float(i) / (DECK_SHEETS - 1)
		c.modulate = Color(k, k, k)
		c.set_process(false)
		n.add_child(c)
	var l := UI.label("20", 30, "title", UI.BONE, 7, Color.BLACK)
	l.name = "Count"
	l.size = Vector2(100, 40)
	l.position = Vector2(-50, -20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(l)
	return n


func _set_deck_count(side: int, count: int) -> void:
	(deck_views[side].get_node("Count") as Label).text = str(count)
	var top := -1
	for i in DECK_SHEETS:
		var on := count > i * 3
		deck_views[side].get_child(i).visible = on
		if on:
			top = i
	var l := deck_views[side].get_node("Count") as Label
	l.position = Vector2(-50, -20) + Vector2(maxi(top, 0) * 1.1, -maxi(top, 0) * 2.2)


func _layout_static() -> void:
	var back: Sprite2D = bg_layer.get_node("Backdrop")
	var ts := back.texture.get_size()
	var s := maxf(V.x / ts.x, V.y / ts.y) * 1.04
	back.scale = Vector2(s, s)
	back.position = V / 2
	var board := bg_layer.get_node_or_null("Board") as Sprite2D
	if board != null:
		# Fit the height so the painted sockets sit exactly on the layout (see _sock).
		var bs := 1080.0 * ky / board.texture.get_size().y
		board.scale = Vector2(bs, bs)
		board.position = V / 2
	for layer in ["frame", "mist"]:
		var n := bg_layer.get_node_or_null("Board_" + layer) as Sprite2D
		if n != null and board != null:
			var ls := board.scale.x * board.texture.get_size().x / n.texture.get_size().x
			n.scale = Vector2(ls, ls)
			n.position = V / 2 if layer == "frame" else Vector2(V.x / 2, _river_y())
	var bed_w := minf(V.x - 520.0, 1220.0)
	for i in 2:
		var bed: Panel = bg_layer.get_node("Bed%d" % i)
		bed.size = Vector2(bed_w, 196 * ky)
		bed.position = Vector2(V.x / 2 - bed_w / 2, _board_y(1 - i) - 98 * ky)
	river.position = Vector2(0, _river_y() - 52 * ky)
	river.size = Vector2(V.x, 104 * ky)
	_river_mat.set_shader_parameter("aspect", V.x / (104.0 * ky))
	var fog: ColorRect = bg_layer.get_node("Fog")
	fog.size = V + Vector2(40, 40)
	fog.position = Vector2(-20, -20)
	var em: CPUParticles2D = bg_layer.get_node("Embers")
	em.position = Vector2(V.x / 2, V.y + 20)
	em.emission_rect_extents = Vector2(V.x / 2, 10)
	end_btn.position = _sock("EndTurn", Vector2(V.x - 175, _river_y()))
	if props != null:
		var anchors := {}
		if _painted_board and arena_scene != null:
			for n in ["PropBell", "PropBrazier", "PropSkulls"]:
				if arena_scene.has_socket(n):
					anchors[n] = _sock(n, Vector2.ZERO)
		props.layout(V, _river_y(), ky, anchors)
	mana_views[0].position = _sock("ManaPlayer", Vector2(V.x - 330, V.y - 54))
	mana_views[1].position = _sock("ManaEnemy", Vector2(V.x - 330, 54))
	deck_views[0].position = _sock("DeckPlayer", Vector2(V.x - 120, _board_y(0) + 40 * ky))
	deck_views[1].position = _sock("DeckEnemy", Vector2(V.x - 120, _board_y(1) - 40 * ky))
	for i in 2:
		if heroes[i] != null:
			heroes[i].home = _hero_pos(i)
			heroes[i].position = heroes[i].home
	banner.size = Vector2(V.x, 200)
	banner.position = Vector2(0, V.y / 2 - 100)
	_flash_rect.size = V
	ui.get_node("MenuButton").position = Vector2(24, 20)
	_tips.position = Vector2(400, V.y / 2 - 160)


## Screen position of an arena socket. Sockets follow the painted board (fit to height, centred); without a painted
## board the old edge-anchored layout (`fallback`) keeps the side widgets near the screen edges on wide phones.
func _sock(n: String, fallback: Vector2) -> Vector2:
	if not _painted_board or arena_scene == null or not arena_scene.has_socket(n):
		return fallback
	return V / 2 + (arena_scene.socket(n) - Vector2(960, 540)) * ky


func _board_y(side: int) -> float:
	return (592.0 if side == 0 else 352.0) * ky + _oy()


func _river_y() -> float:
	return 472.0 * ky + _oy()


func _hero_pos(side: int) -> Vector2:
	return Vector2(V.x / 2, (808.0 if side == 0 else 150.0) * ky + _oy())


## Top of the 16:9 layout: screens taller than 16:9 (tablets) centre it vertically.
func _oy() -> float:
	return (V.y - 1080.0 * ky) / 2.0


func _intro(arena: Dictionary) -> void:
	var title := UI.label(arena.get("name", ""), 64, "title", UI.GOLD, 12, Color(0.1, 0.0, 0.0))
	var sub := UI.label(arena.get("intro", ""), 30, "italic", UI.BONE, 6, Color.BLACK)
	for l in [title, sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(V.x, 100)
		l.modulate.a = 0.0
		ui.add_child(l)
	title.position = Vector2(0, V.y * 0.36)
	sub.position = Vector2(0, V.y * 0.36 + 90)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [title, sub]:
		var t: Tween = l.create_tween()
		t.tween_property(l, "modulate:a", 1.0, 0.6)
		t.tween_interval(1.8)
		t.tween_property(l, "modulate:a", 0.0, 0.7)
		t.tween_callback(l.queue_free)
	Sfx.play("title_sting", -8.0, 1.0, 0.0)
	queue.push_front({"t": "wait", "time": 2.6})


# ================================================================ main loop

func _process(delta: float) -> void:
	_tick_fx(delta)
	_tick_parallax(delta)
	if _painted_board:
		var mist := bg_layer.get_node_or_null("Board_mist") as Sprite2D
		if mist != null:
			var t := Time.get_ticks_msec() / 1000.0
			mist.position.x = V.x / 2 + sin(t * 0.07) * 120.0
			mist.modulate.a = 0.3 + 0.08 * sin(t * 0.31)
	if shots_dir != "":
		_shot_t += delta
		if _shot_t > _shot_every:
			_shot_t = 0.0
			_take_shot()
	if playing:
		return
	if not queue.is_empty():
		_play_next()
		return
	if over:
		return
	if _highlight_dirty:
		_highlight_dirty = false
		_refresh_highlights()
	if st.current == 1 or autoplay:
		_ai_delay -= delta
		if _ai_delay <= 0.0:
			_ai_step()
	if _hover_unit != null and mode == Mode.IDLE and not _pressed:
		_hover_unit_t += delta
		if _hover_unit_t > 0.45 and inspect == null:
			_show_inspect(_hover_unit)


func _play_next() -> void:
	playing = true
	var ev: Dictionary = queue.pop_front()
	await _present(ev)
	playing = false
	_highlight_dirty = true
	_ai_delay = 0.45 / Settings.anim_speed()


func _ai_step() -> void:
	var brain := ai if st.current == 1 else ai_self
	var act := brain.next_action(st)
	var done := false
	match act.do:
		"play":
			done = st.play_card(st.current, act.uid, act.target, act.index)
		"attack":
			done = st.attack(st.current, act.attacker, act.target)
		"power":
			done = st.use_power(st.current, act.target)
	if not done:
		st.end_turn()
	_ai_delay = 0.6


func _speed() -> float:
	return Settings.anim_speed()


func _wait(t: float) -> void:
	await get_tree().create_timer(t / _speed()).timeout


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _tick_fx(delta: float) -> void:
	if _shake > 0.1:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0))
	else:
		cam.offset = Vector2.ZERO
	_river_mat.set_shader_parameter("now", Time.get_ticks_msec() / 1000.0)
	var t := Time.get_ticks_msec() / 1000.0
	for w in _wisps:
		var sd: float = w.get_meta("seed")
		var flee: Vector2 = w.get_meta("flee")
		flee = flee.lerp(Vector2.ZERO, delta * 0.6)
		w.set_meta("flee", flee)
		var base := Vector2(fposmod(sd * 173.0 + t * (12.0 + fmod(sd, 7.0)), V.x + 200) - 100,
			_river_y() + sin(t * 0.4 + sd) * 40 * ky)
		w.position = base + flee + Vector2(sin(t * 1.3 + sd * 3.0), cos(t * 0.9 + sd)) * 14.0
		w.modulate.a = 0.35 + 0.25 * sin(t * 2.0 + sd)
	if inspect != null and mode != Mode.IDLE:
		_hide_inspect()


# ================================================================ presentation

func _present(ev: Dictionary) -> void:
	match ev.t:
		"wait":
			await _wait(ev.time)
		"first":
			_first_side = ev.side
		"start":
			for i in 2:
				var h := HeroView.new().setup(ev.heroes[i])
				h.home = _hero_pos(i)
				h.position = h.home
				board_layer.add_child(h)
				heroes[i] = h
				unit_views[h.uid] = h
				_set_deck_count(i, ev.decks[i])
				h.scale = Vector2(0.6, 0.6)
				h.modulate.a = 0.0
				var t := h.create_tween().set_parallel(true)
				t.tween_property(h, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t.tween_property(h, "modulate:a", 1.0, 0.4)
		"turn":
			_set_end_button(ev.side)
			if ev.side == 0:
				_show_banner("YOUR TURN", UI.GOLD)
				Sfx.play("chime", -6.0, 1.0, 0.0)
			else:
				_show_banner("ENEMY TURN", Color(0.9, 0.5, 0.4), 72)
				Sfx.play("bell_far", -14.0)
			if heroes[ev.side].power_used:
				heroes[ev.side].flip_power(false)
			await _wait(0.75 if ev.side == 0 else 0.5)
		"mana":
			_set_mana(ev.side, ev.mana, ev.max)
		"wake":
			for uid in ev.uids:
				if unit_views.has(uid):
					unit_views[uid].set_sleeping(false)
		"draw":
			await _on_draw(ev)
		"burn":
			var c := CardView.new().setup(ev.id, -1, true)
			c.position = deck_views[ev.side].position
			c.scale = Vector2(0.4, 0.4)
			hand_layer.add_child(c)
			_set_deck_count(ev.side, ev.deck)
			var t := c.create_tween()
			t.tween_property(c, "position", Vector2(V.x / 2 + 300, V.y / 2), 0.4)
			t.parallel().tween_property(c, "scale", Vector2(0.8, 0.8), 0.4)
			await t.finished
			Sfx.play("thunder", -16.0, 1.4)
			await c.burn_away(0.8)
		"fatigue":
			var h: HeroView = heroes[ev.side]
			Fx.number(fx_layer, h.position + Vector2(0, -130), "Fatigue %d" % ev.amount, Color(0.8, 0.7, 1.0), false)
			await _wait(0.4)
		"play":
			await _on_play(ev)
		"summon":
			await _on_summon(ev)
		"attack":
			await _on_attack(ev)
		"damage":
			_on_damage(ev)
			await _wait(0.12)
		"heal":
			var v = unit_views.get(ev.uid)
			if v != null:
				Fx.number(fx_layer, v.position, "+%d" % ev.amount, UI.HEAL, false)
				Fx.burst(fx_layer, v.position, Color(0.4, 1.0, 0.4), 20, 160.0, 0.8, 22.0, -60.0, 180.0, "k_star_01")
				_set_unit_hp(v, ev.hp)
				Sfx.play("chime", -12.0, 1.3)
			await _wait(0.2)
		"armor":
			var h: HeroView = unit_views.get(ev.uid)
			h.set_armor(ev.armor)
			Fx.burst(fx_layer, h.position + Vector2(h.W / 2, -60), Color(0.75, 0.8, 0.9), 24, 200.0, 0.6, 10.0)
			Sfx.play("slam", -12.0, 1.5)
			Sfx.play("metal", -6.0)
			await _wait(0.25)
		"buff":
			var m = unit_views.get(ev.uid)
			if m is MinionView:
				m.apply({"attack": ev.attack, "health": ev.health, "max_health": ev.max_health, "keywords": ev.keywords})
				Fx.flash(fx_layer, "holy_light", m.position, 320.0, 0.7, Color.WHITE, 0.3)
				Fx.burst(fx_layer, m.position, UI.GOLD, 30, 220.0, 0.8, 24.0, -100.0, 180.0, "k_star_04")
				Fx.flash(fx_layer, "k_twirl_01", m.position, 300.0, 0.6, UI.GOLD, 1.5)
				_pop(m, 1.18)
				Sfx.play("chime", -10.0, 1.15)
			await _wait(0.2)
		"ward_break":
			var m = unit_views.get(ev.uid)
			if m is MinionView:
				m.break_ward()
				Fx.flash(fx_layer, "ward_bubble", m.position, 260.0, 0.4, Color.WHITE, 0.0)
				Fx.burst(fx_layer, m.position, Color(1.0, 0.9, 0.5), 36, 340.0, 0.5, 9.0, 0.0)
				Fx.sparks(fx_layer, m.position, Color(1.0, 0.9, 0.5), 16)
				Sfx.play("tick", -4.0, 0.7)
				Sfx.play("glass", -4.0, 1.2)
				Sfx.play("bones", -14.0, 1.6)
			await _wait(0.2)
		"venom":
			var m = unit_views.get(ev.uid)
			if m != null:
				Fx.flash(fx_layer, "venom_drops", m.position, 240.0, 0.6)
				Fx.burst(fx_layer, m.position, Color(0.35, 1.0, 0.25), 30, 200.0, 0.7, 11.0, 100.0)
				m.flash(Color(0.3, 1.0, 0.2))
		"death":
			await _on_death(ev)
		"bounce":
			await _on_bounce(ev)
		"projectile":
			var a = unit_views.get(ev.from)
			var b = unit_views.get(ev.to)
			if a != null and b != null:
				var col := UI.EMBER
				if ev.kind == "buff":
					col = UI.GOLD
				elif ev.kind == "freeze":
					col = Color(0.5, 0.8, 1.0)
				elif ev.kind == "silence":
					col = Color(0.8, 0.8, 0.9)
				elif ev.kind == "destroy":
					col = Color(0.6, 0.2, 1.0)
				Sfx.play("swish_long", -6.0, 0.8)
				Sfx.play({"freeze": "chain", "silence": "lock", "destroy": "spell", "buff": "gem"}.get(ev.kind, "spell_fire"), -8.0)
				if ev.kind in ["buff", "silence"]:
					Sfx.play("magic", -10.0)
				await Fx.projectile(fx_layer, a.position, b.position, col, 0.38 / _speed())
				Sfx.play("thud", -6.0)
				if ev.kind == "freeze":
					Sfx.play("glass", -6.0, 0.8)
					Sfx.play("ice", -6.0)
					Fx.flash(fx_layer, "k_star_07", b.position, 300.0, 0.6, Color(0.6, 0.85, 1.0), 0.6)
				if ev.kind == "destroy":
					shake(10.0)
		"aoe":
			await _on_aoe(ev)
		"power":
			heroes[ev.side].flip_power(true)
			Sfx.play("swish", -6.0, 0.7)
			await _wait(0.25)
		"turn_end":
			pass
		"status":
			var sm = unit_views.get(ev.uid)
			if sm is MinionView:
				sm.apply({"keywords": ev.keywords, "attack": ev.attack, "health": ev.health, "max_health": ev.max_health})
				sm.set_frozen(ev.frozen)
				if ev.silenced:
					sm.flash(Color(0.8, 0.8, 0.9))
			await _wait(0.12)
		"trigger":
			var tm = unit_views.get(ev.uid)
			if tm != null:
				_pop(tm, 1.15)
				Fx.burst(fx_layer, tm.position, UI.GOLD, 16, 160.0, 0.5, 8.0, 0.0)
				Sfx.play("tick", -8.0, 0.8)
			await _wait(0.25)
		"mulligan_begin":
			_in_mulligan = true
		"mulligan_wait":
			await _mulligan_wait()
		"mulligan_swap":
			await _mulligan_swap(ev)
		"mulligan_end":
			_in_mulligan = false
			Sfx.play("swish_long", -6.0)
			Sfx.play("card_shuffle", -6.0)
			for c in hand_views[0]:
				c.selected = false
			_layout_hand(0)
			await _wait(0.45)
		"game_over":
			await _on_game_over(ev)


func _on_draw(ev: Dictionary) -> void:
	var side: int = ev.side
	var c := CardView.new().setup(ev.id, ev.uid, false)
	c.position = deck_views[side].position
	c.rotation = PI / 2
	c.scale = Vector2(0.36, 0.36)
	hand_layer.add_child(c)
	hand_views[side].append(c)
	_set_deck_count(side, ev.deck)
	Sfx.play("swish", -10.0, 1.1)
	Sfx.play("card_slide", -10.0, 1.05)
	if side == 0 and _in_mulligan:
		var i: int = hand_views[0].size() - 1
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "position", _mull_slot(i), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(c, "rotation", 0.0, 0.35)
		t.tween_property(c, "scale", Vector2(0.95, 0.95), 0.35)
		await t.finished
		var f := c.create_tween()
		f.tween_property(c, "scale:x", 0.0, 0.08)
		f.tween_callback(c.set_face_up.bind(true))
		f.tween_property(c, "scale:x", 0.95, 0.08)
		await f.finished
		return
	if side == 0:
		# Fly to the middle, flip face up, then into the hand.
		var mid := Vector2(V.x - 420, V.y * 0.55)
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "position", mid, 0.28 / _speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(c, "rotation", 0.0, 0.28 / _speed())
		t.tween_property(c, "scale", Vector2(0.75, 0.75), 0.28 / _speed())
		await t.finished
		var f := c.create_tween()
		f.tween_property(c, "scale:x", 0.0, 0.08 / _speed())
		f.tween_callback(c.set_face_up.bind(true))
		f.tween_property(c, "scale:x", 0.75, 0.08 / _speed())
		await f.finished
		await _wait(0.1)
	_layout_hand(side)
	await _wait(0.16)


func _mull_slot(i: int) -> Vector2:
	var n: int = st.sides[0].hand.size() # the whole opening hand, even while it is still being dealt
	return Vector2(V.x / 2 + (i - (n - 1) / 2.0) * 300.0, V.y * 0.47)


func _mulligan_wait() -> void:
	if autoplay:
		_confirm_mulligan()
		return
	_mull_waiting = true
	var dim := ColorRect.new()
	dim.name = "MulliganDim"
	dim.color = Color(0, 0, 0, 0)
	dim.size = V + Vector2(200, 200)
	dim.position = Vector2(-100, -100)
	dim.z_index = -1
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_layer.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.82, 0.3)
	_mull_ui = Control.new()
	_mull_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mull_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_mull_ui)
	var title := UI.label("Your starting hand", 64, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(V.x, 80)
	title.position = Vector2(0, V.y * 0.12)
	_mull_ui.add_child(title)
	var order := "You go first." if _first_side == 0 else "You go second, with an extra card and Charon's Obol."
	var sub := UI.label(order + "   Tap the cards you want to replace.", 30, "italic", UI.BONE, 5, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(V.x, 40)
	sub.position = Vector2(0, V.y * 0.12 + 80)
	_mull_ui.add_child(sub)
	var ok := UI.button("Confirm", 340, 84)
	ok.position = Vector2(V.x / 2 - 170, V.y * 0.78)
	ok.pressed.connect(_confirm_mulligan)
	_mull_ui.add_child(ok)
	await mulligan_confirmed


func _toggle_mulligan(c: CardView) -> void:
	if _mull_marks.has(c.uid):
		_mull_marks[c.uid].queue_free()
		_mull_marks.erase(c.uid)
		c.modulate = Color.WHITE
	else:
		var x := UI.label("REPLACE", 40, "title", Color(1.0, 0.35, 0.25), 10, Color.BLACK)
		x.size = Vector2(CardView.W, 60)
		x.position = Vector2(-CardView.W / 2, -30)
		x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.rotation = -0.2
		c.add_child(x)
		_mull_marks[c.uid] = x
		c.modulate = Color(0.6, 0.55, 0.55)
	Sfx.play("tick", -6.0)
	_pop(c, 1.04)


func _confirm_mulligan() -> void:
	if _mull_ui != null:
		_mull_ui.queue_free()
		_mull_ui = null
	_mull_waiting = false
	var dim := hand_layer.get_node_or_null("MulliganDim")
	if dim != null:
		var t := dim.create_tween()
		t.tween_property(dim, "color:a", 0.0, 0.4)
		t.tween_callback(dim.queue_free)
	var chosen := _mull_marks.keys()
	for uid in _mull_marks:
		_mull_marks[uid].queue_free()
	_mull_marks.clear()
	for c in hand_views[0]:
		c.modulate = Color.WHITE
	st.finish_mulligan(1, ai.mulligan_choice(st))
	st.finish_mulligan(0, chosen if not autoplay else ai_self.mulligan_choice(st))
	mulligan_confirmed.emit()


func _mulligan_swap(ev: Dictionary) -> void:
	var side: int = ev.side
	for i in hand_views[side].size():
		var old: CardView = hand_views[side][i]
		if old.uid != ev.old:
			continue
		if side == 1:
			old.uid = ev.uid
			old.card_id = ev.id
			return
		Sfx.play("card_flip", -8.0)
		var c := CardView.new().setup(ev.id, ev.uid, false)
		c.position = deck_views[0].position
		c.rotation = PI / 2
		c.scale = Vector2(0.36, 0.36)
		hand_layer.add_child(c)
		hand_views[0][i] = c
		var slot := old.position
		var t := old.create_tween().set_parallel(true)
		t.tween_property(old, "position", deck_views[0].position, 0.3)
		t.tween_property(old, "scale", Vector2(0.36, 0.36), 0.3)
		t.tween_property(old, "rotation", PI / 2, 0.3)
		t.chain().tween_callback(old.queue_free)
		Sfx.play("swish", -8.0)
		await _wait(0.15)
		var t2 := c.create_tween().set_parallel(true)
		t2.tween_property(c, "position", slot, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t2.tween_property(c, "rotation", 0.0, 0.35)
		t2.tween_property(c, "scale", Vector2(0.95, 0.95), 0.35)
		await t2.finished
		var f := c.create_tween()
		f.tween_property(c, "scale:x", 0.0, 0.08)
		f.tween_callback(c.set_face_up.bind(true))
		f.tween_property(c, "scale:x", 0.95, 0.08)
		await f.finished
		return


func _on_play(ev: Dictionary) -> void:
	var side: int = ev.side
	var c: CardView = null
	for v in hand_views[side]:
		if v.uid == ev.uid:
			c = v
	if c == null:
		c = CardView.new().setup(ev.id, ev.uid, true)
		c.position = Vector2(V.x / 2, V.y / 2)
		hand_layer.add_child(c)
	hand_views[side].erase(c)
	_layout_hand(side)
	c.dragging = false
	c.playable = false
	c.selected = false
	c.z_index = 30
	Sfx.play("whoosh", -6.0)
	Sfx.play("card_slide", -4.0)
	if side == 1 or not c.face_up:
		# Reveal the opponent's card.
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "position", Vector2(V.x / 2 - 380, V.y * 0.42), 0.3 / _speed()).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(c, "rotation", 0.0, 0.3 / _speed())
		t.tween_property(c, "scale", Vector2(0.9, 0.9), 0.3 / _speed())
		await t.finished
		var f := c.create_tween()
		f.tween_property(c, "scale:x", 0.0, 0.1)
		f.tween_callback(c.set_face_up.bind(true))
		f.tween_property(c, "scale:x", 0.9, 0.1)
		await f.finished
		await _wait(0.9)
	if ev.type == "minion":
		_pending_card[ev.uid] = c
	else:
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "position", Vector2(V.x / 2 - 380, V.y * 0.47), 0.2 / _speed())
		t.tween_property(c, "scale", Vector2(0.85, 0.85), 0.2 / _speed())
		t.tween_property(c, "rotation", 0.0, 0.2 / _speed())
		await t.finished
		Fx.flash(fx_layer, "fire_burst", c.position, 380.0, 0.8)
		Fx.burst(fx_layer, c.position, UI.EMBER, 40, 300.0, 0.9, 12.0, -50.0)
		c.burn_away(0.9 / _speed())
		await _wait(0.25)


func _on_summon(ev: Dictionary) -> void:
	var side: int = ev.side
	var snap: Dictionary = ev.unit
	var m := MinionView.new().setup(snap)
	board_layer.add_child(m)
	unit_views[m.uid] = m
	var idx := clampi(int(ev.index), 0, board_views[side].size())
	board_views[side].insert(idx, m)
	_gap_index = -1
	_layout_board(side, m)
	var card: CardView = _pending_card.get(ev.from_card)
	_pending_card.erase(ev.from_card)
	var rarity: String = CardDB.card(snap.id).get("rarity", "common")
	if card != null:
		m.position = card.position
		var t := card.create_tween().set_parallel(true)
		t.tween_property(card, "position", m.home, 0.14 / _speed())
		t.tween_property(card, "scale", Vector2(0.4, 0.4), 0.14 / _speed())
		t.tween_property(card, "modulate:a", 0.0, 0.14 / _speed())
		t.chain().tween_callback(card.queue_free)
	else:
		m.position = m.home
	m.scale = Vector2(1.55, 1.55)
	m.modulate.a = 0.0
	m.z_index = 10
	var drop := m.create_tween().set_parallel(true)
	drop.tween_property(m, "position", m.home, 0.2 / _speed()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop.tween_property(m, "scale", Vector2.ONE, 0.2 / _speed()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop.tween_property(m, "modulate:a", 1.0, 0.1 / _speed())
	await drop.finished
	m.z_index = 0
	Fx.dust(fx_layer, m.position + Vector2(0, MinionView.H * 0.42), MinionView.W * 1.2)
	var cost := int(CardDB.card(m.card_id).get("cost", 0))
	Fx.summon(fx_layer, m.position + Vector2(0, MinionView.H * 0.32), UI.RARITY.get(rarity, UI.EMBER) if rarity != "common" else UI.EMBER,
		300.0 + cost * 14.0, 1.0 + cost * 0.05, clampf((cost - 3) / 5.0, 0.0, 1.0))
	Sfx.play("slam", -4.0)
	Sfx.play("card_place", -6.0)
	if cost >= 6:
		Sfx.play("roar", -8.0, 0.9)
	elif cost >= 4:
		Sfx.play("growl", -12.0, 1.0, 0.1)
	if rarity == "legendary":
		shake(18.0)
		Fx.shockwave(fx_layer, m.position, UI.GOLD, 520.0, 0.7)
		Fx.summon(fx_layer, m.position + Vector2(0, MinionView.H * 0.32), UI.GOLD, 680.0, 1.8, 1.0)
		Fx.flash(fx_layer, "holy_light", m.position, 700.0, 1.0, Color(1, 0.85, 0.6), 0.2)
		Fx.burst(fx_layer, m.position, UI.GOLD, 70, 520.0, 1.2, 14.0, 120.0)
		_screen_flash(Color(1.0, 0.75, 0.3), 0.35)
		Sfx.play("thunder", -8.0, 0.9)
		await _legendary_cutin(snap.id)
	else:
		shake(3.0 + float(CardDB.card(snap.id).get("cost", 1)) * 1.2)
		await _wait(0.2)


func _on_attack(ev: Dictionary) -> void:
	var a = unit_views.get(ev.attacker)
	var b = unit_views.get(ev.target)
	if a == null or b == null:
		return
	a.busy = true
	a.z_index = 15
	var dir: Vector2 = (b.position - a.position).normalized()
	var hit: Vector2 = b.position - dir * 70.0
	var t: Tween = a.create_tween()
	t.tween_property(a, "scale", Vector2(1.14, 1.14), 0.12 / _speed()).set_trans(Tween.TRANS_QUAD)
	Sfx.play("whoosh", -8.0, 0.9)
	t.parallel().tween_property(a, "position", a.position - dir * 26.0, 0.12 / _speed())
	t.tween_property(a, "position", hit, 0.13 / _speed()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await t.finished
	Sfx.play("thud", -2.0, 0.9)
	Sfx.play("clash" if b is MinionView else "blade", -6.0)
	shake(9.0 if b is HeroView else 6.0)
	if int(a.attack if a is MinionView else 0) >= 5 or b is HeroView:
		_hit_stop(0.07 if b is HeroView else 0.09)
	Fx.flash(fx_layer, "claw_slash", b.position, 260.0, 0.35, Color.WHITE, 0.0)
	Fx.slash(fx_layer, b.position, dir, 320.0, Color(1.0, 0.85, 0.6))
	Fx.sparks(fx_layer, b.position - dir * 40.0, Color(1.0, 0.7, 0.3), 22)
	Fx.burst(fx_layer, (a.position + b.position) / 2, Color(1.0, 0.75, 0.4), 22, 300.0, 0.4, 8.0, 200.0)
	_push(b, dir * 18.0)
	var back: Tween = a.create_tween().set_parallel(true)
	back.tween_property(a, "position", a.home, 0.28 / _speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	back.tween_property(a, "scale", Vector2.ONE, 0.28 / _speed())
	back.chain().tween_callback(_land.bind(a))


## A freeze-frame on heavy hits: the world stops for a few frames, which sells the weight of the blow.
var _stops := 0
func _hit_stop(seconds: float) -> void:
	if _speed() > 1.0:
		return
	_stops += 1
	Engine.time_scale = 0.03
	await get_tree().create_timer(seconds, true, false, true).timeout
	_stops -= 1
	if _stops == 0:
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0 # never leave a hit-stop behind when the scene changes


func _land(a: Node2D) -> void:
	if is_instance_valid(a):
		a.busy = false
		a.z_index = 0


func _push(v: Node2D, off: Vector2) -> void:
	var t := v.create_tween()
	t.tween_property(v, "position", v.home + off, 0.06)
	t.tween_property(v, "position", v.home, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_damage(ev: Dictionary) -> void:
	var v = unit_views.get(ev.uid)
	if v == null:
		return
	Fx.number(fx_layer, v.position, "-%d" % ev.amount, Color(0.75, 0.05, 0.03), true)
	v.flash()
	if v is HeroView:
		v.set_health(ev.hp, ev.armor)
		shake(4.0 + ev.amount * 1.6)
	else:
		_set_unit_hp(v, ev.hp)
		shake(2.0 + ev.amount)
	Fx.flash(fx_layer, "blood_splat", v.position, 150.0 + ev.amount * 20.0, 0.5)
	Fx.burst(fx_layer, v.position, Color(0.8, 0.1, 0.05), 10 + ev.amount * 3, 240.0, 0.6, 9.0, 400.0)


func _set_unit_hp(v, hp: int) -> void:
	if v is HeroView:
		v.set_health(hp)
	else:
		v.apply({"health": hp})


func _on_death(ev: Dictionary) -> void:
	var m = unit_views.get(ev.uid)
	unit_views.erase(ev.uid)
	if m == null:
		return
	board_views[ev.side].erase(m)
	Sfx.play("moan", -14.0, 1.0, 0.12)
	Sfx.play("creature_die", -12.0, 1.1)
	Fx.flash(fx_layer, "fire_burst", m.position, 300.0, 0.7)
	Fx.flash(fx_layer, "smoke_puff", m.position + Vector2(0, -30), 340.0, 1.2, Color(1, 1, 1, 0.7), 0.2)
	Fx.burst(fx_layer, m.position, UI.EMBER, 40, 180.0, 1.4, 10.0, -140.0, 120.0)
	Fx.smoke(fx_layer, m.position, Color(0.2, 0.17, 0.15, 0.75), 220.0)
	m.burn_away(0.85 / _speed())
	get_tree().create_timer(0.85 / _speed()).timeout.connect(_remove_dead.bind(m, ev.side))
	await _wait(0.22)


func _remove_dead(m: Node2D, side: int) -> void:
	if is_instance_valid(m):
		m.queue_free()
	_layout_board(side)


func _on_bounce(ev: Dictionary) -> void:
	var m = unit_views.get(ev.uid)
	unit_views.erase(ev.uid)
	if m != null:
		board_views[ev.side].erase(m)
		var t: Tween = m.create_tween().set_parallel(true)
		t.tween_property(m, "position", Vector2(V.x / 2, V.y if ev.side == 0 else 0.0), 0.35)
		t.tween_property(m, "scale", Vector2(0.4, 0.4), 0.35)
		t.tween_property(m, "modulate:a", 0.0, 0.35)
		Sfx.play("gust", -8.0)
		await t.finished
		m.queue_free()
	_layout_board(ev.side)
	var c := CardView.new().setup(ev.id, ev.card_uid, ev.side == 0)
	c.position = Vector2(V.x / 2, V.y if ev.side == 0 else 0.0)
	c.scale = Vector2(0.3, 0.3)
	hand_layer.add_child(c)
	hand_views[ev.side].append(c)
	_layout_hand(ev.side)
	await _wait(0.25)


func _on_aoe(ev: Dictionary) -> void:
	var origin: Vector2 = heroes[ev.side].position
	match ev.id:
		"minotaur_rampage":
			Sfx.play("quake_rumble", -2.0, 1.0, 0.0)
			Sfx.play("thunder", -6.0, 0.8)
			_screen_flash(Color(0.9, 0.1, 0.05), 0.6)
			shake(26.0)
			for i in 6:
				Fx.dust(fx_layer, Vector2(V.x * (0.2 + i * 0.12), _board_y(i % 2) + 70), 260.0, 40)
			await _wait(0.5)
			shake(18.0)
		"medusa_gaze":
			Sfx.play("wail", -10.0, 0.7)
			_screen_flash(Color(1.0, 0.25, 0.0), 0.45)
			Fx.shockwave(fx_layer, origin, Color(1.0, 0.3, 0.05), 1200.0, 0.8)
			await _wait(0.35)
		"furies":
			Sfx.play("wail", -8.0, 1.1)
			var src = board_views[ev.side].back() if not board_views[ev.side].is_empty() else heroes[ev.side]
			Fx.shockwave(fx_layer, src.position, Color(0.7, 0.55, 1.0), 900.0, 0.7)
			await _wait(0.3)
		_:
			Fx.shockwave(fx_layer, origin, UI.EMBER, 900.0, 0.6)
			await _wait(0.3)


func _on_game_over(ev: Dictionary) -> void:
	over = true
	_end_aim()
	await _wait(0.5)
	var loser: int = -1
	if ev.winner == 0:
		loser = 1
	elif ev.winner == 1:
		loser = 0
	if loser != -1:
		var h: HeroView = heroes[loser]
		shake(30.0)
		Sfx.play("thunder", 0.0, 0.7)
		Fx.burst(fx_layer, h.position, UI.EMBER, 120, 700.0, 1.6, 16.0, 200.0)
		Fx.shockwave(fx_layer, h.position, UI.EMBER, 1400.0, 1.0)
		_screen_flash(Color(1, 0.5, 0.2), 0.6)
		await h.burn_away(1.4)
	Game.record_result(ev.winner)
	_show_result(ev.winner)


func _show_result(winner: int) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = V
	ui.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.65, 0.6)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = V
	box.add_theme_constant_override("separation", 26)
	ui.add_child(box)
	var won := winner == 0
	var title := UI.label("VICTORY" if won else ("DEFEAT" if winner == 1 else "DRAW"), 150, "title",
		UI.GOLD if won else Color(0.8, 0.25, 0.2), 18, Color(0.1, 0.0, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var line := "Charon steps aside. The river can be crossed." if won and Game.enemy_deck == "ferry" else (
		"The pilgrim falls silent on the shore." if won else "The shades close in. Try again.")
	var sub := UI.label(line, 34, "italic", UI.BONE, 6, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var reward := Collection.reward_battle(won)
	Sfx.play("coins", -4.0)
	var gain := UI.label("+%d Obols   ·   a pack costs %d" % [reward, Collection.PACK_PRICE], 34, "title",
		Color(1.0, 0.85, 0.5), 6, Color.BLACK)
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(gain)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	if Collection.packs > 0 or Collection.obols >= Collection.PACK_PRICE:
		var packs := UI.button("Open Packs", 340)
		packs.pressed.connect(func(): Game.go(Game.PACKS))
		row.add_child(packs)
	var again := UI.button("Play Again", 340)
	again.pressed.connect(func(): Game.go(Game.BATTLE))
	row.add_child(again)
	var menu := UI.button("Main Menu", 340)
	menu.pressed.connect(func(): Game.go(Game.MENU))
	row.add_child(menu)
	box.modulate.a = 0.0
	title.pivot_offset = Vector2(V.x / 2, 90)
	title.scale = Vector2(1.6, 1.6)
	var t := box.create_tween().set_parallel(true)
	t.tween_property(box, "modulate:a", 1.0, 0.5)
	t.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if won:
		Sfx.play("title_sting", -4.0, 1.0, 0.0)
		Fx.burst(fx_layer, V / 2, UI.GOLD, 120, 800.0, 2.0, 14.0, 300.0)
	else:
		Sfx.play("bell_funeral", -6.0, 1.0, 0.0)


## Legendary entrance: letterbox bars close in, the card swings in big beside its name, then everything sweeps away.
func _legendary_cutin(id: String) -> void:
	var card := CardDB.card(id)
	var root := Control.new()
	root.size = V
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var bar_h := V.y * 0.16
	var bars: Array[ColorRect] = []
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0.02, 0.01, 0.01, 0.92)
		b.size = Vector2(V.x, bar_h)
		b.position = Vector2(0, -bar_h if top else V.y)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		bars.append(b)
	var band := ColorRect.new()
	band.color = Color(0.05, 0.02, 0.01, 0.0)
	band.size = Vector2(V.x, V.y - bar_h * 2)
	band.position = Vector2(0, bar_h)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	var parts := str(card.get("name", "")).split(",")
	var name_l := UI.label(parts[0].strip_edges().to_upper(), 92, "title", UI.RARITY.legendary, 14, Color(0.12, 0.03, 0.0))
	name_l.size = Vector2(V.x * 0.55, 120)
	name_l.position = Vector2(V.x * 0.4, V.y / 2 - 90)
	name_l.modulate.a = 0.0
	root.add_child(name_l)
	var epithet := UI.label(parts[1].strip_edges() if parts.size() > 1 else "Legendary", 40, "italic", UI.BONE, 6, Color.BLACK)
	epithet.size = Vector2(V.x * 0.55, 60)
	epithet.position = Vector2(V.x * 0.4 + 6, V.y / 2 + 30)
	epithet.modulate.a = 0.0
	root.add_child(epithet)
	var cv := CardView.new().setup(id, -1, true)
	cv.sway = true
	cv.auto_tilt = false
	cv.position = Vector2(-300, V.y / 2)
	cv.rotation = -0.5
	cv.scale = Vector2.ONE * 1.25 * ky
	cv.z_index = 10
	root.add_child(cv)
	var sp := _speed()
	var t := root.create_tween().set_parallel(true)
	t.tween_property(bars[0], "position:y", 0.0, 0.25 / sp).set_ease(Tween.EASE_OUT)
	t.tween_property(bars[1], "position:y", V.y - bar_h, 0.25 / sp).set_ease(Tween.EASE_OUT)
	t.tween_property(band, "color:a", 0.75, 0.3 / sp)
	t.tween_property(cv, "position", Vector2(V.x * 0.25, V.y / 2), 0.45 / sp).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(cv, "rotation", -0.06, 0.45 / sp).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(name_l, "modulate:a", 1.0, 0.3 / sp).set_delay(0.2 / sp)
	t.tween_property(name_l, "position:x", V.x * 0.42, 1.4 / sp).set_delay(0.2 / sp)
	t.tween_property(epithet, "modulate:a", 1.0, 0.3 / sp).set_delay(0.35 / sp)
	Fx.burst(fx_layer, Vector2(V.x * 0.25, V.y / 2), UI.GOLD, 50, 600.0, 1.0, 12.0, 100.0)
	await get_tree().create_timer(1.3 / sp).timeout
	var out := root.create_tween().set_parallel(true)
	out.tween_property(cv, "position:x", V.x + 300, 0.3 / sp).set_ease(Tween.EASE_IN)
	out.tween_property(root, "modulate:a", 0.0, 0.3 / sp)
	await out.finished
	root.queue_free()


func _show_banner(text: String, color: Color, size: int = 96) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_font_size_override("font_size", size)
	banner.pivot_offset = banner.size / 2
	banner.scale = Vector2(1.4, 1.4)
	var t := banner.create_tween()
	t.set_parallel(true)
	t.tween_property(banner, "modulate:a", 1.0, 0.2)
	t.tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(0.7)
	t.chain().tween_property(banner, "modulate:a", 0.0, 0.4)


func _screen_flash(color: Color, duration: float) -> void:
	_flash_rect.color = Color(color.r, color.g, color.b, 0.45)
	_flash_rect.create_tween().tween_property(_flash_rect, "color:a", 0.0, duration)


func _pop(n: Node2D, s: float) -> void:
	var t := n.create_tween()
	t.tween_property(n, "scale", Vector2(s, s), 0.1)
	t.tween_property(n, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _set_end_button(side: int) -> void:
	var mine := side == 0 and not autoplay
	end_btn.modulate = Color.WHITE
	_end_label.text = "END TURN" if mine else "ENEMY TURN"
	_end_label.add_theme_font_size_override("font_size", 28 if mine else 22)
	_end_disc.set_fill(Color(0.38, 0.1, 0.05) if mine else Color(0.15, 0.12, 0.1))
	if _end_seal != null:
		_end_seal.modulate = Color.WHITE if mine else Color(0.45, 0.42, 0.4)
	_end_glow.set_on(false)
	var t := end_btn.create_tween()
	t.tween_property(end_btn, "scale:y", 0.0, 0.1)
	t.tween_property(end_btn, "scale:y", 1.0, 0.15).set_trans(Tween.TRANS_BACK)


# ================================================================ layout

func _move(n: Node2D, pos: Vector2, rot: float, scl: float, dur: float = 0.22) -> void:
	if n.has_meta("tw"):
		var old: Tween = n.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var t := n.create_tween().set_parallel(true)
	t.tween_property(n, "position", pos, dur / _speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(n, "rotation", rot, dur / _speed())
	t.tween_property(n, "scale", Vector2(scl, scl), dur / _speed())
	n.set_meta("tw", t)


func _layout_hand(side: int) -> void:
	if side == 0 and _in_mulligan:
		return
	var cards: Array = hand_views[side]
	var n := cards.size()
	if n == 0:
		return
	var s := HAND_SCALE if side == 0 else ENEMY_HAND_SCALE
	var room := minf(V.x - 700.0, 1100.0)
	if side == 0:
		# Keep the hand clear of the mana tray at the bottom right.
		room = minf(room, maxf(640.0, 2.0 * (mana_views[0].position.x - 310.0 - V.x / 2)))
	var spacing := minf(CardView.W * s * 0.92, room / n)
	var hi := cards.find(hover_card) if side == 0 else -1
	for i in n:
		var c: CardView = cards[i]
		if c == drag_card:
			continue
		var k := i - (n - 1) / 2.0
		var x := V.x / 2 + k * spacing
		var y: float
		var rot := k * 0.055
		if side == 0:
			y = V.y - 48 + absf(k) * absf(k) * 3.5
		else:
			y = -38 - absf(k) * absf(k) * 2.5
			rot = -rot + PI
		c.z_index = i
		c.auto_tilt = false
		c.look = i == hi
		if hi != -1:
			if i == hi:
				c.z_index = 100
				# Lifted clear of the screen edge and a bit larger, so the whole card reads.
				c.home = Vector2(x, V.y - CardView.H * HOVER_SCALE / 2 - 24)
				_move(c, c.home, 0.0, HOVER_SCALE, 0.12)
				continue
			x += 70.0 * signf(i - hi)
		c.home = Vector2(x, y)
		c.home_rot = rot
		c.home_scale = s
		_move(c, c.home, rot, s, 0.25)


func _board_slots(side: int, count: int, gap: int = -1) -> Array[float]:
	var n := count + (1 if gap != -1 else 0)
	var step := MinionView.W + MINION_GAP
	var out: Array[float] = []
	for i in n:
		out.append(V.x / 2 + (i - (n - 1) / 2.0) * step)
	if gap != -1:
		out.remove_at(gap)
	return out


func _layout_board(side: int, fresh: Node2D = null) -> void:
	var views: Array = board_views[side]
	var xs := _board_slots(side, views.size(), _gap_index if side == 0 else -1)
	for i in views.size():
		var m: MinionView = views[i]
		m.home = Vector2(xs[i], _board_y(side))
		if m == fresh or m.busy:
			continue
		_move(m, m.home, 0.0, 1.0, 0.25)


func _drop_index(x: float) -> int:
	var views: Array = board_views[0]
	for i in views.size():
		if x < views[i].home.x:
			return i
	return views.size()


# ================================================================ highlights

func _my_turn() -> bool:
	return not over and not autoplay and st.current == 0 and queue.is_empty() and not playing and not st.in_mulligan()


func _refresh_highlights() -> void:
	var mine := _my_turn()
	var any := false
	for c in hand_views[0]:
		c.playable = mine and st.can_play(0, c.uid)
		any = any or c.playable
	for m in board_views[0]:
		var u = st.units.get(m.uid)
		m.can_attack = mine and u != null and st.can_attack(u)
		any = any or m.can_attack
	for m in board_views[1]:
		m.can_attack = false
	if heroes[0]:
		heroes[0].power_ready = mine and st.can_use_power(0)
		any = any or heroes[0].power_ready
	_end_glow.set_on(mine and not any)
	if mine:
		_set_mana(0, st.sides[0].mana, st.sides[0].max_mana)


func _set_targets(uids: Array) -> void:
	for uid in unit_views:
		var v = unit_views[uid]
		var on := uids.has(uid)
		if v is MinionView:
			v.targetable = on
		elif v is HeroView:
			v.set_targeted(on)


func _clear_targets() -> void:
	_set_targets([])
	_highlight_dirty = true


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p := _to_world(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_pressed = true
			_press_pos = p
			_press_time = Time.get_ticks_msec() / 1000.0
			_on_press(p)
		else:
			_pressed = false
			_on_release(p)
	elif event is InputEventMouseMotion:
		_on_motion(_to_world(event.position))


func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _pick_hand(p: Vector2) -> CardView:
	var best: CardView = null
	for c in hand_views[0]:
		if c.contains_point(p) and (best == null or c.z_index > best.z_index):
			best = c
	return best


func _pick_unit(p: Vector2):
	for side in 2:
		for m in board_views[side]:
			if m.contains_point(p):
				return m
		if heroes[side] != null and heroes[side].contains_point(p):
			return heroes[side]
	return null


func _on_press(p: Vector2) -> void:
	_hide_inspect()
	if _mull_waiting:
		var mc := _pick_hand(p)
		if mc != null:
			_toggle_mulligan(mc)
		return
	if mode in [Mode.AIM_BATTLECRY, Mode.AIM_ATTACK, Mode.AIM_POWER, Mode.AIM_SPELL] and _sticky:
		_finish_aim(p)
		return
	if not _my_turn():
		_board_touch(p)
		return
	var c := _pick_hand(p)
	if c != null:
		mode = Mode.DRAG_CARD
		drag_card = c
		c.dragging = true
		c.z_index = 200
		hover_card = null
		_move(c, p, 0.0, 0.78, 0.08)
		Sfx.play("swish", -12.0, 1.3)
		_layout_hand(0)
		return
	var u = _pick_unit(p)
	if u is MinionView and u.side == 0 and u.can_attack:
		mode = Mode.AIM_ATTACK
		aim_attacker = u.uid
		_start_aim(u.position, st.attack_targets(0))
		return
	if heroes[0] != null and heroes[0].power_contains(p):
		if st.can_use_power(0):
			var tt := BattleState.power_target_type(CardDB.hero(st.sides[0].hero_id))
			if tt == "":
				st.use_power(0)
			else:
				mode = Mode.AIM_POWER
				_start_aim(heroes[0].power.global_position, st.valid_targets(0, tt))
		else:
			_nope(heroes[0].power.global_position, "Already used" if st.sides[0].power_used else "Not enough mana")
		return
	if end_btn.to_local(p).length() < 110 and absf(end_btn.to_local(p).y) < 50:
		_end_turn()
		return
	if u != null:
		_show_inspect(u)
		return
	_board_touch(p)


func _on_motion(p: Vector2) -> void:
	match mode:
		Mode.IDLE:
			if _pressed or _in_mulligan:
				return
			var c := _pick_hand(p) if not over else null
			if c != hover_card:
				hover_card = c
				_layout_hand(0)
				if c != null:
					Sfx.play("tick", -18.0, 1.0)
			var u = _pick_unit(p)
			if u != _hover_unit:
				_hover_unit = u
				_hover_unit_t = 0.0
				_hide_inspect()
		Mode.DRAG_CARD:
			var card := CardDB.card(drag_card.card_id)
			var above := p.y < V.y * PLAY_LINE
			# Over the hand the card is shown full size above the finger so it can be read on a phone.
			var target := p if above else p + Vector2(0, -CardView.H * 0.45)
			drag_card.position = drag_card.position.lerp(target, 0.6)
			var want := 0.72 if above else 1.0
			drag_card.scale = drag_card.scale.lerp(Vector2(want, want), 0.25)
			if card.type == "minion":
				var gi := _drop_index(p.x) if above and board_views[0].size() < BattleState.MAX_BOARD else -1
				if gi != _gap_index:
					_gap_index = gi
					_layout_board(0)
			elif above and BattleState.target_type(card) != "" and st.can_play(0, drag_card.uid):
				# A targeted spell turns into an arrow once it leaves the hand.
				mode = Mode.AIM_SPELL
				aim_card_uid = drag_card.uid
				drag_card.dragging = false
				_move(drag_card, Vector2(V.x / 2 - 380, V.y * 0.47), 0.0, 0.8, 0.15)
				drag_card.selected = true
				_start_aim(Vector2(V.x / 2 - 380, V.y * 0.47), st.valid_targets(0, BattleState.target_type(card)))
		Mode.AIM_SPELL, Mode.AIM_BATTLECRY, Mode.AIM_ATTACK, Mode.AIM_POWER:
			arrow.to = p
			var u = _pick_unit(p)
			arrow.valid = u != null and arrow.get_meta("targets", []).has(u.uid)


func _on_release(p: Vector2) -> void:
	match mode:
		Mode.DRAG_CARD:
			var c := drag_card
			c.dragging = false
			var card := CardDB.card(c.card_id)
			var above := p.y < V.y * PLAY_LINE
			if not above:
				_return_card()
				return
			if not st.can_play(0, c.uid):
				_nope(c.position, "Not enough mana" if int(card.cost) > st.sides[0].mana else "Can't play that now")
				_return_card()
				return
			if card.type == "minion":
				var idx: int = _gap_index if _gap_index != -1 else board_views[0].size()
				var tt := BattleState.target_type(card)
				var valid: Array = st.valid_targets(0, tt) if tt != "" else []
				if tt != "" and not valid.is_empty():
					# Park the card in its slot and aim the battlecry from there.
					mode = Mode.AIM_BATTLECRY
					aim_card_uid = c.uid
					aim_index = idx
					var xs := _board_slots(0, board_views[0].size(), idx)
					var slot := Vector2(V.x / 2 + (idx - board_views[0].size() / 2.0) * (MinionView.W + MINION_GAP), _board_y(0))
					if idx < board_views[0].size():
						slot.x = xs[idx] - (MinionView.W + MINION_GAP)
					elif not xs.is_empty():
						slot.x = xs.back() + (MinionView.W + MINION_GAP)
					else:
						slot.x = V.x / 2
					_move(c, slot, 0.0, 0.5, 0.12)
					c.selected = true
					_start_aim(slot, valid)
					_sticky = true ## the finger is already up: the next tap picks the target
					return
				drag_card = null
				mode = Mode.IDLE
				st.play_card(0, c.uid, -1, idx)
			else:
				drag_card = null
				mode = Mode.IDLE
				st.play_card(0, c.uid)
		Mode.AIM_SPELL, Mode.AIM_BATTLECRY, Mode.AIM_ATTACK, Mode.AIM_POWER:
			if _press_pos.distance_to(p) < 24.0 and not _sticky:
				_sticky = true ## tap-tap aiming for touch screens
				return
			_finish_aim(p)
		_:
			var held := Time.get_ticks_msec() / 1000.0 - _press_time
			if held > 0.45 and _press_pos.distance_to(p) < 20.0:
				pass


## Fake depth: the table layers slide a few pixels against the pointer (a slow drift on touch screens), so the hand
## and the UI read as nearer than the board. Frozen while aiming so the arrow keeps its anchor.
func _tick_parallax(delta: float) -> void:
	if arrow.visible or drag_card != null:
		return
	var aim := Vector2.ZERO
	if DisplayServer.is_touchscreen_available():
		_parallax_t += delta
		aim = Vector2(sin(_parallax_t * 0.21), cos(_parallax_t * 0.17)) * 0.5
	else:
		aim = ((get_viewport().get_mouse_position() - V / 2) / (V / 2)).clamp(-Vector2.ONE, Vector2.ONE)
	_parallax = _parallax.lerp(-aim * 9.0, minf(1.0, delta * 2.5))
	bg_layer.position = _parallax
	board_layer.position = _parallax
	fx_layer.position = _parallax


func _start_aim(from: Vector2, targets: Array) -> void:
	from += board_layer.position
	arrow.from = from
	arrow.to = from
	arrow.valid = false
	arrow.set_meta("targets", targets)
	arrow.visible = true
	_sticky = false
	_set_targets(targets)
	if aim_attacker != -1 and unit_views.has(aim_attacker):
		_pop(unit_views[aim_attacker], 1.08)


func _finish_aim(p: Vector2) -> void:
	var u = _pick_unit(p)
	var targets: Array = arrow.get_meta("targets", [])
	var target: int = u.uid if u != null and targets.has(u.uid) else -1
	var m := mode
	var card_uid := aim_card_uid
	var attacker := aim_attacker
	var index := aim_index
	_end_aim()
	if target == -1:
		if m == Mode.AIM_SPELL or m == Mode.AIM_BATTLECRY:
			_return_card()
		return
	match m:
		Mode.AIM_ATTACK:
			st.attack(0, attacker, target)
		Mode.AIM_POWER:
			st.use_power(0, target)
		Mode.AIM_SPELL:
			drag_card = null
			st.play_card(0, card_uid, target)
		Mode.AIM_BATTLECRY:
			drag_card = null
			_gap_index = -1
			st.play_card(0, card_uid, target, index)


func _end_aim() -> void:
	arrow.visible = false
	_sticky = false
	aim_attacker = -1
	aim_card_uid = -1
	if mode != Mode.DRAG_CARD:
		mode = Mode.IDLE
	_clear_targets()


func _return_card() -> void:
	if drag_card != null:
		drag_card.dragging = false
		drag_card.selected = false
	drag_card = null
	mode = Mode.IDLE
	_gap_index = -1
	_layout_board(0)
	_layout_hand(0)
	_highlight_dirty = true


func _cancel() -> void:
	if mode == Mode.DRAG_CARD or mode == Mode.AIM_SPELL or mode == Mode.AIM_BATTLECRY:
		_end_aim()
		_return_card()
	elif mode != Mode.IDLE:
		_end_aim()
	_hide_inspect()


func _end_turn() -> void:
	if not _my_turn():
		return
	_cancel()
	Sfx.play("ui_confirm", -6.0)
	_pop(end_btn, 0.9)
	st.end_turn()


func _nope(pos: Vector2, text: String) -> void:
	Fx.number(fx_layer, pos + Vector2(0, -80), text, Color(1.0, 0.85, 0.7), false)
	Sfx.play("ui_back", -8.0)


## Touching the empty board: ripples in the river, scattered wisps, a puff of ash on the shore.
func _board_touch(p: Vector2) -> void:
	for w in _wisps:
		var d := w.position - p
		if d.length() < 260.0:
			w.set_meta("flee", w.get_meta("flee") + d.normalized() * (260.0 - d.length()) * 1.4)
	if props != null and props.touch(p):
		return
	if absf(p.y - _river_y()) < 60.0 * ky:
		add_ripple(p, 1.0)
		Sfx.play("splash", -12.0)
	else:
		Fx.dust(fx_layer, p, 60.0, 14)
		Fx.burst(fx_layer, p, UI.EMBER, 10, 120.0, 0.8, 7.0, -40.0)


func add_ripple(p: Vector2, strength: float) -> void:
	var ripples := _ripples
	var uv := Vector2((p.x - river.position.x) / river.size.x, (p.y - river.position.y) / river.size.y)
	ripples[_ripple_i] = Vector4(uv.x, uv.y, Time.get_ticks_msec() / 1000.0, strength)
	_ripple_i = (_ripple_i + 1) % 4
	_river_mat.set_shader_parameter("ripples", ripples)


# ================================================================ inspect

func _show_inspect(u) -> void:
	_hide_inspect()
	var id := ""
	if u is MinionView:
		id = u.card_id
	elif u is HeroView:
		_show_hero_tip(u)
		return
	else:
		return
	inspect = CardView.new().setup(id, -1, true)
	inspect.z_index = 300
	inspect.sway = true
	var left: bool = u.position.x > V.x / 2
	inspect.position = Vector2(u.position.x + (-260.0 if left else 260.0), clampf(u.position.y, 200, V.y - 200))
	inspect.scale = Vector2(0.6, 0.6)
	fx_layer.add_child(inspect)
	inspect.create_tween().tween_property(inspect, "scale", Vector2(0.95, 0.95), 0.12)
	var kws: Array = CardDB.card(id).get("keywords", [])
	for e in CardDB.card(id).get("effects", []):
		if e.get("on", "") in ["death", "play"] and CardDB.card(id).get("type") == "minion":
			kws.append(e.on)
	for k in kws:
		if UI.KEYWORD_HELP.has(k):
			_add_tip(UI.KEYWORD_HELP[k][0], UI.KEYWORD_HELP[k][1])
	_tips.position = Vector2(inspect.position.x + (150.0 if not left else -470.0), inspect.position.y - 160)


func _show_hero_tip(h: HeroView) -> void:
	var def := CardDB.hero(h.hero_id)
	_add_tip(def.get("name", ""), "Hero power: %s (%d mana). %s" % [def.power.name, def.power.cost, def.power.text])
	_tips.position = Vector2(h.position.x + 160, h.position.y - 60)


func _add_tip(title: String, text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.frame_box("tooltip_frame_filled", 40, 22,
		UI.box(Color(0.08, 0.05, 0.04, 0.94), UI.GOLD_DARK, 2, 8)))
	p.custom_minimum_size = Vector2(320, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := UI.label(title, 24, "title", UI.GOLD)
	v.add_child(t)
	var b := UI.label(text, 22, "body", UI.BONE)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(300, 0)
	v.add_child(b)
	_tips.add_child(p)


func _hide_inspect() -> void:
	if inspect != null:
		inspect.queue_free()
		inspect = null
	for c in _tips.get_children():
		c.queue_free()


# ================================================================ pause / debug

func _open_pause() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = V
	ui.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = V
	box.add_theme_constant_override("separation", 22)
	dim.add_child(box)
	var title := UI.label("Paused", 80, "title", UI.GOLD, 10, Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for entry in [["Resume", dim.queue_free],
			["Options", func(): dim.add_child(OptionsPanel.new())],
			["Concede", _concede]]:
		var b := UI.button(entry[0], 380)
		b.pressed.connect(entry[1])
		var c := CenterContainer.new()
		c.add_child(b)
		box.add_child(c)


func _concede() -> void:
	over = true
	Game.record_result(1)
	Game.go(Game.MENU)


func _take_shot() -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join("shot_%02d.png" % _shot_i))
	if over:
		_shots_after_over += 1
	_shot_i += 1
	if _shot_i >= 40 or (over and _shots_after_over >= 2):
		get_tree().quit()
