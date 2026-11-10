extends RefCounted

const COURSE = preload("res://course.gd")
const LEFT := 1
const RIGHT := 2
const FAST := 4
const SLOW := 8
const FIRE := 16
const FULL_TANK := 65503
const LOW_FUEL := 16384
const INITIAL_RESERVES := 3
const RESPAWN_TICKS := 176
const FINAL_CRASH_TICKS := 97
const CRUISE := 128
const MIN_SPEED := 64
const MAX_SPEED := 254
const POINTS := {"tanker": 30, "helicopter": 60, "fuel": 80, "jet": 100, "bridge": 500}
const TARGET_SIZE := {
	"tanker": Vector2(8, 4), "helicopter": Vector2(4, 5),
	"fuel": Vector2(3.5, 10), "jet": Vector2(5, 4),
}

enum Status { FLYING, CRASHED, GAME_OVER, COMPLETE }

var tick: int
var status: Status
var x: int
var distance: int
var speed: int
var fuel: int
var score: int
var reserves: int
var section: int
var heading: int
var shot_active: bool
var shot_x: int
var shot_distance: int
var crash_cause: String
var crash_ticks: int
var finish_distance := COURSE.END
var bridge_destroyed: bool:
	get:
		return section > 1
var events: Array[Dictionary] = []

var _vertical_fraction: int
var _lateral_fraction: int
var _lateral_ramp: int
var _destroyed_targets := {}


func _init() -> void:
	reset()


func reset() -> void:
	tick = 0
	status = Status.FLYING
	score = 0
	reserves = INITIAL_RESERVES
	section = 1
	events.clear()
	_place_jet()


func advance(controls: int) -> void:
	if status == Status.CRASHED:
		tick += 1
		crash_ticks -= 1
		if crash_ticks == 0:
			if reserves == 0:
				status = Status.GAME_OVER
				_record("game_over")
			else:
				reserves -= 1
				status = Status.FLYING
				_place_jet()
				_record("respawn")
		return
	if status != Status.FLYING:
		return

	if tick == 0 and controls & FIRE:
		shot_active = true
		_record("fire")
	tick += 1
	var previous_x := x
	var previous_distance := distance
	var bridge_index := section - 1
	_move(controls)
	_shoot(controls, x - previous_x, distance - previous_distance)
	var cause := _check_contact(previous_x, previous_distance, bridge_index)
	if not cause.is_empty():
		_crash(cause)
		return
	if fuel < 32:
		_crash("fuel")
		return
	fuel -= 32
	if distance >= finish_distance:
		status = Status.COMPLETE
		_record("complete")


func _place_jet() -> void:
	x = 76
	distance = COURSE.BRIDGES[section - 2].y + 8 if section > 1 else 0
	speed = 66
	fuel = FULL_TANK
	heading = 0
	shot_active = false
	shot_x = 81
	shot_distance = distance
	crash_cause = ""
	crash_ticks = 0
	_vertical_fraction = 0
	_lateral_fraction = 0
	_lateral_ramp = 0
	_destroyed_targets.clear()


func _move(controls: int) -> void:
	if speed == MAX_SPEED:
		distance += 2
	else:
		_vertical_fraction += speed * 2
		distance += _vertical_fraction >> 8
		_vertical_fraction &= 255
	if controls & FAST:
		speed = mini(speed + 2, MAX_SPEED)
	elif controls & SLOW:
		speed = maxi(speed - 2, MIN_SPEED)
	elif speed < CRUISE:
		speed = mini(speed + 2, CRUISE)
	else:
		speed = maxi(speed - 2, CRUISE)

	var direction := int(bool(controls & RIGHT)) - int(bool(controls & LEFT))
	if direction == 0:
		_lateral_ramp = 0
		_lateral_fraction = 0
	elif _lateral_ramp == 248:
		x += direction
	else:
		_lateral_ramp += 8
		if direction > 0 and heading <= 0:
			_lateral_fraction = 255
		var next_fraction := _lateral_fraction + _lateral_ramp * direction
		x += next_fraction >> 8
		_lateral_fraction = next_fraction & 255
	heading = direction


func _shoot(controls: int, lateral_delta: int, scroll: int) -> void:
	if shot_active and shot_distance - distance + scroll >= 150:
		shot_active = false
	if not shot_active:
		if controls & FIRE:
			shot_active = true
			shot_x = x + 5
			shot_distance = distance
			_record("fire")
		return
	shot_x += lateral_delta
	var old_distance := shot_distance
	shot_distance += 6 + scroll
	var impact := INF
	var target := -1
	for i in range(COURSE.first_target(old_distance - 12), COURSE.first_target(shot_distance + 12.01)):
		if target_gone(i):
			continue
		var info: Array = COURSE.TARGETS[i]
		var center := target_position(i)
		var half: Vector2 = TARGET_SIZE[info[0]]
		if info[0] == "fuel":
			half.x = 2.5
			half.y = 12.0
		if absf(shot_x - center.x) <= half.x and shot_distance >= center.y - half.y \
				and old_distance <= center.y + half.y:
			if center.y - half.y < impact:
				impact = center.y - half.y
				target = i
	var bridge_index := section - 1
	if bridge_index < COURSE.BRIDGES.size() and shot_x >= 64 and shot_x < 96:
		var bridge: Vector2i = COURSE.BRIDGES[bridge_index]
		if old_distance <= bridge.y and shot_distance >= bridge.x and bridge.x <= impact:
			section += 1
			_add_score("bridge")
			shot_active = false
			return
	if target != -1:
		_destroyed_targets[target] = true
		_add_score(COURSE.TARGETS[target][0])
		shot_active = false


func _check_contact(previous_x: int, previous_distance: int, bridge_index: int) -> String:
	if not COURSE.is_water(previous_distance, previous_x + 1, previous_x + 7):
		return "bank"
	if not COURSE.is_water(previous_distance + 7, previous_x + 3, previous_x + 5):
		return "bank"
	if bridge_index < COURSE.BRIDGES.size():
		var bridge: Vector2i = COURSE.BRIDGES[bridge_index]
		if distance + 7 >= bridge.x and previous_distance - 4 <= bridge.y:
			return "bridge"

	for i in range(COURSE.first_target(distance - 16), COURSE.first_target(distance + 16.01)):
		if target_gone(i):
			continue
		var kind: String = COURSE.TARGETS[i][0]
		var center := target_position(i)
		var half: Vector2 = TARGET_SIZE[kind]
		if absf(center.y - distance) > half.y + 6.0 or absf(center.x - (x + 4)) > half.x + 3.0:
			continue
		if kind != "fuel":
			return kind
		fuel = mini(FULL_TANK + 32, fuel + 512)
	return ""


func target_gone(i: int) -> bool:
	return _destroyed_targets.has(i)


func target_position(i: int) -> Vector2:
	var item: Array = COURSE.TARGETS[i]
	var center_x: float = item[1]
	if item.size() > 3:
		if item[3] is Vector2:
			var drift: Vector2 = item[3]
			center_x += clampf((distance - drift.x) * drift.y, -12.0, 12.0)
		else:
			center_x = _tracked_x(item[3], item[0] == "jet")
	return Vector2(center_x, item[2])


func _tracked_x(track: Array, wraps: bool) -> float:
	var previous: Vector2 = track[0]
	if distance <= previous.x:
		return previous.y
	for i in range(1, track.size()):
		var next: Vector2 = track[i]
		if distance <= next.x:
			var fraction := inverse_lerp(previous.x, next.x, distance)
			if wraps:
				var travel := wrapf(next.y - previous.y, -80.0, 80.0)
				return fposmod(previous.y + travel * fraction, 160.0)
			return lerpf(previous.y, next.y, fraction)
		previous = next
	return previous.y


func _add_score(kind: String) -> void:
	var old_threshold := floori(score / 10000.0)
	score += POINTS[kind]
	reserves = mini(9, reserves + floori(score / 10000.0) - old_threshold)
	_record(kind)


func _crash(cause: String) -> void:
	status = Status.CRASHED
	crash_cause = cause
	crash_ticks = FINAL_CRASH_TICKS if reserves == 0 else RESPAWN_TICKS
	shot_active = false
	_record("crash")


func _record(kind: String) -> void:
	events.append({"tick": tick, "kind": kind, "distance": distance, "score": score})


static func reference_controls(frame: int) -> int:
	if frame >= 551 and frame <= 585:
		return FAST | FIRE | LEFT
	return FAST | FIRE
