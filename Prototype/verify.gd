extends SceneTree

const FLIGHT = preload("res://flight.gd")
const COURSE = preload("res://course.gd")
const SETTINGS = preload("res://flight_settings.gd")
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
	_verify_pilot_and_fuel()
	_verify_respawn(435, false)
	_verify_respawn(487, true)
	_verify_game_over()
	_verify_full_raid()
	_verify_continuation()
	_verify_cheats()
	_verify_settings()
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
		"rejeu continu du départ au-delà du dixième pont")
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
	_check(settings.bind(0, KEY_RIGHT, false) and settings.keyboard[1] == KEY_LEFT,
		"permutation de deux raccourcis clavier")
	_check(not settings.bind(0, KEY_ESCAPE, false) and not settings.bind(4, JOY_BUTTON_START, true),
		"les commandes de pause restent disponibles")
	_check(settings.bind(4, JOY_BUTTON_X, true), "affectation manette")
	settings.volume = 35
	settings.quality_hd = false
	settings.sync_mode = PACING.Sync.ADAPTIVE
	settings.refresh_limit = 144
	settings.dynamic_resolution = false
	settings.fullscreen = true
	settings.muted = true
	_check(settings.update_record(1200) and settings.save() == OK, "première sauvegarde locale")

	var restored := SETTINGS.new(path)
	restored.load_file()
	_check(restored.keyboard == settings.keyboard and restored.gamepad == settings.gamepad
		and restored.volume == 35 and not restored.quality_hd and restored.sync_mode == PACING.Sync.ADAPTIVE
		and restored.refresh_limit == 144 and not restored.dynamic_resolution
		and restored.fullscreen and restored.muted and restored.record == 1200
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
	_check(not updated.update_record(1000), "un score inférieur ne remplace pas le record")
	view.free()
	DirAccess.remove_absolute(path)


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
