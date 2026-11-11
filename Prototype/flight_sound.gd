extends Node

const FLIGHT = preload("res://flight.gd")
const RATE := 22050
const DURATIONS := {"engine": 1.0, "fire": 0.16, "hit": 0.31, "bridge": 1.05,
	"crash": 0.66, "splash": 0.26, "debris": 0.47, "fuel": 0.15, "alarm": 0.28,
	"jet": 1.0, "helicopter": 1.0, "tanker": 1.0}
const GAIN_DB := {"fire": -14.0, "hit": -13.0, "bridge": -10.0, "crash": -12.0,
	"splash": -15.0, "debris": -14.0, "fuel": -18.0, "alarm": -14.0}
const BRIDGE_CLANKS := [0.065, 0.16, 0.29]
const ENEMY_GAIN_DB := {"jet": -24.0, "helicopter": -21.0, "tanker": -31.0}


class StereoVoice:
	var player := AudioStreamPlayer.new()
	var panner := AudioEffectPanner.new()
	var level := 0.0

var muted := false
var _engine := AudioStreamPlayer.new()
var _effects: Array[StereoVoice] = []
var _enemies := {}
var _voice_buses: Array[StringName] = []
var _samples := {}
var _event_cursor := 0
var _last_fuel := FLIGHT.FULL_TANK
var _effect_cursor := 0


func _ready() -> void:
	for sound: String in DURATIONS:
		_samples[sound] = _synthesise(sound, DURATIONS[sound])
	_engine.stream = _samples.engine
	add_child(_engine)
	for i in range(8):
		_effects.append(_make_voice())
	for kind: String in ENEMY_GAIN_DB:
		var voice := _make_voice()
		voice.player.stream = _samples[kind]
		_enemies[kind] = voice


func _make_voice() -> StereoVoice:
	var voice := StereoVoice.new()
	var bus := AudioServer.bus_count
	var name := StringName("FluvialStereo%d_%d" % [get_instance_id(), _voice_buses.size()])
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, name)
	AudioServer.add_bus_effect(bus, voice.panner)
	_voice_buses.append(name)
	voice.player.bus = name
	add_child(voice.player)
	return voice


func _exit_tree() -> void:
	silence()
	for i in range(_voice_buses.size() - 1, -1, -1):
		var bus := AudioServer.get_bus_index(_voice_buses[i])
		if bus > 0:
			AudioServer.remove_bus(bus)
	_voice_buses.clear()


func reset() -> void:
	_event_cursor = 0
	_last_fuel = FLIGHT.FULL_TANK
	silence()


func silence() -> void:
	_engine.stop()
	for voice in _effects:
		voice.player.stop()
	for voice: StereoVoice in _enemies.values():
		voice.player.stop()
		voice.level = 0.0


func sync(flight: FLIGHT) -> void:
	var active := flight.status == FLIGHT.Status.FLYING
	if muted or not active:
		_engine.stop()
	else:
		var throttle := clampf(float(flight.speed - FLIGHT.MIN_SPEED) / (FLIGHT.MAX_SPEED - FLIGHT.MIN_SPEED), 0.0, 1.0)
		_engine.pitch_scale = lerpf(0.72, 1.32, throttle)
		_engine.volume_db = lerpf(-24.0, -18.0, throttle)
		if not _engine.playing:
			_engine.play()

	if not muted:
		for i in range(_event_cursor, flight.events.size()):
			if flight.events[i].kind == "fire":
				_play("fire", 0.0)
		if active and flight.fuel < FLIGHT.LOW_FUEL and flight.tick % 48 == 0:
			_play("alarm", 0.0)
		if active and flight.fuel > _last_fuel and flight.tick % 7 == 0:
			_play("fuel", 0.0)
	_event_cursor = flight.events.size()
	_last_fuel = flight.fuel


func update_enemies(sources: Dictionary, delta: float) -> void:
	var weight := 1.0 - exp(-12.0 * delta)
	for kind: String in _enemies:
		var voice: StereoVoice = _enemies[kind]
		var source: Vector2 = sources.get(kind, Vector2(voice.panner.pan, 0.0))
		voice.level = lerpf(voice.level, source.y, weight)
		if voice.level < 0.005:
			voice.player.stop()
			continue
		voice.player.volume_db = ENEMY_GAIN_DB[kind] + linear_to_db(voice.level)
		if voice.player.playing:
			voice.panner.pan = lerpf(voice.panner.pan, source.x, weight)
		else:
			voice.panner.pan = source.x
			voice.player.play()


func play_spatial_effect(kind: String, pan: float) -> void:
	if not muted:
		_play(kind, pan)


func _play(kind: String, pan: float) -> void:
	var voice := _effects[_effect_cursor]
	_effect_cursor = (_effect_cursor + 1) % _effects.size()
	voice.player.stop()
	voice.panner.pan = pan
	voice.player.stream = _samples[kind]
	voice.player.volume_db = GAIN_DB[kind]
	voice.player.play()


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
				var pulse := sin(TAU * 7.0 * t)
				sample = sin(TAU * 58.0 * t) * 0.29 + sin(TAU * 116.0 * t) * 0.12
				sample += sin(TAU * 232.0 * t + pulse * 0.55) * 0.09
				sample += sin(TAU * 696.0 * t + pulse * 0.3) * 0.035
			"jet":
				var turbine := sin(TAU * 141.0 * t) + sin(TAU * 286.0 * t) * 0.37
				sample = turbine * 0.34 + sin(TAU * 716.0 * t + sin(TAU * 6.0 * t)) * 0.09
			"helicopter":
				var blade_pass := pow(0.5 + 0.5 * cos(TAU * 18.0 * t), 6.0)
				var rotor := sin(TAU * 54.0 * t) * (0.12 + 0.39 * blade_pass)
				var blade_air := sin(TAU * 306.0 * t + 0.9 * sin(TAU * 36.0 * t))
				sample = rotor + blade_pass * (sin(TAU * 126.0 * t) * 0.18 + blade_air * 0.075)
			"tanker":
				var diesel := sin(TAU * 46.0 * t) + sin(TAU * 92.0 * t) * 0.42
				sample = diesel * (0.32 + 0.12 * sin(TAU * 8.0 * t))
			"fire":
				var crack := noise * exp(-t * 34.0) * 0.61
				var thump := sin(TAU * t * (470.0 - t * 1350.0)) * exp(-t * 19.0)
				sample = envelope * (crack + thump * 0.52)
			"hit":
				var ring := sin(TAU * 580.0 * t) * 0.32 + sin(TAU * 937.0 * t) * 0.15
				sample = envelope * (ring * exp(-t * 9.0) + noise * exp(-t * 33.0) * 0.44)
			"bridge":
				var boom := sin(TAU * t * (66.0 - t * 20.0)) * 0.55 + filtered * 0.87
				sample = boom * envelope * exp(-t * 2.8) + noise * envelope * exp(-t * 17.0) * 0.21
				for onset: float in BRIDGE_CLANKS:
					var age := t - onset
					if age >= 0.0:
						var metal := sin(TAU * 247.0 * age) + sin(TAU * 389.0 * age) * 0.48
						sample += metal * minf(age * 420.0, 1.0) * exp(-age * 15.0) * end * end * 0.19
			"crash":
				var rumble := sin(TAU * t * (92.0 - 35.0 * t)) * 0.24 + filtered * 1.05
				var flutter := 0.72 + sin(TAU * 19.0 * t) * 0.28
				sample = envelope * (rumble * flutter + noise * exp(-t * 12.0) * 0.45)
			"splash":
				var drops := sin(TAU * t * (370.0 - t * 510.0)) * exp(-t * 13.0)
				sample = envelope * (filtered * 0.94 + noise * 0.24 + drops * 0.29)
			"debris":
				var surge := sin(TAU * t * (122.0 - t * 120.0)) * exp(-t * 6.0)
				sample = envelope * (filtered * 0.98 + noise * 0.14 + surge * 0.44)
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
	if kind == "engine" or ENEMY_GAIN_DB.has(kind):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = frames
	return stream
