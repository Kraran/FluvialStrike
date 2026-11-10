extends RefCounted

const FLIGHT = preload("res://flight.gd")
const ACTIONS := [
	[&"flight_left", "Virer à gauche", FLIGHT.LEFT, KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0],
	[&"flight_right", "Virer à droite", FLIGHT.RIGHT, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
	[&"flight_faster", "Accélérer", FLIGHT.FAST, KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
	[&"flight_slower", "Ralentir", FLIGHT.SLOW, KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
	[&"flight_fire", "Tirer", FLIGHT.FIRE, KEY_SPACE, JOY_BUTTON_A, -1, 0.0],
]
const RESERVED_KEYS := [KEY_NONE, KEY_ESCAPE, KEY_F1, KEY_F5, KEY_F6, KEY_R, KEY_M]

var fullscreen := false
var vsync := true
var quality_hd := true
var volume := 80
var muted := false
var record := 0
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
	fullscreen = _boolean(config, "video", "fullscreen", fullscreen)
	vsync = _boolean(config, "video", "vsync", vsync)
	quality_hd = _boolean(config, "video", "hd", quality_hd)
	muted = _boolean(config, "audio", "muted", muted)
	volume = clampi(_integer(config, "audio", "volume", volume), 0, 100)
	record = maxi(_integer(config, "record", "score", record), 0)
	for i in ACTIONS.size():
		var action: StringName = ACTIONS[i][0]
		bind(i, _integer(config, "keyboard", action, keyboard[i]), false)
		bind(i, _integer(config, "gamepad", action, gamepad[i]), true)


func save() -> Error:
	var config := ConfigFile.new()
	if FileAccess.file_exists(file_path) and config.load(file_path) == OK:
		record = maxi(record, _integer(config, "record", "score", 0))
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "hd", quality_hd)
	config.set_value("audio", "volume", volume)
	config.set_value("audio", "muted", muted)
	config.set_value("record", "score", record)
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
	return error


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


func _integer(config: ConfigFile, section: String, key: String, fallback: int) -> int:
	var value = config.get_value(section, key, fallback)
	return value if value is int else fallback


func _boolean(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value = config.get_value(section, key, fallback)
	return value if value is bool else fallback
