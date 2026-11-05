extends GdUnitTestSuite

const RoomState := preload("res://net/room_state.gd")


## Every field set to something other than its default.
func _busy_room() -> RoomState:
	var state := RoomState.new()
	state.phase = RoomState.Phase.RESULT
	state.outcome = RoomState.Outcome.WON
	state.you = 3
	for id in [1, 3]:
		var s := RoomState.Seat.new()
		s.id = id
		s.ready = id == 1
		s.spectating = id == 3
		s.presence = RoomState.Presence.DROPPED if id == 3 else RoomState.Presence.AWAY
		state.seats.append(s)
	return state


func test_round_trip_keeps_every_field() -> void:
	var state := _busy_room()
	var back := RoomState.new()
	assert_bool(back.read(state.to_bytes())).is_true()
	assert_int(back.phase).is_equal(state.phase)
	assert_int(back.outcome).is_equal(state.outcome)
	assert_int(back.you).is_equal(state.you)
	assert_int(back.seats.size()).is_equal(state.seats.size())
	for i in state.seats.size():
		var a := state.seats[i]
		var b := back.seats[i]
		assert_int(b.id).is_equal(a.id)
		assert_bool(b.ready).is_equal(a.ready)
		assert_bool(b.spectating).is_equal(a.spectating)
		assert_int(b.presence).is_equal(a.presence)


func test_truncated_bytes_change_nothing() -> void:
	var bytes := _busy_room().to_bytes()
	var state := RoomState.new()
	assert_bool(state.read(bytes.slice(0, bytes.size() - 1))).is_false()
	assert_int(state.phase).is_equal(RoomState.Phase.LOBBY)
	assert_array(state.seats).is_empty()


func test_an_unknown_phase_is_refused() -> void:
	var bytes := _busy_room().to_bytes()
	bytes[0] = RoomState.Phase.size()
	assert_bool(RoomState.new().read(bytes)).is_false()


func test_all_ready_needs_someone_seated() -> void:
	var state := RoomState.new()
	assert_bool(state.all_ready()).is_false()
	var s := RoomState.Seat.new()
	state.seats.append(s)
	assert_bool(state.all_ready()).is_false()
	s.ready = true
	assert_bool(state.all_ready()).is_true()


func test_all_ready_skips_dropped_seats() -> void:
	var state := RoomState.new()
	var here := RoomState.Seat.new()
	var gone := RoomState.Seat.new()
	gone.presence = RoomState.Presence.DROPPED
	state.seats.assign([here, gone])
	assert_bool(state.all_ready()).is_false()
	here.ready = true
	assert_bool(state.all_ready()).is_true()


func test_all_ready_needs_someone_connected() -> void:
	var state := RoomState.new()
	var gone := RoomState.Seat.new()
	gone.presence = RoomState.Presence.DROPPED
	gone.ready = true
	state.seats.append(gone)
	assert_bool(state.all_ready()).is_false()
