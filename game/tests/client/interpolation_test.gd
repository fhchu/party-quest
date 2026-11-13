extends GdUnitTestSuite
## The adaptive drawing delay in interpolator.gd.

const GameTime := preload("res://shared/game_time.gd")
const Interpolator := preload("res://client/interpolator.gd")
const Snapshot := preload("res://net/snapshot.gd")

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
	var interval := GameTime.TICK_SEC
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
	var expected := (GameTime.TICK_SEC + Interpolator.MARGIN_SEC) * 1000
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


func test_delay_never_exceeds_the_max() -> void:
	_arrivals(NOW, Interpolator.MAX_DELAY_SEC * 2)
	_settle(NOW)
	assert_int(interp.delay_ms()).is_equal(roundi(Interpolator.MAX_DELAY_SEC * 1000))


## A snapshot arriving at [param now] that the server sent [param late]
## seconds earlier than the clock expects.
func _snapshot_late_by(now: float, late: float) -> Snapshot:
	var snap := Snapshot.new()
	snap.tick = roundi((now + interp._clock_offset - late) * GameTime.TICK_RATE)
	return snap


func test_snapshots_queued_during_a_stall_leave_the_delay_alone() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var before := interp.delay_ms()
	# A tab hidden for a minute hands over what was sent as it hid.
	var back := NOW + 60.0
	interp.add(_snapshot_late_by(back, back - NOW), back)
	for i in roundi(Interpolator.TRANSIT_WINDOW_SEC / FRAME_SEC):
		interp.update(back + i * FRAME_SEC, FRAME_SEC)
	assert_int(interp.delay_ms()).is_equal(before)


func test_the_first_snapshot_starts_the_clock_even_after_a_stall() -> void:
	var fresh := Interpolator.new()
	fresh.update(NOW, FRAME_SEC)
	var snap := Snapshot.new()
	snap.tick = 100
	fresh.add(snap, NOW + Interpolator.STALL_SEC * 2)
	assert_int(fresh.delay_ms()).is_equal(roundi(fresh.delay_sec * 1000))


func test_fixed_delay_stays_put() -> void:
	interp.fixed = true
	interp.delay_sec = 0.2
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_int(interp.delay_ms()).is_equal(roundi(interp.delay_sec * 1000))


func test_a_new_worlds_first_snapshot_replaces_the_old_world() -> void:
	var fresh := Interpolator.new()
	var old := Snapshot.new()
	old.tick = 100
	var swinging := Snapshot.Player.new()
	swinging.swing_ticks = 5
	old.players.append(swinging)
	fresh.add(old, NOW)
	var next := Snapshot.new()
	next.tick = old.tick + 1
	next.layout_number = old.layout_number + 1
	fresh.add(next, NOW + GameTime.TICK_SEC)
	# Long before the new snapshot's time: without the reset, the old world
	# (and its swing) would be drawn here.
	var drawn := fresh.view(NOW - 1.0)
	assert_int(drawn.layout_number).is_equal(next.layout_number)
	assert_array(drawn.players).is_empty()


func test_a_blended_view_is_drawn_at_its_own_tick_with_ages_to_run() -> void:
	var fresh := Interpolator.new()
	var a := Snapshot.new()
	a.tick = 100
	var b := Snapshot.new()
	b.tick = a.tick + 1
	for snap in [a, b]:
		snap.dummies.append(Snapshot.Dummy.new())
	b.dummies[0].ticks_since_struck = 0
	fresh.add(a, NOW)
	fresh.add(b, NOW + GameTime.TICK_SEC)
	# Half a tick past a's moment, so before b's hit.
	var drawn := fresh.view(NOW + fresh.delay_sec + 0.5 / GameTime.TICK_RATE)
	assert_int(drawn.tick).is_equal(a.tick)
	assert_int(drawn.dummies[0].ticks_since_struck).is_equal(a.tick - b.tick)


func test_dummies_blend_with_their_own_earlier_position() -> void:
	var fresh := Interpolator.new()
	var a := Snapshot.new()
	a.tick = 100
	var b := Snapshot.new()
	b.tick = a.tick + 1
	for id in [1, 2]:
		var d := Snapshot.Dummy.new()
		d.id = id
		d.pos = Vector2(id * 100, 0)
		a.dummies.append(d)
	# Dummy 1 is gone in b; dummy 2 hasn't moved.
	b.dummies.append(a.dummies[1].copy())
	fresh.add(a, NOW)
	fresh.add(b, NOW + GameTime.TICK_SEC)
	var drawn := fresh.view(NOW + fresh.delay_sec + GameTime.TICK_SEC / 2)
	assert_int(drawn.dummies.size()).is_equal(1)
	assert_vector(drawn.dummies[0].pos).is_equal(a.dummies[1].pos)


## Feeds [param count] snapshots, each [param late] by the matching entry
## (cycling), and returns the measured jitter.
func _jitter_of(lates: Array[float], count: int) -> int:
	var fresh := Interpolator.new()
	for i in count:
		var snap := Snapshot.new()
		snap.tick = i + 1
		var arrived := Interpolator.time_of(snap) + lates[i % lates.size()]
		fresh.add(snap, arrived)
		fresh.update(arrived, GameTime.TICK_SEC)
	return fresh.jitter_ms()


func test_a_steady_link_has_no_jitter() -> void:
	assert_int(_jitter_of([0.05], 200)).is_equal(0)


func test_uneven_arrivals_measure_their_spread() -> void:
	# Alternating 20 ms and 60 ms late: each snapshot's delay differs from
	# the last by 40 ms, which the estimate settles on.
	assert_int(_jitter_of([0.02, 0.06], 200)).is_equal(40)
