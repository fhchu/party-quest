extends GdUnitTestSuite
## The run the lobby plays: its rooms and its seed.

const Lobby := preload("res://server/lobby.gd")
const Room := preload("res://shared/data/room.gd")
const RoomGraph := preload("res://sim/room_graph.gd")
const World := preload("res://sim/world.gd")


func test_the_lobby_acts_on_every_on_hit_its_maps_name() -> void:
	for room in _lobby_rooms():
		for spot in room.dummies:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.START_RUN]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_on_one_wall() -> void:
	var graph := RoomGraph.new(World.WorldLoader.RUN.passages)
	for room in _lobby_rooms():
		var sides := graph.doors(room).map(func(d: RoomGraph.Door) -> int: return d.side)
		for side in sides:
			assert_int(sides.count(side)).is_equal(1)


func test_a_run_that_sets_a_seed_uses_it_and_one_that_doesnt_gets_its_own() -> void:
	assert_int(World.run_seed(42)).is_equal(42)
	var seeds := [World.run_seed(-1), World.run_seed(-1), World.run_seed(-1)]
	assert_bool(seeds.all(func(s: int) -> bool: return s == seeds[0])).is_false()


## Town, and every room in the run.
func _lobby_rooms() -> Array[Room]:
	var run := World.WorldLoader.RUN
	var out: Array[Room] = [World.WorldLoader.TOWN, run.start]
	for passage in run.passages:
		out.append_array([passage.from, passage.to])
	return out
