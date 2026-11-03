extends GdUnitTestSuite
## The adaptive interpolation delay in client.gd, without connecting.

const Client := preload("res://client/client.gd")
const Protocol := preload("res://net/protocol.gd")

## A 60 Hz display.
const FRAME_SEC := 1.0 / 60
## Any time after the clock started; the delay only looks back from it.
const NOW := 10.0
## Frames don't land exactly on the rates' limits.
const TOLERANCE := 0.002

var c: Client


func before_test() -> void:
	c = Client.new()
	c._have_clock = true
	# Any value: only differences from it matter.
	c._clock_offset = 5.0
	c._render_offset = c._clock_offset - c._interp_delay


func after_test() -> void:
	# Only parented in _ready, which never runs here.
	c._hud.free()
	c.free()


## A window of snapshots that each arrived [param transit] seconds late.
func _arrivals(now: float, transit: float) -> void:
	c._transits.clear()
	var interval := Protocol.SNAPSHOT_INTERVAL_SEC
	for i in int(Client.TRANSIT_WINDOW_SEC / interval):
		c._transits.append(Client.Transit.new(now - i * interval, c._clock_offset - transit))


func _run(now: float, seconds: float) -> void:
	for i in roundi(seconds / FRAME_SEC):
		c._update_render_offset(now, FRAME_SEC)


## Runs until the delay stops changing.
func _settle(now: float) -> void:
	var before := INF
	while not is_equal_approx(before, c._render_offset):
		before = c._render_offset
		_run(now, 1.0)


func test_steady_connection_settles_one_interval_plus_margin_behind() -> void:
	_arrivals(NOW, 0.0)
	_settle(10.0)
	var expected := (Protocol.SNAPSHOT_INTERVAL_SEC + Client.INTERP_MARGIN_SEC) * 1000
	assert_int(c._interp_ms()).is_equal(roundi(expected))


func test_delay_grows_no_faster_than_the_rise_rate() -> void:
	_arrivals(NOW, 0.0)
	_settle(10.0)
	var before := c._render_offset
	# Twice what it can rise in a second.
	_arrivals(NOW, Client.INTERP_RISE * 2)
	var seconds := 0.5
	_run(NOW, seconds)
	assert_float(before - c._render_offset).is_equal_approx(
			Client.INTERP_RISE * seconds, TOLERANCE)


func test_delay_shrinks_slowly() -> void:
	# Twice what it can shrink in a second.
	_arrivals(NOW, Client.INTERP_FALL * 2)
	_settle(10.0)
	var before := c._render_offset
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_float(c._render_offset - before).is_equal_approx(Client.INTERP_FALL, TOLERANCE)


func test_long_frames_are_capped() -> void:
	_arrivals(NOW, 0.0)
	_settle(10.0)
	var before := c._render_offset
	# A hidden tab coming back: far longer than the cap.
	var long_frame := Client.INTERP_MAX_STEP_SEC * 50
	_arrivals(NOW, Client.INTERP_RISE * long_frame)
	c._update_render_offset(NOW, long_frame)
	assert_float(before - c._render_offset).is_equal_approx(
			Client.INTERP_RISE * Client.INTERP_MAX_STEP_SEC, TOLERANCE)


func test_interp_option_fixes_the_delay() -> void:
	c._interp_auto = false
	c._interp_delay = 0.2
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_int(c._interp_ms()).is_equal(roundi(c._interp_delay * 1000))
