extends GdUnitTestSuite
## The adaptive drawing delay in interpolator.gd.

const Interpolator := preload("res://client/interpolator.gd")
const Protocol := preload("res://net/protocol.gd")

## A 60 Hz display.
const FRAME_SEC := 1.0 / 60
## Any time after the clock started; the delay only looks back from it.
const NOW := 10.0
## Frames don't land exactly on the rates' limits.
const TOLERANCE := 0.002

var interp: Interpolator


func before_test() -> void:
	interp = Interpolator.new()
	interp._have_clock = true
	# Any value: only differences from it matter.
	interp._clock_offset = 5.0
	interp._render_offset = interp._clock_offset - interp.delay_sec


## A window of snapshots that each arrived [param transit] seconds late.
func _arrivals(now: float, transit: float) -> void:
	interp._transits.clear()
	var interval := Protocol.SNAPSHOT_INTERVAL_SEC
	for i in int(Interpolator.TRANSIT_WINDOW_SEC / interval):
		interp._transits.append(Interpolator.Transit.new(
				now - i * interval, interp._clock_offset - transit))


func _run(now: float, seconds: float) -> void:
	for i in roundi(seconds / FRAME_SEC):
		interp.update(now, FRAME_SEC)


## Runs until the delay stops changing.
func _settle(now: float) -> void:
	var before := INF
	while not is_equal_approx(before, interp._render_offset):
		before = interp._render_offset
		_run(now, 1.0)


func test_steady_connection_settles_one_interval_plus_margin_behind() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var expected := (Protocol.SNAPSHOT_INTERVAL_SEC + Interpolator.MARGIN_SEC) * 1000
	assert_int(interp.delay_ms()).is_equal(roundi(expected))


func test_delay_grows_no_faster_than_the_rise_rate() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var before := interp._render_offset
	# Twice what it can rise in a second.
	_arrivals(NOW, Interpolator.RISE * 2)
	var seconds := 0.5
	_run(NOW, seconds)
	assert_float(before - interp._render_offset).is_equal_approx(
			Interpolator.RISE * seconds, TOLERANCE)


func test_delay_shrinks_slowly() -> void:
	# Twice what it can shrink in a second.
	_arrivals(NOW, Interpolator.FALL * 2)
	_settle(NOW)
	var before := interp._render_offset
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_float(interp._render_offset - before).is_equal_approx(Interpolator.FALL, TOLERANCE)


func test_long_frames_are_capped() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var before := interp._render_offset
	# A hidden tab coming back: far longer than the cap.
	var long_frame := Interpolator.MAX_STEP_SEC * 50
	_arrivals(NOW, Interpolator.RISE * long_frame)
	interp.update(NOW, long_frame)
	assert_float(before - interp._render_offset).is_equal_approx(
			Interpolator.RISE * Interpolator.MAX_STEP_SEC, TOLERANCE)


func test_fixed_delay_stays_put() -> void:
	interp.fixed = true
	interp.delay_sec = 0.2
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_int(interp.delay_ms()).is_equal(roundi(interp.delay_sec * 1000))
