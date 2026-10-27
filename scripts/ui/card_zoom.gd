class_name CardZoom
## A card shown large: `open` lays it over a dim veil with its name, flavour and keyword tips on a plate beside it
## (the collection, the deck list of Choose your path; any press closes it); `peek` shows it big beside a small card
## the pointer rests on, with its keyword tips, and takes no input.


## The card `id` big over a veil, added to `parent`; a press anywhere closes it (frees it). Returns the veil.
static func open(parent: Node, id: String) -> Control:
	var zoom := ColorRect.new()
	zoom.name = "CardZoom"
	zoom.color = Color(0, 0, 0, 0.75)
	zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom.z_index = 110 # above the dialogs (the deck list opens it over its own panel)
	parent.add_child(zoom)
	var vs := zoom.get_viewport_rect().size
	var c := CardView.new().setup(id, -1, true)
	c.position = Vector2(vs.x * 0.4, vs.y / 2)
	c.scale = Vector2(0.6, 0.6)
	zoom.add_child(c)
	c.create_tween().tween_property(c, "scale", Vector2(1.9, 1.9) * minf(1.0, vs.y / 1080.0), 0.18).set_trans(Tween.TRANS_BACK)
	var card := CardDB.card(id)
	# The name and flavour on a framed plate beside the card.
	var w := minf(620.0, vs.x * 0.34)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.tip_box())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size = Vector2(w, 0)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pv)
	var name_l := UI.label(str(card.get("name", "")), 34, "title", UI.GOLD, 4, Color.BLACK)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(name_l)
	var flavor := str(card.get("flavor", ""))
	if flavor != "":
		var info := UI.label(flavor, 28, "italic", UI.BONE, 3, Color.BLACK)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(w - 100, 0)
		pv.add_child(info)
	var holder := CenterContainer.new()
	holder.position = Vector2(vs.x * 0.58, 0)
	holder.size = Vector2(w + 40, vs.y)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under the plate, a tip for each keyword the card uses (Guard, Last Breath, Freeze...).
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(plate)
	var tips := UI.tip_column(card, false, w - 100.0)
	if tips != null:
		side.add_child(tips)
	holder.add_child(side)
	zoom.add_child(holder)
	Sfx.play("page", -6.0)
	zoom.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			zoom.accept_event()
			zoom.queue_free())
	return zoom


## The card `id` drawn `scale` x big with its centre at `at` (the parent's coordinates), its keyword tips in a column
## on the side `side` (1 right, -1 left). Takes no input; free it to hide it.
static func peek(parent: Control, id: String, at: Vector2, k: float, side: int = 1) -> Control:
	var root := Control.new()
	root.name = "Peek"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 60
	parent.add_child(root)
	var c := CardView.new().setup(id, -1, true)
	c.auto_tilt = false
	c.position = at
	c.scale = Vector2.ONE * k * 0.8
	c.modulate.a = 0.0
	root.add_child(c)
	var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE * k, 0.16)
	t.tween_property(c, "modulate:a", 1.0, 0.1)
	var tips := UI.tip_column(CardDB.card(id), false, 300.0)
	if tips != null:
		tips.reset_size()
		var half := CardView.W * k / 2.0
		tips.position = Vector2(at.x + side * (half + 14.0) - (tips.size.x if side < 0 else 0.0),
			at.y - CardView.H * k / 2.0 + 10.0)
		root.add_child(tips)
	return root
