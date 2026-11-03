extends Node
## Authoritative server for one room: steps the World from client input and
## broadcasts snapshots.
##
## Clients identify themselves with a session ID kept across reconnects, so a
## dropped player gets their character back within
## [constant Protocol.RECONNECT_GRACE_SEC].

const World := preload("res://sim/world.gd")
const Protocol := preload("res://net/protocol.gd")
const TcpServerPeer := preload("res://net/tcp_server_peer.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")

const REJECT_FULL := "room is full"
const REJECT_TAKEN_OVER := "joined from another tab"

## SILENT: connected, no input yet or lately. AWAY: tab hidden, so input is
## ignored and no snapshots are sent. DROPPED: disconnected, kept for the
## grace period.
enum State { SILENT, ACTIVE, AWAY, DROPPED }

## Outlives its connection, so a reconnect gets the same player back.
class Seat:
	var player_id: int
	var peer_id := 0  # 0 while DROPPED; Godot peer IDs start at 1.
	var state := State.SILENT
	var since_msec := 0  # ACTIVE: the last input. DROPPED: the drop.

var net: Node
var world := World.new()

var _seats: Dictionary[String, Seat] = {}  # By session ID, which survives reconnects.
var _next_player_id := 1


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for session_id: String in _seats.keys():
		var seat := _seats[session_id]
		match seat.state:
			State.ACTIVE:
				# The client went quiet without disconnecting.
				if now - seat.since_msec > Protocol.INPUT_SILENCE_SEC * 1000:
					seat.state = State.SILENT
					world.set_input(seat.player_id, Vector2.ZERO, 0)
			State.DROPPED:
				if now - seat.since_msec > Protocol.RECONNECT_GRACE_SEC * 1000:
					_seats.erase(session_id)
					world.remove_player(seat.player_id)
					print("player %d removed after grace period" % seat.player_id)

	world.step()
	if world.tick % Protocol.SNAPSHOT_EVERY == 0:
		var to: Array[int] = []
		for seat: Seat in _seats.values():
			if seat.state == State.SILENT or seat.state == State.ACTIVE:
				to.append(seat.peer_id)
		if not to.is_empty():
			var snap := SnapshotCodec.pack(world.snapshot())
			for peer_id in to:
				net.snapshot.rpc_id(peer_id, snap)


## Loopback by default: browsers come through the relay on this machine.
func start(port: int, bind_address := "127.0.0.1") -> Error:
	var peer := TcpServerPeer.new()
	var err := peer.listen(port, bind_address)
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
	print("listening on %s:%d" % [bind_address, port])
	return OK


func _on_hello(peer_id: int, session_id: String) -> void:
	if _seat_of(peer_id):
		return
	var seat: Seat = _seats.get(session_id)
	if seat:
		# A reconnect or a duplicated tab. Unseat the old connection so its late
		# disconnect can't drop the player.
		if seat.state != State.DROPPED:
			net.reject.rpc_id(seat.peer_id, REJECT_TAKEN_OVER)
			_kick_soon(seat.peer_id)
	else:
		if _seats.size() >= Protocol.MAX_PLAYERS:
			net.reject.rpc_id(peer_id, REJECT_FULL)
			_kick_soon(peer_id)
			return
		seat = Seat.new()
		seat.player_id = _next_player_id
		_next_player_id += 1
		world.add_player(seat.player_id)
		_seats[session_id] = seat
	seat.peer_id = peer_id
	seat.state = State.SILENT
	world.set_connected(seat.player_id, true)
	net.welcome.rpc_id(peer_id, seat.player_id)
	print("peer %d is player %d" % [peer_id, seat.player_id])


## Gives a reject time to arrive before closing.
func _kick_soon(peer_id: int) -> void:
	get_tree().create_timer(1.0).timeout.connect(_kick.bind(peer_id))


func _kick(peer_id: int) -> void:
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _on_input(peer_id: int, _seq: int, move: Vector2, attack_count: int) -> void:
	var seat := _seat_of(peer_id)
	if seat and (seat.state == State.SILENT or seat.state == State.ACTIVE):
		seat.state = State.ACTIVE
		seat.since_msec = Time.get_ticks_msec()
		world.set_input(seat.player_id, move.limit_length(1.0), attack_count)


func _on_ping(peer_id: int, sent_at: float) -> void:
	net.pong.rpc_id(peer_id, sent_at)


## An away player stays connected and just stands still.
func _on_away(peer_id: int, away: bool) -> void:
	var seat := _seat_of(peer_id)
	if not seat or away == (seat.state == State.AWAY):
		return
	if away:
		seat.state = State.AWAY
		world.set_input(seat.player_id, Vector2.ZERO, 0)
	else:
		seat.state = State.SILENT
	print("player %d %s" % [seat.player_id, "away" if away else "back"])


func _on_peer_disconnected(peer_id: int) -> void:
	print("peer %d disconnected" % peer_id)
	var seat := _seat_of(peer_id)
	if seat:
		seat.state = State.DROPPED
		seat.peer_id = 0
		seat.since_msec = Time.get_ticks_msec()
		world.set_connected(seat.player_id, false)


## At most MAX_PLAYERS seats: a search is simpler than a second index to
## keep in sync.
func _seat_of(peer_id: int) -> Seat:
	for seat: Seat in _seats.values():
		if seat.peer_id == peer_id:
			return seat
	return null
