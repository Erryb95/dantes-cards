class_name LessonsScreen
extends Control
## Virgil's lessons (Learn to Play on the title screen): Virgil's portrait and a word from him on the left, the
## lessons down the right, one painted plaque each (its medallion, title, what it teaches, its reward or "Completed"),
## the one to play next lit and tagged. Any lesson can be played in any order, again and again; the reward is paid the
## first time it is won. Back returns to the title screen; How to Play opens the rules reference.

const TILE := Vector2(980, 168)

var _tiles: Array[Button] = []
var _t := 0.0
var _next := "" ## the recommended lesson


func _ready() -> void:
	Sfx.play_ambience("")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	_next = Lessons.recommended()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 22)
	add_child(root)
	root.add_child(UI.banner("Virgil's Lessons", 48, UI.GOLD, 0.0, 0.0, 1.8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	root.add_child(row)
	row.add_child(_virgil())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(list)
	for i in Lessons.all().size():
		var b := _tile(Lessons.all()[i], i)
		list.add_child(b)
		_tiles.append(b)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 30)
	root.add_child(bottom)
	var back := UI.button("Back", 280, 66)
	back.pressed.connect(go_back)
	bottom.add_child(back)
	var how := UI.button("How to Play", 340, 66)
	how.name = "HowToPlay"
	how.pressed.connect(func(): add_child(HowToPlayPanel.new()))
	bottom.add_child(how)
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.5)


## Esc / the back gesture (Game.back): to the title screen.
func go_back() -> void:
	Game.go(Game.MENU)


## Virgil on the left: his portrait with his name, and a word on where the player stands.
func _virgil() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 46)
	col.custom_minimum_size = Vector2(440, 0)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(440, 340)
	holder.add_child(Virgil.portrait(Vector2(232, 296)))
	col.add_child(holder)
	var plate := PanelContainer.new()
	plate.name = "Speech"
	plate.add_theme_stylebox_override("panel", UI.parchment_box(40, 26))
	var done := Lessons.done_count()
	var n := Lessons.all().size()
	var count: String = ["A few", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"][n if n <= 8 else 0]
	var say := "%s short lessons, and you will know the way. Each takes only a few minutes. Shall we begin?" % count
	if done >= n:
		say = "You have learned all I can teach. Play any lesson again whenever you like. Hell is wide: go and see it."
	elif done > 0 or not Settings.lessons.is_empty():
		say = "Welcome back, pilgrim. %s is waiting for you." % str(Lessons.get_lesson(_next).get("title", ""))
	var l := UI.label(say, 27, "italic", UI.INK, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	plate.add_child(l)
	col.add_child(plate)
	return col


## One lesson's plaque: the medallion, "Lesson N" over its title, what it teaches, and on the right its reward (or
## "Completed"). A tap starts it.
func _tile(l: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.name = "Lesson_%s" % l.id
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	var next := str(l.id) == _next
	var tints := {"normal": Color(0.95, 0.9, 0.82), "hover": Color(1.2, 1.08, 0.9), "pressed": Color(0.8, 0.7, 0.6)}
	for st in tints:
		b.add_theme_stylebox_override(st, UI.plaque_box(30, 10, tints[st]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# The iron field a little darker than a plaque's, so two lines of text read over its rivets; the next lesson's lighter.
	var k := 0.95 if next else 0.72
	UI.add_field(b, 6.0, Color(UI.FIELD.r * k, UI.FIELD.g * k, UI.FIELD.b * k))
	b.pressed.connect(func():
		Sfx.play("ui_confirm", -4.0)
		Game.start_lesson(str(l.id)))
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover", -10.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.015, 0.09))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.09))
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	var icon_px := TILE.y - 26.0
	if UiSkin.has(str(l.get("icon", ""))):
		var icon := UiSkin.rect(str(l.icon), Vector2(icon_px, icon_px), Vector2(18, 13))
		icon.name = "Icon"
		icon.use_parent_material = false
		if Lessons.status(l.id) == Lessons.DONE:
			icon.modulate = Color(0.85, 0.82, 0.78)
		b.add_child(icon)
	var x := 18.0 + icon_px + 22.0
	var right_w := 250.0
	var text_w := TILE.x - x - right_w - 30.0
	var learn := UI.label(str(l.learn), 24, "body", UI.BONE, 3, Color(0.04, 0.01, 0.01))
	learn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	learn.max_lines_visible = 2
	# Its lines evened out (no lone word under a full line), and the whole column (number, title, what it teaches)
	# centred on the plaque's height: a one-line lesson does not hang from the top.
	var learn_w := UI.balanced_width(learn.get_theme_font("font"), 24, learn.text, text_w)
	var lines := mini(2, int(UI.text_layout(learn.get_theme_font("font"), 24, learn.text, learn_w)["lines"]))
	# (A wrapped line advances about 4 px more than get_line_height, and the plaque's painted field sits 2 px high:
	# measured on the drawn ink.)
	var y0 := roundf((TILE.y - (76.0 + lines * (learn.get_line_height() + 4.0))) / 2.0) - 2.0
	var num := UI.label("LESSON %d" % (i + 1), 22, "title", Color(0.85, 0.7, 0.45), 3, Color.BLACK)
	num.position = Vector2(x, y0)
	b.add_child(num)
	var title := UI.label(str(l.title), 38, "title", UI.GOLD, 5, Color(0.08, 0.02, 0.0))
	title.position = Vector2(x, y0 + 22)
	title.size = Vector2(text_w, 50)
	UI.fit_label(title, text_w, 24)
	b.add_child(title)
	learn.position = Vector2(x, y0 + 76)
	learn.size = Vector2(learn_w, 60)
	b.add_child(learn)
	# The right-hand column: the reward still to win, or "Completed"; the recommended lesson wears a ribbon.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	right.position = Vector2(TILE.x - right_w - 26.0, 4 if next else 10) # room under it for the ribbon
	right.size = Vector2(right_w, TILE.y - (44.0 if next else 20.0))
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(right)
	if Lessons.status(l.id) == Lessons.DONE:
		var done := UI.label("Completed", 30, "title", Color(0.72, 0.95, 0.6), 4, Color(0.02, 0.06, 0.01))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(done)
	else:
		var hint := UI.label("Reward", 20, "italic", Color(0.85, 0.78, 0.66), 3, Color.BLACK)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(hint)
		var badge := reward_badge(l.get("reward", {}))
		badge.alignment = BoxContainer.ALIGNMENT_CENTER
		right.add_child(badge)
	if next:
		var rib := UI.ribbon("Start here" if Lessons.done_count() == 0 else "Next", 230, 28)
		rib.name = "NextRibbon"
		rib.position += Vector2(TILE.x - right_w / 2.0 - 26.0, TILE.y - 30.0)
		b.add_child(rib)
		b.set_meta("glow", true)
	for c in b.get_children():
		if c is Control and c.name != "Field":
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _process(delta: float) -> void:
	_t += delta
	for b in _tiles:
		if b.get_meta("glow", false):
			var k := 1.0 + 0.08 * (0.5 + 0.5 * sin(_t * 2.6))
			b.self_modulate = Color(k, k * 0.97, k * 0.9)


## A reward as a row: the Obol (or a little pack) beside "50 Obols" / "1 pack", after `prefix`; in red ink on
## parchment when `ink`, else in gold on the iron plaques.
static func reward_badge(r: Dictionary, prefix: String = "", ink: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var packs := int(r.get("packs", 0))
	var obols := int(r.get("obols", 0))
	if packs > 0:
		row.add_child(pack_icon(54.0))
	elif UiSkin.has("icon_obol"):
		var coin := UiSkin.rect("icon_obol", Vector2(44, 44))
		coin.custom_minimum_size = coin.size
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
	var text := ("%d pack" % packs if packs == 1 else "%d packs" % packs) if packs > 0 else "%d Obols" % obols
	var l := UI.label(prefix + text, 30, "title", Virgil.RED_INK, 0) if ink \
		else UI.label(prefix + text, 30, "title", Color(1.0, 0.85, 0.5), 3, Color.BLACK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


## A small card pack `h` px tall: a card back with Charon's Obol stamped on it, as on the pack-opening screen.
static func pack_icon(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(h * CardView.W / CardView.H, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := CardView.new().setup("lost_pilgrim", -1, false)
	back.scale = Vector2.ONE * h / CardView.H
	back.position = c.custom_minimum_size / 2.0
	back.set_process(false)
	c.add_child(back)
	if UiSkin.has("icon_obol"):
		var seal := UiSkin.sprite("icon_obol", Vector2(h * 0.42, h * 0.42))
		seal.use_parent_material = false
		seal.position = c.custom_minimum_size / 2.0
		c.add_child(seal)
	return c
