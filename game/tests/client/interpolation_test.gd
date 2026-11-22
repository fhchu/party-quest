extends GdUnitTestSuite
## The adaptive drawing delay in interpolator.gd.

const GameTime := preload("res://shared/game_time.gd")
const Interpolator := preload("res://client/interpolator.gd")
const WorldView := preload("res://client/world_view.gd")

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
	# Far ahead of anything drawn, so drawing never catches up and pauses.
	interp._snaps.append(_snapshot_late_by(NOW, -60.0))


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
	var earlier := INF
	while not is_equal_approx(earlier, interp._render_offset):
		earlier = interp._render_offset
		_run(now, 1.0)


func test_the_minimum_delay_is_below_the_maximum() -> void:
	assert_float(Interpolator.MIN_DELAY_SEC).is_less(Interpolator.MAX_DELAY_SEC)


func test_a_steady_connection_aims_below_the_minimum_delay() -> void:
	# Snapshots that arrive on time put the target one tick back
	# (Interpolator.update()).
	assert_float(GameTime.TICK_SEC).is_less(Interpolator.MIN_DELAY_SEC)


func test_a_steady_connection_settles_at_the_minimum_delay() -> void:
	# Far enough from the target to be outside the dead zone.
	interp._render_offset = interp._clock_offset - Interpolator.MAX_DELAY_SEC
	_arrivals(NOW, 0.0)
	_settle(NOW)
	assert_int(interp.delay_ms()).is_equal(roundi(Interpolator.MIN_DELAY_SEC * 1000))


func test_a_target_inside_the_dead_zone_leaves_the_delay_alone() -> void:
	# Late enough that the target is above the minimum delay.
	var late := Interpolator.MIN_DELAY_SEC + Interpolator.DEAD_ZONE_SEC * 2
	_arrivals(NOW, late)
	_settle(NOW)
	var earlier := interp._render_offset
	_arrivals(NOW, late + Interpolator.DEAD_ZONE_SEC / 2)
	_run(NOW, 1.0)
	assert_float(interp._render_offset).is_equal(earlier)


func test_a_target_past_the_dead_zone_is_reached_exactly() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var later := Interpolator.DEAD_ZONE_SEC * 4
	_arrivals(NOW, later)
	_settle(NOW)
	var expected := (later + GameTime.TICK_SEC) * 1000
	assert_int(interp.delay_ms()).is_equal(roundi(expected))


func test_delay_grows_no_faster_than_the_rise_rate() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var earlier := interp._render_offset
	# Twice what it can rise in a second.
	_arrivals(NOW, Interpolator.RISE * 2)
	var seconds := 0.5
	_run(NOW, seconds)
	assert_float(earlier - interp._render_offset).is_equal_approx(
			Interpolator.RISE * seconds, TOLERANCE)


func test_delay_shrinks_slowly() -> void:
	# Past the dead zone by twice what it can shrink in a second.
	var late := Interpolator.DEAD_ZONE_SEC + Interpolator.FALL * 2
	interp._render_offset = interp._clock_offset - Interpolator.MAX_DELAY_SEC
	_arrivals(NOW, late)
	_settle(NOW)
	var earlier := interp._render_offset
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_float(interp._render_offset - earlier).is_equal_approx(Interpolator.FALL, TOLERANCE)


func test_long_frames_are_capped() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var earlier := interp._render_offset
	# A hidden tab coming back: far longer than the cap.
	var long_frame := Interpolator.MAX_STEP_SEC * 50
	_arrivals(NOW, Interpolator.RISE * long_frame)
	interp.update(NOW, long_frame)
	assert_float(earlier - interp._render_offset).is_equal_approx(
			Interpolator.RISE * Interpolator.MAX_STEP_SEC, TOLERANCE)


func test_delay_never_exceeds_the_max() -> void:
	_arrivals(NOW, Interpolator.MAX_DELAY_SEC * 2)
	_settle(NOW)
	assert_int(interp.delay_ms()).is_equal(roundi(Interpolator.MAX_DELAY_SEC * 1000))


## A snapshot arriving at [param now] that the server sent [param late]
## seconds earlier than the clock expects.
func _snapshot_late_by(now: float, late: float) -> WorldView:
	var snap := WorldView.new()
	snap.tick = roundi((now + interp._clock_offset - late) * GameTime.TICK_RATE)
	return snap


## Holds only [param snap] and draws so far behind that it's never reached.
func _hold_only(snap: WorldView) -> void:
	interp._snaps.clear()
	interp._snaps.append(snap)


func test_drawing_pauses_at_the_newest_snapshot() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var newest := _snapshot_late_by(NOW, 0.0)
	_hold_only(newest)
	var earlier := interp.delay_ms()
	# Long enough for drawing to pass the newest snapshot's time.
	var later := NOW + interp.delay_ms() / 1000.0 + 0.1
	interp.update(later, FRAME_SEC)
	assert_float(later + interp._render_offset).is_equal_approx(
			Interpolator.time_of(newest), TOLERANCE)
	assert_int(interp.delay_ms()).is_greater(earlier)


func test_drawing_runs_on_past_the_newest_snapshot_at_the_max_delay() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	_hold_only(_snapshot_late_by(NOW, 0.0))
	# Frame by frame, so no frame is long enough to count as a stall.
	for i in roundi(Interpolator.MAX_DELAY_SEC * 2 / FRAME_SEC):
		interp.update(NOW + i * FRAME_SEC, FRAME_SEC)
	assert_int(interp.delay_ms()).is_equal(roundi(Interpolator.MAX_DELAY_SEC * 1000))


func test_drawing_doesnt_pause_after_a_stalled_frame() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	_hold_only(_snapshot_late_by(NOW, 0.0))
	var earlier := interp.delay_ms()
	# A hidden tab's frames: far apart, and no snapshots in between.
	interp.update(NOW + Interpolator.STALL_SEC * 2, FRAME_SEC)
	assert_int(interp.delay_ms()).is_equal(earlier)


func test_a_snapshot_arriving_after_a_newer_one_still_sizes_the_delay() -> void:
	var fresh := Interpolator.new()
	var newer := WorldView.new()
	newer.tick = 101
	fresh.add(newer, Interpolator.time_of(newer))
	var late := WorldView.new()
	late.tick = newer.tick - 1
	var lateness := Interpolator.DEAD_ZONE_SEC * 3
	var arrived := Interpolator.time_of(newer) + lateness
	fresh.update(arrived, FRAME_SEC)
	assert_bool(fresh.add(late, arrived)).is_false()
	var earlier := fresh.delay_ms()
	fresh.update(arrived + FRAME_SEC, FRAME_SEC)
	assert_int(fresh.delay_ms()).is_greater(earlier)


func test_snapshots_queued_during_a_stall_leave_the_delay_alone() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var earlier := interp.delay_ms()
	# A tab hidden for a minute hands over what was sent as it hid.
	var back := NOW + 60.0
	interp.add(_snapshot_late_by(back, back - NOW), back)
	for i in roundi(Interpolator.TRANSIT_WINDOW_SEC / FRAME_SEC):
		interp.update(back + i * FRAME_SEC, FRAME_SEC)
	assert_int(interp.delay_ms()).is_equal(earlier)


func test_the_first_snapshot_starts_the_clock_even_after_a_stall() -> void:
	var fresh := Interpolator.new()
	fresh.update(NOW, FRAME_SEC)
	var snap := WorldView.new()
	snap.tick = 100
	fresh.add(snap, NOW + Interpolator.STALL_SEC * 2)
	assert_int(fresh.delay_ms()).is_equal(roundi(fresh.delay_sec * 1000))


func test_fixed_delay_stays_put() -> void:
	interp.fixed = true
	interp.delay_sec = 0.2
	_arrivals(NOW, 0.0)
	_run(NOW, 1.0)
	assert_int(interp.delay_ms()).is_equal(roundi(interp.delay_sec * 1000))
