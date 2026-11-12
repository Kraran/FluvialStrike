extends SubViewport

signal spatial_effect_requested(kind: String, pan: float)

const COURSE = preload("res://course.gd")
const FLIGHT = preload("res://flight.gd")
const MODELS = preload("res://flight_models.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
const BANK_SHADER = preload("res://bank.gdshader")
const CANOPY_SHADER = preload("res://canopy.gdshader")
const SCENERY = preload("res://scenery.gd")
const EFFECTS = preload("res://flight_effects.gd")
const X_SCALE := 0.6
const OUTER_BAND_WIDTH := 32
const MAX_RENDER_WIDTH := 4096
# Render width per texel of course row: 912 * 161 / 483.
const ROW_TEXEL_WIDTH := 304
const Z_SCALE := 0.3
const PLAYER_CENTER_X := 4.0
const PLAYER_ALTITUDE := 2.30
const SHOT_RENDER_X_CORRECTION := FLIGHT.NATIVE_SHOT_X_OFFSET - PLAYER_CENTER_X
# Render the MiG-29 above the tallest scaled tree, including canopy movement.
const ENEMY_JET_ALTITUDE := 6.6
const JET_TRACK_WIDTH := 160.0
const JET_MODEL_REACH := 2.55
const HELICOPTER_ALTITUDE := 1.38
const ROTOR_FULL_DISTANCE := 5.0
const ROTOR_MAX_DISTANCE := 29.0
const STREAM_START := 9408
const TILE_LENGTH := 512
const ORIGIN_STEP := 4096
const MAX_BANK_ANGLE := PI * 50.0 / 180.0
const GHOST_STEPS_PER_FRAME := 96
const GHOST_TINT := Color("#9aebf7")
const GLIDE_TICKS := 52
const WATER_IMPACT_HEIGHT := 0.40
const GLIDE_OBSTACLE_HEIGHT := {"fuel": 0.68, "tanker": 1.24, "helicopter": 1.92}
const TANKER_BURSTS := [0.23, 0.52]
const HELICOPTER_FALL := 0.62
const HELICOPTER_SMOKE_INTERVAL := 0.085
const BRIDGE_LEFT := 64.0
const BRIDGE_RIGHT := 96.0
const BRIDGE_DECK_HEIGHT := 0.52
const BRIDGE_WATER_HEIGHT := 0.042
const BRIDGE_BAY_WIDTH := 5.34


class DepartingJet:
	var actor: Node3D
	var drift: float


class TargetWreck:
	var actor: Node3D
	var kind: String
	var origin: Vector3
	var drift := 0.0
	var age := 0.0
	var stage := 0

class BridgePiece:
	var actor: Node3D
	var origin: Vector3
	var side: float
	var age: float
	var width: float
	var half_depth: float
	var joint := false
	var splashed := false


var _scene := Node3D.new()
var _intro_scene: Node3D
var _camera := Camera3D.new()
var _models := MODELS.new()
var _aircraft: Node3D
var _ghost_raid: RAID_REPLAY
var _ghost_aircraft: Node3D
var _ghost_material: StandardMaterial3D
var _aircraft_id := AIRCRAFT.DEFAULT
var _aircraft_nose := MODELS.STRATOWING_NOSE
var _aircraft_tip: Vector2 = AIRCRAFT.AIRCRAFT[AIRCRAFT.DEFAULT].tip
var _shot: Node3D
var _effects: EFFECTS
var _effect_cursor := 0
var _crossings := {}
var _decks := {}
var _actors := {}
var _rotors := {}
var _departing_jets: Array[DepartingJet] = []
var _target_wrecks: Array[TargetWreck] = []
var _templates := {}
var _bridge_piece_model: Node3D
var _crossing_model: Node3D
var _shader_prewarm: Node3D
var _bridge_pieces: Array[BridgePiece] = []
var _was_flying := true
var _glide_tick := -1
var _glide_start := Vector3.ZERO
var _glide_travel := Vector2.ZERO
var _glide_impact_tick := GLIDE_TICKS
var _glide_hit_object := false
var _glide_impacted := false
var _clock := 0.0
var _previous_pose := Vector2.ZERO
var _pose := Vector2.ZERO
var _previous_shot := Vector3.ZERO
var _shot_pose := Vector3.ZERO
var _bank_angle := 0.0
var _last_projectile := -1
var presented_pose := Vector2.ZERO
var _scenery := SCENERY.new()
var _tiles := {}
var _terrain_materials := {}
var _scatter_materials := {}
var _canopy_material := ShaderMaterial.new()
var _rock_mesh := SphereMesh.new()
var _landmark_models: Array[Node3D] = []
var _ground_mesh := ArrayMesh.new()
var _ground_plane := PlaneMesh.new()
var _outer_bands := 0
var _playfield_width := 1368.0
var _texel_rows := 3
var _origin_distance := 0
var presented_distance := 0.0
var _sun: DirectionalLight3D


func _init() -> void:
	_canopy_material.shader = CANOPY_SHADER
	_rock_mesh.radial_segments = 7
	_rock_mesh.rings = 4


func _ready() -> void:
	set_quality(4, true)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_scene)
	_intro_scene = Node3D.new()
	_scene.add_child(_intro_scene)
	_configure_light()
	_build_landscape()
	_build_crossings()
	_crossing_model = _make_crossing_model()
	_bridge_piece_model = _make_bridge_piece_model()
	_templates = {"tanker": _models.tanker(), "helicopter": _models.helicopter(),
		"fuel": _models.fuel_barge(), "jet": _models.aircraft(true)}
	_aircraft = _models.player_aircraft(_aircraft_id)
	_scene.add_child(_aircraft)
	_effects = EFFECTS.new()
	_scene.add_child(_effects)
	_shot = Node3D.new()
	_scene.add_child(_shot)
	var tracer := StandardMaterial3D.new()
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.albedo_color = Color("#fff3b4")
	var core := _models.box(_shot, Vector3.ZERO, Vector3(0.18, 0.10, 1.22), tracer)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shot.add_child(_effects.make_trail())
	_build_shader_prewarm()


# Particles, the shot, the ghost, jets and bridge debris are first drawn mid-flight. A tiny copy of
# each sits under the title panel at the screen center for the first frame, so their shaders
# compile before play instead of on the first explosion.
func _build_shader_prewarm() -> void:
	_shader_prewarm = Node3D.new()
	_shader_prewarm.position = Vector3(0, 0, -(_camera.position.y - 1.0))
	_shader_prewarm.scale = Vector3.ONE * 0.01
	_shader_prewarm.add_child(_effects.make_prewarm())
	var models: Array[Node3D] = [_shot, _bridge_piece_model, _crossing_model]
	models.append_array(_templates.values())
	for model in models:
		var copy := model.duplicate() as Node3D
		copy.show()
		_shader_prewarm.add_child(copy)
	_models.box(_shader_prewarm, Vector3.ZERO, Vector3.ONE, _make_ghost_material())
	_camera.add_child(_shader_prewarm)


func finish_shader_prewarm() -> void:
	if _shader_prewarm:
		_shader_prewarm.queue_free()
		_shader_prewarm = null


func set_player_aircraft(id: String) -> void:
	id = AIRCRAFT.validated(id)
	if id == _aircraft_id:
		return
	_aircraft_id = id
	var entry: Dictionary = AIRCRAFT.AIRCRAFT[id]
	_aircraft_nose = Vector3(0, 0, entry.nose)
	_aircraft_tip = entry.tip
	if _aircraft == null:
		return
	var previous := _aircraft
	_aircraft = _models.player_aircraft(id)
	_aircraft.transform = previous.transform
	_aircraft.visible = previous.visible
	_scene.remove_child(previous)
	previous.queue_free()
	_scene.add_child(_aircraft)


func set_ghost_replay(replay: RAID_REPLAY) -> void:
	if replay == _ghost_raid:
		return
	_ghost_raid = replay
	if _ghost_aircraft:
		_scene.remove_child(_ghost_aircraft)
		_ghost_aircraft.queue_free()
		_ghost_aircraft = null
		_ghost_material = null
	if replay == null:
		return
	_ghost_material = _make_ghost_material()
	_ghost_aircraft = _models.player_aircraft(replay.aircraft)
	for part: MeshInstance3D in _ghost_aircraft.get_children():
		part.material_override = _ghost_material
	_models.batch_by_material(_ghost_aircraft)
	for part: MeshInstance3D in _ghost_aircraft.get_children():
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_aircraft.hide()
	_scene.add_child(_ghost_aircraft)


func _make_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = GHOST_TINT
	return material


# The camera shows 161 course rows: rendering 161 * texel_rows lines gives every row the same
# whole number of texels, so a scroll of one row per frame moves the image by texel_rows texels.
func set_quality(texel_rows: int, antialias: bool, aspect_scale: float = 1.0) -> void:
	var expanded_width := ROW_TEXEL_WIDTH * texel_rows * aspect_scale
	var render_width := mini(roundi(expanded_width), MAX_RENDER_WIDTH)
	var height := 161 * texel_rows
	if expanded_width > MAX_RENDER_WIDTH:
		height = maxi(1, roundi(height * render_width / expanded_width))
	size = Vector2i(render_width, height)
	_texel_rows = texel_rows
	_playfield_width = render_width / aspect_scale
	msaa_3d = Viewport.MSAA_2X if antialias else Viewport.MSAA_DISABLED


# World units covered by one render texel along the course.
func texel_length() -> float:
	return Z_SCALE / _texel_rows


func sync(flight: FLIGHT, reset_pose: bool = false) -> void:
	_rebase(flight.distance)
	_sync_tiles(flight.distance)
	_previous_pose = _pose
	_pose = Vector2(flight.visual_x() + PLAYER_CENTER_X, flight.visual_distance() - _origin_distance)
	var jumped := reset_pose or absf(_pose.y - _previous_pose.y) > 2.01
	if jumped:
		_previous_pose = _pose
	_bank_angle = _aircraft_bank(flight.visual_lateral_speed())
	var running := flight.status == FLIGHT.Status.FLYING or flight.status == FLIGHT.Status.COMPLETE
	if flight.status != FLIGHT.Status.CRASHED:
		_glide_tick = -1
		_aircraft.rotation.x = 0.0
	elif flight.crash_cause == "fuel" and _glide_tick < 0 and (reset_pose or _was_flying):
		_start_fuel_glide(flight)
	_aircraft.visible = running or (_glide_tick >= 0 and not _glide_impacted)
	if not jumped and flight.status == FLIGHT.Status.FLYING:
		var throttle := float(flight.speed - FLIGHT.MIN_SPEED) / (FLIGHT.MAX_SPEED - FLIGHT.MIN_SPEED)
		var at := _point(_previous_pose.x, _previous_pose.y + _origin_distance, 2.30)
		_effects.wingtip_vapor(at, _aircraft.rotation.z, throttle, _aircraft_tip)
	if not reset_pose and _was_flying and flight.status == FLIGHT.Status.CRASHED and flight.crash_cause != "fuel":
		_player_explosion(_point(_pose.x, _pose.y + _origin_distance, PLAYER_ALTITUDE) + _aircraft_nose * 0.6)
	_was_flying = running
	_shot.visible = flight.shot_active
	_previous_shot = _shot_pose
	var nose := _player_nose(_pose)
	var native_travel := float(flight.shot_distance - flight.distance) - 2.5
	var ahead := maxf(0.0, native_travel * Z_SCALE + _aircraft_nose.z)
	var shot_x := flight.shot_x + flight.visual_x() - flight.x - SHOT_RENDER_X_CORRECTION
	_shot_pose = Vector3(_x(shot_x), lerpf(nose.y, 1.15, smoothstep(0.0, 2.5, ahead)), nose.z - ahead)
	if jumped:
		_previous_shot = _shot_pose
	elif _last_projectile < 0 or flight.shot_distance < _last_projectile:
		_previous_shot = _player_nose(_previous_pose)
	_last_projectile = flight.shot_distance if flight.shot_active else -1
	_sync_shot_effects(flight, reset_pose)

	_sync_crossings(flight)
	_sync_fleet(flight, reset_pose)
	if reset_pose:
		for jet in _departing_jets:
			jet.actor.hide()
			jet.actor.queue_free()
		_departing_jets.clear()
	if jumped:
		present(flight, 1.0, 0.0)


func _sync_shot_effects(flight: FLIGHT, reset_pose: bool) -> void:
	if not reset_pose:
		for index in range(_effect_cursor, flight.events.size()):
			var event := flight.events[index]
			match event.kind:
				"fire":
					_effects.muzzle(_player_nose(_pose))
				"bridge":
					_break_bridge(event.index, event.impact)
		var miss := flight.missed_shot
		var splash_x := miss.x - SHOT_RENDER_X_CORRECTION
		if miss.is_finite() and COURSE.is_water(floori(miss.y), floori(splash_x), ceili(splash_x) + 1):
			var at := _point(splash_x, miss.y, 0.036)
			_effects.splash(at)
			spatial_effect_requested.emit("splash", _screen_pan(_screen_position(at).x))
	_effect_cursor = flight.events.size()


func _sync_fleet(flight: FLIGHT, reset_pose: bool = false) -> void:
	var first := COURSE.first_target(flight.distance - 25)
	var end := COURSE.first_target(flight.distance + 174)
	for i: int in _actors.keys():
		if i >= first and i < end and not flight.target_gone(i):
			continue
		var actor: Node3D = _actors[i]
		_actors.erase(i)
		_rotors.erase(i)
		if not reset_pose and i >= first and i < end:
			_destroy_target(actor, COURSE.target(i)[0])
		else:
			actor.hide()
			actor.queue_free()
	for i in range(first, end):
		if flight.target_gone(i) or _actors.has(i):
			continue
		var target := flight.target_position(i)
		var kind: String = COURSE.target(i)[0]
		var altitude := 0.0
		if kind == "helicopter":
			altitude = HELICOPTER_ALTITUDE
		elif kind == "jet":
			altitude = ENEMY_JET_ALTITUDE
		var at := _point(target.x, target.y, altitude)
		var template: Node3D = _templates[kind]
		var new_actor := template.duplicate() as Node3D
		new_actor.position = at
		if kind == "jet":
			new_actor.rotation.y = -PI / 2.0
		_scene.add_child(new_actor)
		_actors[i] = new_actor
		if kind == "helicopter":
			_rotors[i] = [new_actor.get_node("Rotor"), new_actor.get_node("TailRotor")]


func _destroy_target(actor: Node3D, kind: String) -> void:
	var at := actor.position + Vector3.UP * 0.58
	var sound_kind: String
	match kind:
		"jet":
			_effects.jet_breakup(at, -actor.basis.z)
			sound_kind = "jet_break"
		"helicopter":
			var rotor := actor.get_node("Rotor") as Node3D
			_effects.helicopter_breakup(at, rotor.rotation.y)
			rotor.hide()
			actor.get_node("TailRotor").hide()
			sound_kind = "rotor_break"
		"tanker":
			_effects.tanker_burst(at, 0.96)
			sound_kind = "tanker_blast"
		"fuel":
			_effects.fuel_barge_blast(at)
			sound_kind = "fuel_blast"
	spatial_effect_requested.emit(sound_kind, _screen_pan(_screen_position(at).x))

	if kind == "tanker" or kind == "helicopter":
		var wreck := TargetWreck.new()
		wreck.actor = actor
		wreck.kind = kind
		wreck.origin = actor.position
		wreck.drift = 2.55 if actor.position.x >= _aircraft.position.x else -2.55
		_target_wrecks.append(wreck)
	else:
		actor.hide()
		actor.queue_free()


func _present_target_wrecks(delta: float) -> void:
	for index in range(_target_wrecks.size() - 1, -1, -1):
		var wreck := _target_wrecks[index]
		wreck.age += delta
		var finished := _sink_tanker(wreck) if wreck.kind == "tanker" else _drop_helicopter(wreck)
		if finished:
			wreck.actor.hide()
			wreck.actor.queue_free()
			_target_wrecks.remove_at(index)


func _sink_tanker(wreck: TargetWreck) -> bool:
	while wreck.stage < TANKER_BURSTS.size() and wreck.age >= TANKER_BURSTS[wreck.stage]:
		var offset := -3.1 if wreck.stage == 0 else 3.25
		var at := wreck.origin + wreck.actor.basis.z * offset + Vector3.UP * 0.65
		_effects.tanker_burst(at, 1.1 if wreck.stage == 0 else 0.74)
		spatial_effect_requested.emit("tanker_secondary", _screen_pan(_screen_position(at).x))
		wreck.stage += 1
	var phase := smoothstep(0.25, 1.25, wreck.age)
	wreck.actor.position.y = wreck.origin.y - 1.5 * phase
	wreck.actor.rotation.z = 0.36 * phase
	return wreck.age >= 1.25


func _drop_helicopter(wreck: TargetWreck) -> bool:
	var phase := clampf(wreck.age / HELICOPTER_FALL, 0.0, 1.0)
	wreck.actor.position = wreck.origin + Vector3(wreck.drift * phase, -wreck.origin.y * phase * phase, 0.85 * phase)
	wreck.actor.rotation.z = 1.35 * phase
	wreck.actor.rotation.y = phase * 2.9
	if phase < 1.0:
		if wreck.age >= wreck.stage * HELICOPTER_SMOKE_INTERVAL:
			_effects.helicopter_smoke(wreck.actor.position + Vector3.UP * 0.32)
			wreck.stage = floori(wreck.age / HELICOPTER_SMOKE_INTERVAL) + 1
		return false

	var at := wreck.actor.position
	var x := at.x / X_SCALE + 8.0
	var distance := _origin_distance - at.z / Z_SCALE
	if COURSE.is_water(floori(distance), floori(x), ceili(x)):
		at.y = 0.04
		_effects.splash(at)
		spatial_effect_requested.emit("debris", _screen_pan(_screen_position(at).x))
	else:
		_effects.helicopter_smoke(at + Vector3.UP * 0.25)
	return true


func present(flight: FLIGHT, fraction: float, delta: float) -> void:
	_clock += delta
	presented_pose = _previous_pose.lerp(_pose, fraction)
	var previous_distance := presented_distance
	# Snap the view to the render texel grid: the static scene then moves by whole texels only.
	presented_distance = roundf((_origin_distance + presented_pose.y) * _texel_rows) / _texel_rows
	var scroll := maxf(0.0, presented_distance - previous_distance) if delta > 0.0 else 0.0
	_camera.position.z = _z(presented_distance + 70.5)
	_present_departing_jets(scroll)
	if _glide_tick >= 0:
		_present_fuel_glide(flight.tick - _glide_tick - 1.0 + fraction)
	else:
		_aircraft.position = _point(presented_pose.x, presented_distance, PLAYER_ALTITUDE)
		_aircraft.rotation.z = lerpf(_aircraft.rotation.z, _bank_angle, 1.0 - exp(-14.0 * delta))
	if _ghost_aircraft:
		_present_ghost(flight, delta)
	if _shot.visible:
		_shot.position = _previous_shot.lerp(_shot_pose, fraction)
		var travel := _shot_pose - _previous_shot
		_shot.rotation.y = atan2(-travel.x, -travel.z) if travel.z < -0.01 else 0.0
	for i: int in _actors:
		var actor: Node3D = _actors[i]
		var item := COURSE.target(i)
		var kind: String = item[0]
		var target := flight.target_position_at(i, presented_distance)
		var display_x := _jet_display_x(item, target.x, presented_distance) if kind == "jet" else target.x
		var new_x := _x(display_x)
		var travel_x := new_x - actor.position.x
		var track_width := JET_TRACK_WIDTH * X_SCALE
		var horizontal_travel := wrapf(travel_x, -track_width * 0.5, track_width * 0.5)
		if kind == "jet" and scroll > 0.0 and absf(travel_x) > track_width * 0.5 and absf(horizontal_travel) > 0.001:
			_depart_jet(actor, new_x + signf(horizontal_travel) * track_width, horizontal_travel / scroll)
		actor.position.x = new_x
		if (kind == "jet" or kind == "tanker") and absf(horizontal_travel) > 0.001:
			actor.rotation.y = -signf(horizontal_travel) * PI / 2.0
		elif kind == "helicopter":
			var rotors: Array = _rotors[i]
			rotors[0].rotation.y = fposmod(_clock * 36.0, TAU)
			rotors[1].rotation.x = fposmod(_clock * 59.0, TAU)
	_present_target_wrecks(delta)
	_present_bridge_pieces(delta)
	_effects.present(delta)


static func _jet_display_x(item: Array, center_x: float, distance: float) -> float:
	if item.size() < 4 or not item[3] is Array:
		return center_x
	var track: Array = item[3]
	if track.size() < 2:
		return center_x
	var endpoint: Vector2 = track[-1]
	var previous: Vector2 = track[-2]
	if distance <= endpoint.x or endpoint.x <= previous.x:
		return center_x
	var displacement := wrapf(endpoint.y - previous.y, -JET_TRACK_WIDTH * 0.5, JET_TRACK_WIDTH * 0.5)
	var edge_x := fposmod(endpoint.y, JET_TRACK_WIDTH)
	# A trace ending on the outgoing left edge can stop before the full silhouette clears it.
	if displacement < 0.0 and edge_x <= 8.0:
		return edge_x + (distance - endpoint.x) * displacement / (endpoint.x - previous.x)
	return center_x


func _depart_jet(actor: Node3D, x: float, drift: float) -> void:
	var position := Vector3(x, actor.position.y, actor.position.z)
	if _jet_clear_of_edge(position, drift):
		return
	var jet := DepartingJet.new()
	jet.actor = actor.duplicate() as Node3D
	jet.actor.position = position
	jet.actor.rotation.y = -signf(drift) * PI / 2.0
	jet.drift = drift
	_scene.add_child(jet.actor)
	_departing_jets.append(jet)


func _present_departing_jets(scroll: float) -> void:
	for index in range(_departing_jets.size() - 1, -1, -1):
		var jet := _departing_jets[index]
		jet.actor.position.x += jet.drift * scroll
		if _jet_clear_of_edge(jet.actor.position, jet.drift):
			jet.actor.queue_free()
			_departing_jets.remove_at(index)


func _jet_clear_of_edge(at: Vector3, drift: float) -> bool:
	at.x -= signf(drift) * JET_MODEL_REACH
	var edge := _camera.unproject_position(at).x
	return edge >= size.x if drift > 0.0 else edge <= 0.0


func _start_fuel_glide(flight: FLIGHT) -> void:
	var last_life := flight.reserves == 0 and not (flight.cheats & FLIGHT.Cheat.LIVES)
	var remaining := FLIGHT.FINAL_CRASH_TICKS if last_life else FLIGHT.RESPAWN_TICKS
	var elapsed := remaining - flight.crash_ticks
	_glide_tick = flight.tick - elapsed
	_glide_start = Vector3(flight.visual_x() + PLAYER_CENTER_X, PLAYER_ALTITUDE, flight.visual_distance())
	_glide_travel = Vector2(flight.visual_lateral_speed() * 17.0, lerpf(24.0, 55.0,
		float(flight.speed - FLIGHT.MIN_SPEED) / (FLIGHT.MAX_SPEED - FLIGHT.MIN_SPEED)))
	_glide_impact_tick = GLIDE_TICKS
	_glide_hit_object = false
	for tick in range(1, GLIDE_TICKS + 1):
		var point := _glide_point(tick)
		if _glide_blocked(point, flight):
			_glide_impact_tick = tick
			_glide_hit_object = true
			break
	_glide_impacted = elapsed >= _glide_impact_tick


func _glide_point(tick: float) -> Vector3:
	var phase := clampf(tick / GLIDE_TICKS, 0.0, 1.0)
	return _glide_start + Vector3(_glide_travel.x * phase * (1.0 - 0.38 * phase),
		(WATER_IMPACT_HEIGHT - PLAYER_ALTITUDE) * phase * phase,
		_glide_travel.y * phase * (1.0 - 0.27 * phase))


func _glide_blocked(point: Vector3, flight: FLIGHT) -> bool:
	var nose := point.z + 4.0
	if not COURSE.is_water(floori(nose), floori(point.x - 1.2), ceili(point.x + 1.2)):
		return true
	var index := flight.section - 1
	if index < COURSE.BRIDGE_COUNT and not flight.is_bridge_destroyed(index):
		var span := COURSE.bridge(index)
		if nose >= span.x and point.z - 4.0 <= span.y:
			return true
	for target in range(COURSE.first_target(point.z - 18.0), COURSE.first_target(point.z + 18.01)):
		if flight.target_gone(target):
			continue
		var kind: String = COURSE.target(target)[0]
		if not GLIDE_OBSTACLE_HEIGHT.has(kind):
			continue
		var height: float = GLIDE_OBSTACLE_HEIGHT[kind]
		if point.y - 0.32 > height or (kind == "helicopter" and point.y < 0.7):
			continue
		var center := flight.target_position_at(target, _glide_start.z)
		var half: Vector2 = FLIGHT.TARGET_SIZE[kind]
		if absf(center.x - point.x) <= half.x + 1.5 and absf(center.y - point.z) <= half.y + 4.0:
			return true
	return false


func _present_fuel_glide(tick: float) -> void:
	if _glide_impacted:
		return
	var point := _glide_point(minf(tick, _glide_impact_tick))
	var at := _point(point.x, point.z, point.y)
	var phase := clampf(tick / GLIDE_TICKS, 0.0, 1.0)
	_aircraft.position = at
	_aircraft.rotation.x = -lerpf(0.0, 0.38, phase)
	_aircraft.rotation.z = lerpf(_bank_angle, _bank_angle * 0.24, phase)
	if tick < _glide_impact_tick:
		return
	_glide_impacted = true
	_aircraft.hide()
	if _glide_hit_object:
		_player_explosion(at)
	else:
		at.y = 0.06
		_effects.player_water_impact(at)
		spatial_effect_requested.emit("water_crash", _screen_pan(_screen_position(at).x))


func _player_explosion(at: Vector3) -> void:
	_effects.player_explosion(at)
	spatial_effect_requested.emit("crash", _screen_pan(_screen_position(at).x))


func _present_ghost(flight: FLIGHT, delta: float) -> void:
	if flight.status != FLIGHT.Status.FLYING:
		_ghost_aircraft.hide()
		return
	var pose := _ghost_raid.ghost_pose(presented_distance, GHOST_STEPS_PER_FRAME if delta > 0.0 else 0)
	if not pose.is_finite():
		_ghost_aircraft.hide()
		return
	var x := pose.x + PLAYER_CENTER_X
	var fade := pose.z * smoothstep(0.75, 7.0, absf(x - presented_pose.x))
	if fade <= 0.0:
		_ghost_aircraft.hide()
		return
	var tint := GHOST_TINT
	tint.a = 0.40 * fade
	_ghost_material.albedo_color = tint
	_ghost_aircraft.position = _point(x, presented_distance, PLAYER_ALTITUDE)
	var bank := _aircraft_bank(pose.y)
	_ghost_aircraft.rotation.z = lerpf(_ghost_aircraft.rotation.z, bank, 1.0 - exp(-14.0 * delta)) \
		if _ghost_aircraft.visible else bank
	_ghost_aircraft.show()


func _aircraft_bank(steering: float) -> float:
	return -MAX_BANK_ANGLE * steering * lerpf(0.6, 1.0, absf(steering))


func player_bank_angle() -> float:
	return _aircraft.rotation.z


func enemy_audio_sources(flight: FLIGHT) -> Dictionary:
	var sources := {}
	for index: int in _actors:
		var kind: String = COURSE.target(index)[0]
		if kind == "fuel" or kind == "helicopter":
			continue
		var actor: Node3D = _actors[index]
		var screen := _screen_position(actor.position)
		var side := absf(screen.x * 2.0 - 1.0)
		var edge_fade := 1.0 - smoothstep(0.88, 1.04, side)
		var vertical_fade := smoothstep(0.01, 0.24, screen.y) * (1.0 - smoothstep(0.90, 1.02, screen.y))
		var proximity := lerpf(0.25, 1.0, smoothstep(0.10, 0.87, screen.y))
		var level := edge_fade * vertical_fade * proximity
		var previous: Vector2 = sources.get(kind, Vector2.ZERO)
		if level > previous.y:
			sources[kind] = Vector2(_screen_pan(screen.x), level)
	var rotor := _rotor_audio_source(flight)
	if rotor.y > 0.0:
		sources["helicopter"] = rotor
	return sources


func _rotor_audio_source(flight: FLIGHT) -> Vector2:
	# Keep listening after the helicopter has scrolled out of the visible fleet.
	var reach := ROTOR_MAX_DISTANCE / Z_SCALE
	var first := COURSE.first_target(presented_distance - reach)
	var end := COURSE.first_target(presented_distance + reach)
	var source := Vector2.ZERO
	for index in range(first, end):
		if COURSE.target(index)[0] != "helicopter" or flight.target_gone(index):
			continue
		var target := flight.target_position_at(index, presented_distance)
		var at := _point(target.x, target.y, HELICOPTER_ALTITUDE)
		var distance := at.distance_to(_aircraft.position)
		var level := 1.0 - smoothstep(ROTOR_FULL_DISTANCE, ROTOR_MAX_DISTANCE, distance)
		if level > source.y:
			source = Vector2(_screen_pan(_screen_position(at).x), level)
	return source


func _player_nose(pose: Vector2) -> Vector3:
	return _point(pose.x, pose.y + _origin_distance, PLAYER_ALTITUDE) + _aircraft_nose


func _screen_position(at: Vector3) -> Vector2:
	var projected := _camera.unproject_position(at)
	projected.x -= (size.x - _playfield_width) * 0.5
	return projected / Vector2(_playfield_width, size.y)


func _screen_pan(normalized_x: float) -> float:
	return clampf(normalized_x * 2.0 - 1.0, -1.0, 1.0)


func _exit_tree() -> void:
	for template: Node3D in _templates.values():
		template.free()
	_templates.clear()
	_bridge_piece_model.free()
	_crossing_model.free()
	for model in _landmark_models:
		model.free()
	_landmark_models.clear()


func reset_effects() -> void:
	for wreck in _target_wrecks:
		wreck.actor.hide()
		wreck.actor.queue_free()
	_target_wrecks.clear()
	for piece in _bridge_pieces:
		piece.actor.hide()
		piece.actor.queue_free()
	_bridge_pieces.clear()
	_glide_tick = -1
	_aircraft.rotation.x = 0.0
	_clock = 0.0
	_was_flying = true
	_last_projectile = -1
	_aircraft.rotation.z = 0.0
	_effect_cursor = 0
	_effects.clear()


func _configure_light() -> void:
	var atmosphere := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#243928")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b9d3ed")
	environment.ambient_light_energy = 0.63
	atmosphere.environment = environment
	_scene.add_child(atmosphere)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-57, -39, 0)
	sun.light_color = Color("#fff0cc")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 112.0
	sun.shadow_bias = 0.065
	_scene.add_child(sun)

	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 161.0 * Z_SCALE
	_camera.position = Vector3(45.6, 65, _z(70.5))
	_camera.rotation_degrees.x = -90.0
	_camera.far = 116.0
	_scene.add_child(_camera)
	_camera.make_current()


func _build_landscape() -> void:
	_scenery.build_shore_map()
	_ground_plane.size = Vector2(152.0 * X_SCALE, 128.0 * Z_SCALE)
	_ground_plane.subdivide_width = 75
	_ground_plane.subdivide_depth = 31
	_build_ground_mesh(0)
	_build_terrain(_intro_scene, _scenery, SCENERY.FIRST_ROW, STREAM_START)
	var clearances := _build_settlements(_intro_scene, _scenery, -120, STREAM_START)
	_build_landmarks(_intro_scene, _scenery, -120, STREAM_START, clearances)
	_scatter_landscape(_intro_scene, _scenery, -120, STREAM_START, clearances)


func _build_terrain(parent: Node3D, scenery: SCENERY, first: int, last: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BANK_SHADER
	material.set_shader_parameter("shore_map", scenery.shore_texture)
	material.set_shader_parameter("region_length", SCENERY.REGION_LENGTH * Z_SCALE)
	material.set_shader_parameter("region_blend", SCENERY.REGION_BLEND * Z_SCALE)
	material.set_shader_parameter("town_weights", SCENERY.TOWN_WEIGHTS)
	material.set_shader_parameter("rock_weights", SCENERY.ROCK_WEIGHTS)
	_terrain_materials[material] = scenery.first_row
	_position_terrain(material, scenery.first_row)
	for distance in range(first, last, 128):
		var patch := MeshInstance3D.new()
		patch.mesh = _ground_mesh
		patch.material_override = material
		patch.position = _point(84, distance + 64, 0)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(patch)
	return material


func _position_terrain(material: ShaderMaterial, first_row: int) -> void:
	material.set_shader_parameter("shore_origin", Vector2(0, _z(first_row)))
	material.set_shader_parameter("course_offset", -_origin_distance * Z_SCALE)


func _rebase(distance: int) -> void:
	var origin := 0 if distance < STREAM_START else distance / ORIGIN_STEP * ORIGIN_STEP
	if origin == _origin_distance:
		return
	var delta := origin - _origin_distance
	_origin_distance = origin
	var shift := delta * Z_SCALE
	for child in _scene.get_children():
		if child is Node3D and child != _intro_scene and child != _effects:
			child.position.z += shift
	_effects.shift_origin(shift)
	for wreck in _target_wrecks:
		wreck.origin.z += shift
	for piece in _bridge_pieces:
		piece.origin.z += shift
	_intro_scene.position.z = origin * Z_SCALE
	_previous_pose.y -= delta
	_pose.y -= delta
	_previous_shot.z += shift
	_shot_pose.z += shift
	for material: ShaderMaterial in _terrain_materials:
		_position_terrain(material, _terrain_materials[material])


func _sync_tiles(distance: int) -> void:
	# The intro scenery ends where streaming starts; drop it with the same margin as old tiles.
	_intro_scene.visible = distance - 96 < STREAM_START
	var first := maxi(0, floori((distance - 96 - STREAM_START) / float(TILE_LENGTH)))
	var last := floori((distance + 300 - STREAM_START) / float(TILE_LENGTH))
	for index: int in _tiles.keys():
		if index >= first and index <= last:
			continue
		var tile: Dictionary = _tiles[index]
		_terrain_materials.erase(tile.material)
		tile.node.hide()
		tile.node.queue_free()
		_tiles.erase(index)
	for index in range(first, last + 1):
		if _tiles.has(index):
			continue
		var start := STREAM_START + index * TILE_LENGTH
		var end := start + TILE_LENGTH
		var tile := Node3D.new()
		_scene.add_child(tile)
		var scenery := SCENERY.new()
		scenery.build_shore_map(start - 8, end + 8)
		var material := _build_terrain(tile, scenery, start, end)
		var clearances := _build_settlements(tile, scenery, start, end)
		_build_landmarks(tile, scenery, start, end, clearances)
		_scatter_landscape(tile, scenery, start, end, clearances)
		_update_outer_scenery(tile, start, end)
		_tiles[index] = {"node": tile, "material": material}


func _build_ground_mesh(extra_columns: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(_ground_plane, 0, Transform3D.IDENTITY)
	if extra_columns > 0:
		var strip := PlaneMesh.new()
		strip.subdivide_depth = _ground_plane.subdivide_depth
		var edge := _ground_plane.size.x * 0.5
		var transition := 6.0 * X_SCALE
		var far_width := extra_columns * X_SCALE - transition
		# Keep the original 1.2 m spacing where the shore height can vary.
		strip.size = Vector2(transition, _ground_plane.size.y)
		strip.subdivide_width = 2
		for side: float in [-1.0, 1.0]:
			var x := side * (edge + transition * 0.5)
			surface.append_from(strip, 0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
		# The outer ground is flat across x, so one quad per depth row is enough.
		strip.size.x = far_width
		strip.subdivide_width = 0
		for side: float in [-1.0, 1.0]:
			var x := side * (edge + transition + far_width * 0.5)
			surface.append_from(strip, 0, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
	_ground_mesh.clear_surfaces()
	surface.commit(_ground_mesh)


func set_panorama(aspect_scale: float) -> void:
	var bands := ceili((aspect_scale - 1.0) * 76.0 / OUTER_BAND_WIDTH)
	if bands == _outer_bands:
		return
	_outer_bands = bands
	_build_ground_mesh(bands * OUTER_BAND_WIDTH)
	_update_outer_scenery(_intro_scene, -120, STREAM_START)
	_update_outer_roads(_intro_scene, -7, 14)
	for index: int in _crossings:
		var limits := COURSE.bridge(index)
		_update_outer_roads(_crossings[index], limits.x, limits.y)
	for index: int in _tiles:
		var start := STREAM_START + index * TILE_LENGTH
		_update_outer_scenery(_tiles[index].node, start, start + TILE_LENGTH)


func _update_outer_scenery(parent: Node3D, first: int, last: int) -> void:
	var outer := parent.get_node_or_null("Panorama") as Node3D
	if outer == null:
		if _outer_bands == 0:
			return
		outer = Node3D.new()
		outer.name = "Panorama"
		parent.add_child(outer)
	outer.visible = _outer_bands > 0
	for band in range(outer.get_child_count(), _outer_bands):
		var group := Node3D.new()
		outer.add_child(group)
		_scatter_outer_band(group, first, last, band, parent.position)


func _scatter_outer_band(parent: Node3D, first: int, last: int, band: int, offset: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 27481 + first * 31 + band * 6151
	var woods := FastNoiseLite.new()
	woods.seed = 7628
	woods.frequency = 0.043
	var trees: Array = []
	var leaves: Array = []
	var hills: Array = []
	var stones: Array = []
	var cabins: Array = []
	var walls: Array = []
	for row in range(first + 8, last, 16):
		for side in [-1.0, 1.0]:
			for column in range(6, OUTER_BAND_WIDTH, 9):
				var x: float = 84.0 + side * (76.0 + band * OUTER_BAND_WIDTH + column + rng.randf_range(-2.0, 2.0))
				var distance := float(row) + rng.randf_range(-5.0, 5.0)
				if _on_road(distance):
					continue
				var ground := _point(x, distance, 0.26) - offset
				var pattern := woods.get_noise_2d(x, distance * 0.5)
				var choice := rng.randf()
				if choice < 0.015:
					cabins.append(_transform(ground, Vector3.ONE, side * 0.08))
					walls.append(Color.WHITE.darkened(0.12))
				elif choice < 0.075 and pattern > 0.0:
					var span := rng.randf_range(2.2, 4.4)
					hills.append(_transform(ground, Vector3(span, span * 0.72, span), rng.randf() * TAU))
					stones.append(Color("#64705e"))
				elif choice < 0.48 + pattern * 0.65:
					var scale := rng.randf_range(0.72, 1.34)
					trees.append(_transform(ground, Vector3.ONE * scale, rng.randf() * TAU))
					leaves.append(Color.WHITE.darkened(rng.randf_range(0.0, 0.17)))
	_scatter_batch(parent, trees, leaves, _scenery.tree(0), _canopy_material, false)
	var matte := _scatter_material(0.9)
	_scatter_batch(parent, hills, stones, _scenery.ridge(), matte, false)
	_scatter_batch(parent, cabins, walls, _scenery.building(0), matte, false)


func _build_settlements(parent: Node3D, scenery: SCENERY, first: int, last: int) -> Array[Rect2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73109 if first < STREAM_START else 73109 + first
	var clearances: Array[Rect2] = []
	var positions := [[], [], []]
	var colors := [[], [], []]
	var first_origin := COURSE.bridge(0).y + 64.0
	var first_district := maxi(-1, floori((first - first_origin - 55.0) / COURSE.SECTION_LENGTH))
	var last_district := mini(COURSE.BRIDGE_COUNT - 1, floori((last - first_origin + 3.0) / COURSE.SECTION_LENGTH))
	for district in range(first_district, last_district + 1):
		var origin: float = 160.0 if district < 0 else COURSE.bridge(district).y + 64.0
		if origin + 55.0 < first:
			continue
		for side in [-1.0, 1.0]:
			for row in range(3):
				for column in range(3):
					if rng.randf() < 0.18:
						continue
					var x := (29.0 if side < 0 else 131.0) + (column - 1) * 11.0 + rng.randf_range(-1.5, 1.5)
					var distance: float = origin + row * 26.0 + rng.randf_range(-3.0, 3.0)
					if distance < first or distance >= last:
						continue
					var dry := true
					for offset in [Vector2.ZERO, Vector2(-4, -10), Vector2(4, -10), Vector2(-4, 10), Vector2(4, 10)]:
						if scenery.shore_distance(x + offset.x, distance + offset.y) < 1.4:
							dry = false
							break
					if not dry or _on_road(distance):
						continue
					var kind := rng.randi_range(0, 3)
					kind = 0 if kind == 3 else kind
					positions[kind].append(_transform(_point(x, distance, 0.26), Vector3.ONE, rng.randf_range(-0.18, 0.18)))
					colors[kind].append(Color.WHITE.darkened(rng.randf_range(0.0, 0.14)))
					clearances.append(Rect2(Vector2(x - 6, distance - 13), Vector2(12, 26)))
	var material := _scatter_material(0.88)
	for kind in range(3):
		_scatter_batch(parent, positions[kind], colors[kind], _scenery.building(kind), material)
	return clearances


func _scatter_landscape(parent: Node3D, scenery: SCENERY, first: int, last: int,
		clearances: Array[Rect2]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60517 if first < STREAM_START else 60517 + first
	var trees := [[], [], []]
	var leaf_colors := [[], [], []]
	var shrubs: Array = []
	var shrub_colors: Array = []
	var rocks: Array = []
	var stone_colors: Array = []
	var ridges: Array = []
	var ridge_colors: Array = []
	var woodline := FastNoiseLite.new()
	woodline.seed = 7628
	woodline.frequency = 0.043
	for distance in range(first, last, 14):
		for column in range(12, 158, 7):
			var x := column + rng.randf_range(-2.6, 2.6)
			var z := distance + rng.randf_range(-5.0, 5.0)
			if (first >= STREAM_START and z < first) or z >= last or _on_road(z) or _inside_settlement(x, z, clearances):
				continue
			var shore := scenery.shore_distance(x, z)
			if shore < 0.35:
				continue
			if shore < 3.3:
				if rng.randf() < 0.48:
					var radius := rng.randf_range(0.28, 1.05)
					rocks.append(_transform(_point(x, z, 0.19 + radius * 0.25),
						Vector3(radius, radius * 0.70, radius), rng.randf() * TAU))
					stone_colors.append(Color("#a49e89").lerp(Color("#66716c"), rng.randf()))
				elif shore > 1.4:
					shrubs.append(_transform(_point(x, z, 0.26), Vector3.ONE * rng.randf_range(0.65, 1.25), rng.randf() * TAU))
					shrub_colors.append(Color.WHITE.darkened(rng.randf_range(0.0, 0.2)))
				continue
			var region := SCENERY.region_weights(z)
			var town := region.x
			var rocky := region.y
			var pattern := woodline.get_noise_2d(x, z * 0.5)
			if rocky > 0.12 and shore > 5.4 and pattern > 0.22 - rocky * 0.32 \
					and rng.randf() < 0.62 and _landmark_site_clear(scenery,
					Rect2(x - 5.5, z - 11.0, 11.0, 22.0), clearances):
				var span := rng.randf_range(2.0, 5.3) * lerpf(0.30, 1.0, rocky)
				var height := rng.randf_range(1.4, 4.5) * rocky
				ridges.append(_transform(_point(x, z, 0.22), Vector3(span, height, span * 1.25),
					rng.randf() * TAU))
				ridge_colors.append(Color("#535750").lerp(Color("#776c58"), rng.randf()))
				continue
			var density := clampf(0.32 + pattern * 0.8, 0.10, 0.68) * (1.0 - town * 0.26 - rocky * 0.17)
			if rng.randf() > density:
				if rng.randf() < 0.10:
					shrubs.append(_transform(_point(x, z, 0.26), Vector3.ONE * rng.randf_range(0.6, 1.1), rng.randf() * TAU))
					shrub_colors.append(Color.WHITE.darkened(rng.randf_range(0.0, 0.2)))
				continue
			var kind := rng.randi_range(0, 9)
			kind = 0 if kind < 4 else (1 if kind < 7 else 2)
			var scale := rng.randf_range(0.68, 1.30)
			var dimensions := Vector3(scale, scale * rng.randf_range(0.82, 1.29), scale)
			trees[kind].append(_transform(_point(x, z, 0.26), dimensions, rng.randf() * TAU))
			leaf_colors[kind].append(Color(rng.randf_range(0.86, 1.08), rng.randf_range(0.91, 1.07), rng.randf_range(0.82, 1.03)))
	for kind in range(3):
		_scatter_batch(parent, trees[kind], leaf_colors[kind], _scenery.tree(kind), _canopy_material)
	_scatter_batch(parent, shrubs, shrub_colors, _scenery.shrub(), _canopy_material, false)
	var stone := _scatter_material(0.94)
	_scatter_batch(parent, rocks, stone_colors, _rock_mesh, stone)
	if not ridges.is_empty():
		_scatter_batch(parent, ridges, ridge_colors, _scenery.ridge(), stone)


# Scattered scenery only varies by roughness, so every tile shares the same materials.
func _scatter_material(roughness: float) -> StandardMaterial3D:
	if not _scatter_materials.has(roughness):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = roughness
		_scatter_materials[roughness] = material
	return _scatter_materials[roughness]


func _build_landmarks(parent: Node3D, scenery: SCENERY, first: int, last: int,
		clearances: Array[Rect2]) -> void:
	var first_block := maxi(1, floori(float(first) / SCENERY.REGION_LENGTH))
	var last_block := floori(float(last - 1) / SCENERY.REGION_LENGTH)
	if _landmark_models.is_empty():
		# Each landmark kind is built once, then duplicated with its shared meshes.
		_landmark_models = [_models.launcher_truck(), _models.launch_platform(), _models.moored_airship()]
	var footprints := [Vector2(5.0, 11.0), Vector2(7.0, 14.0), Vector2(6.0, 17.0)]
	for block in range(first_block, last_block + 1):
		var kind := block % 4 - 1
		# A quiet block between each set of three landmarks.
		var preferred := block * SCENERY.REGION_LENGTH + 260
		if kind < 0 or preferred < first or preferred >= last:
			continue
		var columns := [18.0, 26.0, 36.0, 145.0, 136.0, 125.0]
		if (block + block / 4) % 2 != 0:
			columns.reverse()
		columns.append_array([56.0, 104.0, 80.0])
		_place_landmark(parent, scenery, clearances, preferred, last, columns,
			footprints[kind], _landmark_models[kind])


func _place_landmark(parent: Node3D, scenery: SCENERY, clearances: Array[Rect2],
		preferred: int, last: int, columns: Array, footprint: Vector2, model: Node3D) -> void:
	# The sector that contains the preferred point owns the whole search.
	for offset in [0, 42, 84, 126, 168, 210, 252, 294]:
		var distance := float(preferred + offset)
		if distance + footprint.y >= last:
			break
		for x: float in columns:
			var site := Rect2(Vector2(x, distance) - footprint, footprint * 2.0)
			if not _landmark_site_clear(scenery, site, clearances):
				continue
			var landmark := model.duplicate() as Node3D
			landmark.position = _point(x, distance, 0.26)
			parent.add_child(landmark)
			clearances.append(site)
			return


func _landmark_site_clear(scenery: SCENERY, site: Rect2, clearances: Array[Rect2]) -> bool:
	for reserved in clearances:
		if site.intersects(reserved):
			return false
	for distance in [site.position.y, site.get_center().y, site.end.y]:
		if _on_road(distance):
			return false
		for x in [site.position.x, site.get_center().x, site.end.x]:
			if scenery.shore_distance(x, distance) < 2.2:
				return false
	return true


func _on_road(distance: float) -> bool:
	return absf(distance - 3.0) < 19.0 or absf(fposmod(distance - 1030.0 + 512.0, 1024.0) - 512.0) < 20.0


func _inside_settlement(x: float, distance: float, clearances: Array[Rect2]) -> bool:
	var point := Vector2(x, distance)
	for rectangle in clearances:
		if rectangle.has_point(point):
			return true
	return false


func _scatter_batch(parent: Node3D, transforms: Array, colors: Array, mesh: Mesh,
		material: Material, shadow: bool = true) -> void:
	var sections := {}
	for i in transforms.size():
		var section := floori(transforms[i].origin.z / 48.0)
		if not sections.has(section):
			sections[section] = []
		sections[section].append(i)
	for indices: Array in sections.values():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = mesh
		batch.instance_count = indices.size()
		for i in indices.size():
			batch.set_instance_transform(i, transforms[indices[i]])
			batch.set_instance_color(i, colors[indices[i]])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)

func _transform(at: Vector3, dimensions: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(dimensions), at)


func _build_crossings() -> void:
	_road(-7, 14, 8, 64, _intro_scene)
	_road(-7, 14, 96, 160, _intro_scene)


func _sync_crossings(flight: FLIGHT) -> void:
	var distance := flight.distance
	var first := maxi(0, ceili((distance - 60 - 1030) / float(COURSE.SECTION_LENGTH)))
	var last := mini(COURSE.BRIDGE_COUNT - 1, floori((distance + 260 - 1030) / float(COURSE.SECTION_LENGTH)))
	for index: int in _crossings.keys():
		if index >= first and index <= last:
			continue
		_crossings[index].hide()
		_crossings[index].queue_free()
		_crossings.erase(index)
		_decks.erase(index)
	for index in range(first, last + 1):
		var limits := COURSE.bridge(index)
		if not _crossings.has(index):
			var crossing := _crossing_model.duplicate() as Node3D
			crossing.position.z = _z(limits.x)
			_scene.add_child(crossing)
			_crossings[index] = crossing
			_update_outer_roads(crossing, limits.x, limits.y)
			_decks[index] = crossing.get_node("Deck")
		var center := float(limits.x + limits.y) * 0.5
		_crossings[index].visible = center >= distance - 40 and center <= distance + 190
		_decks[index].visible = not flight.is_bridge_destroyed(index)


# Every bridge has the same span, so its roads, abutments and deck are built once.
# Built from _ready() while the origin is still 0: the model starts at distance 0.
func _make_crossing_model() -> Node3D:
	var crossing := Node3D.new()
	var limits := Vector2i(0, COURSE.bridge(0).y - COURSE.bridge(0).x)
	_road(limits.x, limits.y, 8, 64, crossing)
	_road(limits.x, limits.y, 96, 160, crossing)
	_bridge_abutments(crossing, limits)
	_models.batch_by_material(crossing)
	var deck := Node3D.new()
	deck.name = "Deck"
	_bridge_span(deck, limits)
	crossing.add_child(deck)
	return crossing


func _update_outer_roads(parent: Node3D, from: int, to: int) -> void:
	var roads := parent.get_node_or_null("PanoramaRoads") as Node3D
	if roads:
		if _outer_bands == 0:
			roads.hide()
			return
		if int(roads.get_meta("bands")) >= _outer_bands:
			roads.show()
			return
		parent.remove_child(roads)
		roads.queue_free()
	if _outer_bands == 0:
		return
	roads = Node3D.new()
	roads.name = "PanoramaRoads"
	roads.set_meta("bands", _outer_bands)
	roads.position = -parent.position
	var length := _outer_bands * OUTER_BAND_WIDTH
	_road(from, to, 8 - length, 8, roads)
	_road(from, to, 160, 160 + length, roads)
	_models.batch_by_material(roads)
	for mesh: MeshInstance3D in roads.get_children():
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(roads)


func _road(from: int, to: int, left: int, right: int, parent: Node3D) -> void:
	var mid := float(from + to) * 0.5
	var x := float(left + right) * 0.5
	var width := (right - left) * X_SCALE
	var length := (to - from) * Z_SCALE
	var asphalt := _models.paint(Color("#555854"), 0.91)
	var concrete := _models.paint(Color("#929387"), 0.86)
	var stripe := _models.paint(Color("#cebd8d"), 0.80)
	_models.box(parent, _point(x, mid, 0.52), Vector3(width, 0.48, length), concrete)
	_models.box(parent, _point(x, mid, 0.80), Vector3(width, 0.10, length - 0.40), asphalt)
	for distance in [from + 1.3, to - 1.3]:
		_models.box(parent, _point(x, distance, 0.86), Vector3(width, 0.08, 0.08), stripe)
	for column in range(left + 2, right - 1, 5):
		_models.box(parent, _point(column, mid, 0.857), Vector3(1.22, 0.018, 0.09), stripe)


func _bridge_abutments(parent: Node3D, limits: Vector2i) -> void:
	var middle := (limits.x + limits.y) * 0.5
	var depth := (limits.y - limits.x) * Z_SCALE
	var stone := _models.paint(Color("#74796e"), 0.92)
	var cap := _models.paint(Color("#a7a492"), 0.86)
	var marker := _models.paint(Color("#b49254"), 0.79)
	for x in [62.75, 97.25]:
		_models.box(parent, _point(x, middle, 0.28), Vector3(1.5, 0.66, depth + 0.88), stone)
		for distance in [limits.x + 0.55, limits.y - 0.55]:
			_models.box(parent, _point(x, distance, 0.89), Vector3(1.50, 0.24, 0.34), cap)
			_models.box(parent, _point(x, distance, 1.04), Vector3(0.50, 0.10, 0.29), marker)


func _bridge_span(deck: Node3D, limits: Vector2i) -> void:
	_road(limits.x, limits.y, 64, 96, deck)
	var width := 32.0 * X_SCALE
	var panel := width / 6.0
	var iron := _models.paint(Color("#4d6866"), 0.56, 0.31)
	var brace := _models.paint(Color("#6d8179"), 0.63, 0.27)
	var plate := _models.paint(Color("#86968d"), 0.64, 0.24)
	var seam := _models.paint(Color("#383d39"), 0.87)
	var depth := (limits.y - limits.x) * Z_SCALE
	for distance in [limits.x + 1.3, limits.y - 1.3]:
		_models.box(deck, _point(80, distance, 0.72), Vector3(width, 0.22, 0.21), iron)
		_models.box(deck, _point(80, distance, 2.18), Vector3(width, 0.17, 0.23), iron)
		for bay in range(7):
			var x := 64.0 + (96.0 - 64.0) * float(bay) / 6.0
			_models.box(deck, _point(x, distance, 1.44), Vector3(0.22, 1.52, 0.24), iron)
			for height in [0.82, 2.16]:
				_models.box(deck, _point(x, distance, height), Vector3(0.38, 0.19, 0.34), plate)
			if bay < 6:
				var center := x + panel * 0.5 / X_SCALE
				var diagonal := _models.box(deck, _point(center, distance, 1.44),
					Vector3(Vector2(panel, 1.44).length(), 0.16, 0.19), brace)
				diagonal.rotation.z = atan2(1.44, panel) * (1.0 if bay % 2 == 0 else -1.0)
	for x in [69.33, 74.67, 80.0, 85.33, 90.67]:
		var at := _point(x, (limits.x + limits.y) * 0.5, 0.852)
		_models.box(deck, at, Vector3(0.075, 0.015, depth - 0.45), seam)
	_models.batch_by_material(deck)


func _make_bridge_piece_model() -> Node3D:
	var piece := Node3D.new()
	var span := COURSE.bridge(0)
	var depth := (span.y - span.x) * Z_SCALE
	var asphalt := _models.paint(Color("#555854"), 0.91)
	var concrete := _models.paint(Color("#929387"), 0.86)
	var stripe := _models.paint(Color("#cebd8d"), 0.80)
	var iron := _models.paint(Color("#4d6866"), 0.56, 0.31)
	var brace := _models.paint(Color("#6d8179"), 0.63, 0.27)
	_models.box(piece, Vector3.ZERO, Vector3(1, 0.48, depth), concrete)
	_models.box(piece, Vector3(0, 0.28, 0), Vector3(1, 0.10, depth - 0.40), asphalt)
	_models.box(piece, Vector3(0, 0.337, 0), Vector3(0.38, 0.018, 0.09), stripe)
	for z in [-depth * 0.5 + 0.39, depth * 0.5 - 0.39]:
		_models.box(piece, Vector3(0, 0.20, z), Vector3(1, 0.22, 0.21), iron)
		_models.box(piece, Vector3(0, 1.66, z), Vector3(1, 0.17, 0.23), iron)
		var diagonal := _models.box(piece, Vector3(0, 0.92, z), Vector3(1.65, 0.14, 0.19), brace)
		diagonal.rotation.z = atan2(1.40, 0.83)
		for x in [-0.44, 0.44]:
			_models.box(piece, Vector3(x, 0.92, z), Vector3(0.064, 1.48, 0.20), iron)
	_models.batch_by_material(piece)
	return piece


func _break_bridge(index: int, impact: Vector2) -> void:
	var span := COURSE.bridge(index)
	var hit_x := clampf(impact.x - SHOT_RENDER_X_CORRECTION, BRIDGE_LEFT, BRIDGE_RIGHT)
	var hit := _point(hit_x, impact.y, BRIDGE_DECK_HEIGHT + 0.45)
	_effects.bridge_hit(hit)
	spatial_effect_requested.emit("bridge", _screen_pan(_screen_position(hit).x))
	var center := float(span.x + span.y) * 0.5
	var half_depth := (span.y - span.x) * Z_SCALE * 0.5
	for side: float in [-1.0, 1.0]:
		var end := BRIDGE_LEFT if side < 0 else BRIDGE_RIGHT
		var length := absf(end - hit_x)
		if length < 0.12:
			continue
		var count := ceili(length / BRIDGE_BAY_WIDTH)
		var bay := length / count
		for ordinal in count:
			var x := hit_x + side * bay * (ordinal + 0.5)
			var piece := BridgePiece.new()
			piece.actor = _bridge_piece_model.duplicate() as Node3D
			piece.origin = _point(x, center, BRIDGE_DECK_HEIGHT)
			piece.width = bay * X_SCALE
			piece.half_depth = half_depth
			piece.side = side
			piece.age = -0.021 * bay * ordinal - (0.045 if side > 0 else 0.0)
			piece.actor.position = piece.origin
			piece.actor.scale.x = maxf(0.035, piece.width - 0.035)
			_scene.add_child(piece.actor)
			_bridge_pieces.append(piece)


func _present_bridge_pieces(delta: float) -> void:
	for index in range(_bridge_pieces.size() - 1, -1, -1):
		var piece := _bridge_pieces[index]
		piece.age += delta
		if piece.age <= 0.0:
			continue
		if not piece.joint:
			piece.joint = true
			_effects.bridge_joint_break(piece.origin + Vector3(-piece.side * piece.width * 0.48, 0.31, 0))
		var t := piece.age
		var tilt := smoothstep(0.0, 0.69, t)
		piece.actor.position = piece.origin + Vector3(piece.side * 0.62 * t,
			0.23 * sin(PI * minf(t / 0.32, 1.0)) - 3.35 * t * t, 0.62 * t)
		piece.actor.rotation.z = piece.side * 1.34 * tilt
		piece.actor.rotation.x = piece.side * 0.28 * tilt
		if not piece.splashed:
			_check_bridge_piece_water(piece)
		if t >= 1.12:
			piece.actor.hide()
			piece.actor.queue_free()
			_bridge_pieces.remove_at(index)


func _check_bridge_piece_water(piece: BridgePiece) -> void:
	var edge_x := -piece.side * 0.5
	var edge_z := piece.side * piece.half_depth
	var contact := piece.actor.transform * Vector3(edge_x, -0.24, edge_z)
	if contact.y > BRIDGE_WATER_HEIGHT:
		return
	piece.splashed = true
	var x := contact.x / X_SCALE + 8.0
	var distance := _origin_distance - contact.z / Z_SCALE
	if not COURSE.is_water(floori(distance), floori(x), ceili(x)):
		return
	contact.y = BRIDGE_WATER_HEIGHT
	_effects.bridge_piece_splash(contact, clampf(piece.width / (BRIDGE_BAY_WIDTH * X_SCALE), 0.0, 1.0))
	spatial_effect_requested.emit("debris", _screen_pan(_screen_position(contact).x))


func _x(value: float) -> float:
	return (value - 8.0) * X_SCALE


func _z(value: float) -> float:
	return -(value - _origin_distance) * Z_SCALE


func _point(x: float, distance: float, height: float) -> Vector3:
	return Vector3(_x(x), height, _z(distance))
