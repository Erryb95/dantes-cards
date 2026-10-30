class_name FaceQueue
extends Node
## Builds the card faces of a big grid (the collection, the deck builder) a few per frame instead of all at once: a
## face costs ms to build, its painting more to load. The grid's slots are laid out at once (each with meta "card", the
## card's entry); `build` makes a slot's face (slot, fade: it eases in, the grid already on screen). Faces on screen
## come first, and each waits for its painting, loaded on another thread (CardDB.art_ready), so no frame waits for a
## load.

const BUILD_MS := 6 ## ms of each frame spent building faces
const PREFETCH := 16 ## paintings loading on other threads at a time, ahead of the faces built

var view: Control ## the scroll the grid sits in: what lies inside its rect is on screen
var build: Callable ## func(slot: Control, fade: bool)
var _pending: Array[Control] = []


func _init(p_view: Control, p_build: Callable) -> void:
	view = p_view
	build = p_build
	set_process(false)


## `slot` gets its face now when `now` and its painting is loaded, else in the coming frames.
func want(slot: Control, now: bool) -> void:
	if now and CardDB.art_ready(slot.get_meta("card").id):
		build.call(slot, false)
	else:
		_pending.append(slot)
		set_process(true)


func clear() -> void:
	_pending.clear()
	set_process(false)


func is_done() -> bool:
	return _pending.is_empty()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec()
	var rect := view.get_global_rect()
	var next: Array[Control] = []
	for slot in _pending:
		if is_instance_valid(slot) and slot.is_visible_in_tree() and rect.intersects(slot.get_global_rect()):
			next.append(slot)
	for slot in _pending:
		if next.size() >= PREFETCH:
			break
		if not next.has(slot):
			next.append(slot)
	for slot in next:
		if Time.get_ticks_msec() - t >= BUILD_MS:
			break
		if not is_instance_valid(slot):
			_pending.erase(slot)
		elif CardDB.art_ready(slot.get_meta("card").id):
			_pending.erase(slot)
			build.call(slot, true)
	if _pending.is_empty():
		set_process(false)
