extends Node
## Screenshots of the screens and overlays the plain `--snap` cannot reach (options, pause, banners, damage numbers,
## the legendary cut-in, the result, the collection zoom, the pack reveal, a filled deck), for the painted-UI audit.
##   Godot --path . res://tests/screen_audit.tscn --resolution 1920x1080 -- --out=<dir> --what=<mode>
## Modes: menu (the title screen; `--named` with a player name), menu_living (Francesca, a card with looping art, put in the showcase: two shots a second apart), menu_rotate (the title screen's showcase after a
## rotation: shots before and after, and a frame sequence of a burn swap and a flip swap in <out>/seq_burn, seq_flip),
## profile (the profile panel; `--named`),
## profile_error (an invalid name typed), menu_options, credits, builder, builder_name, builder_long, builder_empty, builder_leave, builder_edit,
## builder_delete, builder_tip, collection_zoom, collection_class (the class strip and a keyword chip's tip),
## collection_guide, collection_neutral, deck_peek (a key card shown big), deck_list (View cards), deck_list_zoom,
## deck_guide (the class guide), packs_reveal, packs_empty, packs_rates (the drop-rates sheet), collection_sort
## (`--sort=<id of the collection's SORTS>` on the `--filter=` set, default all, most cards owned), deck_tip,
## battle (several shots), lessons (Virgil's lessons screen), howto (every How to Play chapter), offer (the
## first-launch question), lesson (`--lesson=<id> [--steps=0,3]`: every line of a lesson played through, and its
## result), lesson_pause.
## `--cls=` also picks the class of collection_class / collection_guide / deck_guide.
## `--cls=<class>`: the class of the deck in the "builder" shot (default Pilgrim).

const LessonDriver := preload("res://tests/lesson_driver.gd")

var out := "user://audit"
var what := "battle"
var cls := "pilgrim"
var sort_id := "rarity"
var filter := "all"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--what="):
			what = a.substr(7)
		elif a.begins_with("--cls="):
			cls = a.substr(6)
		elif a.begins_with("--sort="):
			sort_id = a.substr(7)
		elif a.begins_with("--filter="):
			filter = a.substr(9)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.fast_animations = false
	# `--out=` is not one of the flags that skip the first-launch cinematic: on a fresh profile the main menu would
	# jump to the intro and the menu shots would hang.
	Game.intro_played = true
	match what:
		"menu", "profile", "profile_error":
			Settings.player_name = "Farinata" if "--named" in OS.get_cmdline_user_args() else ""
			var s: Node = load("res://scenes/main_menu.tscn").instantiate()
			get_tree().root.add_child.call_deferred(s)
			await get_tree().process_frame
			get_tree().current_scene = s
			await _wait(1.6)
			if what != "menu":
				var p: ProfilePanel = s.open_profile()
				await _wait(0.4)
				if what == "profile_error":
					p.field.grab_focus()
					p.field.text = "No!"
					p.field.text_changed.emit(p.field.text)
					p.field.caret_column = 3
					p.save()
				await _wait(0.4)
			await _snap(what)
		"menu_rotate":
			var s: Node = load("res://scenes/main_menu.tscn").instantiate()
			get_tree().root.add_child.call_deferred(s)
			await get_tree().process_frame
			get_tree().current_scene = s
			await _wait(1.8)
			print("showcase before: ", s.showcase_ids())
			await _snap("menu_rotate_0")
			for style in ["burn", "flip"]:
				var dir := "%s/seq_%s" % [out, style]
				DirAccess.make_dir_recursive_absolute(dir)
				var slot: int = s.rotate_now(1, false, style)
				var n := 0
				var done := [false]
				s.swapped.connect(func(_i): done[0] = true, CONNECT_ONE_SHOT)
				while not done[0] and n < 200:
					await _wait(1.0 / 20.0)
					get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [dir, n])
					n += 1
				print("showcase after %s on slot %d (%d frames): " % [style, slot, n], s.showcase_ids())
				await _wait(0.8)
				await _snap("menu_rotate_" + style)
			await _wait(0.5)
			await _snap("menu_rotate")
		"menu_living":
			# A card with looping ("living") art in the showcase goes through the same CardView path: its video plays.
			var s: Node = load("res://scenes/main_menu.tscn").instantiate()
			get_tree().root.add_child.call_deferred(s)
			await get_tree().process_frame
			get_tree().current_scene = s
			await _wait(1.5)
			s._replace(1, "francesca", true)
			await _wait(2.0)
			await _snap("menu_living_a")
			await _wait(0.9)
			await _snap("menu_living_b")
			print("looping art on the showcase card: ", s._showcase[1].find_children("*", "ArtLoop", true, false).size(), " player(s)")
		"menu_options", "credits":
			# The title screen as the current scene, so Options shows its title-screen row (Watch intro, Credits).
			var s: Node = load("res://scenes/main_menu.tscn").instantiate()
			get_tree().root.add_child.call_deferred(s) # the root is still setting up its children
			await get_tree().process_frame
			get_tree().current_scene = s
			await _wait(1.6)
			var o := OptionsPanel.new()
			s.add_child(o)
			await _wait(0.5)
			if what == "credits":
				s.add_child(CreditsPanel.new())
				await _wait(0.5)
			await _snap(what)
			if what == "credits": # the end of the list
				var sc: ScrollContainer = s.find_children("*", "ScrollContainer", true, false)[0]
				sc.scroll_vertical = 100000
				await _wait(0.3)
				await _snap("credits_end")
		"builder":
			Game.edit_deck = -1
			Game.new_deck_cls = cls
			var s := _open("res://scenes/deck_builder.tscn")
			await _wait(0.6)
			Collection.autofill(s.deck)
			s._refresh()
			s._problem.text = "Your deck can hold at most two copies of a card."
			s._problem_plate.visible = true
			s._name.release_focus()
			await _wait(0.6)
			await _snap("builder")
		"builder_name", "builder_long", "builder_empty", "builder_leave", "builder_edit", "builder_delete", "builder_tip":
			await _builder(what)
		"collection_zoom":
			var s := _open("res://scenes/collection.tscn")
			await _wait(0.8)
			s._show_zoom("francesca")
			await _wait(0.6)
			await _snap("collection_zoom")
		"collection_class", "collection_guide", "collection_neutral":
			var s := _open("res://scenes/collection.tscn")
			await _wait(0.5)
			s._set_filter("neutral" if what == "collection_neutral" else cls)
			await _wait(0.5)
			if what == "collection_class":
				var chips := s.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("keyword"))
				if not chips.is_empty():
					ClassInfoPanel.show_tip(chips[0])
			elif what == "collection_guide":
				ClassInfoPanel.open(s, cls)
			await _wait(0.6)
			await _snap(what)
		"collection_sort":
			for c in CardDB.all_cards():
				if c.id.hash() % 3 != 0:
					Collection.owned[c.id] = 1 + c.id.hash() % 2
			Settings.collection_sort = sort_id
			var s := _open("res://scenes/collection.tscn")
			await _wait(0.5)
			s._set_filter(filter)
			await _wait(0.8)
			await _snap("collection_sort_%s_%s" % [sort_id, filter])
		"deck_peek", "deck_list", "deck_list_zoom", "deck_guide":
			Settings.deck_choice = {"selected": "pre:" + (CardDB.class_decks(cls)[1].id if what == "deck_list" else CardDB.class_decks(cls)[0].id)}
			var s := _open("res://scenes/deck_select.tscn")
			await _wait(1.0)
			match what:
				"deck_peek":
					var c: CardView = s._cards.get_child(0)
					s._lift(c, true)
					s._peek_card(c.card_id, c)
				"deck_list", "deck_list_zoom":
					s._open_list(s._find(s._selected))
					if what == "deck_list_zoom":
						await _wait(0.4)
						var e: Dictionary = s._find(s._selected)
						CardZoom.open(s.get_node("Dialog"), str(e.featured[0]))
				"deck_guide":
					ClassInfoPanel.open(s, cls)
			await _wait(0.7)
			await _snap(what)
		"packs_reveal":
			Collection.packs = maxi(Collection.packs, 1)
			var s := _open("res://scenes/pack_opening.tscn")
			await _wait(0.8)
			await s._open()
			for c in s._cards:
				s._reveal(c)
			await _wait(0.5)
			s._banner("MINOS", Color(1.0, 0.6, 0.15))
			await _wait(0.6)
			await _snap("packs_reveal")
		"packs_rates":
			Collection.packs = maxi(Collection.packs, 1)
			Collection.packs_since_legendary = 7
			var s := _open("res://scenes/pack_opening.tscn")
			await _wait(1.0)
			DropRatesPanel.open(s)
			await _wait(0.6)
			await _snap("packs_rates")
		"packs_empty":
			Collection.packs = 0
			Collection.obols = 0
			_open("res://scenes/pack_opening.tscn")
			await _wait(1.2)
			await _snap("packs_empty")
		"lessons":
			_open(Game.LESSONS)
			await _wait(1.2)
			await _snap("lessons")
		"howto":
			# Every chapter of How to Play, over the lessons screen it is opened from.
			var s := _open(Game.LESSONS)
			await _wait(0.8)
			var h := HowToPlayPanel.new()
			s.add_child(h)
			for i in HowToPlayPanel.CHAPTERS.size():
				h.show_chapter(i)
				await _wait(0.5)
				await _snap("howto_%d" % i)
		"offer":
			var s: Node = load(Game.MENU).instantiate()
			get_tree().root.add_child.call_deferred(s)
			await get_tree().process_frame
			get_tree().current_scene = s
			await _wait(1.4)
			s.offer_lessons()
			await _wait(0.6)
			await _snap("offer")
		"lesson", "lesson_pause":
			await _lesson(what)
		"deck_tip":
			# A library disc's tooltip (the discs only show when the library overflows, so one is forced on).
			var s := _open("res://scenes/deck_select.tscn")
			await _wait(1.2)
			var b: Button = s._scroll_btns[1]
			b.modulate.a = 1.0
			b.disabled = false
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.tooltip_text = "Scroll down"
			var holder: Control = b.get_parent()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var at := b.get_global_transform() * (b.size / 2)
			for k in 3:
				get_viewport().warp_mouse(at)
				var e := InputEventMouseMotion.new()
				e.position = at + Vector2(k, 0)
				e.global_position = e.position
				Input.parse_input_event(e)
				await _wait(0.2)
			await _wait(1.4)
			await _snap("deck_tip")
		_:
			await _battle()
	get_tree().quit()


## The deck builder in a state a plain snapshot cannot reach (all in memory: debug runs never save):
## builder_name   a name being typed, the gold-ink caret in the middle of it;
## builder_long   the longest name the field takes, with part of it selected (the ink underline);
## builder_empty  an empty deck: the hint in the deck list;
## builder_leave  Back with unsaved changes: the "Leave without saving?" dialog;
## builder_edit   a saved deck being edited (the Delete disc);
## builder_delete Delete on a saved deck: the "Delete this deck?" dialog;
## builder_tip    the keyword tips beside a card of the grid.
func _builder(mode: String) -> void:
	Game.edit_deck = -1
	Game.new_deck_cls = "pilgrim"
	if mode in ["builder_edit", "builder_delete"]:
		Collection.decks.append({"name": "Lions of Violence", "cls": "pilgrim", "cards": {}})
		Game.edit_deck = Collection.decks.size() - 1
	var s := _open("res://scenes/deck_builder.tscn")
	await _wait(0.6)
	var le: LineEdit = s._name
	match mode:
		"builder_name":
			le.grab_focus()
			le.text = "The Long Way"
			le.text_changed.emit(le.text)
			le.deselect()
			le.caret_column = 8
		"builder_long":
			le.grab_focus()
			le.text = "Wolves of the Ninth Ring" # 24 letters, the most the field takes
			le.text_changed.emit(le.text)
			le.select(10, 24)
		"builder_empty":
			le.release_focus()
		"builder_leave":
			le.release_focus()
			s._add("lost_pilgrim")
			s._leave()
		"builder_edit":
			Collection.autofill(s.deck)
			s._refresh()
		"builder_delete":
			s._delete()
		"builder_tip":
			le.release_focus()
			for id in s._views: # the first card of the grid with keyword tips
				if not UI.card_tips(CardDB.card(id)).is_empty():
					s._show_tips(id, s._views[id].get_parent())
					break
	await _wait(0.8)
	await _snap(mode)


## A lesson played through (tests/lesson_driver.gd), a shot of every line Virgil shows and of the result:
## lesson_<id>_<step>.png. `--lesson=<id>` (default the first lesson); `--steps=a,b` keeps only those step shots.
## "lesson_pause": the lesson's pause menu, and How to Play opened from it.
func _lesson(mode: String) -> void:
	var id := str(Lessons.all()[0].id)
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lesson="):
			id = a.substr(9)
		elif a.begins_with("--steps="):
			only = Array(a.substr(8).split(",")).map(func(x): return int(x))
	Game.prepare_lesson(id)
	var b: Node2D = _open(Game.BATTLE)
	if mode == "lesson_pause":
		await _wait(4.0)
		b._open_pause()
		await _wait(0.5)
		await _snap("lesson_pause")
		b._pause_dim.add_child(HowToPlayPanel.new())
		await _wait(0.5)
		await _snap("lesson_pause_howto")
		return
	var shot := func(i: int, _s: Dictionary) -> void:
		if only.is_empty() or only.has(i):
			await _wait(1.3) # the line typed out, the arrow settled
			await _snap("lesson_%s_%02d" % [id, i])
	var r: Dictionary = await LessonDriver.run(get_tree(), b, shot)
	print("AUDIT lesson %s: %s" % [id, r])
	await _wait(2.6)
	await _snap("lesson_%s_result" % id)


func _open(path: String) -> Node:
	var s: Node = load(path).instantiate()
	add_child(s)
	return s


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _battle() -> void:
	var b: Node = _open(Game.BATTLE)
	await _wait(0.9)
	await _snap("b_arena_intro")
	while not b._mull_waiting:
		await get_tree().process_frame
	b._confirm_mulligan()
	# The first turn banner, once it has popped in.
	var t := 0.0
	while t < 8.0 and b.banner.modulate.a < 0.95:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.2)
	await _snap("b_turn_banner")
	await _wait(2.5)
	var h: Node2D = b.heroes[1]
	Fx.number(b.fx_layer, h.position, "-7", Color(0.75, 0.05, 0.03), true)
	Fx.number(b.fx_layer, b.heroes[0].position, "+4", UI.HEAL, false)
	b._nope(b.heroes[0].position + Vector2(-420, 110), "Not enough mana")
	await _wait(0.25)
	await _snap("b_numbers")
	await _wait(1.5)
	b._show_hero_tip(b.heroes[1])
	await _wait(0.3)
	await _snap("b_hero_tip")
	b._hide_inspect()
	b._legendary_cutin("minos")
	await _wait(0.75)
	await _snap("b_cutin")
	await _wait(1.5)
	b._open_pause()
	await _wait(0.4)
	await _snap("b_pause")
	b._pause_dim.add_child(OptionsPanel.new())
	await _wait(0.4)
	await _snap("b_pause_options")
	b._pause_dim.queue_free()
	b._show_result(1)
	await _wait(1.4)
	await _snap("b_defeat")
