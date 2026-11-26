extends GdUnitTestSuite
## What interpolator.gd draws between two snapshots, and its jitter estimate.

const Interpolator := preload("res://client/interpolator.gd")
const WorldView := preload("res://client/world_view.gd")

## Any time after the clock started.
const NOW := 10.0


func test_a_new_worlds_first_snapshot_replaces_the_old_world() -> void:
	var fresh := Interpolator.new()
	var old := WorldView.new()
	old.tick = 100
	var swinging := WorldView.Player.new()
	swinging.slot_ticks = PackedByteArray([5])
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
	b.players[0].slot_ticks = PackedByteArray([5, 7])
	b.dummies[0].ticks_since_struck = 0
	b.graphics_seed = a.graphics_seed + 1
	fresh.add(a, NOW)
	fresh.add(b, NOW + GameTime.TICK_SEC)
	# A quarter of the way from a to b.
	var drawn := fresh.view(NOW + fresh.delay_sec + GameTime.TICK_SEC / 4)
	assert_int(drawn.tick).is_equal(b.tick)
	assert_int(drawn.players[0].health).is_equal(b.players[0].health)
	assert_array(drawn.players[0].slot_ticks).is_equal(b.players[0].slot_ticks)
	assert_int(drawn.dummies[0].ticks_since_struck).is_equal(0)
	assert_int(drawn.graphics_seed).is_equal(b.graphics_seed)
	assert_bool(drawn.players[0].pos.is_equal_approx(
			a.players[0].pos.lerp(b.players[0].pos, 0.25))).is_true()


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
	assert_bool(is_equal_approx(drawn.dummies[0].charge_windup_ticks_left, 3.5)).is_true()
