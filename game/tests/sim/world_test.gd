extends "res://tests/sim/world_fixture.gd"
## The simulation's movement, swings, knockback and dummies.

const DataLoader := preload("res://shared/data_loader.gd")
const Lobby := preload("res://server/lobby.gd")


func test_moves_at_player_speed_and_faces_the_move() -> void:
	var start := _player().pos
	world.set_input(PLAYER_ID, Vector2.DOWN, 0)
	world.step()
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.DOWN * World.walk_step, Vector2.ONE * TOLERANCE)
	assert_vector(_player().facing).is_equal_approx(Vector2.DOWN, Vector2.ONE * TOLERANCE)


func test_whole_hurtbox_stays_on_the_floor() -> void:
	world.set_input(PLAYER_ID, Vector2.LEFT, 0)
	_advance(ceili(World.arena.size.x / World.walk_step))
	var left_edge := RoomShape.floor_area().position.x
	assert_float(_player().pos.x).is_equal_approx(left_edge + World.player_hurtbox.x / 2, TOLERANCE)


func test_walking_into_a_wall_at_an_angle_slides_along_it() -> void:
	_player().pos.x = RoomShape.floor_area().position.x + World.player_hurtbox.x / 2
	var start := _player().pos
	var diagonal := Vector2(-1, -1).normalized()
	world.set_input(PLAYER_ID, diagonal, 0)
	world.step()
	assert_float(_player().pos.x).is_equal_approx(start.x, TOLERANCE)
	assert_float(_player().pos.y).is_equal_approx(
			start.y + diagonal.y * World.walk_step, TOLERANCE)


func test_press_starts_a_swing_and_roots() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(World.swing_ticks)
	var pos := _player().pos
	world.set_input(PLAYER_ID, Vector2.UP, 1)
	world.step()
	assert_vector(_player().pos).is_equal(pos)
	assert_vector(_player().facing).is_equal(Vector2.RIGHT)


func test_cooldown_follows_the_swing() -> void:
	_player().swing_cooldown_ticks = 3
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(_player().swing_ticks + 1)
	assert_int(_player().state).is_equal(World.Player.State.COOLDOWN)
	assert_int(_player().state_ticks).is_equal(_player().swing_cooldown_ticks)
	# A press now is buffered and fires as the cooldown ends.
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_advance(_player().swing_cooldown_ticks)
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)


func test_stale_smaller_count_is_ignored() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 3)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	assert_int(_player().attack_count).is_equal(3)


func test_one_press_swings_once() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(World.swing_ticks * 3)
	assert_int(_player().state).is_equal(World.Player.State.IDLE)


func test_press_within_buffer_fires_when_ready() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(World.swing_ticks - World.swing_buffer_ticks + 1)
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_advance(World.swing_buffer_ticks)
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(World.swing_ticks)


func test_press_before_buffer_is_dropped() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	world.set_input(PLAYER_ID, Vector2.ZERO, 2)
	_advance(World.swing_ticks + 2)
	assert_int(_player().state).is_equal(World.Player.State.IDLE)


func test_swing_touches_in_front_not_behind() -> void:
	var front := _add_dummy(_player().pos + Vector2(World.swing_radius / 2, 0))
	var behind := _add_dummy(_player().pos - Vector2(World.swing_radius / 2, 0))
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(front.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_knockback_pushes_away_from_attacker_over_time() -> void:
	var start := _player().pos + Vector2(World.swing_radius / 2, 0)
	var d := _add_dummy(start, DummyKinds.enemy_kind)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(d.knockback.ticks).is_greater(0)
	_advance(World.knockback_ticks)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * World.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_int(d.knockback.ticks).is_zero()
	# A dummy stays where it was knocked to.
	_advance(A_WHILE)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * World.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_with_zero_ticks_is_instant() -> void:
	World.knockback_ticks = 0
	var start := _player().pos + Vector2(World.swing_radius / 2, 0)
	var d := _add_dummy(start, DummyKinds.enemy_kind)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * World.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_stops_at_the_wall() -> void:
	# Farther than the wall from anywhere.
	World.knockback_px = World.arena.size.x
	var d := _add_dummy_in_reach(DummyKinds.enemy_kind)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(World.knockback_ticks + 1)
	var right_edge := RoomShape.floor_area().end.x
	assert_float(d.pos.x).is_equal_approx(right_edge - d.size.x / 2, KNOCKBACK_TOLERANCE)


func test_reconnect_restarts_the_press_count() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 5)
	_advance(World.swing_ticks + 1)
	world.set_connected(PLAYER_ID, false)
	world.set_connected(PLAYER_ID, true)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(World.swing_ticks)


func test_disconnect_stops_the_player() -> void:
	world.set_input(PLAYER_ID, Vector2.RIGHT, 0)
	world.set_connected(PLAYER_ID, false)
	var pos := _player().pos
	world.step()
	assert_vector(_player().pos).is_equal(pos)


func test_a_world_places_its_maps_dummies_with_own_ids() -> void:
	var m := DataLoader.Map.new()
	for offset in [Vector2(-10, 0), Vector2(10, 0)]:
		var spot := DataLoader.MapDummy.new()
		spot.kind = DummyKinds.enemy_kind
		spot.offset = offset
		spot.on_hit = "effect"
		m.dummies.append(spot)
	var w := World.new(m)
	assert_int(w.dummies.size()).is_equal(m.dummies.size())
	assert_int(w.dummies[0].id).is_not_equal(w.dummies[1].id)
	for i in m.dummies.size():
		assert_int(w.dummies[i].kind).is_equal(m.dummies[i].kind)
		assert_vector(w.dummies[i].pos).is_equal(World.arena.get_center() + m.dummies[i].offset)
		assert_str(w.dummies[i].on_hit).is_equal(m.dummies[i].on_hit)


func test_ready_and_start_never_move() -> void:
	var w := World.new(DataLoader.map(Lobby.TOWN_MAP))
	var where := w.dummies.map(func(d: World.Dummy) -> Vector2: return d.pos)
	for i in A_WHILE:
		w.step()
	assert_array(w.dummies.map(func(d: World.Dummy) -> Vector2: return d.pos)).is_equal(where)


func test_dummies_take_their_kinds_attributes() -> void:
	for map_name in [Lobby.TOWN_MAP, DataLoader.run(Lobby.RUN).start]:
		for d in World.new(DataLoader.map(map_name)).dummies:
			var stats := DataLoader.dummy_stats(d.kind)
			assert_bool(d.damageable).is_equal(stats.health > 0)
			assert_int(d.health).is_equal(stats.health)
			assert_bool(d.pushed_by_swings).is_equal(stats.pushed_by_swings)
			assert_int(d.contact_damage).is_equal(stats.contact_damage)
			assert_float(d.contact_push_px).is_equal(stats.contact_push_px)
			assert_int(d.contact_push_ticks).is_equal(GameTime.ticks(stats.contact_push_sec))
			assert_int(d.fire_interval_ticks).is_equal(GameTime.ticks(stats.fire_interval_sec))
			assert_int(d.aim_lock_ticks).is_equal(GameTime.ticks(stats.aim_lock_sec))
			assert_float(d.turn_step).is_equal_approx(
					stats.turn_rate * GameTime.TICK_SEC, TOLERANCE)


func test_snapshot_reports_ids_swings_hits_and_health() -> void:
	var far := _add_dummy(_player().pos + Vector2(0, World.swing_radius * 2))
	var near := _add_dummy_in_reach(DummyKinds.ready_kind)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	var snap := world.snapshot()
	assert_int(snap.tick).is_equal(world.tick)
	assert_int(snap.players[0].swing_ticks).is_equal(_player().state_ticks)
	assert_int(snap.players[0].health).is_equal(_player().health)
	assert_int(snap.dummies[0].id).is_equal(far.id)
	assert_int(snap.dummies[1].id).is_equal(near.id)
	assert_int(snap.dummies[1].ticks_since_struck).is_zero()
	assert_int(snap.dummies[1].kind).is_equal(DummyKinds.ready_kind)


func test_same_inputs_give_the_same_game() -> void:
	# A run, so swings, contact damage and pushes are compared too.
	var a := World.new(DataLoader.map(DataLoader.run(Lobby.RUN).start))
	var b := World.new(DataLoader.map(DataLoader.run(Lobby.RUN).start))
	for w: World in [a, b]:
		w.add_player(1)
	# Ten seconds of a turning player pressing now and then.
	for i in 600:
		var move := Vector2.from_angle(i * 0.05)
		for w: World in [a, b]:
			w.set_input(1, move, i / 40)
			w.step()
	assert_str(_state_text(a)).is_equal(_state_text(b))
