class_name LessonHeroScreen
extends Control
## The hero choice before The Trial (a lesson with "choose": true, see Lessons.chooses_hero): one painted plaque per
## hero of the class registry (CardDB.classes(), never a fixed number: the row scrolls when the heroes outgrow the
## screen), each with the hero's portrait, class, tagline, hero power and starter deck, all from CardDB.class_info and
## data/decks.json. A press picks a hero; Begin (or a press on the picked hero again) starts the match with that
## hero's class and its starter deck. Esc and Back return to the lessons screen.

const CARD_H := 610.0
const GAP := 26.0

var lesson_id := ""
var pick := "" ## the chosen hero's id
var _cards := {} ## hero id -> its plaque button
var _begin: Button
var _t := 0.0


func _ready() -> void:
	Sfx.play_ambience("")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	lesson_id = Game.lesson_choice
	if Lessons.get_lesson(lesson_id).is_empty() or not Lessons.chooses_hero(Lessons.get_lesson(lesson_id)):
		for l in Lessons.all():
			if Lessons.chooses_hero(l):
				lesson_id = str(l.id)
	var heroes := Lessons.pickable_heroes()
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(UI.banner("Choose Your Hero", 48, UI.GOLD, 0.0, 0.0, 1.8))
	root.add_child(_virgil_line())
	# The plaques: as wide as the screen allows (300 to 380 px), in a row that scrolls sideways when it must.
	var avail := 1800.0
	var w := clampf((avail - GAP * (heroes.size() - 1)) / maxf(1.0, heroes.size()), 300.0, 380.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for h in heroes:
		var b := _card(h, w)
		_cards[h] = b
		row.add_child(b)
	var content_w := w * heroes.size() + GAP * maxf(0.0, heroes.size() - 1.0)
	var scroll := ScrollContainer.new()
	scroll.name = "Heroes"
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(minf(content_w + 20.0, avail), CARD_H + 60.0)
	var pad := MarginContainer.new() # room for the ribbon under a plaque and the glow around it
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 44)
	pad.add_child(row)
	scroll.add_child(pad)
	root.add_child(scroll)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 30)
	root.add_child(bottom)
	var back := UI.button("Back", 280, 66)
	back.name = "Back"
	back.pressed.connect(go_back)
	bottom.add_child(back)
	_begin = UI.button("Begin the Trial", 420, 66)
	_begin.name = "Begin"
	_begin.pressed.connect(begin)
	bottom.add_child(_begin)
	var first := Game.lesson_hero
	if not first in heroes:
		first = str(Lessons.get_lesson(lesson_id).get("player", {}).get("hero", ""))
	if not first in heroes and not heroes.is_empty():
		first = heroes[0]
	choose(first, false)
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.5)


## Esc / the back gesture (Game.back): to the lessons screen.
func go_back() -> void:
	Game.go(Game.LESSONS)


## Virgil's small portrait and a line from him on parchment.
func _virgil_line() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(104, 120)
	holder.add_child(Virgil.portrait(Vector2(84, 108), false))
	row.add_child(holder)
	var say := UI.parchment_label("The Trial is yours alone. Choose who will walk it: each hero leads a class, and "
		+ "plays with that class's own starter deck.", 27, "italic", UI.INK, 0.0, 40, 16)
	var l := say.get_node("Text") as Label
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(980, 0)
	row.add_child(say)
	return row


## One hero's plaque `w` px wide: portrait, class, hero, tagline, hero power and starter deck.
func _card(hero: String, w: float) -> Button:
	var cls := CardDB.hero_class(hero)
	var info := CardDB.class_info(cls)
	var b := Button.new()
	b.name = "Hero_%s" % cls
	b.set_meta("hero", hero)
	b.custom_minimum_size = Vector2(w, CARD_H)
	b.focus_mode = Control.FOCUS_NONE
	var tints := {"normal": Color(0.95, 0.9, 0.82), "hover": Color(1.2, 1.08, 0.9), "pressed": Color(0.8, 0.7, 0.6)}
	for st in tints:
		b.add_theme_stylebox_override(st, UI.plaque_box(22, 14, tints[st]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.add_field(b, 6.0, Color(UI.FIELD.r * 0.8, UI.FIELD.g * 0.8, UI.FIELD.b * 0.8))
	b.pressed.connect(func(): _pressed(hero))
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -10.0))
	var room := w - 56.0
	var v := VBoxContainer.new()
	v.name = "Content"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_right = -22
	v.offset_top = 22
	v.offset_bottom = -14
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pw := minf(room * 0.62, 192.0)
	pc.custom_minimum_size = Vector2(0, pw * 1.25 + 18.0)
	var pf := Control.new()
	pf.custom_minimum_size = Vector2(pw, pw * 1.25)
	pf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(ClassInfoPanel.portrait(hero, Vector2(pw, pw * 1.25)))
	pc.add_child(pf)
	v.add_child(pc)
	var title := ClassInfoPanel.gilded(str(info.title), 36, room)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var name_l := UI.label(str(info.hero_name), 24, "italic", UI.BONE, 3, ClassInfoPanel.SHADE)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.fit_label(name_l, room, 16)
	v.add_child(name_l)
	var tag := ClassInfoPanel.text(str(info.tagline), 21, "italic", Color(0.95, 0.82, 0.55), room)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.max_lines_visible = 2
	v.add_child(tag)
	var hp: Dictionary = info.power
	var power := HBoxContainer.new()
	power.alignment = BoxContainer.ALIGNMENT_CENTER
	power.add_theme_constant_override("separation", 8)
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power.add_child(ClassInfoPanel.power_disc(info, 46.0))
	var pn := ClassInfoPanel.gilded(str(hp.get("name", "")), 21, room - 56.0)
	pn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	power.add_child(pn)
	v.add_child(power)
	var pt := ClassInfoPanel.text(str(hp.get("text", "")), 18, "body", UI.BONE, room)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.max_lines_visible = 3
	v.add_child(pt)
	var decks := CardDB.class_decks(cls)
	if not decks.is_empty():
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(gap)
		var dn := UI.label("Deck: %s" % decks[0].name, 18, "italic", Color(0.85, 0.78, 0.66), 3, ClassInfoPanel.SHADE)
		dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.fit_label(dn, room, 13)
		v.add_child(dn)
	var guide := ClassInfoPanel.info_button(44.0, "%s class guide" % info.title)
	guide.name = "Guide"
	guide.position = Vector2(w - 44.0 - 16.0, 16.0)
	guide.pressed.connect(func(): ClassInfoPanel.open(self, cls))
	b.add_child(guide)
	var rib := UI.ribbon("Your hero", 230, 30)
	rib.name = "Chosen"
	rib.position += Vector2(w / 2.0, CARD_H + 12.0)
	rib.visible = false
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rib)
	return b


## A press on a plaque: picks that hero; on the picked one again, begins.
func _pressed(hero: String) -> void:
	if hero == pick:
		begin()
	else:
		choose(hero)


## Picks `hero` (its plaque lights, the others dim).
func choose(hero: String, sound := true) -> void:
	if not _cards.has(hero):
		return
	pick = hero
	if sound:
		Sfx.play("ui_confirm", -4.0)
	for h in _cards:
		var b: Button = _cards[h]
		var on: bool = h == hero
		b.get_node("Chosen").visible = on
		b.get_node("Content").modulate = Color.WHITE if on else Color(0.8, 0.77, 0.72)
		b.self_modulate = Color.WHITE if on else Color(0.72, 0.68, 0.64)


## Starts The Trial with the picked hero (its class's starter deck).
func begin() -> void:
	if pick == "":
		return
	Sfx.play("ui_confirm", -4.0)
	Game.start_lesson(lesson_id, pick)


func _process(delta: float) -> void:
	_t += delta
	var b: Button = _cards.get(pick)
	if b != null:
		var k := 1.12 + 0.08 * sin(_t * 2.6)
		b.self_modulate = Color(k, k * 0.97, k * 0.88)
