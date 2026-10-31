extends Node
## Authoritative server for one room: steps the World from client input and
## broadcasts snapshots.
##
## Clients identify themselves with a session ID kept across reconnects, so a
## dropped player gets their character back within
## [constant Protocol.RECONNECT_GRACE_SEC].

const World := preload("res://sim/world.gd")
const Protocol := preload("res://net/protocol.gd")

var net: Node
var world := World.new()

var _player_by_peer: Dictionary[int, int] = {}
var _player_by_session: Dictionary[String, int] = {}
var _dropped_at: Dictionary[int, int] = {}  # player id -> msec
var _last_input_at: Dictionary[int, int] = {}  # player id -> msec
var _away: Dictionary[int, bool] = {}  # peer ids with a hidden tab
var _next_player_id := 1


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for player_id: int in _dropped_at.keys():
		if now - _dropped_at[player_id] > Protocol.RECONNECT_GRACE_SEC * 1000:
			_dropped_at.erase(player_id)
			world.remove_player(player_id)
			print("player %d removed after grace period" % player_id)

	# Stop players whose client went quiet without disconnecting.
	for player_id: int in _last_input_at.keys():
		if now - _last_input_at[player_id] > Protocol.INPUT_SILENCE_SEC * 1000:
			_last_input_at.erase(player_id)
			world.set_input(player_id, Vector2.ZERO, 0)

	world.step()
	if world.tick % Protocol.SNAPSHOT_EVERY == 0 and not _player_by_peer.is_empty():
		var snap := world.snapshot()
		for peer_id: int in _player_by_peer:
			if _is_open(peer_id) and not _away.has(peer_id):
				net.snapshot.rpc_id(peer_id, snap)


func start(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.server_relay = false  # Clients never message each other.
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id: int) -> void: print("peer %d connected" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.input_received.connect(_on_input)
	net.ping_received.connect(_on_ping)
	net.away_received.connect(_on_away)
	print("listening on :%d" % port)
	return OK


func _on_hello(peer_id: int, session_id: String) -> void:
	if _player_by_peer.has(peer_id):
		return
	var player_id: int = _player_by_session.get(session_id, 0)
	if world.players.has(player_id):
		# The session's old peer may still be listed: a dead socket not yet
		# noticed, or a duplicated tab. Unlink it so its late disconnect doesn't
		# drop the player, and tell it why if it's still open.
		var old_peer = _player_by_peer.find_key(player_id)
		if old_peer != null:
			_player_by_peer.erase(old_peer)
			if _is_open(old_peer):
				net.reject.rpc_id(old_peer, "joined from another tab")
				get_tree().create_timer(1.0).timeout.connect(_kick.bind(old_peer))
			else:
				_kick(old_peer)
	else:
		if world.players.size() >= Protocol.MAX_PLAYERS:
			net.reject.rpc_id(peer_id, "room is full")
			# Give the reject time to arrive before closing.
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
	if player_id and not _away.has(peer_id):
		_last_input_at[player_id] = Time.get_ticks_msec()
		world.set_input(player_id, move.limit_length(1.0), attack_count)


func _on_ping(peer_id: int, sent_at: float) -> void:
	if _is_open(peer_id):
		net.pong.rpc_id(peer_id, sent_at)


## An away player stays connected and just stands still.
func _on_away(peer_id: int, away: bool) -> void:
	var player_id: int = _player_by_peer.get(peer_id, 0)
	if not player_id:
		return
	if away:
		_away[peer_id] = true
		_last_input_at.erase(player_id)
		world.set_input(player_id, Vector2.ZERO, 0)
	else:
		_away.erase(peer_id)
	print("player %d %s" % [player_id, "away" if away else "back"])


func _on_peer_disconnected(peer_id: int) -> void:
	var player_id: int = _player_by_peer.get(peer_id, 0)
	_player_by_peer.erase(peer_id)
	_away.erase(peer_id)
	print("peer %d disconnected" % peer_id)
	if player_id:
		world.set_connected(player_id, false)
		_dropped_at[player_id] = Time.get_ticks_msec()


## A closing socket is still listed as a peer until its disconnect fires, and
## sending to it logs an error.
func _is_open(peer_id: int) -> bool:
	var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	return ws.get_peer(peer_id).get_ready_state() == WebSocketPeer.STATE_OPEN
