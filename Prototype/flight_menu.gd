extends Control

const SETTINGS = preload("res://flight_settings.gd")
const FLIGHT = preload("res://flight.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const VISIBLE_BRIDGE_ROWS := 7
const BRIDGE_COLUMNS := [48, 72, 62, 52, 49, 66]
const AIRCRAFT = preload("res://player_aircraft.gd")
const MODELS = preload("res://flight_models.gd")
const PACING = preload("res://frame_pacing.gd")
const INPUT_GLYPHS = preload("res://input_glyphs.gd")
const MENU_SOUND = preload("res://menu_sound.gd")
const OPTION_ROW = preload("res://option_row.gd")
const BINDING_TIMEOUT_MS := 5000
# Aide inspirée du manuel de River Raid : onglets, barème des cibles et repères du tableau de bord.
const HELP_TABS := ["help.tab_mission", "settings.tab_controls", "help.tab_targets", "help.tab_dashboard", "help.tab_tips"]
const HELP_TAB_MISSION := 0
const HELP_TAB_CONTROLS := 1
const HELP_TAB_TARGETS := 2
const HELP_TAB_DASHBOARD := 3
const HELP_TAB_TIPS := 4
const HELP_BODY_HEIGHT := 362
const HELP_TARGET_ICON := "res://hud/target_%s.png"
const HELP_TARGETS := [["tanker", "help.tanker", 30, "help.tanker_note"], ["helicopter", "help.helicopter", 60, "help.helicopter_note"],
	["fuel", "help.fuel_depot", 80, "help.fuel_depot_note"], ["jet", "help.jet", 100, "help.jet_note"],
	["bridge", "help.bridge", 500, "help.bridge_note"]]
const HELP_DASHBOARD := ["help.dash_fuel", "help.dash_lives", "help.dash_speed", "help.dash_score", "help.dash_section"]
const HELP_TIPS := ["help.tip_slow", "help.tip_bursts", "help.tip_learn", "help.tip_fuel", "help.tip_depot", "help.tip_bridges"]
const TITLE_WORDMARK := "res://title_wordmark.png"
const TITLE_HEIGHT := 38
const ABOUT_PORTRAIT := "res://about_author.jpg"
const ABOUT_VOICE := "res://intro_voice.mp3"
const AUTHOR_NAME := "Franck Fornasari (Kraran)"
const AUTHOR_URL := "https://github.com/Kraran"
const REPOSITORY_URL := "https://github.com/Kraran/FluvialStrike"
## Place libre de l'écran de ralliement (-1 désigne le clavier, sinon un numéro de manette).
const EMPTY_SLOT := -2
const REPEAT_DELAY := 0.35
const REPEAT_INTERVAL := 0.08
const REPEAT_FAST_AFTER := 1.0
const INK := Color("#071c27")
const LINE := Color("#284651")
const TEXT := Color("#e8f3ed")
const ACCENT := Color("#a8ecc9")
const MUTED := Color("#a7bbc0")
const KEY_NAMES := {KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓", KEY_SPACE: "input.space"}
const SCANLINE_OPTIONS := ["common.off", "settings.scanlines_low", "settings.scanlines_medium", "settings.scanlines_high"]
const GHOST_OPTIONS := ["common.off", "common.best_raid", "common.last_raid"]
const TEST_MENU_CODE := "test"
const SECRET_CODES := {
	"live": [FLIGHT.Cheat.LIVES, "cheat.lives"],
	"invi": [FLIGHT.Cheat.INVULNERABILITY, "cheat.invulnerability"],
	"carbu": [FLIGHT.Cheat.FUEL, "cheat.fuel"],
}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_LEFT: "input.dpad_left", JOY_BUTTON_DPAD_RIGHT: "input.dpad_right",
	JOY_BUTTON_DPAD_UP: "input.dpad_up", JOY_BUTTON_DPAD_DOWN: "input.dpad_down",
}

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS, HANGAR, RESULTS, BRIDGES, CONFIRM_RESET, TESTS, SCORES, INITIALS, LANGUAGES, HOTSEAT_SETUP, HOTSEAT_TURN, HOTSEAT_RESULTS, CONFIRM_ABANDON, ARCHIVES, CONTROLS_HELP, ABOUT }

enum SettingsTab { GAME, CONTROLS, AUDIO, DISPLAY, ADVANCED }
const SETTINGS_TAB_LABELS := ["settings.tab_game", "settings.tab_controls", "settings.tab_audio", "settings.tab_display", "settings.tab_advanced"]

signal action_requested(action: StringName)
signal bridge_replay_requested(best: bool, index: int)
signal settings_changed
signal settings_committed

var screen := Screen.HIDDEN
var cheats := 0
var settings: SETTINGS
var _code_prefix := ""
var _return_to := Screen.TITLE
var _abandon_from := Screen.PAUSE
var _waiting_index := -1
var _waiting_for_controller := false
var _keyboard_buttons: Array[Button] = []
var _controller_buttons: Array[Button] = []
var _status: Label
var _notice_key := ""
var _notice_detail := ""
var _result_flight: FLIGHT
var _result_raid: RAID_REPLAY
var _bridge_top := 0
var _bridge_total := 0
var _bridge_rows: Array[Dictionary] = []
var _bridge_table: HBoxContainer
var _bridge_scroll: VScrollBar
var _bridge_back: Button
var _bridge_focus := Vector2i(-1, 0)
var _pause_from_bridges := false
var _pause_manual := false
var _stick_direction := 0
var _reset_score_button: Button
var _language_button: Button
var _settings_tab := SettingsTab.GAME
var _settings_tabs: Array[Button] = []
var _score_notice := ""
var _scores_return := Screen.TITLE
var _pending_score := 0
# Le score à inscrire vient d'un raid en Expert : il va dans le classement Expert.
var _pending_expert := false
var _initials := "AAA"
var _initial_index := 0
var _initial_stick := Vector2i.ZERO
var _initial_labels: Array[Label] = []
var aircraft_selection := AIRCRAFT.DEFAULT
var _hangar_unavailable := ""
var _hangar_choices := {}
var _flags := {}
var _hangar_models := MODELS.new()
var _hangar_viewport: SubViewport
var _hangar_scene: Node3D
var _hangar_model: Node3D
var _hangar_name: Label
var _hangar_country: Label
var _hangar_flag: TextureRect
var hotseat_devices := Vector2i(-1, -1)
var _hotseat_next := -1
var _hotseat_choose_aircraft := false
var _hotseat_results: Array[FLIGHT] = []
var glyphs: INPUT_GLYPHS
var _sound: MENU_SOUND
var _voice: AudioStreamPlayer
var _building := false
var _bridge_pending := false
var _prompt_bar: HBoxContainer
var _prompt_entries: Array = []
var _held := Vector2i.ZERO
var _held_time := 0.0
var _next_repeat := 0.0
var _held_stick := Vector2i.ZERO
var _repeat_armed := false
var _stick_x := 0
var _bind_controller := false
var _binding_rows: Array[OPTION_ROW] = []
var _listen_deadline := 0
var _description: Label
var _pause_flight: FLIGHT
var _quit_button: Button
var _archives_tab := 0
var _archives_focus_tab := false
var _help_return := Screen.TITLE
var _help_tab := 0
var _card_name: Label
var _card_country: Label
var _card_flag: TextureRect
var _card_count: Label
var _card_chooser: Control
var _hotseat_row: OPTION_ROW
var _hotseat_leave: Button


func configure(options: SETTINGS) -> void:
	settings = options
	theme = _make_theme()
	if glyphs == null:
		glyphs = INPUT_GLYPHS.new()
		glyphs.name = "InputGlyphs"
		add_child(glyphs)
		glyphs.device_changed.connect(_refresh_prompts)
		_sound = MENU_SOUND.new()
		_sound.name = "MenuSound"
		add_child(_sound)
		_voice = AudioStreamPlayer.new()
		_voice.name = "AboutVoice"
		add_child(_voice)
	size = Vector2(912, 594)
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_title()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _on_focus_changed(control: Control) -> void:
	if not _building and screen != Screen.HIDDEN and is_ancestor_of(control):
		play_sound("move")


func play_sound(kind: String) -> void:
	if _sound and settings and not settings.muted and settings.volume > 0:
		_sound.play(kind)


func show_title() -> void:
	_result_flight = null
	_result_raid = null
	_hotseat_results.clear()
	_show_page(Screen.TITLE)


func show_pause(from_bridges: bool = false, manual: bool = false, flight: FLIGHT = null) -> void:
	_pause_from_bridges = from_bridges
	_pause_manual = manual
	_pause_flight = flight
	_show_page(Screen.PAUSE)


func show_results(flight: FLIGHT, replay: RAID_REPLAY) -> void:
	_result_flight = flight
	_result_raid = replay
	_bridge_top = 0
	_bridge_focus = Vector2i(-1, 0)
	_pending_expert = not flight.guided_shots
	_pending_score = flight.score if flight.cheats == 0 and settings.score_rank(flight.score, _pending_expert) >= 0 else 0
	if _pending_score > 0:
		_open_initials()
	else:
		_show_page(Screen.RESULTS)


func confirm_abandon() -> void:
	_abandon_from = screen
	_show_page(Screen.CONFIRM_ABANDON)


func show_hotseat_setup(devices: Vector2i) -> void:
	# Garde les places encore utilisables (clavier ou manette branchée), libère les autres.
	var connected := Input.get_connected_joypads()
	hotseat_devices = Vector2i(EMPTY_SLOT, EMPTY_SLOT)
	for player in 2:
		var device := devices[player]
		if device == -1 or (device in connected and device != hotseat_devices[0]):
			hotseat_devices[player] = device
	_show_page(Screen.HOTSEAT_SETUP)


func show_hotseat_turn(player: int, devices: Vector2i, aircraft: String, unavailable: String) -> void:
	_hotseat_next = player
	hotseat_devices = devices
	_hotseat_choose_aircraft = aircraft.is_empty()
	aircraft_selection = settings.aircraft if _hotseat_choose_aircraft else aircraft
	_hangar_unavailable = unavailable
	if _hotseat_choose_aircraft and aircraft_selection == unavailable:
		for id: String in AIRCRAFT.IDS:
			if id != unavailable:
				aircraft_selection = id
				break
	_show_page(Screen.HOTSEAT_TURN)


func show_hotseat_results(players: Array[FLIGHT]) -> void:
	_hotseat_results.assign(players)
	_show_page(Screen.HOTSEAT_RESULTS)


func refresh_hotseat_devices() -> void:
	if screen in [Screen.HOTSEAT_SETUP, Screen.HOTSEAT_TURN]:
		_show_page(screen)


func show_bridge_results() -> void:
	_show_page(Screen.BRIDGES)


func dismiss() -> void:
	screen = Screen.HIDDEN
	set_process(false)
	_code_prefix = ""
	_waiting_index = -1
	hide()


func back() -> void:
	match screen:
		Screen.SETTINGS:
			if _waiting_index >= 0:
				_finish_binding(tr("settings.binding_cancelled"))
			else:
				_show_page(_return_to)
				settings_committed.emit()
		Screen.HANGAR, Screen.TESTS:
			show_title()
		Screen.BRIDGES:
			_bridge_focus = _focused_bridge()
			_show_page(Screen.RESULTS)
		Screen.RESULTS, Screen.HOTSEAT_RESULTS:
			_request(&"title")
		Screen.HOTSEAT_SETUP, Screen.HOTSEAT_TURN:
			_request(&"title")
		Screen.PAUSE:
			_request(&"resume")
		Screen.CONFIRM_RESET:
			_return_from_reset()
		Screen.CONFIRM_ABANDON:
			_show_page(_abandon_from)
		Screen.SCORES:
			_show_page(_scores_return)
		Screen.INITIALS:
			_show_page(Screen.RESULTS)
		Screen.LANGUAGES:
			_return_to_language_settings()
		Screen.ARCHIVES:
			show_title()
		Screen.CONTROLS_HELP:
			_show_page(_help_return)
		Screen.ABOUT:
			show_title()


func show_notice(key: String, detail: String = "") -> void:
	_notice_key = key
	_notice_detail = detail
	if is_instance_valid(_status) and (screen != Screen.SETTINGS or not key.is_empty()):
		_status.text = _notice_text()


func _notice_text() -> String:
	var message := tr(_notice_key)
	return message if _notice_detail.is_empty() else message % tr(_notice_detail)


func _show_page(next: Screen) -> void:
	_building = true
	for child in get_children():
		if child == glyphs or child == _sound or child == _voice:
			continue
		remove_child(child)
		child.queue_free()
	_prompt_bar = null
	_prompt_entries = []
	_hangar_choices.clear()
	_hangar_model = null
	_keyboard_buttons.clear()
	_controller_buttons.clear()
	_binding_rows.clear()
	_description = null
	_quit_button = null
	_hotseat_row = null
	_hotseat_leave = null
	_waiting_index = -1
	_status = null
	_reset_score_button = null
	_language_button = null
	_settings_tabs.clear()
	_initial_labels.clear()
	_bridge_rows.clear()
	_bridge_table = null
	_bridge_scroll = null
	_bridge_back = null
	_code_prefix = ""
	screen = next
	_bridge_pending = false
	_held = Vector2i.ZERO
	_repeat_armed = false
	set_process(true)
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
	panel.add_theme_stylebox_override("panel", _box(INK, LINE, 12 if next == Screen.SETTINGS else 22, 8))
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 382
	match next:
		Screen.SETTINGS:
			content.custom_minimum_size.x = 670
		Screen.TITLE:
			content.custom_minimum_size.x = 640
		Screen.HOTSEAT_SETUP, Screen.HOTSEAT_TURN:
			content.custom_minimum_size.x = 560
		Screen.CONTROLS_HELP:
			content.custom_minimum_size.x = 640
		Screen.RESULTS:
			content.custom_minimum_size.x = 450
		Screen.ARCHIVES, Screen.SCORES:
			content.custom_minimum_size.x = 560
		Screen.ABOUT:
			content.custom_minimum_size.x = 640
	if next == Screen.SETTINGS:
		content.custom_minimum_size.y = 504
	content.add_theme_constant_override("separation", 4 if next == Screen.SETTINGS else 8)
	panel.add_child(content)

	if next == Screen.SETTINGS:
		_settings_page(content)
	elif next == Screen.HANGAR:
		_hangar_page(content)
	elif next == Screen.RESULTS:
		_results_page(content, _result_flight)
	elif next == Screen.BRIDGES:
		_bridge_results_page(content)
	elif next == Screen.CONFIRM_RESET:
		_confirm_reset_page(content)
	elif next == Screen.CONFIRM_ABANDON:
		_confirm_abandon_page(content)
	elif next == Screen.TESTS:
		_test_page(content)
	elif next == Screen.SCORES:
		_scores_page(content)
	elif next == Screen.INITIALS:
		_initials_page(content)
	elif next == Screen.LANGUAGES:
		_languages_page(content)
	elif next == Screen.HOTSEAT_SETUP:
		_hotseat_setup_page(content)
	elif next == Screen.HOTSEAT_TURN:
		_hotseat_turn_page(content)
	elif next == Screen.HOTSEAT_RESULTS:
		_hotseat_results_page(content)
	elif next == Screen.ARCHIVES:
		_archives_page(content)
	elif next == Screen.CONTROLS_HELP:
		_help_page(content)
	elif next == Screen.ABOUT:
		_about_page(content)
	elif next == Screen.PAUSE:
		_pause_page(content)
	else:
		_title_page(content)
	_add_prompt_bar(content, _prompts_for(next))
	_building = false


func _title_page(content: VBoxContainer) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	content.add_child(columns)
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 8)
	menu_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(menu_column)
	_caption(menu_column, tr("menu.beta") % ProjectSettings.get_setting("application/config/version"), 13, ACCENT)
	var wordmark := _load_texture(TITLE_WORDMARK)
	if wordmark:
		# Lettrage du logo, découpé dans l'image et passé en blanc.
		var title := TextureRect.new()
		title.name = "TitleWordmark"
		title.texture = wordmark
		var ratio := float(wordmark.get_width()) / maxf(wordmark.get_height(), 1.0)
		title.custom_minimum_size = Vector2(roundf(TITLE_HEIGHT * ratio), TITLE_HEIGHT)
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		menu_column.add_child(title)
		_make_about_link(title)
	else:
		var fallback := _caption(menu_column, "FLUVIAL STRIKE", 38, TEXT)
		fallback.name = "TitleWordmark"
		fallback.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_make_about_link(fallback)
	_caption(menu_column, tr("menu.record") % settings.record, 15, MUTED)
	menu_column.add_child(HSeparator.new())
	var solo := _button(menu_column, tr("menu.solo"), true)
	solo.pressed.connect(_request.bind(&"play"))
	_button(menu_column, tr("hotseat.title")).pressed.connect(_open_hotseat_setup)
	_button(menu_column, tr("menu.hangar")).pressed.connect(_show_page.bind(Screen.HANGAR))
	_button(menu_column, tr("menu.archives")).pressed.connect(_open_archives)
	_button(menu_column, tr("menu.settings")).pressed.connect(_open_settings)
	_button(menu_column, tr("help.title")).pressed.connect(_open_help.bind(HELP_TAB_MISSION))
	_quit_button = _hold_button(menu_column, tr("menu.quit"))
	(_quit_button as HoldButton).confirmed.connect(_request.bind(&"quit"))
	_status = _caption(menu_column, _notice_text(), 13, ACCENT)
	_aircraft_card(columns, settings.aircraft)
	solo.grab_focus()


func _aircraft_card(parent: Control, aircraft: String, with_chooser: bool = true) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color("#0c2531"), LINE, 12, 8))
	card.custom_minimum_size.x = 230
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	_caption(body, tr("menu.aircraft"), 13, MUTED)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(206, 115)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(preview)
	_build_hangar_viewport(preview)
	_card_name = _caption(body, "", 16, TEXT)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 8)
	body.add_child(identity)
	_card_flag = TextureRect.new()
	_card_flag.custom_minimum_size = Vector2(32, 20)
	_card_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(_card_flag)
	_card_country = _caption(identity, "", 13, MUTED)
	_card_country.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var chooser := HBoxContainer.new()
	chooser.visible = with_chooser
	_card_chooser = chooser
	chooser.alignment = BoxContainer.ALIGNMENT_CENTER
	chooser.add_theme_constant_override("separation", 10)
	body.add_child(chooser)
	var previous := _button(chooser, "◀", false, 28)
	previous.focus_mode = Control.FOCUS_NONE
	previous.pressed.connect(_cycle_aircraft.bind(-1))
	_card_count = _caption(chooser, "", 14, ACCENT)
	_card_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var next := _button(chooser, "▶", false, 28)
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(_cycle_aircraft.bind(1))
	_show_card_aircraft(aircraft)


func _show_card_aircraft(id: String) -> void:
	var entry: Dictionary = AIRCRAFT.AIRCRAFT[id]
	_card_name.text = entry.short
	_card_country.text = tr(entry.country)
	var flag_path: String = entry.flag
	if not _flags.has(flag_path):
		_flags[flag_path] = _load_flag(flag_path)
	_card_flag.texture = _flags[flag_path]
	_card_count.text = "%d / %d" % [AIRCRAFT.IDS.find(id) + 1, AIRCRAFT.IDS.size()]
	if is_instance_valid(_hangar_model):
		_hangar_scene.remove_child(_hangar_model)
		_hangar_model.queue_free()
	_hangar_model = _hangar_models.player_aircraft(id)
	_hangar_model.rotation.y = -0.28
	_hangar_scene.add_child(_hangar_model)
	_hangar_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Change l'avion depuis l'accueil, sans passer par le Hangar.
func _cycle_aircraft(direction: int) -> void:
	if screen == Screen.HOTSEAT_TURN:
		if _hotseat_row:
			_hotseat_row.step(direction)
		return
	if screen != Screen.TITLE:
		return
	var index := AIRCRAFT.IDS.find(settings.aircraft)
	settings.aircraft = AIRCRAFT.IDS[posmod(index + direction, AIRCRAFT.IDS.size())]
	aircraft_selection = settings.aircraft
	_show_card_aircraft(settings.aircraft)
	play_sound("move")
	_request(&"aircraft_selected")
	settings_committed.emit()


func _pause_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.beta") % ProjectSettings.get_setting("application/config/version"), 13, ACCENT)
	_caption(content, tr("menu.pause"), 38, TEXT)
	if _pause_flight:
		_caption(content, "%s %d   ·   %s %06d" % [tr("results.section"), _pause_flight.section,
			tr("common.score"), _pause_flight.score], 15, MUTED)
	else:
		_caption(content, tr("menu.record") % settings.record, 15, MUTED)
	content.add_child(HSeparator.new())
	var resume := _button(content, tr("menu.resume"), true)
	resume.pressed.connect(_request.bind(&"resume"))
	if _pause_manual:
		_hold_button(content, tr("menu.restart")).confirmed.connect(_request.bind(&"play"))
	else:
		_button(content, tr("menu.restart")).pressed.connect(_request.bind(&"play"))
	_button(content, tr("menu.settings")).pressed.connect(_open_settings)
	_button(content, tr("settings.tab_controls")).pressed.connect(_open_controls_help)
	if _pause_manual and not _pause_from_bridges:
		_hold_button(content, tr("common.main_menu")).confirmed.connect(_request.bind(&"abandon"))
	else:
		var exit_label := tr("results.bridge_report") if _pause_from_bridges else tr("common.main_menu")
		_button(content, exit_label).pressed.connect(_request.bind(&"title"))
	_status = _caption(content, _notice_text(), 13, ACCENT)
	resume.grab_focus()


func _open_archives() -> void:
	_archives_tab = 0
	_archives_focus_tab = false
	_show_page(Screen.ARCHIVES)


func _archives_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.archives"), 30, TEXT)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	var active_tab: Button
	for i in 2:
		# Les onglets sont sélectionnables : ← / → passent de l'un à l'autre, ↑ y remonte.
		var tab := _button(tabs, tr("menu.leaderboard") if i == 0 else tr("menu.replays"), i == _archives_tab, 32)
		tab.name = "ArchivesTab%d" % i
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_archives_tab.bind(i, true))
		if i == _archives_tab:
			active_tab = tab
	content.add_child(HSeparator.new())
	if _archives_tab == 0:
		_scores_grid(content)
		active_tab.grab_focus()
		return
	var best := settings.best_raid
	var latest := settings.last_raid
	var first := _replay_row(content, tr("common.best_raid"), best, &"best_replay", "menu.best_replay_help")
	_replay_row(content, tr("common.last_raid"), latest, &"last_replay", "menu.last_replay_help")
	_description = _caption(content, "", 13, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 36
	if _archives_focus_tab:
		active_tab.grab_focus()
	else:
		first.grab_focus()
	_describe(first)


func _replay_row(parent: Control, title: String, raid: RAID_REPLAY, action: StringName, help: String) -> OPTION_ROW:
	var row := _option_row(parent, title, PackedStringArray(), 0, "" if raid else help)
	if raid:
		row.set_value_text("%06d   ·   %d" % [raid.score, raid.bridge_ticks.size()])
		row.tooltip_text = "%s %d" % [tr("results.bridges"), raid.bridge_ticks.size()]
		row.pressed.connect(_request.bind(action))
	else:
		row.set_value_text("—")
		row.disabled = true
	return row


func _select_archives_tab(tab: int, focus_tab: bool = false) -> void:
	if tab != _archives_tab:
		_archives_tab = tab
		_archives_focus_tab = focus_tab
		_show_page(Screen.ARCHIVES)
		play_sound("move")


# --- Aide ---------------------------------------------------------------------

## Ouvre l'aide sur un onglet : Mission, Commandes, Cibles, Tableau de bord ou Conseils.
func _open_help(tab: int = HELP_TAB_MISSION) -> void:
	if screen != Screen.CONTROLS_HELP:
		_help_return = screen
	_help_tab = clampi(tab, 0, HELP_TABS.size() - 1)
	_show_page(Screen.CONTROLS_HELP)


func _open_controls_help() -> void:
	_open_help(HELP_TAB_CONTROLS)


func _select_help_tab(tab: int) -> void:
	tab = posmod(tab, HELP_TABS.size())
	if tab != _help_tab:
		_help_tab = tab
		_show_page(Screen.CONTROLS_HELP)
		play_sound("move")


func _help_page(content: VBoxContainer) -> void:
	_caption(content, tr("help.title"), 30, TEXT)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	var active: Button
	for i in HELP_TABS.size():
		var tab := _button(tabs, tr(HELP_TABS[i]), i == _help_tab, 32)
		tab.name = "HelpTab%d" % i
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_help_tab.bind(i))
		if i == _help_tab:
			active = tab
	content.add_child(HSeparator.new())
	var body := VBoxContainer.new()
	body.custom_minimum_size.y = HELP_BODY_HEIGHT
	body.add_theme_constant_override("separation", 7)
	content.add_child(body)
	match _help_tab:
		HELP_TAB_MISSION:
			_help_mission(body)
		HELP_TAB_CONTROLS:
			_help_controls(body)
		HELP_TAB_TARGETS:
			_help_targets(body)
		HELP_TAB_DASHBOARD:
			_help_dashboard(body)
		HELP_TAB_TIPS:
			_help_tips(body)
	active.grab_focus()


func _help_section(parent: Control, title: String, text: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 1)
	parent.add_child(block)
	_caption(block, title.to_upper(), 13, ACCENT)
	var label := _caption(block, text, 15, TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 600


func _help_mission(body: VBoxContainer) -> void:
	_help_section(body, tr("help.goal_title"), tr("help.goal"))
	_help_section(body, tr("help.river_title"), tr("help.river"))
	_help_section(body, tr("help.lives_title"), tr("help.lives"))
	_help_section(body, tr("help.difficulty_title"), tr("help.difficulty"))
	_help_section(body, tr("hotseat.title"), tr("help.duel"))


func _help_controls(body: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	_caption(grid, "", 13, MUTED).custom_minimum_size.x = 210
	_caption(grid, tr("settings.keyboard"), 13, ACCENT).custom_minimum_size.x = 150
	_caption(grid, tr("settings.controller"), 13, ACCENT).custom_minimum_size.x = 180
	for i in SETTINGS.ACTIONS.size():
		_caption(grid, tr(SETTINGS.ACTIONS[i][1]), 16, TEXT)
		_caption(grid, _binding_text(i, false), 16, MUTED)
		var pad := _binding_text(i, true)
		if i < 4:
			pad += " · " + tr("settings.stick")
		_caption(grid, pad, 16, MUTED)
	_caption(grid, tr("menu.pause"), 16, TEXT)
	_caption(grid, tr("key.escape"), 16, MUTED)
	_caption(grid, "Start", 16, MUTED)
	var note := _caption(body, tr("help.controls_note"), 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 600


func _help_targets(body: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for target: Array in HELP_TARGETS:
		var icon := TextureRect.new()
		icon.texture = _load_texture(HELP_TARGET_ICON % target[0])
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		grid.add_child(icon)
		var name := _caption(grid, tr(target[1]), 16, TEXT)
		name.custom_minimum_size.x = 150
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var points := _caption(grid, str(target[2]), 18, ACCENT)
		points.custom_minimum_size.x = 50
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var note := _caption(grid, tr(target[3]), 13, MUTED)
		note.custom_minimum_size.x = 330
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(HSeparator.new())
	_help_section(body, tr("help.loss_title"), tr("help.loss"))


func _help_dashboard(body: VBoxContainer) -> void:
	# Tableau de bord en miniature, aux couleurs du jeu, avec ses repères numérotés.
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", _box(INK, LINE, 8, 4))
	body.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)
	var fuel := _help_strip_cell(row, 1, 160)
	_caption(fuel, "62 %", 22, TEXT)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	fuel.add_child(bar)
	for i in 10:
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(13, 6)
		segment.color = Color("#a8ecc9") if i < 6 else Color("#1d3a45")
		bar.add_child(segment)
	var lives := _help_strip_cell(row, 2, 90)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	lives.add_child(icons)
	var life := _load_texture("res://hud/life_%s.png" % settings.aircraft)
	for i in 3:
		var jet := TextureRect.new()
		jet.texture = life
		jet.custom_minimum_size = Vector2(18, 18)
		jet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		jet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icons.add_child(jet)
	var speed := _help_strip_cell(row, 3, 80)
	_caption(speed, tr("hud.speed"), 11, MUTED)
	_caption(speed, "128", 18, TEXT)
	var score := _help_strip_cell(row, 4, 110)
	_caption(score, tr("hud.score"), 11, MUTED)
	_caption(score, "012480", 18, TEXT)
	var section := _help_strip_cell(row, 5, 100)
	_caption(section, tr("hud.section") % 4, 14, TEXT)
	_caption(section, tr("hud.reserves") % 3, 11, MUTED)
	var legend := GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 10)
	legend.add_theme_constant_override("v_separation", 3)
	body.add_child(legend)
	for i in HELP_DASHBOARD.size():
		_caption(legend, "%d" % (i + 1), 14, ACCENT)
		var line := _caption(legend, tr(HELP_DASHBOARD[i]), 14, TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 570
	_help_section(body, tr("help.fuel_title"), tr("help.fuel"))


func _help_strip_cell(row: HBoxContainer, number: int, width: float) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size.x = width
	cell.add_theme_constant_override("separation", 2)
	row.add_child(cell)
	_caption(cell, "%d" % number, 11, ACCENT)
	return cell


func _help_tips(body: VBoxContainer) -> void:
	for key: String in HELP_TIPS:
		var tip := HBoxContainer.new()
		tip.add_theme_constant_override("separation", 10)
		body.add_child(tip)
		var mark := _caption(tip, "›", 18, ACCENT)
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var text := _caption(tip, tr(key), 15, TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 580
	var credit := _caption(body, tr("help.credit"), 12, MUTED)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size.x = 600


# --- À propos ---------------------------------------------------------------

## Le titre du menu principal ouvre « À propos » au clic. Il reste hors de la
## navigation au clavier et à la manette (aucun focus possible).
func _make_about_link(title: Control) -> void:
	title.focus_mode = Control.FOCUS_NONE
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title.tooltip_text = tr("about.title")
	title.mouse_entered.connect(func() -> void: title.modulate = ACCENT)
	title.mouse_exited.connect(func() -> void: title.modulate = Color.WHITE)
	title.gui_input.connect(_on_title_input)


func _on_title_input(event: InputEvent) -> void:
	if screen == Screen.TITLE and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		open_about()


func open_about() -> void:
	play_sound("accept")
	_show_page(Screen.ABOUT)
	_play_about_voice()


func _play_about_voice() -> void:
	if _voice == null or settings == null or settings.muted or settings.volume <= 0:
		return
	if _voice.stream == null:
		_voice.stream = _load_audio(ABOUT_VOICE)
	if _voice.stream:
		_voice.stop()
		_voice.play()


## Charge un son importé par l'éditeur, ou directement le fichier MP3 sans import préalable.
func _load_audio(path: String) -> AudioStream:
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(path + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream:
			return stream
	if FileAccess.file_exists(path):
		return AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
	return null


func _about_page(content: VBoxContainer) -> void:
	_caption(content, tr("about.title"), 30, TEXT)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	content.add_child(layout)

	# Portrait de l'auteur, fondu vers le fond du panneau sur son bord droit.
	var portrait_box := Control.new()
	portrait_box.custom_minimum_size = Vector2(200, 285)
	portrait_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layout.add_child(portrait_box)
	var portrait_texture := _load_texture(ABOUT_PORTRAIT)
	if portrait_texture:
		var portrait := TextureRect.new()
		portrait.name = "AboutPortrait"
		portrait.texture = portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_box.add_child(portrait)
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.6, 1.0])
	gradient.colors = PackedColorArray([Color(INK, 0.0), INK])
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = gradient
	fade_texture.width = 64
	fade_texture.height = 4
	fade_texture.fill_from = Vector2(0, 0)
	fade_texture.fill_to = Vector2(1, 0)
	var fade := TextureRect.new()
	fade.texture = fade_texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_box.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := Panel.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = LINE
	frame_style.border_width_left = 1
	frame_style.border_width_top = 1
	frame_style.border_width_bottom = 1
	frame_style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = AUTHOR_URL
	frame.gui_input.connect(_on_link_input.bind(AUTHOR_URL))
	portrait_box.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 420
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	layout.add_child(info)
	var version := str(ProjectSettings.get_setting("application/config/version"))
	var wordmark := _load_texture(TITLE_WORDMARK)
	if wordmark:
		var name_mark := TextureRect.new()
		name_mark.texture = wordmark
		name_mark.custom_minimum_size = Vector2(roundf(26.0 * wordmark.get_width() / maxf(wordmark.get_height(), 1.0)), 26)
		name_mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		name_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		name_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		name_mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		name_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name_mark)
	else:
		_caption(info, "FLUVIAL STRIKE", 26, TEXT)
	_caption(info, tr("menu.beta") % version, 13, ACCENT)
	_wrapped(info, tr("about.description"), 15, TEXT)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	info.add_child(grid)
	var engine := Engine.get_version_info()
	var rows := [
		["about.version", version],
		["about.author", AUTHOR_NAME],
		["about.license", "MIT"],
		["about.repository", ""],
		["about.engine", "Godot %d.%d · GDScript" % [engine["major"], engine["minor"]]],
	]
	for row in rows:
		_caption(grid, tr(row[0]), 14, MUTED)
		if row[0] == "about.repository":
			var link := LinkButton.new()
			link.text = REPOSITORY_URL.trim_prefix("https://")
			link.focus_mode = Control.FOCUS_NONE
			link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			link.add_theme_font_size_override("font_size", 14)
			link.add_theme_color_override("font_color", ACCENT)
			link.add_theme_color_override("font_hover_color", Color.WHITE)
			link.tooltip_text = REPOSITORY_URL
			link.pressed.connect(_open_url.bind(REPOSITORY_URL))
			grid.add_child(link)
		else:
			_caption(grid, row[1], 14, TEXT)

	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", _box(Color("#0c2531"), LINE, 10, 6))
	info.add_child(note)
	_wrapped(note, tr("about.note"), 13, MUTED)

	content.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var profile := _button(actions, tr("about.profile"))
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.pressed.connect(_open_url.bind(AUTHOR_URL))
	var repository := _button(actions, tr("about.repository_button"))
	repository.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repository.pressed.connect(_open_url.bind(REPOSITORY_URL))
	var close := _button(actions, tr("common.close"), true)
	close.name = "AboutClose"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(back)
	close.grab_focus()


func _wrapped(parent: Control, text: String, points: int, color: Color) -> Label:
	var label := _caption(parent, text, points, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _on_link_input(event: InputEvent, url: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		play_sound("accept")
		_open_url(url)


func _open_url(url: String) -> void:
	if DisplayServer.get_name() != "headless":
		OS.shell_open(url)


func _open_hotseat_setup() -> void:
	show_hotseat_setup(Vector2i(EMPTY_SLOT, EMPTY_SLOT))


# --- Deux joueurs : ralliement -------------------------------------------------

func _hotseat_setup_page(content: VBoxContainer) -> void:
	_caption(content, tr("hotseat.title"), 30, TEXT)
	_caption(content, tr("hotseat.rules"), 15, MUTED)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	content.add_child(slots)
	for player in 2:
		_hotseat_slot(slots, player)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var start := _button(actions, tr("menu.play"), true)
	start.name = "HotseatStart"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.disabled = not _hotseat_ready()
	start.pressed.connect(_start_hotseat)
	var back_button := _button(actions, tr("common.back"))
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(back)
	_status = _caption(content, "", 13, ACCENT)
	start.grab_focus()


func _hotseat_slot(parent: Control, player: int) -> void:
	var device := hotseat_devices[player]
	var taken := device != EMPTY_SLOT
	var slot := PanelContainer.new()
	slot.name = "HotseatSlot%d" % player
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.custom_minimum_size.y = 118
	slot.add_theme_stylebox_override("panel", _box(Color("#102b37") if taken else Color("#0b2230"),
		ACCENT if taken else LINE, 12, 8))
	parent.add_child(slot)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(body)
	_caption(body, tr("hotseat.player") % (player + 1), 16, ACCENT if taken else MUTED)
	if taken:
		_caption(body, ("✔  " if _hotseat_device_ready(player) else "") + _device_label(device), 16, TEXT)
		if device == -1:
			var keys := PackedStringArray()
			for key in settings.hotseat_keys(player, hotseat_devices):
				keys.append(OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(key as Key)))
			_caption(body, "  ·  ".join(keys), 13, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	# Place libre : un clic la donne au clavier.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_join_hotseat(-1))
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(keys)
	var pad_family := glyphs.device if glyphs.is_pad() else INPUT_GLYPHS.Device.XBOX
	keys.add_child(INPUT_GLYPHS.Glyph.new(pad_family, INPUT_GLYPHS.Prompt.ACCEPT, ""))
	_caption(keys, "/", 13, MUTED).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keys.add_child(INPUT_GLYPHS.Glyph.new(INPUT_GLYPHS.Device.KEYBOARD, INPUT_GLYPHS.Prompt.ACCEPT, tr("input.space") + "|F"))
	_caption(body, tr("hotseat.join_hint"), 14, MUTED)


func _device_label(device: int) -> String:
	if device == -1:
		return tr("settings.keyboard")
	var connected := Input.get_connected_joypads()
	if device not in connected:
		return tr("hotseat.unavailable")
	var name := Input.get_joy_name(device)
	return "%d · %s" % [connected.find(device) + 1, name if not name.is_empty() else tr("settings.controller")]


func _hotseat_device_ready(player: int) -> bool:
	return SETTINGS.hotseat_device_ready(player, hotseat_devices, Input.get_connected_joypads())


func _hotseat_ready() -> bool:
	return _hotseat_device_ready(0) and _hotseat_device_ready(1)


## Donne la première place libre à un périphérique (-1 pour le clavier).
func _join_hotseat(device: int) -> bool:
	if device != -1 and device in [hotseat_devices.x, hotseat_devices.y]:
		return false
	for player in 2:
		if hotseat_devices[player] == EMPTY_SLOT:
			hotseat_devices[player] = device
			play_sound("accept")
			if device >= 0 and settings.vibration > 0:
				var strength := settings.vibration / 100.0
				Input.start_joy_vibration(device, 0.3 * strength, 0.6 * strength, 0.18)
			_show_page(Screen.HOTSEAT_SETUP)
			return true
	play_sound("denied")
	return false


func _leave_hotseat(device: int) -> bool:
	for player in [1, 0]:
		if hotseat_devices[player] == device:
			hotseat_devices[player] = EMPTY_SLOT
			play_sound("back")
			_show_page(Screen.HOTSEAT_SETUP)
			return true
	return false


func _start_hotseat() -> void:
	if screen != Screen.HOTSEAT_SETUP:
		return
	if _hotseat_ready():
		_request(&"hotseat_start")
	else:
		play_sound("denied")


## Entrées propres au Duel. Renvoie true si l'événement est consommé.
func _handle_hotseat_input(event: InputEvent) -> bool:
	if screen == Screen.HOTSEAT_SETUP:
		if event is InputEventJoypadButton and event.pressed:
			match event.button_index:
				JOY_BUTTON_A:
					_join_hotseat(event.device)
					return true
				JOY_BUTTON_B:
					return _leave_hotseat(event.device)
				JOY_BUTTON_START:
					_start_hotseat()
					return true
		elif event is InputEventKey and event.pressed and not event.echo:
			var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			match key:
				KEY_SPACE, KEY_F:
					_join_hotseat(-1)
					return true
				KEY_BACKSPACE:
					_leave_hotseat(-1)
					return true
		return false
	if screen != Screen.HOTSEAT_TURN:
		return false
	var device := hotseat_devices[_hotseat_next]
	var on_leave := is_instance_valid(_hotseat_leave) and get_viewport().gui_get_focus_owner() == _hotseat_leave
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A, JOY_BUTTON_START:
				if on_leave and event.button_index == JOY_BUTTON_A:
					return false
				if event.device == device:
					_continue_hotseat()
				elif not _hotseat_device_ready(_hotseat_next) and event.device != hotseat_devices[1 - _hotseat_next]:
					# La manette du joueur a disparu : une autre manette libre prend sa place.
					hotseat_devices[_hotseat_next] = event.device
					play_sound("accept")
					_show_page(Screen.HOTSEAT_TURN)
				else:
					play_sound("denied")
				return true
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				_cycle_aircraft(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
				return true
	elif event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed(&"ui_accept"):
		if on_leave:
			return false
		if device == -1:
			_continue_hotseat()
		else:
			play_sound("denied")
		return true
	return false


## Famille de glyphes de la barre d'aide : au passage de pilote, celle du joueur attendu,
## sinon celle du dernier périphérique utilisé.
func _prompt_device() -> INPUT_GLYPHS.Device:
	if screen == Screen.HOTSEAT_TURN:
		var device := hotseat_devices[_hotseat_next]
		if device == -1:
			return INPUT_GLYPHS.Device.KEYBOARD
		if device in Input.get_connected_joypads():
			return INPUT_GLYPHS.family(device)
	return glyphs.device


# --- Deux joueurs : passage de pilote -------------------------------------------

func _hotseat_turn_page(content: VBoxContainer) -> void:
	_caption(content, tr("hotseat.turn") % (_hotseat_next + 1), 30, TEXT)
	var device := hotseat_devices[_hotseat_next]
	if _hotseat_device_ready(_hotseat_next):
		_caption(content, _device_label(device), 16, MUTED)
	else:
		var warning := _caption(content, tr("hotseat.reconnect"), 15, ACCENT)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	if _hotseat_choose_aircraft:
		var ids: Array[String] = []
		var names := PackedStringArray()
		for id: String in AIRCRAFT.IDS:
			if id != _hangar_unavailable:
				ids.append(id)
				names.append(AIRCRAFT.AIRCRAFT[id].short)
		_hotseat_row = _option_row(left, tr("menu.aircraft"), names, ids.find(aircraft_selection))
		_hotseat_row.value_changed.connect(func(index: int) -> void:
			aircraft_selection = ids[index]
			_show_card_aircraft(aircraft_selection))
	else:
		_caption(left, AIRCRAFT.AIRCRAFT[aircraft_selection].name, 16, TEXT)
	var go := _button(left, tr("hotseat.go"), true)
	go.pressed.connect(_continue_hotseat)
	_hotseat_leave = _button(left, tr("common.main_menu"))
	_hotseat_leave.pressed.connect(_request.bind(&"title"))
	_aircraft_card(columns, aircraft_selection, _hotseat_choose_aircraft)
	_status = _caption(content, "", 13, ACCENT)
	if _hotseat_row:
		_hotseat_row.grab_focus()
	else:
		go.grab_focus()


func _continue_hotseat() -> void:
	if screen != Screen.HOTSEAT_TURN:
		return
	if not _hotseat_device_ready(_hotseat_next):
		play_sound("denied")
		return
	play_sound("accept")
	_request(&"hotseat_continue")


func _hotseat_results_page(content: VBoxContainer) -> void:
	_caption(content, tr("results.title"), 30, TEXT)
	var scores := GridContainer.new()
	scores.columns = 3
	scores.add_theme_constant_override("h_separation", 18)
	content.add_child(scores)
	_caption(scores, "", 15, MUTED)
	for player in range(2):
		_caption(scores, tr("hotseat.player") % (player + 1), 16, ACCENT)
	var first := _hotseat_results[0]
	var second := _hotseat_results[1]
	_result_row(scores, tr("common.score"), "%06d" % first.score, "%06d" % second.score)
	_result_row(scores, tr("results.section"), str(first.section), str(second.section))
	_result_row(scores, tr("results.bridges"), str(first.section - 1), str(second.section - 1))
	var winner := 1 if first.score > second.score else 2
	_caption(content, tr("hotseat.tie") if first.score == second.score else tr("hotseat.winner") % winner, 16, ACCENT)
	var retry := _button(content, tr("results.retry"), true)
	retry.pressed.connect(_request.bind(&"hotseat_restart"))
	var home := _button(content, tr("common.main_menu"))
	home.pressed.connect(_request.bind(&"title"))
	retry.grab_focus()


func _test_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.test"), 30, TEXT)
	var replay := _button(content, tr("menu.reference_replay"), true)
	replay.pressed.connect(_request.bind(&"reference"))
	var return_button := _button(content, tr("menu.back_to_main"))
	return_button.pressed.connect(back)
	replay.grab_focus()


func _results_page(content: VBoxContainer, flight: FLIGHT) -> void:
	_caption(content, tr("results.title"), 34, TEXT)
	if flight.status == FLIGHT.Status.COMPLETE:
		_caption(content, tr("common.raid_complete"), 15, ACCENT)
	if flight.cheats != 0:
		_caption(content, tr("results.cheats"), 14, MUTED)
	content.add_child(HSeparator.new())
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 9)
	content.add_child(stats)
	_caption(stats, "", 15, MUTED).custom_minimum_size.x = 162
	_caption(stats, tr("results.this_raid"), 15, TEXT).custom_minimum_size.x = 108
	_caption(stats, tr("results.local_records"), 15, ACCENT)
	var has_progress := settings.furthest_section > 0
	_result_row(stats, tr("common.score"), "%06d" % flight.score, "%06d" % settings.record)
	_result_row(stats, tr("results.section"), str(flight.section), str(settings.furthest_section) if has_progress else "—")
	_result_row(stats, tr("results.bridges"), str(flight.section - 1), str(settings.most_bridges) if has_progress else "—")
	content.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var retry := _button(actions, tr("results.retry"), true)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(_request.bind(&"play"))
	var home := _button(actions, tr("common.main_menu"))
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(_request.bind(&"title"))
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 8)
	content.add_child(extra)
	var detail := _button(extra, tr("results.bridge_report"))
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.pressed.connect(show_bridge_results)
	var scores_button := _button(extra, tr("menu.leaderboard"))
	scores_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scores_button.pressed.connect(_open_scores.bind(Screen.RESULTS))
	if _pending_score > 0:
		_button(content, tr("scores.enter")).pressed.connect(_open_initials)
	_status = _caption(content, _notice_text(), 13, ACCENT)
	retry.grab_focus()


func _open_scores(return_to: Screen) -> void:
	_scores_return = return_to
	_show_page(Screen.SCORES)


func _scores_page(content: VBoxContainer) -> void:
	_caption(content, tr("scores.title"), 30, TEXT)
	_scores_grid(content)
	var return_button := _button(content, tr("common.back"))
	return_button.pressed.connect(back)
	return_button.grab_focus()


# Deux classements côte à côte : raids en Novice, raids en Expert.
func _scores_grid(content: VBoxContainer) -> void:
	var boards := HBoxContainer.new()
	boards.add_theme_constant_override("separation", 34)
	boards.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(boards)
	_scores_board(boards, tr("settings.difficulty_novice"), settings.scores)
	var divider := VSeparator.new()
	boards.add_child(divider)
	_scores_board(boards, tr("settings.difficulty_expert"), settings.scores_expert)


func _scores_board(parent: Control, title: String, entries: Array[Dictionary]) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	_caption(column, title.to_upper(), 14, ACCENT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)
	column.add_child(grid)
	_caption(grid, tr("scores.rank"), 13, MUTED).custom_minimum_size.x = 34
	_caption(grid, tr("scores.initials"), 13, MUTED).custom_minimum_size.x = 80
	var heading := _caption(grid, tr("common.score"), 13, MUTED)
	heading.custom_minimum_size.x = 90
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in SETTINGS.SCORE_LIMIT:
		var entry: Dictionary = entries[i] if i < entries.size() else {}
		var color := ACCENT if i == 0 and not entry.is_empty() else (MUTED if entry.is_empty() else TEXT)
		_caption(grid, "%02d" % (i + 1), 15, color)
		_caption(grid, entry.get("initials", "—"), 15, color)
		var value := "%06d" % entry.score if not entry.is_empty() else "—"
		_caption(grid, value, 15, color).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _open_initials() -> void:
	_initials = "AAA"
	_initial_index = 0
	_initial_stick = Vector2i.ZERO
	_show_page(Screen.INITIALS)


func _initials_page(content: VBoxContainer) -> void:
	_caption(content, tr("scores.enter_title"), 30, TEXT)
	_caption(content, tr("scores.points") % _pending_score, 22, ACCENT)
	_caption(content, "%s · %s" % [tr("scores.title"), tr("settings.difficulty_expert" if _pending_expert else "settings.difficulty_novice")], 15, MUTED)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	for i in 3:
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", _box(Color("#102b37"), LINE, 8, 5))
		row.add_child(tile)
		var letter := _caption(tile, "", 36, TEXT)
		letter.custom_minimum_size = Vector2(48, 53)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_initial_labels.append(letter)
	_refresh_initials()
	_caption(content, tr("scores.controls"), 14, MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var save_button := _button(actions, tr("scores.save"), true)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_submit_initials)
	var skip := _button(actions, tr("scores.skip"))
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip.pressed.connect(back)
	_status = _caption(content, "", 13, ACCENT)


func _refresh_initials() -> void:
	for i in _initial_labels.size():
		var tile := _initial_labels[i].get_parent() as PanelContainer
		tile.add_theme_stylebox_override("panel", _box(Color("#102b37"), ACCENT if i == _initial_index else LINE, 8, 5))
		_initial_labels[i].text = _initials[i]
		_initial_labels[i].add_theme_color_override("font_color", ACCENT if i == _initial_index else TEXT)


func _submit_initials() -> void:
	if screen != Screen.INITIALS or _pending_score <= 0:
		return
	play_sound("accept")
	var error := settings.submit_score(_initials, _pending_score, _pending_expert)
	if error != OK and error != ERR_UNAVAILABLE:
		_status.text = tr("scores.save_failed")
		return
	_pending_score = 0
	_open_scores(Screen.RESULTS)


func _set_initial(letter: String) -> void:
	_initials = _initials.substr(0, _initial_index) + letter + _initials.substr(_initial_index + 1)


func _handle_initials(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_START:
				_submit_initials()
				return true
			JOY_BUTTON_A:
				if _initial_index >= 2:
					_submit_initials()
				else:
					_initial_index += 1
					_refresh_initials()
					play_sound("move")
				return true
			JOY_BUTTON_B:
				if _initial_index == 0:
					play_sound("back")
					back()
				else:
					_initial_index -= 1
					_refresh_initials()
					play_sound("back")
				return true
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		_submit_initials()
		return true
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_BACKSPACE or event.keycode == KEY_BACKSPACE:
			_initial_index = maxi(0, _initial_index - 1)
			_refresh_initials()
			return true
		if not event.echo and event.unicode >= 65 and event.unicode <= 122 \
				and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			var letter := String.chr(event.unicode).to_upper()
			if SETTINGS.INITIALS_ALPHABET.contains(letter):
				_set_initial(letter)
				_initial_index = mini(2, _initial_index + 1)
				_refresh_initials()
				return true
	var direction := Vector2i.ZERO
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var axis := int(event.axis == JOY_AXIS_LEFT_Y)
		if absf(event.axis_value) < 0.4:
			_initial_stick[axis] = 0
		elif absf(event.axis_value) >= 0.65:
			var tilt := int(signf(event.axis_value))
			if tilt != _initial_stick[axis]:
				direction[axis] = tilt
			_initial_stick[axis] = tilt
	elif event.is_action_pressed(&"ui_left", true):
		direction.x = -1
	elif event.is_action_pressed(&"ui_right", true):
		direction.x = 1
	elif event.is_action_pressed(&"ui_up", true):
		direction.y = -1
	elif event.is_action_pressed(&"ui_down", true):
		direction.y = 1
	if direction == Vector2i.ZERO:
		return event is InputEventJoypadMotion
	_initials_step(direction)
	return true


func _initials_step(direction: Vector2i) -> void:
	_initial_index = posmod(_initial_index + direction.x, 3)
	if direction.y != 0:
		var alphabet := SETTINGS.INITIALS_ALPHABET
		var index := alphabet.find(_initials[_initial_index])
		_set_initial(alphabet[posmod(index - direction.y, alphabet.length())])
	_refresh_initials()
	play_sound("move")


func _result_row(grid: GridContainer, title: String, run: String, best: String) -> void:
	_caption(grid, title, 16, MUTED)
	_caption(grid, run, 22, TEXT)
	_caption(grid, best, 22, ACCENT)


func _bridge_results_page(content: VBoxContainer) -> void:
	_caption(content, tr("results.bridge_report"), 30, TEXT)
	_caption(content, tr("bridges.explanation"), 14, MUTED)
	var best := settings.best_raid
	_bridge_total = maxi(_result_raid.bridge_ticks.size() if _result_raid else 0, best.bridge_ticks.size() if best else 0)
	if _bridge_total > 0:
		var headings := HBoxContainer.new()
		headings.add_theme_constant_override("separation", 8)
		content.add_child(headings)
		_bridge_cell(headings, "", BRIDGE_COLUMNS[0], MUTED)
		_bridge_cell(headings, tr("results.this_raid"), 341, TEXT)
		_bridge_cell(headings, tr("common.best_raid"), 180, ACCENT)
		var columns := _bridge_grid()
		content.add_child(columns)
		_bridge_cell(columns, tr("bridges.bridge"), BRIDGE_COLUMNS[0], MUTED)
		for group in 2:
			var labels := [tr("bridges.time"), tr("bridges.points"), tr("bridges.fuel"), tr("bridges.losses"), ""]
			for column in labels.size():
				_bridge_cell(columns, labels[column], BRIDGE_COLUMNS[column + 1], MUTED)
		_bridge_table = HBoxContainer.new()
		_bridge_table.add_theme_constant_override("separation", 8)
		content.add_child(_bridge_table)
		var grid := _bridge_grid()
		_bridge_table.add_child(grid)
		for slot in mini(_bridge_total, VISIBLE_BRIDGE_ROWS):
			_bridge_rows.append({
				"number": _bridge_cell(grid, "", BRIDGE_COLUMNS[0], TEXT),
				"current": _make_bridge_group(grid, slot, false),
				"best": _make_bridge_group(grid, slot, true),
			})
		_bridge_scroll = VScrollBar.new()
		_bridge_scroll.focus_mode = Control.FOCUS_NONE
		_bridge_scroll.step = 1.0
		_bridge_scroll.max_value = _bridge_total
		_bridge_scroll.page = _bridge_rows.size()
		_bridge_scroll.visible = _bridge_total > _bridge_rows.size()
		_bridge_scroll.custom_minimum_size.x = 16
		_bridge_scroll.value_changed.connect(_scroll_bridges_to)
		_bridge_table.add_child(_bridge_scroll)
		_set_bridge_top(_bridge_top)
		_status = _caption(content, "", 13, MUTED)
		var pending := best != null and not best.prepare_bridge_stats(0)
		if pending:
			_status.text = tr("bridges.calculating")
		_bridge_pending = pending
	else:
		_caption(content, tr("bridges.empty"), 16, MUTED)
		_bridge_pending = false

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_bridge_back = _button(footer, tr("bridges.back"))
	_bridge_back.pressed.connect(back)
	if _bridge_rows.is_empty():
		_bridge_back.grab_focus()
	else:
		_focus_bridge(clampi(_bridge_focus.x, _bridge_top, _bridge_total - 1), _bridge_focus.y == 1)


func _bridge_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 11
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
	return grid


func _make_bridge_group(grid: GridContainer, slot: int, best: bool) -> Dictionary:
	var labels: Array[Label] = []
	for i in 4:
		labels.append(_bridge_cell(grid, "", BRIDGE_COLUMNS[i + 1], ACCENT if best else TEXT))
	var watch := _button(grid, tr("bridges.watch"), false, 33)
	watch.custom_minimum_size.x = BRIDGE_COLUMNS[-1]
	watch.pressed.connect(_watch_bridge.bind(best, slot))
	return {"labels": labels, "watch": watch}


func _refresh_bridge_rows() -> void:
	for slot in _bridge_rows.size():
		var row := _bridge_rows[slot]
		var index := _bridge_top + slot
		row.number.text = "%02d" % (index + 1)
		_fill_bridge_group(row.current, _result_raid, index, false)
		_fill_bridge_group(row.best, settings.best_raid, index, true)


func _fill_bridge_group(group: Dictionary, raid: RAID_REPLAY, index: int, best: bool) -> void:
	var values := ["—", "—", "—", "—"]
	var available := raid != null and index < raid.bridge_ticks.size()
	if available:
		var previous_tick := raid.bridge_ticks[index - 1] if index > 0 else 0
		var tenths := (raid.bridge_ticks[index] - previous_tick) / 6
		values[0] = tr("bridges.time_format") % [tenths / 600, (tenths / 10) % 60, tenths % 10]
		var offset := index * RAID_REPLAY.BRIDGE_STATS_WIDTH
		if offset < raid.bridge_stats.size():
			values[1] = "+%d" % raid.bridge_stats[offset]
			values[2] = "%d %%" % roundi(100.0 * clampi(raid.bridge_stats[offset + 1], 0, FLIGHT.FULL_TANK) / FLIGHT.FULL_TANK)
			values[3] = str(raid.bridge_stats[offset + 2])
	for i in values.size():
		group.labels[i].text = values[i]
	var watch: Button = group.watch
	watch.disabled = not available
	watch.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	watch.modulate.a = 1.0 if available else 0.0
	watch.tooltip_text = tr("bridges.watch_best" if best else "bridges.watch_current") % (index + 1) if available else ""


func _bridge_cell(parent: Control, text: String, width: int, color: Color) -> Label:
	var cell := _caption(parent, text, 15, color)
	cell.custom_minimum_size.x = width
	return cell


func _focused_bridge() -> Vector2i:
	var focus := get_viewport().gui_get_focus_owner()
	for slot in _bridge_rows.size():
		var row := _bridge_rows[slot]
		if focus == row.current.watch:
			return Vector2i(_bridge_top + slot, 0)
		if focus == row.best.watch:
			return Vector2i(_bridge_top + slot, 1)
	return Vector2i(-1, 0)


func _focus_bridge(index: int, best: bool) -> void:
	if index < 0 or index >= _bridge_total:
		_bridge_back.grab_focus()
		return
	if index < _bridge_top:
		_set_bridge_top(index)
	elif index >= _bridge_top + _bridge_rows.size():
		_set_bridge_top(index - _bridge_rows.size() + 1)
	var row := _bridge_rows[index - _bridge_top]
	var watch: Button = row.best.watch if best else row.current.watch
	if watch.disabled:
		watch = row.current.watch if best else row.best.watch
	watch.grab_focus()


func _step_bridge_focus(direction: int) -> void:
	if _bridge_rows.is_empty():
		return
	var focus := _focused_bridge()
	var index := focus.x + direction if focus.x >= 0 else (0 if direction > 0 else _bridge_total - 1)
	_focus_bridge(index, focus.y == 1)


func _set_bridge_top(top: int) -> void:
	_bridge_top = clampi(top, 0, _bridge_total - _bridge_rows.size())
	_bridge_scroll.set_value_no_signal(_bridge_top)
	_refresh_bridge_rows()


func _scroll_bridges_to(value: float) -> void:
	if _bridge_rows.is_empty():
		return
	var focus := _focused_bridge()
	var old_top := _bridge_top
	var top := clampi(roundi(value), 0, _bridge_total - _bridge_rows.size())
	if top == old_top:
		return
	_set_bridge_top(top)
	var index := focus.x + top - old_top if focus.x >= 0 else top
	_focus_bridge(index, focus.y == 1)


func _watch_bridge(best: bool, slot: int) -> void:
	var index := _bridge_top + slot
	_bridge_focus = Vector2i(index, int(best))
	bridge_replay_requested.emit(best, index)


func _process(delta: float) -> void:
	if _bridge_pending and screen == Screen.BRIDGES and settings.best_raid.prepare_bridge_stats(720):
		_status.text = ""
		_refresh_bridge_rows()
		_bridge_pending = false
	_update_binding_countdown()
	_update_repeat(delta)


## Répète la navigation quand une direction reste maintenue à la croix ou au stick.
## Le premier pas vient de l'événement lui-même ; le clavier garde la répétition du système.
## Une direction déjà maintenue à l'ouverture d'un écran ne se répète qu'après avoir été relâchée.
func _update_repeat(delta: float) -> void:
	var direction := _held_pad_direction()
	if direction == Vector2i.ZERO:
		_repeat_armed = true
	if direction != _held:
		_held = direction
		_held_time = 0.0
		_next_repeat = REPEAT_DELAY
		return
	if direction == Vector2i.ZERO or not _repeat_armed:
		return
	_held_time += delta
	if _held_time >= _next_repeat:
		_next_repeat += REPEAT_INTERVAL
		_repeat_step(direction)


func _held_pad_direction() -> Vector2i:
	var dpad := Vector2i.ZERO
	var stick := Vector2.ZERO
	for pad in Input.get_connected_joypads():
		dpad.x += int(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT))
		dpad.y += int(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN)) - int(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP))
		var axes := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if axes.length() > stick.length():
			stick = axes
	for axis in 2:
		if absf(stick[axis]) >= 0.65:
			_held_stick[axis] = int(signf(stick[axis]))
		elif absf(stick[axis]) < 0.4:
			_held_stick[axis] = 0
	var direction := Vector2i(clampi(dpad.x, -1, 1), clampi(dpad.y, -1, 1))
	if direction == Vector2i.ZERO:
		direction = _held_stick
	if direction.x != 0 and direction.y != 0:
		if absf(stick.x) > absf(stick.y):
			direction.y = 0
		else:
			direction.x = 0
	return direction


func _repeat_step(direction: Vector2i) -> void:
	if screen == Screen.INITIALS:
		_initials_step(direction)
		return
	if screen == Screen.SETTINGS and _waiting_index >= 0:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not is_ancestor_of(focus) or (focus is OptionButton and focus.get_popup().visible):
		return
	if direction.y != 0:
		_step_vertical(focus, direction.y)
	else:
		_step_horizontal(focus, direction.x, _held_time >= REPEAT_FAST_AFTER)


func _step_horizontal(focus: Control, direction: int, fast: bool = false) -> void:
	if screen == Screen.ARCHIVES:
		_select_archives_tab(posmod(_archives_tab + direction, 2), focus.name.begins_with("ArchivesTab"))
	elif screen == Screen.CONTROLS_HELP:
		_select_help_tab(_help_tab + direction)
	elif focus is OPTION_ROW and focus.arrows:
		focus.step(direction)
	elif focus is Range:
		var range_control := focus as Range
		range_control.value += range_control.step * direction * (2 if fast else 1)
	else:
		var neighbor := focus.find_valid_focus_neighbor(SIDE_LEFT if direction < 0 else SIDE_RIGHT)
		if neighbor and neighbor != focus and is_ancestor_of(neighbor):
			neighbor.grab_focus()


func _hangar_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.hangar"), 32, TEXT)
	_build_aircraft_picker(content)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	_button(footer, tr("common.back")).pressed.connect(back)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	_button(footer, tr("hangar.choose"), true).pressed.connect(_confirm_aircraft)
	for choice: Button in _hangar_choices.values():
		if not choice.disabled:
			choice.gui_input.connect(_hangar_choice_input)
	_preview_aircraft(settings.aircraft)
	_hangar_choices[settings.aircraft].grab_focus()


func _hangar_choice_input(event: InputEvent) -> void:
	var mouse_release: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
		and not event.pressed
	if mouse_release or (event.is_action_pressed(&"ui_accept") and not event.is_echo()):
		get_viewport().set_input_as_handled()
		_confirm_aircraft.call_deferred()


func _build_aircraft_picker(content: VBoxContainer, unavailable: String = "", compact: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 235
	choices.add_theme_constant_override("separation", 8)
	row.add_child(choices)
	var group := ButtonGroup.new()
	for id: String in AIRCRAFT.IDS:
		var button := _button(choices, AIRCRAFT.AIRCRAFT[id].short, false, 38 if compact else 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		_hangar_choices[id] = button
		if id == unavailable:
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_color_override("font_disabled_color", Color("#809095"))
			button.add_theme_stylebox_override("disabled", _box(Color("#263238"), Color("#38464d"), 8, 4))
		else:
			button.focus_entered.connect(_preview_aircraft.bind(id))
			button.pressed.connect(_preview_aircraft.bind(id))

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	row.add_child(detail)
	_hangar_name = _caption(detail, "", 24, TEXT)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(414, 230) if compact else Vector2(468, 260)
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
	if _hangar_choices[id].disabled or (is_instance_valid(_hangar_model) and id == aircraft_selection):
		return
	aircraft_selection = id
	var entry: Dictionary = AIRCRAFT.AIRCRAFT[id]
	_hangar_name.text = entry.name
	_hangar_country.text = tr(entry.country)
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


## Charge une image importée par l'éditeur, ou directement le fichier quand le projet
## est lancé sans import préalable (Godot en ligne de commande, nouveau clone du dépôt).
func _load_texture(path: String) -> Texture2D:
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(path + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture:
			return texture
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return null


func _load_flag(path: String) -> Texture2D:
	return _load_texture(path)


func _confirm_aircraft() -> void:
	if screen != Screen.HANGAR:
		return
	settings.aircraft = aircraft_selection
	_show_page(Screen.TITLE)
	_request(&"aircraft_selected")
	settings_committed.emit()


func _visible_settings_tabs() -> Array[SettingsTab]:
	if _return_to == Screen.PAUSE:
		return [SettingsTab.CONTROLS, SettingsTab.AUDIO, SettingsTab.DISPLAY]
	return [SettingsTab.GAME, SettingsTab.CONTROLS, SettingsTab.AUDIO, SettingsTab.DISPLAY, SettingsTab.ADVANCED]


func _settings_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.settings"), 25, TEXT)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	for tab in _visible_settings_tabs():
		var button := _button(tabs, tr(SETTINGS_TAB_LABELS[tab]), tab == _settings_tab, 32)
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_settings_tab.bind(tab, false))
		_settings_tabs.append(button)
	content.add_child(HSeparator.new())

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var first: Control
	match _settings_tab:
		SettingsTab.GAME:
			first = _settings_game(body)
		SettingsTab.CONTROLS:
			first = _settings_controls(body)
		SettingsTab.AUDIO:
			first = _settings_audio(body)
		SettingsTab.DISPLAY:
			first = _settings_display(body)
		SettingsTab.ADVANCED:
			first = _settings_advanced(body)
	_description = _caption(content, "", 13, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 36
	_status = _caption(content, tr(_score_notice) if _settings_tab == SettingsTab.ADVANCED else "", 13, ACCENT)
	first.grab_focus()
	_describe(first)


func _select_settings_tab(tab: SettingsTab, _unused: bool = false) -> void:
	if tab != _settings_tab and tab in _visible_settings_tabs():
		_settings_tab = tab
		_show_page(Screen.SETTINGS)
		play_sound("move")


func _cycle_settings_tab(direction: int) -> void:
	var tabs := _visible_settings_tabs()
	var current := maxi(tabs.find(_settings_tab), 0)
	_select_settings_tab(tabs[posmod(current + direction, tabs.size())])


func _settings_game(content: VBoxContainer) -> Control:
	var codes: Array = SETTINGS.LANGUAGES.keys()
	var names := PackedStringArray(SETTINGS.LANGUAGES.values())
	var language := _option_row(content, tr("settings.language"), names, codes.find(settings.language))
	language.value_changed.connect(func(index: int) -> void: _select_language(codes[index]))
	_language_button = language
	var ghosts := PackedStringArray()
	for key: String in GHOST_OPTIONS:
		ghosts.append(tr(key))
	_choice_row(content, tr("settings.ghost"), ghosts, [SETTINGS.Ghost.OFF, SETTINGS.Ghost.BEST, SETTINGS.Ghost.LAST],
		&"ghost_source", "settings.ghost_help")
	_choice_row(content, tr("settings.difficulty"),
		PackedStringArray([tr("settings.difficulty_novice"), tr("settings.difficulty_expert")]),
		[SETTINGS.Difficulty.NOVICE, SETTINGS.Difficulty.EXPERT], &"difficulty", "settings.difficulty_help")
	return language


func _settings_controls(content: VBoxContainer) -> Control:
	var device := _option_row(content, tr("settings.device"),
		PackedStringArray([tr("settings.keyboard"), tr("settings.controller")]), int(_bind_controller))
	device.value_changed.connect(func(index: int) -> void:
		_bind_controller = index == 1
		_refresh_bindings())
	_caption(content, tr("settings.bindings"), 14, ACCENT)
	for i in SETTINGS.ACTIONS.size():
		var row := _option_row(content, tr(SETTINGS.ACTIONS[i][1]), PackedStringArray(), 0, "settings.binding_hint")
		row.set_value_text("")
		row.pressed.connect(_listen.bind(i))
		_binding_rows.append(row)
	_refresh_bindings()
	_slider_row(content, tr("settings.rumble"), &"vibration")
	var restore := _hold_button(content, tr("settings.restore_bindings"))
	restore.confirmed.connect(_restore_bindings)
	return device


func _settings_audio(content: VBoxContainer) -> Control:
	# Deux groupes : le son du jeu, puis la musique d'ambiance.
	_caption(content, tr("settings.sound_section"), 14, ACCENT)
	var first := _slider_row(content, tr("settings.volume"), &"volume")
	_bool_row(content, tr("settings.mute"), &"muted")
	_caption(content, tr("settings.music"), 14, ACCENT)
	var mode := _choice_row(content, tr("settings.music_play"),
		PackedStringArray([tr("common.off"), tr("settings.music_menu"), tr("settings.music_game")]),
		[SETTINGS.Music.OFF, SETTINGS.Music.MENU, SETTINGS.Music.GAME], &"music", "settings.music_help")
	mode.name = "MusicMode"
	# Le choix du morceau et son volume n'apparaissent que si la musique est activée.
	mode.value_changed.connect(func(_index: int) -> void: _refresh_settings_row.call_deferred(&"MusicMode"))
	if settings.music != SETTINGS.Music.OFF:
		var ids: Array = []
		var titles := PackedStringArray()
		for track: Array in SETTINGS.MUSIC_TRACKS:
			ids.append(track[0])
			titles.append(track[1])
		_choice_row(content, tr("settings.music_track"), titles, ids, &"music_track", "settings.music_track_help")
		_slider_row(content, tr("settings.volume"), &"music_volume")
	return first


func _refresh_settings_row(row: StringName) -> void:
	if screen != Screen.SETTINGS:
		return
	_show_page(Screen.SETTINGS)
	var target := find_child(String(row), true, false) as Control
	if target:
		target.grab_focus()
		_describe(target)


func _settings_display(content: VBoxContainer) -> Control:
	var first := _bool_row(content, tr("settings.fullscreen"), &"fullscreen")
	_bool_row(content, tr("settings.hd"), &"quality_hd", "settings.hd_help")
	_bool_row(content, tr("settings.adaptive_resolution"), &"dynamic_resolution", "settings.adaptive_help")
	_bool_row(content, tr("settings.panorama"), &"panorama", "settings.panorama_help")
	var levels := PackedStringArray()
	for key: String in SCANLINE_OPTIONS:
		levels.append(tr(key))
	_choice_row(content, tr("settings.scanlines"), levels,
		[SETTINGS.Scanlines.OFF, SETTINGS.Scanlines.LOW, SETTINGS.Scanlines.MEDIUM, SETTINGS.Scanlines.HIGH], &"scanlines")
	_bool_row(content, tr("settings.show_fps"), &"show_fps")
	return first


func _settings_advanced(content: VBoxContainer) -> Control:
	var monitor_hz := DisplayServer.screen_get_refresh_rate()
	var rates := PackedStringArray([tr("settings.auto")])
	var values: Array = [0]
	for hz in PACING.divisor_rates(monitor_hz):
		rates.append("%d Hz" % hz)
		values.append(hz)
	var first := _choice_row(content, tr("settings.refresh"), rates, values, &"refresh_limit", "settings.refresh_help")
	_choice_row(content, tr("settings.sync"), PackedStringArray([tr("settings.screen"), tr("settings.vrr"), tr("common.off")]),
		[PACING.Sync.SCREEN, PACING.Sync.ADAPTIVE, PACING.Sync.OFF], &"sync_mode", "settings.sync_help")
	if monitor_hz > 0:
		var monitor := _caption(content, tr("settings.monitor") % monitor_hz, 13, MUTED)
		monitor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	content.add_child(HSeparator.new())
	_reset_score_button = _hold_button(content, tr("settings.reset_scores").trim_suffix("…").trim_suffix("..."))
	_reset_score_button.disabled = settings.record == 0 and settings.best_raid == null \
		and settings.scores == SETTINGS.DEFAULT_SCORES and settings.scores_expert == SETTINGS.DEFAULT_SCORES
	(_reset_score_button as HoldButton).confirmed.connect(_confirm_score_reset)
	_reset_score_button.focus_entered.connect(func() -> void:
		if is_instance_valid(_description):
			_description.text = "%s %s" % [tr("settings.reset_defaults"), tr("settings.reset_record")])
	return first


func _option_row(parent: Control, title: String, choices: PackedStringArray, selected: int, help: String = "") -> OPTION_ROW:
	var row := OPTION_ROW.new()
	parent.add_child(row)
	row.setup(title, choices, selected, help)
	row.mouse_entered.connect(_focus_on_hover.bind(row))
	row.focus_entered.connect(_describe.bind(row))
	row.value_changed.connect(func(_index: int) -> void: play_sound("move"))
	row.pressed.connect(func() -> void:
		if not row.arrows:
			play_sound("accept"))
	return row


func _bool_row(parent: Control, title: String, property: StringName, help: String = "") -> OPTION_ROW:
	var row := _option_row(parent, title, PackedStringArray([tr("common.off"), tr("common.on")]),
		int(bool(settings.get(property))), help)
	row.value_changed.connect(func(index: int) -> void:
		settings.set(property, index == 1)
		settings_changed.emit())
	return row


func _choice_row(parent: Control, title: String, labels: PackedStringArray, values: Array, property: StringName,
		help: String = "") -> OPTION_ROW:
	var row := _option_row(parent, title, labels, maxi(values.find(settings.get(property)), 0), help)
	row.value_changed.connect(func(index: int) -> void:
		settings.set(property, values[index])
		settings_changed.emit())
	return row


func _slider_row(parent: Control, title: String, property: StringName) -> HSlider:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 10)
	parent.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var slider := _percentage_slider(row, title, property)
	slider.focus_entered.connect(_describe.bind(slider))
	slider.mouse_entered.connect(func() -> void: slider.grab_focus())
	return slider


func _describe(control: Control) -> void:
	if is_instance_valid(_description):
		var key: String = control.description if control is OPTION_ROW else ""
		_description.text = tr(key) if not key.is_empty() else ""


func _languages_page(content: VBoxContainer) -> void:
	_caption(content, tr("settings.language"), 30, TEXT)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for code: String in SETTINGS.LANGUAGES:
		var selected := code == settings.language
		var button := _button(grid, SETTINGS.LANGUAGES[code], selected, 37)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_language.bind(code))
		if selected:
			button.grab_focus()
	_button(content, tr("common.back")).pressed.connect(back)


func _return_to_language_settings() -> void:
	_show_page(Screen.SETTINGS)
	_language_button.grab_focus()


func _select_language(code: String) -> void:
	var changed := code != settings.language
	settings.language = code
	TranslationServer.set_locale(code)
	_return_to_language_settings()
	_describe(_language_button)
	if changed:
		settings_changed.emit()
		settings_committed.emit()


func _confirm_abandon_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.confirm_abandon"), 28, TEXT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var cancel := _button(actions, tr("common.cancel"), true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(back)
	var confirm := _button(actions, tr("menu.abandon"))
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_request.bind(&"abandon"))
	cancel.grab_focus()


func _confirm_reset_page(content: VBoxContainer) -> void:
	_caption(content, tr("settings.confirm_reset"), 28, TEXT)
	_caption(content, tr("settings.reset_defaults"), 15, MUTED)
	_caption(content, tr("settings.reset_record"), 15, MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var cancel := _button(actions, tr("common.cancel"), true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_return_from_reset)
	var confirm := _button(actions, tr("settings.reset"))
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_confirm_score_reset)
	cancel.grab_focus()


func _return_from_reset() -> void:
	_show_page(Screen.SETTINGS)
	if is_instance_valid(_reset_score_button) and not _reset_score_button.disabled:
		_reset_score_button.grab_focus()


func _confirm_score_reset() -> void:
	var error := settings.clear_high_score()
	_score_notice = "settings.reset_done" if error == OK else "settings.reset_failed"
	if error == OK:
		settings_changed.emit()
	_return_from_reset()


func _input(event: InputEvent) -> void:
	if screen == Screen.HIDDEN:
		return
	if screen == Screen.INITIALS and _handle_initials(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_hotseat_input(event):
		get_viewport().set_input_as_handled()
		return
	var joy_back: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed
	if screen == Screen.SETTINGS and _waiting_index >= 0:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				back()
			elif not _waiting_for_controller:
				_submit_binding(event.physical_keycode)
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed:
			if _waiting_for_controller:
				_submit_binding(event.button_index)
			elif joy_back:
				back()
			get_viewport().set_input_as_handled()
		return

	if joy_back or event.is_action_pressed(&"ui_cancel"):
		var focus := get_viewport().gui_get_focus_owner()
		if focus is OptionButton and focus.get_popup().visible:
			focus.get_popup().hide()
		elif screen == Screen.TITLE:
			if is_instance_valid(_quit_button) and focus != _quit_button:
				play_sound("back")
				_quit_button.grab_focus()
		else:
			play_sound("back")
			back()
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.SETTINGS and _handle_settings_tabs(event):
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.CONTROLS_HELP:
		var help_direction := _tab_direction(event, true)
		if help_direction == 0 and not event.is_echo() and not event is InputEventJoypadMotion:
			if event.is_action_pressed(&"ui_left"):
				help_direction = -1
			elif event.is_action_pressed(&"ui_right"):
				help_direction = 1
		if help_direction != 0:
			_select_help_tab(_help_tab + help_direction)
			get_viewport().set_input_as_handled()
			return
	if screen in [Screen.TITLE, Screen.ARCHIVES]:
		var direction := _tab_direction(event, screen == Screen.ARCHIVES)
		if direction != 0:
			if screen == Screen.TITLE:
				_cycle_aircraft(direction)
			else:
				_select_archives_tab(posmod(_archives_tab + direction, 2))
			get_viewport().set_input_as_handled()
			return
	# Le stick passe par _navigate_vertical (un cran par inclinaison) : ses mouvements
	# continus ne doivent pas compter ici comme autant de pressions sur ← / →.
	if screen == Screen.ARCHIVES and not event.is_echo() and not event is InputEventJoypadMotion:
		var step := 0
		if event.is_action_pressed(&"ui_left"):
			step = -1
		elif event.is_action_pressed(&"ui_right"):
			step = 1
		if step != 0:
			var focus := get_viewport().gui_get_focus_owner()
			_select_archives_tab(posmod(_archives_tab + step, 2), focus != null and focus.name.begins_with("ArchivesTab"))
			get_viewport().set_input_as_handled()
			return
	if screen == Screen.BRIDGES and _handle_bridge_scroll(event):
		get_viewport().set_input_as_handled()
		return
	var shortcut := _shortcut_prompt(event)
	if shortcut >= 0 and _run_prompt(shortcut):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		var focus := get_viewport().gui_get_focus_owner()
		if focus is BaseButton and focus.disabled and is_ancestor_of(focus):
			play_sound("denied")
	if screen == Screen.TITLE and event is InputEventKey and event.pressed and not event.echo \
			and event.unicode > 0 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if _type_cheat_character(String.chr(event.unicode).to_lower()):
			get_viewport().set_input_as_handled()
			return
	_navigate_vertical(event)


func _handle_settings_tabs(event: InputEvent) -> bool:
	var direction := _tab_direction(event, true)
	if direction == 0:
		return false
	_cycle_settings_tab(direction)
	return true


## Sens de changement d'onglet demandé : LB / RB, Page préc. / suiv., et Tab si permis.
func _tab_direction(event: InputEvent, allow_tab_key: bool) -> int:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				return -1
			JOY_BUTTON_RIGHT_SHOULDER:
				return 1
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match key:
			KEY_PAGEUP:
				return -1
			KEY_PAGEDOWN:
				return 1
			KEY_TAB:
				if allow_tab_key and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
					return -1 if event.shift_pressed else 1
	return 0


func _handle_bridge_scroll(event: InputEvent) -> bool:
	var direction := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			direction = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			direction = 1
	elif event is InputEventKey and event.pressed:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_PAGEUP:
			direction = -1
		elif key == KEY_PAGEDOWN:
			direction = 1
	elif event is InputEventMouseButton and event.pressed and _bridge_table \
			and _bridge_table.get_global_rect().has_point(event.position):
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_scroll_bridges_to(_bridge_top + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
			return true
	if direction == 0:
		return false
	if not _bridge_rows.is_empty():
		var focus := _focused_bridge()
		var offset := direction * _bridge_rows.size()
		var index := clampi(maxi(_bridge_top, focus.x) + offset, 0, _bridge_total - 1)
		_set_bridge_top(_bridge_top + offset)
		_focus_bridge(index, focus.y == 1)
	return true


func _navigate_vertical(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not is_ancestor_of(focus) or (focus is OptionButton and focus.get_popup().visible):
		return
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		# Le stick horizontal suit la même hystérésis que le vertical : un cran par inclinaison.
		var tilt := 0
		if absf(event.axis_value) >= 0.65:
			tilt = int(signf(event.axis_value))
		elif absf(event.axis_value) >= 0.4:
			tilt = _stick_x
		if tilt != 0 and tilt != _stick_x:
			_step_horizontal(focus, tilt)
		_stick_x = tilt
		get_viewport().set_input_as_handled()
		return
	var direction := 0
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		if absf(event.axis_value) < 0.4:
			_stick_direction = 0
		elif absf(event.axis_value) >= 0.65:
			var tilt := int(signf(event.axis_value))
			if tilt != _stick_direction:
				direction = tilt
			_stick_direction = tilt
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up", true):
		direction = -1
	elif event.is_action_pressed(&"ui_down", true):
		direction = 1
	if direction == 0:
		return
	_step_vertical(focus, direction)
	get_viewport().set_input_as_handled()


func _step_vertical(focus: Control, direction: int) -> void:
	if screen == Screen.BRIDGES:
		_step_bridge_focus(direction)
		return
	var neighbor := focus.find_valid_focus_neighbor(SIDE_TOP if direction < 0 else SIDE_BOTTOM)
	if neighbor == null or neighbor == focus or not is_ancestor_of(neighbor):
		neighbor = _wrapped_focus(focus, direction)
	if screen == Screen.ARCHIVES and neighbor and neighbor.name.begins_with("ArchivesTab"):
		# Depuis la liste, on remonte toujours sur l'onglet affiché.
		var active := find_child("ArchivesTab%d" % _archives_tab, true, false) as Control
		if active:
			neighbor = active
	if neighbor:
		neighbor.grab_focus()
	else:
		play_sound("denied")


func _wrapped_focus(focus: Control, direction: int) -> Control:
	var target: Control
	var best_edge := -INF
	var best_column := INF
	var focus_x := focus.get_global_rect().get_center().x
	for candidate: Control in find_children("*", "Control", true, false):
		if candidate == focus or not candidate.is_visible_in_tree() or candidate.focus_mode != Control.FOCUS_ALL \
				or (candidate is BaseButton and candidate.disabled):
			continue
		var center := candidate.get_global_rect().get_center()
		var edge := -direction * center.y
		var column := absf(center.x - focus_x)
		if edge > best_edge + 5.0 or (absf(edge - best_edge) <= 5.0 and column < best_column):
			target = candidate
			best_edge = edge
			best_column = column
	return target


func _type_cheat_character(character: String) -> bool:
	var sequence := _code_prefix + character
	while not sequence.is_empty():
		if TEST_MENU_CODE.begins_with(sequence):
			_code_prefix = sequence
			if sequence == TEST_MENU_CODE:
				_show_page(Screen.TESTS)
			return true
		for code: String in SECRET_CODES:
			if not code.begins_with(sequence):
				continue
			_code_prefix = sequence
			if code == sequence:
				var option: Array = SECRET_CODES[code]
				cheats ^= int(option[0])
				var state := "cheat.enabled" if cheats & int(option[0]) else "cheat.disabled"
				show_notice(state, option[1])
				_code_prefix = ""
			return true
		sequence = sequence.substr(1)
	_code_prefix = ""
	return false


func _submit_binding(code: int) -> void:
	if settings.bind(_waiting_index, code, _waiting_for_controller):
		settings_changed.emit()
		_finish_binding(tr("settings.binding_done"))
	else:
		_status.text = tr("settings.binding_reserved")


func _listen(index: int) -> void:
	_waiting_index = index
	_waiting_for_controller = _bind_controller
	_listen_deadline = Time.get_ticks_msec() + BINDING_TIMEOUT_MS
	_refresh_bindings()
	_status.text = tr("settings.binding_press_gamepad") if _bind_controller else tr("settings.binding_press_keyboard")


func _finish_binding(message: String) -> void:
	_waiting_index = -1
	_refresh_bindings()
	_status.text = message


func _update_binding_countdown() -> void:
	if _waiting_index < 0 or screen != Screen.SETTINGS:
		return
	var remaining := ceili((_listen_deadline - Time.get_ticks_msec()) / 1000.0)
	if remaining <= 0:
		play_sound("back")
		_finish_binding(tr("settings.binding_cancelled"))
	elif _waiting_index < _binding_rows.size():
		_binding_rows[_waiting_index].set_value_text("%s %d" % [tr("settings.binding_press"), remaining])


func _refresh_bindings() -> void:
	for i in mini(SETTINGS.ACTIONS.size(), _binding_rows.size()):
		var text := _binding_text(i, _bind_controller)
		if _waiting_index == i:
			text = "%s %d" % [tr("settings.binding_press"),
				maxi(ceili((_listen_deadline - Time.get_ticks_msec()) / 1000.0), 1)]
		_binding_rows[i].set_value_text(text)


func _binding_text(index: int, controller: bool) -> String:
	if controller:
		var pad := settings.gamepad[index]
		return tr(BUTTON_NAMES[pad]) if BUTTON_NAMES.has(pad) else tr("settings.button_number") % (pad + 1)
	var key := DisplayServer.keyboard_get_keycode_from_physical(settings.keyboard[index] as Key)
	return tr(KEY_NAMES.get(key, OS.get_keycode_string(key)))


func _restore_bindings() -> void:
	settings.reset_bindings()
	settings_changed.emit()
	_finish_binding(tr("settings.bindings_restored"))


func _open_settings() -> void:
	_return_to = screen
	_score_notice = ""
	_bind_controller = glyphs.is_pad()
	_settings_tab = _visible_settings_tabs()[0]
	_show_page(Screen.SETTINGS)


func _request(action: StringName) -> void:
	action_requested.emit(action)


func _percentage_slider(row: HBoxContainer, title: String, property: StringName) -> HSlider:
	var name := _caption(row, title, 15, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(230, 30)
	slider.max_value = 100
	slider.step = 5
	slider.value = settings.get(property)
	row.add_child(slider)
	var label := _caption(row, "%d %%" % slider.value, 14, ACCENT)
	label.custom_minimum_size.x = 48
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider.value_changed.connect(_set_percentage.bind(label, property))
	slider.value_changed.connect(func(_value: float) -> void: play_sound("move"))
	return slider


func _set_percentage(value: float, label: Label, property: StringName) -> void:
	settings.set(property, roundi(value))
	label.text = "%d %%" % roundi(value)
	settings_changed.emit()


func _toggle(parent: Control, text: String, enabled: bool, property: StringName) -> CheckButton:
	var box := CheckButton.new()
	box.text = text
	box.button_pressed = enabled
	box.toggled.connect(_set_option.bind(property))
	box.toggled.connect(func(_on: bool) -> void: play_sound("accept"))
	parent.add_child(box)
	return box


func _set_option(enabled: bool, property: StringName) -> void:
	settings.set(property, enabled)
	settings_changed.emit()


func _select(parent: Control, choices: Array[String], values: Array, selected: int, property: StringName) -> OptionButton:
	var button := OptionButton.new()
	button.custom_minimum_size.y = 30
	for i in choices.size():
		button.add_item(choices[i], values[i])
		if values[i] == selected:
			button.select(i)
	button.item_selected.connect(func(index: int) -> void:
		settings.set(property, button.get_item_id(index))
		settings_changed.emit())
	button.item_selected.connect(func(_index: int) -> void: play_sound("accept"))
	parent.add_child(button)
	return button


func _button(parent: Control, text: String, primary: bool = false, height: int = 39) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = height
	if primary:
		button.add_theme_color_override("font_color", ACCENT)
		button.add_theme_stylebox_override("normal", _box(Color("#174036"), Color("#568d75"), 8, 4))
	button.mouse_entered.connect(_focus_on_hover.bind(button))
	button.pressed.connect(play_sound.bind("accept"))
	parent.add_child(button)
	return button


func _focus_on_hover(button: Button) -> void:
	if is_instance_valid(button) and not button.disabled and button.focus_mode == Control.FOCUS_ALL \
			and button.is_visible_in_tree():
		button.grab_focus()


func _hold_button(parent: Control, text: String) -> HoldButton:
	var button := HoldButton.new()
	button.text = text
	button.custom_minimum_size.y = 39
	button.accent = ACCENT
	button.mouse_entered.connect(_focus_on_hover.bind(button))
	button.focus_entered.connect(_show_hold_hint.bind(true))
	button.focus_exited.connect(_show_hold_hint.bind(false))
	button.confirmed.connect(play_sound.bind("accept"))
	parent.add_child(button)
	return button


# --- Barre d'aide -----------------------------------------------------------

## Entrées de la barre d'aide : [bouton, clé de texte, filtre] avec filtre "" (tous),
## "pad" (manette seulement) ou "keys" (clavier seulement).
func _prompts_for(page: Screen) -> Array:
	var P := INPUT_GLYPHS.Prompt
	match page:
		Screen.TITLE:
			return [[P.START, "menu.solo", ""], [P.TABS, "prompt.aircraft", ""], [P.Y, "menu.hangar", ""],
				[P.SELECT, "help.title", ""]]
		Screen.PAUSE:
			return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "prompt.resume", ""], [P.SELECT, "settings.tab_controls", ""]]
		Screen.ARCHIVES:
			if _archives_tab == 0:
				return [[P.BACK, "common.back", ""], [P.TABS, "prompt.tab", ""]]
			return [[P.ACCEPT, "bridges.watch", ""], [P.BACK, "common.back", ""], [P.TABS, "prompt.tab", ""]]
		Screen.CONTROLS_HELP:
			return [[P.BACK, "common.back", ""], [P.TABS, "prompt.tab", ""]]
		Screen.ABOUT:
			return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "common.close", ""]]
		Screen.SETTINGS:
			return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "common.back", ""], [P.TABS, "prompt.tab", ""]]
		Screen.HANGAR:
			return [[P.ACCEPT, "hangar.choose", ""], [P.BACK, "common.back", ""]]
		Screen.RESULTS:
			return [[P.BACK, "common.main_menu", ""], [P.X, "results.bridge_report", ""], [P.Y, "menu.leaderboard", ""]]
		Screen.BRIDGES:
			var entries: Array = [[P.ACCEPT, "bridges.watch", ""], [P.BACK, "common.back", ""]]
			if _bridge_total > _bridge_rows.size():
				entries.append([P.TABS, "prompt.page", ""])
			return entries
		Screen.SCORES:
			return [[P.BACK, "common.back", ""]]
		Screen.INITIALS:
			return [[P.ACCEPT, "prompt.next_letter", "pad"], [P.BACK, "prompt.previous_letter", "pad"],
				[P.START, "scores.save", "pad"], [P.ACCEPT, "scores.save", "keys"], [P.BACK, "scores.skip", "keys"]]
		Screen.CONFIRM_RESET, Screen.CONFIRM_ABANDON:
			return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "common.cancel", ""]]
		Screen.HOTSEAT_SETUP:
			return [[P.ACCEPT, "prompt.join", ""], [P.BACK, "prompt.leave", "pad"], [P.START, "menu.play", ""],
				[P.BACK, "common.back", "keys"]]
		Screen.HOTSEAT_TURN:
			var entries: Array = [[P.ACCEPT, "hotseat.go", ""]]
			if _hotseat_choose_aircraft:
				entries.append([P.TABS, "prompt.aircraft", ""])
			entries.append([P.BACK, "common.main_menu", ""])
			return entries
		Screen.HOTSEAT_RESULTS:
			return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "common.main_menu", ""]]
	return [[P.ACCEPT, "prompt.select", ""], [P.BACK, "common.back", ""]]


func _add_prompt_bar(content: VBoxContainer, entries: Array) -> void:
	if entries.is_empty():
		return
	content.add_child(HSeparator.new())
	_prompt_bar = HBoxContainer.new()
	_prompt_bar.name = "PromptBar"
	_prompt_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_bar.add_theme_constant_override("separation", 18)
	content.add_child(_prompt_bar)
	_prompt_entries = entries
	_refresh_prompts()


func _refresh_prompts() -> void:
	if not is_instance_valid(_prompt_bar):
		return
	for child in _prompt_bar.get_children():
		_prompt_bar.remove_child(child)
		child.queue_free()
	var device := _prompt_device()
	var pad := device != INPUT_GLYPHS.Device.KEYBOARD
	for entry: Array in _prompt_entries:
		if (entry[2] == "pad" and not pad) or (entry[2] == "keys" and pad):
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var prompt: int = entry[0]
		if prompt != INPUT_GLYPHS.Prompt.ACCEPT:
			item.mouse_filter = Control.MOUSE_FILTER_STOP
			item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			item.gui_input.connect(_on_prompt_clicked.bind(prompt))
		item.add_child(INPUT_GLYPHS.Glyph.new(device, prompt, _keyboard_caps(prompt)))
		var label := _caption(item, tr(entry[1]), 13, MUTED)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_prompt_bar.add_child(item)


func _keyboard_caps(prompt: int) -> String:
	match prompt:
		INPUT_GLYPHS.Prompt.ACCEPT:
			return tr("input.space") + "|F" if screen == Screen.HOTSEAT_SETUP else tr("key.enter")
		INPUT_GLYPHS.Prompt.START:
			return tr("key.enter")
		INPUT_GLYPHS.Prompt.BACK:
			return tr("key.escape")
		INPUT_GLYPHS.Prompt.X:
			return "X"
		INPUT_GLYPHS.Prompt.Y:
			return "Y"
		INPUT_GLYPHS.Prompt.TABS:
			return "Pg ↑|Pg ↓" if screen in [Screen.BRIDGES, Screen.TITLE] else "Tab"
		INPUT_GLYPHS.Prompt.SELECT:
			return "Tab"
	return ""


func _on_prompt_clicked(event: InputEvent, prompt: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		if prompt == INPUT_GLYPHS.Prompt.BACK:
			play_sound("back")
			back()
		else:
			_run_prompt(prompt)


## Bouton de raccourci (X, Y) demandé par l'événement, ou -1.
func _shortcut_prompt(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_X:
				return INPUT_GLYPHS.Prompt.X
			JOY_BUTTON_Y:
				return INPUT_GLYPHS.Prompt.Y
			JOY_BUTTON_BACK:
				return INPUT_GLYPHS.Prompt.SELECT
			JOY_BUTTON_START:
				if screen == Screen.TITLE:
					return INPUT_GLYPHS.Prompt.START
	elif event is InputEventKey and event.pressed and not event.echo \
			and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if screen in [Screen.TITLE, Screen.PAUSE] and event.keycode == KEY_TAB and not event.shift_pressed:
			return INPUT_GLYPHS.Prompt.SELECT
		if screen in [Screen.RESULTS, Screen.TITLE]:
			if event.keycode == KEY_X and screen == Screen.RESULTS:
				return INPUT_GLYPHS.Prompt.X
			if event.keycode == KEY_Y:
				return INPUT_GLYPHS.Prompt.Y
	return -1


## Exécute l'action d'un bouton de la barre d'aide. Renvoie false si l'écran n'en a pas.
func _run_prompt(prompt: int) -> bool:
	match prompt:
		INPUT_GLYPHS.Prompt.X:
			if screen == Screen.RESULTS:
				play_sound("accept")
				show_bridge_results()
				return true
		INPUT_GLYPHS.Prompt.Y:
			if screen == Screen.RESULTS:
				play_sound("accept")
				_open_scores(Screen.RESULTS)
				return true
			if screen == Screen.TITLE:
				play_sound("accept")
				_show_page(Screen.HANGAR)
				return true
		INPUT_GLYPHS.Prompt.SELECT:
			if screen == Screen.TITLE:
				play_sound("accept")
				_open_help(HELP_TAB_MISSION)
				return true
			if screen == Screen.PAUSE:
				play_sound("accept")
				_open_controls_help()
				return true
		INPUT_GLYPHS.Prompt.TABS:
			if screen == Screen.SETTINGS:
				_cycle_settings_tab(1)
				return true
			if screen in [Screen.TITLE, Screen.HOTSEAT_TURN]:
				_cycle_aircraft(1)
				return true
			if screen == Screen.ARCHIVES:
				_select_archives_tab(1 - _archives_tab)
				return true
			if screen == Screen.CONTROLS_HELP:
				_select_help_tab(_help_tab + 1)
				return true
			if screen == Screen.BRIDGES:
				var event := InputEventKey.new()
				event.keycode = KEY_PAGEDOWN
				event.pressed = true
				return _handle_bridge_scroll(event)
		INPUT_GLYPHS.Prompt.START:
			if screen == Screen.INITIALS:
				_submit_initials()
				return true
			if screen == Screen.TITLE:
				play_sound("accept")
				_request(&"play")
				return true
			if screen == Screen.HOTSEAT_SETUP:
				_start_hotseat()
				return true
	return false


func _show_hold_hint(shown: bool) -> void:
	if is_instance_valid(_status):
		_status.text = tr("common.hold_to_confirm") if shown else _notice_text()


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
	var focus := _box(Color(ACCENT, 0.16), ACCENT, 8, 4)
	focus.set_border_width_all(2)
	for type in ["Button", "CheckButton", "OptionButton", "HSlider"]:
		result.set_stylebox("focus", type, focus)
	result.set_color("font_focus_color", "Button", Color.WHITE)
	result.set_color("font_focus_color", "CheckButton", Color.WHITE)
	result.set_color("font_focus_color", "OptionButton", Color.WHITE)
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


## Bouton qu'il faut maintenir (A, Entrée, Espace ou clic) pour confirmer une action
## qui fait perdre une progression. Une jauge se remplit pendant le maintien.
class HoldButton extends Button:
	signal confirmed

	const DURATION := 0.8

	var accent := Color.WHITE
	var progress := 0.0
	var _source := 0
	var _fill := StyleBoxFlat.new()

	func _ready() -> void:
		set_process(false)
		_fill.set_corner_radius_all(4)
		focus_exited.connect(_cancel)

	func _gui_input(event: InputEvent) -> void:
		if disabled:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin(2)
			else:
				_cancel()
			accept_event()
		elif event.is_action(&"ui_accept"):
			if event.is_pressed() and not event.is_echo():
				_begin(1)
			elif not event.is_pressed():
				_cancel()
			accept_event()

	func _begin(source: int) -> void:
		if _source != 0:
			return
		_source = source
		progress = 0.0
		set_process(true)
		queue_redraw()

	func _cancel() -> void:
		if _source == 0 and progress == 0.0:
			return
		_source = 0
		progress = 0.0
		set_process(false)
		queue_redraw()

	func _process(delta: float) -> void:
		var held := Input.is_action_pressed(&"ui_accept") if _source == 1 \
			else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if not held:
			_cancel()
			return
		progress = minf(1.0, progress + delta / DURATION)
		queue_redraw()
		if progress >= 1.0:
			_source = 0
			set_process(false)
			confirmed.emit()

	func _draw() -> void:
		var track := Rect2(6, size.y - 7, size.x - 12, 3)
		if has_focus() or progress > 0.0:
			draw_rect(track, Color(accent, 0.25))
		if progress > 0.0:
			_fill.bg_color = Color(accent, 0.2)
			draw_style_box(_fill, Rect2(Vector2.ZERO, Vector2(size.x * progress, size.y)))
			draw_rect(Rect2(track.position, Vector2(track.size.x * progress, track.size.y)), accent)
