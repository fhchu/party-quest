extends "res://tests/sim/world_fixture.gd"
## A world built to replace another.


func test_a_new_world_keeps_the_tick_and_spends_carried_presses() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 3)
	world.step()
	var fresh := World.new(null, world)
	fresh.add_player(PLAYER_ID)
	fresh.set_input(PLAYER_ID, Vector2.ZERO, 3)
	fresh.step()
	assert_int(fresh.tick).is_equal(world.tick + 1)
	assert_int(fresh.players[PLAYER_ID].state).is_equal(World.Player.State.IDLE)
	fresh.set_input(PLAYER_ID, Vector2.ZERO, 4)
	fresh.step()
	assert_int(fresh.players[PLAYER_ID].state).is_equal(World.Player.State.SWINGING)
