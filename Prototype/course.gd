extends RefCounted

const EXTENSION = preload("res://course_extension.gd")
const REFERENCE_END := 1546
const END := 9310
const BRIDGES := [
	Vector2i(1018, 1042), Vector2i(2042, 2066), Vector2i(3066, 3090),
	Vector2i(4090, 4114), Vector2i(5114, 5138), Vector2i(6138, 6162),
	Vector2i(7162, 7186), Vector2i(8186, 8210), Vector2i(9210, 9234),
]

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
	while low < high:
		var middle := (low + high) >> 1
		if TARGETS[middle][2] < distance:
			low = middle + 1
		else:
			high = middle
	return low
