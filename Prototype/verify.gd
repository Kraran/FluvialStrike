extends SceneTree

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const SETTINGS = preload("res://flight_settings.gd")
const RAID_REPLAY = preload("res://raid_replay.gd")
const MUSIC = preload("res://music.gd")
const PACING = preload("res://frame_pacing.gd")
const SCENE = preload("res://main.tscn")
const EXPECTED_SCORE_EVENTS := [
	[10, "tanker", 30], [187, "helicopter", 90], [261, "tanker", 120],
	[466, "tanker", 150], [487, "bridge", 650], [590, "helicopter", 710],
	[663, "fuel", 790], [683, "tanker", 820], [729, "fuel", 900], [749, "tanker", 930],
]

var failures := 0


func _initialize() -> void:
	_verify_reference()
	_verify_replay_controls()
	_verify_bridge_results()
	_verify_shot_alignment()
	_verify_replay_hit_rules()
	_verify_difficulty()
	_verify_music()
	_verify_expert_leaderboard()
	_verify_ghost()
	_verify_pilot_and_fuel()
	_verify_respawn(435, false)
	_verify_respawn(487, true)
	_verify_game_over()
	_verify_extra_lives()
	_verify_full_raid()
	_verify_continuation()
	_verify_cheats()
	_verify_settings()
	_verify_score_reset()
	_verify_leaderboard()
	_verify_localization()
	_verify_presentation()
	_verify_aircraft_model()
	_verify_scenery()
	print("Fluvial Strike — %d échec(s)" % failures)
	quit(int(failures > 0))


func _verify_reference() -> void:
	var view = SCENE.instantiate()
	var start_replay := InputEventKey.new()
	start_replay.physical_keycode = KEY_F5
	start_replay.pressed = true
	view._unhandled_key_input(start_replay)
	for frame in range(1, 810):
		view._process(1.0 / 60.0)

	var flight = view.flight
	_check([flight.tick, flight.x, flight.distance, flight.section, flight.score, flight.reserves, flight.fuel]
		== [809, 56, 1546, 2, 930, 3, 50847], "état final du replay F5")
	_check(flight.status == FLIGHT.Status.COMPLETE, "premier îlot franchi")
	var score_events: Array = []
	for event in flight.events:
		if FLIGHT.POINTS.has(event.kind):
			score_events.append([event.tick, event.kind, event.score])
	_check(score_events == EXPECTED_SCORE_EVENTS, "chronologie des points du replay F5")
	_check(view.settings.record == 0, "un replay ne modifie pas le record local")
	print("Replay F5 : ", flight.tick, " images, ", flight.score, " points, ", flight.fuel, " unités de carburant")
	view.free()


func _verify_replay_controls() -> void:
	var view = SCENE.instantiate()
	var baseline := FLIGHT.new()
	baseline.finish_distance = COURSE.REFERENCE_END
	var results: Array[Vector2] = []
	for refresh in [60, 75, 120, 144]:
		view._start(view.Mode.REFERENCE)
		Input.action_press(&"replay_faster", 0.5)
		view._process(1.0 / refresh)
		_check(view._replay_speed > 1.0 and view._replay_speed < 2.0, "accélération progressive")
		for frame in range(1, refresh):
			view._process(1.0 / refresh)
		results.append(Vector2(view.flight.tick + view._replay_fraction, view._replay_speed))
		Input.action_release(&"replay_faster")
		Input.action_press(&"replay_slower")
		for frame in refresh:
			view._process(1.0 / refresh)
		_check(view._replay_speed > 0.25 and view._replay_speed < 0.27, "ralenti progressif")
		Input.action_release(&"replay_slower")
		for frame in refresh:
			view._process(1.0 / refresh)
		_check(view._replay_speed > 0.99 and view._replay_speed < 1.0, "retour progressif à 1×")
	for result in results:
		_check(result.is_equal_approx(results[0]), "lecture régulière quelle que soit la fréquence")

	view._start(view.Mode.REFERENCE)
	view._request_bridge(-1)
	_check(view._replay_seek_target == -1, "le premier pont n’a pas de précédent")
	view._request_bridge(1)
	view._process(1.0 / 60.0)
	_check(view.flight.tick == 367, "avance à l’approche du premier pont")
	while view.flight.status < FLIGHT.Status.GAME_OVER:
		view._process(1.0 / 60.0)
	view._request_bridge(-1)
	view._process(1.0 / 60.0)
	for i in 367:
		baseline.advance(FLIGHT.reference_controls(i + 1))
	_check([view.flight.tick, view.flight.x, view.flight.distance, view.flight.fuel, view.flight.events] ==
		[baseline.tick, baseline.x, baseline.distance, baseline.fuel, baseline.events],
		"le retour après la fin restitue exactement la trajectoire")
	view.free()


func _verify_bridge_results() -> void:
	var flight := FLIGHT.new()
	var inputs := PackedByteArray()
	for frame in range(1, 810):
		var controls := FLIGHT.reference_controls(frame)
		inputs.append(controls)
		flight.advance(controls)
	var raid := RAID_REPLAY.new()
	raid.capture(flight, inputs, "f22")
	_check(raid.bridge_ticks == PackedInt32Array([487]) and raid.bridge_stats.size() == 3,
		"bilan du premier pont enregistré")
	_check(raid.bridge_stats[0] == 650 and raid.bridge_stats[1] > 0 and raid.bridge_stats[2] == 0,
		"points, carburant et pertes du premier passage")

	var config := ConfigFile.new()
	raid.write(config, RAID_REPLAY.BEST_SECTION)
	var restored := RAID_REPLAY.new()
	_check(restored.read(config, RAID_REPLAY.BEST_SECTION) and restored.bridge_stats == raid.bridge_stats,
		"le bilan par pont survit à la sauvegarde")
	config.erase_section_key(RAID_REPLAY.BEST_SECTION, "bridge_stats")
	var old := RAID_REPLAY.new()
	_check(old.read(config, RAID_REPLAY.BEST_SECTION) and not old.prepare_bridge_stats(200)
		and not old.prepare_bridge_stats(200) and old.prepare_bridge_stats(200)
		and old.bridge_stats == raid.bridge_stats, "un ancien replay restitue le même bilan par étapes")


# Un tir dessiné sur un dépôt le détruit, même si le jet affiché est en retard sur sa
# position logique pendant un déplacement vers la droite.
func _verify_shot_alignment() -> void:
	var depot := -1
	for i in 200:
		if COURSE.target(i)[0] == "fuel":
			depot = i
			break
	var center: Vector2 = FLIGHT.new().target_position(depot)
	var mismatches := 0
	var legacy_misses := 0
	for x in range(int(center.x) - 10, int(center.x) + 4):
		for lag in [0.0, -0.25, -0.5, -0.75, -0.95]:
			var drawn: float = x + 4 + lag
			var expected := absf(drawn - center.x) <= FLIGHT.TARGET_SIZE["fuel"].x
			for legacy in [false, true]:
				var flight := FLIGHT.new()
				flight.legacy_shot_hitbox = legacy
				flight.x = x
				flight.distance = int(center.y) - 40
				flight.set("_visual_lateral_x", x + lag)
				flight.shot_active = true
				flight.shot_x = x + FLIGHT.NATIVE_SHOT_X_OFFSET
				flight.shot_distance = int(center.y) - 14
				flight.call("_shoot", 0, 0, 0)
				flight.call("_shoot", 0, 0, 0)
				if not legacy and flight.target_gone(depot) != expected:
					mismatches += 1
				elif legacy and expected and not flight.target_gone(depot):
					legacy_misses += 1
	_check(mismatches == 0, "un tir touche un dépôt exactement là où il est dessiné (%d écart(s))" % mismatches)
	_check(legacy_misses > 0, "l’ancienne règle laissait passer des tirs dessinés sur le dépôt")


func _verify_replay_hit_rules() -> void:
	var flight := FLIGHT.new()
	var inputs := PackedByteArray()
	for frame in range(1, 200):
		inputs.append(FLIGHT.reference_controls(frame))
		flight.advance(inputs[-1])
	var raid := RAID_REPLAY.new()
	raid.capture(flight, inputs, "f22")
	var config := ConfigFile.new()
	raid.write(config, RAID_REPLAY.LAST_SECTION)
	var restored := RAID_REPLAY.new()
	_check(config.get_value(RAID_REPLAY.LAST_SECTION, "format") == RAID_REPLAY.FORMAT
		and restored.read(config, RAID_REPLAY.LAST_SECTION) and not restored.legacy_hits,
		"un nouveau replay suit la règle de touche actuelle")
	config.set_value(RAID_REPLAY.LAST_SECTION, "format", RAID_REPLAY.LEGACY_FORMAT)
	var old := RAID_REPLAY.new()
	_check(old.read(config, RAID_REPLAY.LAST_SECTION) and old.legacy_hits,
		"un replay au format 1 reste lisible et garde l’ancienne règle de touche")
	var rewritten := ConfigFile.new()
	old.write(rewritten, RAID_REPLAY.LAST_SECTION)
	_check(rewritten.get_value(RAID_REPLAY.LAST_SECTION, "format") == RAID_REPLAY.LEGACY_FORMAT,
		"un ancien replay réenregistré conserve son format")


func _verify_ghost() -> void:
	var flight := FLIGHT.new()
	var controls := PackedByteArray()
	var before := Vector3.ZERO
	var after := Vector3.ZERO
	for tick in range(1, 810):
		var bits := FLIGHT.reference_controls(tick)
		controls.append(bits)
		flight.advance(bits)
		var point := Vector3(flight.visual_distance(), flight.visual_x(), flight.visual_lateral_speed())
		if tick == 162:
			before = point
		elif tick == 163:
			after = point
	var raid := RAID_REPLAY.new()
	raid.capture(flight, controls, "f22")
	var distance := lerpf(before.x, after.x, 0.5)
	_check(not raid.ghost_pose(distance, 1).is_finite(), "le calcul du fantôme respecte le budget par image")
	var pose := raid.ghost_pose(distance, 256)
	_check(pose.is_equal_approx(Vector3(lerpf(before.y, after.y, 0.5), lerpf(before.z, after.z, 0.5), 1.0)),
		"la trajectoire et l’inclinaison sont interpolées à la distance affichée")
	_check(raid.ghost_pose(0.0, 0).is_equal_approx(Vector3(76.0, 0.0, 1.0)),
		"le fantôme reste disponible après un redémarrage de la partie")
	_check(not raid.ghost_pose(flight.visual_distance() + 1.0, 1024).is_finite(),
		"le fantôme disparaît au-delà de la distance enregistrée")
	_check(raid.inputs == controls and raid.score == flight.score and flight.tick == 809,
		"l’affichage du fantôme laisse le replay et la simulation intacts")


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
		for frame in range(1, 720):
			var old_fuel := flight.fuel
			var controls: int = sample[0]
			if frame == 1:
				controls |= FLIGHT.FIRE
			flight.advance(controls)
			if flight.status != FLIGHT.Status.FLYING:
				break
			if flight.fuel > old_fuel:
				_check(flight.over_fuel_barge, "gain de carburant dans la zone de contact")
				gains += 1
			elif gains > 0 and not flight.over_fuel_barge:
				break
		_check(not flight.over_fuel_barge, "sortie de la zone de ravitaillement")
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
	_check(flight.crash_cause == "fuel" and not flight.over_fuel_barge, "panne sèche hors ravitaillement")

	flight.reset()
	flight.x = 90
	flight.distance = 102
	flight.advance(0)
	_check(flight.over_fuel_barge and flight.fuel == FLIGHT.FULL_TANK, "contact avec une barge, réservoir plein")
	flight.reset()
	_check(not flight.over_fuel_barge, "effacement du contact au redémarrage")

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


# Un avion de réserve tous les 10 000 points, jamais plus de 9 en réserve à la fois.
func _verify_extra_lives() -> void:
	var flight := FLIGHT.new()
	var wrong := 0
	var gains := 0
	while flight.score < 200000:
		var before := flight.reserves
		var threshold := floori(flight.score / 10000.0)
		flight.call("_add_score", "jet")
		var crossed := floori(flight.score / 10000.0) - threshold
		gains += flight.reserves - before
		if flight.reserves != mini(9, before + crossed):
			wrong += 1
	_check(wrong == 0 and flight.reserves == 9 and gains == 6,
		"un avion tous les 10 000 points, plafonné à 9 en réserve (%d écart(s), %d gagnés)" % [wrong, gains])
	flight.reserves = 4
	var score_before := flight.score
	while floori(flight.score / 10000.0) == floori(score_before / 10000.0):
		flight.call("_add_score", "tanker")
	_check(flight.reserves == 5, "après des pertes, le palier suivant redonne un avion")
	flight.reserves = 9
	score_before = flight.score
	while floori(flight.score / 10000.0) == floori(score_before / 10000.0):
		flight.call("_add_score", "helicopter")
	_check(flight.reserves == 9, "à 9 en réserve, le palier suivant ne dépasse pas 9")


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
	if not fixture is Dictionary or not fixture.has("rle") or not fixture.has("continuation"):
		_check(false, "commandes du raid complet introuvables")
		return

	var flight := FLIGHT.new()
	# Raid enregistré avec l'ancienne règle de touche, comme les replays au format 1.
	flight.legacy_shot_hitbox = true
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
	_check(bridges.size() == COURSE.LEGACY_BRIDGES, "les neuf ponts sont détruits une seule fois")
	_check(flight.status == FLIGHT.Status.FLYING and flight.tick == 8541 and flight.distance == COURSE.LEGACY_END
		and flight.reserves == 3 and flight.section == 10 and flight.fuel == 62175,
		"poursuite du raid au-delà du neuvième pont")
	print("Neuf premiers ponts : ", flight.tick, " images, ", bridges.size(), " ponts, ", flight.score,
		" points, ", flight.fuel, " unités de carburant")
	for segment: Array in fixture.continuation:
		for frame in int(segment[1]):
			flight.advance(int(segment[0]))
	_check(flight.status == FLIGHT.Status.FLYING and flight.section == 11 and flight.distance == 10275
		and flight.tick == 9077 and flight.score == 8500 and flight.reserves == 3 and flight.fuel == 45023,
		"replay continu du départ au-delà du dixième pont")
	print("Dixième pont : ", flight.tick, " images, ", flight.score, " points, ", flight.fuel, " unités de carburant")


func _verify_continuation() -> void:
	_check(COURSE.water_spans(9497) == [16, 76, 84, 144], "début de l’îlot issu de la cartouche")
	_check(COURSE.water_spans(9515) == [16, 40, 120, 144], "largeur de l’îlot au raccord")
	for index in [9, 10, 47, 48, 1499, 1999]:
		var bridge := COURSE.bridge(index)
		var flight := FLIGHT.new()
		flight.section = index + 1
		flight._place_jet()
		flight.tick = 1
		flight.distance = bridge.x - 42
		flight.shot_distance = flight.distance
		flight.speed = FLIGHT.MAX_SPEED
		for frame in range(37):
			flight.advance(FLIGHT.FAST | FLIGHT.FIRE)
		_check(flight.status == FLIGHT.Status.FLYING and flight.distance == bridge.y + 8
			and flight.section == index + 2, "franchissement du pont %d" % (index + 1))
		flight._crash("bank")
		for frame in FLIGHT.RESPAWN_TICKS:
			flight.advance(0)
		_check(flight.status == FLIGHT.Status.FLYING and flight.distance == bridge.y + 8
			and flight.section == index + 2, "reprise après le pont %d" % (index + 1))
	var champion := FLIGHT.new()
	champion.score = COURSE.MAX_SCORE - 30
	champion._add_score("helicopter")
	_check(champion.score == COURSE.MAX_SCORE and champion.status == FLIGHT.Status.COMPLETE,
		"fin du raid au plafond du score de la cartouche")


func _verify_cheats() -> void:
	var flight := FLIGHT.new()
	flight.cheats = FLIGHT.Cheat.LIVES
	for loss in range(5):
		flight.fuel = 0
		flight.advance(0)
		_check(flight.status == FLIGHT.Status.CRASHED, "les vies infinies laissent le jet s’écraser")
		for frame in FLIGHT.RESPAWN_TICKS:
			flight.advance(0)
		_check(flight.status == FLIGHT.Status.FLYING and flight.reserves == FLIGHT.INITIAL_RESERVES,
			"reprise sans perte de réserve")
	flight.reset()
	flight.cheats = FLIGHT.Cheat.FUEL
	flight.fuel = 0
	for frame in range(90):
		flight.advance(FLIGHT.FAST | FLIGHT.FIRE)
		_check(flight.fuel == FLIGHT.FULL_TANK, "jauge pleine avec le carburant infini")
	flight.reset()
	flight.cheats = FLIGHT.Cheat.INVULNERABILITY
	flight.fuel = 0
	for frame in range(600):
		flight.advance(FLIGHT.FAST | FLIGHT.RIGHT)
	_check(flight.status == FLIGHT.Status.FLYING and flight.fuel == 0 and flight.x == 152,
		"l’avion indestructible reste pilotable à sec et au bord de l’écran")
	_check(flight.section == 2 and flight.score == 0 and not flight.is_bridge_destroyed(0),
		"un pont traversé intact permet de poursuivre sans marquer de points")
	flight.reset()
	_check(flight.cheats == 0 and not flight.is_bridge_destroyed(0), "les effets sont propres au vol")


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
		and branch.distance == COURSE.bridge(4).y + 8 and branch.score == flight.score
		and branch.reserves == flight.reserves - 1, "reprise au dernier pont détruit")


func _verify_settings() -> void:
	var path := "res://.fluvial_qa_%d.cfg" % OS.get_process_id()
	var settings := SETTINGS.new(path)
	_check(settings.ghost_source == SETTINGS.Ghost.OFF, "le fantôme est désactivé par défaut")
	_check(settings.bind(0, KEY_RIGHT, false) and settings.keyboard[1] == KEY_LEFT,
		"permutation de deux raccourcis clavier")
	_check(not settings.bind(0, KEY_ESCAPE, false) and not settings.bind(4, JOY_BUTTON_START, true),
		"les commandes de pause restent disponibles")
	_check(settings.bind(4, JOY_BUTTON_X, true), "affectation manette")
	settings.language = "es"
	settings.volume = 35
	settings.vibration = 40
	_check(settings.fullscreen and settings.panorama and not settings.quality_hd,
		"plein écran et décor panoramique activés, rendu HD désactivé par défaut")
	settings.quality_hd = true
	settings.sync_mode = PACING.Sync.ADAPTIVE
	settings.refresh_limit = 144
	_check(not settings.show_fps, "le compteur de FPS est désactivé par défaut")
	_check(settings.scanlines == SETTINGS.Scanlines.OFF, "les scanlines sont désactivées par défaut")
	settings.dynamic_resolution = false
	settings.show_fps = true
	settings.panorama = false
	settings.scanlines = SETTINGS.Scanlines.MEDIUM
	settings.fullscreen = false
	settings.muted = true
	settings.ghost_source = SETTINGS.Ghost.LAST
	_check(settings.update_record(1200) and settings.save() == OK, "première sauvegarde locale")

	var restored := SETTINGS.new(path)
	restored.load_file()
	_check(restored.keyboard == settings.keyboard and restored.gamepad == settings.gamepad
		and restored.language == "es" and restored.volume == 35 and restored.vibration == 40 and restored.quality_hd and restored.sync_mode == PACING.Sync.ADAPTIVE
		and restored.refresh_limit == 144 and not restored.dynamic_resolution and restored.show_fps and not restored.panorama
		and restored.scanlines == SETTINGS.Scanlines.MEDIUM
		and not restored.fullscreen and restored.muted and restored.ghost_source == SETTINGS.Ghost.LAST and restored.record == 1200
		and restored.furthest_section == 0 and restored.most_bridges == 0,
		"relecture des réglages et du record")
	restored.apply_bindings()
	for device in [0, 1, 3]:
		var accept := InputEventJoypadButton.new()
		accept.device = device
		accept.button_index = JOY_BUTTON_A
		accept.pressed = true
		_check(accept.is_action_pressed(&"ui_accept"),
			"validation A des menus avec plusieurs identifiants de manette")
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
	view.flight.section = 3
	view._physics_process(1.0 / 60.0)
	var updated := SETTINGS.new(path)
	updated.load_file()
	_check(view.flight.status == FLIGHT.Status.GAME_OVER and updated.record == 1300
		and updated.furthest_section == 3 and updated.most_bridges == 2,
		"les records d’un vol manuel sont sauvegardés")
	_check(updated.update_raid_records(800, 5) and updated.save() == OK
		and updated.record == 1300 and updated.furthest_section == 5 and updated.most_bridges == 4,
		"la progression peut battre un record indépendamment du score")
	view._start(view.Mode.MANUAL)
	view.flight.cheats = FLIGHT.Cheat.FUEL
	view.flight.status = FLIGHT.Status.CRASHED
	view.flight.crash_ticks = 1
	view.flight.reserves = 0
	view.flight.score = 5000
	view.flight.section = 12
	view._physics_process(1.0 / 60.0)
	updated.load_file()
	_check(updated.record == 1300 and updated.furthest_section == 5 and updated.most_bridges == 4,
		"un raid avec codes laisse les records locaux intacts")
	_check(updated.best_raid != null and updated.best_raid.score == 1300
		and updated.best_raid.inputs.size() == 1,
		"le replay est conservé avec le meilleur score et survit à un raid avec codes")
	_check(updated.last_raid != null and updated.last_raid.score == 5000
		and updated.last_raid.cheats == FLIGHT.Cheat.FUEL and updated.last_raid.inputs.size() == 1,
		"le dernier raid avec codes survit au rechargement indépendamment du meilleur")
	_check(not updated.update_record(1000), "un score inférieur ne remplace pas le record")
	_check(updated.ghost_raid() == updated.last_raid, "le dernier raid avec codes peut servir de fantôme")
	updated.ghost_source = SETTINGS.Ghost.BEST
	_check(updated.ghost_raid() == updated.best_raid, "le meilleur raid peut servir de fantôme")
	updated.ghost_source = SETTINGS.Ghost.OFF
	_check(updated.ghost_raid() == null, "l’option désactivée ne choisit aucun fantôme")
	var legacy := ConfigFile.new()
	_check(legacy.load(path) == OK, "lecture du réglage pour le test de migration")
	legacy.erase_section_key("player", "ghost_source")
	legacy.set_value("player", "ghost", true)
	_check(legacy.save(path) == OK, "préparation d’un ancien réglage fantôme")
	updated.load_file()
	_check(updated.ghost_source == SETTINGS.Ghost.BEST, "un fantôme actif dans une ancienne version garde le meilleur raid")
	view.free()
	DirAccess.remove_absolute(path)


func _verify_score_reset() -> void:
	var path := "res://.fluvial_qa_reset_%d.cfg" % OS.get_process_id()
	var settings := SETTINGS.new(path)
	var flight := FLIGHT.new()
	flight.advance(0)
	flight.score = 650
	flight.section = 2
	settings.record_completed_raid(flight, PackedByteArray([0]))
	flight.score = 150
	settings.record_completed_raid(flight, PackedByteArray([0]))
	_check(settings.save() == OK, "sauvegarde avant effacement")
	var stale := SETTINGS.new(path)
	stale.load_file()
	var blocked := SETTINGS.new(path)
	blocked.load_file()
	blocked.file_path = path.path_join("blocked.cfg")
	_check(blocked.clear_high_score() != OK and blocked.record == 650 and blocked.best_raid != null,
		"un effacement impossible conserve les données en mémoire")
	_check(settings.clear_high_score() == OK and settings.record == 0 and settings.best_raid == null,
		"effacement du meilleur score et de son replay")
	_check(stale.save() == OK and stale.record == 0 and stale.best_raid == null,
		"une session avec un ancien score ne le rétablit pas")
	var config := ConfigFile.new()
	_check(config.load(path) == OK and not config.has_section(RAID_REPLAY.BEST_SECTION),
		"le fichier de sauvegarde ne contient plus le replay du meilleur score")
	var restored := SETTINGS.new(path)
	restored.load_file()
	_check(restored.record == 0 and restored.best_raid == null and restored.last_raid != null
		and restored.last_raid.score == 150 and restored.furthest_section == 2 and restored.most_bridges == 1,
		"le dernier raid et la progression restent disponibles après effacement")
	restored.record_completed_raid(flight, PackedByteArray([0]))
	_check(restored.save() == OK and restored.record == 150 and restored.best_raid != null,
		"un nouveau record peut être établi après effacement")
	DirAccess.remove_absolute(path)


func _verify_leaderboard() -> void:
	var path := "res://.fluvial_qa_scores_%d.cfg" % OS.get_process_id()
	var config := ConfigFile.new()
	config.set_value("record", "score", 2300)
	_check(config.save(path) == OK, "sauvegarde de l’ancien record pour la migration")
	var settings := SETTINGS.new(path)
	_check(settings.scores == SETTINGS.DEFAULT_SCORES, "les quatre scores sont présents dès le premier lancement")
	settings.load_file()
	_check(settings.scores.slice(0, 4) == SETTINGS.DEFAULT_SCORES
		and settings.scores[-1] == {"initials": "---", "score": 2300},
		"import de l’ancien record avec les scores de départ")
	config.set_value("leaderboard", "entries", [{"initials": "OLD", "score": 3000}])
	_check(config.save(path) == OK, "préparation d’un classement existant")
	settings.load_file()
	_check(settings.scores == [{"initials": "OLD", "score": 3000}], "un classement déjà rempli est conservé")
	for i in range(1, 20):
		_check(settings.submit_score("ABC", 15000 + i * 1000) == OK, "inscription d’un score admissible")
	_check(settings.scores.size() == 15 and settings.scores[0].score == 34000 and settings.scores[-1].score == 20000,
		"les quinze meilleurs scores sont conservés dans l’ordre")
	_check(settings.submit_score("BCD", 34000) == OK and settings.scores[0].initials == "ABC"
		and settings.scores[1].initials == "BCD", "les scores à égalité gardent leur ordre d’inscription")
	_check(settings.submit_score("A12", 2200) == ERR_INVALID_PARAMETER
		and settings.submit_score("XYZ", settings.scores[-1].score) == ERR_UNAVAILABLE,
		"seuls les scores admissibles et trois lettres sont acceptés")
	var restored := SETTINGS.new(path)
	restored.load_file()
	_check(restored.scores == settings.scores, "le classement complet survit au rechargement")
	_check(settings.clear_high_score() == OK and restored.save() == OK
		and restored.scores == SETTINGS.DEFAULT_SCORES and restored.record == 0,
		"les scores de départ persistent après la réinitialisation et la sauvegarde d’une session plus ancienne")
	DirAccess.remove_absolute(path)


func _verify_localization() -> void:
	_check(SETTINGS.new().language == "en", "anglais par défaut")
	var previous := TranslationServer.get_locale()
	var english := load("res://i18n/en.po") as Translation
	var keys := english.get_message_list()
	for code in SETTINGS.LANGUAGES:
		var catalog := load("res://i18n/%s.po" % code) as Translation
		_check(catalog != null and catalog.get_message_count() == keys.size(), "catalogue chargé pour %s" % code)
		if catalog == null:
			continue
		TranslationServer.set_locale(code)
		for key in keys:
			var translated := catalog.get_message(key)
			_check(not translated.is_empty() and TranslationServer.translate(key) == translated,
				"traduction active pour %s / %s" % [code, key])
	TranslationServer.set_locale(previous)


func _verify_presentation() -> void:
	var flight := FLIGHT.new()
	flight.advance(FLIGHT.SLOW | FLIGHT.FIRE)
	for i in range(8):
		var before := flight.visual_distance()
		flight.advance(FLIGHT.SLOW)
		_check(is_equal_approx(flight.visual_distance() - before, 0.5),
			"défilement continu à demi-ligne par pas")
	for direction in [FLIGHT.LEFT, FLIGHT.RIGHT]:
		flight.reset()
		var sign_x := -1.0 if direction == FLIGHT.LEFT else 1.0
		var start_x := flight.visual_x()
		flight._move(direction)
		_check(is_equal_approx(flight.visual_x() - start_x, sign_x / 32.0),
			"démarrage latéral progressif dans les deux sens")
		_check(absf(flight.visual_lateral_speed()) < 0.04,
			"inclinaison initiale proportionnelle à la vitesse latérale")
		for i in range(11):
			flight._move(direction)
		var release_x := flight.visual_x()
		var native_x := flight.x
		flight._move(0)
		_check((flight.visual_x() - release_x) * sign_x >= 0.0
			and absf(flight.visual_x() - release_x) < 0.25,
			"relâchement sans recul et sans saut latéral")
		for i in range(30):
			flight._move(0)
		_check(flight.x == native_x and absf(flight.visual_x() - native_x) < 0.001,
			"position affichée stabilisée sur la position de collision")
	for pattern in [[0, FLIGHT.RIGHT], [0, FLIGHT.LEFT], [0, FLIGHT.RIGHT, FLIGHT.LEFT, FLIGHT.RIGHT, 0]]:
		flight.reset()
		for i in range(1000):
			var direction: int = pattern[i % pattern.size()]
			var before_x := flight.visual_x()
			flight._move(direction)
			var sign_x := int(bool(direction & FLIGHT.RIGHT)) - int(bool(direction & FLIGHT.LEFT))
			_check((flight.visual_x() - before_x) * sign_x >= -0.0001
				and absf(flight.visual_x() - flight.x) < 2.0,
				"appuis courts et inversions sans mouvement opposé ni dérive visuelle")
	var pacing := PACING.new()
	for rate in [60, 75, 120, 144]:
		pacing.configure(rate, rate, PACING.Sync.SCREEN, true, true)
		_check(pacing.cap == 0 and pacing.target == rate, "cadence native sans double limiteur")
		pacing.configure(rate, rate, PACING.Sync.ADAPTIVE, true, true)
		_check(pacing.cap == rate - (3 if rate >= 100 else 2), "marge VRR")
	pacing.configure(60, 60, PACING.Sync.SCREEN, true, true)
	for i in range(150):
		pacing.observe(11.0 if i % 2 == 0 else 1000.0 / 30.0 - 11.0, 5.0)
	_check(pacing.width == PACING.WIDTHS[-1] and pacing.antialias,
		"cadence moyenne stable malgré l’alternance des temps d’image")
	pacing.configure(144, 144, PACING.Sync.OFF, true, true)
	var initial := pacing.width
	for i in range(140):
		pacing.observe(12.0, 10.0)
	_check(pacing.width < initial, "baisse de résolution sous charge")
	for i in range(1300):
		pacing.observe(1000.0 / 144.0, 2.0)
	_check(pacing.width > initial and pacing.width <= PACING.WIDTHS[-1],
		"remontée de résolution avec marge GPU")


func _verify_aircraft_model() -> void:
	var models = load("res://flight_models.gd").new()
	var jet: Node3D = models.aircraft()
	var bounds := AABB()
	for part: MeshInstance3D in jet.get_children():
		bounds = bounds.merge(part.get_aabb())
		_check(part.mesh.surface_get_array_index_len(0) > 0,
			"géométrie indexée avant regroupement des matériaux")
	_check(jet.get_child_count() == 8, "huit groupes de matériau pour le StratoWing")
	_check(bounds.position.z < -2.1 and bounds.end.z > 1.8,
		"fuselage et tuyère conservés dans le modèle regroupé")
	_check(bounds.size.x > 4.8 and bounds.size.x < 4.9 and bounds.end.y > 1.1,
		"envergure et dérive du StratoWing")
	jet.free()


func _verify_scenery() -> void:
	var scenery = load("res://scenery.gd").new()
	scenery.build_shore_map()
	_check(scenery.shore_image.get_width() == 153 and scenery.shore_image.get_height() == scenery.MAP_HEIGHT,
		"carte des berges couvrant tout le parcours")
	for distance in [0, 150, 500, 1400, 2000, 2500, 3500, 4500, 5500, 6500, 7500, 8500, 9300]:
		var spans := COURSE.water_spans(distance)
		for j in range(0, spans.size(), 2):
			var center: float = (spans[j] + spans[j + 1]) * 0.5
			_check(scenery.shore_distance(center, distance) < -0.2,
				"les chenaux restent ouverts dans le décor lissé")
	_check(scenery.shore_distance(80, 1420) > 4.0
		and scenery.shore_distance(80, 1358) < -1.0
		and scenery.shore_distance(80, 1474) < -1.0,
		"apparition et disparition du premier îlot")
	var previous: float = scenery.shore_distance(60, 44)
	for step in range(1, 241):
		var value: float = scenery.shore_distance(60, 44.0 + step * 0.05)
		_check(absf(value - previous) < 0.3, "continuité des berges interpolées")
		previous = value
	var oak: Mesh = scenery.tree(0)
	var pine: Mesh = scenery.tree(1)
	_check(oak.get_aabb().size.x > 2.5 and pine.get_aabb().size.x < 2.2,
		"silhouettes distinctes des arbres")
	_check(scenery.shrub().get_aabb().size.y < 1.0, "buissons plus bas que les arbres")
	for kind in range(3):
		var building: Mesh = scenery.building(kind)
		_check(building.get_aabb().end.y > 1.5 and building.surface_get_array_index_len(0) > 0,
			"bâtiments regroupés en un maillage indexé")
	var world = load("res://flight_world.gd").new()
	world.add_child(world._scene)
	world._scene.add_child(world._camera)
	world._scenery = scenery
	var clearances: Array[Rect2] = world._build_settlements(world._scene, scenery, -120, world.STREAM_START)
	_check(clearances.size() > 20, "bâtiments répartis sur le parcours")
	for rectangle in clearances:
		var center := rectangle.get_center()
		_check(not world._on_road(center.y), "bâtiments à distance des routes")
		for offset in [Vector2.ZERO, Vector2(-4, -10), Vector2(4, -10), Vector2(-4, 10), Vector2(4, 10)]:
			_check(scenery.shore_distance(center.x + offset.x, center.y + offset.y) >= 1.4,
				"emprise des bâtiments sur la terre ferme")
	world.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


# Novice : le missile suit le jet après le tir. Expert : il part tout droit, à l'écran comme en simulation.
func _verify_difficulty() -> void:
	var paths := {}
	for guided in [true, false]:
		var flight := FLIGHT.new()
		flight.guided_shots = guided
		flight.cheats = FLIGHT.Cheat.INVULNERABILITY
		flight.advance(FLIGHT.FIRE)
		for i in 2:
			flight.advance(0)
		var start_x := flight.shot_x
		var start_drawn := flight.shot_visual_x()
		var drawn := PackedFloat32Array()
		for i in 4:
			flight.advance(FLIGHT.RIGHT)
			drawn.append(flight.shot_visual_x())
		paths[guided] = [flight.shot_active, flight.shot_x - start_x, start_drawn, drawn]
	_check(paths[true][0] and paths[true][1] > 0, "Novice : le missile suit l’avion vers la droite (%s)" % str(paths[true][1]))
	_check(paths[false][0] and paths[false][1] == 0, "Expert : le missile garde sa trajectoire (%s)" % str(paths[false][1]))
	var steady := true
	for value: float in paths[false][3]:
		steady = steady and is_equal_approx(value, paths[false][2])
	_check(steady, "Expert : le missile dessiné reste droit pendant que l’avion se déplace")

	var flight := FLIGHT.new()
	flight.guided_shots = false
	var inputs := PackedByteArray()
	for frame in range(1, 120):
		inputs.append(FLIGHT.reference_controls(frame))
		flight.advance(inputs[-1])
	var raid := RAID_REPLAY.new()
	raid.capture(flight, inputs, "f22")
	var config := ConfigFile.new()
	raid.write(config, RAID_REPLAY.LAST_SECTION)
	var restored := RAID_REPLAY.new()
	_check(raid.expert and restored.read(config, RAID_REPLAY.LAST_SECTION) and restored.expert,
		"un replay joué en Expert garde sa difficulté")
	config.erase_section_key(RAID_REPLAY.LAST_SECTION, "expert")
	var older := RAID_REPLAY.new()
	_check(older.read(config, RAID_REPLAY.LAST_SECTION) and not older.expert, "un ancien replay se rejoue en Novice")

	var path := "user://verify_difficulty.cfg"
	var settings := SETTINGS.new(path)
	_check(settings.difficulty == SETTINGS.Difficulty.NOVICE, "Novice est la difficulté par défaut")
	settings.difficulty = SETTINGS.Difficulty.EXPERT
	settings.save()
	var reloaded := SETTINGS.new(path)
	reloaded.load_file()
	_check(reloaded.difficulty == SETTINGS.Difficulty.EXPERT, "la difficulté choisie est sauvegardée")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# Musique : Menus par défaut avec « Fluvial Strike Resolve », boucle infinie, fondu au départ.
func _verify_music() -> void:
	var path := "user://verify_music.cfg"
	var settings := SETTINGS.new(path)
	_check(settings.music == SETTINGS.Music.MENU and settings.music_track == "fluvial_strike_resolve",
		"musique dans les menus et Fluvial Strike Resolve par défaut")
	_check(settings.music_volume == 40 and is_equal_approx(settings.music_volume / 100.0 * SETTINGS.MUSIC_VOLUME_SCALE, 0.15),
		"musique à 40 %% par défaut, au niveau de l’ancien réglage 15 %%")
	settings.music = SETTINGS.Music.GAME
	settings.music_track = "jet_fighter_groove"
	settings.music_volume = 35
	settings.save()
	var reloaded := SETTINGS.new(path)
	reloaded.load_file()
	_check(reloaded.music == SETTINGS.Music.GAME and reloaded.music_track == "jet_fighter_groove" and reloaded.music_volume == 35,
		"les réglages de musique sont sauvegardés")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var music := MUSIC.new()
	root.add_child(music)
	for track: Array in SETTINGS.MUSIC_TRACKS:
		var stream := MUSIC._load(track[0]) as AudioStreamOggVorbis
		_check(stream != null and stream.loop and stream.get_length() > 120.0, "%s se charge et boucle" % track[1])
	music.update("fluvial_strike_resolve", true, 1.0, 0.0)
	var player: AudioStreamPlayer = music.get_child(0)
	var start_db := player.volume_db
	music.update("fluvial_strike_resolve", true, 1.0, 1.0)
	var middle_db := player.volume_db
	music.update("fluvial_strike_resolve", true, 1.0, 1.5)
	_check(start_db < -60.0 and middle_db < -6.0 and is_equal_approx(player.volume_db, 0.0),
		"la musique démarre en fondu jusqu’au plein volume")
	music.update("fluvial_strike_resolve", false, 1.0, 1.0)
	_check(player.volume_db <= -79.0, "la musique s’éteint en fondu hors des menus")
	music.update("fluvial_strike_resolve", true, 1.0, 0.1)
	_check(player.volume_db > -80.0 and player.volume_db < -20.0, "elle reprend par un nouveau fondu")
	music.queue_free()


# Deux classements : un pour les raids en Novice, un pour les raids en Expert.
func _verify_expert_leaderboard() -> void:
	var path := "user://verify_expert_scores.cfg"
	var settings := SETTINGS.new(path)
	_check(settings.scores_expert == SETTINGS.DEFAULT_SCORES, "le classement Expert part du tableau de départ")
	_check(settings.score_rank(20000, true) == 0 and settings.submit_score("EXP", 20000, true) == OK,
		"un raid en Expert entre dans le classement Expert")
	_check(settings.scores_expert[0].initials == "EXP" and settings.scores[0].initials != "EXP",
		"le classement Novice n’est pas touché par un score Expert")
	_check(settings.submit_score("NOV", 18000) == OK and settings.scores[0].initials == "NOV"
		and settings.scores_expert[0].initials == "EXP", "un raid en Novice va dans le classement Novice")
	var reloaded := SETTINGS.new(path)
	reloaded.load_file()
	_check(reloaded.scores_expert[0].initials == "EXP" and reloaded.scores[0].initials == "NOV",
		"les deux classements sont sauvegardés séparément")
	_check(reloaded.clear_high_score() == OK and reloaded.scores == SETTINGS.DEFAULT_SCORES
		and reloaded.scores_expert == SETTINGS.DEFAULT_SCORES, "la réinitialisation remet les deux classements à zéro")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var older := ConfigFile.new()
	older.set_value("leaderboard", "entries", [{"initials": "OLD", "score": 16000}])
	older.save(path)
	var migrated := SETTINGS.new(path)
	migrated.load_file()
	_check(migrated.scores[0].initials == "OLD" and migrated.scores_expert == SETTINGS.DEFAULT_SCORES,
		"un ancien classement devient le classement Novice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
