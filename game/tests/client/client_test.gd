extends GdUnitTestSuite

const Client := preload("res://client/client.gd")
const LobbyState := preload("res://net/lobby_state.gd")


func _lobby(phase: LobbyState.Phase, seats: Array[LobbyState.Seat]) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


func _seat(id: int, readiness := LobbyState.Readiness.NOT_READY) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
	s.id = id
	s.readiness = readiness
	return s


func test_a_connected_seated_player_can_act_in_town_and_the_run() -> void:
	for phase: LobbyState.Phase in [LobbyState.Phase.TOWN, LobbyState.Phase.RUN]:
		assert_bool(Client.can_act(_lobby(phase, [_seat(1)]), 1, true)).is_true()


func test_nobody_can_act_without_a_lobby_a_connection_or_during_the_result() -> void:
	var town := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	assert_bool(Client.can_act(null, 1, true)).is_false()
	assert_bool(Client.can_act(town, 1, false)).is_false()
	assert_bool(Client.can_act(_lobby(LobbyState.Phase.RESULT, [_seat(1)]), 1, true)).is_false()


func test_a_spectator_or_someone_without_a_seat_cannot_act() -> void:
	var late := _seat(2, LobbyState.Readiness.SPECTATING)
	var in_run := _lobby(LobbyState.Phase.RUN, [_seat(1), late])
	assert_bool(Client.can_act(in_run, 2, true)).is_false()
	assert_bool(Client.can_act(in_run, 3, true)).is_false()
