extends CanvasLayer
## Intro au lancement : la vidéo du logo, puis sa dernière image figée pendant qu'une voix
## annonce le titre, puis un fondu vers le menu.
## Une touche, un bouton de manette ou un clic passe l'intro à tout moment ; la voix est
## alors jouée quand même, une seule fois et en entier, pendant l'arrivée du menu.

signal finished

const VIDEO_PATH := "res://intro.ogv"
const VOICE_PATH := "res://intro_voice.mp3"
## Temps laissé à l'image figée après la fin de la voix, ou sans voix.
const HOLD_AFTER_VOICE := 0.4
const HOLD_WITHOUT_VOICE := 1.5
const FADE_OUT := 0.6

var muted := false
var _root: Control
var _video: VideoStreamPlayer
var _still: TextureRect
var _voice: AudioStreamPlayer
var _voice_started := false
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
	# Dernière image de la vidéo, figée pendant la voix.
	_still = TextureRect.new()
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_SCALE
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_still.visible = false
	frame.add_child(_still)

	_voice = AudioStreamPlayer.new()
	_voice.stream = _load_voice()
	_voice.finished.connect(_on_voice_finished)
	add_child(_voice)

	var stream: VideoStream = null
	if ResourceLoader.exists(VIDEO_PATH):
		stream = load(VIDEO_PATH) as VideoStream
	if stream == null:
		_on_video_finished()
		return
	_video.stream = stream
	_video.volume_db = -80.0 if muted else 0.0
	_video.finished.connect(_on_video_finished)
	_video.play()


## Charge la voix importée par l'éditeur, ou directement le fichier MP3 sans import préalable.
static func _load_voice() -> AudioStream:
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(VOICE_PATH + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(VOICE_PATH):
		var stream := load(VOICE_PATH) as AudioStream
		if stream:
			return stream
	if FileAccess.file_exists(VOICE_PATH):
		return AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(VOICE_PATH))
	return null


## Fin de la vidéo : sa dernière image reste à l'écran et la voix annonce le titre.
func _on_video_finished() -> void:
	if _ending:
		return
	var texture := _video.get_video_texture()
	var image := texture.get_image() if texture else null
	if image and not image.is_empty():
		_still.texture = ImageTexture.create_from_image(image)
		_still.visible = true
	if not _start_voice():
		get_tree().create_timer(HOLD_WITHOUT_VOICE).timeout.connect(_end)


## Lance la voix une seule fois. Renvoie false s'il n'y a rien à jouer.
func _start_voice() -> bool:
	if _voice_started:
		return _voice.playing
	_voice_started = true
	if muted or _voice.stream == null:
		return false
	_voice.play()
	return true


func _on_voice_finished() -> void:
	if _ending:
		# Fondu terminé : plus rien à attendre. Sinon, la fin du fondu libère le nœud.
		if not _root.visible:
			queue_free()
	else:
		get_tree().create_timer(HOLD_AFTER_VOICE).timeout.connect(_end)


## Fondu vers le menu. La voix n'est jamais coupée : si elle joue encore, le nœud attend
## sa fin, invisible et sans plus retenir les entrées, avant de disparaître.
func _end() -> void:
	if _ending:
		return
	_ending = true
	_start_voice()
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	if _video.is_playing():
		tween.parallel().tween_property(_video, "volume_db", -60.0, FADE_OUT)
	tween.tween_callback(func() -> void:
		_video.stop()
		_root.visible = false
		set_process_input(false)
		finished.emit()
		if not _voice.playing:
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
