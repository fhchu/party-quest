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


func test_steady_connection_settles_one_interval_plus_margin_behind() -> void:
	# Far enough from the target to be outside the dead zone.
	interp._render_offset = interp._clock_offset - Interpolator.MAX_DELAY_SEC
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var expected := (GameTime.TICK_SEC + Interpolator.MARGIN_SEC) * 1000
	assert_int(interp.delay_ms()).is_equal(roundi(expected))


func test_a_target_inside_the_dead_zone_leaves_the_delay_alone() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var earlier := interp._render_offset
	_arrivals(NOW, Interpolator.DEAD_ZONE_SEC / 2)
	_run(NOW, 1.0)
	assert_float(interp._render_offset).is_equal(earlier)


func test_a_target_past_the_dead_zone_is_reached_exactly() -> void:
	_arrivals(NOW, 0.0)
	_settle(NOW)
	var later := Interpolator.DEAD_ZONE_SEC * 4
	_arrivals(NOW, later)
	_settle(NOW)
	var expected := (later + GameTime.TICK_SEC + Interpolator.MARGIN_SEC) * 1000
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
	# Twice what it can shrink in a second.
	_arrivals(NOW, Interpolator.FALL * 2)
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
	interp.update(NOW + Interpolator.MAX_DELAY_SEC * 2, FRAME_SEC)
	assert_int(interp.delay_ms()).is_equal(roundi(Interpolator.MAX_DELAY_SEC * 1000))


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


func test_a_new_worlds_first_snapshot_replaces_the_old_world() -> void:
	var fresh := Interpolator.new()
	var old := WorldView.new()
	old.tick = 100
	var swinging := WorldView.Player.new()
	swinging.swing_ticks = 5
	old.players.append(swinging)
	fresh.add(old, NOW)
	var next := WorldView.new()
	next.tick = old.tick + 1
	next.layout_number = old.layout_number + 1
	fresh.add(next, NOW + GameTime.TICK_SEC)
	# Long before the new snapshot's time: without the reset, the old world
	# (and its swing) would be drawn here.
	var drawn := fresh.view(NOW - 1.0)
	assert_int(drawn.layout_number).is_equal(next.layout_number)
	assert_array(drawn.players).is_empty()


func test_early_in_a_blend_everything_but_motion_comes_from_the_newer_snapshot() -> void:
	var fresh := Interpolator.new()
	var a := WorldView.new()
	a.tick = 100
	var b := WorldView.new()
	b.tick = a.tick + 1
	for snap in [a, b]:
		var p := WorldView.Player.new()
		p.pos = Vector2(snap.tick, 0)
		snap.players.append(p)
		snap.dummies.append(WorldView.Dummy.new())
	b.players[0].health = a.players[0].health - 1
	b.players[0].swing_ticks = 5
	b.dummies[0].ticks_since_struck = 0
	b.graphics_seed = a.graphics_seed + 1
	fresh.add(a, NOW)
	fresh.add(b, NOW + GameTime.TICK_SEC)
	# A quarter of the way from a to b.
	var drawn := fresh.view(NOW + fresh.delay_sec + GameTime.TICK_SEC / 4)
	assert_int(drawn.tick).is_equal(b.tick)
	assert_int(drawn.players[0].health).is_equal(b.players[0].health)
	assert_int(drawn.players[0].swing_ticks).is_equal(b.players[0].swing_ticks)
	assert_int(drawn.dummies[0].ticks_since_struck).is_equal(0)
	assert_int(drawn.graphics_seed).is_equal(b.graphics_seed)
	assert_vector(drawn.players[0].pos).is_equal_approx(
			a.players[0].pos.lerp(b.players[0].pos, 0.25), Vector2.ONE * 0.01)


func test_dummies_blend_with_their_own_earlier_position() -> void:
	var fresh := Interpolator.new()
	var a := WorldView.new()
	a.tick = 100
	var b := WorldView.new()
	b.tick = a.tick + 1
	for id in [1, 2]:
		var d := WorldView.Dummy.new()
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
		var snap := WorldView.new()
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


func test_a_charge_windup_held_in_both_snapshots_blends() -> void:
	var fresh := Interpolator.new()
	var a := WorldView.new()
	a.tick = 100
	var b := WorldView.new()
	b.tick = a.tick + 1
	for snap in [a, b]:
		snap.dummies.append(WorldView.Dummy.new())
	a.dummies[0].charge_windup_ticks_left = 4
	b.dummies[0].charge_windup_ticks_left = 3
	fresh.add(a, NOW)
	fresh.add(b, NOW + GameTime.TICK_SEC)
	var drawn := fresh.view(NOW + fresh.delay_sec + 0.5 / GameTime.TICK_RATE)
	assert_float(drawn.dummies[0].charge_windup_ticks_left).is_equal_approx(3.5, 0.01)
