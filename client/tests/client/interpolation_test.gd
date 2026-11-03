extends GdUnitTestSuite
## The adaptive interpolation delay in client.gd, without connecting.

const Client := preload("res://client/client.gd")

var c: Client


func before_test() -> void:
	c = Client.new()
	c._have_clock = true
	c._clock_offset = 5.0
	c._render_offset = c._clock_offset - 0.1


func after_test() -> void:
	c._hud.free()  # Only parented in _ready, which never runs here.
	c.free()


## A window of snapshots that each arrived [param transit] seconds late.
func _arrivals(now: float, transit: float) -> void:
	c._transits.clear()
	for i in int(Client.TRANSIT_WINDOW_SEC / Client.SNAP_INTERVAL):
		c._transits.append([now - i * Client.SNAP_INTERVAL, c._clock_offset - transit])


func _run(now: float, seconds: float) -> void:
	var frames := roundi(seconds * 60)
	for i in frames:
		c._update_render_offset(now, 1.0 / 60)


## Runs until the delay stops changing.
func _settle(now: float) -> void:
	var before := INF
	while not is_equal_approx(before, c._render_offset):
		before = c._render_offset
		_run(now, 1.0)


func test_steady_connection_settles_one_interval_plus_margin_behind() -> void:
	_arrivals(10.0, 0.0)
	_settle(10.0)
	var expected := (Client.SNAP_INTERVAL + Client.INTERP_MARGIN_SEC) * 1000
	assert_int(c._interp_ms()).is_equal(roundi(expected))


func test_delay_grows_no_faster_than_the_rise_rate() -> void:
	_arrivals(10.0, 0.0)
	_settle(10.0)
	var before := c._render_offset
	_arrivals(10.0, Client.INTERP_RISE * 2)  # Twice what it can rise in a second.
	_run(10.0, 0.5)
	assert_float(before - c._render_offset).is_equal_approx(Client.INTERP_RISE * 0.5, 0.002)


func test_delay_shrinks_slowly() -> void:
	_arrivals(10.0, Client.INTERP_FALL * 2)  # Twice what it can shrink in a second.
	_settle(10.0)
	var before := c._render_offset
	_arrivals(10.0, 0.0)
	_run(10.0, 1.0)
	assert_float(c._render_offset - before).is_equal_approx(Client.INTERP_FALL, 0.002)


func test_long_frames_are_capped() -> void:
	_arrivals(10.0, 0.0)
	_settle(10.0)
	var before := c._render_offset
	var long_frame := Client.INTERP_MAX_STEP_SEC * 50  # A hidden tab coming back.
	_arrivals(10.0, Client.INTERP_RISE * long_frame)
	c._update_render_offset(10.0, long_frame)
	assert_float(before - c._render_offset).is_equal_approx(
			Client.INTERP_RISE * Client.INTERP_MAX_STEP_SEC, 0.001)


func test_interp_option_fixes_the_delay() -> void:
	c._interp_auto = false
	c._interp_delay = 0.2
	_arrivals(10.0, 0.0)
	_run(10.0, 1.0)
	assert_int(c._interp_ms()).is_equal(200)
