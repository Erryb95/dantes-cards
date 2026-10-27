class_name Coach
extends Control
## First-game tips: a parchment bubble with a bobbing arrow that points at the thing to try next (play a card,
## attack, hero power, Guard, end turn), and the first time a keyword or a trigger shows up on the board, what it
## means ("kw_<keyword>", the text of UI.KEYWORD_HELP). Each tip shows once ever (Settings.coach_seen) and goes away
## on the next press. Never shown in tests or tooling runs; `-- --coach` shows them anyway without marking them seen.
## In Virgil's trial (lesson_mode) every tip shows once in the match, seen before or not.

const TIPS := {
	"play": "Drag a glowing card from your hand up here to play it. It costs the mana shown in its corner.",
	"attack": "Your minion is ready. Drag from it to an enemy to attack - each minion attacks once per turn.",
	"guard": "Guard: while this minion stands, your attacks must hit it first.",
	"power": "Your hero power: {tap} it to use it, once per turn.",
	"end": "Nothing left to do? End your turn.",
}

var _bubble: PanelContainer
var _arrow: Sprite2D
var _label: Label
var _target := Vector2.ZERO
var _t := 0.0
var _id := ""
var _forced := false
var enabled := true ## false: no tips at all (Virgil's scripted lessons, where he does the talking)
var _session: Array = [] ## lesson_mode: the tips already shown in this match
var _per_match := false
var _fade: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_forced = "--coach" in OS.get_cmdline_user_args()
	enabled = _forced or not Game.debug_run()
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", UI.tip_box())
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UI.label("", 26, "body", UI.BONE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(380, 0)
	_bubble.add_child(_label)
	add_child(_bubble)
	_arrow = Sprite2D.new()
	_arrow.texture = UiSkin.tex("arrow_head")
	if _arrow.texture != null:
		_arrow.scale = Vector2.ONE * 120.0 / _arrow.texture.get_width()
	add_child(_arrow)
	visible = false
	modulate.a = 0.0


func showing() -> bool:
	return visible and _id != ""


## True on a phone or tablet, where the tips say "tap" (the same test as SkipRing; "click" on desktop).
static func _touch() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


## Virgil's trial: every tip once in this match, whether the player saw it before or not (and seen from then on).
func lesson_mode() -> void:
	_per_match = true


## Whether tip `id` would show now (not seen yet, or not yet in this match in lesson_mode).
func fresh(id: String) -> bool:
	if not enabled:
		return false
	if _per_match:
		return not _session.has(id)
	return _forced or not Settings.coach_seen.has(id)


## Shows tip `id` pointing at `target` (screen position) unless it was seen already. Returns true when shown.
## `text` replaces the tip's own text (the keyword tips bring theirs).
func offer(id: String, target: Vector2, text: String = "") -> bool:
	if showing() or not fresh(id):
		return false
	_id = id
	_target = target
	_label.text = (text if text != "" else str(TIPS[id])).format({"tap": "tap" if _touch() else "click"})
	_session.append(id)
	if not _forced and not Settings.coach_seen.has(id):
		Settings.coach_seen.append(id)
		Settings.save()
	_bubble.reset_size()
	_fade_to(1.0, 0.3)
	visible = true
	Sfx.play("tick", -10.0)
	return true


func dismiss() -> void:
	if not showing():
		return
	_id = ""
	_fade_to(0.0, 0.2)
	_fade.tween_callback(hide)


## One fade at a time: a tip offered while the last one is still fading out must not be hidden by that fade.
func _fade_to(alpha: float, time: float) -> void:
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, time)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var view := get_viewport_rect().size
	var bs := _bubble.size
	# The bubble sits above the target (below it when the target is near the top), clamped on screen; the arrow
	# bobs between the two, pointing at the target.
	var above := _target.y > bs.y + 200.0
	var bob := sin(_t * 5.0) * 10.0
	var tip := _target + Vector2(0, (-90.0 if above else 90.0) + (bob if above else -bob))
	_arrow.position = tip
	_arrow.rotation = PI / 2 if above else -PI / 2
	var pos := Vector2(_target.x - bs.x / 2, tip.y - 40.0 - bs.y if above else tip.y + 40.0)
	_bubble.position = pos.clamp(Vector2(20, 20), view - bs - Vector2(20, 20))
