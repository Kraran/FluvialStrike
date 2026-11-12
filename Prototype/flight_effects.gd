extends Node3D

const GLOW = preload("res://flight_glow.gdshader")
enum Batch { SPARKS, SMOKE, RIPPLE, VAPOR, FIRE, WRECKAGE }
const CAPACITY := [128, 52, 24, 32, 20, 24]
const EMBER := Color("#b93816")

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
	_make_batch(PlaneMesh.new(), _glow(0), CAPACITY[Batch.VAPOR])
	_make_batch(PlaneMesh.new(), _glow(3), CAPACITY[Batch.FIRE])
	_make_batch(BoxMesh.new(), debris_material, CAPACITY[Batch.WRECKAGE])
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


# One tiny instance per particle batch. Drawing it once compiles the batch shaders before play.
func make_prewarm() -> Node3D:
	var group := Node3D.new()
	for source: MultiMeshInstance3D in get_children():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = source.multimesh.mesh
		batch.instance_count = 1
		batch.set_instance_transform(0, Transform3D.IDENTITY)
		batch.set_instance_color(0, Color.WHITE)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = source.material_override
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(instance)
	return group


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


func jet_breakup(at: Vector3, heading: Vector3) -> void:
	_flash(at, 3.8, Color("#fff2d1"), 0.23, heading * 8.0)
	_flash(at + heading * 1.45, 2.7, Color("#ff993c"), 0.36, heading * 6.0)
	for i in 5:
		var plume := at + heading * i * 0.72
		_emit(Batch.SMOKE, plume, heading * (3.5 + i * 0.55) + Vector3.UP,
			Vector3(2.2, 1, 1.85), Color("#47474cc4"), 0.92 + i * 0.05, 2.1, 0.0)
	for i in 21:
		var velocity := heading * 11.0 + _spray(2.2, 8.8, -1.1, 3.2)
		_emit(Batch.SPARKS, at + velocity * 0.045, velocity, Vector3(0.58, 0.085, 0.10),
			Color("#ffeaac").lerp(Color("#ed652c"), _rng.randf()), _rng.randf_range(0.28, 0.58), 0.18, 13.0)
	for i in 6:
		var velocity := heading * 7.6 + _spray(1.8, 5.8, -0.7, 2.6)
		_emit(Batch.WRECKAGE, at, velocity, Vector3(0.57, 0.17, 1.03),
			Color("#67717b"), 1.42, 1.0, 12.0, Vector3(5.2, i * 1.7 - 4.0, 3.3))


func helicopter_breakup(at: Vector3, blade_angle: float) -> void:
	_flash(at, 2.2, Color("#ffc768"), 0.25, Vector3.UP)
	_sparks(at, 8, 0.82)
	for i in 4:
		var radial := Vector3(cos(blade_angle + i * TAU / 4.0), 0, sin(blade_angle + i * TAU / 4.0))
		_emit(Batch.WRECKAGE, at + radial * 0.83, radial * 5.0 + Vector3.UP * 2.1,
			Vector3(0.19, 0.07, 1.28), Color("#c0bfb0"), 0.83, 1.0, 10.7, Vector3(i * 1.6, 11.0, 2.5))


func helicopter_smoke(at: Vector3) -> void:
	_emit(Batch.SMOKE, at, Vector3(0.35, 0.83, 0.24), Vector3(1.25, 1, 1.25),
		Color("#40454ac6"), 0.84, 2.7, 0.0)


func tanker_burst(at: Vector3, strength: float) -> void:
	_flash(at, 3.5 * strength, Color("#ffae51"), 0.38, Vector3.UP * 2.7)
	_flash(at + Vector3.UP * 0.45, 2.1 * strength, Color("#ffebac"), 0.20, Vector3.UP * 3.8)
	_sparks(at, 9, strength)
	for i in 3:
		_smoke(at, strength)
	_ripple(Vector3(at.x, 0.042, at.z), 1.6 * strength, 0.85)


func fuel_barge_blast(at: Vector3) -> void:
	_flash(at + Vector3.UP * 0.6, 5.2, Color("#fff7d0"), 0.18, Vector3.UP * 2.7)
	for i in 9:
		var velocity := _spray(1.6, 5.4, 2.8, 5.7)
		var size := _rng.randf_range(2.3, 3.8)
		var hot := Color("#f75c21").lerp(Color("#ffc247"), _rng.randf())
		_flash(at + velocity * 0.15, size, hot, _rng.randf_range(0.52, 0.94), velocity)
	_sparks(at, 28, 1.48)
	for i in 7:
		_smoke(at + _spray(0.2, 1.25, 0.1, 0.62), 1.42)
	var water := Vector3(at.x, 0.042, at.z)
	_ripple(water, 3.4, 1.12)
	_ripple(water + Vector3.BACK * 1.6, 2.3, 0.85)


func _flash(at: Vector3, size: float, tint: Color, lifetime: float, velocity: Vector3) -> void:
	_emit(Batch.FIRE, at, velocity, Vector3(size, 1, size), tint, lifetime, 1.92, 0.0)


func player_explosion(at: Vector3) -> void:
	_emit(Batch.FIRE, at + Vector3.UP * 0.52, Vector3.UP * 3.0, Vector3(4.2, 1, 4.2),
		Color("#fff1c8"), 0.18, 2.25, 0.0)
	for i in 11:
		var velocity := _spray(2.2, 7.7, 1.8, 5.4)
		var size := _rng.randf_range(2.1, 4.4)
		var hot := Color("#ffd26d").lerp(Color("#f1501c"), _rng.randf())
		_emit(Batch.FIRE, at + velocity * 0.22, velocity, Vector3(size, 1, size), hot,
			_rng.randf_range(0.38, 0.72), 1.92, 0.0)
	for i in 46:
		var velocity := _spray(7.5, 19.5, 2.1, 6.8)
		var tint := Color("#fff7cb").lerp(Color("#ff8e34"), _rng.randf())
		var length := _rng.randf_range(0.30, 0.72)
		_emit(Batch.SPARKS, at + velocity * 0.08, velocity, Vector3(0.11, 0.12, length),
			tint, _rng.randf_range(0.28, 0.64), 0.16, 14.5, Vector3(0, _rng.randf_range(-9.0, 9.0), 0))
	for i in 11:
		_smoke(at + _spray(0.2, 1.9, 0.03, 0.32), 1.65)
	for i in 18:
		var size := _rng.randf_range(0.18, 0.66)
		var spin := Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0))
		var color := Color("#41454a").lerp(Color("#c1b1a1"), _rng.randf())
		_emit(Batch.WRECKAGE, at, _spray(2.4, 11.0, 2.0, 6.8), Vector3(size, size * 0.24, size * 2.0),
			color, _rng.randf_range(0.65, 1.45), 0.95, 14.0, spin)


func player_water_impact(at: Vector3) -> void:
	_ripple(at, 3.1, 1.24)
	_ripple(at + Vector3.BACK * 1.7, 1.75, 0.88)
	for i in 9:
		var velocity := _spray(1.6, 5.5, 2.6, 5.3) + Vector3.FORWARD * 2.2
		_emit(Batch.VAPOR, at, velocity, Vector3(1.65, 1, 2.1),
			Color("#def8f4cc"), _rng.randf_range(0.35, 0.65), 2.2, 8.0)
	for i in 36:
		var velocity := _spray(1.9, 9.2, 1.8, 7.7) + Vector3.FORWARD * 2.8
		var tint := Color("#f4fffc").lerp(Color("#7cc3cf"), _rng.randf())
		_emit(Batch.SPARKS, at, velocity, Vector3(0.11, 0.17, 0.33), tint,
			_rng.randf_range(0.38, 0.78), 0.22, 18.0)


func bridge_hit(at: Vector3) -> void:
	_flash(at, 3.5, Color("#fff0c4"), 0.20, Vector3.UP * 2.8)
	_flash(at + Vector3.FORWARD * 0.32, 2.7, Color("#ff9444"), 0.34, Vector3.UP * 2.1)
	_sparks(at, 17, 1.44)
	for i in 4:
		_smoke(at, 1.23)


func bridge_joint_break(at: Vector3) -> void:
	_sparks(at, 4, 0.72)
	_emit(Batch.SMOKE, at, Vector3(0.25, 1.18, 0.16), Vector3(1.42, 1, 1.25),
		Color("#aca691aa"), 0.66, 2.38, 0.0)


func bridge_piece_splash(at: Vector3, strength: float) -> void:
	_ripple(at, lerpf(1.12, 2.55, strength), 0.91)
	for i in 11:
		var velocity := _spray(1.1, 5.9, 1.8, 4.5) * lerpf(0.62, 1.18, strength)
		var tint := Color("#f6fffc").lerp(Color("#70b8c5"), _rng.randf())
		_emit(Batch.SPARKS, at, velocity, Vector3(0.095, 0.15, 0.21), tint,
			_rng.randf_range(0.29, 0.53), 0.24, 15.5)
	for i in 3:
		var velocity := _spray(0.8, 2.7, 1.9, 3.8)
		_emit(Batch.VAPOR, at, velocity, Vector3(0.94, 1, 0.94),
			Color("#ddf9f3c0"), 0.42, 2.1, 9.0)


func clear() -> void:
	_rng.seed = 14081
	for group in _batches.size():
		_active[group] = 0
		_batches[group].visible_instance_count = 0


func shift_origin(shift: float) -> void:
	for group in _batches.size():
		for index in _active[group]:
			_particles[group][index].origin.z += shift


func present(delta: float) -> void:
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
			var hits_water := group == Batch.WRECKAGE and position.y <= 0.035
			if group == Batch.VAPOR and particle.gravity > 0.0 and position.y < 0.035:
				age = particle.lifetime
			if hits_water or age >= particle.lifetime:
				if hits_water:
					_ripple(Vector3(position.x, 0.035, position.z), 1.32, 0.72)
				count -= 1
				slots[index] = slots[count]
				slots[count] = particle
				continue
			var phase := age / particle.lifetime
			var basis := Basis.from_euler(particle.spin * age) * Basis.from_scale(particle.size * lerpf(1.0, particle.growth, phase))
			var color := particle.color
			if group == Batch.FIRE:
				color = color.lerp(EMBER, smoothstep(0.15, 0.9, phase))
				color.a *= 1.0 - smoothstep(0.08, 1.0, phase)
			elif group == Batch.SMOKE or group == Batch.RIPPLE or group == Batch.VAPOR:
				color.a *= 1.0 - phase
			batch.set_instance_transform(index, Transform3D(basis, position))
			batch.set_instance_color(index, color)
			index += 1
		_active[group] = count
		batch.visible_instance_count = count
		# Godot only recomputes a MultiMesh's bounding box after culling: the batch would be culled
		# and sorted with last frame's box, and a new burst (empty box) could miss its first frame
		# depending on the engine's internal update order. Asking for it now updates it in time.
		batch.get_aabb()


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
