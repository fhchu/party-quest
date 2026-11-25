extends Node
## The single RPC endpoint.
##
## Server and client both add this node at the same path. Each side handles
## the calls meant for it and re-emits them as signals.

# Client -> server.
signal hello_received(peer_id: int, build_id: String, session_id: String)
signal input_received(
		peer_id: int, move: Vector2, press_counters: PackedByteArray, held_bits: int)
signal ping_received(peer_id: int, sent_at: float)
signal away_received(peer_id: int, away: bool)

# Server -> client.
signal welcomed(player_id: int)
signal rejected(reason: Protocol.RejectReason)
signal snapshot_received(snap: Snapshot)
signal pong_received(sent_at: float)
signal lobby_state_received(state: LobbyState)

const Net := preload("res://net/net.gd")
const InputCodec := preload("res://net/input_codec.gd")
const Protocol := preload("res://net/protocol.gd")
const Snapshot := preload("res://net/snapshot.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const LobbyState := preload("res://net/lobby_state.gd")


## Adds a Net to [param parent] and returns it. RPCs route by node path, so
## both sides give it the same name, and their entry scenes' roots must share
## a name too (tests/net/net_test.gd checks it).
static func add_to(parent: Node) -> Net:
	var net := Net.new()
	net.name = "Net"
	parent.add_child(net)
	return net


## Packs [param snap] once and sends it to each of [param peer_ids].
func send_snapshot(peer_ids: Array[int], snap: Snapshot) -> void:
	var data := SnapshotCodec.pack(snap)
	for peer_id in peer_ids:
		snapshot.rpc_id(peer_id, data)


func send_lobby_state(peer_id: int, state: LobbyState) -> void:
	lobby_state.rpc_id(peer_id, state.to_bytes())


## Sends this client's input to the server. [param press_counters] holds a
## running count of presses per input action, so a lost message can't lose a
## press; [param held_bits] a bit per input action held.
func send_input(move: Vector2, press_counters: PackedByteArray, held_bits: int) -> void:
	input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER,
			InputCodec.pack(move, press_counters, held_bits))


## [param build_id] is the sender's [method Protocol.build_id].
@rpc("any_peer", "reliable")
func hello(build_id: String, session_id: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), build_id, session_id)


## [param data] is packed by input_codec.gd.
@rpc("any_peer", "unreliable_ordered")
func input(data: PackedByteArray) -> void:
	var unpacked := InputCodec.unpack(data)
	if unpacked:
		input_received.emit(multiplayer.get_remote_sender_id(), unpacked.move,
				unpacked.press_counters, unpacked.held_bits)


@rpc("any_peer", "reliable")
func ping(sent_at: float) -> void:
	ping_received.emit(multiplayer.get_remote_sender_id(), sent_at)


## The client's tab was hidden or shown. No snapshots are sent while away.
@rpc("any_peer", "reliable")
func set_away(away: bool) -> void:
	away_received.emit(multiplayer.get_remote_sender_id(), away)


@rpc("authority", "reliable")
func welcome(player_id: int) -> void:
	welcomed.emit(player_id)


## [param reason] is a [enum Protocol.RejectReason].
@rpc("authority", "reliable")
func reject(reason: int) -> void:
	if reason not in Protocol.RejectReason.values():
		push_error("unknown reject reason %d" % reason)
		return
	rejected.emit(reason)


## [param data] is packed by snapshot_codec.gd to fit in one datagram.
@rpc("authority", "unreliable_ordered")
func snapshot(data: PackedByteArray) -> void:
	var snap := SnapshotCodec.unpack(data)
	if snap:
		snapshot_received.emit(snap)


@rpc("authority", "reliable")
func pong(sent_at: float) -> void:
	pong_received.emit(sent_at)


## [param data] is a LobbyState's bytes. Sent to every connected seat
## whenever it changes or someone joins.
@rpc("authority", "reliable")
func lobby_state(data: PackedByteArray) -> void:
	var state := LobbyState.new()
	if state.read(data):
		lobby_state_received.emit(state)
