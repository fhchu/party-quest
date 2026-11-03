extends GdUnitTestSuite
## Server and clients run in this one process, each in its own branch of the
## tree with its own MultiplayerAPI, so RPCs travel over the real transport.

const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")
const TcpClientPeer := preload("res://net/tcp_client_peer.gd")

const SNAP_INTERVAL := float(Protocol.SNAPSHOT_EVERY) / Protocol.TICK_RATE

static var _next_port := 19400

var _port: int
var _server: Server
var _roots: Array[Node] = []


class TestClient:
	var api := SceneMultiplayer.new()
	var net: Node
	var player_id := 0
	var rejected := ""
	var snapshots: Array = []
	var pongs: Array = []


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
	c.net.snapshot_received.connect(func(data: Array) -> void: c.snapshots.append(data))
	c.net.pong_received.connect(func(sent_at: float) -> void: c.pongs.append(sent_at))
	c.api.connected_to_server.connect(func() -> void: c.net.hello.rpc_id(1, session))
	c.api.multiplayer_peer = _client_peer()
	return c


func _leave(c: TestClient) -> void:
	c.api.multiplayer_peer.close()


## Waits up to [param timeout] seconds for [param cond] to be true.
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
	var players: Array = a.snapshots.back()[1]
	assert_int(players[0][0]).is_equal(a.player_id)


func test_input_moves_the_player() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	var start: Vector2 = _server.world.players[a.player_id].pos
	var moved := func() -> bool:
		a.net.send_input.rpc_id(1, 0, Vector2.RIGHT, 0)
		return _server.world.players[a.player_id].pos.x > start.x
	assert_bool(await _until(moved)).is_true()


func test_input_silence_stops_the_player() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.send_input.rpc_id(1, 0, Vector2.RIGHT, 0)
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


func test_one_player_too_many_is_rejected() -> void:
	var clients: Array[TestClient] = []
	for i in Protocol.MAX_PLAYERS:
		clients.append(_join("p%d" % i))
	var all_in := func() -> bool: return clients.all(func(c: TestClient) -> bool: return c.player_id)
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
	a.net.set_away.rpc_id(1, true)
	await _wait(SNAP_INTERVAL * 4)  # Let snapshots already sent arrive.
	a.snapshots.clear()
	await _wait(SNAP_INTERVAL * 6)  # Long enough for several to have come.
	assert_array(a.snapshots).is_empty()
	a.net.set_away.rpc_id(1, false)
	assert_bool(await _until(func() -> bool: return not a.snapshots.is_empty())).is_true()


func test_ping_is_echoed() -> void:
	var a := _join("a")
	assert_bool(await _until(func() -> bool: return a.player_id != 0)).is_true()
	a.net.ping.rpc_id(1, 12.5)
	assert_bool(await _until(func() -> bool: return not a.pongs.is_empty())).is_true()
	assert_float(a.pongs[0]).is_equal(12.5)
