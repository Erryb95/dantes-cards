extends Node2D
## The battle screen: builds the arena, replays BattleState events as animations, and turns pointer / touch
## input into actions. The rules live in BattleState; this script never changes game values itself.
##
## Debug: `-- --autoplay` lets the AI play both sides, `-- --shots=<dir>` saves screenshots and quits,
## `-- --arena=<id>` forces an arena (one whose board isn't painted yet shows on the Acheron board as a stand-in).

const HAND_SCALE := 0.62
const ENEMY_HAND_SCALE := 0.42
const HOVER_SCALE := 1.12
const HOVER_SPREAD := 70.0 ## hand cards beside a hovered one move this far aside
const END_OVAL := Vector2(236, 150) ## the end-turn seal's visible oval, px
const MINION_GAP := 40.0
const PLAY_LINE := 0.70 ## releasing a dragged card above this fraction of the screen height plays it
const INSPECT_SCALE := 0.95 ## the enlarged card shown beside a hovered minion
const TIP_W := 400.0 ## a keyword tip plate's width (UI.tip_plate: a 320 px text column inside the frame)
const TIP_GAP := 8

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
var _shot_max := 40 ## `--shot-count=N`
var _poke_at := -1.0 ## `--poke-toys=<s>`: tap every arena toy and the divider after s seconds (to see the reactions)
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
var _copy_start := {} ## where the next drawn card flies in from (a copy or a stolen card): pos, rot, scl
var _stolen: Array[Dictionary] = [] ## where each stolen card was handed over; its copy event picks it up there
var _morph := {} ## the minion being transformed (uid, side, view): it keeps its slot for its new form
var _ruse_cast := false ## the Ruse flash was already shown on the spell being cast

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
var props: ArenaProps ## the arena's living layer: divider VFX, ambient particles, tappable toys
var arena_scene: ArenaScene ## editor-placed sockets (scenes/arenas/*.tscn)
var arena: Dictionary ## this match's data/arenas.json entry
var _arena_standin := false ## forced arena without its board: shown on the Acheron board
var _river_h := 104.0 ## height of the water band (the Acheron river, or Limbo's thin stream)
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
var _tips: GridContainer ## the inspect card's keyword tips (one column, or two when one would not fit)
var _hand_tips: GridContainer ## keyword tips beside the lifted (hovered or held) hand card
var _hand_tips_card: CardView
var _pointer := Vector2.ZERO
var _coach: Coach
var lesson: Dictionary = {} ## the lesson this battle is (Game.lesson, data/lessons.json), {} in a real match
var guide: LessonGuide ## Virgil, in a lesson: his lines, the pointer and the gate on the player's actions
var _pause_dim: Control ## the open pause menu (no coach tips while it is up)
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
var _ai_task := -1 ## WorkerThreadPool task of the AI thinking, -1 when idle
var _ai_move: Dictionary = {}
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
		elif a.begins_with("--shot-count="):
			_shot_max = int(a.substr(13))
		elif a.begins_with("--poke-toys="):
			_poke_at = float(a.substr(12))
	V = get_viewport_rect().size
	ky = minf(V.y / 1080.0, V.x / 1920.0) # the 16:9 layout fits inside any screen (letterboxed on 16:10)
	if Game.lesson != "":
		lesson = Lessons.get_lesson(Game.lesson)
	_resolve_arena()
	_build_scene()
	get_viewport().size_changed.connect(_on_resize)
	Sfx.play_music(arena.get("music", "music_combat"))
	Sfx.play_ambience(arena.get("ambience", ""), -16.0)
	st = BattleState.new()
	st.event.connect(func(ev): queue.append(ev))
	ai = BattleAI.new(1, BattleAI.Level.HARD if autoplay else Settings.difficulty as BattleAI.Level)
	ai_self = BattleAI.new(0)
	# A lesson opens with its own title and what it teaches, in place of the arena's name and line.
	_intro(arena if lesson.is_empty() else {"name": lesson.title, "intro": lesson.learn,
		"circle": "Lesson %d of %d" % [Lessons.index_of(lesson.id) + 1, Lessons.all().size()]})
	if lesson.is_empty():
		st.start(Game.player_cards, Game.player_hero, Game.enemy_cards, Game.enemy_hero, 0, true, -1)
	else:
		# A lesson: its own dealing, opponent and opening (see Lessons.configure).
		Lessons.configure(st, lesson)
		ai = Lessons.make_ai(lesson)
		st.start(Game.player_cards, Game.player_hero, Game.enemy_cards, Game.enemy_hero, 0,
			bool(lesson.get("mulligan", false)), int(lesson.get("first", 0)))


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

## Settles this match's arena. One whose painted board is missing never breaks the board: the draw skips it, and
## when it is forced (debug) it borrows the Acheron's board and sockets, tinted, with its own living details.
func _resolve_arena() -> void:
	var id := Game.begin_arena()
	arena = CardDB.arena(id).duplicate(true)
	if CardDB.arena_ready(id) or Game.arena_forced and CardDB.arena_painted(id):
		return
	if arena.is_empty() or not Game.arena_forced:
		Game.arena_id = "acheron"
		arena = CardDB.arena("acheron").duplicate(true)
		return
	push_warning("Arena '%s' has no painted board yet: showing it on the Acheron board." % id)
	_arena_standin = true
	arena["board"] = CardDB.arena("acheron").get("board", "")
	arena["scene"] = "res://scenes/arenas/standard.tscn"
	arena.erase("mist")
	arena.erase("frame")


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

	var back := Sprite2D.new()
	back.name = "Backdrop"
	var path := "res://assets/arenas/" + str(arena.get("backdrop", ""))
	var board_path := "res://assets/arenas/" + str(arena.get("board", ""))
	_painted_board = arena.has("board") and ResourceLoader.exists(board_path)
	if arena.has("backdrop") and ResourceLoader.exists(path):
		back.texture = load(path)
	elif _painted_board:
		# No landscape: the board itself, scaled to cover and darkened, fills the side bands of wide screens.
		back.texture = load(board_path)
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
	back.light_mask = ArenaProps.LIGHT_MASK
	# A painted board (ARENA_BRIEF.md) replaces the landscape: same coordinates as the layout, 2560x1440.
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
		board.light_mask = ArenaProps.LIGHT_MASK
		if _arena_standin:
			var c: Array = arena.get("tint", {}).get("standin", [0.7, 0.7, 0.75])
			board.modulate = Color(c[0], c[1], c[2])
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
	river.light_mask = ArenaProps.LIGHT_MASK
	bg_layer.add_child(river)
	# The divider between the two halves: the Acheron's water (also Limbo's thin stream, retinted), or a VFX band
	# drawn by the arena's props (wind, ember crack, frost crack).
	var div: Dictionary = arena.get("divider", {})
	var div_kind := str(div.get("kind", "river"))
	river.visible = div_kind == "river" or div_kind == "stream"
	_river_h = float(div.get("height", 104.0)) if river.visible else 104.0
	if div.has("deep"):
		_river_mat.set_shader_parameter("deep", Color(div.deep[0], div.deep[1], div.deep[2], div.deep[3]))
	if div.has("glint"):
		_river_mat.set_shader_parameter("glint", Color(div.glint[0], div.glint[1], div.glint[2]))

	if _painted_board:
		river.modulate.a = float(div.get("alpha", 0.45))
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

	var scene_path := str(arena.get("scene", "res://scenes/arenas/standard.tscn"))
	if scene_path != "" and ResourceLoader.exists(scene_path):
		arena_scene = load(scene_path).instantiate()
		bg_layer.add_child(arena_scene)
	props = ArenaProps.make(arena)
	props.placeholders = _arena_standin
	props.setup(self, arena)
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

	props.dress()

	_build_end_button()
	for i in 2:
		mana_views[i] = _build_mana(i)
		_set_mana(i, 0, 0)
		deck_views[i] = _build_deck(i)
		_set_deck_count(i, (Game.player_cards if i == 0 else Game.enemy_cards).size())

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
	_tips = _tip_grid()
	_hand_tips = _tip_grid()
	# The coach floats above everything, cards in hand included.
	var coach_layer := CanvasLayer.new()
	coach_layer.layer = 50
	add_child(coach_layer)
	_coach = Coach.new()
	coach_layer.add_child(_coach)
	if not lesson.is_empty():
		# Virgil above the coach. His scripted lessons need no coach; a lesson with "hints" (the trial) shows every
		# coach tip and keyword tip once in the match, seen before or not.
		var guide_layer := CanvasLayer.new()
		guide_layer.layer = 55
		add_child(guide_layer)
		guide = LessonGuide.new().setup(self, lesson)
		guide_layer.add_child(guide)
		if lesson.get("hints", false):
			_coach.lesson_mode()
		else:
			_coach.enabled = false

	var menu := UI.button("Menu", 150, 56)
	menu.add_theme_font_size_override("font_size", 24)
	menu.name = "MenuButton"
	menu.pressed.connect(_open_pause)
	ui.add_child(menu)
	_layout_static()


func _tip_grid() -> GridContainer:
	var g := GridContainer.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", TIP_GAP)
	g.add_theme_constant_override("v_separation", TIP_GAP)
	ui.add_child(g)
	return g


func _build_end_button() -> void:
	end_btn = Node2D.new()
	board_layer.add_child(end_btn)
	# Lights up (gold fire) when nothing is left to play. The aura hugs the seal's visible oval (END_OVAL): the
	# painting has transparent margins left and right, so the sprite is wider than the oval it shows.
	_end_glow = Aura.make(END_OVAL, true, 30.0)
	_end_glow.colors(Aura.SELECTED)
	end_btn.add_child(_end_glow)
	_end_disc = Shapes.make(Shapes.Kind.ELLIPSE, END_OVAL, Color(0.38, 0.1, 0.05), UI.GOLD, 5.0)
	_end_disc.use_parent_material = false
	end_btn.add_child(_end_disc)
	if UiSkin.has("end_turn_seal"):
		_end_disc.visible = false
		var tex := UiSkin.tex("end_turn_seal")
		var vis := _opaque_rect(tex)
		# Scale the painting so its opaque part is exactly END_OVAL, centred on the button.
		var k := END_OVAL / vis.size
		_end_seal = Sprite2D.new()
		_end_seal.texture = tex
		_end_seal.scale = k
		_end_seal.offset = tex.get_size() / 2 - vis.get_center()
		_end_seal.use_parent_material = false
		end_btn.add_child(_end_seal)
	# Engraved into the seal's smooth inner oval (about 56% of its width), not printed over the rope rim.
	_end_label = UI.engraved(UI.label("END TURN", 28, "title"))
	_end_label.size = Vector2(END_OVAL.x * 0.56, END_OVAL.y * 0.5)
	_end_label.position = -_end_label.size / 2
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
	var l := UI.raised(UI.label("0/0", 34, "title", Color(0.75, 0.88, 1.0), 7, Color(0, 0.02, 0.08)))
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
	# The real deck size from the start (the arena intro plays before the deal reports it).
	var l := UI.label(str((Game.player_cards if side == 0 else Game.enemy_cards).size()), 30, "title", UI.BONE, 7,
		Color.BLACK)
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
		bed.size = Vector2(bed_w, 176 * ky)
		bed.position = Vector2(V.x / 2 - bed_w / 2, _board_y(1 - i) - 88 * ky)
	river.position = Vector2(0, _river_y() - _river_h / 2 * ky)
	river.size = Vector2(V.x, _river_h * ky)
	_river_mat.set_shader_parameter("aspect", V.x / (_river_h * ky))
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
			for m in arena_scene.get_node("Sockets").get_children():
				if str(m.name).begins_with("Prop"):
					anchors[str(m.name)] = _sock(str(m.name), Vector2.ZERO)
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
	return (576.0 if side == 0 else 368.0) * ky + _oy() # 104 px each side of the divider (472)


func _river_y() -> float:
	return 472.0 * ky + _oy()


func _hero_pos(side: int) -> Vector2:
	return Vector2(V.x / 2, (801.0 if side == 0 else 143.0) * ky + _oy()) # mirrored about the divider (472)


## Top of the 16:9 layout: screens taller than 16:9 (tablets) centre it vertically.
func _oy() -> float:
	return (V.y - 1080.0 * ky) / 2.0


func _intro(p_arena: Dictionary) -> void:
	# The arena's name as a big title; its circle and intro line on an engraved plaque under it.
	var title := UI.banner(p_arena.get("name", ""), 56, UI.GOLD, 0.0, 90.0)
	title.position = Vector2((V.x - title.size.x) / 2, V.y * 0.36 - 8)
	var holder := CenterContainer.new()
	holder.size = Vector2(V.x, 0)
	holder.position = Vector2(0, V.y * 0.36 + 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plaque := UI.plaque(40, 16)
	holder.add_child(plaque)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(pv)
	var room := minf(1100.0, V.x - 240.0)
	var circle_name := str(p_arena.get("circle", "")).to_upper()
	if circle_name != "":
		var circle := UI.label(circle_name, 24, "title", Color(0.92, 0.76, 0.5), 3, Color.BLACK)
		circle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(circle)
	var sub := UI.label(p_arena.get("intro", ""), 28, "italic", UI.BONE, 3, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# One line when it fits, else wrapped inside the plaque.
	sub.custom_minimum_size = Vector2(minf(room,
		UI.font("italic").get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 8.0), 0)
	pv.add_child(sub)
	for l in [title, holder]:
		l.modulate.a = 0.0
		ui.add_child(l)
	for l in [title, holder]:
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
	_tick_hand_tips()
	_tick_parallax(delta)
	if _painted_board:
		var mist := bg_layer.get_node_or_null("Board_mist") as Sprite2D
		if mist != null:
			var t := Time.get_ticks_msec() / 1000.0
			mist.position.x = V.x / 2 + sin(t * 0.07) * 120.0
			mist.modulate.a = 0.3 + 0.08 * sin(t * 0.31)
	if _poke_at >= 0.0:
		_poke_at -= delta
		if _poke_at < 0.0:
			for p in props.toy_points():
				_board_touch(p)
	if shots_dir != "":
		_shot_t += delta
		if _shot_t > _shot_every:
			_shot_t = 0.0
			_take_shot()
	if playing:
		return
	# The pause menu holds the match: the animation already under way ends, but no new event plays and the enemy
	# does not move until it closes (it used to play on, and could even win, under the menu).
	if _paused():
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


## The AI searches on a worker thread (it only reads the battle and plays on copies), so the board keeps animating
## while it thinks; the chosen move is applied here on the main thread once the search is done.
func _ai_step() -> void:
	if _ai_task == -1:
		var brain := ai if st.current == 1 else ai_self
		_ai_task = WorkerThreadPool.add_task(func(): _ai_move = brain.next_action(st))
		return
	if not WorkerThreadPool.is_task_completed(_ai_task):
		return
	WorkerThreadPool.wait_for_task_completion(_ai_task)
	_ai_task = -1
	var act := _ai_move
	if act.do == "end" or not BattleAI.apply(st, st.current, act):
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
			_last_aoe = ""
			for w in _stolen: # never left behind (each is normally picked up by its copy event)
				if is_instance_valid(w.node):
					w.node.queue_free()
			_stolen.clear()
			_set_end_button(ev.side)
			if guide != null:
				guide.on_turn(ev.side)
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
		"steal":
			await _on_steal(ev)
		"copy":
			_on_copy(ev)
		"ruse":
			if ev.uid == -1 and _ruse_cast:
				_ruse_cast = false # already shown on the card while it was cast
			else:
				await _show_ruse(unit_views.get(ev.uid, heroes[ev.side]))
		"transform":
			await _on_transform(ev)
		"burn":
			var c := CardView.new().setup(ev.id, -1, true)
			# An overdraw leaves the deck pile; a card made for a full hand (an added card, a copy) appears at the hand.
			c.position = deck_views[ev.side].position if not ev.get("made", false) else \
				Vector2(V.x / 2, V.y - 120.0 if ev.side == 0 else 120.0)
			c.scale = Vector2(0.4, 0.4)
			hand_layer.add_child(c)
			_set_deck_count(ev.side, ev.deck)
			var t := c.create_tween()
			t.tween_property(c, "position", Vector2(V.x / 2 + 300, V.y / 2), 0.4)
			t.parallel().tween_property(c, "scale", Vector2(0.8, 0.8), 0.4)
			await t.finished
			Sfx.play("thunder", -16.0, 1.4)
			Vfx.keyword(self, c, "burn")
			await c.burn_away(0.8)
		"fatigue":
			var h: HeroView = heroes[ev.side]
			# Left of the portrait: above it the plaque sat on the row of minions and hid their numbers.
			_toast(h.position + Vector2(-340, 0), "Fatigue: %d damage" % ev.amount, Color(0.85, 0.75, 1.0))
			await _wait(0.4)
		"play":
			_last_aoe = ""
			await _on_play(ev)
		"summon":
			await _on_summon(ev)
		"attack":
			_last_aoe = ""
			await _on_attack(ev)
		"damage":
			_on_damage(ev)
			await _wait(0.12)
		"heal":
			var v = unit_views.get(ev.uid)
			if v != null:
				Fx.number(fx_layer, v.position, "+%d" % ev.amount, UI.HEAL, false)
				if not Vfx.heal(self, v, ev.get("src", "")):
					Fx.burst(fx_layer, v.position, Color(0.4, 1.0, 0.4), 20, 160.0, 0.8, 22.0, -60.0, 180.0, "k_star_01")
				_set_unit_hp(v, ev.hp)
				Sfx.play("chime", -12.0, 1.3)
			await _wait(0.2)
		"armor":
			var h: HeroView = unit_views.get(ev.uid)
			h.set_armor(ev.armor)
			if not Vfx.armor(self, h, ev.get("src", "")):
				Fx.burst(fx_layer, h.position + Vector2(h.W / 2, -60), Color(0.75, 0.8, 0.9), 24, 200.0, 0.6, 10.0)
			Sfx.play("slam", -12.0, 1.5)
			Sfx.play("metal", -6.0)
			await _wait(0.25)
		"buff":
			var m = unit_views.get(ev.uid)
			if m is MinionView:
				m.apply({"attack": ev.attack, "health": ev.health, "max_health": ev.max_health, "keywords": ev.keywords})
				if not Vfx.buff(self, m, ev.get("src", "")):
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
				Vfx.keyword(self, m, "ward")
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
				Vfx.keyword(self, m, "venom")
				Fx.burst(fx_layer, m.position, Color(0.35, 1.0, 0.25), 30, 200.0, 0.7, 11.0, 100.0)
				m.flash(Color(0.3, 1.0, 0.2))
		"death":
			await _on_death(ev)
		"rebirth":
			Vfx.keyword(self, unit_views.get(ev.uid), "rebirth")
			await _wait(0.2)
		"wrath":
			# Wrath wakes on a damaged minion (ember flare, "Wrath" plaque, its Attack jumps) or cools when it is healed
			# to full or silenced.
			var wm = unit_views.get(ev.uid)
			if wm is MinionView:
				wm.apply({"attack": ev.attack})
				wm.set_raging(ev.on)
				if ev.on:
					Vfx.keyword(self, wm, "wrath")
					_toast(wm.position + Vector2(0, -(MinionView.H / 2 + 24)), "Wrath", UI.EMBER)
					_pop(wm, 1.14)
				else:
					Fx.smoke(fx_layer, wm.position, Color(0.3, 0.25, 0.22, 0.5), 160.0, 4)
				await _wait(0.25 if ev.on else 0.1)
		"frenzy":
			var fm = unit_views.get(ev.uid)
			if fm is MinionView:
				Vfx.keyword(self, fm, "frenzy")
				_toast(fm.position + Vector2(0, -(MinionView.H / 2 + 24)), "Frenzy", Color(1.0, 0.35, 0.25))
				_pop(fm, 1.18)
				shake(4.0)
			await _wait(0.3)
		"fight":
			await _on_fight(ev)
		"bounce":
			await _on_bounce(ev)
		"projectile":
			var a = unit_views.get(ev.from)
			var b = unit_views.get(ev.to)
			if a != null and b != null:
				await Vfx.travel(self, a, b, ev.id, ev.kind)
		"aoe":
			await _on_aoe(ev)
		"power":
			_last_aoe = ""
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
			_last_aoe = ""
			if tm != null:
				_pop(tm, 1.15)
				Vfx.keyword(self, tm, "trigger")
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
	# From the deck, or from wherever a copied or stolen card was taken (see _on_copy).
	var from := _copy_start
	_copy_start = {}
	if is_instance_valid(from.get("node")):
		from.node.queue_free() # the stolen card waiting at the handoff: the drawn copy takes its place
	c.position = from.get("pos", deck_views[side].position)
	c.rotation = from.get("rot", PI / 2)
	c.scale = Vector2.ONE * float(from.get("scl", 0.36))
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
		f.tween_callback(Vfx.draw_glow.bind(self, mid))
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
	# The heading on the charred banner.
	var title := UI.banner("Your starting hand", 54, UI.GOLD, 0.0, 80.0)
	title.position = Vector2((V.x - title.size.x) / 2, V.y * 0.12)
	_mull_ui.add_child(title)
	var order := "You go first." if _first_side == 0 else "You go second, with an extra card and Charon's Obol."
	# The instructions on an engraved plaque under the title.
	var sub_row := CenterContainer.new()
	sub_row.size = Vector2(V.x, 64)
	sub_row.position = Vector2(0, V.y * 0.12 + 84)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# "Click" with a mouse, "Tap" on a touch screen.
	var how := "   %s the cards you want to replace." % UI.tap_word()
	sub_row.add_child(UI.plaque_label(order + how, 28, "italic", UI.BONE, minf(1300.0, V.x - 160.0), 36, 10))
	_mull_ui.add_child(sub_row)
	var ok := UI.button("Confirm", 340, 84)
	ok.position = Vector2(V.x / 2 - 170, V.y * 0.78)
	ok.pressed.connect(_confirm_mulligan)
	_mull_ui.add_child(ok)
	if guide != null:
		guide.on_mulligan()
	await mulligan_confirmed


func _toggle_mulligan(c: CardView) -> void:
	if _mull_marks.has(c.uid):
		_mull_marks[c.uid].queue_free()
		_mull_marks.erase(c.uid)
		c.modulate = Color.WHITE
	else:
		# A red sash across the card with the word on it.
		var x := UI.ribbon("Replace", CardView.W + 70, 38)
		x.pivot_offset = x.size / 2
		x.position.y -= 85.0 # across the painting, clear of the name ribbon and the rules text
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
	_did({"act": "mulligan"})
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
		if _ruse_follows(side):
			_ruse_cast = true
			_show_ruse(c)
		await Vfx.cast(self, c, ev.id, side)
		c.burn_away(0.9 / _speed())
		await _wait(0.25)


func _on_summon(ev: Dictionary) -> void:
	var side: int = ev.side
	var snap: Dictionary = ev.unit
	var m := MinionView.new().setup(snap)
	board_layer.add_child(m)
	unit_views[m.uid] = m
	var old: MinionView = _take_morph(side)
	if old != null:
		# A transformed minion's new form takes its slot (see _on_transform).
		board_views[side][board_views[side].find(old)] = m
		old.queue_free()
		_layout_board(side, m)
		await _morph_in(m)
		return
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
	var cost := int(CardDB.card(m.card_id).get("cost", 0))
	var tint: Color = UI.RARITY.get(rarity, UI.EMBER) if rarity != "common" else UI.EMBER
	Fx.gather(fx_layer, m.home, Vfx.summon_tint(m.card_id), 150.0 + cost * 8.0, 0.22 / _speed(), 16 + cost * 2)
	var drop := m.create_tween().set_parallel(true)
	drop.tween_property(m, "position", m.home, 0.2 / _speed()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop.tween_property(m, "scale", Vector2.ONE, 0.2 / _speed()).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop.tween_property(m, "modulate:a", 1.0, 0.1 / _speed())
	await drop.finished
	m.z_index = 0
	Fx.dust(fx_layer, m.position + Vector2(0, MinionView.H * 0.42), MinionView.W * 1.3, 18, Color(0.3, 0.26, 0.22, 0.4))
	# The slam cracks the stone under the minion; the magic circle is kept for legendaries (below).
	# On the table layer, so the cracks run under the minion and out from beneath it.
	Fx.landing(bg_layer, m.position + Vector2(0, MinionView.H * 0.3), tint, 440.0 + cost * 22.0,
		clampf((cost - 2) / 6.0, 0.0, 1.0))
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
		Vfx.legendary(self, m, snap.id)
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
	Vfx.strike(self, a, b, dir, int(a.attack) if a is MinionView else 2)
	_push(b, dir * 18.0)
	var back: Tween = a.create_tween().set_parallel(true)
	back.tween_property(a, "position", a.home, 0.28 / _speed()).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	back.tween_property(a, "scale", Vector2.ONE, 0.28 / _speed())
	back.chain().tween_callback(_land.bind(a))


## A fight (Wrath class): both minions wind back, rush to meet halfway and clash in a splash of mud; then each falls
## back to its slot. The two "damage" events that follow show the blows.
func _on_fight(ev: Dictionary) -> void:
	var a = unit_views.get(ev.a)
	var b = unit_views.get(ev.b)
	if not (a is MinionView and b is MinionView):
		return
	var dir: Vector2 = (b.position - a.position).normalized()
	var mid: Vector2 = (a.position + b.position) / 2.0
	var k := _speed()
	for m in [a, b]:
		m.busy = true
		m.z_index = 15
	Sfx.play("growl", -10.0, 1.1)
	var t: Tween = a.create_tween().set_parallel(true)
	t.tween_property(a, "scale", Vector2(1.14, 1.14), 0.14 / k).set_trans(Tween.TRANS_QUAD)
	t.tween_property(b, "scale", Vector2(1.14, 1.14), 0.14 / k).set_trans(Tween.TRANS_QUAD)
	t.tween_property(a, "position", a.position - dir * 30.0, 0.14 / k)
	t.tween_property(b, "position", b.position + dir * 30.0, 0.14 / k)
	t.chain().tween_property(a, "position", mid - dir * 62.0, 0.14 / k).set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(b, "position", mid + dir * 62.0, 0.14 / k).set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	Sfx.play("whoosh", -8.0, 0.8)
	await t.finished
	Sfx.play("thud", -2.0, 0.8)
	Sfx.play("clash", -6.0)
	Sfx.play("splash", -10.0, 0.8)
	shake(8.0)
	if maxi(int(a.attack), int(b.attack)) >= 5:
		_hit_stop(0.08)
	Vfx.strike(self, a, b, dir, int(a.attack))
	Vfx.strike(self, b, a, -dir, int(b.attack))
	# The mud flies: a dark spray and dust where they meet.
	Fx.burst(fx_layer, mid, Color(0.32, 0.22, 0.12), 28, 360.0, 0.7, 12.0, 700.0, 70.0, "k_dirt_02")
	Fx.dust(fx_layer, mid + Vector2(0, 40), 220.0, 22, Color(0.28, 0.22, 0.16, 0.5))
	for m in [a, b]:
		var back: Tween = m.create_tween().set_parallel(true)
		back.tween_property(m, "position", m.home, 0.3 / k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		back.tween_property(m, "scale", Vector2.ONE, 0.3 / k)
		back.chain().tween_callback(_land.bind(m))


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
	if _ai_task != -1:
		ai.abort = true
		if ai_self != null:
			ai_self.abort = true
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1


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
	if not Vfx.hurt(self, v, ev.get("src", ""), ev.amount):
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
	if _morph.get("uid", -1) == ev.uid:
		return # transformed, not killed: the swirl already took it and its new form keeps the slot
	board_views[ev.side].erase(m)
	Sfx.play("moan", -14.0, 1.0, 0.12)
	Sfx.play("creature_die", -12.0, 1.1)
	Vfx.death(self, m, m.card_id)
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


## A card stolen from the victim's hand (or off the top of their deck) flies across the river to the thief and waits
## there; the thief's copy then arrives from that point through its copy + draw events (it replaces the waiting card).
func _on_steal(ev: Dictionary) -> void:
	var from: int = ev.from
	var c: CardView = null
	if ev.zone == "hand":
		for v in hand_views[from]:
			if v.uid == ev.uid:
				c = v
		if c == null:
			return
		hand_views[from].erase(c)
		if hover_card == c:
			hover_card = null
		_layout_hand(from)
	else:
		_set_deck_count(from, ev.deck)
		c = CardView.new().setup(ev.id, -1, false)
		c.position = deck_views[from].position
		c.rotation = PI / 2
		c.scale = Vector2(0.36, 0.36)
		hand_layer.add_child(c)
	if c.has_meta("tw"):
		(c.get_meta("tw") as Tween).kill() # the hand layout must not pull it back
	c.z_index = 40
	c.look = false
	Vfx.pilfer(self, c.position)
	var to := _handoff(ev.side)
	to.pos = to.pos + Vector2(-90.0 if ev.side == 0 else 90.0, 0) * _stolen.size()
	var k := _speed()
	var t := c.create_tween()
	t.tween_property(c, "position", c.position + Vector2(0, 60 if from == 1 else -60), 0.12 / k)
	t.tween_property(c, "position", to.pos, 0.38 / k).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(c, "rotation", to.rot, 0.38 / k)
	t.parallel().tween_property(c, "scale", Vector2.ONE * to.scl, 0.38 / k)
	await t.finished
	if c.face_up:
		# Your card turns its back as it goes over to the enemy.
		var f := c.create_tween()
		f.tween_property(c, "scale:x", 0.0, 0.08 / k)
		f.tween_callback(c.set_face_up.bind(false))
		f.tween_property(c, "scale:x", to.scl, 0.08 / k)
		await f.finished
	# It waits there (a second stolen card beside the first) until its copy is drawn from that spot.
	_stolen.append({"pos": c.position, "rot": c.rotation, "scl": c.scale.y, "node": c})


## Where a stolen card changes hands: on the thief's side of the river.
func _handoff(thief: int) -> Dictionary:
	if thief == 0:
		return {"pos": Vector2(V.x * 0.62, V.y * 0.52), "rot": 0.0, "scl": 0.6}
	return {"pos": Vector2(V.x * 0.38, V.y * 0.3), "rot": PI, "scl": 0.5}


## A copy is about to be drawn: it flies in from where it was taken (the handed-over stolen card, a card in the enemy
## hand, the enemy deck or the copied minion) instead of from its owner's deck.
func _on_copy(ev: Dictionary) -> void:
	if not _stolen.is_empty():
		_copy_start = _stolen.pop_front()
		return
	var foe: int = 1 - int(ev.side)
	var from := {}
	match ev.from:
		"enemy_hand":
			var src: CardView = null
			for v in hand_views[foe]:
				if v.card_id == ev.id:
					src = v
			if src == null and not hand_views[foe].is_empty():
				src = hand_views[foe][randi() % hand_views[foe].size()]
			if src != null:
				from = {"pos": src.position, "rot": src.rotation, "scl": src.scale.y}
		"enemy_deck":
			from = {"pos": deck_views[foe].position, "rot": PI / 2, "scl": 0.36}
		_:
			for m in board_views[foe] + board_views[int(ev.side)]:
				if m.card_id == ev.id:
					from = {"pos": m.position, "rot": 0.0, "scl": 0.45}
					break
	if not from.is_empty():
		Vfx.pilfer(self, from.pos)
		_copy_start = from


## A Ruse going off: a golden flash and its name over the minion, or over the spell as it is cast.
func _show_ruse(n: Node2D) -> void:
	if not is_instance_valid(n):
		return
	Vfx.keyword(self, n, "ruse")
	_toast(n.position + Vector2(0, -(MinionView.H / 2 + 24) if n is MinionView else -150.0), "Ruse", UI.GOLD)
	if n is MinionView:
		_pop(n, 1.12)
	await _wait(0.3)


## True when this play's Ruse goes off (its "ruse" event is queued before the next action).
func _ruse_follows(side: int) -> bool:
	for e in queue:
		if e.t == "ruse":
			return e.side == side and e.uid == -1
		if e.t in ["play", "attack", "power", "turn_end"]:
			return false
	return false


static func _has_ruse(id: String) -> bool:
	return CardDB.card(id).get("effects", []).any(func(e): return e.get("ruse", false))


## Circe's swine: the minion spins down into a swirl and a puff of smoke, and its new form pops up in the same slot
## (the death event that follows is skipped, the summon replaces the view: see _on_summon).
func _on_transform(ev: Dictionary) -> void:
	var m = unit_views.get(ev.uid)
	if not (m is MinionView):
		return
	_morph = {"uid": ev.uid, "side": ev.side, "view": m}
	m.busy = true
	m.z_index = 12
	var tint: Color = VfxData.school(VfxData.profile(ev.src)).hot
	Vfx.morph(self, m.position, ev.src)
	var k := _speed()
	var t: Tween = m.create_tween().set_parallel(true)
	t.tween_property(m, "rotation", 1.6, 0.32 / k).set_ease(Tween.EASE_IN)
	t.tween_property(m, "scale", Vector2(0.15, 0.15), 0.32 / k).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	t.tween_property(m, "modulate", Color(tint.r, tint.g, tint.b, 0.0), 0.32 / k)
	await t.finished
	m.visible = false


## The view of the minion transformed on `side`, whose new form is being summoned (null when there is none).
func _take_morph(side: int) -> MinionView:
	if _morph.is_empty():
		return null
	var old = _morph.view
	var was: int = _morph.side
	_morph = {}
	if not is_instance_valid(old):
		return null
	if was == side and board_views[side].has(old):
		return old
	board_views[was].erase(old) # never leave a stale slot behind
	old.queue_free()
	_layout_board(was)
	return null


## The new form pops out of the swirl (no slam: it was not played).
func _morph_in(m: MinionView) -> void:
	var k := _speed()
	m.position = m.home
	m.scale = Vector2(0.2, 0.2)
	m.rotation = -1.2
	m.modulate.a = 0.0
	Fx.flash(fx_layer, "k_twirl_01", m.home, 300.0, 0.45, Vfx.summon_tint(m.card_id), -3.0)
	Fx.burst(fx_layer, m.home, Vfx.summon_tint(m.card_id), 18, 220.0, 0.5, 9.0, 0.0)
	Sfx.play("card_place", -8.0, 1.2)
	var t := m.create_tween().set_parallel(true)
	t.tween_property(m, "scale", Vector2.ONE, 0.3 / k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(m, "rotation", 0.0, 0.3 / k).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "modulate:a", 1.0, 0.12 / k)
	await t.finished
	shake(3.0)
	await _wait(0.12)


## Board-wide effects are staged by Vfx from the card's profile (data/vfx.json). A second sweep by the same card in
## one play (Medusa's Gaze damages, then freezes) is shown as a quick follow-up instead of a second sweep.
var _last_aoe := ""
func _on_aoe(ev: Dictionary) -> void:
	var follow: bool = _last_aoe == ev.id
	_last_aoe = ev.id
	await Vfx.mass(self, ev, follow)


func _on_game_over(ev: Dictionary) -> void:
	over = true
	_end_aim()
	# Nothing is playable any more: put out the green and gold glows (hand, minions, hero power, End Turn), which
	# otherwise burned on under the result screen.
	_refresh_highlights()
	_coach.dismiss()
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
		Vfx.hero_death(self, h)
		_screen_flash(Color(1, 0.5, 0.2), 0.6)
		await h.burn_away(1.4)
	if guide != null:
		guide.on_turn(1) # Virgil steps aside for the result
	if not lesson.is_empty():
		_show_lesson_result(ev.winner) # a lesson never counts in the record
		return
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
	# The verdict on the charred banner.
	var title := UI.banner("VICTORY" if won else ("DEFEAT" if winner == 1 else "DRAW"), 120,
		UI.GOLD if won else Color(0.9, 0.3, 0.24), 0.0, 0.0, 1.8)
	box.add_child(title)
	var line: String = str(CardDB.hero(Game.enemy_hero).get("defeat_line", "The way lies open.")) if won else (
		"The shades close in. Try again.")
	# The verdict and the reward on a framed plate under the title, the Obols beside their coin.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.parchment_box(56, 34)) # Virgil's words in dark ink on parchment
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(plate)
	box.add_child(pc)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pv)
	var sub := UI.label(line, 34, "italic", UI.BONE, 3, Color.BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.fit_label(sub, minf(1100.0, V.x - 260.0), 22)
	pv.add_child(sub)
	var reward := Collection.reward_battle(won)
	Sfx.play("coins", -4.0)
	var gain_row := HBoxContainer.new()
	gain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gain_row.add_theme_constant_override("separation", 12)
	gain_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(gain_row)
	if UiSkin.has("icon_obol"):
		var coin := UiSkin.rect("icon_obol", Vector2(46, 46))
		coin.custom_minimum_size = coin.size
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gain_row.add_child(coin)
	var gain := UI.label("+%d Obols   ·   a pack costs %d" % [reward, Collection.PACK_PRICE], 30, "title",
		Color(1.0, 0.85, 0.5), 3, Color.BLACK)
	gain.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gain_row.add_child(gain)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	if Collection.packs > 0 or Collection.obols >= Collection.PACK_PRICE:
		var packs := UI.button("Open Packs", 340)
		packs.pressed.connect(func(): Game.go(Game.PACKS))
		row.add_child(packs)
	var again := UI.button("Play Again", 340)
	# Through start_with, so the opponent deals a new deck (never the one just faced) instead of a rematch.
	again.pressed.connect(func(): Game.start_with(Game.player_cards.duplicate(), Game.player_hero))
	row.add_child(again)
	var menu := UI.button("Main Menu", 340)
	menu.pressed.connect(func(): Game.go(Game.MENU))
	row.add_child(menu)
	box.modulate.a = 0.0
	title.pivot_offset = title.size / 2
	title.scale = Vector2(1.6, 1.6)
	var t := box.create_tween().set_parallel(true)
	t.tween_property(box, "modulate:a", 1.0, 0.5)
	t.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if won:
		Sfx.play("title_sting", -4.0, 1.0, 0.0)
		Fx.burst(fx_layer, V / 2, UI.GOLD, 120, 800.0, 2.0, 14.0, 300.0)
	else:
		Sfx.play("bell_funeral", -6.0, 1.0, 0.0)


## A lesson's end: "Lesson complete" (or the defeat) on the charred banner, Virgil's closing words beside his portrait,
## the reward the first time the lesson is won, then the way on: the next lesson, the lessons, or a new try.
func _show_lesson_result(winner: int) -> void:
	var won := winner == 0
	var paid: Dictionary = Lessons.complete(lesson.id) if won else {}
	var dim := ColorRect.new()
	dim.name = "ResultDim"
	dim.color = Color(0, 0, 0, 0)
	dim.size = V
	ui.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.65, 0.6)
	var box := VBoxContainer.new()
	box.name = "LessonResult"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = V
	box.add_theme_constant_override("separation", 30)
	ui.add_child(box)
	var title := UI.banner("Lesson complete" if won else ("DEFEAT" if winner == 1 else "DRAW"), 96 if won else 120,
		UI.GOLD if won else Color(0.9, 0.3, 0.24), 0.0, 0.0, 1.8)
	box.add_child(title)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.parchment_box(56, 34)) # Virgil's words in dark ink on parchment
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(plate)
	box.add_child(pc)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 48)
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(prow)
	var vh := CenterContainer.new()
	vh.custom_minimum_size = Vector2(150, 200)
	vh.add_child(Virgil.portrait(Vector2(118, 150)))
	prow.add_child(vh)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 14)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prow.add_child(pv)
	var line := str(lesson.get("outro", "")) if won else "Even the bravest stumble here. Try again: I will be at your side."
	var sub := UI.label(line, 32, "italic", UI.INK, 0)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(minf(820.0, V.x - 700.0), 0)
	pv.add_child(sub)
	if not paid.is_empty():
		pv.add_child(LessonsScreen.reward_badge(paid, "Reward:  ", true))
		Sfx.play("coins", -4.0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	var next := Lessons.next_after(lesson.id)
	var buttons := []
	if won and next != "":
		buttons.append(["Next Lesson", Game.start_lesson.bind(next)])
	elif won and Collection.packs > 0:
		buttons.append(["Open Packs", Game.go.bind(Game.PACKS)])
	if not won:
		buttons.append(["Try Again", Game.start_lesson.bind(lesson.id)])
	buttons.append(["Lessons", Game.go.bind(Game.LESSONS)])
	if won and next == "":
		buttons.append(["Main Menu", Game.go.bind(Game.MENU)])
	for b in buttons:
		var btn := UI.button(b[0], 340)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	box.modulate.a = 0.0
	title.pivot_offset = title.size / 2
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
	var bars: Array[TextureRect] = []
	for top in [true, false]:
		# Soot rather than a hard black slab: solid at the screen edge, feathered toward the middle.
		var g := GradientTexture2D.new()
		g.width = 4
		g.height = 64
		g.fill_from = Vector2(0, 0 if top else 1)
		g.fill_to = Vector2(0, 1 if top else 0)
		var gr := Gradient.new()
		gr.set_color(0, Color(0.02, 0.01, 0.01, 0.95))
		gr.add_point(0.6, Color(0.02, 0.01, 0.01, 0.85))
		gr.set_color(gr.get_point_count() - 1, Color(0.02, 0.01, 0.01, 0.0))
		g.gradient = gr
		var b := TextureRect.new()
		b.texture = g
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.size = Vector2(V.x, bar_h)
		b.position = Vector2(0, -bar_h if top else V.y)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		bars.append(b)
	var band := ColorRect.new()
	band.color = Color(0.05, 0.02, 0.01, 0.0)
	# The dim spans the whole screen under the bars, so their feathered inner edges blend into it.
	band.size = V
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	root.move_child(band, 0)
	var parts := str(card.get("name", "")).split(",")
	# The name on the charred banner, the epithet on the red ribbon under it.
	var name_l := UI.banner(parts[0].strip_edges().to_upper(), 76, UI.RARITY.legendary)
	name_l.position = Vector2(V.x * 0.4 - 60, V.y / 2 - 30 - name_l.size.y)
	name_l.modulate.a = 0.0
	root.add_child(name_l)
	# The epithet on the red ribbon under the name.
	var epithet := UI.ribbon(parts[1].strip_edges() if parts.size() > 1 else "Legendary", 640, 38)
	epithet.position = Vector2(V.x * 0.4 - 50, V.y / 2 + 22)
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
	t.tween_property(name_l, "position:x", V.x * 0.4 - 20, 1.4 / sp).set_delay(0.2 / sp)
	t.tween_property(epithet, "modulate:a", 1.0, 0.3 / sp).set_delay(0.35 / sp)
	Fx.burst(fx_layer, Vector2(V.x * 0.25, V.y / 2), UI.GOLD, 50, 600.0, 1.0, 12.0, 100.0)
	await get_tree().create_timer(1.3 / sp).timeout
	var out := root.create_tween().set_parallel(true)
	out.tween_property(cv, "position:x", V.x + 300, 0.3 / sp).set_ease(Tween.EASE_IN)
	out.tween_property(root, "modulate:a", 0.0, 0.3 / sp)
	await out.finished
	root.queue_free()


func _show_banner(text: String, color: Color, size: int = 96) -> void:
	# The painted words when the heading has them (they replace the letters), else the font.
	var old := banner.get_node_or_null("Word")
	if old != null:
		old.free()
	# The label keeps the text (tests read it), its letters then clear.
	var word := UI.word_tex(text)
	banner.text = text
	if word != null:
		# Inside the ribbon's dark band (about 76 px of its 208, between the gilded trims) and clear of its folds.
		var wr := UI.word_rect(word, Vector2(700.0, 72.0))
		wr.position = (banner.size - wr.size) / 2.0 + Vector2(0, 8)
		banner.add_child(wr)
	banner.add_theme_color_override("font_color", color if word == null else Color.TRANSPARENT)
	banner.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.0) if word == null else Color.TRANSPARENT)
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


## The bounding box of a texture's opaque pixels (alpha > 0.15), in texture pixels.
static func _opaque_rect(tex: Texture2D) -> Rect2:
	var img := tex.get_image()
	if img == null:
		return Rect2(Vector2.ZERO, tex.get_size())
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var r := img.get_used_rect()
	return Rect2(r) if r.size.x > 0 else Rect2(Vector2.ZERO, tex.get_size())


func _set_end_button(side: int) -> void:
	var mine := side == 0 and not autoplay
	end_btn.modulate = Color.WHITE
	_end_label.text = "END TURN" if mine else "ENEMY TURN"
	# The dimmed seal of the enemy's turn is too dark for ink: the words go pale there.
	UI.engraved(_end_label, Color(0.2, 0.08, 0.03) if mine else Color(0.62, 0.56, 0.48))
	# Shrink until the words fit inside the seal's smooth inner oval. The room is the oval's, not the label's own
	# size (a label grows to its text, which pushed a long "ENEMY TURN" off centre onto the rope rim).
	var room := END_OVAL * Vector2(0.56, 0.5)
	var fs := 28 if mine else 24
	var font := _end_label.get_theme_font("font")
	while fs > 16 and font.get_string_size(_end_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room.x:
		fs -= 1
	_end_label.add_theme_font_size_override("font_size", fs)
	_end_label.size = room
	_end_label.position = -room / 2
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
	var shift := 0.0 ## the whole fan slides left by this much so its right end stays off the mana tray
	if side == 0 and n > 1:
		# The outermost card's visible corner (it leans outward) must stay left of the painted mana tray, also
		# while a hovered card spreads its right-hand neighbours by HOVER_SPREAD.
		var edge := _hand_edge()
		var half := (n - 1) / 2.0
		var reach := _fan_half_width(half * 0.055, s)
		spacing = minf(spacing, maxf(0.0, (edge - reach - V.x / 2) / half))
		if hi != -1 and hi < n - 1:
			shift = maxf(0.0, V.x / 2 + half * spacing + HOVER_SPREAD + reach - edge)
	for i in n:
		var c: CardView = cards[i]
		if c == drag_card:
			continue
		var k := i - (n - 1) / 2.0
		var x := V.x / 2 + k * spacing - shift
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
				# Lifted clear of the screen edge and a bit larger, so the whole card reads; its right edge stops at
				# the mana tray.
				x = minf(x, _hand_edge() - CardView.W * HOVER_SCALE / 2)
				c.home = Vector2(x, V.y - CardView.H * HOVER_SCALE / 2 - 24)
				_move(c, c.home, 0.0, HOVER_SCALE, 0.12)
				continue
			x += HOVER_SPREAD * signf(i - hi)
		c.home = Vector2(x, y)
		c.home_rot = rot
		c.home_scale = s
		_move(c, c.home, rot, s, 0.25)


## The x the player's hand must stay left of: the left end of the painted mana tray (232 px left of its socket,
## a little margin included).
func _hand_edge() -> float:
	return mana_views[0].position.x - 232.0


## How far right of its centre a hand card at scale `s` leaning by `rot` reaches (its upper outer corner).
static func _fan_half_width(rot: float, s: float) -> float:
	return (CardView.W / 2 * cos(rot) + CardView.H / 2 * sin(absf(rot))) * s


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
	if mine and guide != null:
		guide.on_idle() # Virgil's next line first: it decides what may glow
	var any := false
	var ruse := mine and st.ruse_active(0)
	for c in hand_views[0]:
		c.playable = mine and st.can_play(0, c.uid) and _allowed({"act": "play", "card": c.card_id})
		c.ruse = ruse and _has_ruse(c.card_id)
		any = any or c.playable
	for m in board_views[0]:
		var u = st.units.get(m.uid)
		m.can_attack = mine and u != null and st.can_attack(u) and _allowed({"act": "attack", "card": m.card_id})
		any = any or m.can_attack
	for m in board_views[1]:
		m.can_attack = false
	if heroes[0]:
		heroes[0].power_ready = mine and st.can_use_power(0) and _allowed({"act": "power"})
		any = any or heroes[0].power_ready
	_end_glow.set_on(mine and not any and _allowed({"act": "end"}))
	if mine:
		_set_mana(0, st.sides[0].mana, st.sides[0].max_mana)
		_offer_coach(any)


## First-game tips, most useful first: play a card, attack (Guard when it blocks), hero power, end turn.
func _offer_coach(any: bool) -> void:
	if autoplay or _in_mulligan or _coach.showing() or is_instance_valid(_pause_dim):
		return
	if guide != null and guide.talking():
		return # one voice at a time: Virgil first
	var xf := get_canvas_transform()
	for c in hand_views[0]:
		if c.playable and CardDB.card(c.card_id).type == "minion":
			# Points at the empty board where the card goes, so the bubble never covers the hand.
			if _coach.offer("play", xf * (Vector2(V.x / 2, _board_y(0)) + board_layer.position)):
				return
			break
	if _offer_keyword(xf):
		return
	for m in board_views[0]:
		if m.can_attack:
			for e in board_views[1]:
				var u = st.units.get(e.uid)
				if u != null and u.has("guard") and _coach.offer("guard", xf * (e.position + board_layer.position)):
					return
			if _coach.offer("attack", xf * (m.position + board_layer.position)):
				return
			break
	if heroes[0] != null and heroes[0].power_ready and not any_card_playable():
		if _coach.offer("power", xf * (heroes[0].power.global_position)):
			return
	if not any and st.turn >= 3:
		_coach.offer("end", xf * (end_btn.global_position))


## The first time a keyword or a trigger is on the board (the enemy's minions first: what stands against you), the
## coach says what it means, pointing at the minion: "Ward: The first damage it would take is blocked." Once ever.
func _offer_keyword(xf: Transform2D) -> bool:
	for side in [1, 0]:
		for m in board_views[side]:
			var u = st.units.get(m.uid)
			if u == null:
				continue
			var live: Dictionary = CardDB.card(u.id).duplicate()
			live["keywords"] = u.keywords.keys()
			live["frozen"] = u.frozen
			live["silenced"] = u.silenced
			live["wrath"] = u.wrath
			for t in UI.card_tips(live, true):
				var key := ""
				for k in UI.KEYWORD_HELP:
					if UI.KEYWORD_HELP[k][0] == t[0]:
						key = k
				# Guard keeps the coach's own tip (the one shown when an attack is blocked).
				var id := "guard" if key == "guard" else "kw_" + key
				var text := "" if key == "guard" else "%s: %s" % [t[0], t[1]]
				if key != "" and _coach.fresh(id):
					return _coach.offer(id, xf * (m.position + board_layer.position), text)
	return false


## Lessons: may the player take `action` now ({act, card, target}; see LessonGuide.allows)? Always in a real match.
func _allowed(action: Dictionary) -> bool:
	return guide == null or guide.allows(action)


## The same, but a refusal says so: "Not yet" above `pos` (a board point) and Virgil's line pulses back into view.
func _permit(action: Dictionary, pos: Vector2) -> bool:
	if _allowed(action):
		return true
	_nope(pos, "Not yet")
	guide.nudge()
	return false


## The player's action went through: Virgil hears of it. `hit`: whether it was the step's action, judged before it
## happened (null: judge it now; fine when its target cannot have left the board).
func _did(action: Dictionary, hit: Variant = null) -> void:
	if guide != null:
		guide.performed(action, hit)


func any_card_playable() -> bool:
	for c in hand_views[0]:
		if c.playable:
			return true
	return false


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

## Android's back gesture (Game.back()): the same as Esc, one layer back or the pause menu.
func go_back() -> void:
	_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_on_back()
		get_viewport().set_input_as_handled()
		return
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
	_coach.dismiss()
	if guide != null and guide.wants_tap():
		guide.tap() # Virgil is talking: the tap moves his lesson on
		return
	if guide != null:
		guide.on_press() # a passing remark goes away with the first touch
	if _mull_waiting:
		var mc := _pick_hand(p)
		if mc != null:
			_toggle_mulligan(mc)
		return
	if mode in [Mode.AIM_BATTLECRY, Mode.AIM_ATTACK, Mode.AIM_POWER, Mode.AIM_SPELL] and _sticky:
		_finish_aim(p)
		return
	if not _my_turn():
		# A touch screen has no hover: a tap on a minion or hero shows its card and tips during the enemy turn too.
		var seen = _pick_unit(p) if not over and not _in_mulligan else null
		if seen != null:
			_show_inspect(seen)
		else:
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
	if u is MinionView and u.side == 0 and guide != null and st.can_attack(st.units.get(u.uid)) \
			and not _permit({"act": "attack", "card": u.card_id}, u.position):
		return # it could attack, but this is not the moment in the lesson
	if heroes[0] != null and heroes[0].power_contains(p):
		if st.can_use_power(0) and not _permit({"act": "power"}, heroes[0].power.global_position):
			return
		if st.can_use_power(0):
			var tt := BattleState.power_target_type(CardDB.hero(st.sides[0].hero_id))
			if tt == "":
				if st.use_power(0):
					_did({"act": "power", "target": -1})
			else:
				mode = Mode.AIM_POWER
				_start_aim(heroes[0].power.global_position, st.valid_targets(0, tt))
		else:
			_nope(heroes[0].power.global_position, "Already used" if st.sides[0].power_used else "Not enough mana")
		return
	var lp := end_btn.to_local(p) / (END_OVAL / 2)
	if lp.length() < 1.0:
		_end_turn()
		return
	if u != null:
		_show_inspect(u)
		return
	_board_touch(p)


func _on_motion(p: Vector2) -> void:
	_pointer = p
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
			elif above and BattleState.target_type(card) != "" and st.can_play(0, drag_card.uid) \
					and _allowed({"act": "play", "card": drag_card.card_id}):
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
			if not _permit({"act": "play", "card": c.card_id}, c.position):
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
				if st.play_card(0, c.uid, -1, idx):
					_did({"act": "play", "card": c.card_id, "target": -1})
			else:
				drag_card = null
				mode = Mode.IDLE
				if st.play_card(0, c.uid):
					_did({"act": "play", "card": c.card_id, "target": -1})
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
	# What the aim would do, for the lesson's gate (a real match lets everything through).
	var action := {"act": "power", "target": target}
	if m == Mode.AIM_ATTACK:
		action = {"act": "attack", "card": str(st.units[attacker].id) if st.units.has(attacker) else "", "target": target}
	elif m == Mode.AIM_SPELL or m == Mode.AIM_BATTLECRY:
		action = {"act": "play", "card": str(st.hand_card(0, card_uid).get("id", "")), "target": target}
	if not _permit(action, u.position):
		if m == Mode.AIM_SPELL or m == Mode.AIM_BATTLECRY:
			_return_card()
		return
	# Judged now: once the blow lands, its target may be gone from the board.
	var hit := guide != null and guide.hits(action)
	var done := false
	match m:
		Mode.AIM_ATTACK:
			done = st.attack(0, attacker, target)
		Mode.AIM_POWER:
			done = st.use_power(0, target)
		Mode.AIM_SPELL:
			drag_card = null
			done = st.play_card(0, card_uid, target)
		Mode.AIM_BATTLECRY:
			drag_card = null
			_gap_index = -1
			done = st.play_card(0, card_uid, target, index)
	if done:
		_did(action, hit)


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
	if not _permit({"act": "end"}, end_btn.position + Vector2(0, 40)):
		return
	_cancel()
	Sfx.play("ui_confirm", -6.0)
	_pop(end_btn, 0.9)
	st.end_turn()
	_did({"act": "end"})


## Why an action was refused ("Not enough mana"), on a small plaque that pops above `pos` and fades.
func _nope(pos: Vector2, text: String) -> void:
	Sfx.play("ui_back", -8.0)
	_toast(pos + Vector2(0, -110), text, Color(1.0, 0.86, 0.7))


## A short message on an engraved plaque centred on board point `pos`: pops in, holds, fades. One at a time.
func _toast(pos: Vector2, text: String, color: Color) -> void:
	var old := ui.get_node_or_null("Toast")
	if old != null:
		old.name = "ToastOld"
		old.queue_free()
	var plate := UI.plaque_label(text, 30, "title", color, 0.0, 30, 10)
	plate.name = "Toast"
	ui.add_child(plate)
	plate.reset_size()
	var screen := get_canvas_transform() * pos # the board may sit under a moved camera
	plate.position = (screen - plate.size / 2).clamp(Vector2(16, 16), V - plate.size - Vector2(16, 16))
	plate.pivot_offset = plate.size / 2
	plate.scale = Vector2(0.4, 0.4)
	var t := plate.create_tween()
	t.tween_property(plate, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.9)
	t.tween_property(plate, "modulate:a", 0.0, 0.3)
	t.tween_callback(plate.queue_free)


## Touching the empty board: ripples in the river, scattered wisps, a puff of ash on the shore.
func _board_touch(p: Vector2) -> void:
	for w in _wisps:
		var d := w.position - p
		if d.length() < 260.0:
			w.set_meta("flee", w.get_meta("flee") + d.normalized() * (260.0 - d.length()) * 1.4)
	if props != null and props.touch(p):
		return
	if river.visible and absf(p.y - _river_y()) < maxf(60.0, _river_h * 0.58) * ky:
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
	if u is HeroView:
		_show_hero_tip(u)
		return
	if not (u is MinionView):
		return
	var id: String = u.card_id
	_did({"act": "inspect", "card": id})
	inspect = CardView.new().setup(id, -1, true)
	inspect.z_index = 300
	inspect.sway = true
	inspect.scale = Vector2(0.6, 0.6)
	fx_layer.add_child(inspect)
	inspect.create_tween().tween_property(inspect, "scale", Vector2(INSPECT_SCALE, INSPECT_SCALE), 0.12)
	# The minion as it is now, not as printed: its current numbers, the keywords it has gained or lost, frozen,
	# silenced (a silenced minion keeps no text, so its old keywords and triggers get no tips).
	var live: Dictionary = CardDB.card(id).duplicate()
	var unit = st.units.get(u.uid)
	if unit != null:
		inspect.set_stats(unit.attack, unit.health, unit.max_health)
		live["keywords"] = unit.keywords.keys()
		live["frozen"] = unit.frozen
		live["silenced"] = unit.silenced
		live["wrath"] = unit.wrath
	var tips := UI.card_tips(live, true)
	for t in tips:
		_add_tip(t[0], t[1])
	# Beside the minion, clear of both heroes, their gems, the End Turn seal and the minion itself. The tips go on the
	# far side of the card (so the card stays next to the minion it explains), in two columns when one is too tall.
	var card_size := Vector2(CardView.W, CardView.H) * INSPECT_SCALE
	var left: bool = u.position.x > V.x / 2
	var avoid := _keep_out()
	avoid.append(Rect2(u.position - Vector2(80, 100), Vector2(160, 200)))
	var spots := [] ## [card rect, card on the left of the minion]
	for side_left in [left, not left]:
		var x: float = u.position.x - 140.0 - card_size.x if side_left else u.position.x + 140.0
		var spot = _clear_spot(card_size, Vector2(x, u.position.y - card_size.y / 2), avoid)
		if spot != null:
			spots.append([Rect2(spot, card_size), side_left])
	if spots.is_empty():
		var fx: float = u.position.x - 140.0 - card_size.x if left else u.position.x + 140.0
		spots.append([Rect2(Vector2(fx, clampf(u.position.y - card_size.y / 2, 16.0, V.y - card_size.y - 16.0)),
			card_size), left])
	var chosen: Array = spots[0]
	if not tips.is_empty():
		var placed := false
		for outer in [true, false]:
			for sp in spots:
				var av: Array[Rect2] = avoid.duplicate()
				av.append(sp[0])
				if _fit_tips(_tips, tips, sp[0], sp[1] if outer else not sp[1], av):
					chosen = sp
					placed = true
					break
			if placed:
				break
		if not placed:
			_tips_fallback(_tips, tips, chosen[0], chosen[1])
	inspect.position = (chosen[0] as Rect2).get_center()


## Lays the tips grid beside `card` on its left (`left`) or right side, in one column or else two, slid up or down
## to stay on screen and clear of `avoid`; false when neither fits on that side.
func _fit_tips(grid: GridContainer, tips: Array, card: Rect2, left: bool, avoid: Array[Rect2]) -> bool:
	for cols in [1, 2]:
		if cols > tips.size():
			break
		var sz := _tips_size(tips, cols)
		var x: float = card.position.x - 12.0 - sz.x if left else card.end.x + 12.0
		var spot = _clear_spot(sz, Vector2(x, card.position.y), avoid)
		if spot != null:
			grid.columns = cols
			grid.position = spot
			return true
	return false


## No clear room anywhere: one column beside the card, kept on screen.
func _tips_fallback(grid: GridContainer, tips: Array, card: Rect2, left: bool) -> void:
	var sz := _tips_size(tips, 1)
	grid.columns = 1
	var x: float = card.position.x - 12.0 - sz.x if left else card.end.x + 12.0
	grid.position = Vector2(clampf(x, 16.0, V.x - sz.x - 16.0), clampf(card.position.y, 16.0, maxf(16.0, V.y - sz.y - 16.0)))


## The size of a grid of tip plates (UI.tip_plate at its default width) in `cols` columns, measured from the fonts.
func _tips_size(tips: Array, cols: int) -> Vector2:
	var hs: Array[float] = []
	var title_h := UI.font("title").get_height(24)
	for t in tips:
		hs.append(78.0 + 4.0 + title_h + UI.font("body").get_multiline_string_size(str(t[1]), HORIZONTAL_ALIGNMENT_LEFT,
			TIP_W - 100.0, 22).y + 6.0)
	var h := 0.0
	for i in range(0, hs.size(), cols):
		var row := hs[i]
		if cols > 1 and i + 1 < hs.size():
			row = maxf(row, hs[i + 1])
		h += row + TIP_GAP
	return Vector2(cols * TIP_W + (cols - 1) * TIP_GAP, h - TIP_GAP)


## What a pop-up card and its tips must never cover: both heroes (portrait, health and armor gems, hero power), the
## End Turn seal, the mana trays, the deck piles and the Menu button.
func _keep_out() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in 2:
		out.append(Rect2(_hero_pos(i) + Vector2(-130, -135), Vector2(370, 262)))
		if mana_views[i] != null:
			out.append(Rect2(mana_views[i].position + Vector2(-250, -45), Vector2(450, 90)))
		if deck_views[i] != null: # the pile lies on its side, about 130 x 90 px, a little stacked up and right
			out.append(Rect2(deck_views[i].position + Vector2(-75, -70), Vector2(165, 125)))
	out.append(Rect2(end_btn.position - END_OVAL / 2 - Vector2(14, 14), END_OVAL + Vector2(28, 28)))
	out.append(Rect2(16, 12, 180, 72))
	return out


## Top-left for a `size` box as close to `want` (top-left) as it can be by sliding it up or down, inside the screen
## and clear of `avoid`; null when the column at that x has no such room.
func _clear_spot(size: Vector2, want: Vector2, avoid: Array[Rect2]):
	if want.x < 16.0 or want.x + size.x > V.x - 16.0:
		return null
	var top := 16.0
	var bottom := V.y - 16.0 - size.y
	if bottom < top:
		return null
	for d in range(0, int(V.y), 8):
		for dir in [1.0, -1.0]:
			if d == 0 and dir < 0.0:
				continue
			var y: float = want.y + d * dir
			if y < top or y > bottom:
				continue
			var r := Rect2(Vector2(want.x, y), size)
			var clear := true
			for a in avoid:
				if r.intersects(a):
					clear = false
					break
			if clear:
				return Vector2(want.x, y)
	return null


## Keyword tips beside the hand card you look at: the one lifted under the pointer, or the one you hold over the
## hand (shown full size above the finger). Gone once the card leaves the hand area, is played or let go.
func _tick_hand_tips() -> void:
	var c: CardView = null
	var center := Vector2.ZERO
	var scl := 1.0
	if over or _in_mulligan or _paused():
		c = null
	elif mode == Mode.IDLE and hover_card != null and is_instance_valid(hover_card) and hand_views[0].has(hover_card):
		c = hover_card
		center = c.home
		scl = HOVER_SCALE
	elif mode == Mode.DRAG_CARD and drag_card != null and is_instance_valid(drag_card) \
			and _pointer.y >= V.y * PLAY_LINE:
		c = drag_card
		center = c.position
		scl = c.scale.x
	if c != _hand_tips_card:
		_hand_tips_card = c
		for t in _hand_tips.get_children():
			t.queue_free()
		_hand_tips.set_meta("tips", [])
		if c != null:
			var tips := UI.card_tips(CardDB.card(c.card_id))
			for t in tips:
				_hand_tips.add_child(UI.tip_plate(t[0], t[1]))
			_hand_tips.set_meta("tips", tips)
			_did({"act": "inspect", "card": c.card_id})
	_hand_tips.visible = c != null
	if c == null:
		return
	var size := Vector2(CardView.W, CardView.H) * scl
	var rect := Rect2(center - size / 2, size)
	var avoid := _keep_out()
	avoid.append(rect)
	# Toward the nearer screen edge first, so the tips cover as little of the hand as they can.
	var tips: Array = _hand_tips.get_meta("tips", [])
	var edge := center.x < V.x / 2
	if not _fit_tips(_hand_tips, tips, rect, edge, avoid) and not _fit_tips(_hand_tips, tips, rect, not edge, avoid):
		_tips_fallback(_hand_tips, tips, rect, edge)


func _show_hero_tip(h: HeroView) -> void:
	var def := CardDB.hero(h.hero_id)
	_add_tip(def.get("name", ""), "Hero power: %s (%d mana). %s" % [def.power.name, def.power.cost, def.power.text])
	# Right of the hero power disc (which sits right of the portrait), so the tip never hides it.
	# Kept on screen and clear of the mana trays in the top and bottom corners.
	_tips.position = Vector2(minf(h.position.x + 260, V.x - 430.0), clampf(h.position.y - 60, 110.0, V.y - 330.0))


func _add_tip(title: String, text: String) -> void:
	_tips.add_child(UI.tip_plate(title, text))


func _hide_inspect() -> void:
	if inspect != null:
		inspect.queue_free()
		inspect = null
	for c in _tips.get_children():
		c.queue_free()
	_tips.columns = 1


# ================================================================ pause / debug

## True while the pause menu (or its options / concede pages) is open.
func _paused() -> bool:
	return _pause_dim != null and is_instance_valid(_pause_dim) and not _pause_dim.is_queued_for_deletion()


## Escape (Back) steps out one layer at a time: the options page, the concede question or the pause menu, an aim or
## drag in progress; with nothing open it opens the pause menu.
func _on_back() -> void:
	if _paused():
		# The last page opened over the pause menu closes first (Credits over Options), then the menu itself.
		var pages := _pause_dim.get_children().filter(func(n):
			return (n is OptionsPanel or n is CreditsPanel or n is HowToPlayPanel) and not n.is_queued_for_deletion())
		if not pages.is_empty():
			pages.back()._close()
		else:
			_pause_dim.queue_free()
		return
	if mode != Mode.IDLE:
		_cancel()
		return
	if not over:
		_open_pause()


func _open_pause() -> void:
	if _paused():
		return
	_cancel() # no arrow or held card left hanging under the menu
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = V
	ui.add_child(dim)
	_pause_dim = dim
	_coach.dismiss()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = V
	box.add_theme_constant_override("separation", 22)
	dim.add_child(box)
	box.add_child(UI.banner("Paused", 66)) # the heading on the charred banner
	var entries := [["Resume", dim.queue_free],
			["How to Play", func(): dim.add_child(HowToPlayPanel.new())],
			["Options", func(): dim.add_child(OptionsPanel.new())]]
	if lesson.is_empty():
		entries.append(["Concede", _ask_concede.bind(dim, box)])
	else:
		# A lesson is left, restarted or skipped, never conceded (it does not count in the record).
		entries.append(["Restart Lesson", func(): _leave_lesson(lesson.id)])
		entries.append(["Skip Lesson", func():
			Lessons.skip(lesson.id)
			_leave_lesson(Lessons.next_after(lesson.id))])
		entries.append(["Leave Lesson", func(): _leave_lesson("")])
	box.add_theme_constant_override("separation", 22 if entries.size() <= 4 else 14)
	for entry in entries:
		var b := UI.button(entry[0], 380, 84 if entries.size() <= 4 else 74)
		b.pressed.connect(entry[1])
		var c := CenterContainer.new()
		c.add_child(b)
		box.add_child(c)


## "Concede this match?" on the charred banner over the pause dim: Concede ends the match as a loss, Keep playing
## closes the pause menu.
func _ask_concede(dim: Control, menu: Control) -> void:
	menu.visible = false
	var box := VBoxContainer.new()
	box.name = "ConcedeConfirm"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = V
	box.add_theme_constant_override("separation", 26)
	dim.add_child(box)
	box.add_child(UI.banner("Concede this match?", 60))
	var note := CenterContainer.new()
	note.add_child(UI.plaque_label("It counts as a loss.", 30, "italic", UI.BONE, 0.0, 36, 10))
	box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	var yes := UI.button("Concede", 340)
	yes.pressed.connect(_concede)
	row.add_child(yes)
	var no := UI.button("Keep playing", 340)
	no.pressed.connect(dim.queue_free)
	row.add_child(no)
	Sfx.play("ui_back", -8.0)


func _concede() -> void:
	over = true
	Game.record_result(1)
	Game.go(Game.MENU)


## Out of a lesson from its pause menu: into lesson `next` ("" for the lessons screen). Nothing is recorded.
func _leave_lesson(next: String) -> void:
	over = true
	if next != "":
		Game.start_lesson(next)
	else:
		Game.go(Game.LESSONS)


func _take_shot() -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join("shot_%02d.png" % _shot_i))
	if over:
		_shots_after_over += 1
	_shot_i += 1
	if _shot_i >= _shot_max or (over and _shots_after_over >= 2):
		get_tree().quit()
