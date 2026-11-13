extends CanvasLayer
## Intro au lancement : la vidéo du logo, puis le logo fixe, puis un fondu vers le menu.
## Une touche, un bouton de manette ou un clic passe l'intro à tout moment.

signal finished

const VIDEO_PATH := "res://intro.ogv"
const LOGO := preload("res://intro_logo.png")
const LOGO_FADE_IN := 0.6
const LOGO_HOLD := 2.2
const FADE_OUT := 0.6
const LOGO_MARGIN := 0.08

var muted := false
var _root: Control
var _video: VideoStreamPlayer
var _logo: TextureRect
var _logo_shown := false
var _ending := false


func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame := AspectRatioContainer.new()
	frame.ratio = 16.0 / 9.0
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_video)

	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_root.add_child(_logo)
	_logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_logo.anchor_left = LOGO_MARGIN
	_logo.anchor_top = LOGO_MARGIN
	_logo.anchor_right = 1.0 - LOGO_MARGIN
	_logo.anchor_bottom = 1.0 - LOGO_MARGIN
	_logo.pivot_offset = _logo.size / 2.0

	var stream: VideoStream = null
	if ResourceLoader.exists(VIDEO_PATH):
		stream = load(VIDEO_PATH) as VideoStream
	if stream == null:
		_show_logo()
		return
	_video.stream = stream
	_video.volume_db = -80.0 if muted else 0.0
	_video.finished.connect(_show_logo)
	_video.play()


## La vidéo finit sur un gros plan du logo : le logo entier apparaît en fondu par-dessus.
func _show_logo() -> void:
	if _logo_shown or _ending:
		return
	_logo_shown = true
	_logo.pivot_offset = _logo.size / 2.0
	_logo.scale = Vector2.ONE * 1.06
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_logo, "modulate:a", 1.0, LOGO_FADE_IN)
	tween.parallel().tween_property(_logo, "scale", Vector2.ONE, LOGO_FADE_IN + LOGO_HOLD)
	tween.parallel().tween_property(_video, "modulate:a", 0.0, LOGO_FADE_IN)
	tween.tween_callback(_end)


func _end() -> void:
	if _ending:
		return
	_ending = true
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	if _video.is_playing():
		tween.parallel().tween_property(_video, "volume_db", -60.0, FADE_OUT)
	tween.tween_callback(func() -> void:
		_video.stop()
		finished.emit()
		queue_free())


## Toute entrée est retenue pendant l'intro pour ne pas agir sur le menu caché dessous.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion \
			or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	var skip: bool = event.is_pressed() and not event.is_echo() and not event is InputEventJoypadMotion
	if skip:
		_end()
