extends Node2D

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const WORLD = preload("res://flight_world.gd")
const SOUND = preload("res://flight_sound.gd")
const MENU = preload("res://flight_menu.gd")
const SETTINGS = preload("res://flight_settings.gd")
const SCALE := Vector2(6, 3)
const PLAY_HEIGHT := 483
const JET_ROW := 151
const FOAM := Color("#317587")
const INK := Color("#071e2c")
const TEXT := Color("#e8f3ed")
const AMBER := Color("#ffbf67")
const MINT := Color("#a8ecc9")
enum Mode { MANUAL, REFERENCE, RECORDING }

var flight := FLIGHT.new()
var mode := Mode.MANUAL
var recording := PackedByteArray()
var paused := false
var debug := false
var playing := false
var world: WORLD
var sound: SOUND
var menu: MENU
var settings := SETTINGS.new()


func _ready() -> void:
	settings.load_file()
	if DisplayServer.get_name() != "headless":
		world = WORLD.new()
		add_child(world)
		world.sync(flight, 0)
		sound = SOUND.new()
		add_child(sound)
		menu = MENU.new()
		add_child(menu)
		menu.configure(settings)
		menu.action_requested.connect(_menu_action)
		menu.settings_changed.connect(_apply_settings)
		menu.settings_committed.connect(_save_settings)
		_apply_settings()
	else:
		settings.apply_bindings()
	if "--replay" in OS.get_cmdline_user_args():
		_start(Mode.REFERENCE)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if menu and menu.screen == MENU.Screen.SETTINGS and event.physical_keycode != KEY_ESCAPE:
		return
	match event.physical_keycode:
		KEY_R:
			_start(Mode.MANUAL)
		KEY_F5:
			_start(Mode.REFERENCE)
		KEY_F6:
			if not recording.is_empty():
				_start(Mode.RECORDING)
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
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not playing or paused or _recording_finished() or flight.status >= FLIGHT.Status.GAME_OVER:
		return
	var controls := 0
	match mode:
		Mode.MANUAL:
			controls = settings.controls()
		Mode.REFERENCE:
			controls = FLIGHT.reference_controls(flight.tick + 1)
		Mode.RECORDING:
			controls = recording[flight.tick]
	if mode == Mode.MANUAL:
		recording.append(controls)
	flight.advance(controls)
	if mode == Mode.MANUAL and flight.status >= FLIGHT.Status.GAME_OVER and settings.update_record(flight.score):
		_save_settings()
	if world:
		world.sync(flight, delta)
	if sound:
		sound.sync(flight)
		if _recording_finished():
			sound.silence()
	queue_redraw()


func _start(next_mode: Mode) -> void:
	flight.reset()
	flight.finish_distance = COURSE.REFERENCE_END if next_mode == Mode.REFERENCE else COURSE.END
	mode = next_mode
	if mode == Mode.MANUAL:
		recording.clear()
	paused = false
	playing = true
	if menu:
		menu.dismiss()
	if world:
		world.reset_effects()
		world.sync(flight, 0)
	if sound:
		sound.reset()


func _recording_finished() -> bool:
	return mode == Mode.RECORDING and flight.tick >= recording.size()


func _toggle_pause() -> void:
	if menu and menu.screen == MENU.Screen.SETTINGS:
		menu.back()
	elif paused:
		_resume()
	elif playing and (flight.status >= FLIGHT.Status.GAME_OVER or _recording_finished()):
		_show_title()
	elif playing:
		paused = true
		if sound:
			sound.silence()
		if menu:
			menu.show_pause()


func _resume() -> void:
	paused = false
	if menu:
		menu.dismiss()


func _show_title() -> void:
	flight.reset()
	playing = false
	paused = false
	mode = Mode.MANUAL
	if sound:
		sound.reset()
	if world:
		world.reset_effects()
		world.sync(flight, 0)
	if menu:
		menu.show_title()


func _menu_action(action: StringName) -> void:
	match action:
		&"play":
			_start(Mode.MANUAL)
		&"reference":
			_start(Mode.REFERENCE)
		&"resume":
			_resume()
		&"title":
			_show_title()
		&"quit":
			get_tree().quit()
	queue_redraw()


func _apply_settings() -> void:
	settings.apply_bindings()
	if world:
		world.set_quality(settings.quality_hd)
	var window_mode := Window.MODE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
	if get_window().mode != window_mode:
		get_window().mode = window_mode
	var sync_mode := DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != sync_mode:
		DisplayServer.window_set_vsync_mode(sync_mode)
	_apply_audio()


func _apply_audio() -> void:
	if sound:
		sound.muted = settings.muted or settings.volume == 0
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.volume / 100.0, 0.001)))
		if sound.muted:
			sound.silence()


func _save_settings() -> void:
	if settings.save() != OK:
		push_warning("Sauvegarde des réglages ou du record indisponible.")
		if menu:
			menu.show_notice("Sauvegarde locale indisponible.")
	elif menu:
		menu.show_notice("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and menu and menu.screen == MENU.Screen.SETTINGS:
		_save_settings()


func _draw() -> void:
	if world:
		draw_texture_rect(world.get_texture(), Rect2(0, 0, 912, PLAY_HEIGHT), false)
	if debug:
		_draw_debug()
	_draw_hud()


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
		var kind: String = COURSE.TARGETS[i][0]
		var half: Vector2 = FLIGHT.TARGET_SIZE[kind]
		draw_rect(Rect2(at - half, half * 2), AMBER, false, 0.35)
	draw_set_transform(Vector2.ZERO)


func _world(x: float, distance: float) -> Vector2:
	return Vector2(x, JET_ROW + flight.distance - distance)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, PLAY_HEIGHT, 912, 111), INK)
	draw_rect(Rect2(0, PLAY_HEIGHT, 912, 2), FOAM)
	draw_string(font, Vector2(24, 519), "FLUVIAL STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TEXT)
	draw_string(font, Vector2(24, 552), "SECTION %02d   /   RÉSERVES %d" % [flight.section, flight.reserves],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	var fraction := float(flight.fuel) / FLIGHT.FULL_TANK
	var low_fuel := flight.fuel < FLIGHT.LOW_FUEL
	draw_string(font, Vector2(318, 515), "CARBURANT   %d%%" % roundi(fraction * 100),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AMBER if low_fuel else TEXT)
	draw_rect(Rect2(318, 528, 270, 10), FOAM)
	draw_rect(Rect2(318, 528, 270 * fraction, 10), AMBER if low_fuel else MINT)
	draw_string(font, Vector2(642, 521), "%06d" % flight.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, AMBER)
	draw_string(font, Vector2(642, 552), "PONTS %02d / %02d" % [flight.section - 1, COURSE.BRIDGES.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	var audio := "M Son coupé" if sound and sound.muted else "M Son"
	draw_string(font, Vector2(24, 580), "Échap / Start Pause   ·   R Rejouer   ·   F5 Référence   ·   F6 Dernier vol   ·   F1 Diagnostic   ·   " + audio,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
	if debug or mode != Mode.MANUAL:
		var telemetry := "T %03d   X %d   DIST %d   FUEL %d" % [flight.tick, flight.x, flight.distance, flight.fuel]
		draw_rect(Rect2(14, 12, 348, 32), INK)
		draw_string(font, Vector2(24, 35), telemetry, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	var message := ""
	if playing and flight.status == FLIGHT.Status.COMPLETE:
		message = "Îlot franchi  ·  R Rejouer  ·  Échap Menu" if mode == Mode.REFERENCE else "Raid terminé  ·  R Rejouer  ·  Échap Menu"
	elif flight.status == FLIGHT.Status.GAME_OVER:
		message = "Fin de partie  ·  R Rejouer  ·  Échap Menu"
	elif _recording_finished():
		message = "Fin du rejeu  ·  R pour piloter"
	elif flight.status == FLIGHT.Status.CRASHED:
		message = "Jet perdu  ·  " + ("panne sèche" if flight.crash_cause == "fuel" else "collision")
	if not message.is_empty():
		draw_rect(Rect2(0, 202, 912, 58), Color(0.03, 0.11, 0.16, 0.92))
		draw_string(font, Vector2(0, 240), message, HORIZONTAL_ALIGNMENT_CENTER, 912, 24, TEXT)
