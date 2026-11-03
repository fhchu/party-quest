extends GdUnitTestSuite
## Server and clients run in this one process, each in its own branch of the
## tree with its own MultiplayerAPI, so RPCs travel over the real transport.

const Net := preload("res://net/net.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")
const TcpClientPeer := preload("res://net/tcp_client_peer.gd")


## Long enough for a message to arrive and be acted on.
const SETTLE_SEC := Protocol.SNAPSHOT_INTERVAL_SEC * 2

## Far from the real ports, so tests can run beside ./dev.sh.
static var _next_port := 19400

var _port: int
var _server: Server
var _roots: Array[Node] = []


func before_test() -> void:
	_port = _next_port
	_next_port += 1
	var root := _branch("Server%d" % _port, SceneMultiplayer.new())
	_server = Server.new()
	_server.net = root.get_node("Net")
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
	var net := Net.new()
	net.name = "Net"
	root.add_child(net)
	_roots.append(root)
	return root


func _client_peer() -> MultiplayerPeer:
	var peer := TcpClientPeer.new()
	peer.connect_to("127.0.0.1", _port)
	return peer


## Connects and says hello with [param session].
func _join(session: String) -> TestClient:
	var c := TestClient.new()
	var root := _branch("Client%d_%d" % [_port, _roots.size()], c.api)
	c.net = root.get_node("Net")
	c.net.welcomed.connect(func(id: int) -> void: c.player_id = id)
	c.net.rejected.connect(func(reason: String) -> void: c.rejected = reason)
	c.net.snapshot_received.connect(func(snap: Snapshot) -> void: c.snapshots.append(snap))
	c.net.pong_received.connect(func(sent_at: float) -> void: c.pongs.append(sent_at))
	c.api.connected_to_server.connect(
			func() -> void: c.net.hello.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, session))
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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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
	var start: Vector2 = _server.world.players[a.player_id].pos
	var moved := func() -> bool:
		a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
		return _server.world.players[a.player_id].pos.x > start.x
	assert_bool(await _until(moved)).is_true()


func test_input_silence_stops_the_player() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
	await _wait(Protocol.INPUT_SILENCE_SEC * 2)
	var pos: Vector2 = _server.world.players[a.player_id].pos
	await _wait(Protocol.INPUT_SILENCE_SEC)
	assert_vector(_server.world.players[a.player_id].pos).is_equal(pos)


func test_reconnect_with_the_same_session_keeps_the_player() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var id := a.player_id
	_leave(a)
	var dropped := func() -> bool: return not _server.world.players[id].connected
	assert_bool(await _until(dropped)).is_true()
	var again := _join("s")
	assert_bool(await _until(func() -> bool: return again.player_id != 0)).is_true()
	assert_int(again.player_id).is_equal(id)
	assert_bool(_server.world.players[id].connected).is_true()


func test_a_freed_seat_goes_to_the_next_player() -> void:
	var a := _join("a")
	var b := _join("b")
	assert_bool(await _until(func() -> bool: return a.player_id and b.player_id)).is_true()
	var freed := a.player_id
	_leave(a)
	var seat: Server.Seat = _server._seats["a"]
	assert_bool(await _until(func() -> bool: return seat.state == Server.State.DROPPED)).is_true()
	# Skip the grace period.
	seat.since_msec -= int(Protocol.RECONNECT_GRACE_SEC * 1000) + 1
	assert_bool(await _until(func() -> bool: return not _server._seats.has("a"))).is_true()
	var c := _join("c")
	assert_bool(await _until(func() -> bool: return c.player_id != 0)).is_true()
	assert_int(c.player_id).is_equal(freed)


func test_one_player_too_many_is_rejected() -> void:
	var clients: Array[TestClient] = []
	for i in Protocol.MAX_PLAYERS:
		clients.append(_join("p%d" % i))
	var all_in := func() -> bool:
		return clients.all(func(c: TestClient) -> bool: return c.player_id)
	assert_bool(await _until(all_in)).is_true()
	var extra := _join("extra")
	assert_bool(await _until(func() -> bool: return extra.rejected != "")).is_true()
	assert_str(extra.rejected).is_equal(Server.REJECT_FULL)


func test_duplicated_tab_takes_over_and_the_old_one_stops() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var b := _join("s")
	assert_bool(await _until(func() -> bool: return b.player_id and a.rejected)).is_true()
	assert_int(b.player_id).is_equal(a.player_id)
	assert_str(a.rejected).is_equal(Server.REJECT_TAKEN_OVER)


func test_away_stops_snapshots_until_back() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.snapshots.size() >= 2)).is_true()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)
	# Let snapshots already sent arrive.
	await _wait(Protocol.SNAPSHOT_INTERVAL_SEC * 4)
	a.snapshots.clear()
	# Long enough for several to have come.
	await _wait(Protocol.SNAPSHOT_INTERVAL_SEC * 6)
	assert_array(a.snapshots).is_empty()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, false)
	assert_bool(await _until(func() -> bool: return not a.snapshots.is_empty())).is_true()


func test_seat_follows_input_away_and_drop() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var seat: Server.Seat = _server._seats["s"]
	assert_int(seat.state).is_equal(Server.State.SILENT)
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.ZERO, 0)
	assert_bool(await _until(func() -> bool: return seat.state == Server.State.ACTIVE)).is_true()
	assert_bool(await _until(func() -> bool: return seat.state == Server.State.SILENT)).is_true()
	a.net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)
	assert_bool(await _until(func() -> bool: return seat.state == Server.State.AWAY)).is_true()
	# Away input is ignored.
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
	await _wait(SETTLE_SEC)
	assert_int(seat.state).is_equal(Server.State.AWAY)
	_leave(a)
	assert_bool(await _until(func() -> bool: return seat.state == Server.State.DROPPED)).is_true()
	assert_bool(_server.world.players[a.player_id].connected).is_false()


func test_old_tab_is_ignored_after_a_takeover() -> void:
	var a := _join("s")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var b := _join("s")
	assert_bool(await _until(func() -> bool: return b.player_id and a.rejected)).is_true()
	var start: Vector2 = _server.world.players[b.player_id].pos
	a.net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Vector2.RIGHT, 0)
	await _wait(SETTLE_SEC)
	assert_vector(_server.world.players[b.player_id].pos).is_equal(start)
	# The old tab's disconnect doesn't drop the player.
	var a_closed := func() -> bool:
		var status := a.api.multiplayer_peer.get_connection_status()
		return status == MultiplayerPeer.CONNECTION_DISCONNECTED
	assert_bool(await _until(a_closed)).is_true()
	await _wait(SETTLE_SEC)
	assert_int(_server._seats["s"].state).is_equal(Server.State.SILENT)


func test_ping_is_echoed() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, 12.5)
	assert_bool(await _until(func() -> bool: return not a.pongs.is_empty())).is_true()
	assert_float(a.pongs[0]).is_equal(12.5)


class TestClient:
	var api := SceneMultiplayer.new()
	var net: Node
	var player_id := 0
	var rejected := ""
	var snapshots: Array = []
	var pongs: Array = []
