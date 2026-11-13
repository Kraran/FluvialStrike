extends Control
## Grand « GAME OVER » après la perte de la dernière vie : un bandeau traverse l'écran,
## le titre tombe en grossissant puis se pose avec un rebond qui secoue la vue.
## Il attend ensuite A, Entrée, Espace, Start, B, Échap ou un clic pour ouvrir le bilan.

signal impact
signal continued

const INPUT_GLYPHS = preload("res://input_glyphs.gd")
const TITLE_FONT := "res://fonts/BlackOpsOne-Regular.ttf"
const VOICE_PATH := "res://gameover_voice.mp3"
const TITLE := "GAME OVER"
const PLAY_HEIGHT := 483.0
const BAND_CENTER := 226.0
const BAND_HEIGHT := 196.0
const TITLE_SIZE := 104
const INK := Color("#071c27")
const TEXT := Color("#e8f3ed")
const MUTED := Color("#a7bbc0")
const MINT := Color("#a8ecc9")
const ACCENT := Color("#ff9a3c")
const SHADOW := Color("#0b2633")
const LAND_TIME := 0.28
const STATS_TIME := 0.38
const PROMPT_TIME := 0.9
const PLAYER_LIFT := 14.0
const PLAYER_SIZE := 22

var _time := 0.0
var _landed := false
var _armed := false
var _stats: Array = []
var _title_font: Font
var _prompt: Control
var _prompt_label := ""
# Nom du joueur au-dessus du titre en mode Deux joueurs ; vide en solo.
var _player := ""
## Coupe la voix quand le son du jeu est coupé ou à zéro.
var muted := false
var _voice := AudioStreamPlayer.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func _ready() -> void:
	_title_font = _load_title_font()
	_voice.stream = _load_voice()
	add_child(_voice)


## Montre le bandeau avec le score, la section et le meilleur score de la partie.
func present(score: int, section: int, best: int, device: int, player: String = "") -> void:
	_time = 0.0
	_player = player
	_landed = false
	_armed = false
	_stats = [[tr("gameover.score"), "%06d" % score, Color.WHITE], [tr("gameover.section"), "%02d" % section, Color.WHITE],
		[tr("gameover.best"), "%06d" % maxi(best, score), MINT]]
	if is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = INPUT_GLYPHS.Glyph.new(device, INPUT_GLYPHS.Prompt.ACCEPT, tr("key.enter"))
	_prompt.modulate.a = 0.0
	add_child(_prompt)
	_prompt_label = tr("gameover.continue")
	# La voix annonce le GAME OVER dès que le bandeau s'ouvre, comme celle de l'intro.
	if not muted and _voice.stream:
		_voice.stop()
		_voice.play()
	visible = true
	set_process(true)
	queue_redraw()


## La partie est finie : le bandeau accepte désormais une pression pour continuer.
func arm() -> void:
	_armed = true


func dismiss() -> void:
	visible = false
	_armed = false
	set_process(false)


func is_shown() -> bool:
	return visible


func _process(delta: float) -> void:
	_time += delta
	if not _landed and _time >= LAND_TIME:
		_landed = true
		impact.emit()
	if is_instance_valid(_prompt):
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(_prompt_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var glyph_size := _prompt.get_combined_minimum_size()
		var pill_width := glyph_size.x + 10.0 + text_width + 40.0
		_prompt.size = glyph_size
		_prompt.position = Vector2(size.x * 0.5 - pill_width * 0.5 + 20.0, 352.0 + (42.0 - glyph_size.y) * 0.5)
		_prompt.modulate.a = _prompt_alpha()
	queue_redraw()


func _prompt_alpha() -> float:
	if not _armed:
		return 0.0
	var shown := smoothstep(PROMPT_TIME, PROMPT_TIME + 0.25, _time)
	return shown * (0.8 + 0.2 * sin(_time * 4.0))


func _input(event: InputEvent) -> void:
	if not visible or not _armed or _time < PROMPT_TIME:
		return
	var go := false
	if event is InputEventJoypadButton and event.pressed:
		go = event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]
	elif event is InputEventKey and event.pressed and not event.echo:
		go = event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]
	elif event is InputEventMouseButton and event.pressed:
		go = event.button_index == MOUSE_BUTTON_LEFT
	if go:
		get_viewport().set_input_as_handled()
		continued.emit()


func _draw() -> void:
	var width := size.x
	var center_x := width * 0.5
	draw_rect(Rect2(0, 0, width, PLAY_HEIGHT), Color(0.016, 0.055, 0.078, 0.42 * smoothstep(0.0, 0.3, _time)))
	# Le bandeau s'ouvre depuis sa ligne médiane.
	var opening := _ease_out(clampf(_time / 0.22, 0.0, 1.0))
	# Avec un nom de joueur, le bandeau s'agrandit pour le loger au-dessus du titre.
	var lift := 0.0 if _player.is_empty() else PLAYER_LIFT
	var band := (BAND_HEIGHT + lift * 2.0) * opening
	var top := BAND_CENTER - band * 0.5
	draw_rect(Rect2(0, top, width, band), Color(INK, 0.93))
	draw_rect(Rect2(0, top, width, 2), ACCENT)
	draw_rect(Rect2(0, top + band - 2.0, width, 2), ACCENT)

	# Le titre tombe de très gros à sa taille, puis rebondit légèrement.
	var scale := 1.0
	if _time < LAND_TIME:
		var fall := _time / LAND_TIME
		scale = lerpf(2.4, 1.0, fall * fall * fall)
	else:
		var after := _time - LAND_TIME
		scale = 1.0 + 0.07 * sin(after * 26.0) * exp(-after * 9.0)
	var alpha := smoothstep(0.0, 0.1, _time)
	var font := _title_font if _title_font else ThemeDB.fallback_font
	var title_width := font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	var baseline := BAND_CENTER + 14.0 + lift
	if not _player.is_empty():
		var label_alpha := smoothstep(0.12, 0.3, _time)
		var body := ThemeDB.fallback_font
		var label := _player.to_upper()
		var label_width := body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, PLAYER_SIZE).x
		draw_string(body, Vector2(center_x - label_width * 0.5, BAND_CENTER - 56.0 - lift * 0.4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, PLAYER_SIZE, Color(MINT, label_alpha))
	draw_set_transform(Vector2(center_x, baseline - 36.0), 0.0, Vector2.ONE * scale)
	var origin := Vector2(-title_width * 0.5, 36.0)
	var glow := Color(1.0, 0.55, 0.24, 0.11 * alpha)
	for offset: Vector2 in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-2, -2), Vector2(2, 2)]:
		draw_string(font, origin + offset * 1.4, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, glow)
	draw_string(font, origin + Vector2(0, 4), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(SHADOW, alpha))
	draw_string(font, origin, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO)

	# Score, section et meilleur score.
	var stats_alpha := smoothstep(STATS_TIME, STATS_TIME + 0.25, _time)
	if stats_alpha > 0.0:
		var body := ThemeDB.fallback_font
		var parts: Array = []
		var total := 0.0
		for stat: Array in _stats:
			var label_width := body.get_string_size(stat[0] + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			var value_width := body.get_string_size(stat[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			parts.append([label_width, value_width])
			total += label_width + value_width
		total += 26.0 * (_stats.size() - 1)
		var x := center_x - total * 0.5
		var y := BAND_CENTER + 74.0 + lift + (1.0 - stats_alpha) * 6.0
		for i in _stats.size():
			var stat: Array = _stats[i]
			draw_string(body, Vector2(x, y), stat[0] + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(MUTED, stats_alpha))
			x += parts[i][0]
			draw_string(body, Vector2(x, y), stat[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(stat[2], stats_alpha))
			x += parts[i][1] + 26.0

	# Invite à continuer, sous le bandeau.
	var prompt_alpha := _prompt_alpha()
	if prompt_alpha > 0.0 and is_instance_valid(_prompt):
		var body := ThemeDB.fallback_font
		var text_width := body.get_string_size(_prompt_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var glyph_width := _prompt.size.x
		var pill := Rect2(center_x - (glyph_width + 10.0 + text_width + 40.0) * 0.5, 352.0, glyph_width + 10.0 + text_width + 40.0, 42.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(Color("#174036"), prompt_alpha)
		fill.border_color = Color(Color("#568d75"), prompt_alpha)
		fill.set_border_width_all(1)
		fill.set_corner_radius_all(4)
		draw_style_box(fill, pill)
		var baseline_y := pill.position.y + (pill.size.y + body.get_ascent(16) - body.get_descent(16)) * 0.5
		draw_string(body, Vector2(pill.position.x + 20.0 + glyph_width + 10.0, baseline_y), _prompt_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(MINT, prompt_alpha))


static func _ease_out(value: float) -> float:
	return 1.0 - pow(1.0 - value, 3.0)


## Charge la voix importée par l'éditeur, ou directement le fichier MP3 sans import préalable.
static func _load_voice() -> AudioStream:
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(VOICE_PATH + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	if imported and ResourceLoader.exists(VOICE_PATH):
		var stream := load(VOICE_PATH) as AudioStream
		if stream:
			return stream
	if FileAccess.file_exists(VOICE_PATH):
		return AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(VOICE_PATH))
	return null


## Charge la police importée par l'éditeur, ou directement le fichier sans import préalable.
static func _load_title_font() -> Font:
	var imported := true
	var import_file := ConfigFile.new()
	if import_file.load(TITLE_FONT + ".import") == OK:
		imported = FileAccess.file_exists(str(import_file.get_value("remap", "path", "")))
	var font: FontFile
	if imported and ResourceLoader.exists(TITLE_FONT):
		font = load(TITLE_FONT) as FontFile
	if font == null and FileAccess.file_exists(TITLE_FONT):
		font = FontFile.new()
		if font.load_dynamic_font(ProjectSettings.globalize_path(TITLE_FONT)) != OK:
			return null
	if font == null:
		return null
	var spaced := FontVariation.new()
	spaced.base_font = font
	spaced.spacing_glyph = 6
	return spaced
