extends GdUnitTestSuite
## The Room's seats on a test clock: numbering, holds after a drop, rejoining,
## away and silence, the state it reports, and abandonment.

const Room := preload("res://server/room.gd")
const RoomState := preload("res://net/room_state.gd")
const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const RoomDriver := preload("res://tests/server/room_driver.gd")

const HOLD_MSEC := int(Protocol.LOBBY_SEAT_HOLD_SEC * 1000)
const HALF_HOLD_MSEC := int(Protocol.LOBBY_SEAT_HOLD_SEC * 1000 / 2)
const EXIT_MSEC := int(Protocol.EMPTY_EXIT_SEC * 1000)

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_seats_are_numbered_from_one() -> void:
	var ids: Array[int] = []
	for s in ["a", "b", "c", "d"]:
		ids.append(d.join(s).player_id)
	assert_array(ids).contains_exactly([1, 2, 3, 4])


func test_a_fifth_person_finds_the_room_full() -> void:
	for s in ["a", "b", "c", "d"]:
		d.join(s)
	assert_object(d.join("e")).is_null()


func test_a_lobby_drop_holds_the_seat_for_a_while() -> void:
	var a := d.join("a")
	d.join("b")
	d.room.drop(a, d.now)
	d.step(Protocol.TICK_RATE)
	var back := d.join("a")
	assert_object(back).is_same(a)
	assert_int(back.state).is_equal(Room.State.SILENT)


func test_a_lobby_drop_frees_the_seat_after_the_hold() -> void:
	var a := d.join("a")
	d.join("b")
	d.room.drop(a, d.now)
	d.now += HOLD_MSEC
	d.step()
	assert_object(d.room.seat_of_session("a")).is_null()
	assert_int(d.room.world.players.size()).is_equal(1)


func test_seats_after_a_freed_one_move_down() -> void:
	var a := d.join("a")
	var b := d.join("b")
	var c := d.join("c")
	var spot: Vector2 = d.room.world.players[c.player_id].pos
	d.room.drop(a, d.now)
	d.now += HOLD_MSEC
	d.step()
	assert_int(b.player_id).is_equal(1)
	assert_int(c.player_id).is_equal(2)
	assert_array(d.room.world.players.keys()).contains_exactly_in_any_order([1, 2])
	assert_vector(d.room.world.players[c.player_id].pos).is_equal(spot)
	assert_int(d.join("e").player_id).is_equal(3)


func test_a_held_seat_moves_down_too() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.join("c")
	d.room.drop(a, d.now)
	d.now += HALF_HOLD_MSEC
	d.room.drop(b, d.now)
	d.now += HALF_HOLD_MSEC + RoomDriver.TICK_MSEC
	d.step()
	# a's hold is over; b's isn't, and b now holds seat 1.
	assert_object(d.room.seat_of_session("a")).is_null()
	assert_int(d.join("b").player_id).is_equal(1)


func test_the_state_tells_each_seat_its_number() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_int(d.room.state(b).you).is_equal(2)
	d.room.drop(a, d.now)
	d.now += HOLD_MSEC
	d.step()
	assert_int(d.room.state(b).you).is_equal(1)
	assert_int(d.room.state().you).is_zero()


func test_a_held_seat_counts_toward_full() -> void:
	var seats: Array[Room.Seat] = []
	for s in ["a", "b", "c", "d"]:
		seats.append(d.join(s))
	d.room.drop(seats[0], d.now)
	assert_object(d.join("e")).is_null()


func test_a_match_drop_is_held_until_the_lobby() -> void:
	var a := d.start_with(["a", "b"])[0]
	d.room.drop(a, d.now)
	d.now += HOLD_MSEC * 2
	d.step()
	assert_object(d.room.seat_of_session("a")).is_same(a)
	assert_bool(d.room.world.players[a.player_id].connected).is_false()
	d.end_match(RoomState.Outcome.LOST)
	d.finish_result()
	# The lobby's hold starts when the lobby comes back.
	d.step()
	assert_object(d.room.seat_of_session("a")).is_same(a)
	d.now += HOLD_MSEC
	d.step()
	assert_object(d.room.seat_of_session("a")).is_null()


func test_rejoining_mid_match_gets_the_character_back() -> void:
	var a := d.start_with(["a", "b"])[0]
	d.room.drop(a, d.now)
	var back := d.join("a")
	assert_object(back).is_same(a)
	assert_int(back.standing).is_not_equal(RoomState.Standing.SPECTATING)
	assert_bool(d.room.world.players[a.player_id].connected).is_true()


func test_rejoining_during_the_result_keeps_the_seat() -> void:
	var a := d.start_with(["a"])[0]
	d.room.drop(a, d.now)
	d.end_match(RoomState.Outcome.LOST)
	assert_object(d.join("a")).is_same(a)


func test_away_ignores_input_and_shows_in_the_state() -> void:
	var a := d.join("a")
	d.room.set_away(a, true)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)
	assert_int(d.room.state().seats[0].presence).is_equal(RoomState.Presence.AWAY)
	d.room.set_away(a, false)
	assert_int(d.room.state().seats[0].presence).is_equal(RoomState.Presence.HERE)


func test_input_silence_stops_the_player() -> void:
	var a := d.join("a")
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	assert_int(a.state).is_equal(Room.State.ACTIVE)
	d.step(ceili(Protocol.INPUT_SILENCE_SEC * Protocol.TICK_RATE) + 1)
	assert_int(a.state).is_equal(Room.State.SILENT)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)


func test_state_lists_seats_in_order() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.set_ready(b, true)
	d.room.drop(a, d.now)
	var state := d.room.state()
	assert_int(state.phase).is_equal(RoomState.Phase.LOBBY)
	var ids := state.seats.map(func(s: RoomState.Seat) -> int: return s.id)
	assert_array(ids).contains_exactly([1, 2])
	assert_int(state.seats[0].presence).is_equal(RoomState.Presence.DROPPED)
	assert_int(state.seats[1].standing).is_equal(RoomState.Standing.READY)


func test_the_room_state_is_unsent_after_each_change_until_sent() -> void:
	d.room.mark_room_state_sent()
	assert_bool(d.room.is_room_state_unsent()).is_false()
	var a := d.join("a")
	assert_bool(d.room.is_room_state_unsent()).is_true()
	d.room.mark_room_state_sent()
	d.set_ready(a, true)
	assert_bool(d.room.is_room_state_unsent()).is_true()
	d.room.mark_room_state_sent()
	d.start_match()
	assert_bool(d.room.is_room_state_unsent()).is_true()
	d.room.mark_room_state_sent()
	d.step()
	assert_bool(d.room.is_room_state_unsent()).is_false()


func test_an_empty_room_is_abandoned_after_a_while() -> void:
	assert_bool(d.room.is_abandoned(EXIT_MSEC)).is_false()
	assert_bool(d.room.is_abandoned(EXIT_MSEC + 1)).is_true()


func test_a_held_seat_keeps_the_room() -> void:
	var a := d.join("a")
	d.room.drop(a, d.now)
	d.step()
	assert_bool(d.room.is_abandoned(d.now + EXIT_MSEC)).is_false()


func test_the_wait_starts_when_the_last_seat_frees() -> void:
	var a := d.join("a")
	d.room.drop(a, d.now)
	d.now += HOLD_MSEC
	d.step()
	assert_object(d.room.seat_of_session("a")).is_null()
	assert_bool(d.room.is_abandoned(d.now + EXIT_MSEC - RoomDriver.TICK_MSEC)).is_false()
	assert_bool(d.room.is_abandoned(d.now + EXIT_MSEC + 1)).is_true()
