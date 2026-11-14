extends "res://tests/sim/world_fixture.gd"
## A turret: a dummy that turns toward the nearest living player and fires
## at where they were when its aim locked.


const FIRE_INTERVAL_TICKS := 30
const AIM_LOCK_TICKS := 6
## In radians per tick: a quarter turn takes 30 ticks.
const TURN_STEP := PI / 60


## A turret straight above the player, facing it.
func _add_turret() -> World.Dummy:
	var d := _add_dummy(_player().pos + Vector2(0, -100), DummyKinds.turret_kind)
	d.attack_interval_ticks = FIRE_INTERVAL_TICKS
	d.attack_ticks_left = FIRE_INTERVAL_TICKS
	d.aim_lock_ticks = AIM_LOCK_TICKS
	d.turn_step = TURN_STEP
	d.facing = Vector2.DOWN
	return d


## Ticks until the turret, aiming at [param target], fires; -1 if it
## doesn't within [param limit].
func _ticks_to_fire(d: World.Dummy, target: World.Player, limit := A_WHILE) -> int:
	for i in limit:
		if d.step(target, [], null):
			return i + 1
	return -1


func test_it_turns_no_faster_than_its_rate() -> void:
	var d := _add_turret()
	_player().pos = d.pos + Vector2(100, 0)
	world.step()
	var turned := Vector2.DOWN.angle_to(d.facing)
	assert_float(absf(turned)).is_equal_approx(TURN_STEP, TOLERANCE)
	_advance(GameTime.TICK_RATE)
	assert_float(d.facing.angle_to(Vector2.RIGHT)).is_equal_approx(0.0, TOLERANCE)


func test_it_fires_every_interval_starting_one_interval_in() -> void:
	var d := _add_turret()
	assert_int(_ticks_to_fire(d, _player())).is_equal(FIRE_INTERVAL_TICKS)
	assert_int(_ticks_to_fire(d, _player())).is_equal(FIRE_INTERVAL_TICKS)


func test_it_aims_at_where_the_target_was_when_the_aim_locked() -> void:
	var d := _add_turret()
	_advance(FIRE_INTERVAL_TICKS - AIM_LOCK_TICKS)
	var locked_at := _player().pos
	_player().pos += Vector2(50, 0)
	_advance(AIM_LOCK_TICKS - 1)
	assert_bool(d.is_aim_locked()).is_true()
	assert_vector(d.aim_spot).is_equal(locked_at)
	assert_float(d.facing.angle_to(locked_at - d.pos)).is_equal_approx(0.0, TOLERANCE)


func test_it_targets_the_nearest_living_player_ties_to_the_lower_seat() -> void:
	var d := _add_turret()
	world.add_player(2)
	world.add_player(3)
	# 1 (dropped) and 2 are as near as each other; 3 is nearest but downed.
	_player().pos = d.pos + Vector2(100, 0)
	world.players[2].pos = d.pos + Vector2(-100, 0)
	world.players[3].pos = d.pos + Vector2(0, -10)
	world.players[3].health = 0
	world.set_connected(PLAYER_ID, false)
	_advance(GameTime.TICK_RATE)
	assert_float(d.facing.angle_to(Vector2.RIGHT)).is_equal_approx(0.0, TOLERANCE)


func test_with_nobody_alive_it_skips_the_shot() -> void:
	var d := _add_turret()
	assert_int(_ticks_to_fire(d, null, FIRE_INTERVAL_TICKS * 2)).is_equal(-1)
	assert_vector(d.facing).is_equal(Vector2.DOWN)
	assert_int(_ticks_to_fire(d, _player())).is_less_equal(FIRE_INTERVAL_TICKS)


func test_a_swing_hits_the_turned_hurtbox_not_the_upright_one() -> void:
	# Turned a quarter of a right angle, the box reaches past its upright
	# edge straight ahead, and pulls back from where its upright corners were.
	var d := _add_dummy(_player().pos + Vector2(-100, 0), DummyKinds.turret_kind)
	d.facing = Vector2.from_angle(PI / 4)
	var half := DUMMY_SIZE.x / 2
	var tip := half * sqrt(2.0)
	_player().facing = Vector2.LEFT
	# The arc's reach ends between the upright edge and the turned tip.
	_player().pos = d.pos + Vector2(World.swing_radius + (half + tip) / 2, 0)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_array(world.swing_contacts).has_size(1)


func test_contact_follows_the_turned_hurtbox() -> void:
	var d := _add_dummy(_player().pos + Vector2(-100, 0), DummyKinds.turret_kind)
	d.facing = Vector2.from_angle(PI / 4)
	var half := DUMMY_SIZE.x / 2
	# Beside where an upright corner would be: the turned box has pulled away.
	_player().pos = d.pos + Vector2(half, half) + DUMMY_SIZE / 2 - Vector2.ONE
	world.step()
	assert_int(_player().health).is_equal(World.player_max_health)
	# Just past the upright right edge, overlapping the turned tip.
	_player().pos = d.pos + Vector2(half + DUMMY_SIZE.x / 2 + 1, 0)
	world.step()
	assert_int(_player().health).is_less(World.player_max_health)


func test_a_turned_turret_keeps_its_corners_on_the_floor() -> void:
	var half := DUMMY_SIZE.x / 2
	# Upright against the right wall, then turned diagonally toward the
	# player, below it.
	var d := _add_turret()
	d.pos = Vector2(RoomShape.floor_area().end.x - half, World.arena.get_center().y)
	_player().pos = d.pos + Vector2(-100, 100)
	_advance(GameTime.TICK_RATE)
	var corners := Transform2D(d.facing.angle(), d.pos) * PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])
	for corner in corners:
		assert_bool(RoomShape.floor_area().grow(TOLERANCE).has_point(corner)).is_true()
