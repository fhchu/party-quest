extends GdUnitTestSuite
## The lobby's mapping from phase classes to what clients see.

const Lobby := preload("res://server/lobby.gd")
const LobbyState := preload("res://net/lobby_state.gd")


func test_every_wire_phase_has_one_phase_class() -> void:
	var names: Array = Lobby.WIRE_PHASE.values()
	names.sort()
	assert_array(names).is_equal(LobbyState.Phase.values())
