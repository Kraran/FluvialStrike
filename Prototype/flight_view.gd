extends Node2D

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const WORLD = preload("res://flight_world.gd")
const SOUND = preload("res://flight_sound.gd")
const MENU = preload("res://flight_menu.gd")
const SETTINGS = preload("res://flight_settings.gd")
const PACING = preload("res://frame_pacing.gd")
const UPSCALE = preload("res://upscale.gdshader")
const SCALE := Vector2(6, 3)
const PLAY_HEIGHT := 483
const JET_ROW := 151
const FOAM := Color("#317587")
const INK := Color("#071e2c")
const TEXT := Color("#e8f3ed")
const AMBER := Color("#ffbf67")
const MINT := Color("#a8ecc9")
const FUEL_GAIN := Color("#94eaf4")
enum Mode { MANUAL, REFERENCE, RECORDING }

var flight := FLIGHT.new()
var mode := Mode.MANUAL
var recording := PackedByteArray()
var _recorded_cheats := 0
var paused := false
var debug := false
var playing := false
var world: WORLD
var sound: SOUND
var menu: MENU
var settings := SETTINGS.new()
var pacing := PACING.new()
var _upscale := ShaderMaterial.new()
var _display_options: Array = []
var _last_render_time := 0
var _display_poll := 0.0


func _ready() -> void:
	settings.load_file()
	if DisplayServer.get_name() != "headless":
		world = WORLD.new()
		world.set_player_aircraft(settings.aircraft)
		add_child(world)
		world.sync(flight, true)
		var surface := TextureRect.new()
		surface.show_behind_parent = true
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		surface.texture = world.get_texture()
		surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		surface.size = Vector2(912, PLAY_HEIGHT)
		_upscale.shader = UPSCALE
		surface.material = _upscale
		add_child(surface)
		get_window().size_changed.connect(_update_upscale)
		sound = SOUND.new()
		add_child(sound)
		world.spatial_effect_requested.connect(_on_spatial_effect_requested)
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
	if menu and menu.screen in [MENU.Screen.SETTINGS, MENU.Screen.HANGAR] and event.physical_keycode != KEY_ESCAPE:
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


func _physics_process(_delta: float) -> void:
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
	var recovering := flight.status == FLIGHT.Status.CRASHED
	flight.advance(controls)
	if world:
		world.sync(flight, recovering and flight.status == FLIGHT.Status.FLYING)
	if sound:
		sound.sync(flight)
		if _recording_finished():
			sound.silence()
	if mode == Mode.MANUAL and flight.status >= FLIGHT.Status.GAME_OVER:
		if flight.cheats == 0 and settings.update_raid_records(flight.score, flight.section):
			_save_settings()
		if menu:
			menu.show_results(flight)
	queue_redraw()


func _process(delta: float) -> void:
	if not world:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_render_time) / 1000.0 if _last_render_time else 0.0
	_last_render_time = now
	_display_poll += delta
	if _display_poll >= 1.0:
		_display_poll = 0.0
		_apply_display_pacing()
	if paused:
		return
	var flying := playing and flight.status < FLIGHT.Status.GAME_OVER and not _recording_finished()
	var fraction := Engine.get_physics_interpolation_fraction() if flying else 1.0
	world.present(flight, fraction, delta)
	if sound and not sound.muted and flying and flight.status == FLIGHT.Status.FLYING:
		sound.update_enemies(world.enemy_audio_sources(flight), delta)
	elif sound:
		sound.update_enemies({}, delta)
	if flying and settings.dynamic_resolution:
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(world.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if pacing.observe(frame_ms, gpu_ms):
			_apply_render_resolution()
	if debug:
		queue_redraw()


func _on_spatial_effect_requested(kind: String, pan: float) -> void:
	if not _recording_finished():
		sound.play_spatial_effect(kind, pan)


func _start(next_mode: Mode) -> void:
	flight.reset()
	flight.finish_distance = COURSE.REFERENCE_END if next_mode == Mode.REFERENCE else COURSE.END
	mode = next_mode
	if mode == Mode.MANUAL:
		recording.clear()
		flight.cheats = menu.cheats if menu else 0
		_recorded_cheats = flight.cheats
	elif mode == Mode.RECORDING:
		flight.cheats = _recorded_cheats
	paused = false
	playing = true
	if menu:
		menu.dismiss()
	if world:
		world.reset_effects()
		world.sync(flight, true)
	if sound:
		sound.reset()


func _recording_finished() -> bool:
	return mode == Mode.RECORDING and flight.tick >= recording.size()


func _toggle_pause() -> void:
	if menu and menu.screen in [MENU.Screen.SETTINGS, MENU.Screen.HANGAR]:
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
	if world:
		world.sync(flight, true)
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
		world.sync(flight, true)
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
		&"aircraft_selected":
			world.set_player_aircraft(settings.aircraft)
			world.sync(flight, true)
		&"quit":
			get_tree().quit()
	queue_redraw()


func _apply_settings() -> void:
	settings.apply_bindings()
	var window_mode := Window.MODE_FULLSCREEN if settings.fullscreen else Window.MODE_WINDOWED
	if get_window().mode != window_mode:
		get_window().mode = window_mode
	_apply_display_pacing()
	_apply_audio()


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
	RenderingServer.viewport_set_measure_render_time(world.get_viewport_rid(), settings.dynamic_resolution)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), settings.dynamic_resolution)
	_apply_render_resolution()


func _apply_render_resolution() -> void:
	world.set_quality(pacing.width, pacing.antialias)
	_update_upscale()


func _update_upscale() -> void:
	var window_size := get_window().size
	var output_width := minf(window_size.x, window_size.y * 912.0 / 594.0)
	var enlargement := output_width / world.size.x
	_upscale.set_shader_parameter("sharpness", clampf((enlargement - 1.0) * 0.35, 0.0, 0.25))


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
		var kind: String = COURSE.target(i)[0]
		var half: Vector2 = FLIGHT.TARGET_SIZE[kind]
		draw_rect(Rect2(at - half, half * 2), AMBER, false, 0.35)
	draw_set_transform(Vector2.ZERO)


func _world(x: float, distance: float) -> Vector2:
	var camera_distance := world.presented_distance if world else float(flight.distance)
	return Vector2(x, JET_ROW + camera_distance - distance)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, PLAY_HEIGHT, 912, 111), INK)
	draw_rect(Rect2(0, PLAY_HEIGHT, 912, 2), FOAM)
	draw_string(font, Vector2(24, 519), "FLUVIAL STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TEXT)
	var reserves := "∞" if flight.cheats & FLIGHT.Cheat.LIVES else str(flight.reserves)
	draw_string(font, Vector2(24, 552), "SECTION %02d   /   RÉSERVES %s" % [flight.section, reserves],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	_draw_fuel_gauge(font)
	draw_string(font, Vector2(642, 521), "%06d" % flight.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, AMBER)
	draw_string(font, Vector2(642, 552), "PONTS %02d" % (flight.section - 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	var audio := "M Son coupé" if sound and sound.muted else "M Son"
	draw_string(font, Vector2(24, 580), "Échap / Start Pause   ·   R Rejouer   ·   F5 Référence   ·   F6 Dernier vol   ·   F1 Diagnostic   ·   " + audio,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
	if debug or mode != Mode.MANUAL:
		var telemetry := "T %03d   X %d   DIST %d   FUEL %d" % [flight.tick, flight.x, flight.distance, flight.fuel]
		draw_rect(Rect2(14, 12, 348, 32), INK)
		draw_string(font, Vector2(24, 35), telemetry, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MINT)
	if debug and world:
		draw_rect(Rect2(14, 44, 348, 27), INK)
		var rendering := "%d i/s  /  %.0f cible  /  3D %d × %d" % [
			Engine.get_frames_per_second(), pacing.target, world.size.x, world.size.y]
		draw_string(font, Vector2(24, 63), rendering, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MINT)
	if menu and menu.screen == MENU.Screen.RESULTS:
		return
	var message := ""
	if playing and flight.status == FLIGHT.Status.COMPLETE:
		var result := "Raid terminé"
		if mode == Mode.REFERENCE:
			result = "Îlot franchi"
		elif flight.score == COURSE.MAX_SCORE:
			result = "Score maximal atteint"
		message = result + "  ·  R Rejouer  ·  Échap Menu"
	elif flight.status == FLIGHT.Status.GAME_OVER:
		message = "Fin de partie  ·  R Rejouer  ·  Échap Menu"
	elif _recording_finished():
		message = "Fin du rejeu  ·  R pour piloter"
	elif flight.status == FLIGHT.Status.CRASHED:
		message = "Jet perdu  ·  " + ("panne sèche" if flight.crash_cause == "fuel" else "collision")
	if not message.is_empty():
		draw_rect(Rect2(0, 202, 912, 58), Color(0.03, 0.11, 0.16, 0.92))
		draw_string(font, Vector2(0, 240), message, HORIZONTAL_ALIGNMENT_CENTER, 912, 24, TEXT)


func _draw_fuel_gauge(font: Font) -> void:
	var fraction := clampf(float(flight.fuel) / FLIGHT.FULL_TANK, 0.0, 1.0)
	var low_fuel := flight.fuel < FLIGHT.LOW_FUEL
	var active := playing and flight.status == FLIGHT.Status.FLYING and not _recording_finished()
	var filling := active and flight.over_fuel_barge
	var tint := MINT
	var status_label := ""
	if filling:
		tint = FUEL_GAIN
		status_label = "PLEIN" if flight.fuel >= FLIGHT.FULL_TANK else "RAVITAILLEMENT"
	elif low_fuel:
		tint = AMBER
		if active:
			status_label = "RÉSERVE BASSE"

	var bar := Rect2(318, 528, 270, 10)
	draw_string(font, Vector2(bar.position.x, 515), "CARBURANT   %d%%" % floori(fraction * 100),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT)
	draw_rect(bar, FOAM)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), tint)
	var warning_x := bar.position.x + bar.size.x * FLIGHT.LOW_FUEL / FLIGHT.FULL_TANK
	draw_line(Vector2(warning_x, bar.position.y - 2), Vector2(warning_x, bar.end.y + 2), INK, 2.0)
	if not status_label.is_empty():
		draw_string(font, Vector2(bar.position.x, 557), status_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
