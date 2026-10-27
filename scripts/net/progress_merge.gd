class_name ProgressMerge
extends RefCounted
## The player's progress as one JSON blob for the account's cloud save (Nakama storage, collection "dantes_save",
## key "progress"), and the rules that merge two of them. Pure functions on Dictionaries (no nodes, no network), so
## the tests check them directly; OnlineSession gathers the blob from the game and applies the result.
##
## Blob: {version: VERSION, saved_at_ms, data: {collection: {owned, obols, packs, pity, opened, decks},
##   record: {wins, losses, class_games}, online: {wins, losses, draws}, profile: {name, avatar},
##   settings: {lessons, lessons_offered, intro_seen, coach_seen, difficulty, deck_choice, fast_animations,
##   subtitles}}}. Device-only settings (volumes, fullscreen, frame limit, vsync) never travel.
##
## Merge (`merge`): an empty side takes the other; a fresh install (nothing beyond the starter state) takes the
## account's; otherwise the newer save wins field by field, but nothing earned is lost: owned cards are united (the
## most copies of each), packs, pity, packs opened and the records keep the larger value, custom decks and lessons
## are united, coach tips seen are united. A deleted (or renamed) deck leaves a tombstone (`collection.deleted_decks`,
## "cls|name" -> unix ms), and a deck is united only if it was saved (`saved_ms`) after its tombstone: deleted decks
## no longer come back from another device's save.

const VERSION := 1


static func blob(data: Dictionary, saved_at_ms: int) -> Dictionary:
	return {"version": VERSION, "saved_at_ms": saved_at_ms, "data": data}


static func is_empty(b: Dictionary) -> bool:
	return not (b.get("data") is Dictionary) or (b.data as Dictionary).is_empty()


## Nothing beyond what a new install starts with: no packs opened, no Obols, no own decks, no match finished,
## no lesson, no name. (The starter cards and the three welcome packs are the same everywhere.)
static func is_fresh(b: Dictionary) -> bool:
	if is_empty(b):
		return true
	var d: Dictionary = b.data
	var col: Dictionary = d.get("collection", {})
	var rec: Dictionary = d.get("record", {})
	var onl: Dictionary = d.get("online", {})
	var prof: Dictionary = d.get("profile", {})
	var st: Dictionary = d.get("settings", {})
	return int(col.get("opened", 0)) == 0 and int(col.get("obols", 0)) == 0 and (col.get("decks", []) as Array).is_empty() \
		and int(rec.get("wins", 0)) + int(rec.get("losses", 0)) == 0 \
		and int(onl.get("wins", 0)) + int(onl.get("losses", 0)) + int(onl.get("draws", 0)) == 0 \
		and str(prof.get("name", "")) == "" and (st.get("lessons", {}) as Dictionary).is_empty()


## The merged blob of `local` and `server` (either may be {}).
static func merge(local: Dictionary, server: Dictionary) -> Dictionary:
	if is_empty(server):
		return local.duplicate(true)
	if is_empty(local) or is_fresh(local):
		return server.duplicate(true)
	if is_fresh(server):
		return local.duplicate(true)
	var l_new := int(local.get("saved_at_ms", 0)) >= int(server.get("saved_at_ms", 0))
	var newer: Dictionary = (local if l_new else server).duplicate(true)
	var older: Dictionary = (server if l_new else local)
	var n: Dictionary = newer.data
	var o: Dictionary = older.data
	# Collection: no card, pack or pity step is ever lost.
	var nc: Dictionary = n.get("collection", {})
	var oc: Dictionary = o.get("collection", {})
	var owned: Dictionary = (nc.get("owned", {}) as Dictionary).duplicate()
	var o_owned: Dictionary = oc.get("owned", {})
	for id in o_owned:
		owned[id] = maxi(int(owned.get(id, 0)), int(o_owned[id]))
	nc["owned"] = owned
	for k in ["packs", "pity", "opened"]:
		nc[k] = maxi(int(nc.get(k, 0)), int(oc.get(k, 0)))
	nc["obols"] = int(nc.get("obols", 0))
	var tombs := merge_tombs(nc.get("deleted_decks", {}), oc.get("deleted_decks", {}))
	nc["decks"] = merge_decks(nc.get("decks", []), oc.get("decks", []), tombs)
	if not tombs.is_empty() or nc.has("deleted_decks") or oc.has("deleted_decks"): # (a save from 0.8.1 has none)
		nc["deleted_decks"] = tombs
	n["collection"] = nc
	# Records only grow.
	for sec in ["record", "online"]:
		var a: Dictionary = n.get(sec, {})
		var b: Dictionary = o.get(sec, {})
		for k in b:
			if typeof(b[k]) in [TYPE_INT, TYPE_FLOAT]:
				a[k] = maxi(int(a.get(k, 0)), int(b[k]))
		if b.get("class_games") is Dictionary:
			var cg: Dictionary = (a.get("class_games", {}) as Dictionary).duplicate()
			for c in b.class_games:
				cg[c] = maxi(int(cg.get(c, 0)), int(b.class_games[c]))
			a["class_games"] = cg
		n[sec] = a
	# Lessons ("done" beats "skipped") and coach tips are united.
	var ns: Dictionary = n.get("settings", {})
	var old_s: Dictionary = o.get("settings", {})
	var lessons: Dictionary = (ns.get("lessons", {}) as Dictionary).duplicate()
	var o_lessons: Dictionary = old_s.get("lessons", {})
	for k in o_lessons:
		if not lessons.has(k) or o_lessons[k] == "done":
			lessons[k] = o_lessons[k]
	ns["lessons"] = lessons
	var seen: Array = (ns.get("coach_seen", []) as Array).duplicate()
	for k in old_s.get("coach_seen", []):
		if not seen.has(k):
			seen.append(k)
	ns["coach_seen"] = seen
	for k in ["lessons_offered", "intro_seen"]:
		ns[k] = bool(ns.get(k, false)) or bool(old_s.get(k, false))
	n["settings"] = ns
	# The newer profile, but never an empty name over a chosen one.
	var np: Dictionary = n.get("profile", {})
	var op: Dictionary = o.get("profile", {})
	if str(np.get("name", "")) == "" and str(op.get("name", "")) != "":
		np["name"] = op.name
		np["avatar"] = op.get("avatar", np.get("avatar", ""))
	n["profile"] = np
	newer["data"] = n
	newer["saved_at_ms"] = maxi(int(local.get("saved_at_ms", 0)), int(server.get("saved_at_ms", 0)))
	newer["version"] = VERSION
	return newer


## `local` plus what the account's save holds that this build cannot show (cards or classes from a newer version of
## the game), so uploading this install's progress never erases them. `known_card(id)` and `known_class(cls)` say
## what this build knows.
static func keep_foreign(local: Dictionary, server: Dictionary, known_card: Callable, known_class: Callable) -> Dictionary:
	var out := local.duplicate(true)
	if is_empty(server) or is_empty(out):
		return out
	var sc: Dictionary = server.data.get("collection", {})
	var lc: Dictionary = out.data.get("collection", {})
	var owned: Dictionary = lc.get("owned", {})
	var s_owned: Dictionary = sc.get("owned", {})
	for id in s_owned:
		if not known_card.call(str(id)) and not owned.has(id):
			owned[id] = s_owned[id]
	lc["owned"] = owned
	var decks: Array = lc.get("decks", [])
	var names := {}
	for dk in decks:
		names[deck_key(dk)] = true
	for dk in sc.get("decks", []):
		if dk is Dictionary and not known_class.call(str(dk.get("cls", ""))) and not names.has(deck_key(dk)):
			decks.append(dk)
	lc["decks"] = decks
	if lc.has("deleted_decks") or sc.has("deleted_decks"): # another device's deletions stay on the account
		lc["deleted_decks"] = merge_tombs(lc.get("deleted_decks", {}), sc.get("deleted_decks", {}))
	out.data["collection"] = lc
	return out


## A custom deck's identity across devices: its class and name.
static func deck_key(dk: Variant) -> String:
	if not (dk is Dictionary):
		return str(dk)
	return "%s|%s" % [str(dk.get("cls", "")), str(dk.get("name", ""))]


## When a deck was last saved (unix ms, its `saved_ms`; 0 for a deck from before 0.8.2).
static func deck_ms(dk: Variant) -> int:
	return int(dk.get("saved_ms", 0)) if dk is Dictionary else 0


const MAX_TOMBS := 200 ## deleted-deck records kept (the most recent)


## Deleted decks ("tombstones", deck_key -> unix ms of the deletion) of two saves united, the later time of each.
static func merge_tombs(a: Variant, b: Variant) -> Dictionary:
	var out := {}
	for src in [a, b]:
		if not (src is Dictionary):
			continue
		for k in src:
			if typeof(src[k]) in [TYPE_INT, TYPE_FLOAT]:
				out[str(k)] = maxi(int(out.get(str(k), 0)), int(src[k]))
	if out.size() > MAX_TOMBS:
		var keys := out.keys()
		keys.sort_custom(func(x, y): return int(out[x]) > int(out[y]))
		var kept := {}
		for i in MAX_TOMBS:
			kept[keys[i]] = out[keys[i]]
		out = kept
	return out


## The custom decks of two saves: the newer save's, plus the older save's other decks; a deck saved later on the older
## side replaces the newer side's copy of it. A deck deleted (or renamed away) at or after its last save is dropped,
## so a deck deleted on one device does not come back from another one's save.
static func merge_decks(newer: Variant, older: Variant, tombs: Dictionary) -> Array:
	var out := []
	var at := {} ## deck_key -> index in `out` of the newer side's deck
	for dk in (newer if newer is Array else []):
		if _buried(dk, tombs):
			continue
		if not at.has(deck_key(dk)):
			at[deck_key(dk)] = out.size()
		out.append((dk as Dictionary).duplicate(true) if dk is Dictionary else dk)
	for dk in (older if older is Array else []):
		if _buried(dk, tombs):
			continue
		var k := deck_key(dk)
		if not at.has(k):
			out.append((dk as Dictionary).duplicate(true) if dk is Dictionary else dk)
		elif deck_ms(dk) > deck_ms(out[at[k]]):
			out[at[k]] = (dk as Dictionary).duplicate(true)
	return out


static func _buried(dk: Variant, tombs: Dictionary) -> bool:
	var k := deck_key(dk)
	return tombs.has(k) and int(tombs[k]) >= deck_ms(dk)


## True when two blobs hold the same progress (saved_at_ms aside).
static func same(a: Dictionary, b: Dictionary) -> bool:
	return canon(a.get("data", {})) == canon(b.get("data", {}))


## A value as JSON text with sorted keys, after a round trip (so 3 and 3.0 read the same, as they do after the
## server has stored them).
static func canon(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)
