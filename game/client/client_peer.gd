extends "res://net/framed_peer.gd"
## Reports connected only once the server's first frame gives it a peer ID,
## as Godot's own WebSocket peer does.

var _id := 0
var _status := CONNECTION_CONNECTING
var _link := Link.new()


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _disconnect_peer(peer: int, _force: bool) -> void:
	if peer == TARGET_PEER_SERVER:
		close()


func _on_frame(frame: PackedByteArray) -> void:
	if _status == CONNECTION_CONNECTING:
		# Nothing else is sent before the peer ID.
		if frame[0] == Frames.Kind.PEER_ID and frame.size() >= Frames.PEER_ID_SIZE:
			_id = frame.decode_u32(Frames.KIND_SIZE)
			_status = CONNECTION_CONNECTED
			peer_connected.emit(TARGET_PEER_SERVER)
	elif _status == CONNECTION_CONNECTED and frame[0] != Frames.Kind.PEER_ID:
		_receive(frame, TARGET_PEER_SERVER, _link)


func _lost() -> void:
	var was := _status
	_status = CONNECTION_DISCONNECTED
	if was == CONNECTION_CONNECTED:
		peer_disconnected.emit(TARGET_PEER_SERVER)
