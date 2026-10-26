extends Node
## The player's collection and economy, saved to user://collection.cfg.
## Obols are earned by playing; a pack costs 100 and holds 5 cards (at least one rare or better).

const PATH := "user://collection.cfg"
const PACK_PRICE := 100
const PACK_SIZE := 5
const WIN_REWARD := 100
const LOSS_REWARD := 25
const START_PACKS := 3
const DECK_SIZE := 30
## Class -> hero.
const CLASS_HERO := {"pilgrim": "dante", "ferry": "charon"}
## Chance per card slot; the last slot is upgraded to rare if the pack has no rare yet.
const ODDS := {"legendary": 0.015, "epic": 0.055, "rare": 0.21}
const PITY_LEGENDARY := 20 ## guaranteed legendary within this many packs
const MAX_COPIES := {"common": 2, "rare": 2, "epic": 2, "legendary": 1}
## Obols refunded for a copy beyond the deck limit.
const REFUND := {"common": 5, "rare": 20, "epic": 100, "legendary": 400}

signal changed

var owned := {} ## card id -> copies
var obols := 0
var packs := 0
var packs_since_legendary := 0
var opened_total := 0
var decks := [] ## custom decks: {name, cls, cards: {id: n}}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		# First run: three packs are waiting.
		packs = START_PACKS
	else:
		owned = cfg.get_value("collection", "owned", {})
		obols = cfg.get_value("collection", "obols", 0)
		packs = cfg.get_value("collection", "packs", 0)
		packs_since_legendary = cfg.get_value("collection", "pity", 0)
		opened_total = cfg.get_value("collection", "opened", 0)
		decks = cfg.get_value("collection", "decks", [])
	# The starter decks are always owned (they can grow between versions).
	for d in CardDB.decks():
		for id in d.cards:
			owned[id] = maxi(int(owned.get(id, 0)), int(d.cards[id]))
	save()


func save() -> void:
	if Game.debug_run(): # tests and tooling never write the player's real collection
		return
	var cfg := ConfigFile.new()
	cfg.set_value("collection", "owned", owned)
	cfg.set_value("collection", "obols", obols)
	cfg.set_value("collection", "packs", packs)
	cfg.set_value("collection", "pity", packs_since_legendary)
	cfg.set_value("collection", "opened", opened_total)
	cfg.set_value("collection", "decks", decks)
	cfg.save(PATH)
	changed.emit()


func copies(id: String) -> int:
	return int(owned.get(id, 0))


func reward_battle(won: bool) -> int:
	var r := WIN_REWARD if won else LOSS_REWARD
	obols += r
	save()
	return r


func buy_pack() -> bool:
	if obols < PACK_PRICE:
		return false
	obols -= PACK_PRICE
	packs += 1
	save()
	return true


## The packable pool: every non-token card, grouped by rarity.
func _pool() -> Dictionary:
	var by := {"common": [], "rare": [], "epic": [], "legendary": []}
	for c in CardDB.all_cards():
		if by.has(c.get("rarity", "")):
			by[c.rarity].append(c.id)
	return by


func _roll_rarity() -> String:
	var r := rng.randf()
	if r < ODDS.legendary:
		return "legendary"
	if r < ODDS.legendary + ODDS.epic:
		return "epic"
	if r < ODDS.legendary + ODDS.epic + ODDS.rare:
		return "rare"
	return "common"


## Opens one pack. Returns [{id, rarity, new, refund}], already added to the collection.
func open_pack() -> Array:
	if packs <= 0:
		return []
	packs -= 1
	opened_total += 1
	var pool := _pool()
	var rarities: Array[String] = []
	for i in PACK_SIZE:
		rarities.append(_roll_rarity())
	if not rarities.any(func(r): return r != "common"):
		rarities[PACK_SIZE - 1] = "rare"
	packs_since_legendary += 1
	if rarities.has("legendary"):
		packs_since_legendary = 0
	elif packs_since_legendary >= PITY_LEGENDARY:
		rarities[0] = "legendary"
		packs_since_legendary = 0
	var out := []
	for r in rarities:
		var ids: Array = pool[r] if not pool[r].is_empty() else pool.common
		var id: String = ids[rng.randi_range(0, ids.size() - 1)]
		var had := copies(id)
		var refund := 0
		if had >= int(MAX_COPIES.get(r, 2)):
			refund = int(REFUND.get(r, 5))
			obols += refund
		else:
			owned[id] = had + 1
		out.append({"id": id, "rarity": r, "new": had == 0, "refund": refund})
	# Show the best cards last, like a reveal.
	var order := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
	out.sort_custom(func(a, b): return order[a.rarity] < order[b.rarity])
	save()
	return out


static func max_copies(id: String) -> int:
	return int(MAX_COPIES.get(CardDB.card(id).get("rarity", "common"), 2))


## Can `id` go into a deck of class `cls`?
static func fits_class(id: String, cls: String) -> bool:
	var s: String = CardDB.card(id).get("set", "")
	return s == cls or s == "neutral"


static func deck_count(cards: Dictionary) -> int:
	var n := 0
	for id in cards:
		n += int(cards[id])
	return n


static func deck_cards(cards: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in cards:
		for i in int(cards[id]):
			out.append(id)
	return out


## Empty string when the deck is legal, otherwise the reason.
func deck_problem(d: Dictionary) -> String:
	var n := deck_count(d.cards)
	if n != DECK_SIZE:
		return "%d/%d cards" % [n, DECK_SIZE]
	for id in d.cards:
		if not fits_class(id, d.cls):
			return "%s is not a %s card" % [CardDB.card(id).get("name", id), d.cls]
		if int(d.cards[id]) > mini(max_copies(id), copies(id)):
			return "not enough copies of %s" % CardDB.card(id).get("name", id)
	return ""


## Fills a deck up to 30 cards with the strongest owned cards (the "Auto-fill" button), keeping the cards already in
## it. Strength is each card's measured win-rate edge (data/card_ratings.json, from AI games); a first pass keeps
## a smooth mana curve, a second fills what is left with the best remaining cards.
func autofill(d: Dictionary) -> void:
	var pool := []
	for c in CardDB.all_cards():
		if c.get("set", "") != "token" and fits_class(c.id, d.cls) and copies(c.id) > 0:
			pool.append(c)
	var score := {}
	for c in pool:
		# A small nudge for class cards (the deck's identity) and a tiny jitter between near-equal cards.
		score[c.id] = rating(c.id) + (0.01 if c.set == d.cls else 0.0) + randf_range(-0.004, 0.004)
	pool.sort_custom(func(a, b): return score[a.id] > score[b.id])
	var want := {1: 4, 2: 7, 3: 6, 4: 5, 5: 4, 6: 2, 7: 2}
	for pass_i in 2:
		for c in pool:
			var cost := clampi(int(c.cost), 1, 7)
			while deck_count(d.cards) < DECK_SIZE:
				var have := int(d.cards.get(c.id, 0))
				if have >= mini(max_copies(c.id), copies(c.id)):
					break
				if pass_i == 0 and _at_cost(d.cards, cost) >= want[cost]:
					break
				d.cards[c.id] = have + 1


func _at_cost(cards: Dictionary, cost: int) -> int:
	var n := 0
	for id in cards:
		if clampi(int(CardDB.card(id).cost), 1, 7) == cost:
			n += int(cards[id])
	return n


var _ratings := {}
## A card's measured strength: its win-rate edge over its class average (0 when unmeasured).
func rating(id: String) -> float:
	if _ratings.is_empty():
		var f := FileAccess.open("res://data/card_ratings.json", FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text()) if f != null else null
		_ratings = data.get("ratings", {}) if data is Dictionary else {"_": 0}
	return float(_ratings.get(id, 0.0))
