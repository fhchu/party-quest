extends GdUnitTestSuite
## The maps the lobby uses.

const Lobby := preload("res://server/lobby.gd")
const Map := preload("res://shared/data/map.gd")
const RoomGraph := preload("res://sim/room_graph.gd")


func test_the_lobby_acts_on_every_on_hit_its_maps_name() -> void:
	for map in _lobby_maps():
		for spot in map.dummies:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.START_RUN]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_on_one_wall() -> void:
	var graph := RoomGraph.new(Lobby.RUN.passages)
	for map in _lobby_maps():
		var sides := graph.doors(map).map(func(d: RoomGraph.Door) -> int: return d.side)
		for side in sides:
			assert_int(sides.count(side)).is_equal(1)


## Town, and every room in the run.
func _lobby_maps() -> Array[Map]:
	var out: Array[Map] = [Lobby.TOWN, Lobby.RUN.start]
	for passage in Lobby.RUN.passages:
		out.append_array([passage.from, passage.to])
	return out
