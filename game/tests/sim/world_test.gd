extends "res://tests/sim/world_fixture.gd"
## The simulation's movement, swings, knockback and dummies.


func test_snap_direction() -> void:
	assert_vector(World.snap_direction(Vector2(1, 0.3))).is_equal_approx(
			Vector2.RIGHT, Vector2.ONE * TOLERANCE)
	assert_vector(World.snap_direction(Vector2(1, 1))).is_equal_approx(
			Vector2(1, 1).normalized(), Vector2.ONE * TOLERANCE)
	assert_vector(World.snap_direction(Vector2(World.MOVE_DEAD_ZONE / 2, 0))).is_equal(Vector2.ZERO)


func test_moves_at_player_speed_and_faces_the_move() -> void:
	var start := _player().pos
	world.set_input(PLAYER_ID, Vector2.DOWN, 0)
	world.step()
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.DOWN * Tuning.player_speed * World.DT, Vector2.ONE * TOLERANCE)
	assert_vector(_player().facing).is_equal_approx(Vector2.DOWN, Vector2.ONE * TOLERANCE)


func test_whole_hurtbox_stays_in_the_arena() -> void:
	world.set_input(PLAYER_ID, Vector2.LEFT, 0)
	_steps(ceili(Tuning.arena.size.x / (Tuning.player_speed * World.DT)))
	assert_float(_player().pos.x).is_equal_approx(Tuning.player_hurtbox.x / 2, TOLERANCE)


func test_press_starts_a_swing_and_roots() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)
	var pos := _player().pos
	world.set_input(PLAYER_ID, Vector2.UP, 1)
	world.step()
	assert_vector(_player().pos).is_equal(pos)
	assert_vector(_player().facing).is_equal(Vector2.RIGHT)


func test_cooldown_follows_the_swing() -> void:
	Tuning.swing_cooldown_ticks = 3
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks + 1)
	assert_int(_player().phase).is_equal(World.Phase.COOLDOWN)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_cooldown_ticks)
	# A press now is buffered and fires as the cooldown ends.
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_steps(Tuning.swing_cooldown_ticks)
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)


func test_stale_smaller_count_is_ignored() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 3)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	assert_int(_player().attack_count).is_equal(3)


func test_one_press_swings_once() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks * 3)
	assert_int(_player().phase).is_equal(World.Phase.READY)


func test_press_within_buffer_fires_when_ready() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_steps(Tuning.swing_ticks - Tuning.swing_buffer_ticks + 1)
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_steps(Tuning.swing_buffer_ticks)
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)


func test_press_before_buffer_is_dropped() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_steps(Tuning.swing_ticks + 2)
	assert_int(_player().phase).is_equal(World.Phase.READY)


func test_swing_hits_in_front_not_behind() -> void:
	var front := _add_dummy(_player().pos + Vector2(Tuning.swing_radius / 2, 0))
	var behind := _add_dummy(_player().pos - Vector2(Tuning.swing_radius / 2, 0))
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_bool(front.hit_ticks > 0).is_true()
	assert_bool(behind.hit_ticks > 0).is_false()


func test_knockback_pushes_away_from_attacker_over_time() -> void:
	var start := _player().pos + Vector2(Tuning.swing_radius / 2, 0)
	var d := _add_dummy(start, World.Kind.ENEMY)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(d.motion).is_equal(World.Motion.KNOCKED_BACK)
	_steps(Tuning.knockback_ticks)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_int(d.motion).is_equal(World.Motion.FREE)
	# A standing dummy stays where it was knocked to.
	_steps(A_WHILE)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_with_zero_ticks_is_instant() -> void:
	Tuning.knockback_ticks = 0
	var start := _player().pos + Vector2(Tuning.swing_radius / 2, 0)
	var d := _add_dummy(start, World.Kind.ENEMY)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * Tuning.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_stops_at_the_wall() -> void:
	# Farther than the wall from anywhere.
	Tuning.knockback_px = Tuning.arena.size.x
	var d := _in_reach(World.Kind.ENEMY)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_steps(Tuning.knockback_ticks + 1)
	assert_float(d.pos.x).is_equal_approx(Tuning.arena.end.x - d.size.x / 2, KNOCKBACK_TOLERANCE)


func test_reconnect_restarts_the_press_count() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 5)
	_steps(Tuning.swing_ticks + 1)
	world.set_connected(PLAYER_ID, false)
	world.set_connected(PLAYER_ID, true)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().phase).is_equal(World.Phase.SWINGING)
	assert_int(_player().phase_ticks).is_equal(Tuning.swing_ticks)


func test_disconnect_stops_the_player() -> void:
	world.set_input(PLAYER_ID, Vector2.RIGHT, 0)
	world.set_connected(PLAYER_ID, false)
	var pos := _player().pos
	world.step()
	assert_vector(_player().pos).is_equal(pos)


func test_the_lobby_has_ready_left_of_start_standing_still() -> void:
	var w := World.new(1, false, World.Layout.LOBBY)
	var kinds := w.dummies.map(func(d: World.Dummy) -> World.Kind: return d.kind)
	assert_array(kinds).contains_exactly_in_any_order([World.Kind.READY, World.Kind.START])
	var ready: World.Dummy = w.dummies[kinds.find(World.Kind.READY)]
	var start: World.Dummy = w.dummies[kinds.find(World.Kind.START)]
	assert_float(ready.pos.x).is_less(start.pos.x)
	var where := [ready.pos, start.pos]
	for i in A_WHILE:
		w.step()
	assert_array([ready.pos, start.pos]).is_equal(where)


func test_a_match_has_one_enemy_at_full_health() -> void:
	var w := World.new(1, false, World.Layout.MATCH)
	assert_int(w.enemies_left()).is_equal(1)
	assert_int(w.dummies.size()).is_equal(1)
	assert_int(w.dummies[0].health).is_equal(Tuning.enemy_health)


func test_snapshot_reports_swings_hits_and_health() -> void:
	_in_reach(World.Kind.READY)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	var snap := world.snapshot()
	assert_int(snap.tick).is_equal(world.tick)
	assert_int(snap.players[0].swing_ticks).is_equal(_player().phase_ticks)
	assert_int(snap.players[0].health).is_equal(_player().health)
	assert_bool(snap.dummies[0].hit).is_true()
	assert_int(snap.dummies[0].kind).is_equal(World.Kind.READY)


func test_same_seed_and_inputs_give_the_same_game() -> void:
	# Not the default seed, so it isn't only seed 1 that works.
	# Load dummies, so the random wandering is compared too.
	var a := World.new(7, true)
	var b := World.new(7, true)
	for w: World in [a, b]:
		w.add_player(1)
	# Ten seconds of a turning player pressing now and then.
	for i in 600:
		var move := Vector2.from_angle(i * 0.05)
		for w: World in [a, b]:
			w.set_input(1, move, i / 40)
			w.step()
	assert_str(_state(a)).is_equal(_state(b))
