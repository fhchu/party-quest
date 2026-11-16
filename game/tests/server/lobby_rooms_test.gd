extends GdUnitTestSuite
## The run the lobby plays: its rooms and its seed.

const Lobby := preload("res://server/lobby.gd")
const World := preload("res://sim/world.gd")


func test_the_lobby_acts_on_every_on_hit_its_rooms_name() -> void:
	for room in _lobby_rooms():
		for spot in room.spots:
			assert_array(["", Lobby.TOGGLE_READY]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_in_one_wall() -> void:
	for room in _lobby_rooms():
		var walls := room.doors.map(func(d: World.RoomPlan.DoorPlan) -> Object: return d.wall)
		for wall: Object in walls:
			assert_int(walls.count(wall)).is_equal(1)


func test_run_seed_keeps_a_set_seed_and_picks_a_new_one_otherwise() -> void:
	assert_int(World.run_seed(42)).is_equal(42)
	var seeds := [World.run_seed(-1), World.run_seed(-1), World.run_seed(-1)]
	assert_bool(seeds.all(func(s: int) -> bool: return s == seeds[0])).is_false()


func test_the_run_uses_the_seed_its_data_sets() -> void:
	var rng_seed := World.WorldLoader.first_run().rng_seed
	assert_int(rng_seed).is_greater_equal(0)
	assert_int(World.run(null).rng.seed).is_equal(rng_seed)


## Town, and every room in the run.
func _lobby_rooms() -> Array[World.RoomPlan]:
	var out: Array[World.RoomPlan] = [World.WorldLoader.town().start]
	out.append_array(World.WorldLoader.first_run().rooms)
	return out
