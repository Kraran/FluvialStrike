extends Control

const SETTINGS = preload("res://flight_settings.gd")
const INK := Color("#071c27")
const LINE := Color("#284651")
const TEXT := Color("#e8f3ed")
const ACCENT := Color("#a8ecc9")
const MUTED := Color("#a7bbc0")
const KEY_NAMES := {KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_SPACE: "Espace"}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_LEFT: "Croix gauche", JOY_BUTTON_DPAD_RIGHT: "Croix droite",
	JOY_BUTTON_DPAD_UP: "Croix haut", JOY_BUTTON_DPAD_DOWN: "Croix bas",
}

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS }

signal action_requested(action: StringName)
signal settings_changed
signal settings_committed

var screen := Screen.HIDDEN
var settings: SETTINGS
var _return_to := Screen.TITLE
var _waiting_index := -1
var _waiting_for_controller := false
var _keyboard_buttons: Array[Button] = []
var _controller_buttons: Array[Button] = []
var _status: Label
var _notice := ""


func configure(options: SETTINGS) -> void:
	settings = options
	theme = _make_theme()
	size = Vector2(912, 594)
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_title()


func show_title() -> void:
	_show_page(Screen.TITLE)


func show_pause() -> void:
	_show_page(Screen.PAUSE)


func dismiss() -> void:
	screen = Screen.HIDDEN
	_waiting_index = -1
	hide()


func back() -> void:
	if screen == Screen.SETTINGS:
		_show_page(_return_to)
		settings_committed.emit()


func show_notice(message: String) -> void:
	_notice = message
	if is_instance_valid(_status):
		_status.text = message


func _show_page(next: Screen) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_keyboard_buttons.clear()
	_controller_buttons.clear()
	_waiting_index = -1
	_status = null
	screen = next
	show()

	var shade := ColorRect.new()
	shade.color = Color(0.023, 0.072, 0.10, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(INK, LINE, 22, 8))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 592 if next == Screen.SETTINGS else 382
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)

	if next == Screen.SETTINGS:
		_settings_page(content)
	else:
		_home_page(content, next == Screen.PAUSE)


func _home_page(content: VBoxContainer, paused: bool) -> void:
	_caption(content, "RAID FLUVIAL   /   BÊTA %s" % ProjectSettings.get_setting("application/config/version"), 13, ACCENT)
	_caption(content, "Pause" if paused else "FLUVIAL STRIKE", 38, TEXT)
	_caption(content, "9 ponts à franchir   ·   Record local %06d" % settings.record, 16, MUTED)
	if not paused:
		_caption(content, "Par défaut  ·  Flèches ou stick gauche  ·  Tir Espace / A", 13, MUTED)
	content.add_child(HSeparator.new())
	var primary := _button(content, "Reprendre le vol" if paused else "Jouer", true)
	primary.pressed.connect(_request.bind(&"resume" if paused else &"play"))
	var secondary := _button(content, "Recommencer" if paused else "Rejeu de référence")
	secondary.pressed.connect(_request.bind(&"play" if paused else &"reference"))
	var options := _button(content, "Réglages")
	options.pressed.connect(_open_settings)
	var last := _button(content, "Menu principal" if paused else "Quitter")
	last.pressed.connect(_request.bind(&"title" if paused else &"quit"))
	_status = _caption(content, _notice, 13, ACCENT)
	primary.grab_focus()


func _settings_page(content: VBoxContainer) -> void:
	var back_button := _button(content, "Retour", false, 30)
	back_button.pressed.connect(back)
	_caption(content, "Réglages", 28, TEXT)

	var video := HBoxContainer.new()
	video.add_theme_constant_override("separation", 9)
	content.add_child(video)
	_toggle(video, "Plein écran", settings.fullscreen, &"fullscreen")
	_toggle(video, "Synchronisation verticale", settings.vsync, &"vsync")
	_toggle(video, "Rendu HD", settings.quality_hd, &"quality_hd")

	var audio := HBoxContainer.new()
	audio.add_theme_constant_override("separation", 10)
	content.add_child(audio)
	_caption(audio, "Volume", 16, TEXT)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(210, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.max_value = 100
	slider.step = 5
	slider.value = settings.volume
	audio.add_child(slider)
	var value_label := _caption(audio, "%d %%" % settings.volume, 14, MUTED)
	value_label.custom_minimum_size.x = 48
	slider.value_changed.connect(_set_volume.bind(value_label))
	_toggle(audio, "Muet", settings.muted, &"muted")

	content.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for title in ["Commandes de vol", "Clavier", "Manette"]:
		_caption(grid, title, 15, ACCENT)
	for i in SETTINGS.ACTIONS.size():
		var label := _caption(grid, SETTINGS.ACTIONS[i][1], 15, TEXT)
		label.custom_minimum_size.x = 182
		var key := _button(grid, "", false, 31)
		key.custom_minimum_size.x = 145
		key.pressed.connect(_listen.bind(i, false))
		_keyboard_buttons.append(key)
		var pad := _button(grid, "", false, 31)
		pad.custom_minimum_size.x = 145
		pad.pressed.connect(_listen.bind(i, true))
		_controller_buttons.append(pad)
	_refresh_bindings()
	_status = _caption(content, "Choisis une commande pour la modifier. Le stick gauche reste actif.", 13, MUTED)
	var reset := _button(content, "Rétablir les commandes", false, 30)
	reset.pressed.connect(_restore_bindings)
	back_button.grab_focus()


func _input(event: InputEvent) -> void:
	if screen != Screen.SETTINGS or _waiting_index < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_finish_binding("Affectation annulée.")
		elif not _waiting_for_controller:
			_submit_binding(event.physical_keycode)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if _waiting_for_controller:
			_submit_binding(event.button_index)
		get_viewport().set_input_as_handled()


func _submit_binding(code: int) -> void:
	if settings.bind(_waiting_index, code, _waiting_for_controller):
		settings_changed.emit()
		_finish_binding("Commande affectée.")
	else:
		_status.text = "Cette commande est réservée. Choisis-en une autre ou appuie sur Échap."


func _listen(index: int, controller: bool) -> void:
	_waiting_index = index
	_waiting_for_controller = controller
	_refresh_bindings()
	_status.text = "Appuie sur un bouton de la manette." if controller else "Appuie sur une touche du clavier."


func _finish_binding(message: String) -> void:
	_waiting_index = -1
	_refresh_bindings()
	_status.text = message


func _refresh_bindings() -> void:
	for i in SETTINGS.ACTIONS.size():
		var key := DisplayServer.keyboard_get_keycode_from_physical(settings.keyboard[i] as Key)
		var pad := settings.gamepad[i]
		_keyboard_buttons[i].text = "Appuie…" if _waiting_index == i and not _waiting_for_controller \
			else KEY_NAMES.get(key, OS.get_keycode_string(key))
		_controller_buttons[i].text = "Appuie…" if _waiting_index == i and _waiting_for_controller \
			else BUTTON_NAMES.get(pad, "Bouton %d" % (pad + 1))


func _restore_bindings() -> void:
	settings.reset_bindings()
	settings_changed.emit()
	_finish_binding("Commandes rétablies.")


func _open_settings() -> void:
	_return_to = screen
	_show_page(Screen.SETTINGS)


func _request(action: StringName) -> void:
	action_requested.emit(action)


func _set_volume(value: float, label: Label) -> void:
	settings.volume = roundi(value)
	label.text = "%d %%" % settings.volume
	settings_changed.emit()


func _toggle(parent: Control, text: String, enabled: bool, property: StringName) -> void:
	var box := CheckButton.new()
	box.text = text
	box.button_pressed = enabled
	box.toggled.connect(_set_option.bind(property))
	parent.add_child(box)


func _set_option(enabled: bool, property: StringName) -> void:
	settings.set(property, enabled)
	settings_changed.emit()


func _button(parent: Control, text: String, primary: bool = false, height: int = 39) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = height
	if primary:
		button.add_theme_color_override("font_color", ACCENT)
		button.add_theme_stylebox_override("normal", _box(Color("#174036"), Color("#568d75"), 8, 4))
	parent.add_child(button)
	return button


func _caption(parent: Control, text: String, points: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_color", "CheckButton", TEXT)
	result.set_stylebox("normal", "Button", _box(Color("#102b37"), LINE, 8, 4))
	result.set_stylebox("hover", "Button", _box(Color("#183b48"), Color("#588692"), 8, 4))
	result.set_stylebox("pressed", "Button", _box(Color("#204b51"), ACCENT, 8, 4))
	result.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, ACCENT, 8, 4))
	return result


func _box(color: Color, border: Color, margin: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, margin)
	return box
