extends Node
## Musique d'ambiance : un morceau en boucle infinie, qui démarre (ou reprend) par un fondu
## et s'interrompt par un fondu court. La vue indique à chaque image s'il doit jouer.

const FADE_IN := 2.0
const FADE_OUT := 0.6
const PATH := "res://music/%s.ogg"

var _player := AudioStreamPlayer.new()
var _track := ""
var _level := 0.0
var _target := 0.0
var _gain := 1.0


func _init() -> void:
	_player.name = "MusicPlayer"
	add_child(_player)


## track : identifiant du morceau ; active : la musique doit-elle jouer ; volume : 0 à 1.
func update(track: String, active: bool, volume: float, delta: float) -> void:
	if track != _track:
		_track = track
		_player.stop()
		_player.stream = _load(track)
		_level = 0.0
	_gain = clampf(volume, 0.0, 1.0)
	_target = 1.0 if active and _gain > 0.0 and _player.stream else 0.0
	if _target > 0.0:
		_level = minf(1.0, _level + delta / FADE_IN)
		if not _player.playing and _player.is_inside_tree():
			_player.play()
		_player.stream_paused = false
	else:
		_level = maxf(0.0, _level - delta / FADE_OUT)
		if _level <= 0.0 and not _player.stream_paused:
			_player.stream_paused = true
	_player.volume_db = linear_to_db(maxf(_level * _level * _gain, 0.0001))


## Charge le morceau importé par l'éditeur, ou directement le fichier Ogg sans import préalable.
static func _load(track: String) -> AudioStream:
	var path := PATH % track
	var stream: AudioStreamOggVorbis
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(path + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(path):
		stream = load(path) as AudioStreamOggVorbis
	if stream == null and FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if stream:
		stream.loop = true
	return stream
