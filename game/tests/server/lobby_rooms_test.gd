extends GdUnitTestSuite
## The run the lobby plays: its rooms and its seed.

const Lobby := preload("res://server/lobby.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const RoomPlan := preload("res://sim/room_plan.gd")


func test_the_lobby_acts_on_every_on_hit_its_rooms_name() -> void:
	var known := ["", Lobby.TOGGLE_READY, Lobby.TOGGLE_SHIELD]
	var unknown := _on_hits().filter(func(on_hit: String) -> bool: return on_hit not in known)
	assert_array(unknown).is_empty()


func test_no_room_in_the_run_has_two_doors_in_one_wall() -> void:
	for room in _lobby_rooms():
		var walls := room.doors.map(func(d: RoomPlan.DoorPlan) -> Object: return d.wall)
		for wall: Object in walls:
			assert_int(walls.count(wall)).override_failure_message(
					"a room has two doors in one wall").is_equal(1)


func test_run_seed_keeps_a_set_seed_and_picks_a_new_one_otherwise() -> void:
	assert_int(WorldSimulator.run_seed(42)).is_equal(42)
	var a := WorldSimulator.run_seed(-1)
	var b := WorldSimulator.run_seed(-1)
	var c := WorldSimulator.run_seed(-1)
	assert_array([a, b, c]).is_not_equal([a, a, a])


## Every dummy's on_hit in [method _lobby_rooms].
func _on_hits() -> Array[String]:
	var out: Array[String] = []
	for room in _lobby_rooms():
		for spot in room.spots:
			out.append(spot.on_hit)
	return out


## Town, and every room in the run.
func _lobby_rooms() -> Array[RoomPlan]:
	var out: Array[RoomPlan] = [WorldLoader.town().start]
	out.append_array(WorldLoader.first_run().rooms)
	return out
