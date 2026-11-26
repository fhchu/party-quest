extends GdUnitTestSuite
## The run the lobby plays: its rooms and its seed.

const Lobby := preload("res://server/lobby.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const RoomPlan := preload("res://sim/room_plan.gd")


func test_the_lobby_acts_on_every_on_hit_its_rooms_name() -> void:
	for room in _lobby_rooms():
		for spot in room.spots:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.TOGGLE_SHIELD]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_in_one_wall() -> void:
	for room in _lobby_rooms():
		var walls := room.doors.map(func(d: RoomPlan.DoorPlan) -> Object: return d.wall)
		for wall: Object in walls:
			assert_int(walls.count(wall)).is_equal(1)


func test_run_seed_keeps_a_set_seed_and_picks_a_new_one_otherwise() -> void:
	assert_int(WorldSimulator.run_seed(42)).is_equal(42)
	var seeds := [
			WorldSimulator.run_seed(-1), WorldSimulator.run_seed(-1), WorldSimulator.run_seed(-1)]
	assert_bool(seeds.all(func(s: int) -> bool: return s == seeds[0])).is_false()


## Town, and every room in the run.
func _lobby_rooms() -> Array[RoomPlan]:
	var out: Array[RoomPlan] = [WorldLoader.town().start]
	out.append_array(WorldLoader.run_of(0).rooms)
	return out
