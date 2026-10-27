class_name VfxData
## The looks behind Vfx: the schools (colours, textures, sounds, default patterns), which school each circle uses,
## the pattern names, and each card's profile from data/vfx.json. Pure data (no nodes, no autoloads), so the
## headless tests can check it.

const DATA := "res://data/vfx.json"

## name -> look. color / hot: the effect's colour and its white-hot core. core: the missile's head; trail and mote:
## particle textures; impact: the hit flash; rune: the circle drawn under casts. Each texture slot lists names
## from best to fallback. rise: the motes float up (fire, light, souls) or fall (ice, blood, stone). cast_sfx /
## hit_sfx: Sfx names. hit / mass: the default patterns.
const SCHOOLS := {
	"fire": {"name": "fire", "color": Color(1.0, 0.42, 0.1), "hot": Color(1.0, 0.85, 0.45), "core": ["vfx_fireball", "k_fire_01"],
		"trail": "k_flame_04", "mote": "k_flame_05", "impact": ["fire_burst"], "rune": "k_magic_02", "rise": true,
		"cast_sfx": "spell_fire", "hit_sfx": "spell_fire", "hit": "orb", "mass": "rain"},
	"ice": {"name": "ice", "color": Color(0.45, 0.78, 1.0), "hot": Color(0.88, 0.97, 1.0), "core": ["vfx_ice_shard", "k_star_08"],
		"trail": "k_star_04", "mote": "k_star_06", "impact": ["vfx_frost_star", "k_star_09"], "rune": "k_magic_03",
		"rise": false, "cast_sfx": "ice", "hit_sfx": "glass", "hit": "shard", "mass": "blizzard"},
	"venom": {"name": "venom", "color": Color(0.35, 0.95, 0.2), "hot": Color(0.8, 1.0, 0.5),
		"core": ["vfx_venom_glob", "k_circle_05"], "trail": "k_smoke_03", "mote": "k_circle_05",
		"impact": ["venom_drops"], "rune": "k_magic_01", "rise": false, "cast_sfx": "vial", "hit_sfx": "splash",
		"hit": "serpent", "mass": "nova"},
	"holy": {"name": "holy", "color": Color(1.0, 0.82, 0.45), "hot": Color(1.0, 0.98, 0.88),
		"core": ["vfx_angel_feather", "k_star_09"], "trail": "k_star_04", "mote": "k_star_06",
		"impact": ["vfx_sunburst", "holy_light"], "rune": "k_magic_04", "rise": true, "cast_sfx": "magic", "hit_sfx": "chime",
		"hit": "beam", "mass": "radiance"},
	"soul": {"name": "soul", "color": Color(0.55, 0.72, 1.0), "hot": Color(0.9, 0.95, 1.0), "core": ["vfx_soul_wisp", "k_light_02"],
		"trail": "k_smoke_02", "mote": "k_smoke_05", "impact": ["vfx_skull_wisp", "k_light_03"],
		"rune": "k_circle_03", "rise": true, "cast_sfx": "wail", "hit_sfx": "sigh", "hit": "wisp", "mass": "wail"},
	"shadow": {"name": "shadow", "color": Color(0.62, 0.25, 1.0), "hot": Color(0.95, 0.72, 1.0), "core": ["k_magic_05"],
		"trail": "k_smoke_04", "mote": "k_spark_03", "impact": ["vfx_shadow_burst", "vfx_chain_glow", "k_scorch_03"],
		"rune": "k_magic_02", "rise": true, "cast_sfx": "spell", "hit_sfx": "thud", "hit": "orb", "mass": "wail"},
	"wind": {"name": "wind", "color": Color(0.95, 0.55, 0.85), "hot": Color(1.0, 0.9, 1.0), "core": ["vfx_whirlwind", "k_twirl_02"],
		"trail": "k_trace_02", "mote": "k_twirl_03", "impact": ["vfx_gust_streak", "k_twirl_01"],
		"rune": "k_circle_02", "rise": true, "cast_sfx": "gust", "hit_sfx": "whoosh", "hit": "gust",
		"mass": "gale"},
	"water": {"name": "water", "color": Color(0.3, 0.62, 0.95), "hot": Color(0.8, 0.95, 1.0), "core": ["k_circle_05"],
		"trail": "k_dirt_01", "mote": "k_dirt_02", "impact": ["vfx_water_splash", "k_dirt_03"],
		"rune": "k_circle_01", "rise": false, "cast_sfx": "splash", "hit_sfx": "splash", "hit": "orb",
		"mass": "wave"},
	"blood": {"name": "blood", "color": Color(0.9, 0.08, 0.05), "hot": Color(1.0, 0.5, 0.35), "core": ["vfx_blood_burst", "k_circle_05"],
		"trail": "k_dirt_01", "mote": "k_dirt_02", "impact": ["blood_splat"], "rune": "k_magic_01", "rise": false,
		"cast_sfx": "growl", "hit_sfx": "splash", "hit": "orb", "mass": "claws"},
	"stone": {"name": "stone", "color": Color(0.78, 0.64, 0.45), "hot": Color(1.0, 0.85, 0.6), "core": ["k_dirt_03"],
		"trail": "k_smoke_06", "mote": "k_dirt_02", "impact": ["vfx_lava_crack", "k_smoke_09"],
		"rune": "k_circle_04", "rise": false, "cast_sfx": "rubble", "hit_sfx": "rubble", "hit": "crack",
		"mass": "quake"},
	"gold": {"name": "gold", "color": Color(1.0, 0.76, 0.22), "hot": Color(1.0, 0.95, 0.7), "core": ["vfx_gold_coin", "coin_glint"],
		"trail": "k_star_04", "mote": "k_star_07", "impact": ["coin_glint"], "rune": "k_magic_04", "rise": false,
		"cast_sfx": "coins", "hit_sfx": "coin_spin", "hit": "orb", "mass": "rain"},
	"word": {"name": "word", "color": Color(0.5, 0.9, 0.82), "hot": Color(0.9, 1.0, 0.95), "core": ["vfx_page_glow", "k_star_02"],
		"trail": "k_star_04", "mote": "k_star_07", "impact": ["vfx_glyph_ring", "k_magic_01"],
		"rune": "k_magic_01", "rise": true, "cast_sfx": "page", "hit_sfx": "lock", "hit": "seal", "mass": "seal"},
	"thorn": {"name": "thorn", "color": Color(0.55, 0.78, 0.25), "hot": Color(0.9, 1.0, 0.6), "core": ["k_scratch_01"],
		"trail": "k_dirt_01", "mote": "k_scorch_01", "impact": ["vfx_thorn_vines", "k_scratch_01"], "rune": "k_magic_02",
		"rise": false, "cast_sfx": "blade", "hit_sfx": "blade", "hit": "spikes", "mass": "spikes"},
	"pitch": {"name": "pitch", "color": Color(0.95, 0.38, 0.06), "hot": Color(1.0, 0.65, 0.25), "core": ["k_scorch_02"],
		"trail": "k_smoke_04", "mote": "k_scorch_01", "impact": ["vfx_pitch_splash", "k_scorch_03"], "rune": "k_magic_02",
		"rise": false, "cast_sfx": "spell_fire", "hit_sfx": "splash", "hit": "fall", "mass": "rain"},
	"judgment": {"name": "judgment", "color": Color(1.0, 0.3, 0.12), "hot": Color(1.0, 0.82, 0.55),
		"core": ["vfx_judgment_sigil", "k_magic_03"], "trail": "k_spark_04", "mote": "k_star_07",
		"impact": ["vfx_judgment_sigil", "k_magic_03"], "rune": "k_magic_03", "rise": true,
		"cast_sfx": "bell_funeral", "hit_sfx": "thud", "hit": "smite", "mass": "seal"},
}

## Painted casting circles (assets/vfx/vfx_rune_*.png) per school; the Kenney "rune" stands in until they exist.
const RUNE_ART := {
	"fire": "vfx_rune_fire", "pitch": "vfx_rune_fire", "blood": "vfx_rune_fire", "judgment": "vfx_rune_fire",
	"stone": "vfx_rune_fire", "ice": "vfx_rune_ice", "holy": "vfx_rune_holy", "gold": "vfx_rune_holy",
	"shadow": "vfx_rune_shadow", "wind": "vfx_rune_shadow", "venom": "vfx_rune_venom", "thorn": "vfx_rune_venom",
	"soul": "vfx_rune_soul", "word": "vfx_rune_soul", "water": "vfx_rune_soul",
}

## Each legendary's signature sprite for its entrance (assets/vfx/vfx_leg_*.png).
const LEGEND_ART := {
	"cd_nicholas_iii": "vfx_leg_nicholas", "cd_capaneus": "vfx_leg_capaneus",
	"cd_old_man_crete": "vfx_leg_old_man_crete", "ih_malacoda": "vfx_leg_malacoda", "ih_nimrod": "vfx_leg_nimrod",
	"ih_typhon": "vfx_leg_typhon", "mc_ruggieri": "vfx_leg_ruggieri", "mc_alberigo": "vfx_leg_alberigo",
	"mc_lucifer": "vfx_leg_lucifer", "pj_homer": "vfx_leg_homer", "pj_cato": "vfx_leg_cato",
	"pj_beatrice": "vfx_leg_beatrice", "uh_achilles": "vfx_leg_achilles", "uh_semiramis": "vfx_leg_semiramis",
	"uh_caesar": "vfx_leg_caesar", "francesca": "vfx_leg_francesca", "ugolino": "vfx_leg_ugolino",
	"minos": "vfx_leg_minos",
	# The Wanderer's legendaries borrow the closest painted sigil: Diomedes the spear of Troy, the Horse the cracked
	# statue plate, the Black Cherub the devil's forks, Circe the enchanting swirl, the Mountain the sinking whirlwind.
	"ul_diomedes": "vfx_leg_achilles", "ul_trojan_horse": "vfx_leg_old_man_crete",
	"ul_black_cherub": "vfx_leg_malacoda", "ul_circe": "vfx_leg_semiramis", "ul_distant_mountain": "vfx_leg_typhon",
	# The Wrathful's own: Filippo's red burst of spite, Tydeus' burning helm, the signal fire on the Red Towers and
	# Athamas' whirl of madness.
	"uh_filippo_argenti": "vfx_leg_filippo", "wr_tydeus": "vfx_leg_tydeus", "wr_red_towers": "vfx_leg_red_towers",
	"wr_athamas": "vfx_leg_athamas",
}

## A card's school when data/vfx.json does not name one.
const CIRCLE_SCHOOL := {
	"dark_wood": "thorn", "ante_inferno": "holy", "limbo": "soul", "lust": "wind", "gluttony": "water",
	"greed": "gold", "wrath": "blood", "heresy": "fire", "dis": "shadow", "violence": "fire",
	"malebolge": "pitch", "cocytus": "ice",
}

const HITS := ["orb", "shard", "serpent", "wisp", "gust", "volley", "fall", "beam", "bolt", "lash", "tether",
	"seal", "crack", "spikes", "geyser", "smite", "slash", "claw"]
const MASSES := ["rain", "nova", "gale", "wave", "blizzard", "quake", "radiance", "seal", "wail", "claws",
	"spikes", "frost", "gaze"]
const CASTS := ["", "coins", "pages", "stars", "mana"]
## Patterns that hurt: a buff or a heal reaching a friend never uses them.
const HARSH := ["crack", "spikes", "claw", "slash", "lash", "smite", "fall", "geyser", "bolt", "volley"]

static var _cards := {}
static var _loaded := false


# ================================================================ data

## The card's vfx.json entry merged over its defaults: school, hit, mass, cast, power (0..1, from cost and
## rarity). Hero powers are "power_<hero id>".
static func profile(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_cards = d.get("cards", {})
	var card := CardDB.card(id)
	var p: Dictionary = (_cards.get(id, {}) as Dictionary).duplicate()
	var school: String = p.get("school", CIRCLE_SCHOOL.get(card.get("circle", ""), "fire"))
	if not SCHOOLS.has(school):
		school = "fire"
	p.school = school
	var s: Dictionary = SCHOOLS[school]
	p.hit = p.get("hit", s.hit)
	p.mass = p.get("mass", s.mass)
	p.cast = p.get("cast", "")
	var rarity: String = card.get("rarity", "common")
	p.power = clampf(float(card.get("cost", 2)) / 8.0 + {"epic": 0.2, "legendary": 0.35}.get(rarity, 0.0), 0.0, 1.0)
	p.big = rarity in ["epic", "legendary"]
	return p


static func school(p: Dictionary) -> Dictionary:
	return SCHOOLS[p.school]


## True when data/vfx.json sets `key` for this card itself (not inherited from its school).
static func has_own(id: String, key: String) -> bool:
	profile("")
	return (_cards.get(id, {}) as Dictionary).has(key)
