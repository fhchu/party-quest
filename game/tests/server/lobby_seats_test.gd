extends GdUnitTestSuite
## The Lobby's seats on a test clock: numbering, drops and holds, rejoining,
## away and silence, the state it reports, and abandonment.

const GameTime := preload("res://shared/game_time.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const World := preload("res://sim/world.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")

const EXIT_MSEC := int(Lobby.EMPTY_EXIT_SEC * 1000)

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_seats_are_numbered_from_one() -> void:
	var ids: Array[int] = []
	for s in ["a", "b", "c", "d"]:
		ids.append(d.join(s).player_id)
	assert_array(ids).contains_exactly([1, 2, 3, 4])


func test_a_fifth_person_finds_the_lobby_full() -> void:
	for s in ["a", "b", "c", "d"]:
		d.join(s)
	assert_object(d.join("e")).is_null()


func test_a_town_drop_frees_the_seat_at_once() -> void:
	var a := d.join("a")
	d.join("b")
	d.lobby.drop(a)
	d.step()
	assert_object(d.lobby.seat_of_session("a")).is_null()
	assert_int(d.lobby.world.players.size()).is_equal(1)


func test_seats_after_a_freed_one_move_down() -> void:
	var a := d.join("a")
	var b := d.join("b")
	var c := d.join("c")
	var spot: Vector2 = d.lobby.world.players[c.player_id].pos
	d.lobby.drop(a)
	d.step()
	assert_int(b.player_id).is_equal(1)
	assert_int(c.player_id).is_equal(2)
	assert_array(d.lobby.world.players.keys()).contains_exactly_in_any_order([1, 2])
	assert_vector(d.lobby.world.players[c.player_id].pos).is_equal(spot)
	assert_int(d.join("e").player_id).is_equal(3)


func test_the_state_tells_each_seat_its_number() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_int(d.lobby.state(b).you).is_equal(2)
	d.lobby.drop(a)
	d.step()
	assert_int(d.lobby.state(b).you).is_equal(1)
	assert_int(d.lobby.state().you).is_zero()


func test_a_held_seat_counts_toward_full() -> void:
	var seats := d.start_with(["a", "b", "c", "d"])
	d.lobby.drop(seats[0])
	d.step()
	assert_object(d.join("e")).is_null()


func test_a_run_drop_is_held_until_town() -> void:
	var a := d.start_with(["a", "b"])[0]
	d.lobby.drop(a)
	d.step(GameTime.TICK_RATE)
	assert_object(d.lobby.seat_of_session("a")).is_same(a)
	assert_bool(d.lobby.world.players[a.player_id].connected).is_false()
	d.lobby.end_run(World.Outcome.LOST)
	d.finish_result()
	d.step()
	assert_object(d.lobby.seat_of_session("a")).is_null()


func test_rejoining_mid_run_gets_the_character_back() -> void:
	var a := d.start_with(["a", "b"])[0]
	d.lobby.drop(a)
	var back := d.join("a")
	assert_object(back).is_same(a)
	assert_int(back.readiness).is_not_equal(Seat.Readiness.SPECTATING)
	assert_bool(d.lobby.world.players[a.player_id].connected).is_true()


func test_rejoining_during_the_result_keeps_the_seat() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.drop(a)
	d.lobby.end_run(World.Outcome.LOST)
	assert_object(d.join("a")).is_same(a)


func test_away_ignores_input_and_shows_in_the_state() -> void:
	var a := d.join("a")
	d.lobby.set_away(a, true)
	var pos: Vector2 = d.lobby.world.players[a.player_id].pos
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(pos)
	assert_int(d.lobby.state().seats[0].presence).is_equal(LobbyState.Presence.AWAY)
	d.lobby.set_away(a, false)
	assert_int(d.lobby.state().seats[0].presence).is_equal(LobbyState.Presence.HERE)


func test_input_silence_stops_the_player() -> void:
	var a := d.join("a")
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	assert_int(a.state).is_equal(Seat.State.ACTIVE)
	d.step(ceili(Lobby.INPUT_SILENCE_SEC * GameTime.TICK_RATE) + 1)
	assert_int(a.state).is_equal(Seat.State.SILENT)
	var pos: Vector2 = d.lobby.world.players[a.player_id].pos
	d.step()
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(pos)


func test_state_lists_seats_in_order() -> void:
	var a := d.start_with(["a", "b"])[0]
	d.lobby.drop(a)
	var state := d.lobby.state()
	assert_int(state.phase).is_equal(LobbyState.Phase.RUN)
	var ids := state.seats.map(func(s: LobbyState.Seat) -> int: return s.id)
	assert_array(ids).contains_exactly([1, 2])
	assert_int(state.seats[0].presence).is_equal(LobbyState.Presence.DROPPED)
	assert_int(state.seats[1].readiness).is_equal(LobbyState.Readiness.READY)


func test_the_lobby_state_is_unsent_after_each_change_until_sent() -> void:
	d.lobby.mark_lobby_state_sent()
	assert_bool(d.lobby.is_lobby_state_unsent()).is_false()
	var a := d.join("a")
	assert_bool(d.lobby.is_lobby_state_unsent()).is_true()
	d.lobby.mark_lobby_state_sent()
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.is_lobby_state_unsent()).is_true()
	d.lobby.mark_lobby_state_sent()
	d.lobby.start_run()
	assert_bool(d.lobby.is_lobby_state_unsent()).is_true()
	d.lobby.mark_lobby_state_sent()
	d.step()
	assert_bool(d.lobby.is_lobby_state_unsent()).is_false()


func test_an_empty_lobby_is_abandoned_after_a_while() -> void:
	assert_bool(d.lobby.is_abandoned(EXIT_MSEC)).is_false()
	assert_bool(d.lobby.is_abandoned(EXIT_MSEC + 1)).is_true()


func test_a_held_seat_keeps_the_lobby() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.drop(a)
	d.step()
	assert_bool(d.lobby.is_abandoned(d.now + EXIT_MSEC)).is_false()


func test_the_wait_starts_when_the_last_seat_frees() -> void:
	var a := d.join("a")
	d.lobby.drop(a)
	d.step()
	assert_object(d.lobby.seat_of_session("a")).is_null()
	assert_bool(d.lobby.is_abandoned(d.now + EXIT_MSEC - LobbyDriver.TICK_MSEC)).is_false()
	assert_bool(d.lobby.is_abandoned(d.now + EXIT_MSEC + 1)).is_true()
