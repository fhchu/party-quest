extends "res://tests/sim/world_fixture.gd"
## The simulation's movement, swings, knockback and dummies.

const Room := preload("res://shared/data/room.gd")
const RoomDummy := preload("res://shared/data/room_dummy.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")


func test_moves_at_player_speed_and_faces_the_move() -> void:
	_player().facing = Direction.Cardinal.EAST
	var start := _player().pos
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.DOWN, 0)
	WorldSimulator.step(world)
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.DOWN * _player().walk_step, Vector2.ONE * TOLERANCE)
	assert_int(_player().facing).is_equal(Direction.Cardinal.SOUTH)


func test_whole_hurtbox_stays_on_the_floor() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.LEFT, 0)
	_advance(ceili(WorldState.data.arena.size.x / _player().walk_step))
	var left_edge := RoomShape.floor_area().position.x
	assert_float(_player().pos.x).is_equal_approx(left_edge + PLAYER_SIZE.x / 2, TOLERANCE)


func test_walking_into_a_wall_at_an_angle_slides_along_it() -> void:
	_player().pos.x = RoomShape.floor_area().position.x + PLAYER_SIZE.x / 2
	var start := _player().pos
	var diagonal := Vector2(-1, -1).normalized()
	WorldSimulator.set_input(world, PLAYER_ID, diagonal, 0)
	WorldSimulator.step(world)
	assert_float(_player().pos.x).is_equal_approx(start.x, TOLERANCE)
	assert_float(_player().pos.y).is_equal_approx(
			start.y + diagonal.y * _player().walk_step, TOLERANCE)


func test_press_starts_a_swing_and_roots() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(_player().state).is_equal(Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(WorldState.data.swing_ticks)
	var pos := _player().pos
	_player().facing = Direction.Cardinal.EAST
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.UP, 1)
	WorldSimulator.step(world)
	assert_vector(_player().pos).is_equal(pos)
	assert_int(_player().facing).is_equal(Direction.Cardinal.EAST)


func test_stale_smaller_count_is_ignored() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 3)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	assert_int(_player().attack_count).is_equal(3)


func test_one_press_swings_once() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(WorldState.data.swing_ticks * 3)
	assert_int(_player().state).is_equal(Player.State.IDLE)


func test_press_within_buffer_fires_when_ready() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(WorldState.data.swing_ticks - _player().swing_buffer_ticks + 1)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 2)
	_advance(_player().swing_buffer_ticks)
	assert_int(_player().state).is_equal(Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(WorldState.data.swing_ticks)


func test_press_before_buffer_is_dropped() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 2)
	_advance(WorldState.data.swing_ticks + 2)
	assert_int(_player().state).is_equal(Player.State.IDLE)


func test_swing_touches_in_front_not_behind() -> void:
	_player().facing = Direction.Cardinal.EAST
	var front := _add_dummy(_player().pos + Vector2(WorldState.data.swing_radius / 2, 0))
	var behind := _add_dummy(_player().pos - Vector2(WorldState.data.swing_radius / 2, 0))
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(front.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_knockback_pushes_away_from_attacker_over_time() -> void:
	var start := _player().pos + Vector2(WorldState.data.swing_radius / 2, 0)
	var d := _add_dummy(start, DummyKinds.turret_kind)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(d.knockback.ticks).is_greater(0)
	_advance(WorldState.data.knockback_ticks)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * WorldState.data.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_int(d.knockback.ticks).is_zero()
	# A dummy stays where it was knocked to.
	_advance(A_WHILE)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * WorldState.data.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_with_zero_ticks_is_instant() -> void:
	WorldState.data.knockback_ticks = 0
	var start := _player().pos + Vector2(WorldState.data.swing_radius / 2, 0)
	var d := _add_dummy(start, DummyKinds.turret_kind)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_vector(d.pos).is_equal_approx(
			start + Vector2.RIGHT * WorldState.data.knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_stops_at_the_wall() -> void:
	# Farther than the wall from anywhere.
	WorldState.data.knockback_px = WorldState.data.arena.size.x
	var d := _add_dummy_in_reach(DummyKinds.turret_kind)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(WorldState.data.knockback_ticks + 1)
	var right_edge := RoomShape.floor_area().end.x
	assert_float(d.pos.x).is_equal_approx(right_edge - DUMMY_SIZE.x / 2, KNOCKBACK_TOLERANCE)


func test_reconnect_restarts_the_press_count() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 5)
	_advance(WorldState.data.swing_ticks + 1)
	WorldSimulator.set_connected(world, PLAYER_ID, false)
	WorldSimulator.set_connected(world, PLAYER_ID, true)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(_player().state).is_equal(Player.State.SWINGING)
	assert_int(_player().state_ticks).is_equal(WorldState.data.swing_ticks)


func test_disconnect_stops_the_player() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.RIGHT, 0)
	WorldSimulator.set_connected(world, PLAYER_ID, false)
	var pos := _player().pos
	WorldSimulator.step(world)
	assert_vector(_player().pos).is_equal(pos)


func test_a_world_places_its_maps_dummies_with_own_ids() -> void:
	var m := Room.new()
	for offset in [Vector2(-10, 0), Vector2(10, 0)]:
		var spot := RoomDummy.new()
		spot.kind = DummyKinds.TURRET
		spot.offset = offset
		spot.on_hit = "effect"
		m.dummies.append(spot)
	var w := WorldSimulator.start(WorldLoader.run_plan(m))
	assert_int(w.dummies.size()).is_equal(m.dummies.size())
	assert_int(w.dummies[0].id).is_not_equal(w.dummies[1].id)
	for i in m.dummies.size():
		assert_int(w.dummies[i].kind).is_equal(DummyKinds.turret_kind)
		var expected := WorldState.data.arena.get_center() + m.dummies[i].offset
		assert_vector(w.dummies[i].pos).is_equal(expected)
		assert_str(w.dummies[i].on_hit).is_equal(m.dummies[i].on_hit)


func test_the_snapshot_reports_each_dummys_id_kind_and_strike() -> void:
	var far := _add_dummy(_player().pos + Vector2(0, WorldState.data.swing_radius * 2),
			DummyKinds.charger_kind)
	var near := _add_dummy_in_reach(DummyKinds.turret_kind)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	var snap := WorldSnapshot.of(world)
	assert_int(snap.tick).is_equal(world.tick)
	assert_int(snap.dummies[0].id).is_equal(far.id)
	assert_int(snap.dummies[0].kind).is_equal(DummyKinds.charger_kind)
	assert_int(snap.dummies[1].id).is_equal(near.id)
	assert_int(snap.dummies[1].kind).is_equal(DummyKinds.turret_kind)
	assert_int(snap.dummies[1].ticks_since_struck).is_zero()


func test_the_snapshot_counts_a_swing_down_a_tick_at_a_time() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(3)
	var swing_ticks := WorldSnapshot.of(world).players[0].swing_ticks
	assert_int(swing_ticks).is_equal(WorldState.data.swing_ticks - 2)


func test_the_snapshot_reports_a_players_health() -> void:
	_player().health = 1
	assert_int(WorldSnapshot.of(world).players[0].health).is_equal(1)


func test_the_same_seed_and_inputs_give_the_same_game() -> void:
	var a := _world_choosing_at_random(1)
	var b := _world_choosing_at_random(1)
	var reseeded := _world_choosing_at_random(2)
	# Ten seconds of a turning player pressing now and then.
	for i in 600:
		var move := Vector2.from_angle(i * 0.05)
		for w: WorldState in [a, b, reseeded]:
			WorldSimulator.set_input(w, PLAYER_ID, move, floori(i / 40.0))
			WorldSimulator.step(w)
	assert_str(_state_text(a)).is_equal(_state_text(b))
	# Otherwise the seed changed nothing, and the match above proves nothing.
	assert_str(_state_text(reseeded)).is_not_equal(_state_text(a))


## A world seeded [param rng_seed] with one player and an enemy that picks
## between a shot and a charge at random each time.
func _world_choosing_at_random(rng_seed: int) -> WorldState:
	world = WorldSimulator.start()
	world.rng.seed = rng_seed
	WorldSimulator.add_player(world, PLAYER_ID)
	var d := _add_dummy(_player().pos + Vector2(100, 0), DummyKinds.turret_kind)
	d.attack_interval_ticks = 20
	d.attack_ticks_left = 20
	d.turn_step = PI / 30
	var fire := Fire.new()
	fire.aim_lock_ticks = 3
	fire.step = 4.0
	fire.radius = 2.0
	fire.damage = 1
	var charge := Charge.new()
	charge.aim_lock_ticks = 3
	charge.step = 4.0
	charge.length = 48.0
	d.charge = charge
	d.attacks.assign([fire, charge])
	d.weights = PackedFloat32Array([1.0, 1.0])
	d.attack_rule = AttackChoice.Rule.WEIGHTED_RANDOM
	return world
