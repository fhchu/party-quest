extends Node
## Authoritative server for one lobby: maps connections onto the Lobby's
## seats, steps it from client input and broadcasts snapshots and lobby
## state.
##
## Clients identify themselves with a session ID kept across reconnects, so a
## dropped player gets their seat back while the Lobby holds it.

const Lobby := preload("res://server/lobby.gd")
const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Match := preload("res://server/match.gd")
const TcpServerPeer := preload("res://server/tcp_server_peer.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const ClientTuning := preload("res://net/client_tuning.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")

## Loopback: browsers come through the relay on this machine.
const DEFAULT_BIND := "127.0.0.1"

## What every welcome carries. Balance is loaded once, so it never changes.
static var _client_tuning: PackedByteArray = _build_client_tuning().to_bytes()

var net: Node
## Gives a reject time to reach the client before its connection closes: a
## one-way trip, with room for a resend. Tests on loopback shorten it.
var kick_delay_sec := 1.0
## Quit once the lobby is abandoned (see [method Lobby.is_abandoned]).
var exit_when_empty := false
## DEBUG: accept the dev keys that end a match.
var dev := false
var lobby: Lobby


## The balance values every client draws with.
static func _build_client_tuning() -> ClientTuning:
	var t := ClientTuning.new()
	t.arena = Tuning.arena
	t.player_hurtbox = Tuning.player_hurtbox
	t.dummy_hurtbox = Tuning.dummy_hurtbox
	t.player_max_health = Tuning.player_max_health
	t.swing_arc = World.swing_arc_points()
	return t


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	lobby.step(now)
	if lobby.is_lobby_state_unsent():
		# Each copy names its receiver's seat, which can change in town.
		for seat in lobby.seats():
			if seat.peer_id:
				net.lobby_state.rpc_id(seat.peer_id, lobby.state(seat).to_bytes())
		lobby.mark_lobby_state_sent()

	if lobby.world.tick % Protocol.SNAPSHOT_EVERY == 0:
		var to: Array[int] = []
		for seat in lobby.seats():
			if seat.state == Lobby.State.SILENT or seat.state == Lobby.State.ACTIVE:
				to.append(seat.peer_id)
		if not to.is_empty():
			var snap := SnapshotCodec.pack(lobby.snapshot())
			for peer_id in to:
				net.snapshot.rpc_id(peer_id, snap)

	if exit_when_empty and lobby.is_abandoned(now):
		print("lobby empty for %d s, exiting" % Protocol.EMPTY_EXIT_SEC)
		get_tree().quit()


func start(port: int, bind_address := DEFAULT_BIND) -> Error:
	var peer := TcpServerPeer.new()
	var err := peer.listen(port, bind_address)
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
	net.dev_end_received.connect(_on_dev_end)
	print("listening on %s:%d" % [bind_address, port])
	return OK


func _on_hello(peer_id: int, version: int, session_id: String) -> void:
	if lobby.seat_of_peer(peer_id):
		return
	if version != Protocol.PROTOCOL_VERSION:
		_turn_away(peer_id, Protocol.RejectReason.VERSION)
		return
	var held := lobby.seat_of_session(session_id)
	if held and held.state != Lobby.State.DROPPED:
		# A reconnect or a duplicated tab. Unseat the old connection so its late
		# disconnect can't drop the player.
		_turn_away(held.peer_id, Protocol.RejectReason.DUPLICATE_SESSION)
	var seat := lobby.join(session_id, peer_id)
	if not seat:
		_turn_away(peer_id, Protocol.RejectReason.FULL)
		return
	net.welcome.rpc_id(peer_id, seat.player_id, _client_tuning)
	print("peer %d is seat %d%s" % [
		peer_id, seat.player_id,
		" (spectating)" if seat.readiness == LobbyState.Readiness.SPECTATING else ""])


func _on_input(peer_id: int, move: Vector2, attack_count: int) -> void:
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.input(seat, move, attack_count, Time.get_ticks_msec())


func _on_ping(peer_id: int, sent_at: float) -> void:
	net.pong.rpc_id(peer_id, sent_at)


func _on_away(peer_id: int, away: bool) -> void:
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.set_away(seat, away)
		print("seat %d %s" % [seat.player_id, "away" if away else "back"])


## DEBUG: a dev key ends the match, until players can die and lose.
func _on_dev_end(peer_id: int, won: bool) -> void:
	var running := lobby.phase as Match
	if dev and running and lobby.seat_of_peer(peer_id):
		var outcome := LobbyState.Outcome.WON if won else LobbyState.Outcome.LOST
		running.end_match(lobby, outcome, Time.get_ticks_msec())


func _on_peer_disconnected(peer_id: int) -> void:
	print("peer %d disconnected" % peer_id)
	var seat := lobby.seat_of_peer(peer_id)
	if seat:
		lobby.drop(seat)


## Rejects [param peer_id] with [param reason] and closes its connection soon.
func _turn_away(peer_id: int, reason: Protocol.RejectReason) -> void:
	net.reject.rpc_id(peer_id, reason)
	get_tree().create_timer(kick_delay_sec).timeout.connect(_kick.bind(peer_id))


func _kick(peer_id: int) -> void:
	if peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
