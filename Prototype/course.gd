extends RefCounted

const EXTENSION = preload("res://course_extension.gd")
const PROFILES = preload("res://course_profiles.gd")
const REFERENCE_END := 1546
const LEGACY_END := 9310
const LEGACY_BRIDGES := 9
const SECTION_LENGTH := 1024
const MAX_SCORE := 1000000
const BRIDGE_COUNT := MAX_SCORE / 500
const END := BRIDGE_COUNT * SECTION_LENGTH + 94
const CONTINUATION_START := 9497
const TARGET_BYTES := 6
const TARGET_KINDS := {4: "jet", 5: "helicopter", 6: "helicopter", 7: "tanker", 10: "fuel"}
const TARGET_CENTERS := {4: 3.5, 5: 3.5, 6: 3.5, 7: 8.5, 10: 3.0}

# Little-endian terrain byte count (u32), then one profile ID per two scanlines.
# Each following target is twice its distance (u32), native X (u8), and kind/direction (u8).
static var _continuation := FileAccess.get_file_as_bytes("res://course_blocks.bin")
static var _target_offset := 4 + _continuation.decode_u32(0)
static var _extra_targets := (_continuation.size() - _target_offset) / TARGET_BYTES

# Start distance and playable water intervals in the cropped Stella coordinate system.
const BANKS := [
	[-170, [64, 96]], [49, [60, 100]], [51, [56, 104]], [53, [52, 108]],
	[55, [48, 112]], [57, [44, 116]],
	[985, [48, 112]], [987, [52, 108]], [989, [56, 104]], [991, [60, 100]],
	[993, [64, 96]], [1075, [60, 100]], [1077, [56, 104]], [1079, [52, 108]],
	[1081, [48, 112]], [1143, [44, 116]], [1145, [40, 120]], [1177, [44, 116]],
	[1179, [48, 112]], [1263, [44, 116]], [1265, [40, 120]], [1267, [36, 124]],
	[1269, [32, 128]], [1271, [28, 132]], [1273, [24, 136]],
	[1335, [20, 140]], [1337, [16, 144]],
	[1369, [16, 76, 84, 144]], [1371, [16, 72, 88, 144]],
	[1463, [16, 76, 84, 144]], [1465, [16, 144]],
	[1497, [20, 140]], [1499, [24, 136]], [1501, [28, 132]], [1503, [32, 128]],
	[1505, [36, 124]], [1507, [40, 120]], [1509, [44, 116]], [1512, [48, 112]],
	[1585, [44, 116]], [1587, [40, 120]], [1589, [36, 124]], [1591, [32, 128]],
	[1593, [28, 132]], [1653, [24, 136]], [1655, [20, 140]], [1657, [16, 144]],
	[1689, [16, 76, 84, 144]], [1691, [16, 72, 88, 144]],
	[1693, [16, 68, 92, 144]], [1695, [16, 64, 96, 144]],
	[1697, [16, 60, 100, 144]], [1699, [16, 56, 104, 144]],
	[1701, [16, 52, 108, 144]], [1704, [16, 48, 112, 144]],
] + EXTENSION.BANKS

# Kind, center X, distance. Moving enemies add a drift origin and slope.
const TARGETS := [
	["tanker", 79.5, 67.5], ["fuel", 94, 102],
	["helicopter", 69.5, 133], ["fuel", 84, 166], ["fuel", 103, 198],
	["fuel", 89, 326], ["helicopter", 60.5, 357], ["fuel", 66, 390],
	["helicopter", 77.5, 421], ["fuel", 99, 454], ["tanker", 99.5, 515.5],
	["helicopter", 94.5, 549], ["tanker", 74.5, 579.5], ["fuel", 84, 614],
	["helicopter", 103.5, 645], ["helicopter", 100.5, 773],
	["tanker", 99.5, 835.5], ["helicopter", 96.5, 869],
	["fuel", 92, 934], ["helicopter", 66.5, 965],
	["tanker", 78.5, 995.5], ["tanker", 94.5, 1091.5],
	["tanker", 102.5, 1155.5, Vector2(1090, -0.22)], ["helicopter", 99.5, 1189],
	["fuel", 100, 1222], ["helicopter", 61, 1254], ["fuel", 124, 1318],
	["helicopter", 27.5, 1349], ["fuel", 60, 1385.5], ["tanker", 54.5, 1411.5],
	["tanker", 104.5, 1443.5], ["helicopter", 27.5, 1477],
	["fuel", 59, 1512], ["tanker", 64.5, 1539.5],
	["tanker", 94.5, 1571.5, Vector2(1500, -0.14)],
	["fuel", 132, 1670], ["helicopter", 35.5, 1701, Vector2(1560, -0.09)],
	["fuel", 36, 1734],
] + EXTENSION.TARGETS


static func is_water(distance: int, left: int, right: int) -> bool:
	var spans := water_spans(distance)
	for j in range(0, spans.size(), 2):
		if left >= spans[j] and right <= spans[j + 1]:
			return true
	return false


static func water_spans(distance: float) -> Array:
	if distance >= CONTINUATION_START:
		var row := mini(floori((distance - CONTINUATION_START) * 0.5), _target_offset - 5)
		return PROFILES.SPANS[_continuation[4 + row]]
	var low := 0
	var high := BANKS.size()
	while low < high:
		var middle := (low + high) >> 1
		if BANKS[middle][0] <= distance:
			low = middle + 1
		else:
			high = middle
	return BANKS[maxi(low - 1, 0)][1]


static func first_target(distance: float) -> int:
	var low := 0
	var high := TARGETS.size()
	if distance > TARGETS[-1][2]:
		low = high
		high += _extra_targets
	while low < high:
		var middle := (low + high) >> 1
		if _target_distance(middle) < distance:
			low = middle + 1
		else:
			high = middle
	return low


static func bridge(index: int) -> Vector2i:
	var start := index * SECTION_LENGTH + 1018
	return Vector2i(start, start + 24)


static func _target_distance(index: int) -> float:
	if index < TARGETS.size():
		return TARGETS[index][2]
	return _continuation.decode_u32(_target_offset + (index - TARGETS.size()) * TARGET_BYTES) * 0.5


static func target(index: int) -> Array:
	if index < TARGETS.size():
		return TARGETS[index]
	var offset := _target_offset + (index - TARGETS.size()) * TARGET_BYTES
	var flags := _continuation[offset + 5]
	var kind := flags & 15
	return [TARGET_KINDS[kind], _continuation[offset + 4] + TARGET_CENTERS[kind],
		_continuation.decode_u32(offset) * 0.5, -1 if flags & 16 else 1]
