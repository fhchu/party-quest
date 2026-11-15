extends GdUnitTestSuite
## The rooms the lobby uses.

const Lobby := preload("res://server/lobby.gd")
const Room := preload("res://shared/data/room.gd")
const RoomGraph := preload("res://sim/room_graph.gd")


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


## Town, and every room in the run.
func _lobby_rooms() -> Array[Room]:
	var out: Array[Room] = [Lobby.TOWN, Lobby.RUN.start]
	for passage in Lobby.RUN.passages:
		out.append_array([passage.from, passage.to])
	return out
