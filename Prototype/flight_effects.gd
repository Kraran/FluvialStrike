extends Node3D

const GLOW = preload("res://flight_glow.gdshader")
enum Batch { SPARKS, SMOKE, RIPPLE, DEBRIS, VAPOR }
const CAPACITY := [96, 40, 16, 24, 32]

class Particle:
	var origin: Vector3
	var velocity: Vector3
	var size: Vector3
	var spin: Vector3
	var color: Color
	var age: float
	var lifetime: float
	var growth: float
	var gravity: float

var _batches: Array[MultiMesh] = []
var _particles: Array[Array] = []
var _active := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _bridge_splash_pending := false


func _ready() -> void:
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.vertex_color_use_as_albedo = true
	var debris_material := StandardMaterial3D.new()
	debris_material.vertex_color_use_as_albedo = true
	debris_material.roughness = 0.93
	_make_batch(BoxMesh.new(), spark_material, CAPACITY[Batch.SPARKS])
	_make_batch(PlaneMesh.new(), _glow(0), CAPACITY[Batch.SMOKE])
	_make_batch(PlaneMesh.new(), _glow(1), CAPACITY[Batch.RIPPLE])
	_make_batch(_slab_mesh(), debris_material, CAPACITY[Batch.DEBRIS])
	_make_batch(PlaneMesh.new(), _glow(0), CAPACITY[Batch.VAPOR])
	_active.resize(_batches.size())
	clear()


func make_trail() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.52, 2.8)
	var trail := MeshInstance3D.new()
	trail.mesh = mesh
	trail.material_override = _glow(2, Color("#ffbd66ca"))
	trail.position = Vector3(0, 0.015, 1.19)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return trail


func wingtip_vapor(at: Vector3, bank: float, throttle: float, wingtip: Vector2) -> void:
	var wing := Basis(Vector3.BACK, bank)
	var tint := Color(0.72, 0.88, 0.94, lerpf(0.09, 0.23, throttle))
	var streak := Vector3(lerpf(0.18, 0.29, throttle), 1.0, lerpf(0.46, 0.80, throttle))
	for side in [-1.0, 1.0]:
		var tip := wing * Vector3(side * wingtip.x, 0.02, wingtip.y)
		var drift := Vector3(side * 0.12, 0.0, 0.38)
		_emit(Batch.VAPOR, at + tip, drift, streak, tint, 0.20, 1.45, 0.0)


func muzzle(at: Vector3) -> void:
	_emit(Batch.SMOKE, at, Vector3.ZERO, Vector3(1.5, 1, 1.7), Color("#ff923fbc"), 0.105, 1.5, 0.0)
	_emit(Batch.SMOKE, at + Vector3.UP * 0.02, Vector3.FORWARD, Vector3(0.65, 1, 0.85),
		Color("#fff3cb"), 0.073, 0.55, 0.0)


func splash(at: Vector3) -> void:
	_ripple(at, 0.9, 0.52)
	for i in range(9):
		var velocity := _spray(1.0, 3.2, 1.8, 3.8)
		_emit(Batch.SPARKS, at, velocity, Vector3(0.09, 0.14, 0.23),
			Color("#d4f3f5").lerp(Color("#71c0c7"), _rng.randf()), 0.42, 0.3, 16.0)


func impact(at: Vector3, strength: float) -> void:
	_emit(Batch.SMOKE, at, Vector3.UP, Vector3(2.9, 1, 2.9) * strength,
		Color("#ff8e3cdb"), 0.22, 1.45, 0.0)
	_sparks(at, 12, strength)
	for i in range(4):
		_smoke(at, strength)


func bridge(at: Vector3) -> void:
	_bridge_splash_pending = true
	for row in [-1.0, 1.0]:
		for column in range(6):
			var offset := (column - 2.5) * 3.2
			var origin := at + Vector3(offset, 0, row * 1.78)
			var velocity := Vector3(offset * 0.23, _rng.randf_range(1.3, 3.6), row * _rng.randf_range(0.5, 2.8))
			var spin := Vector3(_rng.randf_range(-4.2, 4.2), _rng.randf_range(-2.0, 2.0), row * 3.1)
			_emit(Batch.DEBRIS, origin, velocity, Vector3(3.16, 0.43, 3.52),
				Color.WHITE.darkened(_rng.randf_range(0.03, 0.21)), 0.92, 0.94, 13.5, spin)
	for offset in [-6.4, -3.2, 0.0, 3.2, 6.4]:
		var plume := at + Vector3(offset, 0.32, _rng.randf_range(-0.7, 0.7))
		_emit(Batch.SMOKE, plume, Vector3.UP, Vector3(3.8, 1, 3.2), Color("#ffad4be6"), 0.26, 1.35, 0.0)
		_emit(Batch.SMOKE, plume + Vector3.UP * 0.03, Vector3.UP, Vector3(2.1, 1, 1.8),
			Color("#fff0bf"), 0.19, 1.48, 0.0)
		_smoke(plume, 1.5)
		_sparks(plume, 6, 1.1)


func clear() -> void:
	_bridge_splash_pending = false
	_rng.seed = 14081
	for group in _batches.size():
		_active[group] = 0
		_batches[group].visible_instance_count = 0


func shift_origin(shift: float) -> void:
	for group in _batches.size():
		for index in _active[group]:
			_particles[group][index].origin.z += shift


func present(delta: float) -> Vector3:
	var bridge_splash := Vector3.INF
	for group in _batches.size():
		var batch := _batches[group]
		var slots := _particles[group]
		var count := _active[group]
		if count == 0:
			continue
		var index := 0
		while index < count:
			var particle: Particle = slots[index]
			particle.age += delta
			var age := particle.age
			var position := particle.origin + particle.velocity * age + Vector3.DOWN * (particle.gravity * age * age * 0.5)
			var hits_water := group == Batch.DEBRIS and position.y <= 0.035
			if hits_water or age >= particle.lifetime:
				if hits_water:
					if _bridge_splash_pending:
						_bridge_splash_pending = false
						bridge_splash = position
					_ripple(Vector3(position.x, 0.035, position.z), 1.32, 0.72)
				count -= 1
				slots[index] = slots[count]
				slots[count] = particle
				continue
			var phase := age / particle.lifetime
			var basis := Basis.from_euler(particle.spin * age) * Basis.from_scale(particle.size * lerpf(1.0, particle.growth, phase))
			var color := particle.color
			if group == Batch.SMOKE or group == Batch.RIPPLE or group == Batch.VAPOR:
				color.a *= 1.0 - phase
			batch.set_instance_transform(index, Transform3D(basis, position))
			batch.set_instance_color(index, color)
			index += 1
		_active[group] = count
		batch.visible_instance_count = count
	return bridge_splash


func _sparks(at: Vector3, count: int, strength: float) -> void:
	for i in count:
		var size := Vector3(0.09, 0.095, 0.31) * strength
		_emit(Batch.SPARKS, at, _spray(2.8, 7.2, 1.2, 4.7) * strength, size,
			Color("#fff0b3").lerp(Color("#f18032"), _rng.randf()), _rng.randf_range(0.22, 0.49),
			0.10, 13.0, Vector3(2, _rng.randf_range(-12.0, 12.0), 0))


func _smoke(at: Vector3, strength: float) -> void:
	var origin := at + Vector3(_rng.randf_range(-0.55, 0.55), 0, _rng.randf_range(-0.55, 0.55))
	_emit(Batch.SMOKE, origin, _spray(0.7, 1.8, 0.9, 1.6), Vector3(2.0, 1, 2.0) * strength,
		Color("#4950529e"), _rng.randf_range(0.83, 1.56), 2.25, 0.0)


func _ripple(at: Vector3, diameter: float, lifetime: float) -> void:
	_emit(Batch.RIPPLE, at, Vector3.ZERO, Vector3(diameter, 1, diameter),
		Color("#b8e5e1b0"), lifetime, 4.2, 0.0)


func _spray(min_speed: float, max_speed: float, min_up: float, max_up: float) -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var speed := _rng.randf_range(min_speed, max_speed)
	return Vector3(cos(angle) * speed, _rng.randf_range(min_up, max_up), sin(angle) * speed)


func _emit(group: Batch, origin: Vector3, velocity: Vector3, size: Vector3, color: Color,
		lifetime: float, growth: float, gravity: float, spin: Vector3 = Vector3.ZERO) -> void:
	var index := _active[group]
	if index >= CAPACITY[group]:
		return
	var particle: Particle = _particles[group][index]
	particle.origin = origin
	particle.velocity = velocity
	particle.size = size
	particle.spin = spin
	particle.color = color
	particle.age = 0.0
	particle.lifetime = lifetime
	particle.growth = growth
	particle.gravity = gravity
	_active[group] = index + 1


func _glow(shape: int, tint: Color = Color.WHITE) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW
	material.set_shader_parameter("shape", shape)
	material.set_shader_parameter("tint", tint)
	return material


func _make_batch(mesh: Mesh, material: Material, capacity: int) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = capacity
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_batches.append(batch)
	var slots: Array[Particle] = []
	for index in capacity:
		slots.append(Particle.new())
	_particles.append(slots)


func _slab_mesh() -> ArrayMesh:
	var arrays := BoxMesh.new().surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors := PackedColorArray()
	for normal in normals:
		colors.append(Color("#555854") if normal.y > 0.5 else Color("#929387"))
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
