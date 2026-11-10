extends Node

const FLIGHT = preload("res://flight.gd")
const RATE := 22050
const DURATIONS := {"engine": 1.0, "fire": 0.17, "hit": 0.38, "bridge": 0.78,
	"crash": 0.60, "fuel": 0.15, "alarm": 0.28}

var muted := false
var _engine := AudioStreamPlayer.new()
var _effects: Array[AudioStreamPlayer] = []
var _samples := {}
var _event_cursor := 0
var _last_fuel := FLIGHT.FULL_TANK
var _effect_cursor := 0


func _ready() -> void:
	for sound: String in DURATIONS:
		_samples[sound] = _synthesise(sound, DURATIONS[sound])
	_engine.stream = _samples.engine
	_engine.volume_db = -21
	add_child(_engine)
	for i in range(5):
		var player := AudioStreamPlayer.new()
		player.volume_db = -14
		add_child(player)
		_effects.append(player)


func reset() -> void:
	_event_cursor = 0
	_last_fuel = FLIGHT.FULL_TANK
	silence()


func silence() -> void:
	_engine.stop()
	for player in _effects:
		player.stop()


func sync(flight: FLIGHT) -> void:
	var active := flight.status == FLIGHT.Status.FLYING
	if muted or not active:
		_engine.stop()
	else:
		_engine.pitch_scale = lerpf(0.72, 1.32, float(flight.speed - 64) / 190.0)
		if not _engine.playing:
			_engine.play()

	if not muted:
		for i in range(_event_cursor, flight.events.size()):
			var kind: String = flight.events[i].kind
			if kind in ["fire", "bridge", "crash"]:
				_play(kind)
			elif FLIGHT.POINTS.has(kind):
				_play("hit")
		if active and flight.fuel < FLIGHT.LOW_FUEL and flight.tick % 48 == 0:
			_play("alarm")
		if active and flight.fuel > _last_fuel and flight.tick % 7 == 0:
			_play("fuel")
	_event_cursor = flight.events.size()
	_last_fuel = flight.fuel


func _play(kind: String) -> void:
	var player := _effects[_effect_cursor]
	_effect_cursor = (_effect_cursor + 1) % _effects.size()
	player.stream = _samples[kind]
	player.play()


func _synthesise(kind: String, duration: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3405
	var data := PackedByteArray()
	var frames := roundi(duration * RATE)
	data.resize(frames * 2)
	var filtered := 0.0
	for frame in frames:
		var t := float(frame) / RATE
		var end := 1.0 - float(frame) / frames
		var envelope := minf(t * 260.0, 1.0) * end * end
		var noise := rng.randf_range(-1, 1)
		filtered = lerpf(filtered, noise, 0.13)
		var sample := 0.0
		match kind:
			"engine":
				sample = sin(TAU * 57.0 * t) * 0.23 + sin(TAU * 114.0 * t) * 0.13
				sample += sin(TAU * 171.0 * t + sin(TAU * 9.0 * t) * 0.7) * 0.08
			"fire":
				sample = envelope * (0.60 * noise + 0.45 * sin(TAU * t * (415.0 - t * 1350.0)))
			"bridge", "crash", "hit":
				sample = envelope * (0.30 * noise + 1.5 * filtered + sin(TAU * 57.0 * t) * 0.28)
			"fuel":
				sample = envelope * sin(TAU * t * (585.0 + t * 1250.0)) * 0.58
			"alarm":
				var tone := 540.0 if t < 0.14 else 420.0
				sample = envelope * (sin(TAU * tone * t) + 0.24 * sin(TAU * tone * 2 * t)) * 0.56
		data.encode_s16(frame * 2, roundi(clampf(sample, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	if kind == "engine":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = frames
	return stream
