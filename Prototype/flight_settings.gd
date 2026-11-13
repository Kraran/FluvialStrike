extends RefCounted

const FLIGHT = preload("res://flight.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const PACING = preload("res://frame_pacing.gd")
const ACTIONS := [
	[&"flight_left", "input.turn_left", FLIGHT.LEFT, KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0],
	[&"flight_right", "input.turn_right", FLIGHT.RIGHT, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
	[&"flight_faster", "input.accelerate", FLIGHT.FAST, KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
	[&"flight_slower", "input.slow_down", FLIGHT.SLOW, KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
	[&"flight_fire", "input.fire", FLIGHT.FIRE, KEY_SPACE, JOY_BUTTON_A, -1, 0.0],
]
const HOTSEAT_KEYBOARD := [
	[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE],
	[KEY_A, KEY_D, KEY_W, KEY_S, KEY_F],
]
const RESERVED_KEYS := [KEY_NONE, KEY_ESCAPE, KEY_F1, KEY_F5, KEY_F6, KEY_R, KEY_M]

enum Ghost { OFF, BEST, LAST }
enum Scanlines { OFF, LOW, MEDIUM, HIGH }
# Difficulté de River Raid : Novice (B), missiles guidés après le tir ; Expert (A), missiles en ligne droite.
enum Difficulty { NOVICE, EXPERT }

const LANGUAGES := {
	"en": "English", "fr": "Français", "es": "Español",
	"da": "Dansk",
	"de": "Deutsch",
	"it": "Italiano",
	"nl": "Nederlands",
	"no": "Norsk",
	"pl": "Polski",
	"pt": "Português (Portugal)",
	"ru": "Русский",
	"sv": "Svenska",
	"tr": "Türkçe",
}
const SCORE_LIMIT := 15
const DEFAULT_SCORES: Array[Dictionary] = [
	{"initials": "KRA", "score": 15000},
	{"initials": "FFC", "score": 10000},
	{"initials": "GRK", "score": 8000},
	{"initials": "GPT", "score": 5000},
]
const INITIALS_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var language := "en"
# Par défaut : plein écran et décor panoramique activés, rendu HD désactivé.
var fullscreen := true
var panorama := true
var sync_mode := PACING.Sync.SCREEN
var refresh_limit := 0
var dynamic_resolution := false
var show_fps := false
var scanlines := Scanlines.OFF
var quality_hd := false
var volume := 80
var vibration := 70
var muted := false
var record := 0
var scores: Array[Dictionary] = DEFAULT_SCORES.duplicate(true)
var _score_reset := 0
var furthest_section := 0
var most_bridges := 0
var best_raid: RAID_REPLAY
var last_raid: RAID_REPLAY
var _last_raid_pending := false
var aircraft := AIRCRAFT.DEFAULT
var ghost_source := Ghost.OFF
var difficulty := Difficulty.NOVICE
var keyboard: Array[int] = []
var gamepad: Array[int] = []
var file_path: String


func _init(path: String = "user://fluvial_strike.cfg") -> void:
	file_path = path
	reset_bindings()


func reset_bindings() -> void:
	keyboard.clear()
	gamepad.clear()
	for action in ACTIONS:
		keyboard.append(action[3])
		gamepad.append(action[4])


func load_file() -> void:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(file_path) or config.load(file_path) != OK:
		return
	var saved_language = config.get_value("ui", "language", "en")
	language = saved_language if saved_language is String and saved_language in LANGUAGES else "en"
	fullscreen = _boolean(config, "video", "fullscreen", fullscreen)
	panorama = _boolean(config, "video", "panorama", panorama)
	var legacy_sync := _boolean(config, "video", "vsync", true)
	var legacy_mode := PACING.Sync.SCREEN if legacy_sync else PACING.Sync.OFF
	sync_mode = clampi(_integer(config, "video", "sync_mode", legacy_mode), PACING.Sync.SCREEN, PACING.Sync.OFF)
	refresh_limit = _integer(config, "video", "refresh_limit", 0)
	if refresh_limit < PACING.MIN_CAP:
		refresh_limit = 0
	# New key: older versions saved the former default (on), which changed the resolution mid-flight.
	dynamic_resolution = _boolean(config, "video", "adaptive_resolution", dynamic_resolution)
	show_fps = _boolean(config, "video", "show_fps", false)
	var scanline_level := _integer(config, "video", "scanlines", Scanlines.OFF)
	scanlines = scanline_level as Scanlines if scanline_level in Scanlines.values() else Scanlines.OFF
	quality_hd = _boolean(config, "video", "hd", quality_hd)
	muted = _boolean(config, "audio", "muted", muted)
	volume = clampi(_integer(config, "audio", "volume", volume), 0, 100)
	vibration = clampi(_integer(config, "gamepad", "vibration", vibration), 0, 100)
	_merge_records(config)
	_load_scores(config)
	if not _last_raid_pending:
		var saved := RAID_REPLAY.new()
		last_raid = saved if saved.read(config, RAID_REPLAY.LAST_SECTION) else null
	var legacy_ghost := Ghost.BEST if _boolean(config, "player", "ghost", false) else Ghost.OFF
	var saved_ghost := _integer(config, "player", "ghost_source", legacy_ghost)
	ghost_source = saved_ghost as Ghost if saved_ghost in [Ghost.OFF, Ghost.BEST, Ghost.LAST] else legacy_ghost
	aircraft = AIRCRAFT.validated(str(config.get_value("player", "aircraft", AIRCRAFT.DEFAULT)))
	var saved_difficulty := _integer(config, "player", "difficulty", Difficulty.NOVICE)
	difficulty = saved_difficulty as Difficulty if saved_difficulty in Difficulty.values() else Difficulty.NOVICE
	for i in ACTIONS.size():
		var action: StringName = ACTIONS[i][0]
		bind(i, _integer(config, "keyboard", action, keyboard[i]), false)
		bind(i, _integer(config, "gamepad", action, gamepad[i]), true)


func save() -> Error:
	return _save(false)


func clear_high_score() -> Error:
	return _save(true)


func _save(clear_score: bool, entry: Dictionary = {}) -> Error:
	var config := ConfigFile.new()
	if FileAccess.file_exists(file_path):
		var read_error := config.load(file_path)
		if read_error == OK:
			_merge_records(config)
			_load_scores(config)
		elif clear_score or not entry.is_empty():
			return read_error
	var saved_scores: Array[Dictionary] = DEFAULT_SCORES.duplicate(true) if clear_score else scores.duplicate()
	if not entry.is_empty() and not _insert_score(saved_scores, entry):
		return ERR_UNAVAILABLE
	config.set_value("leaderboard", "entries", saved_scores)
	var score_reset := _score_reset + int(clear_score)
	config.set_value("ui", "language", language)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "panorama", panorama)
	config.set_value("video", "vsync", sync_mode != PACING.Sync.OFF)
	config.set_value("video", "sync_mode", sync_mode)
	config.set_value("video", "refresh_limit", refresh_limit)
	config.set_value("video", "adaptive_resolution", dynamic_resolution)
	config.set_value("video", "show_fps", show_fps)
	config.set_value("video", "scanlines", scanlines)
	config.set_value("video", "hd", quality_hd)
	config.set_value("audio", "volume", volume)
	config.set_value("audio", "muted", muted)
	config.set_value("gamepad", "vibration", vibration)
	config.set_value("record", "score", 0 if clear_score else record)
	config.set_value("record", "score_reset", score_reset)
	config.set_value("record", "section", furthest_section)
	config.set_value("record", "bridges", most_bridges)
	if not clear_score and best_raid and best_raid.score == record:
		best_raid.write(config, RAID_REPLAY.BEST_SECTION)
	elif config.has_section(RAID_REPLAY.BEST_SECTION):
		config.erase_section(RAID_REPLAY.BEST_SECTION)
	if _last_raid_pending:
		last_raid.write(config, RAID_REPLAY.LAST_SECTION)
	config.set_value("player", "aircraft", aircraft)
	config.set_value("player", "ghost_source", ghost_source)
	config.set_value("player", "difficulty", difficulty)
	for i in ACTIONS.size():
		config.set_value("keyboard", ACTIONS[i][0], keyboard[i])
		config.set_value("gamepad", ACTIONS[i][0], gamepad[i])
	var pending := "%s.%d.tmp" % [file_path, OS.get_process_id()]
	var error := config.save(pending)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(pending, file_path)
	if error != OK:
		DirAccess.remove_absolute(pending)
	else:
		_last_raid_pending = false
		scores = saved_scores
		if clear_score:
			record = 0
			best_raid = null
			_score_reset = score_reset
	return error


func score_rank(score: int) -> int:
	return _score_index(scores, score)


func submit_score(initials: String, score: int) -> Error:
	if not _valid_initials(initials) or score <= 0 or score > FLIGHT.COURSE.MAX_SCORE:
		return ERR_INVALID_PARAMETER
	return _save(false, {"initials": initials, "score": score})


func _load_scores(config: ConfigFile) -> void:
	scores.clear()
	if not config.has_section_key("leaderboard", "entries"):
		var old_record := _integer(config, "record", "score", 0)
		if old_record > 0 and old_record <= FLIGHT.COURSE.MAX_SCORE:
			scores.append({"initials": "---", "score": old_record})
	else:
		var entries = config.get_value("leaderboard", "entries")
		if entries is Array:
			for entry in entries:
				if not entry is Dictionary:
					continue
				var initials = entry.get("initials", "")
				var score = entry.get("score", 0)
				if initials is String and (initials == "---" or _valid_initials(initials)) \
						and score is int and score > 0 and score <= FLIGHT.COURSE.MAX_SCORE:
					_insert_score(scores, {"initials": initials, "score": score})
	if scores.is_empty() or (scores.size() == 1 and scores[0].initials == "---"):
		for entry in DEFAULT_SCORES:
			_insert_score(scores, entry.duplicate())


func _valid_initials(initials: String) -> bool:
	if initials.length() != 3:
		return false
	for i in 3:
		if not INITIALS_ALPHABET.contains(initials[i]):
			return false
	return true


func _score_index(entries: Array[Dictionary], score: int) -> int:
	if score <= 0:
		return -1
	for i in entries.size():
		if score > entries[i].score:
			return i
	return entries.size() if entries.size() < SCORE_LIMIT else -1


func _insert_score(entries: Array[Dictionary], entry: Dictionary) -> bool:
	var index := _score_index(entries, entry.score)
	if index < 0:
		return false
	entries.insert(index, entry)
	if entries.size() > SCORE_LIMIT:
		entries.pop_back()
	return true


func _merge_records(config: ConfigFile) -> void:
	var saved_reset := _integer(config, "record", "score_reset", 0)
	if saved_reset > _score_reset:
		record = 0
		best_raid = null
		_score_reset = saved_reset
	record = maxi(record, _integer(config, "record", "score", 0))
	furthest_section = maxi(furthest_section,
		clampi(_integer(config, "record", "section", 0), 0, FLIGHT.COURSE.BRIDGE_COUNT + 1))
	most_bridges = maxi(most_bridges,
		clampi(_integer(config, "record", "bridges", 0), 0, FLIGHT.COURSE.BRIDGE_COUNT))
	if best_raid and best_raid.score != record:
		best_raid = null
	if best_raid == null and config.has_section(RAID_REPLAY.BEST_SECTION):
		var saved := RAID_REPLAY.new()
		if saved.read(config, RAID_REPLAY.BEST_SECTION, record) and saved.cheats == 0:
			best_raid = saved


func ghost_raid() -> RAID_REPLAY:
	match ghost_source:
		Ghost.BEST:
			return best_raid
		Ghost.LAST:
			return last_raid
	return null


func record_completed_raid(flight: FLIGHT, controls: PackedByteArray) -> bool:
	var clean := flight.cheats == 0
	var changed := update_raid_records(flight.score, flight.section) if clean else false
	if controls.size() != flight.tick or controls.is_empty() or controls.size() > RAID_REPLAY.MAX_FRAMES:
		return changed
	last_raid = RAID_REPLAY.new()
	last_raid.capture(flight, controls, aircraft)
	_last_raid_pending = true
	if clean and flight.score == record and (best_raid == null or best_raid.score != record):
		best_raid = last_raid
	return true



func update_raid_records(score: int, section: int) -> bool:
	var changed := update_record(score)
	if section > furthest_section:
		furthest_section = section
		changed = true
	if section - 1 > most_bridges:
		most_bridges = section - 1
		changed = true
	return changed


func update_record(score: int) -> bool:
	if score <= record:
		return false
	record = score
	return true


func bind(index: int, code: int, controller: bool) -> bool:
	if controller:
		if code < 0 or code >= JOY_BUTTON_MAX or code == JOY_BUTTON_START:
			return false
	elif code < 0 or code in RESERVED_KEYS:
		return false
	var mapping := gamepad if controller else keyboard
	var other := mapping.find(code)
	if other >= 0 and other != index:
		mapping[other] = mapping[index]
	mapping[index] = code
	return true


func apply_bindings() -> void:
	for i in ACTIONS.size():
		var spec: Array = ACTIONS[i]
		var action: StringName = spec[0]
		if InputMap.has_action(action):
			Input.action_release(action)
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.5)
		var key := InputEventKey.new()
		key.physical_keycode = keyboard[i] as Key
		InputMap.action_add_event(action, key)
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = gamepad[i] as JoyButton
		InputMap.action_add_event(action, button)
		if spec[5] >= 0:
			var stick := InputEventJoypadMotion.new()
			stick.device = -1
			stick.axis = spec[5] as JoyAxis
			stick.axis_value = spec[6]
			InputMap.action_add_event(action, stick)


func controls() -> int:
	var result := 0
	for action in ACTIONS:
		if Input.is_action_pressed(action[0]):
			result |= action[2]
	return result


func hotseat_keys(player: int, devices: Vector2i) -> Array:
	return HOTSEAT_KEYBOARD[player] if devices.x == -1 and devices.y == -1 else keyboard


static func hotseat_default_devices(connected: Array[int]) -> Vector2i:
	return Vector2i(connected[0] if not connected.is_empty() else -1,
		connected[1] if connected.size() > 1 else -1)


static func hotseat_device_ready(player: int, devices: Vector2i, connected: Array[int]) -> bool:
	var device := devices[player]
	return device == -1 or (device in connected and device != devices[1 - player])


func hotseat_controls(player: int, devices: Vector2i) -> int:
	var device := devices[player]
	var result := 0
	if device == -1:
		var keys := hotseat_keys(player, devices)
		for i in ACTIONS.size():
			if Input.is_physical_key_pressed(keys[i] as Key):
				result |= ACTIONS[i][2]
	else:
		for i in ACTIONS.size():
			var action: Array = ACTIONS[i]
			if Input.is_joy_button_pressed(device, gamepad[i] as JoyButton) or \
					(action[5] >= 0 and Input.get_joy_axis(device, action[5] as JoyAxis) * action[6] > 0.5):
				result |= action[2]
	return result


func _integer(config: ConfigFile, section: String, key: String, fallback: int) -> int:
	var value = config.get_value(section, key, fallback)
	return value if value is int else fallback


func _boolean(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value = config.get_value(section, key, fallback)
	return value if value is bool else fallback
