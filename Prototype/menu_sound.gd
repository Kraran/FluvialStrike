extends Node
## Sons courts des menus, synthétisés au lancement comme ceux de flight_sound.gd.

const RATE := 22050
const SOUNDS := {"move": [0.045, -21.0], "accept": [0.12, -17.0], "back": [0.12, -18.0], "denied": [0.14, -17.0]}
const MOVE_INTERVAL_MS := 35

var _players: Array[AudioStreamPlayer] = []
var _samples := {}
var _cursor := 0
var _last_move := -1000


func _ready() -> void:
	for kind: String in SOUNDS:
		_samples[kind] = _synthesise(kind, SOUNDS[kind][0])
	for i in 3:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(kind: String) -> void:
	if not _samples.has(kind):
		return
	if kind == "move":
		var now := Time.get_ticks_msec()
		if now - _last_move < MOVE_INTERVAL_MS:
			return
		_last_move = now
	var player := _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.stop()
	player.stream = _samples[kind]
	player.volume_db = SOUNDS[kind][1]
	player.play()


func _synthesise(kind: String, duration: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var frames := roundi(duration * RATE)
	data.resize(frames * 2)
	var phase := 0.0
	for frame in frames:
		var t := float(frame) / RATE
		var progress := float(frame) / frames
		var attack := minf(t * 900.0, 1.0)
		var frequency := 0.0
		var sample := 0.0
		match kind:
			"move":
				frequency = 1250.0
				phase += TAU * frequency / RATE
				sample = sin(phase) * exp(-t * 90.0)
			"accept":
				frequency = 760.0 if progress < 0.45 else 1140.0
				phase += TAU * frequency / RATE
				sample = (sin(phase) + 0.25 * sin(phase * 2.0)) * (1.0 - progress)
			"back":
				frequency = 1000.0 if progress < 0.45 else 660.0
				phase += TAU * frequency / RATE
				sample = (sin(phase) + 0.25 * sin(phase * 2.0)) * (1.0 - progress)
			"denied":
				frequency = 170.0
				phase += TAU * frequency / RATE
				sample = clampf(sin(phase) * 2.5, -1.0, 1.0) * 0.6 * (1.0 - progress)
		data.encode_s16(frame * 2, roundi(clampf(sample * attack * 0.8, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
