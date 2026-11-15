extends "res://tests/sim/world_fixture.gd"
## A swing's reach: where it starts, how wide it is, and its slices in turn.


func test_a_swing_reaches_from_its_offset_not_the_center() -> void:
	World.swing_offset = World.swing_radius / 2
	var past_center_reach := _add_dummy(_player().pos + Vector2(World.swing_radius * 1.25, 0))
	var behind_start := _add_dummy(_player().pos - Vector2(World.swing_radius / 4, 0))
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(past_center_reach.struck_tick).is_equal(world.tick)
	assert_int(behind_start.struck_tick).is_not_equal(world.tick)


func test_an_arc_wider_than_half_a_turn_hits_beside_not_behind() -> void:
	World.swing_arc = deg_to_rad(270)
	# Far enough out that the dummy behind clears the arc's straight edges.
	var reach := World.swing_radius * 0.75
	var beside := _add_dummy(_player().pos + Vector2.from_angle(deg_to_rad(120)) * reach)
	var behind := _add_dummy(_player().pos + Vector2.LEFT * reach)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(beside.struck_tick).is_equal(world.tick)
	assert_int(behind.struck_tick).is_not_equal(world.tick)


func test_a_sweep_hits_on_its_right_only_once_its_right_slice_is_active() -> void:
	World.swing_arc = PI
	World.swing_slices = 3
	var ticks_per_slice := 3
	World.swing_ticks = ticks_per_slice * World.swing_slices
	world.players.clear()
	world.add_player(PLAYER_ID)
	_player().facing = Vector2.RIGHT
	# Facing right, the player's right is down the screen.
	var right := _add_dummy(_player().pos + Vector2.DOWN * World.swing_radius * 0.75)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(ticks_per_slice * 2)
	assert_int(right.struck_tick).is_not_equal(world.tick)
	assert_array(world.swing_contacts).is_empty()
	_advance(1)
	assert_int(right.struck_tick).is_equal(world.tick)


func test_a_sweep_hits_a_dummy_under_every_slice_once() -> void:
	World.swing_arc = PI
	World.swing_slices = 3
	# Big enough to touch all three slices.
	var d := _add_dummy(_player().pos + Vector2(World.swing_radius / 4, 0), DummyKinds.turret_kind)
	d.collider = CircleShape2D.new()
	(d.collider as CircleShape2D).radius = World.swing_radius
	d.pushed_by_swings = false
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	_advance(World.swing_ticks)
	assert_int(d.health).is_equal(ENEMY_HEALTH - World.swing_damage)
