class_name ShowcaseDeck
extends RefCounted
## The order in which the title screen's showcase shows its cards: every id of the pool once, in a fresh shuffled
## cycle, before any is shown again. Legendaries are spread evenly through each cycle, so the screen can nearly always
## keep one in view (`take(.., true)` asks for one when the card being replaced was the last).

var pool: Array[String] = []
var rng := RandomNumberGenerator.new()
var _queue: Array[String] = []


func _init(p_pool: Array[String] = [], seed_value: int = 0) -> void:
	pool = p_pool.duplicate()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


static func is_legendary(id: String) -> bool:
	return str(CardDB.card(id).get("rarity", "")) == "legendary"


func _shuffled(a: Array[String]) -> Array[String]:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = b[i]
		b[i] = b[j]
		b[j] = t
	return b


## One new cycle: the legendaries and the rest each shuffled, then merged so the legendaries come at an even pace.
func _cycle() -> Array[String]:
	var leg: Array[String] = []
	var rest: Array[String] = []
	for id in pool:
		(leg if is_legendary(id) else rest).append(id)
	leg = _shuffled(leg)
	rest = _shuffled(rest)
	var out: Array[String] = []
	var n := leg.size() + rest.size()
	var li := 0
	var ri := 0
	for i in n:
		var due := li < leg.size() and (ri >= rest.size() or (li + 0.5) / leg.size() <= (i + 0.5) / n)
		if due:
			out.append(leg[li])
			li += 1
		else:
			out.append(rest[ri])
			ri += 1
	return out


## The next id of the order that is not in `on_screen` (and a legendary when `legendary` is set and one is left in this
## cycle). When the cycle has nothing suitable left, a new one starts. "" for an empty pool.
func take(on_screen: Array, legendary: bool = false) -> String:
	if pool.is_empty():
		return ""
	for attempt in 3:
		for want in ([true, false] if legendary else [false]):
			for i in _queue.size():
				var id := _queue[i]
				if id in on_screen or (want and not is_legendary(id)):
					continue
				_queue.remove_at(i)
				return id
		for id in _cycle(): # a new cycle; what is left of the old one stays in front
			if not id in _queue:
				_queue.append(id)
	for id in pool: # fewer cards than places on screen: show whatever there is
		if not id in on_screen:
			return id
	return pool[0]
