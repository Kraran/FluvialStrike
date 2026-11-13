extends Node

const FLIGHT = preload("res://flight.gd")
const RATE := 22050
const DURATIONS := {"engine": 1.0, "fire": 0.16, "bridge": 1.05,
	"jet_break": 0.51, "rotor_break": 0.36, "tanker_blast": 0.66, "tanker_secondary": 0.44, "fuel_blast": 0.94,
	"crash": 1.9, "water_crash": 1.7, "glide": 1.0, "game_over": 1.6, "extra_life": 0.75, "splash": 0.26, "debris": 0.47, "fuel": 0.15, "alarm": 0.28,
	"jet": 1.0, "helicopter": 1.0, "tanker": 1.0}
const GAIN_DB := {"fire": -14.0, "bridge": -10.0, "crash": -14.5, "water_crash": -13.0, "glide": -15.0, "game_over": -12.0, "extra_life": -15.0,
	"jet_break": -12.0, "rotor_break": -14.0, "tanker_blast": -11.0, "tanker_secondary": -13.5, "fuel_blast": -10.0,
	"splash": -15.0, "debris": -14.0, "fuel": -18.0, "alarm": -14.0}
const BRIDGE_CLANKS := [0.065, 0.16, 0.29]
# Explosions secondaires du crash, aux mêmes instants que les boules de feu à l'écran.
const CRASH_BLASTS := [0.13, 0.31]
# Chute dans l'eau : l'eau de la gerbe retombe à ces instants, comme à l'écran.
const WATER_FALLBACKS := [0.32, 0.55]
const ENEMY_GAIN_DB := {"jet": -24.0, "helicopter": -21.0, "tanker": -31.0}
# Sons enregistrés : moteur en boucle et tir. Sans ces fichiers, les sons synthétisés restent.
const RECORDED := {"engine": "res://sfx_engine.wav", "fire": "res://sfx_fire.wav"}
# Correction de niveau des enregistrements pour garder l'équilibre du mixage (mesuré en LUFS).
const RECORDED_GAIN_DB := {"engine": -4.8, "fire": -3.0}
# Le moteur s'éclaircit en accélérant : coupure du filtre passe-bas, du ralenti à la pleine poussée.
const ENGINE_CUTOFF_HZ := Vector2(1800.0, 9000.0)


class StereoVoice:
	var player := AudioStreamPlayer.new()
	var panner := AudioEffectPanner.new()
	var level := 0.0

var muted := false
var _engine := AudioStreamPlayer.new()
var _engine_filter := AudioEffectLowPassFilter.new()
var _engine_bus := StringName()
var _gain_db := GAIN_DB.duplicate()
var _engine_gain_db := 0.0
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
	for kind: String in RECORDED:
		var recorded := _load_recorded(RECORDED[kind], kind == "engine")
		if recorded:
			_samples[kind] = recorded
			if kind == "engine":
				_engine_gain_db = RECORDED_GAIN_DB[kind]
			else:
				_gain_db[kind] = GAIN_DB[kind] + RECORDED_GAIN_DB[kind]
	_engine.stream = _samples.engine
	_engine_bus = StringName("FluvialEngine%d" % get_instance_id())
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, _engine_bus)
	_engine_filter.cutoff_hz = ENGINE_CUTOFF_HZ.y
	AudioServer.add_bus_effect(bus, _engine_filter)
	_voice_buses.append(_engine_bus)
	_engine.bus = _engine_bus
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


func reset(flight: FLIGHT = null) -> void:
	_event_cursor = flight.events.size() if flight else 0
	_last_fuel = flight.fuel if flight else FLIGHT.FULL_TANK
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
		_engine.volume_db = lerpf(-24.0, -18.0, throttle) + _engine_gain_db
		_engine_filter.cutoff_hz = ENGINE_CUTOFF_HZ.x * pow(ENGINE_CUTOFF_HZ.y / ENGINE_CUTOFF_HZ.x, throttle)
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
	voice.player.volume_db = _gain_db[kind]
	# Un tir enregistré varie légèrement d'un coup à l'autre, comme une vraie arme.
	voice.player.pitch_scale = randf_range(0.96, 1.04) if kind == "fire" and RECORDED.has(kind) else 1.0
	voice.player.play()


## Charge un son importé par l'éditeur, ou directement le fichier WAV sans import préalable.
func _load_recorded(path: String, loop: bool) -> AudioStreamWAV:
	var stream: AudioStreamWAV
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(path + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(path):
		stream = load(path) as AudioStreamWAV
	if stream == null and FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if stream and loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream


func _synthesise(kind: String, duration: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3405
	var data := PackedByteArray()
	var frames := roundi(duration * RATE)
	data.resize(frames * 2)
	var filtered := 0.0
	var low := 0.0
	var crackle := 0.0
	var hiss := 0.0
	var spool := 0.0
	for frame in frames:
		var t := float(frame) / RATE
		var end := 1.0 - float(frame) / frames
		var envelope := minf(t * 260.0, 1.0) * end * end
		var noise := rng.randf_range(-1, 1)
		filtered = lerpf(filtered, noise, 0.13)
		low = lerpf(low, noise, 0.045)
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
			"jet_break":
				var snap := noise * 0.68 * exp(-t * 16.0)
				var tear := sin(TAU * t * (640.0 - 380.0 * t)) * 0.23 * exp(-t * 7.0)
				sample = envelope * (snap + tear + filtered * 0.67 * exp(-t * 5.2))
			"rotor_break":
				var strike := sin(TAU * t * 485.0) + sin(TAU * t * 853.0) * 0.52
				var stutter := 0.5 + 0.5 * cos(TAU * t * (25.0 - 29.0 * t))
				sample = envelope * (strike * 0.32 * exp(-t * 11.0) + noise * 0.45 * stutter * exp(-t * 8.0))
			"tanker_blast", "tanker_secondary":
				var pitch := 72.0 if kind == "tanker_blast" else 86.0
				var thud := sin(TAU * t * (pitch - 23.0 * t)) * 0.42 + filtered * 0.66
				var metal := sin(TAU * t * 247.0) * 0.12 * exp(-t * 15.0)
				sample = envelope * (thud * exp(-t * 5.8) + metal)
			"fuel_blast":
				var front := noise * 0.69 * exp(-t * 18.0)
				var roar := filtered * 1.07 + sin(TAU * t * (96.0 - 38.0 * t)) * 0.28
				sample = envelope * (front + roar * exp(-t * 2.7))
			"bridge":
				var boom := sin(TAU * t * (66.0 - t * 20.0)) * 0.55 + filtered * 0.87
				sample = boom * envelope * exp(-t * 2.8) + noise * envelope * exp(-t * 17.0) * 0.21
				for onset: float in BRIDGE_CLANKS:
					var age := t - onset
					if age >= 0.0:
						var metal := sin(TAU * 247.0 * age) + sin(TAU * 389.0 * age) * 0.48
						sample += metal * minf(age * 420.0, 1.0) * exp(-age * 15.0) * end * end * 0.19
			"crash":
				# Claquement, boum grave qui descend, grondement du feu, crépitements et
				# deux réservoirs qui explosent à leur tour.
				var tail := 1.0 - smoothstep(1.3, duration, t)
				var attack := minf(t * 330.0, 1.0)
				var crack := noise * exp(-t * 55.0) * 0.95
				var boom := sin(TAU * (38.0 * t + 9.5 * (1.0 - exp(-t * 6.0)))) * exp(-t * 2.9) * 0.82
				var flutter := 0.78 + sin(TAU * 9.0 * t) * 0.14 + sin(TAU * 23.0 * t) * 0.08
				var roar := (low * 3.1 + filtered * 0.55) * exp(-t * 1.55) * flutter
				for onset: float in CRASH_BLASTS:
					var age := t - onset
					if age >= 0.0:
						var hit := minf(age * 400.0, 1.0)
						boom += sin(TAU * (44.0 * age + 6.0 * (1.0 - exp(-age * 7.0)))) * exp(-age * 5.0) * 0.5 * hit
						crack += noise * exp(-age * 48.0) * 0.55 * hit
				if t > 0.06 and rng.randf() < 0.0035 * exp(-t * 1.6):
					crackle = rng.randf_range(0.35, 0.9)
				crackle *= 0.991
				sample = attack * tail * (crack + boom + roar + noise * crackle * 0.42)
			"water_crash":
				# Gifle de l'impact, boum étouffé sous l'eau, gerbe qui retombe en pluie,
				# puis sifflement de la vapeur sur le réacteur encore chaud.
				var tail := 1.0 - smoothstep(1.25, duration, t)
				var attack := minf(t * 300.0, 1.0)
				var slap := sin(TAU * t * (103.0 - t * 45.0)) * exp(-t * 13.0) * 0.6
				var thud := sin(TAU * (34.0 * t + 6.0 * (1.0 - exp(-t * 5.0)))) * exp(-t * 3.6) * 0.7
				var burst := (noise * 0.55 + filtered * 0.9) * exp(-t * 16.0)
				var wash := (filtered * 1.25 + low * 1.6) * smoothstep(0.0, 0.05, t) * exp(-t * 2.4)
				var rain := 0.0
				for onset: float in WATER_FALLBACKS:
					var age := t - onset
					if age >= 0.0:
						rain += (noise * 0.35 + filtered * 0.5) * minf(age * 60.0, 1.0) * exp(-age * 6.5)
				hiss = lerpf(hiss, noise - filtered, 0.5)
				var steam := hiss * smoothstep(0.08, 0.3, t) * exp(-maxf(t - 0.3, 0.0) * 1.7) * 0.32
				sample = attack * tail * (slap + thud + burst + wash + rain + steam)
			"extra_life":
				# Jingle d'avion gagné : arpège montant aux notes carillonnées.
				var notes := [659.3, 830.6, 987.8, 1318.5]
				var step := mini(int(t / 0.085), notes.size() - 1)
				var age := t - step * 0.085
				var hz: float = notes[step]
				var ring := minf(age * 400.0, 1.0) * exp(-age * (6.0 if step == notes.size() - 1 else 14.0))
				var tone := sin(TAU * hz * age) + 0.35 * sin(TAU * hz * 2.0 * age) + 0.12 * sin(TAU * hz * 3.01 * age)
				sample = tone * ring * 0.5 * (1.0 - smoothstep(0.6, duration, t))
			"game_over":
				# Le titre GAME OVER se pose : coup sourd, plaque de métal qui résonne, souffle bref.
				var tail := 1.0 - smoothstep(1.1, duration, t)
				var attack := minf(t * 500.0, 1.0)
				var hit := sin(TAU * (40.0 * t + 7.0 * (1.0 - exp(-t * 9.0)))) * exp(-t * 4.2) * 0.85
				var plate := (sin(TAU * 196.0 * t) + sin(TAU * 311.0 * t) * 0.6 + sin(TAU * 523.0 * t) * 0.35
					+ sin(TAU * 788.0 * t) * 0.2) * exp(-t * 3.4) * 0.22
				var burst := (noise * 0.4 + filtered * 0.6) * exp(-t * 22.0)
				sample = attack * tail * (hit + plate + burst + low * 1.2 * exp(-t * 3.0))
			"glide":
				# Le réacteur s'éteint en toussant : sifflement qui retombe, souffle de chute croissant.
				var fall := 1.0 - smoothstep(0.82, duration, t)
				var whine_hz := 520.0 + 1500.0 * exp(-t * 2.6)
				spool += TAU * whine_hz / RATE
				var cough := 1.0 if t > 0.32 else (0.35 + (0.65 if sin(TAU * 13.0 * t + sin(TAU * 5.0 * t) * 2.0) > -0.45 else 0.0))
				var whine := (sin(spool) + 0.42 * sin(spool * 2.0) + 0.18 * sin(spool * 0.5)) * exp(-t * 2.2) * 0.34 * cough
				var rumble := low * 2.4 * exp(-t * 3.0) * cough
				var wind := (filtered * 0.9 + (noise - filtered) * 0.25) * smoothstep(0.05, 0.85, t) * 0.62
				sample = minf(t * 200.0, 1.0) * fall * (whine + rumble + wind)
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
