extends "res://tests/sim/world_fixture.gd"
## A world built to replace another.

const WorldSnapshot := preload("res://sim/world_snapshot.gd")


func test_a_new_world_keeps_the_tick() -> void:
	WorldSimulator.step(world)
	var fresh := WorldSimulator.start(null, world)
	WorldSimulator.step(fresh)
	assert_int(fresh.tick).is_equal(world.tick + 1)


func test_a_new_world_tells_clients_its_layout_is_new() -> void:
	var fresh := WorldSimulator.start(null, world)
	var old_layout := WorldSnapshot.of(world).layout_number
	assert_int(WorldSnapshot.of(fresh).layout_number).is_not_equal(old_layout)
