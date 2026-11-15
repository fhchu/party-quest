extends GdUnitTestSuite
## The run the lobby plays: its rooms and its seed.

const Lobby := preload("res://server/lobby.gd")
const Room := preload("res://shared/data/room.gd")
const RoomGraph := preload("res://sim/room_graph.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")


func test_the_lobby_acts_on_every_on_hit_its_maps_name() -> void:
	for room in _lobby_rooms():
		for spot in room.dummies:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.START_RUN]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_on_one_wall() -> void:
	var graph := RoomGraph.new(Lobby.RUN.passages)
	for room in _lobby_rooms():
		var sides := graph.doors(room).map(func(d: RoomGraph.Door) -> int: return d.side)
		for side in sides:
			assert_int(sides.count(side)).is_equal(1)


func test_a_run_that_sets_a_seed_uses_it_and_one_that_doesnt_gets_its_own() -> void:
	var run := RunSetup.new()
	run.rng_seed = 42
	assert_int(Lobby.run_seed(run)).is_equal(42)
	run.rng_seed = -1
	var seeds := [Lobby.run_seed(run), Lobby.run_seed(run), Lobby.run_seed(run)]
	assert_bool(seeds.all(func(s: int) -> bool: return s == seeds[0])).is_false()


## Town, and every room in the run.
func _lobby_rooms() -> Array[Room]:
	var out: Array[Room] = [Lobby.TOWN, Lobby.RUN.start]
	for passage in Lobby.RUN.passages:
		out.append_array([passage.from, passage.to])
	return out
