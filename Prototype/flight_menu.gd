extends Control

const SETTINGS = preload("res://flight_settings.gd")
const FLIGHT = preload("res://flight.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const VISIBLE_BRIDGE_ROWS := 7
const BRIDGE_COLUMNS := [48, 72, 62, 52, 49, 66]
const AIRCRAFT = preload("res://player_aircraft.gd")
const MODELS = preload("res://flight_models.gd")
const PACING = preload("res://frame_pacing.gd")
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

enum Screen { HIDDEN, TITLE, PAUSE, SETTINGS, HANGAR, RESULTS, BRIDGES, CONFIRM_RESET, TESTS, SCORES, INITIALS, LANGUAGES }

enum SettingsTab { GAME, AUDIO, DISPLAY, ADVANCED }
const SETTINGS_TAB_LABELS := ["settings.tab_game", "settings.tab_audio", "settings.tab_display", "settings.tab_advanced"]

signal action_requested(action: StringName)
signal bridge_replay_requested(best: bool, index: int)
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
var _stick_direction := 0
var _reset_score_button: Button
var _language_button: Button
var _settings_tab := SettingsTab.GAME
var _settings_tabs: Array[Button] = []
var _score_notice := ""
var _scores_return := Screen.TITLE
var _pending_score := 0
var _initials := "AAA"
var _initial_index := 0
var _initial_stick := Vector2i.ZERO
var _initial_labels: Array[Label] = []
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
	_result_flight = null
	_result_raid = null
	_show_page(Screen.TITLE)


func show_pause(from_bridges: bool = false) -> void:
	_pause_from_bridges = from_bridges
	_show_page(Screen.PAUSE)


func show_results(flight: FLIGHT, replay: RAID_REPLAY) -> void:
	_result_flight = flight
	_result_raid = replay
	_bridge_top = 0
	_bridge_focus = Vector2i(-1, 0)
	_pending_score = flight.score if flight.cheats == 0 and settings.score_rank(flight.score) >= 0 else 0
	if _pending_score > 0:
		_open_initials()
	else:
		_show_page(Screen.RESULTS)


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
		Screen.RESULTS:
			_request(&"title")
		Screen.PAUSE:
			_request(&"resume")
		Screen.CONFIRM_RESET:
			_return_from_reset()
		Screen.SCORES:
			_show_page(_scores_return)
		Screen.INITIALS:
			_show_page(Screen.RESULTS)
		Screen.LANGUAGES:
			_return_to_language_settings()


func show_notice(key: String, detail: String = "") -> void:
	_notice_key = key
	_notice_detail = detail
	if is_instance_valid(_status) and (screen != Screen.SETTINGS or not key.is_empty()):
		_status.text = _notice_text()


func _notice_text() -> String:
	var message := tr(_notice_key)
	return message if _notice_detail.is_empty() else message % tr(_notice_detail)


func _show_page(next: Screen) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_hangar_choices.clear()
	_hangar_model = null
	_keyboard_buttons.clear()
	_controller_buttons.clear()
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
	set_process(next == Screen.BRIDGES)
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
	content.custom_minimum_size.x = 670 if next == Screen.SETTINGS else (450 if next == Screen.RESULTS else 382)
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
	elif next == Screen.TESTS:
		_test_page(content)
	elif next == Screen.SCORES:
		_scores_page(content)
	elif next == Screen.INITIALS:
		_initials_page(content)
	elif next == Screen.LANGUAGES:
		_languages_page(content)
	else:
		_home_page(content, next == Screen.PAUSE)


func _home_page(content: VBoxContainer, paused: bool) -> void:
	_caption(content, tr("menu.beta") % ProjectSettings.get_setting("application/config/version"), 13, ACCENT)
	_caption(content, tr("menu.pause") if paused else "FLUVIAL STRIKE", 38, TEXT)
	_caption(content, tr("menu.record") % settings.record, 16, MUTED)
	if not paused:
		_caption(content, tr("menu.controls"), 13, MUTED)
	content.add_child(HSeparator.new())
	var primary := _button(content, tr("menu.resume") if paused else tr("menu.play"), true)
	primary.pressed.connect(_request.bind(&"resume" if paused else &"play"))
	if paused:
		var retry := _button(content, tr("menu.restart"))
		retry.pressed.connect(_request.bind(&"play"))
	else:
		var best := _button(content, tr("menu.best_replay"))
		best.disabled = settings.best_raid == null
		best.tooltip_text = tr("menu.best_replay_help") if best.disabled else ""
		best.pressed.connect(_request.bind(&"best_replay"))
		var latest := _button(content, tr("menu.last_replay"))
		latest.disabled = settings.last_raid == null
		latest.tooltip_text = tr("menu.last_replay_help") if latest.disabled else ""
		latest.pressed.connect(_request.bind(&"last_replay"))
		var scores_button := _button(content, tr("menu.leaderboard"))
		scores_button.pressed.connect(_open_scores.bind(Screen.TITLE))
		var hangar := _button(content, tr("menu.hangar"))
		hangar.pressed.connect(_show_page.bind(Screen.HANGAR))
	var options := _button(content, tr("menu.settings"))
	options.pressed.connect(_open_settings)
	var exit_label := tr("results.bridge_report") if _pause_from_bridges else tr("common.main_menu")
	var last := _button(content, exit_label if paused else tr("menu.quit"))
	last.pressed.connect(_request.bind(&"title" if paused else &"quit"))
	_status = _caption(content, _notice_text(), 13, ACCENT)
	primary.grab_focus()


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
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	content.add_child(grid)
	_caption(grid, tr("scores.rank"), 13, MUTED).custom_minimum_size.x = 45
	_caption(grid, tr("scores.initials"), 13, MUTED).custom_minimum_size.x = 115
	var heading := _caption(grid, tr("common.score"), 13, MUTED)
	heading.custom_minimum_size.x = 130
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in SETTINGS.SCORE_LIMIT:
		var entry: Dictionary = settings.scores[i] if i < settings.scores.size() else {}
		var color := ACCENT if i == 0 and not entry.is_empty() else (MUTED if entry.is_empty() else TEXT)
		_caption(grid, "%02d" % (i + 1), 17, color)
		_caption(grid, entry.get("initials", "—"), 17, color)
		var value := "%06d" % entry.score if not entry.is_empty() else "—"
		_caption(grid, value, 17, color).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var return_button := _button(content, tr("common.back"))
	return_button.pressed.connect(back)
	return_button.grab_focus()


func _open_initials() -> void:
	_initials = "AAA"
	_initial_index = 0
	_initial_stick = Vector2i.ZERO
	_show_page(Screen.INITIALS)


func _initials_page(content: VBoxContainer) -> void:
	_caption(content, tr("scores.enter_title"), 30, TEXT)
	_caption(content, tr("scores.points") % _pending_score, 22, ACCENT)
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
	_caption(content, tr("scores.actions"), 14, MUTED)
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
	var error := settings.submit_score(_initials, _pending_score)
	if error != OK and error != ERR_UNAVAILABLE:
		_status.text = tr("scores.save_failed")
		return
	_pending_score = 0
	_open_scores(Screen.RESULTS)


func _set_initial(letter: String) -> void:
	_initials = _initials.substr(0, _initial_index) + letter + _initials.substr(_initial_index + 1)


func _handle_initials(event: InputEvent) -> bool:
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
	_initial_index = posmod(_initial_index + direction.x, 3)
	if direction.y != 0:
		var alphabet := SETTINGS.INITIALS_ALPHABET
		var index := alphabet.find(_initials[_initial_index])
		_set_initial(alphabet[posmod(index - direction.y, alphabet.length())])
	_refresh_initials()
	return true


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
		set_process(pending)
	else:
		_caption(content, tr("bridges.empty"), 16, MUTED)
		set_process(false)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	if _bridge_total > _bridge_rows.size():
		var hint := _caption(footer, tr("bridges.page_controls"), 14, MUTED)
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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


func _process(_delta: float) -> void:
	if screen == Screen.BRIDGES and settings.best_raid.prepare_bridge_stats(720):
		_status.text = ""
		_refresh_bridge_rows()
		set_process(false)


func _hangar_page(content: VBoxContainer) -> void:
	_caption(content, tr("menu.hangar"), 32, TEXT)
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
	_button(footer, tr("common.back")).pressed.connect(back)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	_button(footer, tr("hangar.choose"), true).pressed.connect(_confirm_aircraft)
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
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var back_button := _button(header, tr("common.back"), false, 30)
	back_button.pressed.connect(back)
	var title := _caption(header, tr("menu.settings"), 25, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hint := _caption(header, tr("settings.tabs_navigation"), 13, MUTED)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	for i in SETTINGS_TAB_LABELS.size():
		var tab := _button(tabs, tr(SETTINGS_TAB_LABELS[i]), i == _settings_tab)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_settings_tab.bind(i as SettingsTab, true))
		_settings_tabs.append(tab)
	content.add_child(HSeparator.new())

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	content.add_child(body)
	var first: Control
	match _settings_tab:
		SettingsTab.GAME:
			first = _settings_game(body)
		SettingsTab.AUDIO:
			first = _settings_audio(body)
		SettingsTab.DISPLAY:
			first = _settings_display(body)
		SettingsTab.ADVANCED:
			first = _settings_advanced(body)
	if _status == null:
		_status = _caption(body, "", 13, ACCENT)
	first.grab_focus()


func _select_settings_tab(tab: SettingsTab, keep_tab_focus: bool) -> void:
	if tab != _settings_tab:
		_settings_tab = tab
		_show_page(Screen.SETTINGS)
	if keep_tab_focus:
		_settings_tabs[tab].grab_focus()


func _settings_game(content: VBoxContainer) -> Control:
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	content.add_child(options)
	var language := _caption(options, tr("settings.language"), 15, TEXT)
	language.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_language_button = _button(options, SETTINGS.LANGUAGES[settings.language] + "  ›", false, 30)
	_language_button.custom_minimum_size.x = 115
	_language_button.tooltip_text = tr("settings.language_help")
	_language_button.pressed.connect(_show_page.bind(Screen.LANGUAGES))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)
	var ghost_label := _caption(options, tr("settings.ghost"), 15, TEXT)
	ghost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ghost := _button(options, tr(GHOST_OPTIONS[settings.ghost_source]) + "  ↻", false, 30)
	ghost.custom_minimum_size.x = 135
	ghost.tooltip_text = tr("settings.ghost_help")
	ghost.pressed.connect(func() -> void:
		settings.ghost_source = ((settings.ghost_source + 1) % GHOST_OPTIONS.size()) as SETTINGS.Ghost
		ghost.text = tr(GHOST_OPTIONS[settings.ghost_source]) + "  ↻"
		settings_changed.emit())
	var vibration := HBoxContainer.new()
	vibration.add_theme_constant_override("separation", 10)
	content.add_child(vibration)
	_percentage_slider(vibration, tr("settings.rumble"), &"vibration")
	content.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for title in [tr("settings.bindings"), tr("settings.keyboard"), tr("settings.controller")]:
		_caption(grid, title, 15, ACCENT)
	for i in SETTINGS.ACTIONS.size():
		var label := _caption(grid, tr(SETTINGS.ACTIONS[i][1]), 15, TEXT)
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
	var notice := tr("settings.binding_hint")
	_status = _caption(content, notice, 13, MUTED)
	_button(content, tr("settings.restore_bindings"), false, 30).pressed.connect(_restore_bindings)
	return _language_button


func _settings_audio(content: VBoxContainer) -> Control:
	var audio := HBoxContainer.new()
	audio.add_theme_constant_override("separation", 10)
	content.add_child(audio)
	var first := _percentage_slider(audio, tr("settings.volume"), &"volume")
	_toggle(audio, tr("settings.mute"), settings.muted, &"muted")
	return first


func _settings_display(content: VBoxContainer) -> Control:
	var video := HBoxContainer.new()
	video.add_theme_constant_override("separation", 9)
	content.add_child(video)
	var first := _toggle(video, tr("settings.fullscreen"), settings.fullscreen, &"fullscreen")
	_toggle(video, tr("settings.hd"), settings.quality_hd, &"quality_hd")
	_toggle(video, tr("settings.adaptive_resolution"), settings.dynamic_resolution, &"dynamic_resolution")
	_toggle(content, tr("settings.panorama"), settings.panorama, &"panorama")
	var overlay := HBoxContainer.new()
	overlay.add_theme_constant_override("separation", 8)
	content.add_child(overlay)
	_toggle(overlay, tr("settings.show_fps"), settings.show_fps, &"show_fps")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	var scanline_label := _caption(overlay, tr("settings.scanlines"), 15, TEXT)
	scanline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var scanlines := _button(overlay, tr(SCANLINE_OPTIONS[settings.scanlines]) + "  ↻", false, 30)
	scanlines.custom_minimum_size.x = 135
	scanlines.pressed.connect(func() -> void:
		settings.scanlines = ((settings.scanlines + 1) % SCANLINE_OPTIONS.size()) as SETTINGS.Scanlines
		scanlines.text = tr(SCANLINE_OPTIONS[settings.scanlines]) + "  ↻"
		settings_changed.emit())
	return first


func _settings_advanced(content: VBoxContainer) -> Control:
	var timing := HBoxContainer.new()
	timing.add_theme_constant_override("separation", 8)
	content.add_child(timing)
	_caption(timing, tr("settings.refresh"), 15, TEXT)
	var rates: Array[String] = [tr("settings.auto")]
	for hz in PACING.RATES.slice(1):
		rates.append("%d Hz" % hz)
	var first := _select(timing, rates, PACING.RATES, settings.refresh_limit, &"refresh_limit")
	_caption(timing, tr("settings.sync"), 15, TEXT)
	_select(timing, [tr("settings.screen"), tr("settings.vrr"), tr("common.off")],
		[PACING.Sync.SCREEN, PACING.Sync.ADAPTIVE, PACING.Sync.OFF], settings.sync_mode, &"sync_mode")
	var monitor_hz := DisplayServer.screen_get_refresh_rate()
	if monitor_hz > 0:
		_caption(timing, tr("settings.monitor") % monitor_hz, 13, MUTED)
	content.add_child(HSeparator.new())
	_reset_score_button = _button(content, tr("settings.reset_scores"), false, 30)
	_reset_score_button.disabled = settings.record == 0 and settings.best_raid == null \
		and settings.scores == SETTINGS.DEFAULT_SCORES
	_reset_score_button.pressed.connect(_show_page.bind(Screen.CONFIRM_RESET))
	_status = _caption(content, tr(_score_notice), 13, ACCENT)
	return first


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
	if changed:
		settings_changed.emit()
		settings_committed.emit()


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
	if not _reset_score_button.disabled:
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

	if joy_back or (screen != Screen.TITLE and event.is_action_pressed(&"ui_cancel")):
		var focus := get_viewport().gui_get_focus_owner()
		if focus is OptionButton and focus.get_popup().visible:
			focus.get_popup().hide()
		else:
			back()
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.SETTINGS and _handle_settings_tabs(event):
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.BRIDGES and _handle_bridge_scroll(event):
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.TITLE and event is InputEventKey and event.pressed and not event.echo \
			and event.unicode > 0 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if _type_cheat_character(String.chr(event.unicode).to_lower()):
			get_viewport().set_input_as_handled()
			return
	_navigate_vertical(event)


func _handle_settings_tabs(event: InputEvent) -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is OptionButton and focus.get_popup().visible:
		return false
	var tab_focused := focus is Button and focus in _settings_tabs
	var direction := 0
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				direction = -1
			JOY_BUTTON_RIGHT_SHOULDER:
				direction = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match key:
			KEY_PAGEUP:
				direction = -1
			KEY_PAGEDOWN:
				direction = 1
			KEY_TAB:
				if not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
					direction = -1 if event.shift_pressed else 1
	if direction == 0 and tab_focused and (event is InputEventKey or event is InputEventJoypadButton):
		if event.is_action_pressed(&"ui_left"):
			direction = -1
		elif event.is_action_pressed(&"ui_right"):
			direction = 1
	if direction == 0:
		return false
	_select_settings_tab(posmod(_settings_tab + direction, SETTINGS_TAB_LABELS.size()) as SettingsTab, tab_focused)
	return true


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
	if screen == Screen.BRIDGES:
		_step_bridge_focus(direction)
		get_viewport().set_input_as_handled()
		return
	var neighbor := focus.find_valid_focus_neighbor(SIDE_TOP if direction < 0 else SIDE_BOTTOM)
	if neighbor == null or neighbor == focus or not is_ancestor_of(neighbor):
		neighbor = _wrapped_focus(focus, direction)
	if neighbor:
		neighbor.grab_focus()
	get_viewport().set_input_as_handled()


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


func _listen(index: int, controller: bool) -> void:
	_waiting_index = index
	_waiting_for_controller = controller
	_refresh_bindings()
	_status.text = tr("settings.binding_press_gamepad") if controller else tr("settings.binding_press_keyboard")


func _finish_binding(message: String) -> void:
	_waiting_index = -1
	_refresh_bindings()
	_status.text = message


func _refresh_bindings() -> void:
	for i in SETTINGS.ACTIONS.size():
		var key := DisplayServer.keyboard_get_keycode_from_physical(settings.keyboard[i] as Key)
		var pad := settings.gamepad[i]
		var pad_name := tr(BUTTON_NAMES[pad]) if BUTTON_NAMES.has(pad) else tr("settings.button_number") % (pad + 1)
		_keyboard_buttons[i].text = tr("settings.binding_press") if _waiting_index == i and not _waiting_for_controller \
			else tr(KEY_NAMES.get(key, OS.get_keycode_string(key)))
		_controller_buttons[i].text = tr("settings.binding_press") if _waiting_index == i and _waiting_for_controller \
			else pad_name


func _restore_bindings() -> void:
	settings.reset_bindings()
	settings_changed.emit()
	_finish_binding(tr("settings.bindings_restored"))


func _open_settings() -> void:
	_return_to = screen
	_score_notice = ""
	_settings_tab = SettingsTab.GAME
	_show_page(Screen.SETTINGS)


func _request(action: StringName) -> void:
	action_requested.emit(action)


func _percentage_slider(row: HBoxContainer, title: String, property: StringName) -> HSlider:
	_caption(row, title, 16, TEXT).custom_minimum_size.x = 92
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(210, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.max_value = 100
	slider.step = 5
	slider.value = settings.get(property)
	row.add_child(slider)
	var label := _caption(row, "%d %%" % slider.value, 14, MUTED)
	label.custom_minimum_size.x = 48
	slider.value_changed.connect(_set_percentage.bind(label, property))
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
	parent.add_child(button)
	return button


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
