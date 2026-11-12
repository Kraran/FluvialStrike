extends RefCounted

const AIRCRAFT = preload("res://player_aircraft.gd")
const FUEL_DECK = preload("res://fuel_deck.svg")
const STRATOWING_NOSE := Vector3(0.0, 0.0, -2.12)

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
	return _mig29() if hostile else _stratowing()


func _mig29() -> Node3D:
	var jet := Node3D.new()
	jet.name = "MiG29"
	var grey := paint(Color("#77847d"), 0.61, 0.19)
	var green := paint(Color("#475952"), 0.66, 0.13)
	var dark := paint(Color("#303c41"), 0.58, 0.30)
	var metal := paint(Color("#566261"), 0.52, 0.48)
	var glass := paint(Color("#243e4b"), 0.22, 0.31)
	var red := paint(Color("#a9362c"), 0.62)
	var ivory := paint(Color("#f1dec1"), 0.62)

	_lathe(jet, [Vector3(-2.49, 0.012, 0.014), Vector3(-2.17, 0.15, 0.115),
		Vector3(-1.80, 0.28, 0.20)], dark)
	_lathe(jet, [Vector3(-1.80, 0.28, 0.20), Vector3(-1.38, 0.39, 0.26),
		Vector3(-0.77, 0.48, 0.28), Vector3(0.11, 0.57, 0.24),
		Vector3(0.92, 0.49, 0.21), Vector3(1.55, 0.30, 0.13),
		Vector3(1.87, 0.14, 0.055), Vector3(1.95, 0.01, 0.01)], grey)
	_ellipsoid(jet, Vector3(0, 0.22, -1.05), Vector3(0.26, 0.25, 0.58), glass)
	_ellipsoid(jet, Vector3(-0.085, 0.45, -1.11), Vector3(0.025, 0.013, 0.27), metal)

	for side in [-1.0, 1.0]:
		var wing := _mirror_outline(PackedVector2Array([
			Vector2(0.31, -1.46), Vector2(0.70, -0.67), Vector2(2.43, 0.53),
			Vector2(2.36, 0.92), Vector2(1.93, 1.02), Vector2(0.51, 0.82),
		]), side)
		_plate(jet, wing, 0.09, 0.075, grey)
		var patches := [
			PackedVector2Array([Vector2(0.23, -1.54), Vector2(0.92, -1.02),
				Vector2(1.16, -0.48), Vector2(0.94, -0.24), Vector2(0.57, -0.37), Vector2(0.26, 0.14)]),
			PackedVector2Array([Vector2(2.52, 0.23), Vector2(2.55, 1.14),
				Vector2(1.61, 1.12), Vector2(1.47, 0.85), Vector2(1.78, 0.64), Vector2(1.69, 0.21)]),
		]
		for patch: PackedVector2Array in patches:
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(wing, _mirror_outline(patch, side)):
				_plate(jet, clipped, 0.094, 0.004, green)
		_wing_star(jet, Vector2(side * 2.06, 0.74), 0.205, 0.100, ivory)
		_wing_star(jet, Vector2(side * 2.06, 0.74), 0.146, 0.104, red)
		_plate(jet, _mirror_outline(PackedVector2Array([
			Vector2(0.52, 0.98), Vector2(1.58, 1.75), Vector2(1.50, 2.04), Vector2(0.50, 1.83),
		]), side), 0.075, 0.065, green)

		_ellipsoid(jet, Vector3(side * 0.53, 0.02, 0.47), Vector3(0.34, 0.28, 1.28), grey)
		box(jet, Vector3(side * 0.50, -0.09, -0.49), Vector3(0.49, 0.24, 0.56), green)
		box(jet, Vector3(side * 0.50, -0.085, -0.779), Vector3(0.39, 0.15, 0.026), dark)
		for slot in range(4):
			box(jet, Vector3(side * 0.49, 0.252, -0.48 + slot * 0.11), Vector3(0.25, 0.019, 0.044), dark)

		var nozzle := _mesh(jet, _cylinder_mesh, Vector3(side * 0.54, 0.018, 1.72),
			Vector3(0.49, 0.52, 0.45), metal)
		nozzle.rotation.x = PI / 2.0
		_ellipsoid(jet, Vector3(side * 0.54, 0.018, 1.984), Vector3(0.197, 0.177, 0.013), dark)

		var fin := _plate(jet, PackedVector2Array([
			Vector2(0, 0.88), Vector2(0.82, 1.49), Vector2(0.85, 1.84), Vector2(0, 1.90),
		]), 0.045, 0.09, green)
		fin.position = Vector3(side * 0.66, 0.19, 0)
		fin.rotation.z = PI / 2.0 - side * 0.27

	batch_by_material(jet)
	return jet


func _mirror_outline(outline: PackedVector2Array, side: float) -> PackedVector2Array:
	for index in outline.size():
		outline[index].x *= side
	return outline


func _wing_star(jet: Node3D, center: Vector2, radius: float, height: float, material: Material) -> void:
	var outline := PackedVector2Array()
	for point in range(10):
		var angle := -PI / 2.0 + point * TAU / 10.0
		var length := radius if point % 2 == 0 else radius * 0.43
		outline.append(center + Vector2.from_angle(angle) * length)
	_plate(jet, outline, height, 0.003, material)


func player_aircraft(id: String) -> Node3D:
	id = AIRCRAFT.validated(id)
	if id == AIRCRAFT.DEFAULT:
		return _stratowing()
	var jet := Node3D.new()
	jet.name = AIRCRAFT.AIRCRAFT[id].short
	var nose: float = AIRCRAFT.AIRCRAFT[id].nose
	var rafale := id == "rafale"
	var raptor := id == "f22"
	var sukhoi := id == "su57"
	var chengdu := id == "j20"
	var shell := paint(Color("#aeb6b8") if rafale else (Color("#687680") if sukhoi else Color("#757b80")), 0.52, 0.25)
	var dark := paint(Color("#38464d"), 0.55, 0.34)
	var accent := paint(Color("#bbc2bd") if sukhoi else Color("#515b64"), 0.58, 0.16)
	var white := paint(Color("#e4e6db"), 0.49, 0.15)
	var canopy := paint(Color("#594736") if raptor else Color("#203e51"), 0.21, 0.46)
	var gleam := paint(Color("#b8c3b6"), 0.25, 0.24)
	_lathe(jet, [Vector3(nose, 0.012, 0.014), Vector3(nose + 0.25, 0.16, 0.10),
		Vector3(-1.55, 0.38, 0.19), Vector3(-0.65, 0.62 if raptor or sukhoi else 0.45, 0.22),
		Vector3(0.25, 0.74 if raptor or sukhoi else 0.53, 0.24), Vector3(1.15, 0.55, 0.17),
		Vector3(1.83, 0.36, 0.12), Vector3(2.05, 0.04, 0.04)], shell)
	_ellipsoid(jet, Vector3(0, 0.17, nose + 1.02), Vector3(0.235, 0.23, 0.58), canopy)
	_ellipsoid(jet, Vector3(-0.071, 0.386, nose + 0.98), Vector3(0.022, 0.014, 0.29), gleam)

	var outline: PackedVector2Array
	if rafale:
		outline = PackedVector2Array([Vector2(0.24, -0.74), Vector2(2.29, 0.96),
			Vector2(2.27, 1.19), Vector2(0.31, 1.31)])
	elif raptor:
		outline = PackedVector2Array([Vector2(0.46, -0.91), Vector2(2.32, 0.38),
			Vector2(2.27, 0.68), Vector2(1.28, 1.11), Vector2(0.48, 0.80)])
	elif sukhoi:
		outline = PackedVector2Array([Vector2(0.35, -1.23), Vector2(2.40, 0.58),
			Vector2(2.34, 0.96), Vector2(1.49, 1.18), Vector2(0.42, 0.90)])
	else:
		outline = PackedVector2Array([Vector2(0.53, -0.59), Vector2(2.30, 0.73),
			Vector2(2.24, 1.05), Vector2(1.82, 1.22), Vector2(0.50, 1.36)])

	for side in [-1.0, 1.0]:
		var wing := _mirror_outline(outline.duplicate(), side)
		var wing_paint := shell
		if rafale:
			wing_paint = paint(Color("#224d8c") if side < 0.0 else Color("#a43136"), 0.53, 0.18)
		_plate(jet, wing, 0.08, 0.084, wing_paint)
		var panel := PackedVector2Array([Vector2(0.28, 0.16), Vector2(1.1, 0.44), Vector2(1.34, 0.25),
			Vector2(1.76, 0.69), Vector2(2.4, 0.83), Vector2(2.4, 1.28), Vector2(0.3, 1.17)])
		var panel_paint := white if rafale else accent
		if rafale:
			panel = PackedVector2Array([Vector2(0.42, -0.67), Vector2(0.51, -0.67),
				Vector2(1.56, 1.26), Vector2(1.41, 1.31)])
		elif sukhoi:
			panel = PackedVector2Array([Vector2(1.01, -0.93), Vector2(2.5, 0.20), Vector2(2.5, 1.27),
				Vector2(1.58, 1.27), Vector2(1.58, 0.86), Vector2(1.44, 0.86), Vector2(1.44, 0.72),
				Vector2(1.34, 0.72), Vector2(1.34, 0.55), Vector2(1.19, 0.55), Vector2(1.19, 0.34),
				Vector2(1.02, 0.34)])
		for region: PackedVector2Array in Geometry2D.intersect_polygons(wing, _mirror_outline(panel, side)):
			_plate(jet, region, 0.085, 0.004, panel_paint)

		if rafale or chengdu:
			var start := -1.51 if rafale else -1.82
			_plate(jet, _mirror_outline(PackedVector2Array([Vector2(0.24, start),
				Vector2(1.05, start + 0.33), Vector2(0.92, start + 0.58), Vector2(0.29, start + 0.41)]), side),
				0.11, 0.052, wing_paint if rafale else accent)
		if not rafale:
			var tail_span := 1.57 if raptor else (1.49 if sukhoi else 1.17)
			_plate(jet, _mirror_outline(PackedVector2Array([Vector2(0.47, 1.06), Vector2(tail_span, 1.69),
				Vector2(tail_span - 0.20, 2.03), Vector2(0.42, 1.86)]), side), 0.07, 0.065, accent)

		var nacelle_x := 0.61 if sukhoi else (0.49 if raptor else 0.39)
		_ellipsoid(jet, Vector3(side * nacelle_x, 0.025, 0.73), Vector3(0.27, 0.24, 1.12), shell)
		box(jet, Vector3(side * (nacelle_x + 0.17), -0.02, -0.65), Vector3(0.32, 0.21, 0.52), dark)
		if raptor:
			box(jet, Vector3(side * nacelle_x, 0.025, 1.91), Vector3(0.46, 0.22, 0.38), dark)
		else:
			var nozzle := _mesh(jet, _cylinder_mesh, Vector3(side * nacelle_x, 0.025, 1.96),
				Vector3(0.38, 0.41, 0.38), dark)
			nozzle.rotation.x = PI / 2.0
		if not rafale:
			_player_fin(jet, side * (0.61 if sukhoi else 0.51), side, 0.72 if sukhoi else 0.87,
				1.18 if chengdu else 0.90, accent)
	if rafale:
		_player_fin(jet, 0.0, 0.0, 0.90, 0.79, white)
	batch_by_material(jet)
	return jet


func _player_fin(jet: Node3D, x: float, side: float, height: float, start: float, material: Material) -> void:
	var fin := _plate(jet, PackedVector2Array([Vector2(0, start), Vector2(height, start + 0.48),
		Vector2(height * 0.95, start + 0.80), Vector2(0, 1.90)]), 0.038, 0.075, material)
	fin.position = Vector3(x, 0.16, 0)
	fin.rotation.z = PI / 2.0 - side * 0.30


func _stratowing() -> Node3D:
	var jet := Node3D.new()
	jet.name = "StratoWing"
	var alloy := paint(Color("#c5c6bd"), 0.32, 0.72)
	var red := paint(Color("#a92c23"), 0.38, 0.24)
	var ivory := paint(Color("#ece5cf"), 0.43, 0.16)
	var seams := paint(Color("#697274"), 0.42, 0.60)
	var dark := paint(Color("#242e32"), 0.37, 0.65)
	var glass := paint(Color("#234b59"), 0.16, 0.48)
	var reflection := paint(Color("#b0d1cf"), 0.24, 0.28)

	_lathe(jet, [Vector3(STRATOWING_NOSE.z, 0.015, 0.015), Vector3(-1.98, 0.16, 0.15),
		Vector3(-1.60, 0.30, 0.27), Vector3(-1.07, 0.37, 0.33),
		Vector3(-0.35, 0.41, 0.36), Vector3(0.50, 0.43, 0.38),
		Vector3(1.12, 0.42, 0.37), Vector3(1.48, 0.35, 0.32)], alloy)
	_lathe(jet, [Vector3(1.47, 0.352, 0.322), Vector3(1.58, 0.37, 0.34),
		Vector3(1.81, 0.34, 0.31), Vector3(1.86, 0.27, 0.245),
		Vector3(1.66, 0.235, 0.215)], dark)
	_lathe(jet, [Vector3(1.54, 0.369, 0.339), Vector3(1.59, 0.372, 0.342)], alloy)
	_lathe(jet, [Vector3(0.64, 0.432, 0.382), Vector3(0.657, 0.432, 0.382)], seams)
	_lathe(jet, [Vector3(-1.58, 0.305, 0.275), Vector3(-1.565, 0.307, 0.277)], seams)
	var exhaust := paint(Color("#e2803f"), 0.6)
	exhaust.emission_enabled = true
	exhaust.emission = Color("#a74013")
	_ellipsoid(jet, Vector3(0, 0, 1.68), Vector3(0.235, 0.214, 0.018), exhaust)

	var bubble := SphereMesh.new()
	bubble.radial_segments = 32
	bubble.rings = 16
	_mesh(jet, bubble, Vector3(0, 0.34, -0.99), Vector3(0.53, 0.43, 1.12), glass)
	_ellipsoid(jet, Vector3(-0.12, 0.51, -1.09), Vector3(0.025, 0.018, 0.33), reflection)
	box(jet, Vector3(0, 0.36, -0.45), Vector3(0.44, 0.13, 0.045), alloy)
	_plate(jet, PackedVector2Array([Vector2(-0.12, -0.36), Vector2(0.12, -0.36),
		Vector2(0.09, 1.12), Vector2(-0.09, 1.12)]), 0.385, 0.018, red)

	for side in [-1.0, 1.0]:
		_plate(jet, PackedVector2Array([Vector2(0.31 * side, -0.66),
			Vector2(2.43 * side, 0.72), Vector2(2.40 * side, 1.12),
			Vector2(1.93 * side, 1.06), Vector2(0.38 * side, 0.50)]), 0.02, 0.065, red)
		_plate(jet, PackedVector2Array([Vector2(0.32 * side, -0.66),
			Vector2(2.43 * side, 0.72), Vector2(2.425 * side, 0.79),
			Vector2(0.32 * side, -0.54)]), 0.025, 0.012, alloy)
		_plate(jet, PackedVector2Array([Vector2(2.16 * side, 0.55),
			Vector2(2.30 * side, 0.64), Vector2(2.27 * side, 1.10),
			Vector2(2.13 * side, 1.085)]), 0.027, 0.012, ivory)
		_plate(jet, PackedVector2Array([Vector2(0.30 * side, 1.03),
			Vector2(1.16 * side, 1.56), Vector2(1.10 * side, 1.91),
			Vector2(0.26 * side, 1.69)]), 0.08, 0.055, alloy)
		_plate(jet, PackedVector2Array([Vector2(0.75 * side, 1.31),
			Vector2(1.16 * side, 1.56), Vector2(1.10 * side, 1.91),
			Vector2(0.70 * side, 1.80)]), 0.085, 0.012, red)
		box(jet, Vector3(side * 1.44, -0.13, 0.35), Vector3(0.065, 0.20, 0.22), dark)
		_ellipsoid(jet, Vector3(side * 1.44, -0.26, 0.39), Vector3(0.105, 0.105, 0.53), alloy)

	var fin := _plate(jet, PackedVector2Array([Vector2(0.27, 0.65),
		Vector2(1.18, 1.46), Vector2(1.20, 1.72), Vector2(0.18, 1.76)]), 0.045, 0.09, red)
	fin.rotation.z = PI / 2.0
	for face in [-1.0, 1.0]:
		var marking := _plate(jet, PackedVector2Array([Vector2(0.30, 1.19),
			Vector2(0.77, 1.48), Vector2(0.77, 1.59), Vector2(0.26, 1.62)]),
			face * 0.047, 0.002, ivory)
		marking.rotation.z = PI / 2.0
	batch_by_material(jet)
	return jet


func _lathe(parent: Node3D, profile: Array[Vector3], material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(profile.size() - 1):
		var a := profile[ring]
		var b := profile[ring + 1]
		for segment in range(32):
			var angle := segment * TAU / 32.0
			var next := (segment + 1) * TAU / 32.0
			var p := Vector3(cos(angle) * a.y, sin(angle) * a.z, a.x)
			var q := Vector3(cos(next) * a.y, sin(next) * a.z, a.x)
			var r := Vector3(cos(angle) * b.y, sin(angle) * b.z, b.x)
			var s := Vector3(cos(next) * b.y, sin(next) * b.z, b.x)
			for vertex in [p, r, q, q, r, s]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	surface.index()
	_mesh(parent, surface.commit(), Vector3.ZERO, Vector3.ONE, material)


func batch_by_material(parent: Node3D) -> void:
	var surfaces := {}
	for part: MeshInstance3D in parent.get_children():
		var material := part.material_override
		if not surfaces.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[material] = surface
		surfaces[material].append_from(part.mesh, 0, part.transform)
		part.free()
	for material: Material in surfaces:
		var surface: SurfaceTool = surfaces[material]
		surface.generate_normals()
		surface.index()
		_mesh(parent, surface.commit(), Vector3.ZERO, Vector3.ONE, material)


func tanker() -> Node3D:
	var ship := Node3D.new()
	var hull := paint(Color("#854739"), 0.69, 0.22)
	var deck := paint(Color("#4b5754"), 0.70, 0.13)
	var ivory := paint(Color("#bfba9f"), 0.55, 0.14)
	var glass := paint(Color("#283b40"), 0.28, 0.24)
	var pipe := paint(Color("#93988d"), 0.51, 0.30)
	var rust := paint(Color("#9c6042"), 0.65, 0.15)
	var outline := PackedVector2Array([
		Vector2(0, -4.55), Vector2(0.56, -4.07), Vector2(1.04, -3.20),
		Vector2(1.18, 3.40), Vector2(0.88, 4.22), Vector2(0.55, 4.42),
		Vector2(-0.55, 4.42), Vector2(-0.88, 4.22), Vector2(-1.18, 3.40),
		Vector2(-1.04, -3.20), Vector2(-0.56, -4.07),
	])
	_plate(ship, outline, 0.56, 0.74, hull)
	_plate(ship, _scaled_outline(outline, 0.925), 0.585, 0.030, deck)

	for z in [-2.45, -1.10, 0.25, 1.60]:
		box(ship, Vector3(0, 0.65, z), Vector3(1.34, 0.13, 0.91), rust)
		box(ship, Vector3(0, 0.724, z), Vector3(1.14, 0.043, 0.70), ivory)
		box(ship, Vector3(0, 0.76, z + 0.20), Vector3(0.35, 0.060, 0.15), deck)
	for side in [-1.0, 1.0]:
		box(ship, Vector3(side * 0.81, 0.672, -0.36), Vector3(0.071, 0.084, 5.11), pipe)
		for z in [-2.83, -0.81, 1.34]:
			box(ship, Vector3(side * 0.76, 0.628, z), Vector3(0.25, 0.088, 0.10), pipe)
		for z in [-3.46, 3.96]:
			_mesh(ship, _cylinder_mesh, Vector3(side * 0.42, 0.64, z), Vector3(0.13, 0.17, 0.13), glass)

	box(ship, Vector3(0, 0.87, 3.02), Vector3(1.70, 0.58, 1.40), ivory)
	box(ship, Vector3(0, 1.17, 2.84), Vector3(1.72, 0.19, 1.06), glass)
	box(ship, Vector3(0, 1.30, 2.84), Vector3(1.82, 0.10, 1.16), ivory)
	box(ship, Vector3(0, 1.51, 2.94), Vector3(0.075, 0.34, 0.075), pipe)
	box(ship, Vector3(0, 1.69, 2.94), Vector3(0.58, 0.059, 0.080), ivory)
	box(ship, Vector3(0.52, 1.36, 3.59), Vector3(0.29, 0.48, 0.28), hull)
	box(ship, Vector3(0.52, 1.60, 3.59), Vector3(0.30, 0.10, 0.29), glass)
	box(ship, Vector3(0, 0.67, -3.67), Vector3(0.38, 0.17, 0.29), pipe)

	batch_by_material(ship)
	_wake(ship, 4.12)
	ship.rotation.y = -PI / 2.0
	return ship


func launcher_truck() -> Node3D:
	var truck := Node3D.new()
	truck.name = "LauncherTruck"
	var olive := paint(Color("#727d54"), 0.75)
	var dark := paint(Color("#323932"), 0.83)
	var rack := paint(Color("#a69c76"), 0.71)
	var glass := paint(Color("#354a50"), 0.28)
	box(truck, Vector3(0, 0.36, 0), Vector3(1.76, 0.38, 4.58), dark)
	box(truck, Vector3(0, 0.81, -1.48), Vector3(1.71, 0.94, 1.42), olive)
	box(truck, Vector3(0, 1.12, -1.90), Vector3(1.47, 0.26, 0.15), glass)
	box(truck, Vector3(0, 0.73, 0.80), Vector3(1.72, 0.27, 2.70), olive)
	for z in [-1.55, 0.69, 1.62]:
		for x in [-0.88, 0.88]:
			var wheel := _mesh(truck, _cylinder_mesh, Vector3(x, 0.36, z),
				Vector3(0.66, 0.29, 0.66), dark)
			wheel.rotation.z = PI / 2.0
	for x in [-0.49, 0, 0.49]:
		var canister := box(truck, Vector3(x, 1.04, 0.68), Vector3(0.38, 0.39, 2.53), rack)
		canister.rotation.x = -0.17
	batch_by_material(truck)
	return truck


func launch_platform() -> Node3D:
	var site := Node3D.new()
	site.name = "LaunchPlatform"
	var concrete := paint(Color("#aaa493"), 0.91)
	var platform := paint(Color("#4d5955"), 0.76)
	var marker := paint(Color("#d2a85b"), 0.74)
	box(site, Vector3(0, 0.02, 0), Vector3(6.5, 0.10, 6.8), concrete)
	box(site, Vector3(0, 0.33, 0.67), Vector3(3.6, 0.58, 3.7), platform)
	for x in [-0.80, 0.80]:
		var rail := box(site, Vector3(x, 1.27, 0.08), Vector3(0.28, 0.23, 4.7), platform)
		rail.rotation.x = 0.45
		box(site, Vector3(x, 0.78, -1.24), Vector3(0.23, 1.17, 0.28), platform)
	for x in [-2.51, 2.51]:
		box(site, Vector3(x, 0.09, 0), Vector3(0.18, 0.04, 5.56), marker)
	batch_by_material(site)
	return site


func moored_airship() -> Node3D:
	var airship := Node3D.new()
	airship.name = "MooredAirship"
	var fabric := paint(Color("#a4a08f"), 0.86)
	var trim := paint(Color("#6e817b"), 0.67)
	var frame := paint(Color("#4b524c"), 0.74)
	_ellipsoid(airship, Vector3(0, 3.90, 0), Vector3(1.55, 1.08, 4.10), fabric)
	_ellipsoid(airship, Vector3(0, 2.89, -0.60), Vector3(0.48, 0.27, 0.96), frame)
	_plate(airship, PackedVector2Array([Vector2(-0.63, 2.49), Vector2(0.63, 2.49),
		Vector2(1.36, 3.45), Vector2(1.32, 3.93), Vector2(-1.32, 3.93), Vector2(-1.36, 3.45)]),
		3.90, 0.085, trim)
	var rudder := box(airship, Vector3(0, 4.58, 3.10), Vector3(0.10, 0.65, 1.34), trim)
	rudder.rotation.x = 0.29
	box(airship, Vector3(0, 1.45, -3.93), Vector3(0.10, 2.88, 0.10), frame)
	box(airship, Vector3(0, 0.10, -3.93), Vector3(1.20, 0.17, 0.82), frame)
	batch_by_material(airship)
	return airship


func fuel_barge() -> Node3D:
	var barge := Node3D.new()
	var hull := paint(Color("#353d42"), 0.70, 0.25)
	var steel := paint(Color("#60676a"), 0.61, 0.34)
	var fittings := paint(Color("#2f3639"), 0.58, 0.31)
	var safety := paint(Color("#d69d32"), 0.61, 0.12)
	_plate(barge, PackedVector2Array([
		Vector2(-1.55, -2.98), Vector2(1.55, -2.98), Vector2(2.02, -2.27),
		Vector2(2.02, 2.22), Vector2(1.55, 2.98), Vector2(-1.55, 2.98),
		Vector2(-2.02, 2.22), Vector2(-2.02, -2.27),
	]), 0.23, 0.42, hull)
	var tank := PackedVector2Array([
		Vector2(-0.91, -0.94), Vector2(0.91, -0.94), Vector2(1.32, -0.54),
		Vector2(1.32, 0.54), Vector2(0.91, 0.94), Vector2(-0.91, 0.94),
		Vector2(-1.32, 0.54), Vector2(-1.32, -0.54),
	])
	for z in [-1.63, 1.63]:
		_plate(barge, tank.duplicate(), 0.56, 0.33, fittings).position.z = z
		_plate(barge, _scaled_outline(tank, 0.88), 0.96, 0.41, steel).position.z = z
		_mesh(barge, _cylinder_mesh, Vector3(0, 1.01, z), Vector3(0.66, 0.12, 0.66), fittings)
		for side in [-1.0, 1.0]:
			box(barge, Vector3(side * 0.78, 0.97, z), Vector3(0.11, 0.05, 1.35), fittings)
			box(barge, Vector3(side * 1.68, 0.29, z), Vector3(0.13, 0.12, 0.93), safety)
	var deck := StandardMaterial3D.new()
	deck.albedo_texture = FUEL_DECK
	deck.roughness = 0.64
	deck.metallic = 0.12
	box(barge, Vector3(0, 0.60, 0), Vector3(3.74, 0.27, 1.30), deck)
	batch_by_material(barge)
	return barge


func helicopter() -> Node3D:
	var heli := Node3D.new()
	var olive := paint(Color("#6b7652"), 0.68, 0.18)
	var trim := paint(Color("#37433d"), 0.65, 0.17)
	var glass := paint(Color("#233e48"), 0.24, 0.28)
	var metal := paint(Color("#687471"), 0.44, 0.43)
	var marking := paint(Color("#d7a34d"), 0.62)

	_lathe(heli, [Vector3(-1.45, 0.075, 0.085), Vector3(-1.31, 0.34, 0.27),
		Vector3(-0.92, 0.51, 0.38), Vector3(-0.36, 0.60, 0.41),
		Vector3(0.45, 0.57, 0.39), Vector3(0.85, 0.43, 0.28),
		Vector3(1.04, 0.24, 0.17), Vector3(1.06, 0.02, 0.02)], olive)
	_ellipsoid(heli, Vector3(0, 0.16, -0.88), Vector3(0.48, 0.28, 0.52), glass)
	box(heli, Vector3(0, 0.424, -0.89), Vector3(0.032, 0.035, 0.36), trim)
	for side in [-1.0, 1.0]:
		_ellipsoid(heli, Vector3(side * 0.28, 0.31, 0.21), Vector3(0.235, 0.23, 0.54), trim)
		_ellipsoid(heli, Vector3(side * 0.29, 0.40, 0.60), Vector3(0.135, 0.12, 0.18), metal)
		box(heli, Vector3(side * 0.43, 0.299, -0.25), Vector3(0.115, 0.025, 0.43), marking)
		for z in [-0.53, 0.46]:
			box(heli, Vector3(side * 0.38, -0.34, z), Vector3(0.34, 0.09, 0.08), metal)
		box(heli, Vector3(side * 0.56, -0.48, -0.07), Vector3(0.073, 0.075, 1.86), trim)
		var skid_tip := box(heli, Vector3(side * 0.56, -0.432, -1.01), Vector3(0.073, 0.075, 0.29), trim)
		skid_tip.rotation.x = -0.30

	_lathe(heli, [Vector3(0.76, 0.24, 0.17), Vector3(1.16, 0.18, 0.135),
		Vector3(2.26, 0.082, 0.08), Vector3(2.37, 0.037, 0.045)], olive)
	_plate(heli, PackedVector2Array([Vector2(-0.69, 1.62), Vector2(0.69, 1.62),
		Vector2(0.61, 1.97), Vector2(-0.61, 1.97)]), 0.065, 0.06, olive)
	var fin := _plate(heli, PackedVector2Array([Vector2(0, 1.88), Vector2(0.45, 2.25),
		Vector2(0.45, 2.48), Vector2(0, 2.35)]), 0.035, 0.07, trim)
	fin.rotation.z = PI / 2.0
	_ellipsoid(heli, Vector3(0, 0.55, -0.12), Vector3(0.13, 0.18, 0.13), metal)
	batch_by_material(heli)

	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 0.70, -0.12)
	heli.add_child(rotor)
	for index in range(4):
		var angle := index * PI / 2.0
		var direction := Vector3(cos(angle), 0, -sin(angle))
		var blade := box(rotor, direction * 1.03, Vector3(1.91, 0.028, 0.13), trim)
		blade.rotation.y = angle
		var tip := box(rotor, direction * 1.91 + Vector3.UP * 0.016, Vector3(0.16, 0.009, 0.125), marking)
		tip.rotation.y = angle
	batch_by_material(rotor)
	for part: MeshInstance3D in rotor.get_children():
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sweep := PlaneMesh.new()
	sweep.size = Vector2(4.04, 4.04)
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://flight_glow.gdshader")
	blur.set_shader_parameter("shape", 1)
	blur.set_shader_parameter("tint", Color(0.66, 0.71, 0.67, 0.16))
	var sweep_mesh := _mesh(rotor, sweep, Vector3.DOWN * 0.025, Vector3.ONE, blur)
	sweep_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var tail_rotor := Node3D.new()
	tail_rotor.name = "TailRotor"
	tail_rotor.position = Vector3(0.09, 0.28, 2.33)
	heli.add_child(tail_rotor)
	box(tail_rotor, Vector3.ZERO, Vector3(0.025, 0.61, 0.067), metal)
	box(tail_rotor, Vector3.ZERO, Vector3(0.026, 0.067, 0.61), metal)
	batch_by_material(tail_rotor)
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


func _plate(parent: Node3D, outline: PackedVector2Array, y: float, depth: float, material: Material) -> MeshInstance3D:
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
	surface.index()
	return _mesh(parent, surface.commit(), Vector3.ZERO, Vector3.ONE, material)


func _scaled_outline(outline: PackedVector2Array, factor: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in outline:
		scaled.append(point * factor)
	return scaled


func _wake(parent: Node3D, stern: float) -> void:
	var surface := PlaneMesh.new()
	surface.size = Vector2(5.5, 6.4)
	var material := ShaderMaterial.new()
	material.shader = preload("res://tanker_wake.gdshader")
	var wake := _mesh(parent, surface, Vector3(0, 0.049, stern + surface.size.y * 0.5),
		Vector3.ONE, material)
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
