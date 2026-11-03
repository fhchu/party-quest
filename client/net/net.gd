extends Node
## The single RPC endpoint.
##
## Server and client both add this node at the same path. Each side handles
## the calls meant for it and re-emits them as signals.
## [codeblock]
## Snapshot: [tick, players, dummies]
##   players: [[id, pos, facing, swing_ticks_left, connected], ...]
##   dummies: [[pos, hit, target], ...]
## [/codeblock]

# Client -> server.
signal hello_received(peer_id: int, session_id: String)
signal input_received(peer_id: int, seq: int, move: Vector2, attack_count: int)
signal ping_received(peer_id: int, sent_at: float)
signal away_received(peer_id: int, away: bool)

# Server -> client.
signal welcomed(player_id: int)
signal rejected(reason: String)
signal snapshot_received(data: Array)
signal pong_received(sent_at: float)

const SnapshotCodec := preload("res://net/snapshot_codec.gd")


@rpc("any_peer", "reliable")
func hello(session_id: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), session_id)


## [param attack_count] is a running total of presses, so a lost message can't
## lose a press.
@rpc("any_peer", "unreliable_ordered")
func send_input(seq: int, move: Vector2, attack_count: int) -> void:
	input_received.emit(multiplayer.get_remote_sender_id(), seq, move, attack_count)


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


@rpc("authority", "reliable")
func reject(reason: String) -> void:
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
