extends Node
## Suit le dernier périphérique utilisé (clavier ou famille de manette)
## et fournit les glyphes de boutons affichés dans la barre d'aide des menus.

signal device_changed

enum Device { KEYBOARD, XBOX, PLAYSTATION, NINTENDO }
enum Prompt { ACCEPT, BACK, X, Y, TABS, START, SELECT }

const PLAYSTATION_HINTS := ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony"]
const NINTENDO_HINTS := ["nintendo", "switch", "joy-con", "joycon"]

var device := Device.KEYBOARD


func _ready() -> void:
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		device = family(pads[0])
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_set_device(Device.KEYBOARD)
	elif event is InputEventJoypadButton and event.pressed:
		_set_device(family(event.device))
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_device(family(event.device))


func is_pad() -> bool:
	return device != Device.KEYBOARD


static func family(pad: int) -> Device:
	var name := Input.get_joy_name(pad).to_lower()
	for hint: String in PLAYSTATION_HINTS:
		if name.contains(hint):
			return Device.PLAYSTATION
	for hint: String in NINTENDO_HINTS:
		if name.contains(hint):
			return Device.NINTENDO
	return Device.XBOX


func _set_device(next: Device) -> void:
	if next != device:
		device = next
		device_changed.emit()


func _on_joy_connection_changed(_pad: int, connected: bool) -> void:
	if not connected and Input.get_connected_joypads().is_empty():
		_set_device(Device.KEYBOARD)


## Glyphe d'un bouton, dessiné sans dépendre d'une police de symboles.
class Glyph extends Control:
	const SIZE := 22.0
	const FONT_SIZE := 12
	const INK := Color("#071c27")
	const CAP := Color("#d5e3e0")
	const XBOX_COLORS := {Prompt.ACCEPT: Color("#6cc24a"), Prompt.BACK: Color("#e5533d"),
		Prompt.X: Color("#3d8fe0"), Prompt.Y: Color("#f0c330")}
	const PLAYSTATION_COLORS := {Prompt.ACCEPT: Color("#82aef0"), Prompt.BACK: Color("#ee7a72"),
		Prompt.X: Color("#df90d0"), Prompt.Y: Color("#4fcfa6")}
	## Sur les manettes Nintendo, le bouton du bas porte la lettre B.
	const NINTENDO_LETTERS := {Prompt.ACCEPT: "B", Prompt.BACK: "A", Prompt.X: "Y", Prompt.Y: "X"}
	const XBOX_LETTERS := {Prompt.ACCEPT: "A", Prompt.BACK: "B", Prompt.X: "X", Prompt.Y: "Y"}

	var device := Device.KEYBOARD
	var prompt := Prompt.ACCEPT
	var keyboard_text := ""

	func _init(on: Device, button: Prompt, keys: String) -> void:
		device = on
		prompt = button
		keyboard_text = keys
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _caps() -> PackedStringArray:
		if device == Device.KEYBOARD:
			return keyboard_text.split("|")
		match prompt:
			Prompt.TABS:
				match device:
					Device.PLAYSTATION:
						return PackedStringArray(["L1", "R1"])
					Device.NINTENDO:
						return PackedStringArray(["L", "R"])
				return PackedStringArray(["LB", "RB"])
			Prompt.START:
				match device:
					Device.PLAYSTATION:
						return PackedStringArray(["Options"])
					Device.NINTENDO:
						return PackedStringArray(["+"])
				return PackedStringArray(["Start"])
			Prompt.SELECT:
				match device:
					Device.PLAYSTATION:
						return PackedStringArray(["Create"])
					Device.NINTENDO:
						return PackedStringArray(["−"])
				return PackedStringArray(["View"])
		return PackedStringArray()

	func _font() -> Font:
		return get_theme_default_font()

	func _cap_width(text: String) -> float:
		return maxf(SIZE, _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 12.0)

	func _get_minimum_size() -> Vector2:
		var caps := _caps()
		if caps.is_empty():
			return Vector2(SIZE, SIZE)
		var width := 0.0
		for text in caps:
			width += _cap_width(text)
		return Vector2(width + 4.0 * (caps.size() - 1), SIZE)

	func _draw() -> void:
		var caps := _caps()
		if not caps.is_empty():
			var x := 0.0
			for text in caps:
				var width := _cap_width(text)
				_draw_cap(Rect2(x, 0, width, SIZE), text)
				x += width + 4.0
			return
		var center := Vector2(SIZE, SIZE) / 2.0
		var radius := SIZE / 2.0 - 1.0
		draw_circle(center, radius, INK)
		match device:
			Device.PLAYSTATION:
				var color: Color = PLAYSTATION_COLORS[prompt]
				draw_arc(center, radius, 0, TAU, 32, Color(color, 0.55), 1.2, true)
				_draw_shape(center, color)
			Device.NINTENDO:
				draw_arc(center, radius, 0, TAU, 32, CAP, 1.5, true)
				_draw_letter(center, NINTENDO_LETTERS[prompt], CAP)
			_:
				var color: Color = XBOX_COLORS[prompt]
				draw_arc(center, radius, 0, TAU, 32, color, 1.8, true)
				_draw_letter(center, XBOX_LETTERS[prompt], color)

	func _draw_cap(rect: Rect2, text: String) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = INK
		box.border_color = CAP
		box.set_border_width_all(1)
		box.set_corner_radius_all(5)
		draw_style_box(box, rect.grow(-0.5))
		var font := _font()
		var baseline := rect.position.y + (rect.size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
		draw_string(font, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, FONT_SIZE, CAP)

	func _draw_letter(center: Vector2, letter: String, color: Color) -> void:
		var font := _font()
		var baseline := center.y + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
		draw_string(font, Vector2(0, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, SIZE, FONT_SIZE, color)

	func _draw_shape(center: Vector2, color: Color) -> void:
		var r := 5.0
		match prompt:
			Prompt.ACCEPT:
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r), color, 1.8, true)
				draw_line(center + Vector2(-r, r), center + Vector2(r, -r), color, 1.8, true)
			Prompt.BACK:
				draw_arc(center, r + 0.5, 0, TAU, 24, color, 1.8, true)
			Prompt.X:
				draw_rect(Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), color, false, 1.8)
			Prompt.Y:
				var points := PackedVector2Array([center + Vector2(0, -r - 0.5), center + Vector2(r + 0.5, r - 0.5),
					center + Vector2(-r - 0.5, r - 0.5), center + Vector2(0, -r - 0.5)])
				draw_polyline(points, color, 1.8, true)
