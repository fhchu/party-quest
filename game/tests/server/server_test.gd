extends GdUnitTestSuite
## The game server over real connections; see ServerDriver.

const Protocol := preload("res://net/protocol.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const ServerDriver := preload("res://tests/server/server_driver.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Run := preload("res://server/run.gd")
const DataRecords := preload("res://tests/data_records.gd")

var _d: ServerDriver


func before_test() -> void:
	_d = ServerDriver.new(get_tree())
	assert_int(_d.start_error()).is_equal(OK)


func after_test() -> void:
	_d.stop()
	WorldLoader.levels = WorldLoader.LEVELS


func test_hello_gets_a_player() -> void:
	var a := _d.join("a")
	var b := _d.join("b")
	assert_bool(await _d.until(func() -> bool: return a.player_id and b.player_id)).is_true()
	assert_array([a.player_id, b.player_id]).contains_exactly_in_any_order([1, 2])


func test_snapshots_follow_the_welcome() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.snapshots.size() >= 3)).is_true()
	assert_int(a.snapshots.back().players[0].id).is_equal(a.player_id)


func test_input_moves_the_player() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var start: Vector2 = _d.server.lobby.world.players[a.player_id].pos
	var moved := func() -> bool:
		a.net.send_input(Vector2.RIGHT, PackedInt32Array(), 0)
		return _d.server.lobby.world.players[a.player_id].pos.x > start.x
	assert_bool(await _d.until(moved)).is_true()


func test_reconnect_with_the_same_session_keeps_the_player() -> void:
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var id := a.player_id
	# A run holds a dropped seat; town would free it.
	_d.start_run()
	_d.leave(a)
	var dropped := func() -> bool: return not _d.server.lobby.world.players[id].connected
	assert_bool(await _d.until(dropped)).is_true()
	var again := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return again.player_id != 0)).is_true()
	assert_int(again.player_id).is_equal(id)
	assert_bool(_d.server.lobby.world.players[id].connected).is_true()


func test_one_player_too_many_is_rejected() -> void:
	var clients := _join_a_full_lobby()
	var all_in := func() -> bool:
		return clients.all(func(c: ServerDriver.TestClient) -> bool: return c.player_id)
	assert_bool(await _d.until(all_in)).is_true()
	var extra := _d.join("extra")
	assert_bool(await _d.until(func() -> bool: return extra.is_rejected())).is_true()
	assert_int(extra.reject_reason).is_equal(Protocol.RejectReason.FULL)


func test_duplicated_tab_replaces_the_old_one_which_stops() -> void:
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var b := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return b.player_id and a.is_rejected())).is_true()
	assert_int(b.player_id).is_equal(a.player_id)
	assert_int(a.reject_reason).is_equal(Protocol.RejectReason.DUPLICATE_SESSION)


func test_away_stops_snapshots_until_back() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.snapshots.size() >= 2)).is_true()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)
	# The pong follows every snapshot sent before the server read set_away.
	assert_bool(await _d.round_trip(a)).is_true()
	a.snapshots.clear()
	var away_at := _d.server.lobby.world.tick
	var ticks_passed := func() -> bool: return _d.server.lobby.world.tick >= away_at + 3
	assert_bool(await _d.until(ticks_passed)).is_true()
	# Anything sent in those ticks has arrived by the next pong.
	assert_bool(await _d.round_trip(a)).is_true()
	assert_array(a.snapshots).is_empty()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, false)
	assert_bool(await _d.until(func() -> bool: return not a.snapshots.is_empty())).is_true()


func test_input_makes_a_seat_active_and_silence_makes_it_silent() -> void:
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var seat: Seat = _d.server.lobby.seat_of_session("s")
	assert_int(seat.connection).is_equal(Seat.Connection.SILENT)
	a.net.send_input(Vector2.ZERO, PackedInt32Array(), 0)
	assert_bool(await _d.until(
			func() -> bool: return seat.connection == Seat.Connection.ACTIVE)).is_true()
	assert_bool(await _d.until(
			func() -> bool: return seat.connection == Seat.Connection.SILENT)).is_true()


func test_a_chosen_level_reaches_the_lobby() -> void:
	# Two levels of their own, told apart by their turret counts; a new
	# lobby, so its level select knows them.
	var turrets_by_level: Array[int] = [1, 2]
	WorldLoader.levels = DataRecords.levels(turrets_by_level)
	_d.server.lobby = Lobby.new(Time.get_ticks_msec())
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var lobby := _d.server.lobby
	await _open_level_select(a, "s")
	a.net.choose_level.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, 1)
	assert_bool(await _d.until(func() -> bool: return lobby.phase is Run)).is_true()
	# turrets_by_level[1].
	assert_int(lobby.world.dummies.size()).is_equal(2)


func test_a_press_moves_the_level_selects_cursor_on_the_pressers_client() -> void:
	# Levels of their own, three so one press right can't wrap; a new lobby,
	# so its level select knows them.
	var turrets_by_level: Array[int] = [1, 2, 3]
	WorldLoader.levels = DataRecords.levels(turrets_by_level)
	_d.server.lobby = Lobby.new(Time.get_ticks_msec())
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	await _open_level_select(a, "s")
	var counts := PackedInt32Array()
	counts.resize(Protocol.INPUT_ACTION_COUNT)
	counts[Protocol.InputAction.MOVE_RIGHT] = 1
	# Resending the same counts is still one press.
	var moved := func() -> bool:
		a.net.send_input(Vector2.ZERO, counts, 0)
		return a.lobby.cursor != 0
	assert_bool(await _d.until(moved)).is_true()
	assert_int(a.lobby.cursor).is_equal(1)


## Readies [param a]'s seat, joined as [param session], puts its character
## in town's open doorway and waits for the level select; fails the test if
## it doesn't open.
func _open_level_select(a: ServerDriver.TestClient, session: String) -> void:
	var lobby := _d.server.lobby
	lobby.set_ready(lobby.seat_of_session(session), true)
	assert_bool(await _d.until(func() -> bool: return lobby.world.room.cleared)).is_true()
	lobby.world.players[a.player_id].pos = lobby.world.room.doors[0].wall.gap.get_center()
	assert_bool(await _d.until(
			func() -> bool: return lobby.state().level_select_open)).is_true()


func test_leaving_town_frees_the_seat() -> void:
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	_d.leave(a)
	var freed := func() -> bool: return _d.server.lobby.seat_of_session("s") == null
	assert_bool(await _d.until(freed)).is_true()


func test_old_tab_is_ignored_after_being_replaced() -> void:
	var a := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var a_peer := a.api.get_unique_id()
	var b := _d.join("s")
	assert_bool(await _d.until(func() -> bool: return b.player_id and a.is_rejected())).is_true()
	var start: Vector2 = _d.server.lobby.world.players[b.player_id].pos
	a.net.send_input(Vector2.RIGHT, PackedInt32Array(), 0)
	# The server reads all the old tab sent before it sees the tab close.
	var a_gone := func() -> bool: return a_peer not in _d.server.multiplayer.get_peers()
	assert_bool(await _d.until(a_gone)).is_true()
	assert_vector(_d.server.lobby.world.players[b.player_id].pos).is_equal(start)
	# Its disconnect doesn't drop the player.
	assert_int(_d.server.lobby.seat_of_session("s").connection).is_equal(Seat.Connection.SILENT)


func test_ping_is_echoed() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, 12.5)
	assert_bool(await _d.until(func() -> bool: return not a.pongs.is_empty())).is_true()
	assert_float(a.pongs[0]).is_equal(12.5)


func test_other_build_is_rejected() -> void:
	var a := _d.join("a", Protocol.build_id() + "-other")
	assert_bool(await _d.until(func() -> bool: return a.is_rejected())).is_true()
	assert_int(a.reject_reason).is_equal(Protocol.RejectReason.VERSION)
	assert_int(a.player_id).is_zero()
	assert_object(_d.server.lobby.seat_of_session("a")).is_null()


func test_lobby_state_follows_the_welcome() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.lobby != null)).is_true()
	assert_int(a.lobby.phase).is_equal(LobbyState.Phase.TOWN)
	assert_int(a.lobby.seats.size()).is_equal(1)
	assert_int(a.lobby.seats[0].id).is_equal(a.player_id)


func test_others_see_a_newcomer() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.lobby != null)).is_true()
	_d.join("b")
	assert_bool(await _d.until(func() -> bool: return a.lobby.seats.size() == 2)).is_true()


func test_clients_see_the_run_and_its_timer() -> void:
	var a := _d.join("a")
	var b := _d.join("b")
	var both_in := func() -> bool: return a.lobby != null and a.lobby.seats.size() == 2
	assert_bool(await _d.until(both_in)).is_true()
	_d.start_run()
	var started := func() -> bool: return b.lobby.phase == LobbyState.Phase.RUN
	assert_bool(await _d.until(started)).is_true()
	var timed := func() -> bool: return b.snapshots.back().run_ticks_left > 0
	assert_bool(await _d.until(timed)).is_true()


## Lobby.MAX_PLAYERS clients, each joining.
func _join_a_full_lobby() -> Array[ServerDriver.TestClient]:
	var clients: Array[ServerDriver.TestClient] = []
	for i in Lobby.MAX_PLAYERS:
		clients.append(_d.join("p%d" % i))
	return clients
