extends Node
## Run state and scene flow: menu -> deck choice -> arena -> battle -> result.

const MENU := "res://scenes/main_menu.tscn"
const DECK_SELECT := "res://scenes/deck_select.tscn"
const BATTLE := "res://scenes/battle.tscn"
const COLLECTION := "res://scenes/collection.tscn"
const PACKS := "res://scenes/pack_opening.tscn"
const DECK_BUILDER := "res://scenes/deck_builder.tscn"
const INTRO := "res://scenes/intro.tscn"
const LESSONS := "res://scenes/lessons.tscn" ## Virgil's lessons (the guided matches for new players)
const PROGRESS := "user://progress.cfg" ## wins / losses and the last arena
const SaveFile := preload("res://scripts/core/save_file.gd")

var player_deck := "pilgrim" ## the player's class
var enemy_deck := "ferry" ## the opponent's class
var enemy_deck_id := "" ## the preconstructed deck (data/decks.json id) the opponent plays
var player_cards: Array[String] = CardDB.deck_list("pilgrim")
var player_hero := "dante"
var enemy_cards: Array[String] = CardDB.deck_list("ferry")
var enemy_hero := "charon"
var new_deck_cls := "pilgrim"
var edit_deck := -1 ## index into Collection.decks for the deck builder, -1 = new
var arena_id := "acheron"
var arena_picked := false ## the deck screen already drew this match's arena (and showed its name)
var last_arena := "" ## the previous match's arena, so the draw avoids repeating it
var force_arena := "" ## debug / tests: always open this arena, even before its board is painted
var arena_forced := false ## the current battle's arena was forced (it may be shown on the Acheron stand-in)
var last_winner := -1
var stats := {"wins": 0, "losses": 0}
var intro_played := false ## the cinematic has played in this run (so `--intro` does not loop)
var lesson := "" ## the lesson (data/lessons.json id) the next / current battle is, "" for a real match

var _fade: ColorRect
var _layer: CanvasLayer


## A window in the background needs almost no frames: leaves the GPU to other programs (the art PC runs ComfyUI next
## to the game) and saves battery on phones. In front, the player's Frame limit (Settings.frame_limit) applies.
const FPS_BACKGROUND := 10


func _ready() -> void:
	if DisplayServer.get_name() != "headless": # tests run the frames as fast as they can
		Engine.max_fps = Settings.frame_limit
	UI.paint_tooltips()
	# Android's back gesture steps back through the menus (back()) instead of quitting the game from any screen.
	get_tree().quit_on_go_back = false
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap="):
			_snap(a.substr(7))
	load_progress(PROGRESS)


## Reads the run progress (wins / losses, the last arena). A missing, damaged or hand-edited file gives defaults
## for what cannot be read (SaveFile), never a crash.
func load_progress(path: String) -> void:
	var cfg := SaveFile.open(path, not debug_run())
	var saved: Dictionary = SaveFile.value(cfg, "run", "stats", {})
	stats = {"wins": 0, "losses": 0}
	for k in stats:
		if typeof(saved.get(k)) in [TYPE_INT, TYPE_FLOAT]:
			stats[k] = maxi(0, int(saved[k]))
	last_arena = str(SaveFile.value(cfg, "run", "last_arena", ""))


## The first match keeps the intro's promise ("At the river Acheron, Charon is waiting."): on a fresh profile the
## arena is the Acheron and the opponent plays Charon's starter deck (unless the player leads Charon's class).
const FIRST_ARENA := "acheron"
const FIRST_FOE := "charon"


## No match finished yet (wins + losses == 0; draws and abandoned games do not count).
func first_match() -> bool:
	return int(stats.get("wins", 0)) + int(stats.get("losses", 0)) == 0


## Draws the arena for the next match: a random one whose painted board is installed, never the previous
## match's when there is a choice. Arenas still waiting for their art are left out (the Acheron always qualifies).
## The first match is always at the Acheron.
func pick_arena() -> String:
	if first_match() and CardDB.arena_ready(FIRST_ARENA):
		arena_id = FIRST_ARENA
		arena_picked = true
		return arena_id
	var pool: Array[String] = []
	for a in CardDB.arenas():
		if CardDB.arena_ready(a.id) and a.id != last_arena:
			pool.append(a.id)
	if pool.is_empty():
		pool.append(last_arena if CardDB.arena_ready(last_arena) else "acheron")
	arena_id = pool[randi() % pool.size()]
	arena_picked = true
	return arena_id


## Called by the battle as it opens: settles which arena it shows (a forced one wins: `force_arena`, or the
## `-- --arena=<id>` debug flag) and remembers it, so the next draw picks another one.
func begin_arena() -> String:
	var forced := force_arena
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arena="):
			forced = a.substr(8)
	arena_forced = forced != "" and not CardDB.arena(forced).is_empty()
	if arena_forced:
		arena_id = forced
	elif not arena_picked:
		pick_arena()
	arena_picked = false
	last_arena = arena_id
	_save_progress("last_arena", last_arena)
	return arena_id


## Debug: `-- --snap=file.png` saves one screenshot of the opening scene and quits.
func _snap(path: String) -> void:
	var delay := 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap-delay="):
			delay = float(a.substr(13))
	await get_tree().create_timer(delay).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## Starts a battle with a preconstructed deck (by id) against a random preconstructed deck of another class.
func start_battle(deck_id: String) -> void:
	start_with(CardDB.deck_list(deck_id), CardDB.deck(deck_id).hero)


## Starts one of Virgil's lessons (data/lessons.json): its fixed decks and heroes, its arena (a lesson with none draws
## one as a match does). A lesson's result never counts in the record (see `record_result`).
func start_lesson(id: String) -> void:
	if prepare_lesson(id):
		go(BATTLE)


## Sets the next battle up as lesson `id` without opening it (the tests open the battle scene themselves).
func prepare_lesson(id: String) -> bool:
	var l := Lessons.get_lesson(id)
	if l.is_empty():
		return false
	var lu := Lessons.line_up(l)
	lesson = id
	player_cards.assign(lu.player_cards)
	player_hero = lu.player_hero
	player_deck = CardDB.hero_class(player_hero)
	enemy_cards.assign(lu.enemy_cards)
	enemy_hero = lu.enemy_hero
	enemy_deck = CardDB.hero_class(enemy_hero)
	enemy_deck_id = lu.enemy_deck_id
	var a := str(l.get("arena", ""))
	if a != "" and CardDB.arena_ready(a):
		arena_id = a
		arena_picked = true
	else:
		pick_arena()
	return true


## Starts a battle with any card list; the opponent plays a random preconstructed deck of class `enemy_cls`, or of
## a random other class when it is "".
func start_with(cards: Array, hero: String, enemy_cls := "") -> void:
	lesson = ""
	player_cards.assign(cards)
	player_hero = hero
	player_deck = CardDB.hero_class(hero)
	if enemy_cls == "":
		enemy_cls = pick_enemy_class(player_deck)
	enemy_deck = enemy_cls
	enemy_deck_id = pick_enemy_deck(enemy_cls)
	enemy_cards = CardDB.deck_list(enemy_deck_id)
	enemy_hero = CardDB.deck(enemy_deck_id).hero
	go(BATTLE)


## A random opponent class for a player of class `cls`: any other class with preconstructed decks (the same class
## when it is the only one). The first match is against Charon's class when the player is not playing it.
func pick_enemy_class(cls: String) -> String:
	var first_foe := CardDB.hero_class(FIRST_FOE)
	if first_match() and first_foe != cls and not CardDB.class_decks(first_foe).is_empty():
		return first_foe
	var pool: Array[String] = []
	for c in CardDB.other_classes(cls):
		if not CardDB.class_decks(c).is_empty():
			pool.append(c)
	return pool.pick_random() if not pool.is_empty() else cls


## A random preconstructed deck of class `cls`, never the one faced last time when there is a choice. In the first
## match Charon's class plays its starter (its first deck).
func pick_enemy_deck(cls: String) -> String:
	if first_match() and cls == CardDB.hero_class(FIRST_FOE) and not CardDB.class_decks(cls).is_empty():
		return str(CardDB.class_decks(cls)[0].id)
	var pool: Array[String] = []
	for d in CardDB.class_decks(cls):
		if d.id != enemy_deck_id or CardDB.class_decks(cls).size() == 1:
			pool.append(str(d.id))
	return pool[randi() % pool.size()] if not pool.is_empty() else cls


func record_result(winner: int) -> void:
	last_winner = winner
	if winner == 0:
		stats.wins += 1
	elif winner == 1:
		stats.losses += 1
	_save_progress("stats", stats)


## Tests and tooling (`debug_run`) keep their results in memory, so they never touch the player's real profile.
func _save_progress(key: String, value: Variant) -> void:
	if debug_run():
		return
	var cfg := SaveFile.open(PROGRESS)
	cfg.set_value("run", key, value)
	cfg.save(PROGRESS)


## The opening cinematic plays once, on the first launch, before the main menu. Never in headless runs (tests), with
## `--no-intro` or in any other `debug_run` (a tooling flag such as `--snap`, `--shots`, `--autoplay`); `--intro` forces it.
func intro_due() -> bool:
	if intro_played:
		return false
	var args := OS.get_cmdline_user_args()
	if "--intro" in args:
		return true
	if Settings.intro_seen or DisplayServer.get_name() == "headless":
		return false
	if "--no-intro" in args or debug_run():
		return false
	return true


## Flags of the tooling runs (BUILD.md, tests/*.gd) that drive the real game; any of them makes a `debug_run`.
const DEBUG_FLAGS := ["--autoplay", "--snap=", "--shots=", "--out=", "--intro-shots="]


## True for tests and tooling runs, where first-time things such as the intro and the coach tips must neither show
## nor be marked as seen, and nothing is written to the player's profile (settings, progress, collection): headless
## runs, a debug flag that drives the game (DEBUG_FLAGS), or any scene or script started from res://tests/.
func debug_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_user_args():
		for f in DEBUG_FLAGS:
			if a == f or (f.ends_with("=") and a.begins_with(f)):
				return true
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/") or a.begins_with("tests/"):
			return true
	return false


## "Watch intro" (options): plays the cinematic again, then returns to the main menu.
func play_intro() -> void:
	go(INTRO)


## Fades to black, swaps the scene, fades back in.
func go(path: String) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.45)
	await t2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Esc on a desktop, the back gesture / button on Android (the engine's default there quits the app from any
## screen, see _ready): closes an open dialog, Credits or Options, else asks the scene to step back (`go_back()`, which
## the menus define; a scene without it, the battle or the intro, ignores it).
func back() -> void:
	var s := get_tree().current_scene
	if s == null or _fade.color.a > 0.01: # mid-fade: a second press would change the scene twice
		return
	if UI.cancel_dialog(s):
		return
	var panels := s.find_children("*", "Control", true, false)
	panels.reverse() # the last one opened (credits over options) closes first
	for n in panels:
		if (n is OptionsPanel or n is CreditsPanel or n is HowToPlayPanel) and not n.is_queued_for_deletion():
			n._close()
			return
	if s.has_method("go_back"):
		s.go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()
		return
	if debug_run(): # tooling (snapshots, autoplay) runs unfocused and must not slow down
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = FPS_BACKGROUND
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = Settings.frame_limit
