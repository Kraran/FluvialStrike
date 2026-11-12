extends RefCounted

enum Sync { SCREEN, ADAPTIVE, OFF }

const MIN_CAP := 30
const WIDTHS := [480, 608, 736, 912, 1064, 1216, 1368]
const BUDGET_WINDOW := 800.0

var target := 60.0
var cap := 0
var width := 1368
var antialias := true

var _level := WIDTHS.size() - 1
var _max_level := _level
var _enabled := true
var _high_quality := true
var _elapsed := 0.0
var _frames := 0
var _late := 0
var _gpu_time := 0.0
var _gpu_samples := 0
var _stable_windows := 0
var _cooldown := 0


func configure(refresh: float, requested: int, sync: int, hd: bool, adaptive: bool) -> void:
	if refresh <= 0.0:
		refresh = 60.0
	var effective := float(requested) if requested > 0 else refresh
	if sync == Sync.ADAPTIVE:
		var upper := minf(effective, refresh)
		var headroom := 3 if upper >= 100.0 else 2
		cap = maxi(30, floori(upper + 0.1) - headroom)
		target = float(cap)
	elif sync == Sync.SCREEN:
		# With vsync, only a whole fraction of the refresh shows every image for the same time.
		cap = requested if divides_refresh(refresh, requested) else 0
		target = float(cap) if cap > 0 else refresh
	else:
		cap = roundi(effective)
		target = float(cap)

	_enabled = adaptive
	_high_quality = hd
	_max_level = WIDTHS.size() - 1 if hd else 3
	_level = _max_level
	if adaptive and target >= 100.0:
		_level = mini(_max_level, 3)
	_cooldown = 0
	_stable_windows = 0
	_clear_window()
	_apply_level()


# Frame caps that show each image for the same number of refreshes: half, third, quarter.
static func divisor_rates(refresh: float) -> Array[int]:
	var rates: Array[int] = []
	if refresh <= 0.0:
		return rates
	for divisor in range(2, 5):
		var rate := roundi(refresh / divisor)
		if rate >= MIN_CAP:
			rates.append(rate)
	return rates


static func divides_refresh(refresh: float, rate: int) -> bool:
	return rate > 0 and rate in divisor_rates(refresh)


func observe(frame_ms: float, gpu_ms: float) -> bool:
	if not _enabled or frame_ms <= 0.0:
		return false
	var budget := 1000.0 / target
	_elapsed += minf(frame_ms, 100.0)
	_frames += 1
	if frame_ms > budget * 1.28:
		_late += 1
	if gpu_ms > 0.0:
		_gpu_time += gpu_ms
		_gpu_samples += 1
	if _elapsed < BUDGET_WINDOW:
		return false

	var mean := _elapsed / _frames
	var late_fraction := float(_late) / _frames
	var gpu_mean := _gpu_time / _gpu_samples if _gpu_samples else 0.0
	var old_level := _level
	_cooldown = maxi(0, _cooldown - 1)
	# Alternating early and late samples can still sustain the requested cadence.
	var sustained_lateness := late_fraction > 0.12 and mean > budget * 1.025
	# Only a GPU-bound frame gets faster at a lower resolution; CPU spikes do not.
	var gpu_bound := gpu_mean > budget * 0.85
	if gpu_bound and (mean > budget * 1.07 or sustained_lateness):
		_level = maxi(_level - 1, 0)
		_cooldown = 5
		_stable_windows = 0
	elif late_fraction < 0.025 and (gpu_mean <= 0.0 or gpu_mean < budget * 0.63):
		_stable_windows += 1
		var required := 3 if gpu_mean > 0.0 else 6
		if _cooldown == 0 and _stable_windows >= required:
			_level = mini(_level + 1, _max_level)
			_stable_windows = 0
	else:
		_stable_windows = 0
	_clear_window()
	_apply_level()
	return _level != old_level


func _apply_level() -> void:
	width = WIDTHS[_level]
	antialias = _high_quality and target <= 75.5


func _clear_window() -> void:
	_elapsed = 0.0
	_frames = 0
	_late = 0
	_gpu_time = 0.0
	_gpu_samples = 0
