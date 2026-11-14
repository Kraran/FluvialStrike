extends RefCounted

enum Sync { SCREEN, ADAPTIVE, OFF }

const MIN_CAP := 30
const WIDTHS := [480, 608, 736, 912, 1064, 1216, 1368]
const BUDGET_WINDOW := 800.0
# The simulation always advances 60 ticks per second of real time, whatever the display rate.
const TICK_RATE := 60.0
# A very late frame catches up on at most this many ticks, then the game slows down.
const MAX_FRAME_TICKS := 4.0
const CADENCE_WINDOW := 0.5
const DRIFT_MEMORY := 0.2

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
# Expected time between two displayed frames (0 when unknown) and the same in simulation ticks.
var _period := 0.0
var _period_ticks := 0.0
# True while the measured frame times confirm that cadence: frames then advance by equal steps.
var _steady := false
var _drift := 0.0
var _cadence_time := 0.0
var _cadence_expected := 0.0


func configure(refresh: float, requested: int, sync: int, hd: bool, adaptive: bool) -> void:
	var known_refresh := refresh > 0.0
	if not known_refresh:
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

	if cap > 0:
		_period = 1.0 / cap
	elif sync == Sync.SCREEN and known_refresh:
		_period = 1.0 / refresh
	else:
		_period = 0.0
	_period_ticks = _period * TICK_RATE
	# Near a whole fraction of the tick rate (60, 120, 240 Hz), every image shows a whole tick,
	# half a tick, a quarter of a tick: the scroll keeps landing on the same sub-positions.
	var frames_per_tick := roundf(1.0 / _period_ticks) if _period > 0.0 else 0.0
	if frames_per_tick >= 1.0 and absf(_period_ticks * frames_per_tick - 1.0) < 1.0 / TICK_RATE:
		_period_ticks = 1.0 / frames_per_tick
	_steady = _period > 0.0
	_drift = 0.0
	_cadence_time = 0.0
	_cadence_expected = 0.0


# Simulation ticks elapsed during the frame that lasted `delta` seconds; fractions are kept.
# The result follows real time, so the game speed never depends on the display rate. On a steady
# cadence (vsync or frame cap), the measured time is replaced by the exact frame period: every
# image then moves by the same amount. That period is only trusted while the measured times
# agree with it: a wrong or unknown refresh rate, VRR or a slow GPU fall back to the real time.
func frame_ticks(delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var elapsed := minf(delta * TICK_RATE, MAX_FRAME_TICKS)
	if _period <= 0.0:
		return elapsed
	var beats := maxf(1.0, roundf(delta / _period))
	# Gap between real time and the announced cadence over the last frames. Vsync jitter cancels
	# out; a display faster or slower than announced builds up two periods within a few frames.
	_drift = _drift * exp(-delta / DRIFT_MEMORY) + delta - beats * _period
	if absf(_drift) > _period * 2.0:
		_steady = false
	# Smaller gaps show over half a second: beyond 2 %, real time takes over.
	_cadence_time += delta
	_cadence_expected += beats * _period
	if _cadence_time >= CADENCE_WINDOW:
		var error := absf(_cadence_time / _cadence_expected - 1.0)
		if error > 0.02:
			_steady = false
		elif error < 0.01 and absf(_drift) < _period * 0.5:
			_steady = true
		_cadence_time = 0.0
		_cadence_expected = 0.0
	return minf(beats * _period_ticks, MAX_FRAME_TICKS) if _steady else elapsed


func is_steady() -> bool:
	return _steady


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
