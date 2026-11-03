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
	# Tests place their own.
	world.dummies.clear()
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


## Everything the rules decide, as text, so two worlds compare exactly.
func _state(w: World) -> String:
	var parts := []
	for p: World.Player in w.players.values():
		parts.append([p.pos, p.facing, p.phase, p.phase_ticks])
	for d in w.dummies:
		parts.append([d.pos, d.hit_ticks, d.motion])
	return var_to_str(parts)


func _steps(n: int) -> void:
	for i in n:
		world.step()


func test_snap_direction() -> void:
	assert_vector(World.snap_direction(Vector2(1, 0.3))).is_equal_approx(
			Vector2.RIGHT, Vector2.ONE * 0.001)
	assert_vector(World.snap_direction(Vector2(1, 1))).is_equal_approx(
			Vector2(1, 1).normalized(), Vector2.ONE * 0.001)
	assert_vector(World.snap_direction(Vector2(World.MOVE_DEAD_ZONE / 2, 0))).is_equal(Vector2.ZERO)


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
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)
	var pos := _player().pos
	world.set_input(1, Vector2.UP, 1)
	world.step()
	assert_vector(_player().pos).is_equal(pos)
	assert_vector(_player().facing).is_equal(Vector2.RIGHT)


func test_cooldown_follows_the_swing() -> void:
	Tuning.swing_cooldown_ticks = 3
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks + 1)
	assert_int(_player().phase).is_equal(World.Phase.COOLDOWN)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_cooldown_ticks)
	# A press now is buffered and fires as the cooldown ends.
	world.set_input(1, Vector2.ZERO, 2)
	_steps(Tuning.swing_cooldown_ticks)
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)


func test_stale_smaller_count_is_ignored() -> void:
	world.set_input(1, Vector2.ZERO, 3)
	world.set_input(1, Vector2.ZERO, 1)
	assert_int(_player().attack_count).is_equal(3)


func test_one_press_swings_once() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks * 3)
	assert_int(_player().phase).is_equal(World.Phase.READY)


func test_press_within_buffer_fires_when_ready() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks - Tuning.swing_buffer_ticks + 1)
	world.set_input(1, Vector2.ZERO, 2)
	_steps(Tuning.swing_buffer_ticks)
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)


func test_press_before_buffer_is_dropped() -> void:
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	world.set_input(1, Vector2.ZERO, 2)
	_steps(Tuning.swing_ticks + 2)
	assert_int(_player().phase).is_equal(World.Phase.READY)


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
	assert_int(d.motion).is_equal(World.Motion.KNOCKED_BACK)
	_steps(Tuning.knockback_ticks)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * 0.01)
	assert_int(d.motion).is_equal(World.Motion.FREE)
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
	# Farther than the wall from anywhere.
	Tuning.knockback_px = Tuning.arena.size.x
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
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)


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


func test_snapshot_reports_swings_and_hits() -> void:
	_add_dummy(_player().pos + Vector2(Tuning.swing_radius / 2, 0), true)
	world.set_input(1, Vector2.ZERO, 1)
	world.step()
	var snap := world.snapshot()
	assert_int(snap.tick).is_equal(world.tick)
	assert_int(snap.players[0].swing_ticks).is_equal(_player().phase_ticks)
	assert_bool(snap.dummies[0].hit).is_true()
	assert_bool(snap.dummies[0].target).is_true()


func test_same_seed_and_inputs_give_the_same_game() -> void:
	var a := World.new(7)
	var b := World.new(7)
	for w: World in [a, b]:
		w.add_player(1)
	# Ten seconds of a turning player pressing now and then.
	for i in 600:
		var move := Vector2.from_angle(i * 0.05)
		for w: World in [a, b]:
			w.set_input(1, move, i / 40)
			w.step()
	assert_str(_state(a)).is_equal(_state(b))
