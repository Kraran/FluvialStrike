extends SceneTree

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const SETTINGS = preload("res://flight_settings.gd")
const SCENE = preload("res://main.tscn")
const EXPECTED_SCORE_EVENTS := [
	[10, "tanker", 30], [187, "helicopter", 90], [261, "tanker", 120],
	[466, "tanker", 150], [487, "bridge", 650], [590, "helicopter", 710],
	[663, "fuel", 790], [683, "tanker", 820], [729, "fuel", 900], [749, "tanker", 930],
]

var failures := 0


func _initialize() -> void:
	_verify_reference()
	_verify_pilot_and_fuel()
	_verify_respawn(435, false)
	_verify_respawn(487, true)
	_verify_game_over()
	_verify_full_raid()
	_verify_settings()
	print("Fluvial Strike — %d échec(s)" % failures)
	quit(int(failures > 0))


func _verify_reference() -> void:
	var view = SCENE.instantiate()
	var start_replay := InputEventKey.new()
	start_replay.physical_keycode = KEY_F5
	start_replay.pressed = true
	view._unhandled_key_input(start_replay)
	for frame in range(1, 810):
		view._physics_process(1.0 / 60.0)

	var flight = view.flight
	_check([flight.tick, flight.x, flight.distance, flight.section, flight.score, flight.reserves, flight.fuel]
		== [809, 56, 1546, 2, 930, 3, 50847], "état final du rejeu F5")
	_check(flight.status == FLIGHT.Status.COMPLETE, "premier îlot franchi")
	var score_events: Array = []
	for event in flight.events:
		if FLIGHT.POINTS.has(event.kind):
			score_events.append([event.tick, event.kind, event.score])
	_check(score_events == EXPECTED_SCORE_EVENTS, "chronologie des points du rejeu F5")
	_check(view.settings.record == 0, "un rejeu ne modifie pas le record local")
	print("Rejeu F5 : ", flight.tick, " images, ", flight.score, " points, ", flight.fuel, " unités de carburant")
	view.free()


func _verify_pilot_and_fuel() -> void:
	var flight := FLIGHT.new()
	for direction in [FLIGHT.LEFT, FLIGHT.RIGHT]:
		flight.reset()
		var sign_x := -1 if direction == FLIGHT.LEFT else 1
		flight.advance(direction)
		_check(flight.x == 76 + sign_x, "premier pas latéral")
		for i in range(11):
			flight.advance(direction)
		_check(flight.x == 76 + 3 * sign_x, "rampe latérale")
		flight.advance(0)
		_check(flight.x == 76 + 3 * sign_x, "relâchement latéral")
		flight.reset()
		for i in range(12):
			flight.advance(direction)
		flight.advance(FLIGHT.RIGHT if direction == FLIGHT.LEFT else FLIGHT.LEFT)
		_check(flight.x == (74 if direction == FLIGHT.LEFT else 79), "inversion latérale")

	for sample in [[FLIGHT.SLOW, 20], [0, 11], [FLIGHT.FAST, 8]]:
		flight.reset()
		var gains := 0
		for frame in range(1, 360):
			var old_fuel := flight.fuel
			var controls: int = sample[0]
			if frame == 1:
				controls |= FLIGHT.FIRE
			flight.advance(controls)
			if flight.status != FLIGHT.Status.FLYING:
				break
			if flight.fuel > old_fuel:
				gains += 1
			elif gains > 0:
				break
		_check(gains == sample[1], "images de ravitaillement (entrée %d, mesuré %d)" % [sample[0], gains])

	flight.reset()
	for i in range(29):
		flight.advance(FLIGHT.RIGHT)
	_check(flight.status == FLIGHT.Status.FLYING and flight.x == 90, "trajectoire limite à l’image 29")
	flight.advance(FLIGHT.RIGHT)
	_check(flight.crash_cause == "bank", "collision de berge à l’image 30")

	flight.reset()
	flight.fuel = 31
	flight.advance(0)
	_check(flight.crash_cause == "fuel", "panne sèche")

	flight.reset()
	flight.score = 9970
	for i in range(10):
		flight.advance(FLIGHT.FIRE)
	_check(flight.score == 10000 and flight.reserves == 4, "réserve au seuil de 10 000 points")


func _verify_respawn(cut_fire: int, destroy_bridge: bool) -> void:
	var flight := FLIGHT.new()
	for frame in range(1, 650):
		var controls := FLIGHT.FAST
		if frame <= cut_fire:
			controls |= FLIGHT.FIRE
		elif destroy_bridge:
			controls |= FLIGHT.RIGHT
		flight.advance(controls)
		if flight.status == FLIGHT.Status.CRASHED:
			break
	_check(flight.status == FLIGHT.Status.CRASHED, "crash avant la reprise")
	_check(flight.bridge_destroyed == destroy_bridge, "état du pont avant la reprise")
	var crash_score := flight.score
	for i in range(FLIGHT.RESPAWN_TICKS - 1):
		flight.advance(0)
	_check(flight.status == FLIGHT.Status.CRASHED, "dernière image du délai de reprise")
	flight.advance(0)
	_check(flight.status == FLIGHT.Status.FLYING and flight.section == (2 if destroy_bridge else 1)
		and flight.score == crash_score and flight.reserves == 2 and flight.fuel == FLIGHT.FULL_TANK,
		"section, score, réserves et carburant après la reprise")


func _verify_game_over() -> void:
	var flight := FLIGHT.new()
	for i in range(744):
		flight.advance(FLIGHT.RIGHT)
	_check(flight.status == FLIGHT.Status.CRASHED and flight.reserves == 0,
		"dernière image avant la fin de partie")
	flight.advance(FLIGHT.RIGHT)
	_check(flight.status == FLIGHT.Status.GAME_OVER and flight.tick == 745, "fin de partie")


func _verify_full_raid() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://raid_replay.json"))
	if not fixture is Dictionary or not fixture.has("rle"):
		_check(false, "commandes du raid complet introuvables")
		return

	var flight := FLIGHT.new()
	for frame in range(1, 810):
		flight.advance(FLIGHT.reference_controls(frame))
	_check(flight.status == FLIGHT.Status.FLYING and flight.distance == COURSE.REFERENCE_END,
		"le pilotage manuel peut dépasser le premier îlot")

	var late_checkpoint_checked := false
	for segment: Array in fixture.rle:
		var controls := int(segment[0])
		for i in int(segment[1]):
			flight.advance(controls)
			if not late_checkpoint_checked and flight.section == 6:
				late_checkpoint_checked = true
				_verify_late_checkpoint(flight)

	var bridges := flight.events.filter(func(event: Dictionary) -> bool: return event.kind == "bridge")
	_check(late_checkpoint_checked, "reprise vérifiée après le cinquième pont")
	_check(bridges.size() == COURSE.BRIDGES.size(), "les neuf ponts sont détruits une seule fois")
	_check(flight.status == FLIGHT.Status.COMPLETE and flight.tick == 8541 and flight.distance == COURSE.END
		and flight.reserves == 3 and flight.section == 10 and flight.fuel == 62175,
		"arrivée du raid sans crash")
	print("Raid complet : ", flight.tick, " images, ", bridges.size(), " ponts, ", flight.score,
		" points, ", flight.fuel, " unités de carburant")


func _verify_late_checkpoint(flight: FLIGHT) -> void:
	var branch := FLIGHT.new()
	for key in ["tick", "x", "distance", "speed", "fuel", "score", "reserves", "section"]:
		branch.set(key, flight.get(key))
	branch.fuel = 0
	branch.advance(0)
	_check(branch.status == FLIGHT.Status.CRASHED, "perte du jet après le cinquième pont")
	for i in FLIGHT.RESPAWN_TICKS:
		branch.advance(0)
	_check(branch.status == FLIGHT.Status.FLYING and branch.section == 6
		and branch.distance == COURSE.BRIDGES[4].y + 8 and branch.score == flight.score
		and branch.reserves == flight.reserves - 1, "reprise au dernier pont détruit")


func _verify_settings() -> void:
	var path := "res://.fluvial_qa_%d.cfg" % OS.get_process_id()
	var settings := SETTINGS.new(path)
	_check(settings.bind(0, KEY_RIGHT, false) and settings.keyboard[1] == KEY_LEFT,
		"permutation de deux raccourcis clavier")
	_check(not settings.bind(0, KEY_ESCAPE, false) and not settings.bind(4, JOY_BUTTON_START, true),
		"les commandes de pause restent disponibles")
	_check(settings.bind(4, JOY_BUTTON_X, true), "affectation manette")
	settings.volume = 35
	settings.quality_hd = false
	settings.vsync = false
	settings.fullscreen = true
	settings.muted = true
	_check(settings.update_record(1200) and settings.save() == OK, "première sauvegarde locale")

	var restored := SETTINGS.new(path)
	restored.load_file()
	_check(restored.keyboard == settings.keyboard and restored.gamepad == settings.gamepad
		and restored.volume == 35 and not restored.quality_hd and not restored.vsync
		and restored.fullscreen and restored.muted and restored.record == 1200,
		"relecture des réglages et du record")
	restored.apply_bindings()
	Input.action_press(&"flight_fire")
	_check(restored.controls() & FLIGHT.FIRE != 0, "commande de tir issue de la table d’entrées")
	Input.action_release(&"flight_fire")

	var view = SCENE.instantiate()
	view.settings = restored
	view._start(view.Mode.MANUAL)
	view.flight.status = FLIGHT.Status.CRASHED
	view.flight.crash_ticks = 1
	view.flight.reserves = 0
	view.flight.score = 1300
	view._physics_process(1.0 / 60.0)
	var updated := SETTINGS.new(path)
	updated.load_file()
	_check(view.flight.status == FLIGHT.Status.GAME_OVER and updated.record == 1300,
		"le record d’un vol manuel est sauvegardé")
	_check(not updated.update_record(1000), "un score inférieur ne remplace pas le record")
	view.free()
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
