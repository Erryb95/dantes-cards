class_name CreditsPanel
extends Control
## Modal credits (opened from Options): who made what, condensed for players from assets/CREDITS.md. The heading on
## the charred banner, then one framed plate per section in a painted scroll, then Done. Keep it in step with
## assets/CREDITS.md when assets are added; the AI-generated art is always named as such.

const BAR_W := 22 ## the painted scroll bar
const BAR_ROOM := 30.0 ## the scroll bar and its gap, right of the sheets

## [heading, text] per section, in reading order.
const SECTIONS := [
	["Art", "The card, hero, arena and card-back paintings, the painted frames, plates and gems of the interface and the "
		+ "spell effects are AI-generated. We made them on our own computer with Qwen-Image 2512 (Apache-2.0 licence), "
		+ "in the style of Gustave Doré's engravings. The animated legendary cards are AI-generated as well, with Wan 2.2 "
		+ "(Apache-2.0), from each card's own painting. Depth Anything V2 Small (Apache-2.0) estimates the depth behind "
		+ "the cards' parallax."],
	["Gustave Doré", "Doré's engravings for the Inferno (1861, public domain) are the model for the whole look of the "
		+ "game, and his own plates make the opening cinematic. Four of its clips were set in motion with the AI video "
		+ "model Wan 2.2; the others are the plates themselves."],
	["Narration", "Cori Samuel reading Longfellow's translation of the Inferno, a LibriVox recording (public domain)."],
	["Music", "Public-domain and CC0 recordings:\n"
		+ "Brahms, A German Requiem: II, and Cherubini, Requiem in C minor: Introitus and Dies irae, sung by the "
		+ "St Matthews Choir (CC0).\n"
		+ "Tchaikovsky, Symphony No. 6 \"Pathétique\": I, III and IV · Suk, Meditation on the Old Czech Chorale "
		+ "\"St Wenceslas\" · Beethoven, Coriolan Overture and Egmont Overture · Mozart, Symphony No. 40: I · Brahms, "
		+ "Symphony No. 4: IV and Tragic Overture, played for Musopen (public domain)."],
	["Sound effects", "CC0 sounds by Kenney, rubberduck, Vehicle, bart, JaggedStone, qubodup, Ogrebane, artisticdude, "
		+ "Voltiment555, AntumDeluge, Andrastos87, Henrythetrain, Divinux, xXx_JPMC_xXx, nene, aoristos, uagadugu, "
		+ "Umplix and others, from Freesound, OpenGameArt and kenney.nl. Particle textures by Kenney (CC0)."],
	["Character voices", "Every character's cries, growls, sighs and laughs are CC0 recordings (no speech, no AI audio), "
		+ "cut, pitched and layered for each card: by rubberduck, HaelDB, mieki256, Stormyman (Christopher Hahn), "
		+ "Nocturnal_Vanguard, StarNinjas, Exewin, thebardofblasphemy, Darsycho, qubodup, Badre-Eddine, AntumDeluge, "
		+ "ArcadeParty, OwlishMedia, artisticdude, EmoPreben, Reitanna, LookIMadeAThing and more than 200 other "
		+ "Freesound and OpenGameArt contributors (all listed in CREDITS.md)."],
	["Fonts", "Cinzel by Natanael Gama and IM Fell English by Igino Marini (SIL Open Font Licence)."],
	["Engine", "Made with Godot Engine (MIT licence), by Juan Linietsky, Ariel Manzur and the Godot Engine contributors."],
	["Online and statistics", "Online duels and the account's cloud save run on Nakama (Apache-2.0 licence), on our own "
		+ "server. To balance the decks the game sends anonymous match statistics after each match: classes, decks, the "
		+ "result, turns and length. No name, e-mail or device id is kept with them."],
]


## The "Credits" plate for the Options panel `host`: opens the credits over it (one line there:
## `<column>.add_child(CreditsPanel.open_button(self))`).
static func open_button(host: Control) -> Button:
	var b := UI.button("Credits", 400, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): host.get_parent().add_child(CreditsPanel.new()))
	return b


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110 # above the options panel it is opened from
	var vs := get_viewport_rect().size
	var dim := ColorRect.new() # the veil, like the options panel's
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var s := UI.frame_box("panel_frame_filled", 96, 0,
		UI.box(Color(0.09, 0.05, 0.04, 0.97), UI.GOLD, 3, 14, Color(0, 0, 0, 0.7), 30))
	s.content_margin_left = 100 # clear of the painted frame's inner edge, like the options panel
	s.content_margin_right = 100
	s.content_margin_top = 56
	s.content_margin_bottom = 64
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(UI.banner("Credits", 46, UI.GOLD, 0.0, 0.0, 1.8))
	# The sections scroll in what the screen leaves between the banner and Done.
	var w := minf(1000.0, vs.x - 280.0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(w + BAR_ROOM, minf(760.0, vs.y - 120.0 - 83.0 - 76.0 - 32.0 - 120.0))
	UI.paint_scroll(scroll, BAR_W)
	# The scroll bar's room mirrored on the left, so the parchment sheets, and not sheets plus bar, are centred under
	# the banner and over Done.
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 0)
	var pad := Control.new()
	pad.custom_minimum_size.x = BAR_ROOM
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(pad)
	srow.add_child(scroll)
	v.add_child(srow)
	# The sheets w wide: the scroll fits its content to its width less the bar's, the rest of BAR_ROOM is the gap.
	var gap := MarginContainer.new()
	gap.add_theme_constant_override("margin_right", int(BAR_ROOM) - BAR_W)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gap)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	gap.add_child(list)
	for sec in SECTIONS:
		list.add_child(_section(sec[0], sec[1], w))
	var ver := UI.label("Dante's Inferno: The Card Game  ·  version %s" %
		ProjectSettings.get_setting("application/config/version"), 22, "italic", Color(0.86, 0.8, 0.7), 3, Color.BLACK)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.custom_minimum_size = Vector2(w, 0)
	var vp := UI.plaque(24, 8)
	vp.add_child(ver)
	list.add_child(vp)
	var done := UI.button("Done", 300)
	done.pressed.connect(_close)
	var dc := CenterContainer.new()
	dc.add_child(done)
	v.add_child(dc)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _close() -> void:
	queue_free()


## One section: its heading in dark crimson over the text in ink, on the parchment tip sheet.
func _section(title: String, text: String, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.tip_box())
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	col.add_child(UI.label(title, 28, "title", UI.INK_RED))
	var body := UI.label(text, 24, "body", UI.INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(w - 110.0, 0)
	col.add_child(body)
	return p
