extends GdUnitTestSuite
## The simulation rules. Balance values that a test depends on are set here
## and restored afterwards, so tuning balance.json doesn't break the tests.

const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")

var world: World
var _saved: Array


func before_test() -> void:
	_saved = [
		Tuning.swing_ticks, Tuning.swing_cooldown_ticks, Tuning.swing_buffer_ticks,
		Tuning.knockback_px, Tuning.knockback_ticks, Tuning.swing_radius,
		Tuning.swing_arc, Tuning.swing_hold_repeats, Tuning.player_speed,
	]
	Tuning.swing_ticks = 10
	Tuning.swing_cooldown_ticks = 0
	Tuning.swing_buffer_ticks = 5
	Tuning.knockback_px = 24.0
	Tuning.knockback_ticks = 6
	Tuning.swing_radius = 30.0
	Tuning.swing_arc = PI / 2
	Tuning.swing_hold_repeats = false
	Tuning.player_speed = 100.0
	world = World.new()
	world.dummies.clear()  # Tests place their own.
	world.add_player(1)


func after_test() -> void:
	Tuning.swing_ticks = _saved[0]
	Tuning.swing_cooldown_ticks = _saved[1]
	Tuning.swing_buffer_ticks = _saved[2]
	Tuning.knockback_px = _saved[3]
	Tuning.knockback_ticks = _saved[4]
	Tuning.swing_radius = _saved[5]
	Tuning.swing_arc = _saved[6]
	Tuning.swing_hold_repeats = _saved[7]
	Tuning.player_speed = _saved[8]


func _player() -> World.Player:
	return world.players[1]


func _add_dummy(pos: Vector2, target := false) -> World.Dummy:
	var d := World.Dummy.new()
	d.pos = pos
	d.size = Vector2(16, 16)
	d.target = target
	world.dummies.append(d)
	return d


func _steps(n: int) -> void:
	for i in n:
		world.step()


func test_snap8() -> void:
	assert_vector(World.snap8(Vector2(1, 0.3))).is_equal_approx(Vector2.RIGHT, Vector2.ONE * 0.001)
	assert_vector(World.snap8(Vector2(1, 1))).is_equal_approx(
			Vector2(1, 1).normalized(), Vector2.ONE * 0.001)
	assert_vector(World.snap8(Vector2(World.MOVE_DEAD_ZONE / 2, 0))).is_equal(Vector2.ZERO)


func test_moves_at_player_speed_and_faces_the_move() -> void:
	var start := _player().pos
	world.set_input(1, Vector2.DOWN, 0)
	world.step()
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.DOWN * Tuning.player_speed * World.DT, Vector2.ONE * 0.001)
	assert_vector(_player().facing).is_equal_approx(Vector2.DOWN, Vector2.ONE * 0.001)


func test_whole_hurtbox_stays_in_the_arena() -> void:
	world.set_input(1, Vector2.LEFT, 0)
	_steps(ceili(Tuning.arena.size.x / (Tuning.player_speed * World.DT)))
	assert_float(_player().pos.x).is_equal_approx(Tuning.player_hurtbox.x / 2, 0.001)


func test_press_starts_a_swing_and_roots() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().swing_ticks).is_equal(Tuning.swing_ticks)
	var pos := _player().pos
	world.set_input(1, Vector2.UP, 1)
	world.step()
	assert_vector(_player().pos).is_equal(pos)
	assert_vector(_player().facing).is_equal(Vector2.RIGHT)


func test_stale_smaller_count_is_ignored() -> void:
	world.set_input(1, Vector2.ZERO, 3)
	world.set_input(1, Vector2.ZERO, 1)
	assert_int(_player().attack_count).is_equal(3)


func test_holding_does_not_repeat() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks * 3)
	assert_int(_player().swing_ticks).is_equal(0)


func test_press_within_buffer_fires_when_ready() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks - Tuning.swing_buffer_ticks + 1)
	world.set_input(1, Vector2.ZERO, 2)
	_steps(Tuning.swing_buffer_ticks)
	assert_int(_player().swing_ticks).is_equal(Tuning.swing_ticks)


func test_press_before_buffer_is_dropped() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	world.set_input(1, Vector2.ZERO, 2)
	_steps(Tuning.swing_ticks + 2)
	assert_int(_player().swing_ticks).is_equal(0)


func test_swing_hits_in_front_not_behind() -> void:
	var front := _add_dummy(_player().pos + Vector2(Tuning.swing_radius / 2, 0))
	var behind := _add_dummy(_player().pos - Vector2(Tuning.swing_radius / 2, 0))
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	assert_bool(front.hit_ticks > 0).is_true()
	assert_bool(behind.hit_ticks > 0).is_false()


func test_knockback_pushes_away_from_attacker_over_time() -> void:
	var start := _player().pos + Vector2(Tuning.swing_radius / 2, 0)
	var d := _add_dummy(start, true)
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	_steps(Tuning.knockback_ticks)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * 0.01)
	# The target dummy stays where it was knocked to.
	_steps(120)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * 0.01)


func test_knockback_with_zero_ticks_is_instant() -> void:
	Tuning.knockback_ticks = 0
	var start := _player().pos + Vector2(Tuning.swing_radius / 2, 0)
	var d := _add_dummy(start, true)
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * 0.01)


func test_knockback_stops_at_the_wall() -> void:
	Tuning.knockback_px = Tuning.arena.size.x  # Farther than the wall from anywhere.
	var d := _add_dummy(_player().pos + Vector2(Tuning.swing_radius / 2, 0), true)
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.knockback_ticks + 1)
	assert_float(d.pos.x).is_equal_approx(Tuning.arena.end.x - d.size.x / 2, 0.01)


func test_reconnect_restarts_the_press_count() -> void:
	world.set_input(1, Vector2.ZERO, 5)
	_steps(Tuning.swing_ticks + 1)
	world.set_connected(1, false)
	world.set_connected(1, true)
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().swing_ticks).is_equal(Tuning.swing_ticks)


func test_disconnect_stops_the_player() -> void:
	world.set_input(1, Vector2.RIGHT, 0)
	world.set_connected(1, false)
	var pos := _player().pos
	world.step()
	assert_vector(_player().pos).is_equal(pos)


func test_new_world_has_a_still_target_dummy() -> void:
	var w := World.new()
	var target: World.Dummy = w.dummies.back()
	assert_bool(target.target).is_true()
	var pos := target.pos
	for i in 300:
		w.step()
	assert_vector(target.pos).is_equal(pos)


func test_snapshot_layout() -> void:
	_add_dummy(Vector2(50, 50), true)
	var snap := world.snapshot()
	assert_int(snap[0]).is_equal(world.tick)
	assert_array(snap[1][0]).has_size(5)  # [id, pos, facing, swing_ticks, connected]
	assert_array(snap[2][0]).is_equal([Vector2(50, 50), false, true])  # [pos, hit, target]


func test_same_seed_and_inputs_give_the_same_game() -> void:
	var a := World.new(7)
	var b := World.new(7)
	for w: World in [a, b]:
		w.add_player(1)
	for i in 600:
		var move := Vector2.from_angle(i * 0.05)
		for w: World in [a, b]:
			w.set_input(1, World.snap8(move), i / 40)
			w.step()
	assert_str(var_to_str(a.snapshot())).is_equal(var_to_str(b.snapshot()))
