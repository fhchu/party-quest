extends GdUnitTestSuite
## The maps the lobby uses, as balance.json gives them.

const Lobby := preload("res://server/lobby.gd")
const DataLoader := preload("res://shared/data_loader.gd")


func test_the_lobby_acts_on_every_on_hit_its_maps_name() -> void:
	for map_name in [Lobby.TOWN_MAP, DataLoader.run(Lobby.RUN).map_name]:
		for spot in DataLoader.map(map_name).dummies:
			assert_array(["", Lobby.TOGGLE_READY, Lobby.START_RUN]).contains([spot.on_hit])
