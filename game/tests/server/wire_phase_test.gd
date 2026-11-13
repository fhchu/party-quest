extends GdUnitTestSuite
## The lobby's mappings from its own state to what clients see.

const Lobby := preload("res://server/lobby.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Seat := preload("res://server/seat.gd")
const World := preload("res://sim/world.gd")


func test_every_wire_phase_has_one_phase_class() -> void:
	var names: Array = Lobby.WIRE_PHASE.values()
	names.sort()
	assert_array(names).is_equal(LobbyState.Phase.values())


func test_every_readiness_maps_one_to_one() -> void:
	_assert_one_to_one(Lobby.WIRE_READINESS, Seat.Readiness, LobbyState.Readiness)


func test_every_outcome_maps_one_to_one() -> void:
	_assert_one_to_one(Lobby.WIRE_OUTCOME, World.Outcome, LobbyState.Outcome)


func _assert_one_to_one(mapping: Dictionary, server_enum: Dictionary,
		wire_enum: Dictionary) -> void:
	var keys := mapping.keys()
	keys.sort()
	assert_array(keys).is_equal(server_enum.values())
	var values := mapping.values()
	values.sort()
	assert_array(values).is_equal(wire_enum.values())
