extends "res://tests/sim/world_fixture.gd"
## A swing's reach: where it starts, how wide it is, and its slices in turn.


func test_a_swing_reaches_from_its_offset_not_the_center() -> void:
	_set_swing(SWING_ARC, 1, SWING_TICKS, SWING_RADIUS / 2)
	_player().facing = Direction.Cardinal.EAST
	var radius := SWING_RADIUS
	var past_center_reach := _add_unit(_player().pos + Vector2(radius * 1.25, 0))
	var behind_start := _add_unit(_player().pos - Vector2(SWING_RADIUS / 4, 0))
	_press()
	WorldSimulator.step(world)
	assert_int(past_center_reach.struck_tick).is_equal(world.tick)
	assert_int(behind_start.struck_tick).is_not_equal(world.tick)


func test_an_arc_wider_than_half_a_turn_hits_beside_not_behind() -> void:
	_set_swing(deg_to_rad(270), 1, SWING_TICKS)
	_player().facing = Direction.Cardinal.EAST
	# Far enough out that the unit behind clears the arc's straight edges.
	var reach := SWING_RADIUS * 0.75
	var beside := _add_unit(_player().pos + Vector2.from_angle(deg_to_rad(120)) * reach)
	var behind := _add_unit(_player().pos + Vector2.LEFT * reach)
	_press()
	WorldSimulator.step(world)
	assert_int(beside.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_a_sweep_hits_on_its_right_only_once_its_right_slice_is_active() -> void:
	var ticks_per_slice := 3
	world.players.clear()
	_add_armed_player(world, PLAYER_ID)
	_set_swing(PI, 3, ticks_per_slice * 3)
	_player().facing = Direction.Cardinal.EAST
	# Facing right, the player's right is down the screen.
	var right := _add_unit(_player().pos + Vector2.DOWN * SWING_RADIUS * 0.75)
	_press()
	_advance(ticks_per_slice * 2)
	assert_int(right.struck_tick).is_not_equal(world.tick)
	assert_array(world.swing_contacts).is_empty()
	_advance(1)
	assert_int(right.struck_tick).is_equal(world.tick)


func test_a_sweep_hits_a_unit_under_every_slice_once() -> void:
	_set_swing(PI, 3, SWING_TICKS)
	# Big enough to touch all three slices.
	var d := _add_unit(
			_player().pos + Vector2(SWING_RADIUS / 4, 0), Units.turret_type)
	d.collider = CircleShape2D.new()
	(d.collider as CircleShape2D).radius = SWING_RADIUS
	d.pushed_by_swings = false
	_press()
	_advance(SWING_TICKS)
	# ENEMY_HEALTH 3, less one swing_damage 1.
	assert_int(d.health).is_equal(2)
