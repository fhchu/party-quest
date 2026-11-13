extends GdUnitTestSuite
## The maps the lobby uses, as balance.json gives them.

const Lobby := preload("res://server/lobby.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const RoomGraph := preload("res://shared/room_graph.gd")


func test_the_maps_the_lobby_names_exist() -> void:
	for map_name in _lobby_maps():
		assert_object(DataLoader.map(map_name)).is_not_null()


func test_the_lobby_acts_on_every_on_hit_its_maps_name() -> void:
	for map_name in _lobby_maps():
		for spot in DataLoader.map(map_name).dummies:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.START_RUN]).contains([spot.on_hit])


func test_no_room_in_the_run_has_two_doors_on_one_wall() -> void:
	var setup := DataLoader.run(Lobby.RUN)
	for map_name in _lobby_maps():
		var doors := RoomGraph.doors(setup.passages, map_name)
		var sides := doors.map(func(d: RoomGraph.Passage) -> int: return d.side)
		for side in sides:
			assert_int(sides.count(side)).is_equal(1)


## Town, and every room in the run.
func _lobby_maps() -> Array[String]:
	var out: Array[String] = [Lobby.TOWN_MAP]
	out.append_array(DataLoader.run(Lobby.RUN).rooms.keys())
	return out
