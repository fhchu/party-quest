extends RefCounted
## A game server and its clients in this one process, each in its own branch
## of the tree with its own MultiplayerAPI, so RPCs travel over the real
## transport. As in production, Godot's own network polling is off: the
## server polls before each tick, and [method until] polls the clients.

const Net := preload("res://net/net.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const TcpClientPeer := preload("res://client/tcp_client_peer.gd")
const LagSimulator := preload("res://client/lag_simulator.gd")

## Long enough for a message to arrive and be acted on.
const SETTLE_SEC := GameTime.TICK_SEC * 2

## Far from the real ports, so tests can run beside ./dev.sh.
static var _next_port := 19400

var server: Server

var _tree: SceneTree
var _port: int
var _roots: Array[Node] = []
var _clients: Array[TestClient] = []
var _next_ping := 0


## Adds a server to [param tree]; [method start_error] starts it.
func _init(tree: SceneTree) -> void:
	_tree = tree
	_tree.set_multiplayer_poll_enabled(false)
	_port = _next_port
	_next_port += 1
	var root := _branch("Server%d" % _port, SceneMultiplayer.new())
	server = Server.new()
	server.net = root.get_node("Net")
	root.add_child(server)


## Whether the server started listening; call it once, right after making
## the driver.
func start_error() -> Error:
	return server.start(_port)


## Closes every connection and frees what the driver added to the tree.
func stop() -> void:
	for root in _roots:
		var api := _tree.get_multiplayer(root.get_path())
		api.multiplayer_peer.close()
		_tree.set_multiplayer(null, root.get_path())
		root.free()
	_roots.clear()
	_clients.clear()
	_tree.set_multiplayer_poll_enabled(true)


## A client that says hello as [param session] once connected. [param lag]
## delays its connection, as [code]?lag=[/code] does.
func join(session: String, build_id := Protocol.build_id(),
		lag: LagSimulator = null) -> TestClient:
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
	var peer := TcpClientPeer.new()
	peer.lag = lag
	peer.connect_to("127.0.0.1", _port)
	c.api.multiplayer_peer = peer
	_clients.append(c)
	return c


func leave(c: TestClient) -> void:
	c.api.multiplayer_peer.close()


## Waits up to [param timeout] seconds for [param cond] to be true. Replies
## need a few frames; 3 s is far beyond that, and still fails fast.
func until(cond: Callable, timeout := 3.0) -> bool:
	var end := Time.get_ticks_msec() + timeout * 1000
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		for c in _clients:
			c.api.poll()
		await _tree.process_frame
	return true


## Pings the server as [param c] and waits for the pong. TCP keeps order,
## so everything the server sent before reading the ping has arrived.
func round_trip(c: TestClient) -> bool:
	_next_ping += 1
	var sent := float(_next_ping)
	c.net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, sent)
	return await until(func() -> bool: return sent in c.pongs)


## Readies every seat and starts the run.
func start_run() -> void:
	for seat in server.lobby.seats():
		server.lobby.set_ready(seat, true)
	server.lobby.start_run(0)


## A branch of the tree with its own MultiplayerAPI and a Net node, like Main.
func _branch(root_name: String, api: MultiplayerAPI) -> Node:
	var root := Node.new()
	root.name = root_name
	_tree.root.add_child(root)
	_tree.set_multiplayer(api, root.get_path())
	Net.add_to(root)
	_roots.append(root)
	return root


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
