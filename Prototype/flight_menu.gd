extends Control

const SETTINGS = preload("res://flight_settings.gd")
const FLIGHT = preload("res://flight.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
const MODELS = preload("res://flight_models.gd")
const PACING = preload("res://frame_pacing.gd")
const INK := Color("#071c27")
const LINE := Color("#284651")
const TEXT := Color("#e8f3ed")
const ACCENT := Color("#a8ecc9")
const MUTED := Color("#a7bbc0")
const KEY_NAMES := {KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_SPACE: "Espace"}
const SECRET_CODES := {
	"live": [FLIGHT.Cheat.LIVES, "Vies infinies"],
	"invi": [FLIGHT.Cheat.INVULNERABILITY, "Invulnérabilité"],
	"carbu": [FLIGHT.Cheat.FUEL, "Carburant infini"],
}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_LEFT: "Croix gauche", JOY_BUTTON_DPAD_RIGHT: "Croix droite",
	JOY_BUTTON_DPAD_UP: "Croix haut", JOY_BUTTON_DPAD_DOWN: "Croix bas",
}

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS, HANGAR, RESULTS }

signal action_requested(action: StringName)
signal settings_changed
signal settings_committed

var screen := Screen.HIDDEN
var cheats := 0
var settings: SETTINGS
var _code_prefix := ""
var _return_to := Screen.TITLE
var _waiting_index := -1
var _waiting_for_controller := false
var _keyboard_buttons: Array[Button] = []
var _controller_buttons: Array[Button] = []
var _status: Label
var _notice := ""
var _hangar_selection := AIRCRAFT.DEFAULT
var _hangar_choices := {}
var _flags := {}
var _hangar_models := MODELS.new()
var _hangar_viewport: SubViewport
var _hangar_scene: Node3D
var _hangar_model: Node3D
var _hangar_name: Label
var _hangar_country: Label
var _hangar_flag: TextureRect


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


func show_results(flight: FLIGHT) -> void:
	_show_page(Screen.RESULTS, flight)


func dismiss() -> void:
	screen = Screen.HIDDEN
	_code_prefix = ""
	_waiting_index = -1
	hide()


func back() -> void:
	if screen == Screen.SETTINGS:
		_show_page(_return_to)
		settings_committed.emit()
	elif screen == Screen.HANGAR:
		show_title()


func show_notice(message: String) -> void:
	_notice = message
	if is_instance_valid(_status):
		_status.text = message


func _show_page(next: Screen, flight: FLIGHT = null) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_hangar_choices.clear()
	_hangar_model = null
	_keyboard_buttons.clear()
	_controller_buttons.clear()
	_waiting_index = -1
	_status = null
	_code_prefix = ""
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
	panel.add_theme_stylebox_override("panel", _box(INK, LINE, 16 if next == Screen.SETTINGS else 22, 8))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 592 if next == Screen.SETTINGS else (450 if next == Screen.RESULTS else 382)
	content.add_theme_constant_override("separation", 5 if next == Screen.SETTINGS else 8)
	panel.add_child(content)

	if next == Screen.SETTINGS:
		_settings_page(content)
	elif next == Screen.HANGAR:
		_hangar_page(content)
	elif next == Screen.RESULTS:
		_results_page(content, flight)
	else:
		_home_page(content, next == Screen.PAUSE)


func _home_page(content: VBoxContainer, paused: bool) -> void:
	_caption(content, "RAID FLUVIAL   /   BÊTA %s" % ProjectSettings.get_setting("application/config/version"), 13, ACCENT)
	_caption(content, "Pause" if paused else "FLUVIAL STRIKE", 38, TEXT)
	_caption(content, "Raid intégral   ·   Record local %06d" % settings.record, 16, MUTED)
	if not paused:
		_caption(content, "Par défaut  ·  Flèches ou stick gauche  ·  Tir Espace / A", 13, MUTED)
	content.add_child(HSeparator.new())
	var primary := _button(content, "Reprendre le vol" if paused else "Jouer", true)
	primary.pressed.connect(_request.bind(&"resume" if paused else &"play"))
	var secondary := _button(content, "Recommencer" if paused else "Rejeu de référence")
	secondary.pressed.connect(_request.bind(&"play" if paused else &"reference"))
	if not paused:
		var hangar := _button(content, "Hangar")
		hangar.pressed.connect(_show_page.bind(Screen.HANGAR))
	var options := _button(content, "Réglages")
	options.pressed.connect(_open_settings)
	var last := _button(content, "Menu principal" if paused else "Quitter")
	last.pressed.connect(_request.bind(&"title" if paused else &"quit"))
	_status = _caption(content, _notice, 13, ACCENT)
	primary.grab_focus()


func _results_page(content: VBoxContainer, flight: FLIGHT) -> void:
	_caption(content, "Bilan du raid", 34, TEXT)
	if flight.status == FLIGHT.Status.COMPLETE:
		_caption(content, "Raid terminé", 15, ACCENT)
	if flight.cheats != 0:
		_caption(content, "Raid avec codes · records réservés aux raids sans code", 14, MUTED)
	content.add_child(HSeparator.new())
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 9)
	content.add_child(stats)
	_caption(stats, "", 15, MUTED).custom_minimum_size.x = 162
	_caption(stats, "Ce raid", 15, TEXT).custom_minimum_size.x = 108
	_caption(stats, "Records locaux", 15, ACCENT)
	var has_progress := settings.furthest_section > 0
	_result_row(stats, "Score", "%06d" % flight.score, "%06d" % settings.record)
	_result_row(stats, "Section atteinte", str(flight.section), str(settings.furthest_section) if has_progress else "—")
	_result_row(stats, "Ponts franchis", str(flight.section - 1), str(settings.most_bridges) if has_progress else "—")
	content.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var retry := _button(actions, "Rejouer", true)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(_request.bind(&"play"))
	var home := _button(actions, "Menu principal")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(_request.bind(&"title"))
	_status = _caption(content, _notice, 13, ACCENT)
	retry.grab_focus()


func _result_row(grid: GridContainer, title: String, run: String, best: String) -> void:
	_caption(grid, title, 16, MUTED)
	_caption(grid, run, 22, TEXT)
	_caption(grid, best, 22, ACCENT)


func _hangar_page(content: VBoxContainer) -> void:
	_caption(content, "Hangar", 32, TEXT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 235
	choices.add_theme_constant_override("separation", 8)
	row.add_child(choices)
	var group := ButtonGroup.new()
	for id: String in AIRCRAFT.IDS:
		var button := _button(choices, AIRCRAFT.AIRCRAFT[id].short, false, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.focus_entered.connect(_preview_aircraft.bind(id))
		button.pressed.connect(_preview_aircraft.bind(id))
		_hangar_choices[id] = button

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	row.add_child(detail)
	_hangar_name = _caption(detail, "", 24, TEXT)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(468, 260)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(preview)
	_build_hangar_viewport(preview)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	detail.add_child(identity)
	_hangar_flag = TextureRect.new()
	_hangar_flag.custom_minimum_size = Vector2(52, 32)
	_hangar_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hangar_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(_hangar_flag)
	_hangar_country = _caption(identity, "", 16, MUTED)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	_button(footer, "Retour").pressed.connect(back)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	_button(footer, "Choisir cet avion", true).pressed.connect(_confirm_aircraft)
	_preview_aircraft(settings.aircraft)
	_hangar_choices[settings.aircraft].grab_focus()


func _build_hangar_viewport(preview: TextureRect) -> void:
	_hangar_viewport = SubViewport.new()
	_hangar_viewport.own_world_3d = true
	_hangar_viewport.size = Vector2i(702, 390)
	_hangar_viewport.msaa_3d = Viewport.MSAA_2X
	preview.add_child(_hangar_viewport)
	preview.texture = _hangar_viewport.get_texture()
	_hangar_scene = Node3D.new()
	_hangar_viewport.add_child(_hangar_scene)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#123345")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cee0e5")
	environment.ambient_light_energy = 0.72
	world.environment = environment
	_hangar_scene.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-54, -34, 0)
	key.light_energy = 0.85
	_hangar_scene.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-31, 142, 0)
	rim.light_color = Color("#99cee0")
	rim.light_energy = 0.42
	_hangar_scene.add_child(rim)
	var camera := Camera3D.new()
	_hangar_scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.95
	camera.position = Vector3(2.1, 8.5, 3.9)
	camera.look_at(Vector3(0, 0, -0.28))
	camera.make_current()


func _preview_aircraft(id: String) -> void:
	if is_instance_valid(_hangar_model) and id == _hangar_selection:
		return
	_hangar_selection = id
	var entry: Dictionary = AIRCRAFT.AIRCRAFT[id]
	_hangar_name.text = entry.name
	_hangar_country.text = entry.country
	var flag_path: String = entry.flag
	if not _flags.has(flag_path):
		_flags[flag_path] = _load_flag(flag_path)
	_hangar_flag.texture = _flags[flag_path]
	_hangar_choices[id].button_pressed = true
	if is_instance_valid(_hangar_model):
		_hangar_scene.remove_child(_hangar_model)
		_hangar_model.queue_free()
	_hangar_model = _hangar_models.player_aircraft(id)
	_hangar_model.rotation.y = -0.28
	_hangar_scene.add_child(_hangar_model)
	_hangar_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _load_flag(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return load(path) as Texture2D


func _confirm_aircraft() -> void:
	settings.aircraft = _hangar_selection
	_show_page(Screen.TITLE)
	_request(&"aircraft_selected")
	settings_committed.emit()


func _settings_page(content: VBoxContainer) -> void:
	var back_button := _button(content, "Retour", false, 30)
	back_button.pressed.connect(back)
	_caption(content, "Réglages", 25, TEXT)

	var video := HBoxContainer.new()
	video.add_theme_constant_override("separation", 9)
	content.add_child(video)
	_toggle(video, "Plein écran", settings.fullscreen, &"fullscreen")
	_toggle(video, "Rendu HD", settings.quality_hd, &"quality_hd")
	_toggle(video, "Résolution adaptative", settings.dynamic_resolution, &"dynamic_resolution")

	var timing := HBoxContainer.new()
	timing.add_theme_constant_override("separation", 8)
	content.add_child(timing)
	_caption(timing, "Cadence", 15, TEXT)
	var rates: Array[String] = ["Auto"]
	for hz in PACING.RATES.slice(1):
		rates.append("%d Hz" % hz)
	_select(timing, rates, PACING.RATES, settings.refresh_limit, &"refresh_limit")
	_caption(timing, "Synchro", 15, TEXT)
	_select(timing, ["Écran", "Adaptative / VRR", "Off"],
		[PACING.Sync.SCREEN, PACING.Sync.ADAPTIVE, PACING.Sync.OFF], settings.sync_mode, &"sync_mode")
	var monitor_hz := DisplayServer.screen_get_refresh_rate()
	if monitor_hz > 0:
		_caption(timing, "Écran %.0f Hz" % monitor_hz, 13, MUTED)

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
	if screen in [Screen.HANGAR, Screen.RESULTS] and event is InputEventJoypadButton \
			and event.pressed and event.button_index == JOY_BUTTON_B:
		if screen == Screen.RESULTS:
			_request(&"title")
		else:
			back()
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.TITLE and event is InputEventKey:
		if event.pressed and not event.echo and event.unicode > 0 \
				and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if _type_cheat_character(String.chr(event.unicode).to_lower()):
				get_viewport().set_input_as_handled()
		return
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


func _type_cheat_character(character: String) -> bool:
	var sequence := _code_prefix + character
	while not sequence.is_empty():
		for code: String in SECRET_CODES:
			if not code.begins_with(sequence):
				continue
			_code_prefix = sequence
			if code == sequence:
				var option: Array = SECRET_CODES[code]
				cheats ^= int(option[0])
				var state := "Code actif" if cheats & int(option[0]) else "Code désactivé"
				show_notice("%s  ·  %s" % [state, option[1]])
				_code_prefix = ""
			return true
		sequence = sequence.substr(1)
	_code_prefix = ""
	return false


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


func _select(parent: Control, choices: Array[String], values: Array, selected: int, property: StringName) -> void:
	var button := OptionButton.new()
	button.custom_minimum_size.y = 30
	for i in choices.size():
		button.add_item(choices[i], values[i])
		if values[i] == selected:
			button.select(i)
	button.item_selected.connect(func(index: int) -> void:
		settings.set(property, button.get_item_id(index))
		settings_changed.emit())
	parent.add_child(button)


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
