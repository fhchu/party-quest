extends GdUnitTestSuite

const LobbyState := preload("res://net/lobby_state.gd")


## Every field set to something other than its default.
func _busy_lobby() -> LobbyState:
	var state := LobbyState.new()
	state.phase = LobbyState.Phase.RESULT
	state.outcome = LobbyState.Outcome.WON
	state.all_ready = true
	state.you = 3
	state.level_select_open = true
	state.cursor = 2
	for id: int in [1, 3]:
		var s := LobbyState.Seat.new()
		s.id = id
		s.participation = (LobbyState.Participation.READY if id == 1
				else LobbyState.Participation.SPECTATING)
		s.connection = LobbyState.Connection.DROPPED
		s.slot_items = PackedInt32Array([id + 1, LobbyState.NO_ITEM])
		# Quantities past a u16, so a narrower field shows.
		s.inventory = { id + 1: 70000 + id, id + 2: 1 }
		state.seats.append(s)
	return state


func test_round_trip_keeps_every_field() -> void:
	var state := _busy_lobby()
	var back := LobbyState.new()
	assert_bool(back.read(state.to_bytes())).is_true()
	assert_int(back.phase).is_equal(state.phase)
	assert_int(back.outcome).is_equal(state.outcome)
	assert_bool(back.all_ready).is_equal(state.all_ready)
	assert_int(back.you).is_equal(state.you)
	assert_bool(back.level_select_open).is_equal(state.level_select_open)
	assert_int(back.cursor).is_equal(state.cursor)
	assert_int(back.seats.size()).is_equal(state.seats.size())
	for i in state.seats.size():
		var a := state.seats[i]
		var b := back.seats[i]
		assert_int(b.id).is_equal(a.id)
		assert_int(b.participation).is_equal(a.participation)
		assert_int(b.connection).is_equal(a.connection)
		assert_array(b.slot_items).is_equal(a.slot_items)
		assert_dict(b.inventory).is_equal(a.inventory)


func test_truncated_bytes_change_nothing() -> void:
	var bytes := _busy_lobby().to_bytes()
	var state := LobbyState.new()
	assert_bool(state.read(bytes.slice(0, bytes.size() - 1))).is_false()
	assert_int(state.phase).is_equal(LobbyState.Phase.TOWN)
	assert_array(state.seats).is_empty()


func test_bytes_cut_at_any_length_are_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	for length in bytes.size():
		assert_bool(LobbyState.new().read(bytes.slice(0, length))) \
				.override_failure_message("cut to %d bytes" % length).is_false()


func test_extra_bytes_are_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	bytes.append(0)
	assert_bool(LobbyState.new().read(bytes)).is_false()


func test_an_unknown_phase_is_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	bytes[0] = LobbyState.Phase.size()
	assert_bool(LobbyState.new().read(bytes)).is_false()


func test_an_all_ready_flag_other_than_0_or_1_is_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	# phase, outcome, then all_ready.
	bytes[2] = 2
	assert_bool(LobbyState.new().read(bytes)).is_false()


func test_a_level_select_flag_other_than_0_or_1_is_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	# phase, outcome, all_ready, you, then level_select_open.
	bytes[4] = 2
	assert_bool(LobbyState.new().read(bytes)).is_false()


func test_an_unknown_participation_is_refused() -> void:
	var bytes := _busy_lobby().to_bytes()
	bytes[LobbyState.HEADER_SIZE + 1] = LobbyState.Participation.size()
	assert_bool(LobbyState.new().read(bytes)).is_false()
