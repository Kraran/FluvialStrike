extends RefCounted

var _materials := {}
var _box_mesh := BoxMesh.new()
var _sphere_mesh := SphereMesh.new()
var _cylinder_mesh := CylinderMesh.new()


func _init() -> void:
	_sphere_mesh.radial_segments = 16
	_sphere_mesh.rings = 8
	_cylinder_mesh.radial_segments = 16
	_cylinder_mesh.rings = 1


func aircraft(hostile: bool = false) -> Node3D:
	var jet := Node3D.new()
	var alloy := paint(Color("#b05f3d") if hostile else Color("#a8b7bb"), 0.48, 0.32)
	var slate := paint(Color("#566f78"), 0.53, 0.32)
	var trim := paint(Color("#253946"), 0.31, 0.26)
	var canopy := paint(Color("#173744"), 0.19, 0.45)
	var warning := paint(Color("#cf6340"), 0.44)
	_ellipsoid(jet, Vector3(0, 0, -0.27), Vector3(0.42, 0.28, 1.96), alloy)
	_ellipsoid(jet, Vector3(0, 0.22, -0.88), Vector3(0.28, 0.22, 0.57), canopy)
	_ellipsoid(jet, Vector3(0.10, 0.38, -1.03), Vector3(0.05, 0.025, 0.27), alloy)
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(0.29 * side, -0.86), Vector2(2.45 * side, 0.54),
			Vector2(2.42 * side, 0.95), Vector2(0.44 * side, 0.73),
		])
		_plate(jet, wing, 0.02, 0.09, alloy)
		_plate(jet, PackedVector2Array([
			Vector2(0.29 * side, 1.06), Vector2(1.23 * side, 1.64),
			Vector2(1.17 * side, 1.95), Vector2(0.23 * side, 1.73),
		]), 0.06, 0.075, slate)
		_ellipsoid(jet, Vector3(side * 0.40, 0.02, 0.75), Vector3(0.21, 0.20, 1.08), slate)
		box(jet, Vector3(side * 0.4, 0.02, 1.68), Vector3(0.33, 0.25, 0.36), trim)
		box(jet, Vector3(side * 2.20, 0.078, 0.65), Vector3(0.15, 0.025, 0.28), warning)
		var fin := box(jet, Vector3(side * 0.53, 0.33, 1.44), Vector3(0.09, 0.48, 0.57), slate)
		fin.rotation.z = side * -0.19
	return jet


func tanker() -> Node3D:
	var ship := Node3D.new()
	var rust := paint(Color("#934939"), 0.69, 0.24)
	var deck := paint(Color("#4b5754"), 0.64, 0.17)
	var trim := paint(Color("#d7cab0"), 0.58, 0.11)
	var dark := paint(Color("#293335"), 0.42, 0.24)
	var cargo := paint(Color("#b86c43"), 0.64, 0.21)
	var bow := PackedVector2Array([
		Vector2(0, -4.55), Vector2(1.02, -3.3), Vector2(1.17, 3.80),
		Vector2(0.82, 4.28), Vector2(-0.82, 4.28), Vector2(-1.17, 3.8),
		Vector2(-1.02, -3.3),
	])
	_plate(ship, bow, 0.34, 0.57, rust)
	_plate(ship, _scaled_outline(bow, 0.92), 0.66, 0.11, deck)
	for z in [-2.40, -0.95, 0.50, 1.95]:
		box(ship, Vector3(0, 0.82, z), Vector3(1.50, 0.29, 1.09), cargo)
		box(ship, Vector3(0, 0.98, z), Vector3(1.28, 0.065, 0.84), trim)
	box(ship, Vector3(0, 1.03, 3.16), Vector3(1.71, 0.77, 1.12), trim)
	box(ship, Vector3(0, 1.20, 2.56), Vector3(1.42, 0.16, 0.13), dark)
	box(ship, Vector3(0.52, 1.55, 3.53), Vector3(0.26, 0.35, 0.26), rust)
	_wake(ship, 4.8)
	ship.rotation.y = -PI / 2
	return ship


func fuel_barge() -> Node3D:
	var barge := Node3D.new()
	var hull := paint(Color("#32484a"), 0.61, 0.20)
	var paintwork := paint(Color("#c3dad4"), 0.36, 0.25)
	var stripe := paint(Color("#519a7c"), 0.44, 0.15)
	var panel := paint(Color("#213331"), 0.44, 0.2)
	_plate(barge, PackedVector2Array([
		Vector2(-1.55, -2.98), Vector2(1.55, -2.98), Vector2(2.02, -2.27),
		Vector2(2.02, 2.22), Vector2(1.55, 2.98), Vector2(-1.55, 2.98),
		Vector2(-2.02, 2.22), Vector2(-2.02, -2.27),
	]), 0.23, 0.42, hull)
	for z in [-1.30, 1.30]:
		_mesh(barge, _cylinder_mesh, Vector3(0, 0.62, z), Vector3(1.82, 0.38, 1.82), paintwork)
		_mesh(barge, _cylinder_mesh, Vector3(0, 1.00, z), Vector3(1.63, 0.06, 1.63), stripe)
		box(barge, Vector3(0, 1.11, z), Vector3(0.37, 0.13, 0.46), panel)
	box(barge, Vector3(0, 0.55, 0), Vector3(3.47, 0.22, 0.25), stripe)
	return barge


func helicopter() -> Node3D:
	var heli := Node3D.new()
	var steel := paint(Color("#788475"), 0.59, 0.20)
	var paintwork := paint(Color("#bf8159"), 0.49, 0.20)
	var glass := paint(Color("#263b47"), 0.22, 0.26)
	_ellipsoid(heli, Vector3(0, 0, -0.20), Vector3(0.57, 0.42, 1.11), paintwork)
	_ellipsoid(heli, Vector3(0, 0.11, -0.77), Vector3(0.46, 0.35, 0.50), glass)
	box(heli, Vector3(0, -0.02, 0.91), Vector3(0.27, 0.21, 1.85), steel)
	box(heli, Vector3(0, 0.21, 1.70), Vector3(0.13, 0.43, 0.48), paintwork)
	for x in [-0.43, 0.43]:
		box(heli, Vector3(x, -0.48, 0), Vector3(0.10, 0.11, 1.58), glass)
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 0.51, -0.20)
	heli.add_child(rotor)
	for angle in [0.0, PI / 2.0]:
		var blade := box(rotor, Vector3.ZERO, Vector3(4.12, 0.035, 0.18), steel)
		blade.rotation.y = angle
	return heli


func paint(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var key := [color, roughness, metallic]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = metallic
		_materials[key] = material
	return _materials[key]


func box(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	return _mesh(parent, _box_mesh, at, dimensions, material)


func _ellipsoid(parent: Node3D, at: Vector3, radii: Vector3, material: Material) -> MeshInstance3D:
	return _mesh(parent, _sphere_mesh, at, radii * 2, material)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = dimensions
	parent.add_child(instance)
	return instance


func _plate(parent: Node3D, outline: PackedVector2Array, y: float, depth: float, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0, triangles.size(), 3):
		for j in range(3):
			var p := outline[triangles[i + j]]
			surface.add_vertex(Vector3(p.x, y, p.y))
		for j in range(2, -1, -1):
			var p := outline[triangles[i + j]]
			surface.add_vertex(Vector3(p.x, y - depth, p.y))
	if not Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var a := Vector3(p.x, y, p.y)
		var b := Vector3(q.x, y, q.y)
		var down := Vector3(0, -depth, 0)
		for vertex in [a, a + down, b, b, a + down, b + down]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	_mesh(parent, surface.commit(), Vector3.ZERO, Vector3.ONE, material)


func _scaled_outline(outline: PackedVector2Array, factor: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in outline:
		scaled.append(point * factor)
	return scaled


func _wake(parent: Node3D, stern: float) -> void:
	var wash := paint(Color("#438f92"), 0.71)
	for side in [-1.0, 1.0]:
		var ripple := box(parent, Vector3(1.14 * side, 0.035, stern), Vector3(0.16, 0.02, 3.12), wash)
		ripple.rotation.y = side * 0.24
		ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
