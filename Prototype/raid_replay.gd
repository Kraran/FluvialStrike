extends RefCounted

const FLIGHT = preload("res://flight.gd")
const AIRCRAFT = preload("res://player_aircraft.gd")
# Format 2 : tir testé là où il est dessiné. Les replays au format 1 gardent l'ancienne règle.
const FORMAT := 2
const LEGACY_FORMAT := 1
const BRIDGE_STATS_WIDTH := 3
const BEST_SECTION := "best_replay"
const LAST_SECTION := "last_replay"
const CHEAT_MASK := FLIGHT.Cheat.LIVES | FLIGHT.Cheat.INVULNERABILITY | FLIGHT.Cheat.FUEL
const MAX_FRAMES := FLIGHT.COURSE.END * 3

var score: int
var cheats: int
var legacy_hits := false
# Raid joué en Expert : missiles non guidés. Absent des anciens replays, joués en Novice.
var expert := false
var aircraft: String
var inputs := PackedByteArray()
var bridge_ticks := PackedInt32Array()
var bridge_stats := PackedInt32Array()
var _encoded_inputs := ""
var _analysis: FLIGHT
var _analysis_finished := false
var _ghost_flight: FLIGHT
# Each sample stores distance, lateral position and steering.
var _ghost_path := PackedVector3Array()
var _ghost_finished := false


func capture(flight: FLIGHT, controls: PackedByteArray, aircraft_id: String) -> void:
	score = flight.score
	cheats = flight.cheats
	legacy_hits = flight.legacy_shot_hitbox
	expert = not flight.guided_shots
	aircraft = AIRCRAFT.validated(aircraft_id)
	inputs = controls.duplicate()
	for event: Dictionary in flight.events:
		if event.kind in ["bridge", "bridge_passed"]:
			bridge_ticks.append(event.tick)
	_collect_bridge_stats(flight.events)


# Returns lateral position, steering and visibility at the player's rendered distance.
func ghost_pose(distance: float, step_budget: int) -> Vector3:
	_extend_ghost_path(distance + 12.0, step_budget)
	if _ghost_path.is_empty() or distance < _ghost_path[0].x or distance > _ghost_path[-1].x:
		return Vector3.INF

	var low := 0
	var high := _ghost_path.size() - 1
	while low < high:
		var mid := (low + high) >> 1
		if _ghost_path[mid].x < distance:
			low = mid + 1
		else:
			high = mid
	var current := _ghost_path[low]
	var previous := _ghost_path[maxi(0, low - 1)]
	if distance < current.x and absf(current.y - previous.y) > 3.0:
		# The replay caught up to its earlier position after a crash.
		return Vector3.INF
	var weight := inverse_lerp(previous.x, current.x, distance) if previous.x != current.x else 1.0
	var fade := smoothstep(0.0, 10.0, _ghost_path[-1].x - distance) if _ghost_finished else 1.0
	return Vector3(lerpf(previous.y, current.y, weight), lerpf(previous.z, current.z, weight), fade)


func _extend_ghost_path(look_ahead: float, step_budget: int) -> void:
	if _ghost_finished or step_budget <= 0:
		return
	if _ghost_flight == null:
		_ghost_flight = FLIGHT.new()
		_ghost_flight.cheats = cheats
		_ghost_flight.legacy_shot_hitbox = legacy_hits
		_ghost_flight.guided_shots = not expert
		_ghost_path.append(Vector3(_ghost_flight.visual_distance(), _ghost_flight.visual_x(), 0.0))

	var stop := mini(inputs.size(), _ghost_flight.tick + step_budget)
	while _ghost_flight.tick < stop and _ghost_flight.status < FLIGHT.Status.GAME_OVER \
			and _ghost_path[-1].x < look_ahead:
		_ghost_flight.advance(inputs[_ghost_flight.tick])
		if _ghost_flight.status in [FLIGHT.Status.FLYING, FLIGHT.Status.COMPLETE]:
			var distance := _ghost_flight.visual_distance()
			# Keep the first passage at each distance, even when the replay respawns upstream.
			if distance > _ghost_path[-1].x:
				_ghost_path.append(Vector3(distance, _ghost_flight.visual_x(), _ghost_flight.visual_lateral_speed()))
	# Event history is unnecessary for the visual trace.
	_ghost_flight.events.clear()
	if _ghost_flight.tick == inputs.size() or _ghost_flight.status >= FLIGHT.Status.GAME_OVER:
		_ghost_finished = true
		_ghost_flight = null


func prepare_bridge_stats(step_budget: int) -> bool:
	if _analysis_finished or bridge_stats.size() == bridge_ticks.size() * BRIDGE_STATS_WIDTH:
		return true
	if _analysis == null:
		_analysis = FLIGHT.new()
		_analysis.cheats = cheats
		_analysis.legacy_shot_hitbox = legacy_hits
		_analysis.guided_shots = not expert
	var stop := mini(_analysis.tick + step_budget, bridge_ticks[-1])
	while _analysis.tick < stop and _analysis.status < FLIGHT.Status.GAME_OVER:
		_analysis.advance(inputs[_analysis.tick])
	if _analysis.tick < bridge_ticks[-1] and _analysis.status < FLIGHT.Status.GAME_OVER:
		return false
	_collect_bridge_stats(_analysis.events)
	_analysis = null
	_analysis_finished = true
	return true


func _collect_bridge_stats(events: Array[Dictionary]) -> void:
	var stats := PackedInt32Array()
	var previous_score := 0
	var losses := 0
	for event: Dictionary in events:
		match event.kind:
			"crash":
				losses += 1
			"bridge", "bridge_passed":
				var index := stats.size() / BRIDGE_STATS_WIDTH
				if index >= bridge_ticks.size() or event.tick != bridge_ticks[index]:
					return
				stats.append_array(PackedInt32Array([event.score - previous_score, event.fuel, losses]))
				previous_score = event.score
				losses = 0
	if stats.size() == bridge_ticks.size() * BRIDGE_STATS_WIDTH:
		bridge_stats = stats


func read(config: ConfigFile, section: String, expected_score: int = -1) -> bool:
	var version = config.get_value(section, "format", 0)
	var stored_score = config.get_value(section, "score", -1)
	var frames = config.get_value(section, "frames", 0)
	var packed = config.get_value(section, "inputs", "")
	var bridges = config.get_value(section, "bridges", PackedInt32Array())
	var stored_cheats = config.get_value(section, "cheats", 0)
	if not version in [LEGACY_FORMAT, FORMAT] or not stored_score is int or stored_score < 0 or stored_score > FLIGHT.COURSE.MAX_SCORE \
			or (expected_score >= 0 and stored_score != expected_score) \
			or not stored_cheats is int or stored_cheats < 0 or stored_cheats > CHEAT_MASK \
			or not frames is int \
			or frames <= 0 or frames > MAX_FRAMES or not packed is String \
			or packed.is_empty() or packed.length() > MAX_FRAMES * 2 \
			or not bridges is PackedInt32Array or bridges.size() > FLIGHT.COURSE.BRIDGE_COUNT:
		return false
	var previous := 0
	for tick: int in bridges:
		if tick <= previous or tick > frames:
			return false
		previous = tick
	var decoded := Marshalls.base64_to_raw(packed).decompress(frames, FileAccess.COMPRESSION_DEFLATE)
	if decoded.size() != frames:
		return false
	score = stored_score
	cheats = stored_cheats
	legacy_hits = version == LEGACY_FORMAT
	expert = config.get_value(section, "expert", false) == true
	aircraft = AIRCRAFT.validated(str(config.get_value(section, "aircraft", AIRCRAFT.DEFAULT)))
	inputs = decoded
	bridge_ticks = bridges
	var stats = config.get_value(section, "bridge_stats", PackedInt32Array())
	if stats is PackedInt32Array and stats.size() == bridges.size() * BRIDGE_STATS_WIDTH:
		bridge_stats = stats
	_encoded_inputs = packed
	return true


func write(config: ConfigFile, section: String) -> void:
	if _encoded_inputs.is_empty():
		_encoded_inputs = Marshalls.raw_to_base64(inputs.compress(FileAccess.COMPRESSION_DEFLATE))
	config.set_value(section, "format", LEGACY_FORMAT if legacy_hits else FORMAT)
	if expert:
		config.set_value(section, "expert", true)
	elif config.has_section_key(section, "expert"):
		config.erase_section_key(section, "expert")
	config.set_value(section, "score", score)
	config.set_value(section, "cheats", cheats)
	config.set_value(section, "aircraft", aircraft)
	config.set_value(section, "frames", inputs.size())
	config.set_value(section, "inputs", _encoded_inputs)
	config.set_value(section, "bridges", bridge_ticks)
	if not bridge_stats.is_empty():
		config.set_value(section, "bridge_stats", bridge_stats)
	elif config.has_section_key(section, "bridge_stats"):
		config.erase_section_key(section, "bridge_stats")
