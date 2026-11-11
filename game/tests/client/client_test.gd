extends GdUnitTestSuite

const Client := preload("res://client/client.gd")
const RoomState := preload("res://net/room_state.gd")


func _room(phase: RoomState.Phase, seats: Array[RoomState.Seat]) -> RoomState:
	var state := RoomState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


func _seat(id: int, readiness := RoomState.Readiness.NOT_READY) -> RoomState.Seat:
	var s := RoomState.Seat.new()
	s.id = id
	s.readiness = readiness
	return s


func test_a_connected_seated_player_can_act_in_town_and_the_match() -> void:
	for phase: RoomState.Phase in [RoomState.Phase.TOWN, RoomState.Phase.MATCH]:
		assert_bool(Client.can_act(_room(phase, [_seat(1)]), 1, true)).is_true()


func test_nobody_can_act_without_a_room_a_connection_or_during_the_result() -> void:
	var town := _room(RoomState.Phase.TOWN, [_seat(1)])
	assert_bool(Client.can_act(null, 1, true)).is_false()
	assert_bool(Client.can_act(town, 1, false)).is_false()
	assert_bool(Client.can_act(_room(RoomState.Phase.RESULT, [_seat(1)]), 1, true)).is_false()


func test_a_spectator_or_someone_without_a_seat_cannot_act() -> void:
	var late := _seat(2, RoomState.Readiness.SPECTATING)
	var in_match := _room(RoomState.Phase.MATCH, [_seat(1), late])
	assert_bool(Client.can_act(in_match, 2, true)).is_false()
	assert_bool(Client.can_act(in_match, 3, true)).is_false()
