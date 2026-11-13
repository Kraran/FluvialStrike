extends Node2D

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const WORLD = preload("res://flight_world.gd")
const SOUND = preload("res://flight_sound.gd")
const MENU = preload("res://flight_menu.gd")
const SETTINGS = preload("res://flight_settings.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const PACING = preload("res://frame_pacing.gd")
const UPSCALE = preload("res://upscale.gdshader")
const SCALE := Vector2(6, 3)
const PLAY_HEIGHT := 483
const PLAY_WIDTH := 912
const CRT_RASTER_LINES := 161
const CRT_MIN_LINE_PITCH := 3.5
const SCANLINE_STRENGTH := [0.0, 0.16, 0.27, 0.40]
const JET_ROW := 151
const FOAM := Color("#317587")
const INK := Color("#071e2c")
const TEXT := Color("#e8f3ed")
const AMBER := Color("#ffbf67")
const MINT := Color("#a8ecc9")
const FUEL_GAIN := Color("#94eaf4")
const HUD_MUTED := Color("#aac5d0")
const HUD_RULE := Color("#688896")
const GAUGE_TRACK := Color("#365764")
const BANK_DIAL_RADIUS := 34.0
enum Mode { MANUAL, REFERENCE, RECORDING, BEST, LAST }
const BRIDGE_APPROACH_FRAMES := 120
const SEEK_STEPS_PER_FRAME := 720
const REPLAY_TICKS_PER_SECOND := 60.0
# The shader clock wraps every 60 s (3600 ticks): foliage and wakes complete whole cycles.
const SHADER_CLOCK_TICKS := 3600.0
# The water pattern repeats every 3000 course rows (bank.gdshader WATER_PERIOD): the drift
# wraps after exactly that many rows of whole texels, on an identical image.
const WATER_PERIOD_ROWS := 3000
const REPLAY_MIN_SPEED := 0.25
const REPLAY_MAX_SPEED := 3.0
const REPLAY_SPEED_RESPONSE := 5.0
const FUEL_BAR := Rect2(26, 568, 266, 13)
enum Vibration { REFUEL, BRIDGE, CRASH }
# Weak motor, strong motor and duration in seconds.
const VIBRATION_PATTERNS := [
	Vector3(0.62, 0.42, 0.19),
	Vector3(0.74, 0.96, 0.33),
	Vector3(1.00, 1.00, 0.42),
]

var _horizon_sky := _make_horizon_sky()
var flight := FLIGHT.new()
var _hotseat_flights: Array[FLIGHT] = []
var _hotseat_devices := Vector2i(-1, -1)
var _hotseat_aircraft: Array[String] = ["", ""]
var _hotseat_player := 0
var _hotseat_pending := -1
var mode := Mode.MANUAL
var recording := PackedByteArray()
var _recorded_cheats := 0
var _saved_replay: RAID_REPLAY
var _recorded_bridges := PackedInt32Array()
var _reference_bridges := PackedInt32Array()
var _replay_bridges := PackedInt32Array()
var _replay_landed_bridge := -1
var _replay_speed := 1.0
var _replay_fraction := 0.0
var _replay_seek_target := -1
var _bridge_results_flight: FLIGHT
var paused := false
var debug := false
var playing := false
var world: WORLD
var sound: SOUND
var menu: MENU
var settings := SETTINGS.new()
var pacing := PACING.new()
var _surface: TextureRect
var _upscale := ShaderMaterial.new()
var _display_options: Array = []
var _last_render_time := 0
var _display_poll := 0.0
# Everything the last _draw() depended on: in manual flight the HUD is only redrawn when it changes.
var _drawn_hud := []
# Whole screen pixels per course row. The playfield shows 161 rows over 483 canvas units, so the
# canvas scale is kept at a multiple of 1/3 and the scroll moves by whole pixels.
var _row_pixels := 3
var _shader_ticks := 0.0
var _water_frames := 0.0
var _fps_label: Label
var _rumble_device := -1
var _rumble_until := 0
var _rumble_priority := Vibration.REFUEL
# On a display whose refresh matches the simulation rate, run exactly one tick per displayed
# frame instead of following the measured frame time: every frame scrolls by the same amount.
var _frame_locked := false
var _refresh_period := 1.0 / 60.0
var _resolution_pending := false


func _ready() -> void:
	settings.load_file()
	TranslationServer.set_locale(settings.language)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if DisplayServer.get_name() != "headless":
		world = WORLD.new()
		world.set_player_aircraft(settings.aircraft)
		add_child(world)
		world.sync(flight, true)
		_surface = TextureRect.new()
		_surface.show_behind_parent = true
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_surface.texture = world.get_texture()
		_surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_surface.size = Vector2(PLAY_WIDTH, PLAY_HEIGHT)
		_upscale.shader = UPSCALE
		_surface.material = _upscale
		add_child(_surface)
		sound = SOUND.new()
		add_child(sound)
		world.spatial_effect_requested.connect(_on_spatial_effect_requested)
		menu = MENU.new()
		add_child(menu)
		menu.configure(settings)
		menu.action_requested.connect(_menu_action)
		menu.bridge_replay_requested.connect(_start_bridge_replay)
		menu.settings_changed.connect(_apply_settings)
		menu.settings_committed.connect(_save_settings)
		_create_fps_label()
		get_window().size_changed.connect(_update_layout, CONNECT_DEFERRED)
		_apply_settings()
		# Render the world on the first draw, even before the surface is marked visible.
		world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		RenderingServer.frame_post_draw.connect(_finish_startup_layout, CONNECT_ONE_SHOT)
	else:
		settings.apply_bindings()
	if "--replay" in OS.get_cmdline_user_args():
		_start(Mode.REFERENCE)


func _input(event: InputEvent) -> void:
	if not _hotseat_flights.is_empty():
		return
	if event is InputEventJoypadButton and event.pressed:
		_select_rumble_device(event.device)
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] \
			and absf(event.axis_value) > 0.55:
		_select_rumble_device(event.device)
	elif _rumble_device >= 0 and event is InputEventKey and event.pressed and not event.echo:
		for action: Array in SETTINGS.ACTIONS:
			if event.is_action_pressed(action[0]):
				_select_rumble_device(-1)
				break


func _select_rumble_device(device: int) -> void:
	if device != _rumble_device:
		_stop_rumble()
		_rumble_device = device


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == _rumble_device:
		_select_rumble_device(-1)
	if not connected and playing and not _hotseat_flights.is_empty() and _hotseat_pending < 0 \
			and flight.status < FLIGHT.Status.GAME_OVER and device == _hotseat_devices[_hotseat_player]:
		_wait_for_hotseat_player(_hotseat_player)
	elif menu:
		menu.refresh_hotseat_devices()


func _vibrate(kind: Vibration) -> void:
	if _rumble_device < 0 or settings.vibration == 0:
		return
	var now := Time.get_ticks_msec()
	if now < _rumble_until and kind < _rumble_priority:
		return
	var pattern: Vector3 = VIBRATION_PATTERNS[kind]
	var remaining := 1.0 - settings.vibration / 100.0
	var intensity := 1.0 - remaining * remaining
	Input.start_joy_vibration(_rumble_device, pattern.x * intensity, pattern.y * intensity, pattern.z)
	_rumble_priority = kind
	_rumble_until = now + ceili(pattern.z * 1000.0)


func _stop_rumble() -> void:
	if _rumble_until != 0:
		Input.stop_joy_vibration(_rumble_device)
		_rumble_until = 0


func _exit_tree() -> void:
	_stop_rumble()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if menu and menu.screen in [MENU.Screen.SETTINGS, MENU.Screen.HANGAR, MENU.Screen.BRIDGES, MENU.Screen.CONFIRM_RESET,
			MENU.Screen.SCORES, MENU.Screen.INITIALS, MENU.Screen.LANGUAGES, MENU.Screen.HOTSEAT_SETUP,
			MENU.Screen.HOTSEAT_TURN, MENU.Screen.HOTSEAT_RESULTS, MENU.Screen.CONFIRM_ABANDON] \
			and event.physical_keycode != KEY_ESCAPE:
		return
	match event.physical_keycode:
		KEY_R:
			_restart_manual()
		KEY_F5:
			if _hotseat_flights.is_empty():
				_start(Mode.REFERENCE)
		KEY_F6:
			if _hotseat_flights.is_empty() and not recording.is_empty():
				_start(Mode.RECORDING)
		KEY_LEFT:
			_request_bridge(-1)
		KEY_RIGHT:
			_request_bridge(1)
		KEY_F1:
			debug = not debug
		KEY_M:
			settings.muted = not settings.muted
			_apply_audio()
			_save_settings()
		KEY_ESCAPE:
			_toggle_pause()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventJoypadButton or not event.pressed:
		return
	if event.button_index == JOY_BUTTON_START:
		if not paused and not _hotseat_flights.is_empty() and event.device != _hotseat_devices[_hotseat_player]:
			return
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif playing and mode != Mode.MANUAL and not paused:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_request_bridge(-1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_RIGHT_SHOULDER:
				_request_bridge(1)
				get_viewport().set_input_as_handled()
			JOY_BUTTON_B:
				if _bridge_results_flight:
					_return_to_bridge_results()
					get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _frame_locked:
		return
	if playing and not paused and mode == Mode.MANUAL and flight.status < FLIGHT.Status.GAME_OVER:
		_advance_flight()


# Ticks to run this frame in frame-locked mode. A late frame (more than one and a half refresh
# periods) catches up on the missed refreshes instead of slowing the game down.
func _locked_ticks(delta: float) -> int:
	if delta <= _refresh_period * 1.5:
		return 1
	return clampi(roundi(delta / _refresh_period), 1, 4)


func _advance_flight() -> void:
	var hotseat := not _hotseat_flights.is_empty()
	var controls: int
	if hotseat:
		controls = settings.hotseat_controls(_hotseat_player, _hotseat_devices)
	else:
		controls = settings.controls() if mode == Mode.MANUAL else _replay_controls()
	if mode == Mode.MANUAL and not hotseat:
		recording.append(controls)
	var recovering := flight.status == FLIGHT.Status.CRASHED
	var previous_section := flight.section
	var previous_fuel := flight.fuel
	var was_refueling := flight.over_fuel_barge
	flight.advance(controls)
	if mode == Mode.MANUAL and not hotseat and flight.section > previous_section:
		_recorded_bridges.append(flight.tick)
	if mode == Mode.MANUAL and _rumble_device >= 0:
		if not recovering and flight.status == FLIGHT.Status.CRASHED and flight.crash_cause != "fuel":
			_vibrate(Vibration.CRASH)
		elif flight.section > previous_section and flight.is_bridge_destroyed(flight.section - 2):
			_vibrate(Vibration.BRIDGE)
		elif not was_refueling and flight.over_fuel_barge and flight.fuel > previous_fuel:
			_vibrate(Vibration.REFUEL)
	if world:
		world.sync(flight, recovering and flight.status == FLIGHT.Status.FLYING)
	if sound:
		sound.sync(flight)
		if _recording_finished():
			sound.silence()
	if hotseat:
		if flight.status >= FLIGHT.Status.GAME_OVER or (recovering and flight.status == FLIGHT.Status.FLYING):
			_finish_hotseat_turn()
	elif mode == Mode.MANUAL and flight.status >= FLIGHT.Status.GAME_OVER:
		var previous_raid := settings.last_raid
		if settings.record_completed_raid(flight, recording):
			_save_settings()
		if menu:
			var current := settings.last_raid if settings.last_raid != previous_raid else null
			menu.show_results(flight, current)
	# Manual flight: _process redraws only if the HUD changed (see _hud_state). Replays redraw anyway.
	if mode != Mode.MANUAL or not world:
		queue_redraw()


func _process(delta: float) -> void:
	var frame_delta := delta
	if _frame_locked:
		frame_delta = _locked_ticks(delta) / float(Engine.physics_ticks_per_second)
	var replay_delta := frame_delta
	if playing and not paused and mode != Mode.MANUAL:
		if _replay_seek_target >= 0:
			_step_replay_seek()
			if _replay_seek_target >= 0:
				return
		elif _is_flying():
			replay_delta = _advance_replay(frame_delta)
	elif _frame_locked and playing and not paused and mode == Mode.MANUAL:
		for tick in _locked_ticks(delta):
			if paused or flight.status >= FLIGHT.Status.GAME_OVER:
				break
			_advance_flight()
	if not world:
		return
	# Shader animations (water, wakes, foliage) follow the displayed frames, not the wall clock:
	# in frame-locked mode every image advances them by exactly one tick.
	# Counted in ticks so that both clocks stay whole numbers in frame-locked mode.
	var frame_ticks := float(_locked_ticks(delta)) if _frame_locked \
		else frame_delta * Engine.physics_ticks_per_second
	_shader_ticks = fposmod(_shader_ticks + frame_ticks, SHADER_CLOCK_TICKS)
	RenderingServer.global_shader_parameter_set(&"game_time",
		_shader_ticks / Engine.physics_ticks_per_second)
	# The current drifts by exactly one render texel per frame relative to the banks (one
	# screen pixel when the render is shown 1:1), so the water moves by whole pixels too.
	_water_frames = fposmod(_water_frames + frame_ticks, float(WATER_PERIOD_ROWS * world.texel_rows()))
	RenderingServer.global_shader_parameter_set(&"water_flow", _water_frames * world.texel_length())
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_render_time) / 1000.0 if _last_render_time else 0.0
	_last_render_time = now
	_display_poll += delta
	if _display_poll >= 1.0:
		_display_poll = 0.0
		_apply_display_pacing()
		_refresh_fps_label()
	if paused:
		return
	var flying := _is_flying()
	var fraction := 1.0
	if flying and mode != Mode.MANUAL:
		fraction = _replay_fraction
	elif flying and not _frame_locked:
		fraction = Engine.get_physics_interpolation_fraction()
	world.present(flight, fraction, replay_delta)
	if _hud_state() != _drawn_hud:
		queue_redraw()
	if sound and not sound.muted and flying and flight.status == FLIGHT.Status.FLYING:
		sound.update_enemies(world.enemy_audio_sources(flight), delta)
	elif sound:
		sound.update_enemies({}, delta)
	if flying and settings.dynamic_resolution:
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(world.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_resolution_pending = pacing.observe(frame_ms, gpu_ms) or _resolution_pending
	# A new render size reallocates the viewport: wait for a respawn or the end of the flight.
	if _resolution_pending and flight.status != FLIGHT.Status.FLYING:
		_apply_pending_resolution()
	if debug or (playing and mode != Mode.MANUAL):
		queue_redraw()


func _apply_pending_resolution() -> void:
	if _resolution_pending:
		_resolution_pending = false
		_apply_render_resolution()


func _is_flying() -> bool:
	return playing and flight.status < FLIGHT.Status.GAME_OVER and not _recording_finished()


func _replay_controls() -> int:
	if _saved_replay:
		return _saved_replay.inputs[flight.tick]
	if mode == Mode.REFERENCE:
		return FLIGHT.reference_controls(flight.tick + 1)
	return recording[flight.tick]


func _advance_replay(delta: float) -> float:
	var faster := Input.get_action_strength(&"replay_faster")
	var slower := Input.get_action_strength(&"replay_slower")
	var target := 1.0 + faster * (REPLAY_MAX_SPEED - 1.0) - slower * (1.0 - REPLAY_MIN_SPEED)
	if faster > 0.0 and slower > 0.0:
		target = 1.0
	var response := 1.0 - exp(-REPLAY_SPEED_RESPONSE * delta)
	# Integrate the speed ramp over the frame before sampling the fixed-rate simulation.
	var replay_delta := target * delta + (_replay_speed - target) * response / REPLAY_SPEED_RESPONSE
	_replay_speed = lerpf(_replay_speed, target, response)
	_replay_fraction += replay_delta * REPLAY_TICKS_PER_SECOND
	while _replay_fraction >= 1.0 and _is_flying():
		_replay_fraction -= 1.0
		_advance_flight()
	return replay_delta


func _on_spatial_effect_requested(kind: String, pan: float) -> void:
	if mode == Mode.MANUAL and flight.crash_cause == "fuel" and kind in ["crash", "water_crash"]:
		_vibrate(Vibration.CRASH)
	if not _recording_finished():
		sound.play_spatial_effect(kind, pan)


func _start(next_mode: Mode, two_players: bool = false) -> void:
	var replay: RAID_REPLAY
	match next_mode:
		Mode.BEST:
			replay = settings.best_raid
		Mode.LAST:
			replay = settings.last_raid
	if next_mode in [Mode.BEST, Mode.LAST] and replay == null:
		return
	_stop_rumble()
	if two_players:
		_hotseat_flights.assign([FLIGHT.new(), FLIGHT.new()])
		_hotseat_aircraft.fill("")
		_hotseat_player = 0
		_hotseat_pending = -1
		flight = _hotseat_flights[0]
		_select_rumble_device(_hotseat_devices[0])
	else:
		_clear_hotseat()
	_bridge_results_flight = null
	_saved_replay = replay
	_replay_landed_bridge = -1
	_replay_seek_target = -1
	_replay_speed = 1.0
	mode = next_mode
	_reset_flight()
	match mode:
		Mode.REFERENCE:
			_replay_bridges = _reference_bridge_ticks()
		Mode.RECORDING:
			_replay_bridges = _recorded_bridges
		Mode.BEST, Mode.LAST:
			_replay_bridges = _saved_replay.bridge_ticks
		_:
			_replay_bridges = PackedInt32Array()
	if mode == Mode.MANUAL and not two_players:
		recording.clear()
		_recorded_bridges.clear()
		flight.cheats = menu.cheats if menu else 0
		_recorded_cheats = flight.cheats
	paused = false
	playing = true
	if menu:
		menu.dismiss()
	if world:
		_update_ghost()
		world.set_player_aircraft(_saved_replay.aircraft if _saved_replay else settings.aircraft)
		world.reset_effects()
		world.sync(flight, true)
	if sound:
		sound.reset()


func _clear_hotseat() -> void:
	if _hotseat_flights.is_empty():
		return
	_hotseat_flights.clear()
	_hotseat_pending = -1
	flight = FLIGHT.new()
	_select_rumble_device(-1)


func _restart_manual() -> void:
	if _hotseat_flights.is_empty():
		_start(Mode.MANUAL)
	else:
		_start_hotseat(_hotseat_devices)


func _start_hotseat(devices: Vector2i) -> void:
	var connected := Input.get_connected_joypads()
	if not SETTINGS.hotseat_device_ready(0, devices, connected) or not SETTINGS.hotseat_device_ready(1, devices, connected):
		if not _hotseat_flights.is_empty():
			paused = true
			_stop_rumble()
			if sound:
				sound.silence()
		if menu:
			menu.show_hotseat_setup(devices)
		return
	_hotseat_devices = devices
	_start(Mode.MANUAL, true)
	_wait_for_hotseat_player(0)


func _finish_hotseat_turn() -> void:
	var other := 1 - _hotseat_player
	if _hotseat_flights[other].status < FLIGHT.Status.GAME_OVER:
		_wait_for_hotseat_player(other)
	elif flight.status >= FLIGHT.Status.GAME_OVER:
		paused = true
		_stop_rumble()
		if sound:
			sound.silence()
		if menu:
			menu.show_hotseat_results(_hotseat_flights)
		queue_redraw()


func _wait_for_hotseat_player(player: int) -> void:
	_hotseat_pending = player
	paused = true
	_stop_rumble()
	if sound:
		sound.silence()
	if menu:
		menu.show_hotseat_turn(player, _hotseat_devices, _hotseat_aircraft[player], _hotseat_aircraft[1 - player])
	queue_redraw()


func _continue_hotseat(devices: Vector2i, aircraft: String) -> void:
	if _hotseat_pending < 0 or not SETTINGS.hotseat_device_ready(_hotseat_pending, devices, Input.get_connected_joypads()):
		return
	if _hotseat_aircraft[_hotseat_pending].is_empty():
		if aircraft not in AIRCRAFT.IDS or aircraft == _hotseat_aircraft[1 - _hotseat_pending]:
			return
		_hotseat_aircraft[_hotseat_pending] = aircraft
	_hotseat_devices = devices
	_hotseat_player = _hotseat_pending
	_hotseat_pending = -1
	flight = _hotseat_flights[_hotseat_player]
	_select_rumble_device(_hotseat_devices[_hotseat_player])
	if world:
		world.set_player_aircraft(_hotseat_aircraft[_hotseat_player])
		world.reset_effects()
	if sound:
		sound.reset(flight)
	_resume()


func _reset_flight() -> void:
	flight.reset()
	flight.finish_distance = COURSE.REFERENCE_END if mode == Mode.REFERENCE else COURSE.END
	if _saved_replay:
		flight.cheats = _saved_replay.cheats
	elif mode == Mode.RECORDING:
		flight.cheats = _recorded_cheats
	_replay_fraction = 0.0


func _reference_bridge_ticks() -> PackedInt32Array:
	if _reference_bridges.is_empty():
		var reference := FLIGHT.new()
		reference.finish_distance = COURSE.REFERENCE_END
		while reference.status < FLIGHT.Status.GAME_OVER:
			var section := reference.section
			reference.advance(FLIGHT.reference_controls(reference.tick + 1))
			if reference.section > section:
				_reference_bridges.append(reference.tick)
	return _reference_bridges


func _recording_finished() -> bool:
	if _saved_replay:
		return flight.tick >= _saved_replay.inputs.size()
	return mode == Mode.RECORDING and flight.tick >= recording.size()


func _bridge_index(direction: int) -> int:
	var first_ahead := _replay_bridges.bsearch(flight.tick, false)
	if direction < 0:
		return first_ahead - 1
	var next := maxi(first_ahead, _replay_landed_bridge + 1)
	if next < _replay_bridges.size() and _replay_bridges[next] - 1 <= flight.tick:
		next += 1
	return next


func _request_bridge(direction: int) -> void:
	if not playing or mode == Mode.MANUAL or paused or _replay_seek_target >= 0:
		return
	var index := _bridge_index(direction)
	if index < 0 or index >= _replay_bridges.size():
		return
	var bridge_tick := _replay_bridges[index]
	var approach := maxi(0, bridge_tick - BRIDGE_APPROACH_FRAMES)
	if direction > 0 and approach <= flight.tick:
		approach = bridge_tick - 1
	_seek_bridge(index, approach)


func _seek_bridge(index: int, approach: int) -> void:
	_replay_landed_bridge = index
	_replay_seek_target = approach
	if approach < flight.tick:
		_reset_flight()
	if sound:
		sound.silence()
	queue_redraw()


func _step_replay_seek() -> void:
	var stop := mini(_replay_seek_target, flight.tick + SEEK_STEPS_PER_FRAME)
	while flight.tick < stop and flight.status < FLIGHT.Status.GAME_OVER:
		flight.advance(_replay_controls())
	if flight.tick < _replay_seek_target and flight.status < FLIGHT.Status.GAME_OVER:
		return
	_replay_seek_target = -1
	_replay_fraction = 0.0
	if sound:
		sound.reset(flight)
	if world:
		world.reset_effects()
		world.sync(flight, true)
	queue_redraw()


func _start_bridge_replay(best: bool, index: int) -> void:
	var replay := settings.best_raid if best else settings.last_raid
	if replay == null or index < 0 or index >= replay.bridge_ticks.size():
		return
	var result := flight
	flight = FLIGHT.new()
	_start(Mode.BEST if best else Mode.LAST)
	_bridge_results_flight = result
	_seek_bridge(index, maxi(0, replay.bridge_ticks[index] - BRIDGE_APPROACH_FRAMES))


func _return_to_bridge_results() -> void:
	_stop_rumble()
	flight = _bridge_results_flight
	_bridge_results_flight = null
	_saved_replay = null
	_replay_seek_target = -1
	mode = Mode.MANUAL
	paused = false
	if sound:
		sound.reset(flight)
	if world:
		world.set_player_aircraft(settings.aircraft)
		world.reset_effects()
		world.sync(flight, true)
	menu.show_bridge_results()
	queue_redraw()


func _toggle_pause() -> void:
	if menu and menu.screen in [MENU.Screen.SETTINGS, MENU.Screen.HANGAR, MENU.Screen.BRIDGES,
			MENU.Screen.CONFIRM_RESET, MENU.Screen.TESTS, MENU.Screen.SCORES, MENU.Screen.INITIALS, MENU.Screen.LANGUAGES,
			MENU.Screen.HOTSEAT_SETUP, MENU.Screen.HOTSEAT_TURN, MENU.Screen.HOTSEAT_RESULTS, MENU.Screen.CONFIRM_ABANDON,
			MENU.Screen.ARCHIVES, MENU.Screen.CONTROLS_HELP]:
		menu.back()
	elif paused:
		_resume()
	elif playing and (flight.status >= FLIGHT.Status.GAME_OVER or _recording_finished()):
		if _bridge_results_flight:
			_return_to_bridge_results()
		else:
			_show_title()
	elif playing:
		paused = true
		_apply_pending_resolution()
		_stop_rumble()
		if sound:
			sound.silence()
		if menu:
			menu.show_pause(_bridge_results_flight != null, mode == Mode.MANUAL, flight)


func _resume() -> void:
	paused = false
	if world:
		world.sync(flight, true)
	if menu:
		menu.dismiss()


func _show_title() -> void:
	_stop_rumble()
	_clear_hotseat()
	_bridge_results_flight = null
	_replay_seek_target = -1
	_saved_replay = null
	flight.reset()
	playing = false
	paused = false
	mode = Mode.MANUAL
	_update_ghost()
	if sound:
		sound.reset()
	if world:
		world.set_player_aircraft(settings.aircraft)
		world.reset_effects()
		world.sync(flight, true)
	if menu:
		menu.show_title()


func _menu_action(action: StringName) -> void:
	match action:
		&"play":
			_restart_manual()
		&"hotseat_start":
			_start_hotseat(menu.hotseat_devices)
		&"hotseat_continue":
			_continue_hotseat(menu.hotseat_devices, menu.aircraft_selection)
		&"hotseat_restart":
			_restart_manual()
		&"reference":
			_start(Mode.REFERENCE)
		&"best_replay":
			_start(Mode.BEST)
		&"last_replay":
			_start(Mode.LAST)
		&"resume":
			_resume()
		&"title":
			if _bridge_results_flight:
				_return_to_bridge_results()
			elif playing and mode == Mode.MANUAL and (flight.status < FLIGHT.Status.GAME_OVER or _hotseat_pending >= 0):
				menu.confirm_abandon()
			else:
				_show_title()
		&"abandon":
			_show_title()
		&"aircraft_selected":
			world.set_player_aircraft(settings.aircraft)
			world.sync(flight, true)
		&"quit":
			get_tree().quit()
	queue_redraw()


func _apply_settings() -> void:
	if settings.vibration == 0:
		_stop_rumble()
	settings.apply_bindings()
	var window := get_window()
	# Set the canvas policy before the native resize. A size_changed callback runs
	# before Godot finishes attaching the resized viewport to the screen.
	# The view centres itself in the expanded canvas, at a scale chosen by _update_display_scale.
	if window.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_update_display_scale()
	# Exclusive fullscreen lets Windows bypass the compositor (DWM), which paces OpenGL frames
	# unevenly; plain fullscreen keeps a 1-pixel border precisely to stay composited.
	var window_mode := Window.MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
	if window.mode != window_mode:
		window.mode = window_mode
	_apply_display_pacing()
	_update_layout()
	_apply_audio()
	_update_ghost()
	_upscale.set_shader_parameter("scanline_strength", SCANLINE_STRENGTH[settings.scanlines])
	_refresh_fps_label()
	queue_redraw()


func _create_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.position = Vector2(768, 12)
	_fps_label.size = Vector2(128, 24)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.z_index = 1
	var style := LabelSettings.new()
	style.font_size = 16
	style.font_color = MINT
	style.outline_color = INK
	style.outline_size = 5
	_fps_label.label_settings = style
	add_child(_fps_label)


func _refresh_fps_label() -> void:
	_fps_label.visible = settings.show_fps
	if settings.show_fps:
		var reading := "%d FPS" % roundi(Engine.get_frames_per_second())
		if reading != _fps_label.text:
			_fps_label.text = reading


func _update_ghost() -> void:
	if world:
		var active := playing and mode == Mode.MANUAL and _hotseat_flights.is_empty() \
			and flight.status < FLIGHT.Status.GAME_OVER
		world.set_ghost_replay(settings.ghost_raid() if active else null)


func _apply_display_pacing() -> void:
	var window := get_window()
	var refresh := DisplayServer.screen_get_refresh_rate(window.current_screen)
	var options := [refresh, settings.refresh_limit, settings.sync_mode, settings.quality_hd,
		settings.dynamic_resolution]
	if options == _display_options:
		return
	_display_options = options
	pacing.configure(refresh, settings.refresh_limit, settings.sync_mode, settings.quality_hd,
		settings.dynamic_resolution)
	var sync_mode := DisplayServer.VSYNC_ENABLED
	if settings.sync_mode == PACING.Sync.OFF:
		sync_mode = DisplayServer.VSYNC_DISABLED
	elif settings.sync_mode == PACING.Sync.ADAPTIVE and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		sync_mode = DisplayServer.VSYNC_ADAPTIVE
	if DisplayServer.window_get_vsync_mode(window.get_window_id()) != sync_mode:
		DisplayServer.window_set_vsync_mode(sync_mode, window.get_window_id())
	Engine.max_fps = pacing.cap
	var rate := float(Engine.physics_ticks_per_second)
	var display_rate := refresh if refresh > 0.0 else rate
	_refresh_period = 1.0 / display_rate
	_frame_locked = settings.sync_mode == PACING.Sync.SCREEN and pacing.cap == 0 \
		and absf(display_rate - rate) < 1.0
	RenderingServer.viewport_set_measure_render_time(world.get_viewport_rid(), settings.dynamic_resolution)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), settings.dynamic_resolution)
	_apply_render_resolution()


# Largest canvas scale in thirds that fits the window: each course row then covers the same
# whole number of screen pixels, the remaining space becomes black bars.
func _update_display_scale() -> void:
	var window := get_window()
	var natural := minf(window.size.x / float(PLAY_WIDTH), window.size.y / 594.0)
	if natural <= 0.0:
		return
	_row_pixels = maxi(1, floori(natural * 3.0 + 0.001))
	var factor := _row_pixels / 3.0 / natural
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


func _update_layout() -> void:
	_update_display_scale()
	var canvas := get_viewport_rect().size
	var pixel_scale := _row_pixels / 3.0
	# Whole-pixel margins keep the playfield texels on the screen pixel grid.
	var margin := Vector2(floorf((canvas.x - PLAY_WIDTH) * pixel_scale * 0.5),
		floorf((canvas.y - 594.0) * pixel_scale * 0.5)) / pixel_scale
	margin = margin.max(Vector2.ZERO)
	var width := maxf(PLAY_WIDTH, canvas.x) if settings.panorama else float(PLAY_WIDTH)
	if position != margin or _surface.size.x != width:
		position = margin
		_surface.position.x = -margin.x if settings.panorama else 0.0
		_surface.size.x = width
		menu.position.x = _surface.position.x
		menu.size.x = width
		world.set_panorama(width / PLAY_WIDTH)
		queue_redraw()
	_apply_render_resolution()


func _finish_startup_layout() -> void:
	world.finish_shader_prewarm()
	_update_layout()
	world.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _apply_render_resolution() -> void:
	world.set_quality(_render_rows(), pacing.antialias, _surface.size.x / PLAY_WIDTH)
	_update_upscale()


# Texels per course row in the 3D render: a divisor of the screen pixels per row, so the render
# is shown 1:1 or enlarged by a whole factor. The resolution tier picks the closest divisor.
func _render_rows() -> int:
	var requested := pacing.width / float(WORLD.ROW_TEXEL_WIDTH)
	var rows := _row_pixels
	for divisor in range(_row_pixels, 0, -1):
		if _row_pixels % divisor == 0 and absf(divisor - requested) < absf(rows - requested) - 0.001:
			rows = divisor
	return rows


func _update_upscale() -> void:
	var playfield_pixels := float(PLAY_HEIGHT / 3 * _row_pixels)
	var line_count := clampi(floori(playfield_pixels / CRT_MIN_LINE_PITCH), 1, CRT_RASTER_LINES)
	_upscale.set_shader_parameter("crt_line_count", float(line_count))
	var enlargement := playfield_pixels / world.size.y
	_upscale.set_shader_parameter("sharpness", clampf((enlargement - 1.0) * 0.35, 0.0, 0.25))


func _apply_audio() -> void:
	if sound:
		sound.muted = settings.muted or settings.volume == 0
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.volume / 100.0, 0.001)))
		if sound.muted:
			sound.silence()


func _save_settings() -> void:
	if settings.save() != OK:
		push_warning("Could not save settings or local records.")
		if menu:
			menu.show_notice("notice.save_failed")
	elif menu:
		menu.show_notice("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_rumble()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and menu \
			and menu.screen in [MENU.Screen.SETTINGS, MENU.Screen.CONFIRM_RESET, MENU.Screen.LANGUAGES]:
		_save_settings()


func _draw() -> void:
	_drawn_hud = _hud_state()
	_draw_bars()
	if debug:
		_draw_debug()
	_draw_hud()


# Black bars around the game area when the window is not a whole multiple of the scale.
func _draw_bars() -> void:
	var left := _surface.position.x if _surface else 0.0
	var right := left + (_surface.size.x if _surface else float(PLAY_WIDTH))
	var reach := 100000.0
	draw_rect(Rect2(-reach, -reach, reach * 2.0, reach), Color.BLACK)
	draw_rect(Rect2(-reach, 594.0, reach * 2.0, reach), Color.BLACK)
	draw_rect(Rect2(-reach, 0.0, reach + left, 594.0), Color.BLACK)
	draw_rect(Rect2(right, 0.0, reach, 594.0), Color.BLACK)


func _draw_debug() -> void:
	draw_set_transform(Vector2(-48, 0), 0, SCALE)
	draw_rect(Rect2(flight.x + 1, JET_ROW - 3, 6, 6), MINT, false, 0.35)
	for i in range(COURSE.first_target(flight.distance - 30), COURSE.first_target(flight.distance + 176)):
		if flight.target_gone(i):
			continue
		var target: Vector2 = flight.target_position(i)
		var at := _world(target.x, target.y)
		if at.y < -20 or at.y > 178:
			continue
		var kind: String = COURSE.target(i)[0]
		var half: Vector2 = FLIGHT.TARGET_SIZE[kind]
		draw_rect(Rect2(at - half, half * 2), AMBER, false, 0.35)
	draw_set_transform(Vector2.ZERO)


func _world(x: float, distance: float) -> Vector2:
	var camera_distance := world.presented_distance if world else float(flight.distance)
	return Vector2(x, JET_ROW + camera_distance - distance)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(_surface.position.x if _surface else 0.0, PLAY_HEIGHT,
		_surface.size.x if _surface else PLAY_WIDTH, 111), INK)
	draw_rect(Rect2(_surface.position.x if _surface else 0.0, PLAY_HEIGHT,
		_surface.size.x if _surface else PLAY_WIDTH, 2), FOAM)
	for divider in [310, 418, 582, 746]:
		draw_line(Vector2(divider, 493), Vector2(divider, 584), HUD_RULE, 1.0)
	_draw_fuel_gauge(font)
	_draw_speedometer(font)
	_draw_bank_indicator(font)

	draw_string(font, Vector2(594, 507), tr("hud.score"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
	draw_string(font, Vector2(592, 546), "%06d" % flight.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 33, TEXT)
	var score_note := tr("hud.best_score") % settings.record if _hotseat_flights.is_empty() \
		else tr("hotseat.player") % (_hotseat_player + 1)
	draw_string(font, Vector2(594, 570), score_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_MUTED)
	var reserves := "∞" if flight.cheats & FLIGHT.Cheat.LIVES else str(flight.reserves)
	draw_string(font, Vector2(758, 520), tr("hud.section") % flight.section,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 21, TEXT)
	draw_string(font, Vector2(758, 546), "%d %s" % [flight.section - 1, tr("hud.bridge") if flight.section == 2 else tr("hud.bridges")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)
	draw_string(font, Vector2(758, 566), tr("hud.reserves") % reserves,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HUD_MUTED)
	if sound and sound.muted:
		draw_string(font, Vector2(758, 586), tr("hud.muted"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_MUTED)
	if debug or mode != Mode.MANUAL:
		var telemetry := tr("hud.telemetry") % [flight.tick, flight.x, flight.distance, flight.fuel]
		draw_rect(Rect2(14, 12, 348, 32), INK)
		draw_string(font, Vector2(24, 35), telemetry, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	if debug and world:
		draw_rect(Rect2(14, 44, 348, 27), INK)
		var rendering := tr("hud.rendering") % [
			Engine.get_frames_per_second(), pacing.target, world.size.x, world.size.y]
		draw_string(font, Vector2(24, 63), rendering, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MINT)
	if playing and mode != Mode.MANUAL:
		var top := 76 if debug else 50
		var rate := "%.2f" % _replay_speed
		if settings.language != "en":
			rate = rate.replace(".", ",")
		var rate_hint := tr("hud.replay_speed") % rate
		if _bridge_results_flight:
			rate_hint += "   ·   " + tr("hud.back_to_report")
		var navigation := tr("hud.bridge_navigation")
		var rate_width := font.get_string_size(rate_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var navigation_width := font.get_string_size(navigation, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_rect(Rect2(14, top, maxf(375.0, maxf(rate_width, navigation_width) + 20.0), 47), INK)
		draw_string(font, Vector2(24, top + 18), rate_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MINT)
		draw_string(font, Vector2(24, top + 37), navigation, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HUD_MUTED)
	if menu and menu.screen in [MENU.Screen.RESULTS, MENU.Screen.BRIDGES, MENU.Screen.SCORES, MENU.Screen.INITIALS,
			MENU.Screen.HOTSEAT_RESULTS]:
		return
	var message := ""
	if _replay_seek_target >= 0:
		message = tr("hud.seeking")
	elif _saved_replay and (flight.status >= FLIGHT.Status.GAME_OVER or _recording_finished()):
		var destination := tr("results.bridge_report") if _bridge_results_flight else tr("hud.menu")
		message = tr("hud.last_replay_end" if mode == Mode.LAST else "hud.best_replay_end") % destination
	elif playing and flight.status == FLIGHT.Status.COMPLETE:
		var result := tr("common.raid_complete")
		if mode == Mode.REFERENCE:
			result = tr("hud.island_cleared")
		elif flight.score == COURSE.MAX_SCORE:
			result = tr("hud.max_score")
		message = result + "  ·  " + tr("hud.retry")
	elif flight.status == FLIGHT.Status.GAME_OVER:
		message = tr("hud.game_over") + "  ·  " + tr("hud.retry")
	elif _recording_finished():
		message = tr("hud.recording_end")
	elif flight.status == FLIGHT.Status.CRASHED:
		if flight.crash_cause == "fuel" and world and not world._glide_impacted:
			message = tr("hud.fuel_fall")
		else:
			message = tr("hud.lost_fuel" if flight.crash_cause == "fuel" else "hud.lost_collision")
	if not message.is_empty():
		draw_rect(Rect2(0, 202, 912, 58), Color(0.03, 0.11, 0.16, 0.92))
		draw_string(font, Vector2(0, 240), message, HORIZONTAL_ALIGNMENT_CENTER, 912, 24, TEXT)


# What _draw() shows, down to the bank angle. The fuel bar shrinks by a fraction of a pixel per
# tick: only the screen pixel its edge reaches counts, and an edge close to a pixel center
# always redraws. The image is therefore the same as with a redraw on every tick.
func _hud_state() -> Array:
	var screen := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var fraction := clampf(float(flight.fuel) / FLIGHT.FULL_TANK, 0.0, 1.0)
	var tenths := fraction * 10.0
	var segment := floori(tenths)
	var segment_width := (FUEL_BAR.size.x - 9.0 * 4.0) / 10.0
	var edge_x := FUEL_BAR.position.x + segment * (segment_width + 4.0) + segment_width * (tenths - segment)
	var edge := (screen * Vector2(edge_x, FUEL_BAR.position.y)).x - 0.5
	var fuel_edge := ceili(edge) if absf(edge - roundf(edge)) > 0.01 else -flight.fuel
	return [flight, flight.status, flight.crash_cause, flight.over_fuel_barge, flight.fuel >= FLIGHT.FULL_TANK,
		flight.fuel < FLIGHT.LOW_FUEL, floori(fraction * 100), segment, fuel_edge, flight.speed, flight.score,
		flight.section, flight.reserves, flight.cheats, world.player_bank_angle() if world else 0.0,
		world._glide_impacted if world else false, settings.record, sound.muted if sound else false,
		playing, paused, debug, mode, menu.screen if menu else -1, _replay_seek_target, _saved_replay,
		_bridge_results_flight, _recording_finished(), TranslationServer.get_locale(), screen,
		_surface.position if _surface else Vector2.ZERO, _surface.size if _surface else Vector2.ZERO]


func _draw_fuel_gauge(font: Font) -> void:
	var fraction := clampf(float(flight.fuel) / FLIGHT.FULL_TANK, 0.0, 1.0)
	var low_fuel := flight.fuel < FLIGHT.LOW_FUEL
	var active := playing and flight.status == FLIGHT.Status.FLYING and not _recording_finished()
	var tint := AMBER if low_fuel else MINT
	var label := tr("hud.low_fuel") if low_fuel and active else tr("hud.fuel")
	if active and flight.over_fuel_barge:
		tint = FUEL_GAIN
		label = tr("hud.full") if flight.fuel >= FLIGHT.FULL_TANK else tr("hud.refueling")

	draw_string(font, Vector2(24, 528), "%d %%" % floori(fraction * 100),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 45, tint if low_fuel else TEXT)
	draw_string(font, Vector2(26, 553), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, TEXT)
	var bar := FUEL_BAR
	var segment_width := (bar.size.x - 9.0 * 4.0) / 10.0
	for index in range(10):
		var at := bar.position + Vector2(index * (segment_width + 4.0), 0)
		draw_rect(Rect2(at, Vector2(segment_width, bar.size.y)), GAUGE_TRACK)
		var fill := clampf(fraction * 10.0 - index, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(at, Vector2(segment_width * fill, bar.size.y)), tint)
	var threshold := 10.0 * FLIGHT.LOW_FUEL / FLIGHT.FULL_TANK
	var warning_x := bar.position.x + threshold * segment_width + floorf(threshold) * 4.0
	draw_line(Vector2(warning_x, 565), Vector2(warning_x, 584), HUD_RULE, 1.0)


func _draw_speedometer(font: Font) -> void:
	var center := Vector2(364, 539)
	var radius := 34.0
	draw_arc(center, radius, -PI, 0.0, 32, HUD_RULE, 1.7, true)
	for tick in range(9):
		var direction := Vector2.from_angle(lerpf(-PI, 0.0, tick / 8.0))
		draw_line(center + direction * (radius - 5), center + direction * radius, HUD_RULE, 1.2, true)
	var throttle := clampf(inverse_lerp(FLIGHT.MIN_SPEED, FLIGHT.MAX_SPEED, flight.speed), 0.0, 1.0)
	var needle := Vector2.from_angle(lerpf(-PI, 0.0, throttle))
	draw_line(center, center + needle * (radius - 5), TEXT, 2.1, true)
	draw_circle(center, 3.6, TEXT, true, -1.0, true)
	draw_string(font, Vector2(314, 559), tr("hud.speed"), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, HUD_MUTED)
	draw_string(font, Vector2(314, 583), str(flight.speed), HORIZONTAL_ALIGNMENT_CENTER, 100, 23, TEXT)


func _draw_bank_indicator(font: Font) -> void:
	var center := Vector2(454, 538)
	var bank := world.player_bank_angle() if world else 0.0
	draw_circle(center, BANK_DIAL_RADIUS, Color("#655f51"), true, -1.0, true)
	draw_set_transform(center, -bank)
	draw_colored_polygon(_horizon_sky, Color("#447a9c"))
	draw_line(Vector2(-BANK_DIAL_RADIUS, 0), Vector2(BANK_DIAL_RADIUS, 0), TEXT, 1.35, true)
	draw_set_transform(Vector2.ZERO)
	draw_arc(center, BANK_DIAL_RADIUS, 0.0, TAU, 48, TEXT, 1.35, true)
	for tick in range(-3, 4):
		var direction := Vector2.from_angle(-PI * 0.5 + tick * PI / 12.0)
		draw_line(center + direction * (BANK_DIAL_RADIUS - 5),
			center + direction * (BANK_DIAL_RADIUS - 1), TEXT, 1.0, true)
	for side in [-1.0, 1.0]:
		draw_line(center + Vector2(side * 20, 0), center + Vector2(side * 7, 0), TEXT, 1.8, true)
	draw_circle(center, 2.1, TEXT, true, -1.0, true)
	draw_string(font, Vector2(493, 526), tr("hud.bank"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_MUTED)
	draw_string(font, Vector2(493, 558), "%d°" % roundi(absf(rad_to_deg(bank))),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 27, TEXT)


func _make_horizon_sky() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(33):
		points.append(Vector2.from_angle(lerpf(-PI, 0.0, i / 32.0)) * BANK_DIAL_RADIUS)
	return points
