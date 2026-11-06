extends Node
## Authoritative server for one room: maps connections onto the Room's
## seats, steps it from client input and broadcasts snapshots.
##
## Clients identify themselves with a session ID kept across reconnects, so a
## dropped player gets their seat back while the Room holds it.

const Room := preload("res://server/room.gd")
const Protocol := preload("res://net/protocol.gd")
const TcpServerPeer := preload("res://net/tcp_server_peer.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")

const REJECT_FULL := "room is full"
const REJECT_TAKEN_OVER := "joined from another tab"
## Loopback: browsers come through the relay on this machine.
const DEFAULT_BIND := "127.0.0.1"
## Gives a reject time to reach the client before its connection closes: a
## one-way trip, with room for a resend.
const KICK_DELAY_SEC := 1.0

var net: Node
var room: Room


func _physics_process(_delta: float) -> void:
	room.step(Time.get_ticks_msec())

	if room.world.tick % Protocol.SNAPSHOT_EVERY == 0:
		var to: Array[int] = []
		for seat in room.seats():
			if seat.state == Room.State.SILENT or seat.state == Room.State.ACTIVE:
				to.append(seat.peer_id)
		if not to.is_empty():
			var snap := SnapshotCodec.pack(room.world.snapshot())
			for peer_id in to:
				net.snapshot.rpc_id(peer_id, snap)


func start(port: int, bind_address := DEFAULT_BIND) -> Error:
	var peer := TcpServerPeer.new()
	var err := peer.listen(port, bind_address)
	if err != OK:
		return err
	room = Room.new()
	# Clients never message each other.
	multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.input_received.connect(_on_input)
	net.ping_received.connect(_on_ping)
	net.away_received.connect(_on_away)
	print("listening on %s:%d" % [bind_address, port])
	return OK


func _on_hello(peer_id: int, session_id: String) -> void:
	if room.seat_of_peer(peer_id):
		return
	var held := room.seat_of_session(session_id)
	if held and held.state != Room.State.DROPPED:
		# A reconnect or a duplicated tab. Unseat the old connection so its late
		# disconnect can't drop the player.
		_turn_away(held.peer_id, REJECT_TAKEN_OVER)
	var seat := room.join(session_id, peer_id)
	if not seat:
		_turn_away(peer_id, REJECT_FULL)
		return
	net.welcome.rpc_id(peer_id, seat.player_id)
	print("peer %d is seat %d" % [peer_id, seat.player_id])


func _on_input(peer_id: int, move: Vector2, attack_count: int) -> void:
	var seat := room.seat_of_peer(peer_id)
	if seat:
		room.input(seat, move, attack_count, Time.get_ticks_msec())


func _on_ping(peer_id: int, sent_at: float) -> void:
	net.pong.rpc_id(peer_id, sent_at)


func _on_away(peer_id: int, away: bool) -> void:
	var seat := room.seat_of_peer(peer_id)
	if seat:
		room.set_away(seat, away)
		print("seat %d %s" % [seat.player_id, "away" if away else "back"])


func _on_peer_disconnected(peer_id: int) -> void:
	print("peer %d disconnected" % peer_id)
	var seat := room.seat_of_peer(peer_id)
	if seat:
		room.drop(seat, Time.get_ticks_msec())


## Rejects [param peer_id] with [param reason] and closes its connection soon.
func _turn_away(peer_id: int, reason: String) -> void:
	net.reject.rpc_id(peer_id, reason)
	get_tree().create_timer(KICK_DELAY_SEC).timeout.connect(_kick.bind(peer_id))


func _kick(peer_id: int) -> void:
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
