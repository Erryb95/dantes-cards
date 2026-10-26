class_name ArtLoop
extends VideoStreamPlayer
## Plays a legendary card's looping art (CardDB.art_loop) in place of its still picture. The player itself is invisible
## (2x2, alpha 0, like the intro's clips); its video texture is fed into the card's art TextureRect, which keeps its
## card_fx material, so the rounded / oval mask, shine and burn-away work unchanged. The still stays on screen until
## the first video frame arrives. The player only decodes while the card is on screen (not hidden, face up, not
## scrolled out of a ScrollContainer) and is freed with its card.

const MAX_ACTIVE := 12 ## decoders alive at once; further legendaries keep their still
const MARGIN := 120.0 ## a card this close to the edge of the screen / scroll area still plays
const START_GAP_MS := 60 ## minimum time between two decoder starts, so a screen of legendaries does not hitch

static var _active := 0
static var _last_start := 0

var _gate: CanvasItem
var _target: TextureRect
var _mat: ShaderMaterial
var _crop: Rect2
var _started := false
var _shown := false
var _check := 0.0


## Adds a loop for `card_id` to `art` when the card has one (otherwise does nothing). `gate` is the node whose
## visibility decides whether the video plays; `aspect` / `focus_y` are the ones the still was framed with.
static func attach(parent: Node, gate: CanvasItem, art: TextureRect, mat: ShaderMaterial, card_id: String,
		aspect: float, focus_y: float) -> void:
	var stream := CardDB.art_loop(card_id)
	if stream == null:
		return
	var loop := ArtLoop.new()
	loop.stream = stream
	loop.loop = true
	loop.volume_db = -80.0
	loop.custom_minimum_size = Vector2(2, 2)
	loop.size = Vector2(2, 2)
	loop.modulate.a = 0.0
	loop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loop._gate = gate
	loop._target = art
	loop._mat = mat
	loop._crop = CardDB.art_crop_uv(card_id, aspect, focus_y)
	parent.add_child(loop)


func _exit_tree() -> void:
	if _started:
		_active -= 1
		_started = false


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 and (_shown or not _started): # slow poll; per frame only while waiting for the first frame
		return
	_check = 0.2
	var want := _gate.is_visible_in_tree() and _on_screen()
	if not _started:
		var now := Time.get_ticks_msec()
		if not want or _active >= MAX_ACTIVE or now - _last_start < START_GAP_MS:
			return
		_last_start = now
		_started = true
		_active += 1
		play()
	paused = not want
	if _shown or not is_playing() or stream_position <= 0.0:
		return
	var tex := get_video_texture()
	if tex == null or tex.get_width() <= 0:
		return
	_shown = true
	_mat.set_shader_parameter("crop", Vector4(_crop.position.x, _crop.position.y, _crop.size.x, _crop.size.y))
	_target.stretch_mode = TextureRect.STRETCH_SCALE # the shader does the cropping; UV is 0..1 across the rect
	_target.texture = tex


## The gate's centre lies inside the screen and inside every ScrollContainer it sits in (collection pages are long).
func _on_screen() -> bool:
	var xf := _gate.get_global_transform_with_canvas()
	var centre := xf * ((_gate as Control).size / 2.0 if _gate is Control else Vector2.ZERO)
	if not get_viewport().get_visible_rect().grow(MARGIN).has_point(centre):
		return false
	var n := _gate.get_parent()
	while n != null:
		if n is ScrollContainer:
			var sx := (n as ScrollContainer).get_global_transform_with_canvas()
			if not Rect2(sx.origin, (n as ScrollContainer).size * sx.get_scale()).grow(MARGIN).has_point(centre):
				return false
		n = n.get_parent()
	return true
