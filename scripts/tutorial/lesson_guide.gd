class_name LessonGuide
extends Control
## Virgil in a lesson's battle: his portrait and his line on the painted tip plate, a bobbing arrow and a pulsing ring
## on what to do next, and the gate on the player's input. It walks the lesson's steps (data/lessons.json, see
## Lessons) in order:
## - "wait": "tap"  the line waits for a tap (anywhere); the board waits with it;
## - "do": {...}    the player must take that action; other actions are turned away with a nudge (hovering and
##                  reading cards always work), and only the taught card, minion or button glows;
## - "until": ...   free play until the turn ends, the match is won, any action ("act") or the opening hand is kept.
## Lines show when the board is idle on the player's turn (after the enemy's moves have played out), or during the
## opening-hand choice for "when": "mulligan" steps. The battle (battle_view.gd) calls on_idle, on_turn, on_mulligan,
## allows, performed, wants_tap and tap.

signal step_shown(index: int)

const PORTRAIT := Vector2(132, 168)
const PLATE_W := 520.0
const TEXT_PX := 27
const TYPE_RATE := 110.0 ## letters per second of the typewriter reveal

var battle: Node2D
var lesson: Dictionary
var steps: Array = []
var index := 0 ## the current step
var _shown := false ## the current step's line is on screen
var _complete := false ## the current step is done (the next one shows at the next idle moment)
var _collapsed := false
var _mulligan := false

var _box: Control ## portrait + plate
var _portrait: Control
var _plate: PanelContainer
var _text: Label
var _hint: Label
var _arrow: Sprite2D
var _ring: Sprite2D
var _mark: Sprite2D
var _ghost: TargetArrow ## the faint aiming arrow that shows a drag
var _t := 0.0
var _type: Tween
var _fade: Tween


func setup(p_battle: Node2D, p_lesson: Dictionary) -> LessonGuide:
	battle = p_battle
	lesson = p_lesson
	steps = lesson.get("steps", [])
	return self


func _ready() -> void:
	name = "LessonGuide"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring = _reticle()
	_mark = _reticle()
	_ghost = TargetArrow.new()
	_ghost.name = "Ghost"
	_ghost.visible = false
	add_child(_ghost)
	_arrow = Sprite2D.new()
	_arrow.texture = UiSkin.tex("arrow_head")
	if _arrow.texture != null:
		_arrow.scale = Vector2.ONE * 110.0 / _arrow.texture.get_width()
	_arrow.visible = false
	add_child(_arrow)
	_box = Control.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_plate = PanelContainer.new()
	_plate.add_theme_stylebox_override("panel", UI.tip_box())
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.gui_input.connect(_on_box_input)
	_box.add_child(_plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(v)
	_text = UI.label("", TEXT_PX, "body", UI.BONE, 3, Color(0.04, 0.01, 0.01))
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(PLATE_W - 100.0, 0)
	v.add_child(_text)
	_hint = UI.label("", 22, "italic", Color(0.95, 0.78, 0.45), 3, Color(0.04, 0.01, 0.01))
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)
	_portrait = Virgil.portrait(PORTRAIT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait.gui_input.connect(_on_box_input)
	_box.add_child(_portrait)
	_box.visible = false
	_box.modulate.a = 0.0


func _reticle() -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = UiSkin.tex("target_reticle")
	s.modulate = Color(1.0, 0.82, 0.4, 0.9)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = add
	s.visible = false
	add_child(s)
	return s


# ---------------------------------------------------------------- the battle's calls

func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


## The board is idle on the player's turn: moves on past finished steps and shows the current one.
func on_idle() -> void:
	_mulligan = false
	_advance()
	var s := current()
	if s.is_empty() or str(s.get("when", "")) == "mulligan":
		return
	if not _shown:
		_show_step()
	elif _collapsed and str(s.get("until", "")) == "win" and _turn_fresh:
		_expand()
	_turn_fresh = false


var _turn_fresh := false ## a new turn of the player's began: a free step's line comes back once


## A turn begins: Virgil steps aside while the enemy plays.
func on_turn(side: int) -> void:
	if side == 1:
		_hide_box()
		_hide_pointer()
	else:
		_turn_fresh = true


## The opening-hand choice is on screen: a "when": "mulligan" step shows now.
func on_mulligan() -> void:
	_mulligan = true
	_advance()
	if str(current().get("when", "")) == "mulligan" and not _shown:
		_show_step()


## True when the player may take `action` now ({act: play|attack|power|end|inspect, card, target uid}; an action whose
## aim has not ended yet has no "target" and is judged on the rest).
func allows(action: Dictionary) -> bool:
	if str(action.get("act", "")) == "inspect":
		return true
	# A finished step hands the rule to the next one (it shows as soon as the board is idle).
	var i := index + (1 if _complete else 0)
	var s: Dictionary = steps[i] if i < steps.size() else {}
	if s.is_empty():
		return true
	if str(s.get("wait", "")) == "tap":
		return false
	if not s.has("do"):
		return true
	return Lessons.matches(s.do, action, battle.st)


## True when `action` is the current step's action (the battle asks before an attack or a targeted card resolves, as
## the target may not survive it).
func hits(action: Dictionary) -> bool:
	var s := current()
	return not s.is_empty() and not _complete and s.has("do") and Lessons.matches(s.do, action, battle.st)


## The player took `action` (it was allowed and the rules accepted it); `hit` is hits(action) from before it resolved,
## or null to judge it now.
func performed(action: Dictionary, hit: Variant = null) -> void:
	var s := current()
	if s.is_empty() or _complete:
		return
	var act := str(action.get("act", ""))
	var done := false
	if s.has("do"):
		done = bool(hit) if hit != null else Lessons.matches(s.do, action, battle.st)
	else:
		match str(s.get("until", "")):
			"act":
				done = act != "inspect"
			"end_turn":
				done = act == "end"
			"mulligan":
				done = act == "mulligan"
			"win":
				if act != "inspect" and not _collapsed:
					_collapse()
	if done:
		_complete = true
		_hide_pointer()
		if act == "inspect":
			Sfx.play("tick", -8.0, 1.2)
		# The next line follows at once while the board stays idle (an inspect, or a step that waits for nothing).
		if act == "inspect" or act == "mulligan":
			if act == "mulligan":
				_hide_box()
			else:
				_advance()
				_show_step()


## A tap-to-continue line is up: the next press anywhere goes to Virgil, not to the board.
func wants_tap() -> bool:
	return _shown and not _complete and str(current().get("wait", "")) == "tap" and _box.visible


## The press that wants_tap() asked for: finishes the typing, else moves on.
func tap() -> void:
	if _type != null and _type.is_running():
		_type.kill()
		_text.visible_ratio = 1.0
		return
	_complete = true
	Sfx.play("page", -12.0)
	_advance()
	_show_step()


## Any press on the board: a passing remark ("until": "act") has been read.
func on_press() -> void:
	if _shown and not _complete and str(current().get("until", "")) == "act":
		_complete = true
		_hide_box()
		_advance()


## Virgil's line is on screen (the coach waits for him).
func talking() -> bool:
	return _shown and not _complete and _box.visible and _plate.visible and str(current().get("say", "")) != ""


## The player tried something else: Virgil's line comes back into view and the arrow bobs harder.
func nudge() -> void:
	if _collapsed:
		_expand()
	_box.pivot_offset = _box.size / 2.0
	var t := _box.create_tween()
	t.tween_property(_box, "scale", Vector2(1.05, 1.05), 0.08)
	t.tween_property(_box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	_t = 0.0


## The line on screen, for tests and screenshots ("" when none).
func line() -> String:
	return _text.text if _box.visible else ""


# ---------------------------------------------------------------- steps

func _advance() -> void:
	while _complete and index < steps.size():
		index += 1
		_complete = false
		_shown = false


func _show_step() -> void:
	var s := current()
	if s.is_empty():
		_hide_box()
		_hide_pointer()
		return
	if str(s.get("when", "")) == "mulligan" and not _mulligan:
		return
	_shown = true
	_collapsed = false
	var say := str(s.get("say", ""))
	if say == "":
		_hide_box()
	else:
		_text.text = say
		var tap := str(s.get("wait", "")) == "tap"
		_hint.text = ("%s to continue" % UI.tap_word()) if tap else ""
		_hint.visible = tap
		_plate.visible = true
		_plate.reset_size()
		_show_box()
		_text.visible_ratio = 0.0
		if _type != null:
			_type.kill()
		_type = create_tween()
		_type.tween_property(_text, "visible_ratio", 1.0, maxf(0.25, say.length() / TYPE_RATE))
		Sfx.play("page", -14.0, 1.05)
	_place_pointer(s)
	step_shown.emit(index)


func _show_box() -> void:
	_box.visible = true
	if _fade != null:
		_fade.kill()
	_fade = _box.create_tween()
	_fade.tween_property(_box, "modulate:a", 1.0, 0.2)


func _hide_box() -> void:
	if not _box.visible:
		return
	if _fade != null:
		_fade.kill()
	_fade = _box.create_tween()
	_fade.tween_property(_box, "modulate:a", 0.0, 0.18)
	_fade.tween_callback(_box.hide)


## Free play: the plate folds away and only Virgil's portrait stays (a tap on it brings the line back).
func _collapse() -> void:
	_collapsed = true
	_plate.visible = false
	_hide_pointer()


func _expand() -> void:
	_collapsed = false
	_plate.visible = true
	_show_box()
	_place_pointer(current())


func _on_box_input(e: InputEvent) -> void:
	var press: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or \
		(e is InputEventScreenTouch and e.pressed)
	if not press:
		return
	accept_event()
	if _collapsed:
		_expand()
	elif wants_tap():
		tap()
	elif str(current().get("until", "")) == "act" and not _complete:
		_complete = true
		Sfx.play("page", -12.0)
		_hide_box()
		_advance()


# ---------------------------------------------------------------- pointer

var _point := ""
var _mark_spec := ""


func _place_pointer(s: Dictionary) -> void:
	_point = str(s.get("point", ""))
	_mark_spec = str(s.get("mark", ""))
	_t = 0.0


func _hide_pointer() -> void:
	_point = ""
	_mark_spec = ""
	_arrow.visible = false
	_ring.visible = false
	_mark.visible = false
	_ghost.visible = false


## The node a pointer spec names in the battle, or null.
func target_node(spec: String) -> Node2D:
	if spec == "" or battle == null:
		return null
	match spec:
		"my_hero":
			return battle.heroes[0]
		"foe_hero":
			return battle.heroes[1]
		"power":
			return battle.heroes[0].power if battle.heroes[0] != null else null
		"end":
			return battle.end_btn
		"mana":
			return battle.mana_views[0]
	var parts := spec.split(":")
	if parts.size() != 2:
		return null
	var pool: Array = battle.hand_views[0] if parts[0] == "hand" else battle.board_views[0 if parts[0] == "mine" else 1]
	for n in pool:
		if is_instance_valid(n) and n.card_id == parts[1] and not n.is_queued_for_deletion():
			return n
	return null


## The ring's size around a target and where its centre sits (screen px).
func _target_rect(spec: String) -> Array:
	var n := target_node(spec)
	if n == null:
		return []
	var p := n.get_global_transform_with_canvas().origin
	var r := 150.0
	if spec.begins_with("hand:"):
		r = CardView.H * n.scale.y * 1.0
	elif spec.begins_with("mine:") or spec.begins_with("foe:"):
		r = MinionView.H * 1.25
	elif spec.ends_with("_hero"):
		r = HeroView.H * 1.3
	elif spec == "power":
		r = 140.0
	elif spec == "end":
		r = 270.0
	elif spec == "mana":
		p += Vector2(-60, 0)
		r = 300.0
	return [p, r]


func _process(delta: float) -> void:
	_t += delta
	var view := get_viewport_rect().size
	var pr := _target_rect(_point) if _point != "" else []
	var mr := _target_rect(_mark_spec) if _mark_spec != "" else []
	var pulse := 1.0 + 0.06 * sin(_t * 5.0)
	_ring.visible = not pr.is_empty()
	_arrow.visible = not pr.is_empty()
	if not pr.is_empty():
		var p: Vector2 = pr[0]
		var r: float = pr[1]
		_ring.position = p
		_ring.rotation = _t * 0.4
		if _ring.texture != null:
			_ring.scale = Vector2.ONE * r / _ring.texture.get_width() * pulse
		# The arrow above the target pointing down (below it, pointing up, near the top of the screen).
		var above := p.y > view.y * 0.3
		var bob := sin(_t * 5.0) * 12.0
		var gap := r * 0.5 + 46.0
		_arrow.position = p + Vector2(0, -gap - bob if above else gap + bob)
		_arrow.rotation = PI / 2 if above else -PI / 2
	_mark.visible = not mr.is_empty()
	if not mr.is_empty():
		_mark.position = mr[0]
		_mark.rotation = -_t * 0.4
		if _mark.texture != null:
			_mark.scale = Vector2.ONE * float(mr[1]) / _mark.texture.get_width() * pulse
		_mark.modulate = Color(1.0, 0.45, 0.3, 0.85)
	_tick_ghost(pr, mr)
	_layout_box(view, pr, mr)


## A drag to show: a faint aiming arrow grows from the card or minion to where it should go (the target, or the board
## for a minion card), again and again, the way the player's own arrow will look. It replaces the bobbing arrow.
func _tick_ghost(pr: Array, mr: Array) -> void:
	var want: Dictionary = current().get("do", {}) if not _complete else {}
	var act := str(want.get("act", ""))
	var dest = null
	if not pr.is_empty() and (act == "attack" or act == "play") and not battle.arrow.visible \
			and battle.drag_card == null:
		if not mr.is_empty():
			dest = mr[0]
		elif act == "play" and _point.begins_with("hand:"):
			var v: Vector2 = battle.V
			dest = battle.get_canvas_transform() * Vector2(v.x / 2.0, battle._board_y(0))
	_ghost.visible = dest != null
	if dest == null:
		return
	_arrow.visible = false
	var cycle := fmod(_t, 2.2)
	var k := clampf(cycle / 1.3, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	_ghost.from = pr[0]
	_ghost.to = (pr[0] as Vector2).lerp(dest, k)
	_ghost.valid = k > 0.97
	_ghost.modulate.a = 0.75 * (1.0 - clampf((cycle - 1.8) / 0.4, 0.0, 1.0))


## Virgil sits on the left of the board, beside the action: in the middle band, else higher or lower, wherever his
## plate covers the least of the board's pieces (minions, heroes, the hand) and never the pointer's target or the mark.
## During the opening hand he sits low, under the cards.
func _layout_box(view: Vector2, pr: Array, mr: Array) -> void:
	if not _box.visible:
		return
	var plate_sz := _plate.get_combined_minimum_size() if _plate.visible else Vector2.ZERO
	var w := PORTRAIT.x + 40.0 + plate_sz.x
	var h := maxf(PORTRAIT.y + 50.0, plate_sz.y)
	var x0 := 40.0 + PORTRAIT.x * 0.15
	var ys := [view.y * 0.47 - h / 2.0, view.y * 0.2, view.y - h - 200.0]
	if _mulligan:
		ys = [view.y - h - 24.0]
	var avoid := _pieces(view)
	var pick: float = ys[0]
	var best := INF
	for y in ys:
		var rect := Rect2(x0 - 20.0, y - 10.0, w + 30.0, h + 20.0)
		var cost := 0.0
		for a in avoid:
			cost += rect.intersection(a).get_area()
		for t in [pr, mr]:
			if not t.is_empty() and rect.grow(float(t[1]) * 0.35).has_point(t[0]):
				cost += 1e7
		if cost < best - 1.0:
			best = cost
			pick = y
	_box.position = _box.position.lerp(Vector2(x0, pick), 1.0 if _box.position == Vector2.ZERO else 0.2)
	_portrait.position = Vector2(0, (h - PORTRAIT.y) / 2.0 - 14.0)
	_plate.position = Vector2(PORTRAIT.x + 40.0, (h - plate_sz.y) / 2.0)
	_box.size = Vector2(w, h)


## Screen rectangles of what Virgil should not cover: every minion, both heroes and the hand.
func _pieces(view: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side in 2:
		for m in battle.board_views[side]:
			if is_instance_valid(m):
				var p: Vector2 = m.get_global_transform_with_canvas().origin
				out.append(Rect2(p - Vector2(MinionView.W, MinionView.H) * 0.6, Vector2(MinionView.W, MinionView.H) * 1.2))
		if battle.heroes[side] != null:
			var hp: Vector2 = battle.heroes[side].get_global_transform_with_canvas().origin
			out.append(Rect2(hp - Vector2(HeroView.W * 0.7, HeroView.H * 0.7), Vector2(HeroView.W, HeroView.H) * 1.4))
	out.append(Rect2(view.x / 2.0 - 600.0, view.y - 150.0, 1200.0, 150.0))
	return out
