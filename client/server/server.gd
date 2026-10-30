extends Node
## Authoritative game server for a single room. Clients send input, the
## server steps the World at TICK_RATE and broadcasts snapshots.
##
## A client identifies itself with a session ID it keeps across reconnects, so
## a player whose socket drops (e.g. a laptop sleeping) gets their
## character back if they return within RECONNECT_GRACE_SEC.

const World := preload("res://sim/world.gd")
const Protocol := preload("res://net/protocol.gd")

var net: Node
var world := World.new()

var _player_by_peer := {}  # peer id -> player id
var _player_by_session := {}  # session id -> player id
var _dropped_at := {}  # player id -> msec when their peer disconnected
var _next_player_id := 1


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for player_id: int in _dropped_at.keys():
		if now - _dropped_at[player_id] > Protocol.RECONNECT_GRACE_SEC * 1000:
			_dropped_at.erase(player_id)
			world.remove_player(player_id)
			print("player %d removed after grace period" % player_id)

	world.step()
	if world.tick % Protocol.SNAPSHOT_EVERY == 0 and not _player_by_peer.is_empty():
		var snap := world.snapshot()
		for peer_id: int in _player_by_peer:
			if _is_open(peer_id):
				net.snapshot.rpc_id(peer_id, snap)


func start(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	# Clients only talk to the server, never to each other through it.
	multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id: int) -> void: print("peer %d connected" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.input_received.connect(_on_input)
	net.ping_received.connect(_on_ping)
	print("listening on :%d" % port)
	return OK


func _on_hello(peer_id: int, session_id: String) -> void:
	if _player_by_peer.has(peer_id):
		return
	var player_id: int = _player_by_session.get(session_id, 0)
	if world.players.has(player_id):
		# A socket that died silently may not have disconnected yet. Drop it
		# now so its late disconnect doesn't mark the returning player as gone.
		var old_peer = _player_by_peer.find_key(player_id)
		if old_peer != null:
			_player_by_peer.erase(old_peer)
			_kick(old_peer)
	else:
		if world.players.size() >= Protocol.MAX_PLAYERS:
			net.reject.rpc_id(peer_id, "room is full")
			# Give the reject message time to arrive before closing.
			get_tree().create_timer(1.0).timeout.connect(_kick.bind(peer_id))
			return
		player_id = _next_player_id
		_next_player_id += 1
		world.add_player(player_id)
		_player_by_session[session_id] = player_id
	world.set_connected(player_id, true)
	_dropped_at.erase(player_id)
	_player_by_peer[peer_id] = player_id
	net.welcome.rpc_id(peer_id, player_id)
	print("peer %d is player %d" % [peer_id, player_id])


func _kick(peer_id: int) -> void:
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _on_input(peer_id: int, _seq: int, move: Vector2, attack_count: int) -> void:
	var player_id: int = _player_by_peer.get(peer_id, 0)
	if player_id:
		world.set_input(player_id, move.limit_length(1.0), attack_count)


func _on_ping(peer_id: int, sent_at: float) -> void:
	if _is_open(peer_id):
		net.pong.rpc_id(peer_id, sent_at)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_id: int = _player_by_peer.get(peer_id, 0)
	_player_by_peer.erase(peer_id)
	print("peer %d disconnected" % peer_id)
	if player_id:
		world.set_connected(player_id, false)
		_dropped_at[player_id] = Time.get_ticks_msec()


## A closing socket stays listed as a peer until its disconnect fires, and
## sending to it logs an error.
func _is_open(peer_id: int) -> bool:
	var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	return ws.get_peer(peer_id).get_ready_state() == WebSocketPeer.STATE_OPEN
