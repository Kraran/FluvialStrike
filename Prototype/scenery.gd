extends RefCounted

const REGION_LENGTH := 3 * COURSE.SECTION_LENGTH
const REGION_BLEND := 480.0
const TOWN_WEIGHTS := Vector4(0.0, 0.48, 0.12, 0.24)
const ROCK_WEIGHTS := Vector4(0.0, 0.08, 0.48, 0.23)


static func region_weights(distance: float) -> Vector2:
	var block := maxi(0, floori(distance / REGION_LENGTH))
	var current := block % 4
	var previous := (maxi(0, block - 1)) % 4
	var blend := smoothstep(0.0, REGION_BLEND, distance - block * REGION_LENGTH)
	return Vector2(lerpf(TOWN_WEIGHTS[previous], TOWN_WEIGHTS[current], blend),
		lerpf(ROCK_WEIGHTS[previous], ROCK_WEIGHTS[current], blend))

const COURSE = preload("res://course.gd")
const FIRST_ROW := -192
const MAP_WIDTH := 153
const MAP_HEIGHT := (COURSE.LEGACY_END + 240 - FIRST_ROW) / 2 + 1

var first_row := FIRST_ROW
var shore_image: Image
var shore_texture: ImageTexture
var _sphere := SphereMesh.new()
var _box := BoxMesh.new()
var _trunk := CylinderMesh.new()
var _trees := {}
var _buildings := {}
var _shrub_mesh: ArrayMesh


func _init() -> void:
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_trunk.radial_segments = 8
	_trunk.rings = 1
	_trunk.height = 1.0


func build_shore_map(from: int = FIRST_ROW, to: int = COURSE.LEGACY_END + 240) -> void:
	first_row = from
	var height := (to - from) / 2 + 1
	var profile_ids := {}
	var scanlines: Array[PackedByteArray] = []
	var row_ids := PackedInt32Array()
	for row in height:
		var spans := COURSE.water_spans(from + row * 2)
		if not profile_ids.has(spans):
			profile_ids[spans] = scanlines.size()
			scanlines.append(_shore_scanline(spans))
		row_ids.append(profile_ids[spans])
	var smooth := PackedByteArray()
	var filtered := {}
	for row in height:
		var neighbors := [row_ids[maxi(row - 2, 0)], row_ids[maxi(row - 1, 0)], row_ids[row],
			row_ids[mini(row + 1, height - 1)], row_ids[mini(row + 2, height - 1)]]
		if not filtered.has(neighbors):
			filtered[neighbors] = _blend_scanlines(scanlines, neighbors)
		smooth.append_array(filtered[neighbors])
	shore_image = Image.create_from_data(MAP_WIDTH, height, false, Image.FORMAT_R8, smooth)
	shore_texture = ImageTexture.create_from_image(shore_image)


func _blend_scanlines(scanlines: Array[PackedByteArray], neighbors: Array) -> PackedByteArray:
	var a := scanlines[neighbors[0]]
	var b := scanlines[neighbors[1]]
	var c := scanlines[neighbors[2]]
	var d := scanlines[neighbors[3]]
	var e := scanlines[neighbors[4]]
	var line := PackedByteArray()
	line.resize(MAP_WIDTH)
	for column in MAP_WIDTH:
		line[column] = (a[column] + 4 * b[column] + 6 * c[column] + 4 * d[column] + e[column] + 8) >> 4
	return line


func _shore_scanline(spans: Array) -> PackedByteArray:
	var line := PackedByteArray()
	line.resize(MAP_WIDTH)
	for column in MAP_WIDTH:
		var x := float(column + 8)
		var nearest := INF
		var wet := false
		for i in range(0, spans.size(), 2):
			nearest = minf(nearest, minf(absf(x - spans[i]), absf(x - spans[i + 1])))
			wet = wet or (x >= spans[i] and x <= spans[i + 1])
		var signed_distance := -nearest if wet else nearest
		line[column] = roundi(clampf(0.5 + signed_distance / 12.0, 0.0, 1.0) * 255)
	return line


func shore_distance(x: float, distance: float) -> float:
	var world_z := -distance * 0.3
	var warp := (sin(world_z * 0.11) * 0.45 + sin(world_z * 0.47) * 0.12) / 0.6
	var u := clampf(x - 8.0 + warp, 0.0, MAP_WIDTH - 1.001)
	var v := clampf((distance - first_row) * 0.5, 0.0, shore_image.get_height() - 1.001)
	var column := floori(u)
	var row := floori(v)
	var top := lerpf(shore_image.get_pixel(column, row).r,
		shore_image.get_pixel(column + 1, row).r, u - column)
	var bottom := lerpf(shore_image.get_pixel(column, row + 1).r,
		shore_image.get_pixel(column + 1, row + 1).r, u - column)
	return (lerpf(top, bottom, v - row) - 0.5) * 12.0


func tree(kind: int) -> ArrayMesh:
	if _trees.has(kind):
		return _trees[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.29, 0.22, 0.13, 0.0)
	_piece(surface, _trunk, Vector3(0, 0.85, 0), Vector3(0.19, 1.7, 0.19), bark)
	if kind == 1:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.015
		cone.bottom_radius = 0.5
		cone.height = 1.0
		cone.radial_segments = 12
		cone.rings = 1
		for tier in range(4):
			var width := 2.05 - tier * 0.43
			_piece(surface, cone, Vector3(0, 1.02 + tier * 0.58, 0),
				Vector3(width, 1.24, width), Color("#385647").lightened(tier * 0.035))
	elif kind == 2:
		_piece(surface, _trunk, Vector3(0, 1.16, 0), Vector3(0.15, 2.32, 0.15), Color(0.70, 0.68, 0.52, 0))
		for lobe in range(3):
			_piece(surface, _sphere, Vector3(sin(lobe * 2.4) * 0.34, 1.78 + lobe * 0.35, cos(lobe * 2.4) * 0.30),
				Vector3(1.32, 1.35, 1.22), Color("#819451").darkened(lobe * 0.045))
	else:
		_piece(surface, _sphere, Vector3(-0.38, 1.88, 0.14), Vector3(1.94, 1.54, 1.88), Color("#506e3d"))
		_piece(surface, _sphere, Vector3(0.48, 2.02, -0.21), Vector3(1.86, 1.72, 1.82), Color("#657d42"))
		_piece(surface, _sphere, Vector3(0.13, 2.65, 0.10), Vector3(1.39, 1.14, 1.46), Color("#6d8348"))
	surface.index()
	_trees[kind] = surface.commit()
	return _trees[kind]


func shrub() -> ArrayMesh:
	if _shrub_mesh:
		return _shrub_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lobe in range(3):
		_piece(surface, _sphere, Vector3(sin(lobe * 2.4) * 0.33, 0.39 + lobe * 0.04, cos(lobe * 2.4) * 0.26),
			Vector3(0.86, 0.83, 0.81), Color("#727d43").darkened(lobe * 0.055))
	surface.index()
	_shrub_mesh = surface.commit()
	return _shrub_mesh


func ridge() -> ArrayMesh:
	var outline := PackedVector2Array([
		Vector2(-0.54, -0.23), Vector2(-0.30, -0.55), Vector2(0.23, -0.49),
		Vector2(0.51, -0.12), Vector2(0.37, 0.46), Vector2(-0.24, 0.53),
	])
	var shoulder := [0.48, 0.55, 0.69, 0.57, 0.43, 0.39]
	var peak := Vector3(-0.13, 1.0, 0.09)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in outline.size():
		var next := (i + 1) % outline.size()
		var a := outline[i]
		var b := outline[next]
		var foot_a := Vector3(a.x, 0.0, a.y)
		var foot_b := Vector3(b.x, 0.0, b.y)
		var ledge_a := Vector3(a.x * 0.76 - 0.07, shoulder[i], a.y * 0.79 + 0.02)
		var ledge_b := Vector3(b.x * 0.76 - 0.07, shoulder[next], b.y * 0.79 + 0.02)
		for vertex in [foot_a, foot_b, ledge_a, foot_b, ledge_b, ledge_a, ledge_a, ledge_b, peak]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	surface.index()
	return surface.commit()


func building(kind: int) -> ArrayMesh:
	if _buildings.has(kind):
		return _buildings[kind]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color("#d0c3a1") if kind == 0 else Color("#aeb5aa")
	var roof := Color("#9b5744") if kind == 0 else Color("#42545c")
	var glass := Color("#273e47")
	var width := 2.2 if kind == 0 else 3.3
	var depth := 2.9 if kind == 0 else 4.2
	_piece(surface, _box, Vector3(0, 0.025, 0), Vector3(width + 0.8, 0.05, depth + 0.8), Color("#a69d7d"))
	_piece(surface, _box, Vector3(0, 0.70, 0), Vector3(width, 1.4, depth), wall)
	if kind < 2:
		var ridge := 2.05 if kind == 0 else 1.95
		_roof(surface, width * 0.5 + 0.16, depth * 0.5 + 0.17, 1.4, ridge, roof)
		_piece(surface, _box, Vector3(width * 0.25, 1.94, 0.38), Vector3(0.28, 0.59, 0.30), Color("#866c59"))
	else:
		_piece(surface, _box, Vector3(0, 1.46, 0), Vector3(width + 0.18, 0.13, depth + 0.18), roof)
		for z in [-0.9, 0.9]:
			_piece(surface, _box, Vector3(0, 1.64, z), Vector3(0.86, 0.25, 0.47), Color("#9da39b"))
	for side in [-1.0, 1.0]:
		for z in [-0.77, 0.77]:
			_piece(surface, _box, Vector3(side * (width * 0.5 + 0.008), 0.88, z), Vector3(0.025, 0.40, 0.51), glass)
	_piece(surface, _box, Vector3(0, 0.50, depth * 0.5 + 0.012), Vector3(0.53, 1.0, 0.027), Color("#605c4c"))
	for x in [-0.63, 0.63]:
		_piece(surface, _box, Vector3(x, 0.93, -depth * 0.5 - 0.012), Vector3(0.43, 0.40, 0.027), glass)
	surface.index()
	_buildings[kind] = surface.commit()
	return _buildings[kind]


func _piece(surface: SurfaceTool, mesh: Mesh, center: Vector3, size: Vector3, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(color)
		surface.set_normal((normals[index] / size).normalized())
		surface.add_vertex(vertices[index] * size + center)


func _roof(surface: SurfaceTool, half_width: float, half_depth: float, base: float, ridge: float, color: Color) -> void:
	var vertices := PackedVector3Array([
		Vector3(-half_width, base, -half_depth), Vector3(half_width, base, -half_depth),
		Vector3(0, ridge, -half_depth), Vector3(-half_width, base, half_depth),
		Vector3(half_width, base, half_depth), Vector3(0, ridge, half_depth),
	])
	for triangle in [[0, 1, 2], [3, 5, 4], [0, 2, 3], [2, 5, 3], [1, 4, 2], [2, 4, 5]]:
		var a := vertices[triangle[0]]
		var b := vertices[triangle[1]]
		var c := vertices[triangle[2]]
		var normal := (c - a).cross(b - a).normalized()
		for vertex in [a, b, c]:
			surface.set_color(color)
			surface.set_normal(normal)
			surface.add_vertex(vertex)
