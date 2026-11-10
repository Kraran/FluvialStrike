extends SubViewport

const COURSE = preload("res://course.gd")
const FLIGHT = preload("res://flight.gd")
const MODELS = preload("res://flight_models.gd")
const BANK_SHADER = preload("res://bank.gdshader")
const RIVER_SHADER = preload("res://river.gdshader")
const CANOPY_SHADER = preload("res://canopy.gdshader")
const X_SCALE := 0.6
const Z_SCALE := 0.3

var _scene := Node3D.new()
var _camera := Camera3D.new()
var _models := MODELS.new()
var _aircraft: Node3D
var _shot: MeshInstance3D
var _crossings: Array[Node3D] = []
var _decks: Array[Node3D] = []
var _actors := {}
var _templates := {}
var _blasts: Array[Dictionary] = []
var _previous_section := 1
var _was_flying := true
var _clock := 0.0


func _ready() -> void:
	set_quality(true)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_scene)
	_configure_light()
	_build_landscape()
	_build_crossings()
	_templates = {"tanker": _models.tanker(), "helicopter": _models.helicopter(),
		"fuel": _models.fuel_barge(), "jet": _models.aircraft(true)}
	_aircraft = _models.aircraft()
	_scene.add_child(_aircraft)
	var tracer := StandardMaterial3D.new()
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.albedo_color = Color("#fff3b4")
	_shot = _models.box(_scene, Vector3.ZERO, Vector3(0.13, 0.10, 1.22), tracer)
	_shot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_quality(hd: bool) -> void:
	size = Vector2i(1368, 725) if hd else Vector2i(912, 483)
	msaa_3d = Viewport.MSAA_2X if hd else Viewport.MSAA_DISABLED


func sync(flight: FLIGHT, delta: float) -> void:
	_clock += delta
	_camera.position.z = _z(flight.distance + 70.5)
	var running := flight.status == FLIGHT.Status.FLYING or flight.status == FLIGHT.Status.COMPLETE
	_aircraft.visible = running
	_aircraft.position = _point(flight.x + 4, flight.distance, 2.30)
	_aircraft.rotation.z = lerpf(_aircraft.rotation.z, flight.heading * -0.28, minf(delta * 14, 1.0))
	if _was_flying and flight.status == FLIGHT.Status.CRASHED:
		_explode(_aircraft.position, 0.85)
	_was_flying = running
	_shot.visible = flight.shot_active
	_shot.position = _point(flight.shot_x, flight.shot_distance - 2.5, 1.15)

	for i in _decks.size():
		var bridge: Vector2i = COURSE.BRIDGES[i]
		var center := float(bridge.x + bridge.y) * 0.5
		_crossings[i].visible = center >= flight.distance - 40 and center <= flight.distance + 190
		_decks[i].visible = i >= flight.section - 1
		if i == flight.section - 2 and flight.section > _previous_section:
			_explode(_point(80, center, 0.65), 2.7)
	_previous_section = flight.section
	_sync_fleet(flight)
	_update_blasts(delta)


func _sync_fleet(flight: FLIGHT) -> void:
	var first := COURSE.first_target(flight.distance - 25)
	var end := COURSE.first_target(flight.distance + 174)
	for i: int in _actors.keys():
		if i >= first and i < end and not flight.target_gone(i):
			continue
		var actor: Node3D = _actors[i]
		if i >= first and i < end:
			var kind: String = COURSE.TARGETS[i][0]
			_explode(actor.position + Vector3.UP * 0.55, 0.64 if kind == "helicopter" else 1.0)
		actor.hide()
		actor.queue_free()
		_actors.erase(i)
	for i in range(first, end):
		if flight.target_gone(i):
			continue
		var target := flight.target_position(i)
		var kind: String = COURSE.TARGETS[i][0]
		var altitude := 0.0
		if kind == "helicopter":
			altitude = 1.38
		elif kind == "jet":
			altitude = 2.30
		var at := _point(target.x, target.y, altitude)
		if not _actors.has(i):
			var template: Node3D = _templates[kind]
			var new_actor := template.duplicate() as Node3D
			new_actor.position = at
			if kind == "jet":
				new_actor.rotation.y = -PI / 2.0
			_scene.add_child(new_actor)
			_actors[i] = new_actor
		var actor: Node3D = _actors[i]
		if kind == "jet":
			var horizontal_travel := wrapf(at.x - actor.position.x, -48.0, 48.0)
			if absf(horizontal_travel) > 0.01:
				actor.rotation.y = -signf(horizontal_travel) * PI / 2.0
		actor.position = at
		if kind == "helicopter":
			actor.get_node("Rotor").rotation.y = _clock * 36.0


func _exit_tree() -> void:
	for template: Node3D in _templates.values():
		template.free()
	_templates.clear()


func reset_effects() -> void:
	_clock = 0.0
	_previous_section = 1
	_was_flying = true
	_aircraft.rotation.z = 0.0
	for blast in _blasts:
		blast.node.queue_free()
	_blasts.clear()


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
	sun.rotation_degrees = Vector3(-57, -39, 0)
	sun.light_color = Color("#fff0cc")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
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
	var land := SurfaceTool.new()
	var water := SurfaceTool.new()
	land.begin(Mesh.PRIMITIVE_TRIANGLES)
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in COURSE.BANKS.size():
		var start: float = COURSE.BANKS[i][0]
		var end := float(COURSE.END + 240)
		if i + 1 < COURSE.BANKS.size():
			end = COURSE.BANKS[i + 1][0]
		var spans: Array = COURSE.BANKS[i][1]
		var previous := 8.0
		for j in range(0, spans.size(), 2):
			var left: float = spans[j]
			var right: float = spans[j + 1]
			_bank_strip(land, previous, left, start, end, j != 0, true)
			var edge := minf((right - left) * 0.25, 3.2)
			_strip(water, left, left + edge, start, end, 0.0, 0.0, 1.0, 0.0)
			_strip(water, left + edge, right - edge, start, end, 0.0, 0.0, 0.0, 0.0)
			_strip(water, right - edge, right, start, end, 0.0, 0.0, 0.0, 1.0)
			previous = right
		_bank_strip(land, previous, 160.0, start, end, true, false)
	_commit_surface(land, BANK_SHADER)
	_commit_surface(water, RIVER_SHADER)
	_scatter_landscape()


func _bank_strip(surface: SurfaceTool, left: float, right: float, start: float, end: float,
		wet_left: bool, wet_right: bool) -> void:
	var edge := minf((right - left) * 0.22, 1.55)
	var dry_left := left
	var dry_right := right
	if wet_left:
		dry_left += edge
		_strip(surface, left, dry_left, start, end, 0.028, 0.26, 1.0, 0.0)
	if wet_right:
		dry_right -= edge
		_strip(surface, dry_right, right, start, end, 0.26, 0.028, 0.0, 1.0)
	_strip(surface, dry_left, dry_right, start, end, 0.26, 0.26, 0.0, 0.0)


func _strip(surface: SurfaceTool, left: float, right: float, start: float, end: float,
		height_left: float, height_right: float, edge_left: float, edge_right: float) -> void:
	if right <= left:
		return
	var a := _point(left, end, height_left)
	var b := _point(right, end, height_right)
	var c := _point(left, start, height_left)
	var d := _point(right, start, height_right)
	var normal := (c - a).cross(b - a).normalized()
	var tones := [edge_left, edge_right, edge_left, edge_right, edge_left, edge_right]
	var vertices := [a, b, c, d, c, b]
	for i in vertices.size():
		surface.set_normal(normal)
		surface.set_color(Color(tones[i], 0, 0))
		surface.add_vertex(vertices[i])


func _commit_surface(surface: SurfaceTool, shader: Shader) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene.add_child(instance)


func _scatter_landscape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60517
	var trees: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var rocks: Array[Transform3D] = []
	var stone_colors: Array[Color] = []
	var woodline := FastNoiseLite.new()
	woodline.seed = 7628
	woodline.frequency = 0.043
	for distance in range(-120, COURSE.END + 228, 17):
		for column in range(12, 158, 7):
			var x := column + rng.randf_range(-2.6, 2.6)
			var z := distance + rng.randf_range(-7.0, 7.0)
			if absf(z - 3.0) < 17.0 or absf(fposmod(z - 1030.0 + 512.0, 1024.0) - 512.0) < 19.0:
				continue
			if _close_to_water(x, z, 2.7):
				if not _close_to_water(x, z, 0.5) and rng.randf() < 0.43:
					var radius := rng.randf_range(0.24, 0.95)
					rocks.append(_transform(_point(x, z, 0.25), Vector3(radius, radius * 0.65, radius), rng.randf() * TAU))
					stone_colors.append(Color("#9d9782").lerp(Color("#646764"), rng.randf()))
				continue
			if rng.randf() > 0.20 + clampf(woodline.get_noise_2d(x, z * 0.5) * 0.9, -0.12, 0.70):
				continue
			var width := rng.randf_range(1.5, 3.3)
			var height := width * rng.randf_range(0.77, 1.24)
			var leaf := Color("#5d7349").lerp(Color("#2b4333"), rng.randf())
			var twist := rng.randf() * TAU
			for lobe in range(4):
				var angle := twist + lobe * 2.4
				var spread := 0.0 if lobe == 0 else width * 0.26
				var center := _point(x, z, 0.64 + height * (0.52 if lobe == 0 else 0.39))
				center += Vector3(cos(angle), 0, sin(angle)) * spread
				var factor := 0.81 if lobe == 0 else rng.randf_range(0.51, 0.72)
				var dimensions := Vector3(width, height, width * 0.87) * factor
				trees.append(_transform(center, dimensions, angle))
				leaf_colors.append(leaf.lightened(rng.randf_range(-0.08, 0.12)))
	var canopy := ShaderMaterial.new()
	canopy.shader = CANOPY_SHADER
	_scatter_batch(trees, leaf_colors, 9, 5, canopy)
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 0.94
	_scatter_batch(rocks, stone_colors, 6, 4, stone)


func _close_to_water(x: float, distance: float, clearance: float) -> bool:
	var spans := COURSE.water_spans(distance)
	for j in range(0, spans.size(), 2):
		if x >= spans[j] - clearance and x <= spans[j + 1] + clearance:
			return true
	return false


func _scatter_batch(transforms: Array[Transform3D], colors: Array[Color], sides: int, rings: int,
		material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = sides
	mesh.rings = rings
	mesh.material = material
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
		_scene.add_child(instance)


func _transform(at: Vector3, dimensions: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(dimensions), at)


func _build_crossings() -> void:
	_road(-7, 14, 8, 64, _scene, false)
	_road(-7, 14, 96, 160, _scene, false)
	for limits: Vector2i in COURSE.BRIDGES:
		var crossing := Node3D.new()
		_scene.add_child(crossing)
		_crossings.append(crossing)
		_road(limits.x, limits.y, 8, 64, crossing, false)
		_road(limits.x, limits.y, 96, 160, crossing, false)
		var deck := Node3D.new()
		crossing.add_child(deck)
		_decks.append(deck)
		_road(limits.x, limits.y, 64, 96, deck, true)


func _road(from: int, to: int, left: int, right: int, parent: Node3D, over_water: bool) -> void:
	var mid := float(from + to) * 0.5
	var x := float(left + right) * 0.5
	var width := (right - left) * X_SCALE
	var length := (to - from) * Z_SCALE
	var asphalt := _models.paint(Color("#555854"), 0.91)
	var concrete := _models.paint(Color("#929387"), 0.86)
	var stripe := _models.paint(Color("#cebd8d"), 0.80)
	var iron := _models.paint(Color("#43514f"), 0.53, 0.40)
	_models.box(parent, _point(x, mid, 0.52), Vector3(width, 0.48, length), concrete)
	_models.box(parent, _point(x, mid, 0.80), Vector3(width, 0.10, length - 0.40), asphalt)
	for distance in [from + 1.3, to - 1.3]:
		_models.box(parent, _point(x, distance, 0.86), Vector3(width, 0.08, 0.08), stripe)
		if over_water:
			_models.box(parent, _point(x, distance, 1.21), Vector3(width, 0.12, 0.14), iron)
			for column in range(left + 1, right, 3):
				_models.box(parent, _point(column, distance, 1.02), Vector3(0.13, 0.45, 0.14), iron)
	for column in range(left + 2, right - 1, 5):
		_models.box(parent, _point(column, mid, 0.857), Vector3(1.22, 0.018, 0.09), stripe)
		if over_water:
			_models.box(parent, _point(column, mid, 0.16), Vector3(0.68, 0.34, length), concrete)


func _explode(at: Vector3, strength: float) -> void:
	var node := Node3D.new()
	node.position = at
	_scene.add_child(node)
	var parts: Array[MeshInstance3D] = []
	for i in range(10):
		var color := Color("#e97b39") if i < 6 else Color("#584f45")
		var part := _models.box(node, Vector3.ZERO, Vector3.ONE, _models.paint(color))
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parts.append(part)
	_blasts.append({"node": node, "parts": parts, "age": 0.0, "strength": strength})


func _update_blasts(delta: float) -> void:
	for i in range(_blasts.size() - 1, -1, -1):
		var blast := _blasts[i]
		blast.age += delta
		var age: float = blast.age
		if age >= 0.68:
			blast.node.queue_free()
			_blasts.remove_at(i)
			continue
		var strength: float = blast.strength
		var parts: Array[MeshInstance3D] = blast.parts
		for j in parts.size():
			var piece := parts[j]
			var angle := j * 2.4
			var spread := strength * (0.26 + 4.9 * age)
			piece.position = Vector3(cos(angle) * spread, sin(age * 4) * strength, sin(angle) * spread)
			piece.scale = Vector3.ONE * (1.0 - age / 0.68) * strength * (0.25 + (j % 3) * 0.12)
			piece.rotation = Vector3(angle, age * 8 + angle, age * 6)


func _x(value: float) -> float:
	return (value - 8.0) * X_SCALE


func _z(value: float) -> float:
	return -value * Z_SCALE


func _point(x: float, distance: float, height: float) -> Vector3:
	return Vector3(_x(x), height, _z(distance))
