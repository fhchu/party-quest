extends Node
## The single RPC endpoint. Server and client both add this node at the same
## path; each side handles only the calls meant for it, re-emitted as signals.
##
## Snapshot layout: [tick, players, dummies]
##   players: [[id, pos: Vector2, facing: Vector2, swing_ticks_left, connected], ...]
##   dummies: [[pos: Vector2, hit: bool], ...]

# Client -> server.
signal hello_received(peer_id: int, session_id: String)
signal input_received(peer_id: int, seq: int, move: Vector2, attack_count: int)
signal ping_received(peer_id: int, sent_at: float)

# Server -> client.
signal welcomed(player_id: int)
signal rejected(reason: String)
signal snapshot_received(data: Array)
signal pong_received(sent_at: float)


@rpc("any_peer", "reliable")
func hello(session_id: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), session_id)


## attack_count is a running total of presses rather than a flag, so a press
## isn't lost if an input message is.
@rpc("any_peer", "unreliable_ordered")
func send_input(seq: int, move: Vector2, attack_count: int) -> void:
	input_received.emit(multiplayer.get_remote_sender_id(), seq, move, attack_count)


@rpc("any_peer", "reliable")
func ping(sent_at: float) -> void:
	ping_received.emit(multiplayer.get_remote_sender_id(), sent_at)


@rpc("authority", "reliable")
func welcome(player_id: int) -> void:
	welcomed.emit(player_id)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


@rpc("authority", "unreliable_ordered")
func snapshot(data: Array) -> void:
	snapshot_received.emit(data)


@rpc("authority", "reliable")
func pong(sent_at: float) -> void:
	pong_received.emit(sent_at)
