extends "res://tests/sim/world_fixture.gd"
## A world built to replace another.


func test_a_new_world_keeps_the_tick_and_spends_carried_presses() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, 3)
	WorldSimulator.step(world)
	var fresh := WorldSimulator.start(null, world)
	WorldSimulator.add_player(fresh, PLAYER_ID)
	WorldSimulator.set_input(fresh, PLAYER_ID, Vector2.ZERO, 3)
	WorldSimulator.step(fresh)
	assert_int(fresh.tick).is_equal(world.tick + 1)
	assert_int(fresh.players[PLAYER_ID].state).is_equal(World.Player.State.IDLE)
	WorldSimulator.set_input(fresh, PLAYER_ID, Vector2.ZERO, 4)
	WorldSimulator.step(fresh)
	assert_int(fresh.players[PLAYER_ID].state).is_equal(World.Player.State.SWINGING)


func test_a_new_world_tells_clients_its_layout_is_new() -> void:
	var fresh := WorldSimulator.start(null, world)
	var old_layout := WorldSnapshot.of(world).layout_number
	assert_int(WorldSnapshot.of(fresh).layout_number).is_not_equal(old_layout)
