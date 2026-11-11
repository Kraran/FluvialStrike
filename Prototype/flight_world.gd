extends SubViewport

signal spatial_effect_requested(kind: String, pan: float)

const COURSE = preload("res://course.gd")
const FLIGHT = preload("res://flight.gd")
const MODELS = preload("res://flight_models.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
const BANK_SHADER = preload("res://bank.gdshader")
const CANOPY_SHADER = preload("res://canopy.gdshader")
const SCENERY = preload("res://scenery.gd")
const EFFECTS = preload("res://flight_effects.gd")
const X_SCALE := 0.6
const Z_SCALE := 0.3
const PLAYER_CENTER_X := 4.0
const PLAYER_ALTITUDE := 2.30
const SHOT_RENDER_X_CORRECTION := FLIGHT.NATIVE_SHOT_X_OFFSET - PLAYER_CENTER_X
# Render the MiG-29 above the tallest scaled tree, including canopy movement.
const ENEMY_JET_ALTITUDE := 6.6
const HELICOPTER_ALTITUDE := 1.38
const ROTOR_FULL_DISTANCE := 5.0
const ROTOR_MAX_DISTANCE := 29.0
const STREAM_START := 9408
const TILE_LENGTH := 512
const ORIGIN_STEP := 4096
const MAX_BANK_ANGLE := PI * 50.0 / 180.0

var _scene := Node3D.new()
var _intro_scene: Node3D
var _camera := Camera3D.new()
var _models := MODELS.new()
var _aircraft: Node3D
var _aircraft_id := AIRCRAFT.DEFAULT
var _aircraft_nose := MODELS.STRATOWING_NOSE
var _aircraft_tip: Vector2 = AIRCRAFT.AIRCRAFT[AIRCRAFT.DEFAULT].tip
var _shot: Node3D
var _effects: EFFECTS
var _effect_cursor := 0
var _crossings := {}
var _decks := {}
var _actors := {}
var _templates := {}
var _previous_section := 1
var _was_flying := true
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
var _ground_mesh := PlaneMesh.new()
var _origin_distance := 0
var presented_distance := 0.0
var _sun: DirectionalLight3D


func _ready() -> void:
	set_quality(1368, true)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_scene)
	_intro_scene = Node3D.new()
	_scene.add_child(_intro_scene)
	_configure_light()
	_build_landscape()
	_build_crossings()
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


func set_quality(width: int, antialias: bool) -> void:
	size = Vector2i(width, roundi(width * 483.0 / 912.0))
	msaa_3d = Viewport.MSAA_2X if antialias else Viewport.MSAA_DISABLED
	if _sun:
		_sun.shadow_enabled = width > 608


func sync(flight: FLIGHT, reset_pose: bool = false) -> void:
	_rebase(flight.distance)
	_sync_tiles(flight.distance)
	_previous_pose = _pose
	_pose = Vector2(flight.visual_x() + PLAYER_CENTER_X, flight.visual_distance() - _origin_distance)
	var jumped := reset_pose or absf(_pose.y - _previous_pose.y) > 2.01
	if jumped:
		_previous_pose = _pose
	var steering := flight.visual_lateral_speed()
	_bank_angle = -MAX_BANK_ANGLE * steering * lerpf(0.6, 1.0, absf(steering))
	var running := flight.status == FLIGHT.Status.FLYING or flight.status == FLIGHT.Status.COMPLETE
	_aircraft.visible = running
	if not jumped and flight.status == FLIGHT.Status.FLYING:
		var throttle := float(flight.speed - FLIGHT.MIN_SPEED) / (FLIGHT.MAX_SPEED - FLIGHT.MIN_SPEED)
		var at := _point(_previous_pose.x, _previous_pose.y + _origin_distance, 2.30)
		_effects.wingtip_vapor(at, _aircraft.rotation.z, throttle, _aircraft_tip)
	if _was_flying and flight.status == FLIGHT.Status.CRASHED:
		var crash := _point(_pose.x, _pose.y + _origin_distance, 2.30)
		_effects.impact(crash, 1.1)
		spatial_effect_requested.emit("crash", _screen_pan(_screen_position(crash).x))
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
	if not reset_pose and flight.section > _previous_section and flight.is_bridge_destroyed(flight.section - 2):
		var bridge := COURSE.bridge(flight.section - 2)
		var at := _point(80, float(bridge.x + bridge.y) * 0.5, 0.62)
		_effects.bridge(at)
		spatial_effect_requested.emit("bridge", _screen_pan(_screen_position(at).x))
	_previous_section = flight.section
	_sync_fleet(flight)
	if jumped:
		present(flight, 1.0, 0.0)


func _sync_shot_effects(flight: FLIGHT, reset_pose: bool) -> void:
	if not reset_pose:
		for index in range(_effect_cursor, flight.events.size()):
			if flight.events[index].kind == "fire":
				_effects.muzzle(_player_nose(_pose))
		var miss := flight.missed_shot
		var splash_x := miss.x - SHOT_RENDER_X_CORRECTION
		if miss.is_finite() and COURSE.is_water(floori(miss.y), floori(splash_x), ceili(splash_x) + 1):
			var at := _point(splash_x, miss.y, 0.036)
			_effects.splash(at)
			spatial_effect_requested.emit("splash", _screen_pan(_screen_position(at).x))
	_effect_cursor = flight.events.size()


func _sync_fleet(flight: FLIGHT) -> void:
	var first := COURSE.first_target(flight.distance - 25)
	var end := COURSE.first_target(flight.distance + 174)
	for i: int in _actors.keys():
		if i >= first and i < end and not flight.target_gone(i):
			continue
		var actor: Node3D = _actors[i]
		if i >= first and i < end:
			var kind: String = COURSE.target(i)[0]
			var at := actor.position + Vector3.UP * 0.55
			_effects.impact(at, 0.68 if kind == "helicopter" else 1.0)
			spatial_effect_requested.emit("hit", _screen_pan(_screen_position(at).x))
		actor.hide()
		actor.queue_free()
		_actors.erase(i)
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


func present(flight: FLIGHT, fraction: float, delta: float) -> void:
	_clock += delta
	presented_pose = _previous_pose.lerp(_pose, fraction)
	presented_distance = _origin_distance + presented_pose.y
	_camera.position.z = _z(presented_distance + 70.5)
	_aircraft.position = _point(presented_pose.x, presented_distance, PLAYER_ALTITUDE)
	_aircraft.rotation.z = lerpf(_aircraft.rotation.z, _bank_angle, 1.0 - exp(-14.0 * delta))
	if _shot.visible:
		_shot.position = _previous_shot.lerp(_shot_pose, fraction)
		var travel := _shot_pose - _previous_shot
		_shot.rotation.y = atan2(-travel.x, -travel.z) if travel.z < -0.01 else 0.0
	for i: int in _actors:
		var actor: Node3D = _actors[i]
		var kind: String = COURSE.target(i)[0]
		var target := flight.target_position_at(i, presented_distance)
		var horizontal_travel := wrapf(_x(target.x) - actor.position.x, -48.0, 48.0)
		actor.position.x = _x(target.x)
		if (kind == "jet" or kind == "tanker") and absf(horizontal_travel) > 0.001:
			actor.rotation.y = -signf(horizontal_travel) * PI / 2.0
		elif kind == "helicopter":
			actor.get_node("Rotor").rotation.y = fposmod(_clock * 36.0, TAU)
			actor.get_node("TailRotor").rotation.x = fposmod(_clock * 59.0, TAU)
	var splash := _effects.present(delta)
	if splash.is_finite():
		spatial_effect_requested.emit("debris", _screen_pan(_screen_position(splash).x))


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
	return _camera.unproject_position(at) / Vector2(size)


func _screen_pan(normalized_x: float) -> float:
	return clampf(normalized_x * 2.0 - 1.0, -1.0, 1.0)


func _exit_tree() -> void:
	for template: Node3D in _templates.values():
		template.free()
	_templates.clear()


func reset_effects() -> void:
	_clock = 0.0
	_previous_section = 1
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
	_ground_mesh.size = Vector2(152.0 * X_SCALE, 128.0 * Z_SCALE)
	_ground_mesh.subdivide_width = 75
	_ground_mesh.subdivide_depth = 31
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
	_intro_scene.position.z = origin * Z_SCALE
	_previous_pose.y -= delta
	_pose.y -= delta
	_previous_shot.z += shift
	_shot_pose.z += shift
	for material: ShaderMaterial in _terrain_materials:
		_position_terrain(material, _terrain_materials[material])


func _sync_tiles(distance: int) -> void:
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
		_tiles[index] = {"node": tile, "material": material}


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
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
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
	var canopy := ShaderMaterial.new()
	canopy.shader = CANOPY_SHADER
	for kind in range(3):
		_scatter_batch(parent, trees[kind], leaf_colors[kind], _scenery.tree(kind), canopy)
	_scatter_batch(parent, shrubs, shrub_colors, _scenery.shrub(), canopy, false)
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 0.94
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	_scatter_batch(parent, rocks, stone_colors, rock, stone)
	if not ridges.is_empty():
		_scatter_batch(parent, ridges, ridge_colors, scenery.ridge(), stone)


func _build_landmarks(parent: Node3D, scenery: SCENERY, first: int, last: int,
		clearances: Array[Rect2]) -> void:
	var first_block := maxi(1, floori(float(first) / SCENERY.REGION_LENGTH))
	var last_block := floori(float(last - 1) / SCENERY.REGION_LENGTH)
	var models := [_models.launcher_truck, _models.launch_platform, _models.moored_airship]
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
			footprints[kind], models[kind])


func _place_landmark(parent: Node3D, scenery: SCENERY, clearances: Array[Rect2],
		preferred: int, last: int, columns: Array, footprint: Vector2, make: Callable) -> void:
	# The sector that contains the preferred point owns the whole search.
	for offset in [0, 42, 84, 126, 168, 210, 252, 294]:
		var distance := float(preferred + offset)
		if distance + footprint.y >= last:
			break
		for x: float in columns:
			var site := Rect2(Vector2(x, distance) - footprint, footprint * 2.0)
			if not _landmark_site_clear(scenery, site, clearances):
				continue
			var landmark: Node3D = make.call()
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
			var crossing := Node3D.new()
			_scene.add_child(crossing)
			_crossings[index] = crossing
			_road(limits.x, limits.y, 8, 64, crossing)
			_road(limits.x, limits.y, 96, 160, crossing)
			_bridge_abutments(crossing, limits)
			_models.batch_by_material(crossing)
			var deck := Node3D.new()
			_bridge_span(deck, limits)
			crossing.add_child(deck)
			_decks[index] = deck
		var center := float(limits.x + limits.y) * 0.5
		_crossings[index].visible = center >= distance - 40 and center <= distance + 190
		_decks[index].visible = not flight.is_bridge_destroyed(index)


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


func _x(value: float) -> float:
	return (value - 8.0) * X_SCALE


func _z(value: float) -> float:
	return -(value - _origin_distance) * Z_SCALE


func _point(x: float, distance: float, height: float) -> Vector3:
	return Vector3(_x(x), height, _z(distance))
