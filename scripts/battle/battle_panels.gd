class_name BattlePanels
extends Control
## The battle's side panels, in the free band left of the board, each one a lane of that band (PANELS, left to right).
## The player switches each one on or off in Options (Settings.panels); the battle lays them out again at once.
##   log      the match history (BattleLog): the last actions as small portraits, newest on top, and a disc that opens
##            the whole log (BattleLogPanel). Resting the pointer on a portrait (a tap on a touch screen) shows what
##            happened: the card big in the next lane with the line under it.
##   inspect  the card the player is looking at, big: the hand card under the pointer or the finger, the minion
##            rested on or tapped. On a phone a card on the board is tiny; here it can be read.
## A lane with a fixed width (`lane` > 0) takes that much; the one with `lane` 0 takes what is left. A new panel is one
## more entry (and its Settings default) plus what it shows.
##
## Nothing here runs every frame: the strip changes when the log does, the big card when the focus does. Input comes
## from the battle (`press`, `hover`): the panels never take the mouse themselves, so a drag across them still plays.

const PANELS := [
	{"id": "log", "name": "Log", "lane": 92.0, "default": true},
	{"id": "inspect", "name": "Zoom", "lane": 0.0, "default": true},
]
const ICON := 72.0 ## a portrait of the strip
const ICON_GAP := 10.0
const MAX_ICONS := 10
const TOP := 92.0 ## under the Menu plate
const MARGIN := 14.0
const LANE_GAP := 6.0
const BUTTON := 64.0 ## the disc that opens the whole log
const MINE := Color(0.82, 0.95, 1.2) ## the ring of my actions: cool bronze
const THEIRS := Color(1.3, 0.72, 0.6) ## the opponent's: heated red
const RUSE := Color(1.5, 1.25, 0.55) ## an action whose Ruse went off: bright gold
const INK_MINE := Color(0.1, 0.2, 0.45) ## my lines on parchment (blue-black ink)
const CARD_FX := preload("res://assets/shaders/card_fx.gdshader")

signal open_log

var history: BattleLog
var band := Rect2() ## the whole free band
var lanes := {} ## panel id -> Rect2 (on screen), only the panels that are on
var show_rect := Rect2() ## where a big card goes: the inspect lane, or the room right of the strip
var _strip: Control
var _icons: Array[Control] = [] ## newest first
var _button: Button
var _show: Control ## the big card (and the log line) on show, or null
var _show_key := ""
var _hand_id := "" ## the hand card in focus
var _unit_id := "" ## the minion in focus
var _unit_live = null ## its BattleState.Unit (current numbers)
var _detail: Control ## the strip portrait whose action is on show (null: none)
var _sticky := false ## the action was tapped (stays until the next tap)

static var _thumbs := {} ## card / hero id -> a small square ImageTexture of its art
static var _mask: ShaderMaterial


static func on(id: String) -> bool:
	return Settings.panel_on(id)


func setup(p_log: BattleLog) -> BattlePanels:
	name = "Panels"
	history = p_log
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strip = Control.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_button = UI.disc(Loc.t("Battle log"), Callable(), "icon_quest", BUTTON)
	_button.name = "LogButton"
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE # pressed through `press`
	add_child(_button)
	history.entry_added.connect(_on_added)
	history.entry_changed.connect(_on_changed)
	return self


## Lays the lanes out in the band left of x = `right`, from TOP down to y = `bottom` (screen coordinates).
func layout(right: float, bottom: float) -> void:
	band = Rect2(MARGIN, TOP, maxf(0.0, right - MARGIN), maxf(0.0, bottom - TOP))
	lanes.clear()
	var x := band.position.x
	var fixed := x
	for p in PANELS:
		if not on(p.id):
			continue
		var w: float = p.lane if p.lane > 0.0 else maxf(0.0, band.end.x - x)
		lanes[p.id] = Rect2(x, band.position.y, w, band.size.y)
		x += w + LANE_GAP
		if p.lane > 0.0:
			fixed = x
	show_rect = lanes.get("inspect", Rect2(fixed, band.position.y, maxf(0.0, band.end.x - fixed), band.size.y))
	_strip.visible = lanes.has("log")
	_button.visible = lanes.has("log")
	if lanes.has("log"):
		var r: Rect2 = lanes.log
		_button.position = Vector2(r.get_center().x - BUTTON / 2.0, r.end.y - BUTTON)
		_place_icons(false)
	else:
		_hide_detail()
	if not lanes.has("inspect"):
		_hand_id = ""
		_unit_id = ""
	_refresh_show()


## How many portraits fit the strip above its disc.
func icon_room() -> int:
	if not lanes.has("log"):
		return 0
	return clampi(int((lanes.log.size.y - BUTTON - 12.0 + ICON_GAP) / (ICON + ICON_GAP)), 0, MAX_ICONS)


## What the band covers on screen (the battle keeps its pop-up cards and tips off it).
func covered() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if visible and lanes.has("log"):
		out.append(lanes.log)
	if visible and _show != null and is_instance_valid(_show) and _show.has_meta("used"):
		out.append(_show.get_meta("used"))
	return out


# ---------------------------------------------------------------- input (from the battle)

## A press at screen point `p`: a portrait shows (or hides) its action, the disc opens the log. True when it was ours.
func press(p: Vector2) -> bool:
	if not visible:
		return false
	if _button.visible and Rect2(_button.position, _button.size).grow(6.0).has_point(p):
		_hide_detail()
		Sfx.play("page", -6.0)
		open_log.emit()
		return true
	var ic := _icon_at(p)
	if ic != null:
		if ic == _detail and _sticky:
			_hide_detail()
		else:
			_show_detail(ic)
			_sticky = true
		return true
	if _sticky:
		_hide_detail()
	return false


## The pointer moved to `p` (a mouse: touch screens have no hover).
func hover(p: Vector2) -> void:
	if not visible or _sticky:
		return
	var ic := _icon_at(p)
	if ic == _detail:
		return
	if ic != null:
		_show_detail(ic)
	else:
		_hide_detail()


func _icon_at(p: Vector2) -> Control:
	if not _strip.visible:
		return null
	for ic in _icons:
		if ic.has_meta("gone"):
			continue
		var at: Vector2 = ic.get_meta("home", ic.position)
		if Rect2(at, Vector2(ICON, ICON)).grow(ICON_GAP / 2.0).has_point(p):
			return ic
	return null


# ---------------------------------------------------------------- the strip

func _on_added(e: Dictionary) -> void:
	if not e.strip:
		return
	var ic := make_icon(e, ICON)
	ic.set_meta("seq", e.seq)
	_strip.add_child(ic)
	_icons.push_front(ic)
	ic.pivot_offset = Vector2(ICON, ICON) / 2.0
	ic.scale = Vector2(0.2, 0.2)
	ic.modulate.a = 0.0
	_place_icons(true)
	var t := ic.create_tween().set_parallel(true)
	t.tween_property(ic, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(ic, "modulate:a", 1.0, 0.15)


func _on_changed(e: Dictionary) -> void:
	for ic in _icons:
		if int(ic.get_meta("seq", -1)) == int(e.seq):
			_badges(ic, e, ICON)
			if ic == _detail:
				_show_detail(ic) # its line grew (the blow's damage, a death)
			return


## Each portrait to its row (newest on top); the ones past the room fade out and go.
func _place_icons(animate: bool) -> void:
	if not lanes.has("log"):
		return
	var r: Rect2 = lanes.log
	var room := icon_room()
	var keep: Array[Control] = []
	for i in _icons.size():
		var ic := _icons[i]
		if i >= room:
			if ic == _detail:
				_hide_detail()
			ic.set_meta("gone", true)
			var t := ic.create_tween()
			t.tween_property(ic, "modulate:a", 0.0, 0.2)
			t.tween_callback(ic.queue_free)
			continue
		keep.append(ic)
		var home := Vector2(r.get_center().x - ICON / 2.0, r.position.y + i * (ICON + ICON_GAP))
		ic.set_meta("home", home)
		if animate and ic.position != Vector2.ZERO:
			ic.create_tween().tween_property(ic, "position", home, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			ic.position = home
	_icons = keep


## A round portrait of entry `e`, `px` wide: the card's art (the hero's for the hero power, fatigue and the end) in a
## bronze ring tinted by side, with the action's badge. Takes no input.
static func make_icon(e: Dictionary, px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size = c.custom_minimum_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.name = "Art"
	var hero_pic: bool = str(e.card) == ""
	art.texture = thumb(str(e.hero) if hero_pic else str(e.card), hero_pic)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = Vector2(px, px) * 0.78
	art.position = Vector2(px, px) * 0.11
	art.material = _round_mask()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(art)
	if UiSkin.has("class_emblem_frame"):
		var ring := UiSkin.rect("class_emblem_frame", Vector2(px, px))
		ring.name = "Ring"
		ring.use_parent_material = false
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		c.add_child(ring)
	_badges(c, e, px)
	return c


## The ring's tint and the badges of portrait `c` (again when its entry changes: a Ruse, a kill).
static func _badges(c: Control, e: Dictionary, px: float) -> void:
	var ring := c.get_node_or_null("Ring") as Control
	if ring != null:
		ring.modulate = RUSE if e.ruse else (MINE if int(e.side) == 0 else THEIRS)
	for n in c.get_children():
		if str(n.name).begins_with("Badge"):
			n.free()
	var b := px * 0.42
	match str(e.kind):
		"play":
			var cost := int(CardDB.card(str(e.card)).get("cost", 0))
			var gem := Control.new()
			gem.name = "BadgeCost"
			gem.size = Vector2(b, b)
			gem.position = Vector2(-b * 0.12, -b * 0.12)
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if UiSkin.has("gem_mana"):
				gem.add_child(UiSkin.rect("gem_mana", gem.size))
			var l := UI.raised(UI.label("", roundi(b * 0.58), "title", UI.NUMBER, 4, Color(0, 0.02, 0.08)))
			l.text = str(cost)
			l.size = gem.size
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UI.center_ink(l)
			gem.add_child(l)
			c.add_child(gem)
		"attack":
			_badge(c, "icon_fight", b)
		"power":
			_badge(c, str(CardDB.hero(str(e.hero)).get("power_icon", "icon_trigger")), b, true)
		"trigger":
			_badge(c, "icon_trigger", b)
		"fatigue", "burn":
			_badge(c, "icon_ash", b)
		"over":
			_badge(c, "icon_deathrattle", b)
	if int(e.kills) > 0 and str(e.kind) != "over":
		var k := _badge(c, "icon_deathrattle", b * 0.8)
		k.name = "BadgeKill"
		k.position = Vector2(px - b * 0.8 * 0.85, -b * 0.8 * 0.15)


static func _badge(c: Control, icon: String, b: float, disc: bool = false) -> Control:
	var holder := Control.new()
	holder.name = "Badge"
	holder.size = Vector2(b, b)
	holder.position = c.size - Vector2(b, b) * 0.85
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if disc and UiSkin.has("power_disc"):
		holder.add_child(UiSkin.rect("power_disc", holder.size))
	if UiSkin.has(icon):
		var k := b * (0.72 if disc else 1.0)
		var r := UiSkin.rect(icon, Vector2(k, k), (holder.size - Vector2(k, k)) / 2.0)
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		holder.add_child(r)
	c.add_child(holder)
	return holder


## The round mask every portrait shares (card_fx's oval on a square is a circle).
static func _round_mask() -> ShaderMaterial:
	if _mask == null:
		_mask = ShaderMaterial.new()
		_mask.shader = CARD_FX
		_mask.set_shader_parameter("mask_mode", 1)
	return _mask


## A small square crop of a card's (or a hero's) art, made once per id: the strip never samples the full painting.
static func thumb(id: String, hero: bool = false) -> Texture2D:
	var key := ("hero:" if hero else "") + id
	if _thumbs.has(key):
		return _thumbs[key]
	var tex := CardDB.hero_art(id) if hero else CardDB.art(id)
	var out: Texture2D = tex
	var img := tex.get_image() if tex != null else null
	if img != null:
		if img.is_compressed():
			img.decompress()
		var s := mini(img.get_width(), img.get_height())
		var y := clampi(int(img.get_height() * (0.3 if hero else 0.34) - s / 2.0), 0, img.get_height() - s)
		img = img.get_region(Rect2i((img.get_width() - s) / 2, y, s, s))
		img.resize(128, 128, Image.INTERPOLATE_CUBIC)
		out = ImageTexture.create_from_image(img)
	_thumbs[key] = out
	return out


# ---------------------------------------------------------------- the big card

## The hand card in focus ("" for none): held, dragged or under the pointer.
func focus_hand(id: String) -> void:
	if id == _hand_id:
		return
	_hand_id = id if lanes.has("inspect") else ""
	_refresh_show()


## A minion (or "" to let go of it) to show with its current numbers (`live`: its BattleState.Unit). Returns the
## card's rect on screen (empty when nothing is shown), so the battle can set the keyword tips beside it.
func focus_unit(id: String, live = null) -> Rect2:
	_unit_id = id if lanes.has("inspect") else ""
	_unit_live = live
	if _unit_id != "":
		_hand_id = "" # looking at a minion now (the hand's own focus comes back when a hand card is pointed at)
	_refresh_show()
	if _unit_id != "" and _show != null and _show.has_meta("card_rect") and _detail == null and _hand_id == "":
		return _show.get_meta("card_rect")
	return Rect2()


func _show_detail(ic: Control) -> void:
	if _detail != ic:
		_lift(_detail, false)
		_lift(ic, true)
	_detail = ic
	_refresh_show(true)


func _hide_detail() -> void:
	_sticky = false
	if _detail != null:
		_lift(_detail, false)
		_detail = null
		_refresh_show()


## The portrait on show stands out a little from the strip.
static func _lift(ic: Control, up: bool) -> void:
	if ic == null or not is_instance_valid(ic) or ic.has_meta("gone"):
		return
	ic.create_tween().tween_property(ic, "scale", Vector2.ONE * (1.14 if up else 1.0), 0.1)


## Shows what has the focus: a log action first, then the hand card, then the minion.
func _refresh_show(force: bool = false) -> void:
	var key := ""
	var e: Dictionary = {}
	if _detail != null and is_instance_valid(_detail):
		for x in history.entries:
			if int(x.seq) == int(_detail.get_meta("seq", -1)):
				e = x
		key = "log:%d" % int(_detail.get_meta("seq", -1))
	elif _hand_id != "":
		key = "hand:" + _hand_id
	elif _unit_id != "":
		key = "unit:%s:%s" % [_unit_id, _live_print()]
	if key == _show_key and not force:
		return
	_show_key = key
	if _show != null and is_instance_valid(_show):
		var old := _show
		old.name = "ShowOld"
		var t := old.create_tween()
		t.tween_property(old, "modulate:a", 0.0, 0.12)
		t.tween_callback(old.queue_free)
	_show = null
	if key == "" or show_rect.size.x < 120.0:
		return
	if key.begins_with("log:"):
		if e.is_empty():
			return
		_show = _build_show(str(e.card), e.get("hero", ""), null, e)
	elif key.begins_with("hand:"):
		_show = _build_show(_hand_id, "", null, {})
	else:
		_show = _build_show(_unit_id, "", _unit_live, {})
	_show.name = "Show"
	add_child(_show)
	_show.modulate.a = 0.0
	_show.create_tween().tween_property(_show, "modulate:a", 1.0, 0.1)


func _live_print() -> String:
	if _unit_live == null:
		return ""
	return "%d/%d/%d/%s/%s/%s" % [_unit_live.attack, _unit_live.health, _unit_live.max_health, _unit_live.frozen,
		_unit_live.silenced, _unit_live.keywords.keys()]


## The big card in the show area: card `id` (or hero `hero` when id is ""), and for a log action its lines on a
## parchment under it. The control covers the area it uses; its meta "card_rect" is the card's rect on screen.
func _build_show(id: String, hero: String, live, e: Dictionary) -> Control:
	var area := show_rect
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = area.position
	root.size = area.size
	var caption: Control = null
	var cap_h := 0.0
	if not e.is_empty():
		caption = _caption(e, maxf(area.size.x, 380.0))
		caption.reset_size()
		cap_h = caption.size.y + 12.0
	var room_h := area.size.y - cap_h
	var card_h := 0.0
	var card_rect := Rect2()
	if id != "" and not CardDB.card(id).is_empty():
		var k := minf(minf((area.size.x - 8.0) / CardView.W, room_h / CardView.H), 1.6)
		if k >= 0.45:
			card_h = CardView.H * k
			var c := CardView.new().setup(id, -1, true)
			c.auto_tilt = false
			c.scale = Vector2(k, k)
			if live != null:
				c.set_stats(live.attack, live.health, live.max_health)
			root.add_child(c)
			c.set_meta("k", k)
			root.set_meta("view", c)
	elif hero != "":
		var ph := minf((area.size.x - 60.0) / 0.85, minf(room_h - 30.0, 300.0)) # an upright oval, 0.85 x its height
		if ph >= 90.0:
			card_h = ph + 20.0
			var p := ClassInfoPanel.portrait(hero, Vector2(ph * 0.85, ph))
			root.add_child(p)
			root.set_meta("view", p)
	# The block (card above, line under it) centred in the area's height, the card on the area's middle.
	var block := card_h + cap_h
	var top := maxf(0.0, (area.size.y - block) / 2.0)
	var view = root.get_meta("view", null)
	if view is CardView:
		var k: float = view.get_meta("k")
		view.position = Vector2(area.size.x / 2.0, top + CardView.H * k / 2.0)
		card_rect = Rect2(area.position + view.position - Vector2(CardView.W, CardView.H) * k / 2.0,
			Vector2(CardView.W, CardView.H) * k)
	elif view is Control:
		view.position = Vector2((area.size.x - view.custom_minimum_size.x) / 2.0, top + 10.0)
	var used := card_rect if card_rect.has_area() else Rect2(area.position + Vector2(0, top), Vector2(area.size.x, card_h))
	if caption != null:
		caption.position = Vector2(0.0, top + card_h + (12.0 if card_h > 0.0 else 0.0))
		root.add_child(caption)
		used = used.merge(Rect2(area.position + caption.position, caption.size))
	root.set_meta("card_rect", card_rect)
	root.set_meta("used", used)
	return root


## An action's lines inked on parchment: the headline in the side's ink, its results under it.
func _caption(e: Dictionary, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.tip_box())
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var inner := w - 2.0 * UI.TIP_PAD_X
	var head := UI.label("", 24, "title", side_ink(int(e.side)))
	head.text = history.headline(e)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(inner, 0)
	v.add_child(head)
	var extra := PackedStringArray()
	if e.ruse:
		extra.append(Loc.t("Ruse"))
	if str(e.kind) == "power":
		var h := CardDB.hero(str(e.hero))
		extra.append(str(h.get("power", {}).get("text", "")))
	for t in extra + history.lines(e):
		var l := UI.label("", 22, "italic", UI.INK)
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(inner, 0)
		v.add_child(l)
	return p


## The ink of a side's lines on parchment (mine blue-black, the opponent's crimson, the match's end plain ink).
static func side_ink(side: int) -> Color:
	return INK_MINE if side == 0 else (UI.INK_RED if side == 1 else UI.INK)
