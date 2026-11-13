extends Button
## Ligne de réglage : libellé à gauche, « ◀ valeur ▶ » à droite.
## Gauche / droite change la valeur sur place ; A ou un clic avance d'un cran,
## un clic sur la flèche de gauche recule. Sans flèches, la ligne affiche une
## valeur et émet seulement « pressed » (affectation d'une commande, par exemple).

signal value_changed(index: int)

const TEXT := Color("#e8f3ed")
const MUTED := Color("#a7bbc0")
const ACCENT := Color("#a8ecc9")
const VALUE_WIDTH := 190.0

var choices := PackedStringArray()
var index := 0
var description := ""
var arrows := true
var _name: Label
var _value: Label
var _left: Label
var _right: Label


func setup(title: String, options: PackedStringArray, selected: int, help: String = "") -> void:
	choices = options
	index = clampi(selected, 0, maxi(options.size() - 1, 0))
	description = help
	custom_minimum_size.y = 36
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -10
	_name = _label(row, title, TEXT)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left = _label(row, "◀", MUTED)
	_value = _label(row, "", ACCENT)
	_value.custom_minimum_size.x = VALUE_WIDTH
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_right = _label(row, "▶", MUTED)
	pressed.connect(_on_pressed)
	_refresh()


## Affiche une valeur libre, sans flèches.
func set_value_text(text: String) -> void:
	arrows = false
	_value.text = text
	_left.visible = false
	_right.visible = false


func step(direction: int) -> void:
	if choices.is_empty() or not arrows:
		return
	index = posmod(index + direction, choices.size())
	_refresh()
	value_changed.emit(index)


func _on_pressed() -> void:
	if arrows:
		step(1)


func _gui_input(event: InputEvent) -> void:
	if not arrows or disabled:
		return
	if event is InputEventJoypadMotion:
		return
	if event.is_action_pressed(&"ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and _left.get_global_rect().grow(8).has_point(get_global_mouse_position()):
		step(-1)
		accept_event()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT] and _left:
		var color := TEXT if has_focus() else MUTED
		_left.add_theme_color_override("font_color", color)
		_right.add_theme_color_override("font_color", color)


func _refresh() -> void:
	if arrows and not choices.is_empty():
		_value.text = choices[index]


func _label(parent: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
