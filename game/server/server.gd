extends Node
## Authoritative server for one lobby: maps connections onto the Lobby's
## seats, steps it from client input and broadcasts snapshots and lobby
## state.
##
## Clients identify themselves with a session ID kept across reconnects, so a
## dropped player gets their seat back while the Lobby holds it.

const Lobby := preload("res://server/lobby.gd")
const Net := preload("res://net/net.gd")
const Seat := preload("res://server/seat.gd")
const Protocol := preload("res://net/protocol.gd")
const TcpServerPeer := preload("res://server/tcp_server_peer.gd")

## Loopback: browsers come through the relay on this machine.
const BIND := "127.0.0.1"
var net: Net
## Quit once the lobby is abandoned (see [method Lobby.is_abandoned]).
## For a launcher that starts a server per lobby.
var exit_when_empty := false
var lobby: Lobby


func _physics_process(_delta: float) -> void:
	# Read the network right before stepping, so an input is applied on the
	# next tick. Godot's own poll comes after the frame's ticks, a frame late,
	# so whoever runs the server turns it off (server/main.gd).
	multiplayer.poll()
	var now := Time.get_ticks_msec()
	lobby.step(now)
	if lobby.is_lobby_state_unsent():
		# Each copy names its receiver's seat, which can change in town.
		for seat in lobby.seats():
			if seat.peer_id:
				net.send_lobby_state(seat.peer_id, lobby.state(seat))
		lobby.mark_lobby_state_sent()

	var to: Array[int] = []
	for seat in lobby.seats():
		if seat.connection == Seat.Connection.SILENT or seat.connection == Seat.Connection.ACTIVE:
			to.append(seat.peer_id)
	if not to.is_empty():
		net.send_snapshot(to, lobby.snapshot())

	if exit_when_empty and lobby.is_abandoned(now):
		print("lobby empty for %d s, exiting" % Lobby.EMPTY_EXIT_SEC)
		get_tree().quit()


func start(port := Protocol.GAME_PORT) -> Error:
	var peer := TcpServerPeer.new()
	var err := peer.listen(port, BIND)
	if err != OK:
		return err
	lobby = Lobby.new(Time.get_ticks_msec())
	# Clients never message each other.
	multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id: int) -> void: print("peer %d connected" % id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.input_received.connect(_on_input)
	net.ping_received.connect(_on_ping)
	net.away_received.connect(_on_away)
	print("listening on %s:%d" % [BIND, port])
	return OK


func _on_hello(peer_id: int, build_id: String, session_id: String) -> void:
	if lobby.seat_of_peer(peer_id):
		return
	if build_id != Protocol.build_id():
		_turn_away(peer_id, Protocol.RejectReason.VERSION)
		return
	var held := lobby.seat_of_session(session_id)
	if held and held.connection != Seat.Connection.DROPPED:
		# A reconnect or a duplicated tab. Unseat the old connection so its late
		# disconnect can't drop the player.
		_turn_away(held.peer_id, Protocol.RejectReason.DUPLICATE_SESSION)
	var seat := lobby.join(session_id, peer_id)
	if not seat:
		_turn_away(peer_id, Protocol.RejectReason.FULL)
		return
	net.welcome.rpc_id(peer_id, seat.player_id)
	print("peer %d is seat %d%s" % [
		peer_id, seat.player_id,
		" (spectating)" if seat.participation == Seat.Participation.SPECTATING else ""])


func _on_input(
		peer_id: int, move: Vector2, press_counters: PackedByteArray, held_bits: int) -> void:
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.input(seat, move, press_counters, held_bits, Time.get_ticks_msec())


func _on_ping(peer_id: int, sent_at: float) -> void:
	net.pong.rpc_id(peer_id, sent_at)


func _on_away(peer_id: int, away: bool) -> void:
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.set_away(seat, away)
		print("seat %d %s" % [seat.player_id, "away" if away else "back"])


func _on_peer_disconnected(peer_id: int) -> void:
	print("peer %d disconnected" % peer_id)
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.drop(seat)


## Rejects [param peer_id] with [param reason] and closes its connection at
## once. TCP delivers the reject before the close, and the relay keeps the
## browser's session open until it has it (finish in relay/relay.go).
func _turn_away(peer_id: int, reason: Protocol.RejectReason) -> void:
	net.reject.rpc_id(peer_id, reason)
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)
