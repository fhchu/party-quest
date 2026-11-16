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


func test_a_run_that_sets_a_seed_uses_it_and_one_that_doesnt_gets_its_own() -> void:
	assert_int(World.run_seed(42)).is_equal(42)
	var seeds := [World.run_seed(-1), World.run_seed(-1), World.run_seed(-1)]
	assert_bool(seeds.all(func(s: int) -> bool: return s == seeds[0])).is_false()


## Town, and every room in the run.
func _lobby_rooms() -> Array[World.RoomPlan]:
	var out: Array[World.RoomPlan] = [World.WorldLoader.town().start]
	out.append_array(World.WorldLoader.first_run().rooms)
	return out
