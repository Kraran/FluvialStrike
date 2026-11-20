extends RefCounted
## Petits drapeaux des langues proposées, dessinés point par point (sans fichier image) :
## chaque drapeau est calculé une fois, lissé par sur-échantillonnage, puis gardé en mémoire.

const WIDTH := 30
const HEIGHT := 20
const SAMPLES := 3
const BORDER := Color(0.0, 0.0, 0.0, 0.35)

static var _cache := {}


## Texture du drapeau de la langue (code « fr », « en »…), ou null si la langue n'en a pas.
static func texture(code: String) -> Texture2D:
	if _cache.has(code):
		return _cache[code]
	var result: Texture2D = null
	if code in ["en", "fr", "es", "da", "de", "it", "nl", "no", "pl", "pt", "ru", "sv", "tr"]:
		var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
		for py in HEIGHT:
			for px in WIDTH:
				var sum := Color(0, 0, 0, 0)
				for sy in SAMPLES:
					for sx in SAMPLES:
						var u := (px + (sx + 0.5) / SAMPLES) / WIDTH
						var v := (py + (sy + 0.5) / SAMPLES) / HEIGHT
						sum += color_at(code, u, v)
				var pixel := sum / float(SAMPLES * SAMPLES)
				if px == 0 or py == 0 or px == WIDTH - 1 or py == HEIGHT - 1:
					pixel = pixel.blend(BORDER)
				image.set_pixel(px, py, pixel)
		result = ImageTexture.create_from_image(image)
	_cache[code] = result
	return result


## Couleur du drapeau au point (u, v), u et v allant de 0 à 1 (gauche → droite, haut → bas).
static func color_at(code: String, u: float, v: float) -> Color:
	# x va de 0 à 3 et y de 0 à 2 : les formes gardent leurs proportions sur un drapeau 3:2.
	var x := u * 3.0
	var y := v * 2.0
	match code:
		"en":
			var blue := Color("#012169")
			var white := Color.WHITE
			var red := Color("#c8102e")
			if absf(x - 1.5) < 0.2 or absf(y - 1.0) < 0.2:
				return red
			if absf(x - 1.5) < 0.34 or absf(y - 1.0) < 0.34:
				return white
			var d1 := absf(2.0 * x - 3.0 * y) / sqrt(13.0)
			var d2 := absf(2.0 * x + 3.0 * y - 6.0) / sqrt(13.0)
			if minf(d1, d2) < 0.08:
				return red
			if minf(d1, d2) < 0.21:
				return white
			return blue
		"fr":
			return _bands(u, [Color("#0055a4"), Color.WHITE, Color("#ef4135")])
		"it":
			return _bands(u, [Color("#009246"), Color.WHITE, Color("#ce2b37")])
		"de":
			return _bands(v, [Color("#000000"), Color("#dd0000"), Color("#ffce00")])
		"nl":
			return _bands(v, [Color("#ae1c28"), Color.WHITE, Color("#21468b")])
		"ru":
			return _bands(v, [Color.WHITE, Color("#0039a6"), Color("#d52b1e")])
		"pl":
			return Color.WHITE if v < 0.5 else Color("#dc143c")
		"es":
			return Color("#aa151b") if v < 0.25 or v > 0.75 else Color("#f1bf00")
		"da":
			return _nordic(u, v, Color("#c8102e"), Color.WHITE, Vector4(12.0 / 37.0, 16.0 / 37.0, 12.0 / 28.0, 16.0 / 28.0))
		"sv":
			return _nordic(u, v, Color("#006aa7"), Color("#fecc02"), Vector4(5.0 / 16.0, 7.0 / 16.0, 4.0 / 10.0, 6.0 / 10.0))
		"no":
			if (u > 7.0 / 22.0 and u < 9.0 / 22.0) or (v > 7.0 / 16.0 and v < 9.0 / 16.0):
				return Color("#00205b")
			return _nordic(u, v, Color("#ba0c2f"), Color.WHITE, Vector4(6.0 / 22.0, 10.0 / 22.0, 6.0 / 16.0, 10.0 / 16.0))
		"pt":
			var center := Vector2(1.2, 1.0)
			var offset := Vector2(x, y) - center
			# Écu blanc bordé de rouge, au centre de la sphère armillaire jaune.
			if absf(offset.x) < 0.17 and offset.y > -0.22 and offset.y < 0.22:
				return Color.WHITE
			if absf(offset.x) < 0.26 and offset.y > -0.31 and offset.y < 0.31:
				return Color("#da291c")
			var radius := offset.length()
			if radius > 0.4 and radius < 0.58:
				return Color("#ffe900")
			return Color("#046a38") if u < 0.4 else Color("#da291c")
		"tr":
			var red := Color("#e30a17")
			var point := Vector2(x, y)
			if point.distance_to(Vector2(1.0, 1.0)) < 0.5 and point.distance_to(Vector2(1.125, 1.0)) >= 0.4:
				return Color.WHITE
			if _in_star(point, Vector2(1.62, 1.0), 0.25):
				return Color.WHITE
			return red
	return Color(0, 0, 0, 0)


static func _bands(t: float, colors: Array) -> Color:
	return colors[clampi(int(t * colors.size()), 0, colors.size() - 1)]


## Croix scandinave : bounds = début et fin de la barre verticale (en u), puis de l'horizontale (en v).
static func _nordic(u: float, v: float, field: Color, cross: Color, bounds: Vector4) -> Color:
	if (u > bounds.x and u < bounds.y) or (v > bounds.z and v < bounds.w):
		return cross
	return field


## Étoile à cinq branches, une pointe tournée vers le croissant (à gauche).
static func _in_star(point: Vector2, center: Vector2, outer: float) -> bool:
	var vertices := PackedVector2Array()
	for i in 10:
		var angle := PI + i * TAU / 10.0
		var radius := outer if i % 2 == 0 else outer * 0.382
		vertices.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return Geometry2D.is_point_in_polygon(point, vertices)
