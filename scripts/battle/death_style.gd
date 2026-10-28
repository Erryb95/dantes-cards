class_name DeathStyle
## Which death a kill gets (DeathFx stages it): the killer school of a death event, the style each school kills in,
## the styles' shader modes, timing and sounds, the quality level and the particle budget. Pure data and rules (no
## nodes, no autoloads), so the headless tests can check it.

enum { OFF, LITE, FULL }

static var forced := -1 ## tests / previews: a quality level to use instead of level()

## Killer school -> death style. Every school in VfxData.SCHOOLS has one (tested).
const STYLE_OF := {
	"fire": "burn", "judgment": "burn", "pitch": "tar", "ice": "shatter", "venom": "melt", "soul": "spirit",
	"shadow": "spirit", "stone": "crumble", "wind": "shred", "water": "sink", "blood": "rend", "thorn": "rend",
	"holy": "fade", "word": "fade", "gold": "coins",
}

## mode: death_mode in the shader. pre: the share of the time spent before the dissolve starts. sfx: played as it
## begins, late: when it breaks (Sfx name, dB, pitch).
const STYLES := {
	"burn": {"mode": 1, "pre": 0.3, "sfx": [["spell_fire", -8.0, 0.8], ["creature_die", -14.0, 1.0]], "late": []},
	"tar": {"mode": 2, "pre": 0.4, "sfx": [["splash", -8.0, 0.55]], "late": [["spell_fire", -12.0, 0.65]]},
	"shatter": {"mode": 3, "pre": 0.4, "sfx": [["ice", -8.0, 0.9]], "late": [["glass", -4.0, 0.75]]},
	"melt": {"mode": 4, "pre": 0.3, "sfx": [["vial", -8.0, 0.6]], "late": [["splash", -12.0, 0.65]]},
	"spirit": {"mode": 5, "pre": 0.3, "sfx": [["sigh", -10.0, 0.9]], "late": [["whoosh", -14.0, 0.6]]},
	"crumble": {"mode": 6, "pre": 0.45, "sfx": [["rubble", -12.0, 1.3]], "late": [["rubble", -5.0, 0.8],
		["bones", -14.0, 0.9]]},
	"shred": {"mode": 7, "pre": 0.15, "sfx": [["gust", -6.0, 1.1]], "late": [["whoosh", -10.0, 0.8]]},
	"sink": {"mode": 8, "pre": 0.25, "sfx": [["splash", -6.0, 0.8]], "late": [["splash", -11.0, 0.6]]},
	"rend": {"mode": 9, "pre": 0.15, "sfx": [["blade", -8.0, 0.8], ["creature_die", -12.0, 1.0]], "late": []},
	"fade": {"mode": 10, "pre": 0.3, "sfx": [["magic", -12.0, 1.3]], "late": [["gem", -10.0, 0.9]]},
	"coins": {"mode": 11, "pre": 0.4, "sfx": [["coin_spin", -8.0, 0.9]], "late": [["coins", -6.0, 1.0]]},
}

## Schools whose own sound replaces the style's opening one.
const SCHOOL_SFX := {
	"soul": [["wail", -12.0, 1.2]], "judgment": [["thud", -6.0, 0.7], ["spell_fire", -10.0, 0.9]],
	"word": [["page", -6.0, 0.8]], "thorn": [["blade", -8.0, 1.1], ["bones", -14.0, 1.2]],
}

const LEAD := 0.2 ## the killer's impact (and the damage number) has its moment before the piece gives way
const TIME := 0.85 ## a minion's death at normal speed after the lead: pre phase + dissolve
const HERO_TIME := 1.5 ## a hero's defeat after its lead


## How much of the deaths' particles run here: FULL, LITE (half the particles, no extra lights) on phones and at a
## 30 fps frame limit, OFF (the dissolve alone). DV_DEATHFX=0/1/2 forces it.
static func level() -> int:
	if forced >= 0:
		return forced
	var env := OS.get_environment("DV_DEATHFX")
	if env != "":
		return clampi(int(env), OFF, FULL)
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	if settings != null and (int(settings.get("frame_limit")) == 30 or settings.call("is_mobile")):
		return LITE
	return FULL


## The particle budget of one death among `n` played back to back (a board-wide clear): the counts shrink as more
## pieces die at once, so seven deaths cost about twice one.
static func budget(n: int) -> float:
	var q := 1.0 if n <= 1 else clampf(1.8 / n, 0.3, 1.0)
	match level():
		LITE:
			q *= 0.5
		OFF:
			q = 0.0
	return q


## The school a blow kills with. `killer` / `how` as in the death event (BattleState._kill_info).
## - a minion's attack or fight: that minion's school; a neutral body (no school of its own, no circle) strikes a
##   plain physical blow, "blood";
## - Venom always kills with venom; fatigue (the empty deck) with shadow;
## - a spell, a minion's effect, a destroy, a transform or a lost bounce: that card's school;
## - a hero power ("power_<hero>") or a hero: the hero's power school;
## - "" for a sourceless death (the caller falls back on the victim's own school).
static func killer_school(killer: String, how: String) -> String:
	if how == "venom":
		return "venom"
	if how == "fatigue" or killer == "fatigue":
		return "shadow"
	if killer == "":
		return ""
	if killer.begins_with("power_"):
		return VfxData.profile(killer).school
	if not CardDB.hero(killer).is_empty():
		return VfxData.profile("power_" + killer).school
	var card := CardDB.card(killer)
	if card.is_empty():
		return "blood"
	if card.get("type", "") == "minion" and not VfxData.has_own(killer, "school") \
			and not VfxData.CIRCLE_SCHOOL.has(str(card.get("circle", ""))):
		return "blood"
	return VfxData.profile(killer).school


## The school a death is staged in: the killer's, or the victim's own when nothing struck it.
static func school_for(ev: Dictionary, victim_id: String) -> String:
	var k := killer_school(str(ev.get("killer", "")), str(ev.get("how", "")))
	return k if k != "" else VfxData.profile(victim_id).school


static func style_for(school: String) -> String:
	return STYLE_OF.get(school, "burn")
