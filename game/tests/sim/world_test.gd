extends "res://tests/sim/world_fixture.gd"
## The simulation's movement, swings, knockback and dummies.

const Room := preload("res://shared/data/room.gd")
const RoomDummy := preload("res://shared/data/room_dummy.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")


func test_moves_at_player_speed_and_faces_the_move() -> void:
	_player().facing = Direction.Cardinal.EAST
	var start := _player().pos
	_steer(Vector2.DOWN)
	WorldSimulator.step(world)
	# walk_step 4
	assert_vector(_player().pos).is_equal_approx(start + Vector2(0, 4), Vector2.ONE * 0.001)
	assert_int(_player().facing).is_equal(Direction.Cardinal.SOUTH)


func test_whole_hurtbox_stays_on_the_floor() -> void:
	_steer(Vector2.LEFT)
	# Far enough to cross the whole arena.
	_advance(ceili(WorldState.data.arena.size.x / _player().walk_step))
	var left_edge := RoomShape.floor_area().position.x
	# Half of PLAYER_SIZE.
	assert_float(_player().pos.x).is_equal_approx(left_edge + 8.0, 0.001)


func test_walking_into_a_wall_at_an_angle_slides_along_it() -> void:
	# Against the west wall.
	_player().pos.x = RoomShape.floor_area().position.x + PLAYER_SIZE.x / 2
	var start := _player().pos
	_steer(Vector2(-1, -1).normalized())
	WorldSimulator.step(world)
	assert_float(_player().pos.x).is_equal_approx(start.x, 0.001)
	# The diagonal's share of walk_step 4: 4 * sin(45°).
	assert_float(_player().pos.y).is_equal_approx(start.y - 2.828, 0.001)


func test_a_swing_roots_the_player() -> void:
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()
	var pos := _player().pos
	_player().facing = Direction.Cardinal.EAST
	_steer(Vector2.UP)
	WorldSimulator.step(world)
	assert_vector(_player().pos).is_equal(pos)
	assert_int(_player().facing).is_equal(Direction.Cardinal.EAST)


func test_a_swing_lasts_its_ticks() -> void:
	_press()
	_advance(SWING_TICKS)
	assert_bool(_is_swinging()).is_true()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_false()


func test_a_swing_started_as_one_ends_leaves_only_its_own_hit_area() -> void:
	_press()
	_advance(SWING_TICKS)
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()
	assert_array(world.hit_areas).has_size(1)


func test_new_items_mid_swing_end_what_it_hits_with() -> void:
	_press()
	WorldSimulator.step(world)
	assert_array(world.hit_areas).has_size(1)
	_set_swing(SWING_ARC, 1, SWING_TICKS)
	WorldSimulator.step(world)
	assert_array(world.hit_areas).is_empty()


func test_swing_touches_in_front_not_behind() -> void:
	_player().facing = Direction.Cardinal.EAST
	var front := _add_dummy(_player().pos + Vector2(SWING_RADIUS / 2, 0))
	var behind := _add_dummy(_player().pos - Vector2(SWING_RADIUS / 2, 0))
	_press()
	WorldSimulator.step(world)
	assert_int(front.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_knockback_pushes_away_from_attacker_over_time() -> void:
	var start := _player().pos + Vector2(SWING_RADIUS / 2, 0)
	var d := _add_dummy(start, DummyKinds.turret_kind)
	_press()
	WorldSimulator.step(world)
	assert_int(d.knockback.ticks).is_greater(0)
	# knockback_ticks 6, knockback_px 24
	_advance(6)
	assert_vector(d.pos).is_equal_approx(start + Vector2(24, 0), Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_int(d.knockback.ticks).is_zero()
	# A dummy stays where it was knocked to.
	_advance(A_WHILE)
	assert_vector(d.pos).is_equal_approx(start + Vector2(24, 0), Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_with_zero_ticks_is_instant() -> void:
	WorldState.data.knockback_ticks = 0
	var start := _player().pos + Vector2(SWING_RADIUS / 2, 0)
	var d := _add_dummy(start, DummyKinds.turret_kind)
	_press()
	WorldSimulator.step(world)
	# knockback_px 24
	assert_vector(d.pos).is_equal_approx(start + Vector2(24, 0), Vector2.ONE * KNOCKBACK_TOLERANCE)


func test_knockback_stops_at_the_wall() -> void:
	# Farther than the wall from anywhere.
	WorldState.data.knockback_px = WorldState.data.arena.size.x
	var d := _add_dummy_in_reach(DummyKinds.turret_kind)
	_press()
	_advance(A_WHILE)
	var right_edge := RoomShape.floor_area().end.x
	# Half of DUMMY_SIZE.
	assert_float(d.pos.x).is_equal_approx(right_edge - 8.0, KNOCKBACK_TOLERANCE)


func test_a_reconnect_drops_unhandled_presses() -> void:
	_press()
	WorldSimulator.set_connected(world, PLAYER_ID, false)
	WorldSimulator.set_connected(world, PLAYER_ID, true)
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_false()


func test_disconnect_stops_the_player() -> void:
	_steer(Vector2.RIGHT)
	WorldSimulator.set_connected(world, PLAYER_ID, false)
	var pos := _player().pos
	WorldSimulator.step(world)
	assert_vector(_player().pos).is_equal(pos)


func test_a_world_places_its_maps_dummies_with_own_ids() -> void:
	var m := Room.new()
	m.dummies.append(_spot(DummyKinds.TURRET, Vector2(-10, 0), "left"))
	m.dummies.append(_spot(DummyKinds.CHARGER, Vector2(10, 0), "right"))
	var w := WorldSimulator.start(WorldLoader.run_plan(m))
	var center := WorldState.data.arena.get_center()
	assert_int(w.dummies.size()).is_equal(2)
	assert_int(w.dummies[0].id).is_not_equal(w.dummies[1].id)
	assert_int(w.dummies[0].kind).is_equal(DummyKinds.turret_kind)
	assert_vector(w.dummies[0].pos).is_equal(center + Vector2(-10, 0))
	assert_str(w.dummies[0].on_hit).is_equal("left")
	assert_int(w.dummies[1].kind).is_equal(DummyKinds.charger_kind)
	assert_vector(w.dummies[1].pos).is_equal(center + Vector2(10, 0))
	assert_str(w.dummies[1].on_hit).is_equal("right")


func test_the_snapshot_reports_each_dummys_id_kind_and_strike() -> void:
	var far := _add_dummy(_player().pos + Vector2(0, SWING_RADIUS * 2),
			DummyKinds.charger_kind)
	var near := _add_dummy_in_reach(DummyKinds.turret_kind)
	_press()
	WorldSimulator.step(world)
	var snap := WorldSnapshot.of(world)
	assert_int(snap.tick).is_equal(world.tick)
	assert_int(snap.dummies[0].id).is_equal(far.id)
	assert_int(snap.dummies[0].kind).is_equal(DummyKinds.charger_kind)
	assert_int(snap.dummies[1].id).is_equal(near.id)
	assert_int(snap.dummies[1].kind).is_equal(DummyKinds.turret_kind)
	assert_int(snap.dummies[1].ticks_since_struck).is_zero()


func test_the_snapshot_counts_a_swing_up_a_tick_at_a_time() -> void:
	_press()
	_advance(3)
	assert_int(WorldSnapshot.of(world).players[0].slot_ticks[SWORD_INPUT]).is_equal(3)


func test_the_snapshot_reports_a_players_health() -> void:
	_player().health = 1
	assert_int(WorldSnapshot.of(world).players[0].health).is_equal(1)


func test_the_same_seed_and_inputs_give_the_same_game() -> void:
	var a := _world_choosing_at_random(1)
	var b := _world_choosing_at_random(1)
	var reseeded := _world_choosing_at_random(2)
	_play(a)
	_play(b)
	_play(reseeded)
	assert_str(_state_text(a)).is_equal(_state_text(b))
	# Otherwise the seed changed nothing, and the match above proves nothing.
	assert_str(_state_text(reseeded)).is_not_equal(_state_text(a))


func _spot(kind: DummyKind, offset: Vector2, on_hit: String) -> RoomDummy:
	var out := RoomDummy.new()
	out.kind = kind
	out.offset = offset
	out.on_hit = on_hit
	return out


## Ten seconds of a turning player pressing now and then.
func _play(w: WorldState) -> void:
	for i in 600:
		var presses := PackedByteArray([1 if i % 40 == 0 else 0])
		WorldSimulator.set_input(w, PLAYER_ID, Vector2.from_angle(i * 0.05), presses, 0)
		WorldSimulator.step(w)


## A world seeded [param rng_seed] with one player and an enemy that picks
## between a shot and a charge at random each time.
func _world_choosing_at_random(rng_seed: int) -> WorldState:
	world = WorldSimulator.start()
	world.rng.seed = rng_seed
	_add_armed_player(world, PLAYER_ID)
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
