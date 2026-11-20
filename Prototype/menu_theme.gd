extends RefCounted
## Thème du menu : toutes ses couleurs, ses cadres et ses styles de boutons sont rangés ici.
## Le menu, les lignes de réglage et les pastilles de touches les lisent dans le Theme
## au lieu de les coder en dur : changer le thème suffit à changer l'aspect du menu.
##
## Le thème habille aussi le tableau de bord en vol (voir « FluvialHud » plus bas).
##
## Thèmes proposés dans Réglages > Affichage > Thème :
## - « Estuaire (Défaut) » (estuary) : bleu nuit et vert d'eau, l'aspect d'origine ;
## - « Phosphore » (phosphor) : écran ambre des terminaux des années 80, police à chasse fixe ;
## - « Mousson » (monsoon) : jungle humide, vert profond et citron vert, coins arrondis ;
## - « Escadrille » (squadron) : kaki militaire et jaune pochoir, police condensée ;
## - « Glacier » (glacier) : thème clair, blanc givré et bleu acier ;
## - « Néon » (neon) : synthwave, violet nuit, magenta et cyan ;
## - « Carte d'état-major » (staff_map) : thème clair, papier ancien, sépia et rouge ;
## - « Personnalisé » (custom), proposé seulement si res://menu_theme.tres existe :
##   ce Theme, enregistré depuis l'éditeur Godot, part d'Estuaire et remplace
##   les valeurs qu'il définit ; tout le reste garde l'aspect d'Estuaire.
## Pour ajouter un thème intégré, ajoute son identifiant et son nom à THEMES, puis sa
## palette à PALETTES : build() part d'Estuaire et y applique la palette.
##
## Valeurs propres au menu, sous le type « FluvialMenu » :
## - couleurs : ink, line, text, accent, muted, highlight, shade, gauge_full, gauge_empty,
##   hangar_background, hangar_ambient, hangar_rim, glyph_ink, glyph_cap, logo (teinte du logo
##   FLUVIAL STRIKE, blanc d'origine : à foncer sur un thème clair) ;
## - cadres : page, page_settings, card, note, strip, slot_free, slot_taken, tile,
##   tile_active, portrait_frame ;
## - police : arrow_font (facultative), pour les flèches ◀ ▶ des lignes de réglage et les
##   flèches des touches (← → ↑ ↓) quand la police du thème les dessine trop petites.
## Variantes de boutons : « PrimaryButton » (action principale) et « UnavailableButton »
## (avion déjà pris par l'autre joueur).
##
## Tableau de bord en vol (HUD), sous le type « FluvialHud » :
## - couleurs : background (fond de la barre), top_line (liseré du haut), divider (séparateurs
##   et graduations), text, muted, accent (jauge et textes d'information), warning (carburant bas,
##   avion gagné), refuel (ravitaillement), gauge_track (segments vides), horizon_ground,
##   horizon_sky (horizon artificiel), overlay (encadrés en haut de l'écran), banner (bandeau
##   des messages au centre) ;
## - police : font (facultative ; sans elle, la police par défaut de Godot).

const TYPE := &"FluvialMenu"
const HUD_TYPE := &"FluvialHud"
## Couleurs du tableau de bord lues par flight_view.gd.
const HUD_COLORS := [&"background", &"top_line", &"divider", &"text", &"muted", &"accent", &"warning",
	&"refuel", &"gauge_track", &"horizon_ground", &"horizon_sky", &"overlay", &"banner"]
const PRIMARY_BUTTON := &"PrimaryButton"
const UNAVAILABLE_BUTTON := &"UnavailableButton"
const CUSTOM_PATH := "res://menu_theme.tres"
const DEFAULT := "estuary"
const CUSTOM := "custom"
## Thèmes intégrés, dans l'ordre du menu : identifiant enregistré → clé de traduction du nom.
const THEMES := {
	"estuary": "theme.estuary",
	"phosphor": "theme.phosphor",
	"monsoon": "theme.monsoon",
	"squadron": "theme.squadron",
	"glacier": "theme.glacier",
	"neon": "theme.neon",
	"staff_map": "theme.staff_map",
}
## Palettes des thèmes autres qu'Estuaire. Couleurs en hexadécimal, ou [r, g, b, a] pour
## les voiles translucides ; radius et border règlent l'arrondi et l'épaisseur des cadres ;
## font est la police des menus et du tableau de bord (weight : graisse d'une police variable) ;
## godot_arrows dessine les flèches ◀ ▶ des réglages avec la police de Godot.
const PALETTES := {
	"phosphor": {
		"bg": "#0a0700", "card": "#120c02", "button": "#1a1103", "hover": "#2a1b04", "pressed": "#3a2606",
		"line": "#5a3a00", "hover_line": "#a06a00", "text": "#ffb000", "muted": "#b07a10", "accent": "#ffd36a",
		"highlight": "#ff5a1f", "primary": "#3a2606", "primary_line": "#ffb000", "focus_text": "#fff2c8",
		"shade": [0.04, 0.025, 0.0, 0.72], "radius": 0, "border": 1, "logo": "#ffb000",
		"font": "res://fonts/AnonymousPro-Bold.ttf",
		"hangar_background": "#1a1103", "hangar_ambient": "#ffd9a0", "hangar_rim": "#ffb000",
		"glyph_ink": "#0a0700", "glyph_cap": "#ffb000",
		"hud": {"background": "#0a0700", "top_line": "#ffb000", "divider": "#5a3a00", "text": "#ffb000",
			"muted": "#b07a10", "accent": "#ffb000", "warning": "#ff5a1f", "refuel": "#fff2c8",
			"gauge_track": "#2a1b04", "horizon_ground": "#3a2606", "horizon_sky": "#a06a00",
			"overlay": "#0a0700", "banner": [0.04, 0.025, 0.0, 0.9]},
	},
	"monsoon": {
		"bg": "#0c1a11", "card": "#12261a", "button": "#163020", "hover": "#1f412b", "pressed": "#275235",
		"line": "#2f5a3a", "hover_line": "#5f9a5c", "text": "#eef4e2", "muted": "#a3bd9c", "accent": "#c9e85a",
		"highlight": "#ff8a3d", "primary": "#2c4a1c", "primary_line": "#9cc23e", "focus_text": "#ffffff",
		"shade": [0.02, 0.07, 0.04, 0.6], "radius": 12, "border": 1, "logo": "#ffffff",
		"font": "res://fonts/FiraSans-SemiBold.ttf",
		"hangar_background": "#14301f", "hangar_ambient": "#e3f0c8", "hangar_rim": "#c9e85a",
		"glyph_ink": "#0c1a11", "glyph_cap": "#c9e85a",
		"hud": {"background": "#0c1a11", "top_line": "#9cc23e", "divider": "#3d6b48", "text": "#eef4e2",
			"muted": "#a3bd9c", "accent": "#c9e85a", "warning": "#ff8a3d", "refuel": "#7fe3d0",
			"gauge_track": "#1f412b", "horizon_ground": "#5b4a2a", "horizon_sky": "#4f8a6a",
			"overlay": "#0c1a11", "banner": [0.03, 0.09, 0.05, 0.9]},
	},
	"squadron": {
		"bg": "#1d2114", "card": "#262b1a", "button": "#2c321e", "hover": "#3a4127", "pressed": "#4a5230",
		"line": "#5c6440", "hover_line": "#8e9662", "text": "#efe8cf", "muted": "#b6af8f", "accent": "#f2c230",
		"highlight": "#e2512b", "primary": "#4a4520", "primary_line": "#f2c230", "focus_text": "#ffffff",
		"shade": [0.07, 0.08, 0.04, 0.62], "radius": 2, "border": 2, "logo": "#f2c230",
		"font": "res://fonts/Anton-Regular.ttf",
		"hangar_background": "#2c321e", "hangar_ambient": "#efe8cf", "hangar_rim": "#f2c230",
		"glyph_ink": "#1d2114", "glyph_cap": "#efe8cf",
		"hud": {"background": "#1d2114", "top_line": "#f2c230", "divider": "#5c6440", "text": "#efe8cf",
			"muted": "#b6af8f", "accent": "#f2c230", "warning": "#e2512b", "refuel": "#9fd3e6",
			"gauge_track": "#3a4127", "horizon_ground": "#6b5a3a", "horizon_sky": "#7c8e9a",
			"overlay": "#1d2114", "banner": [0.11, 0.13, 0.08, 0.92]},
	},
	"glacier": {
		"bg": "#eef5f8", "card": "#dfeaf0", "button": "#e3edf2", "hover": "#d3e3ec", "pressed": "#c3d9e6",
		"line": "#a3bccb", "hover_line": "#6f97ad", "text": "#10313f", "muted": "#557785", "accent": "#0b78a8",
		"highlight": "#d9480f", "primary": "#cfe6f2", "primary_line": "#0b78a8", "focus_text": "#062230",
		"shade": [0.85, 0.92, 0.96, 0.35], "radius": 10, "border": 1, "logo": "#10313f",
		"font": "res://fonts/Inter-SemiBold.otf",
		"hangar_background": "#cfe2ec", "hangar_ambient": "#ffffff", "hangar_rim": "#9fd0ea",
		"glyph_ink": "#ffffff", "glyph_cap": "#10313f",
		"hud": {"background": "#e8f1f5", "top_line": "#0b78a8", "divider": "#a3bccb", "text": "#10313f",
			"muted": "#557785", "accent": "#0b78a8", "warning": "#d9480f", "refuel": "#14a3a3",
			"gauge_track": "#c9dae3", "horizon_ground": "#b9a68a", "horizon_sky": "#8cc4e0",
			"overlay": "#e8f1f5", "banner": [0.93, 0.96, 0.98, 0.92]},
	},
	"neon": {
		"bg": "#140a24", "card": "#1d0f33", "button": "#22123c", "hover": "#2f1950", "pressed": "#3d1f66",
		"line": "#5b2b8a", "hover_line": "#a052d6", "text": "#f6ecff", "muted": "#b79bd9", "accent": "#ff4fd8",
		"highlight": "#38e8ff", "primary": "#4a1650", "primary_line": "#ff4fd8", "focus_text": "#ffffff",
		"shade": [0.06, 0.02, 0.12, 0.6], "radius": 14, "border": 1, "logo": "#ffd6f6",
		"font": "res://fonts/Montserrat-Variable.ttf", "weight": 600, "godot_arrows": true,
		"hangar_background": "#22123c", "hangar_ambient": "#e6d4ff", "hangar_rim": "#38e8ff",
		"glyph_ink": "#140a24", "glyph_cap": "#38e8ff",
		"hud": {"background": "#140a24", "top_line": "#ff4fd8", "divider": "#5b2b8a", "text": "#f6ecff",
			"muted": "#b79bd9", "accent": "#38e8ff", "warning": "#ff4fd8", "refuel": "#9dffb0",
			"gauge_track": "#2f1950", "horizon_ground": "#4a1650", "horizon_sky": "#2a6fd6",
			"overlay": "#140a24", "banner": [0.08, 0.04, 0.14, 0.9]},
	},
	"staff_map": {
		"bg": "#efe4c9", "card": "#e6d8b6", "button": "#e9dcbc", "hover": "#dfcea6", "pressed": "#d4c093",
		"line": "#a68f63", "hover_line": "#7a6440", "text": "#3a2a17", "muted": "#7a6547", "accent": "#a8321e",
		"highlight": "#1f5f8b", "primary": "#e3c9a0", "primary_line": "#a8321e", "focus_text": "#2a1c0c",
		"shade": [0.94, 0.89, 0.78, 0.3], "radius": 3, "border": 1, "logo": "#3a2a17",
		"font": "res://fonts/Bitter-Variable.ttf", "weight": 600, "godot_arrows": true,
		"hangar_background": "#e6d8b6", "hangar_ambient": "#fff4dc", "hangar_rim": "#d9b77a",
		"glyph_ink": "#efe4c9", "glyph_cap": "#3a2a17",
		"hud": {"background": "#efe4c9", "top_line": "#a8321e", "divider": "#a68f63", "text": "#3a2a17",
			"muted": "#7a6547", "accent": "#1f5f8b", "warning": "#a8321e", "refuel": "#3d8a5a",
			"gauge_track": "#dccca8", "horizon_ground": "#b5946a", "horizon_sky": "#8fb4c9",
			"overlay": "#efe4c9", "banner": [0.94, 0.89, 0.78, 0.94]},
	},
}

static var _fonts := {}
const ARROW_CHARACTERS := "←→↑↓◀▶"


## Vrai pour un texte fait seulement de flèches (et d'espaces ou de barres) : « ← », « ↑ / ↓ »…
static func is_arrow_text(text: String) -> bool:
	var found := false
	for character in text:
		if character in ARROW_CHARACTERS:
			found = true
		elif not character in " /·":
			return false
	return found


## Thèmes proposés, dans l'ordre du menu : identifiant → clé de traduction du nom.
static func available() -> Dictionary:
	var result := THEMES.duplicate()
	if ResourceLoader.exists(CUSTOM_PATH):
		result[CUSTOM] = "theme.custom"
	return result


## Vrai si l'identifiant désigne un thème connu (le thème personnalisé compris).
static func is_known(id: String) -> bool:
	return id in THEMES or id == CUSTOM


## Thème du menu choisi dans les réglages ; Estuaire si le thème demandé n'est pas disponible.
static func load_theme(id: String = DEFAULT) -> Theme:
	if id == CUSTOM and ResourceLoader.exists(CUSTOM_PATH):
		var custom := load(CUSTOM_PATH) as Theme
		if custom:
			var result := build(DEFAULT)
			result.merge_with(custom)
			return result
	return build(id if id in THEMES else DEFAULT)


## Construit un thème intégré : Estuaire, sur lequel on applique la palette du thème demandé.
static func build(id: String) -> Theme:
	var result := build_estuary()
	if id in PALETTES:
		_apply_palette(result, PALETTES[id])
	return result


static func _apply_palette(result: Theme, spec: Dictionary) -> void:
	for key: String in ["text", "accent", "muted", "highlight", "line", "logo", "hangar_background",
			"hangar_ambient", "hangar_rim", "glyph_ink", "glyph_cap"]:
		result.set_color(StringName(key), TYPE, _color(spec[key]))
	result.set_color(&"ink", TYPE, _color(spec.bg))
	result.set_color(&"shade", TYPE, _color(spec.shade))
	result.set_color(&"gauge_full", TYPE, _color(spec.hud.accent))
	result.set_color(&"gauge_empty", TYPE, _color(spec.hud.gauge_track))
	result.set_stylebox(&"page", TYPE, _frame(spec, spec.bg, spec.line, 22))
	result.set_stylebox(&"page_settings", TYPE, _frame(spec, spec.bg, spec.line, 12))
	result.set_stylebox(&"card", TYPE, _frame(spec, spec.card, spec.line, 12))
	result.set_stylebox(&"note", TYPE, _frame(spec, spec.card, spec.line, 10))
	result.set_stylebox(&"strip", TYPE, _frame(spec, spec.bg, spec.line, 8))
	result.set_stylebox(&"slot_free", TYPE, _frame(spec, spec.card, spec.line, 12))
	result.set_stylebox(&"slot_taken", TYPE, _frame(spec, spec.button, spec.accent, 12))
	result.set_stylebox(&"tile", TYPE, _frame(spec, spec.button, spec.line, 8))
	result.set_stylebox(&"tile_active", TYPE, _frame(spec, spec.button, spec.accent, 8))
	var portrait := result.get_stylebox(&"portrait_frame", TYPE).duplicate() as StyleBoxFlat
	portrait.border_color = _color(spec.line)
	result.set_stylebox(&"portrait_frame", TYPE, portrait)

	result.set_stylebox(&"normal", &"Button", _frame(spec, spec.button, spec.line, 8))
	result.set_stylebox(&"hover", &"Button", _frame(spec, spec.hover, spec.hover_line, 8))
	result.set_stylebox(&"pressed", &"Button", _frame(spec, spec.pressed, spec.accent, 8))
	var focus := _frame(spec, spec.hover, spec.accent, 8)
	focus.bg_color = Color(_color(spec.accent), 0.16)
	focus.set_border_width_all(2)
	for type: StringName in [&"Button", &"CheckButton", &"OptionButton", &"HSlider"]:
		result.set_stylebox(&"focus", type, focus)
	for type: StringName in [&"Button", &"CheckButton"]:
		result.set_color(&"font_color", type, _color(spec.text))
		result.set_color(&"font_hover_color", type, _color(spec.text))
		result.set_color(&"font_pressed_color", type, _color(spec.text))
		result.set_color(&"font_hover_pressed_color", type, _color(spec.text))
		result.set_color(&"font_focus_color", type, _color(spec.focus_text))
	# Boutons désactivés (et avion déjà pris en duel) : fond de carte et texte estompé.
	var disabled := _frame(spec, spec.card, spec.line, 8)
	var faded := Color(_color(spec.muted), 0.55)
	for type: StringName in [&"Button", UNAVAILABLE_BUTTON]:
		result.set_stylebox(&"disabled", type, disabled)
		result.set_color(&"font_disabled_color", type, faded)
	result.set_color(&"font_color", PRIMARY_BUTTON, _color(spec.accent))
	result.set_stylebox(&"normal", PRIMARY_BUTTON, _frame(spec, spec.primary, spec.primary_line, 8))
	result.set_color(&"font_color", &"LinkButton", _color(spec.accent))
	result.set_color(&"font_hover_color", &"LinkButton", _color(spec.focus_text))
	result.set_color(&"font_color", &"Label", _color(spec.text))

	for key: String in spec.hud:
		result.set_color(StringName(key), HUD_TYPE, _color(spec.hud[key]))
	var font := _font(spec.font, spec.get("weight", 0))
	if font:
		result.default_font = font
		result.set_font(&"font", HUD_TYPE, font)
	if spec.get("godot_arrows", false):
		result.set_font(&"arrow_font", TYPE, ThemeDB.fallback_font)


static func _color(value: Variant) -> Color:
	return Color(value[0], value[1], value[2], value[3]) if value is Array else Color(value)


static func _frame(spec: Dictionary, color: String, border: String, margin: int) -> StyleBoxFlat:
	var result := box(_color(color), _color(border), margin, spec.radius)
	result.set_border_width_all(spec.border)
	return result


## Police du projet, importée par l'éditeur ou lue directement ; weight règle une police variable.
static func _font(path: String, weight: int = 0) -> Font:
	var key := "%s@%d" % [path, weight]
	if _fonts.has(key):
		return _fonts[key]
	var font: Font
	if ResourceLoader.exists(path):
		font = load(path) as Font
	if font == null and FileAccess.file_exists(path):
		var file := FontFile.new()
		if file.load_dynamic_font(ProjectSettings.globalize_path(path)) == OK:
			font = file
	# Symboles absents de certaines polices (◀ ▶, flèches des touches) : pris dans celle de Godot.
	if font is FontFile and not ThemeDB.fallback_font in font.fallbacks:
		font.fallbacks = [ThemeDB.fallback_font]
	if font and weight > 0:
		var variation := FontVariation.new()
		variation.base_font = font
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		font = variation
	_fonts[key] = font
	return font


## Estuaire : le thème d'origine du menu, bleu nuit et vert d'eau.
static func build_estuary() -> Theme:
	var ink := Color("#071c27")
	var line := Color("#284651")
	var text := Color("#e8f3ed")
	var accent := Color("#a8ecc9")
	var result := Theme.new()
	result.default_font_size = 16

	# Palette.
	result.set_color(&"ink", TYPE, ink)
	result.set_color(&"line", TYPE, line)
	result.set_color(&"text", TYPE, text)
	result.set_color(&"accent", TYPE, accent)
	result.set_color(&"muted", TYPE, Color("#a7bbc0"))
	# Score qui vient d'entrer au classement, avertissement de manette perdue.
	result.set_color(&"highlight", TYPE, Color("#ff9a3c"))
	# Teinte du logo FLUVIAL STRIKE (image blanche) : blanc, il garde ses couleurs d'origine.
	result.set_color(&"logo", TYPE, Color.WHITE)
	# Voile posé sur le jeu derrière les pages du menu.
	result.set_color(&"shade", TYPE, Color(0.023, 0.072, 0.10, 0.62))
	# Jauge de carburant de l'aide (segments pleins et vides).
	result.set_color(&"gauge_full", TYPE, Color("#a8ecc9"))
	result.set_color(&"gauge_empty", TYPE, Color("#1d3a45"))
	# Studio du hangar : fond, lumière ambiante et lumière de contour.
	result.set_color(&"hangar_background", TYPE, Color("#123345"))
	result.set_color(&"hangar_ambient", TYPE, Color("#cee0e5"))
	result.set_color(&"hangar_rim", TYPE, Color("#99cee0"))
	# Pastilles de touches et de boutons de manette.
	result.set_color(&"glyph_ink", TYPE, Color("#071c27"))
	result.set_color(&"glyph_cap", TYPE, Color("#d5e3e0"))

	# Cadres.
	result.set_stylebox(&"page", TYPE, box(ink, line, 22, 8))
	result.set_stylebox(&"page_settings", TYPE, box(ink, line, 12, 8))
	result.set_stylebox(&"card", TYPE, box(Color("#0c2531"), line, 12, 8))
	result.set_stylebox(&"note", TYPE, box(Color("#0c2531"), line, 10, 6))
	result.set_stylebox(&"strip", TYPE, box(ink, line, 8, 4))
	result.set_stylebox(&"slot_free", TYPE, box(Color("#0b2230"), line, 12, 8))
	result.set_stylebox(&"slot_taken", TYPE, box(Color("#102b37"), accent, 12, 8))
	result.set_stylebox(&"tile", TYPE, box(Color("#102b37"), line, 8, 5))
	result.set_stylebox(&"tile_active", TYPE, box(Color("#102b37"), accent, 8, 5))
	# Cadre du portrait de « À propos » : ouvert à droite, où le dégradé rejoint la page.
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = line
	frame.border_width_left = 1
	frame.border_width_top = 1
	frame.border_width_bottom = 1
	frame.set_corner_radius_all(4)
	result.set_stylebox(&"portrait_frame", TYPE, frame)

	# Boutons.
	result.set_color(&"font_color", &"Button", text)
	result.set_color(&"font_color", &"CheckButton", text)
	result.set_stylebox(&"normal", &"Button", box(Color("#102b37"), line, 8, 4))
	result.set_stylebox(&"hover", &"Button", box(Color("#183b48"), Color("#588692"), 8, 4))
	result.set_stylebox(&"pressed", &"Button", box(Color("#204b51"), accent, 8, 4))
	var focus := box(Color(accent, 0.16), accent, 8, 4)
	focus.set_border_width_all(2)
	for type: StringName in [&"Button", &"CheckButton", &"OptionButton", &"HSlider"]:
		result.set_stylebox(&"focus", type, focus)
	result.set_color(&"font_focus_color", &"Button", Color.WHITE)
	result.set_color(&"font_focus_color", &"CheckButton", Color.WHITE)
	result.set_color(&"font_focus_color", &"OptionButton", Color.WHITE)

	result.set_type_variation(PRIMARY_BUTTON, &"Button")
	result.set_color(&"font_color", PRIMARY_BUTTON, accent)
	result.set_stylebox(&"normal", PRIMARY_BUTTON, box(Color("#174036"), Color("#568d75"), 8, 4))

	result.set_type_variation(UNAVAILABLE_BUTTON, &"Button")
	result.set_color(&"font_disabled_color", UNAVAILABLE_BUTTON, Color("#809095"))
	result.set_stylebox(&"disabled", UNAVAILABLE_BUTTON, box(Color("#263238"), Color("#38464d"), 8, 4))

	# Lien vers le dépôt dans « À propos ».
	result.set_color(&"font_color", &"LinkButton", accent)
	result.set_color(&"font_hover_color", &"LinkButton", Color.WHITE)

	# Tableau de bord en vol.
	result.set_color(&"background", HUD_TYPE, Color("#071e2c"))
	result.set_color(&"top_line", HUD_TYPE, Color("#317587"))
	result.set_color(&"divider", HUD_TYPE, Color("#688896"))
	result.set_color(&"text", HUD_TYPE, Color("#e8f3ed"))
	result.set_color(&"muted", HUD_TYPE, Color("#aac5d0"))
	result.set_color(&"accent", HUD_TYPE, Color("#a8ecc9"))
	result.set_color(&"warning", HUD_TYPE, Color("#ffbf67"))
	result.set_color(&"refuel", HUD_TYPE, Color("#94eaf4"))
	result.set_color(&"gauge_track", HUD_TYPE, Color("#365764"))
	result.set_color(&"horizon_ground", HUD_TYPE, Color("#655f51"))
	result.set_color(&"horizon_sky", HUD_TYPE, Color("#447a9c"))
	result.set_color(&"overlay", HUD_TYPE, Color("#071e2c"))
	result.set_color(&"banner", HUD_TYPE, Color(0.03, 0.11, 0.16, 0.92))
	return result


## Cadre plein à bordure fine : fond, bordure, marge intérieure et arrondi.
static func box(color: Color, border: Color, margin: int, radius: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_content_margin(side, margin)
	return result
