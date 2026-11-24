extends "res://tests/sim/world_fixture.gd"
## A swing's reach: where it starts, how wide it is, and its slices in turn.


func test_a_swing_reaches_from_its_offset_not_the_center() -> void:
	WorldState.data.swing_offset = WorldState.data.swing_radius / 2
	var radius := WorldState.data.swing_radius
	var past_center_reach := _add_dummy(_player().pos + Vector2(radius * 1.25, 0))
	var behind_start := _add_dummy(_player().pos - Vector2(WorldState.data.swing_radius / 4, 0))
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(past_center_reach.struck_tick).is_equal(world.tick)
	assert_int(behind_start.struck_tick).is_not_equal(world.tick)


func test_an_arc_wider_than_half_a_turn_hits_beside_not_behind() -> void:
	_set_swing(deg_to_rad(270), WorldState.data.swing_slices, WorldState.data.swing_ticks)
	# Far enough out that the dummy behind clears the arc's straight edges.
	var reach := WorldState.data.swing_radius * 0.75
	var beside := _add_dummy(_player().pos + Vector2.from_angle(deg_to_rad(120)) * reach)
	var behind := _add_dummy(_player().pos + Vector2.LEFT * reach)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(beside.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_a_sweep_hits_on_its_right_only_once_its_right_slice_is_active() -> void:
	var ticks_per_slice := 3
	_set_swing(PI, 3, ticks_per_slice * 3)
	world.players.clear()
	WorldSimulator.add_player(world, PLAYER_ID)
	_player().facing = Direction.Cardinal.EAST
	# Facing right, the player's right is down the screen.
	var right := _add_dummy(_player().pos + Vector2.DOWN * WorldState.data.swing_radius * 0.75)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(ticks_per_slice * 2)
	assert_int(right.struck_tick).is_not_equal(world.tick)
	assert_array(world.swing_contacts).is_empty()
	_advance(1)
	assert_int(right.struck_tick).is_equal(world.tick)


func test_a_sweep_hits_a_dummy_under_every_slice_once() -> void:
	_set_swing(PI, 3, WorldState.data.swing_ticks)
	# Big enough to touch all three slices.
	var d := _add_dummy(
			_player().pos + Vector2(WorldState.data.swing_radius / 4, 0), DummyKinds.turret_kind)
	d.collider = CircleShape2D.new()
	(d.collider as CircleShape2D).radius = WorldState.data.swing_radius
	d.pushed_by_swings = false
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 1)
	_advance(WorldState.data.swing_ticks)
	assert_int(d.health).is_equal(ENEMY_HEALTH - WorldState.data.swing_damage)
