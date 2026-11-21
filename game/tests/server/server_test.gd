extends GdUnitTestSuite
## Server and clients run in this one process, each in its own branch of the
## tree with its own MultiplayerAPI, so RPCs travel over the real transport.

const Net := preload("res://net/net.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Protocol := preload("res://net/protocol.gd")
const GameTime := preload("res://shared/game_time.gd")
const Server := preload("res://server/server.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const TcpClientPeer := preload("res://client/tcp_client_peer.gd")


## Long enough for a message to arrive and be acted on.
const SETTLE_SEC := GameTime.TICK_SEC * 2

## Far from the real ports, so tests can run beside ./dev.sh.
static var _next_port := 19400

var _port: int
var _server: Server
var _roots: Array[Node] = []
var _next_ping := 0


func before_test() -> void:
	_port = _next_port
	_next_port += 1
	var root := _branch("Server%d" % _port, SceneMultiplayer.new())
	_server = Server.new()
	_server.net = root.get_node("Net")
	# A message crosses loopback well within this.
	_server.kick_delay_sec = SETTLE_SEC
	root.add_child(_server)
	assert_int(_server.start(_port)).is_equal(OK)


func after_test() -> void:
	for root in _roots:
		var api := get_tree().get_multiplayer(root.get_path())
		api.multiplayer_peer.close()
		get_tree().set_multiplayer(null, root.get_path())
		root.free()
	_roots.clear()


## A branch of the tree with its own MultiplayerAPI and a Net node, like Main.
func _branch(root_name: String, api: MultiplayerAPI) -> Node:
	var root := Node.new()
	root.name = root_name
	get_tree().root.add_child(root)
	get_tree().set_multiplayer(api, root.get_path())
	Net.add_to(root)
	_roots.append(root)
	return root


func _client_peer() -> MultiplayerPeer:
	var peer := TcpClientPeer.new()
	peer.connect_to("127.0.0.1", _port)
	return peer


func _join(session: String, build_id := Protocol.build_id()) -> TestClient:
	var c := TestClient.new()
	var root := _branch("Client%d_%d" % [_port, _roots.size()], c.api)
	c.net = root.get_node("Net")
	c.net.welcomed.connect(func(id: int) -> void: c.player_id = id)
	c.net.rejected.connect(func(reason: Protocol.RejectReason) -> void: c.reject_reason = reason)
	c.net.snapshot_received.connect(func(snap: Snapshot) -> void: c.snapshots.append(snap))
	c.net.pong_received.connect(func(sent_at: float) -> void: c.pongs.append(sent_at))
	c.net.lobby_state_received.connect(func(state: LobbyState) -> void: c.lobby = state)
	# Capturing c here would leak it: c holds api, api holds this lambda.
	var net := c.net
	c.api.connected_to_server.connect(
			func() -> void: net.hello.rpc_id(
					MultiplayerPeer.TARGET_PEER_SERVER, build_id, session))
	c.api.multiplayer_peer = _client_peer()
	return c


func _leave(c: TestClient) -> void:
	c.api.multiplayer_peer.close()


## Waits up to [param timeout] seconds for [param cond] to be true. Replies
## take a few frames; 3 s is far beyond that, and still fails fast.
func _until(cond: Callable, timeout := 3.0) -> bool:
	var end := Time.get_ticks_msec() + timeout * 1000
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


## Pings the server as [param c] and waits for the pong. TCP keeps order,
## so everything the server sent before reading the ping has arrived.
func _round_trip(c: TestClient) -> bool:
	_next_ping += 1
	var sent := float(_next_ping)
	c.net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, sent)
	return await _until(func() -> bool: return sent in c.pongs)


func test_hello_gets_a_player() -> void:
	var a := _join("a")
	var b := _join("b")
	assert_bool(await _until(func() -> bool: return a.player_id and b.player_id)).is_true()
	assert_array([a.player_id, b.player_id]).contains_exactly_in_any_order([1, 2])


func test_snapshots_follow_the_welcome() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.snapshots.size() >= 3)).is_true()
	assert_int(a.snapshots.back().players[0].id).is_equal(a.player_id)


func test_input_moves_the_player() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var start: Vector2 = _server.lobby.world.players[a.player_id].pos
	var moved := func() -> bool:
		a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
		return _server.lobby.world.players[a.player_id].pos.x > start.x
	assert_bool(await _until(moved)).is_true()


func test_reconnect_with_the_same_session_keeps_the_player() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var id := a.player_id
	_leave(a)
	var dropped := func() -> bool: return not _server.lobby.world.players[id].connected
	assert_bool(await _until(dropped)).is_true()
	var again := _join("s")
	assert_bool(await _until(func() -> bool: return again.player_id != 0)).is_true()
	assert_int(again.player_id).is_equal(id)
	assert_bool(_server.lobby.world.players[id].connected).is_true()


func test_one_player_too_many_is_rejected() -> void:
	var clients: Array[TestClient] = []
	for i in Lobby.MAX_PLAYERS:
		clients.append(_join("p%d" % i))
	var all_in := func() -> bool:
		return clients.all(func(c: TestClient) -> bool: return c.player_id)
	assert_bool(await _until(all_in)).is_true()
	var extra := _join("extra")
	assert_bool(await _until(func() -> bool: return extra.is_rejected())).is_true()
	assert_int(extra.reject_reason).is_equal(Protocol.RejectReason.FULL)


func test_duplicated_tab_takes_over_and_the_old_one_stops() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var b := _join("s")
	assert_bool(await _until(func() -> bool: return b.player_id and a.is_rejected())).is_true()
	assert_int(b.player_id).is_equal(a.player_id)
	assert_int(a.reject_reason).is_equal(Protocol.RejectReason.DUPLICATE_SESSION)


func test_away_stops_snapshots_until_back() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.snapshots.size() >= 2)).is_true()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)
	# The pong follows every snapshot sent before the server read set_away.
	assert_bool(await _round_trip(a)).is_true()
	a.snapshots.clear()
	var away_at := _server.lobby.world.tick
	var ticks_passed := func() -> bool: return _server.lobby.world.tick >= away_at + 3
	assert_bool(await _until(ticks_passed)).is_true()
	# Anything sent in those ticks has arrived by the next pong.
	assert_bool(await _round_trip(a)).is_true()
	assert_array(a.snapshots).is_empty()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, false)
	assert_bool(await _until(func() -> bool: return not a.snapshots.is_empty())).is_true()


func test_input_makes_a_seat_active_and_silence_makes_it_silent() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var seat: Seat = _server.lobby.seat_of_session("s")
	assert_int(seat.connection).is_equal(Seat.Connection.SILENT)
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.ZERO, 0)
	assert_bool(await _until(
			func() -> bool: return seat.connection == Seat.Connection.ACTIVE)).is_true()
	assert_bool(await _until(
			func() -> bool: return seat.connection == Seat.Connection.SILENT)).is_true()


func test_away_reaches_the_seat() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var seat: Seat = _server.lobby.seat_of_session("s")
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)
	assert_bool(await _until(
			func() -> bool: return seat.connection == Seat.Connection.AWAY)).is_true()


func test_leaving_town_frees_the_seat() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	_leave(a)
	var freed := func() -> bool: return _server.lobby.seat_of_session("s") == null
	assert_bool(await _until(freed)).is_true()


func test_old_tab_is_ignored_after_a_takeover() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var a_peer := a.api.get_unique_id()
	var b := _join("s")
	assert_bool(await _until(func() -> bool: return b.player_id and a.is_rejected())).is_true()
	var start: Vector2 = _server.lobby.world.players[b.player_id].pos
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
	# The server reads all the old tab sent before it sees the tab close.
	var a_gone := func() -> bool: return a_peer not in _server.multiplayer.get_peers()
	assert_bool(await _until(a_gone)).is_true()
	assert_vector(_server.lobby.world.players[b.player_id].pos).is_equal(start)
	# Its disconnect doesn't drop the player.
	assert_int(_server.lobby.seat_of_session("s").connection).is_equal(Seat.Connection.SILENT)


func test_ping_is_echoed() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, 12.5)
	assert_bool(await _until(func() -> bool: return not a.pongs.is_empty())).is_true()
	assert_float(a.pongs[0]).is_equal(12.5)


func test_other_build_is_rejected() -> void:
	var a := _join("a", Protocol.build_id() + "-other")
	assert_bool(await _until(func() -> bool: return a.is_rejected())).is_true()
	assert_int(a.reject_reason).is_equal(Protocol.RejectReason.VERSION)
	assert_int(a.player_id).is_zero()
	assert_object(_server.lobby.seat_of_session("a")).is_null()


func test_lobby_state_follows_the_welcome() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.lobby != null)).is_true()
	assert_int(a.lobby.phase).is_equal(LobbyState.Phase.TOWN)
	assert_int(a.lobby.seats.size()).is_equal(1)
	assert_int(a.lobby.seats[0].id).is_equal(a.player_id)


func test_a_freed_lobby_seat_moves_the_next_player_down() -> void:
	var a := _join("a")
	var b := _join("b")
	var both_in := func() -> bool: return b.lobby != null and b.lobby.seats.size() == 2
	assert_bool(await _until(both_in)).is_true()
	assert_int(b.lobby.you).is_equal(2)
	_leave(a)
	assert_bool(await _until(func() -> bool: return b.lobby.you == 1)).is_true()
	assert_int(b.lobby.seats.size()).is_equal(1)
	assert_int(b.lobby.seats[0].id).is_equal(1)


func test_others_see_a_newcomer() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.lobby != null)).is_true()
	_join("b")
	assert_bool(await _until(func() -> bool: return a.lobby.seats.size() == 2)).is_true()


func _start_run() -> void:
	for seat in _server.lobby.seats():
		_server.lobby.set_ready(seat, true)
	_server.lobby.start_run()


func test_clients_see_the_run_and_its_timer() -> void:
	var a := _join("a")
	var b := _join("b")
	var both_in := func() -> bool: return a.lobby != null and a.lobby.seats.size() == 2
	assert_bool(await _until(both_in)).is_true()
	_start_run()
	var started := func() -> bool: return b.lobby.phase == LobbyState.Phase.RUN
	assert_bool(await _until(started)).is_true()
	var timed := func() -> bool: return b.snapshots.back().run_ticks_left > 0
	assert_bool(await _until(timed)).is_true()


class TestClient:
	const NOT_REJECTED := -1

	var api := SceneMultiplayer.new()
	var net: Node
	var player_id := 0
	## NOT_REJECTED until the server turns this client away.
	var reject_reason := NOT_REJECTED
	var snapshots: Array = []
	var pongs: Array = []
	## The latest lobby state; null before the first.
	var lobby: LobbyState

	func is_rejected() -> bool:
		return reject_reason != NOT_REJECTED
