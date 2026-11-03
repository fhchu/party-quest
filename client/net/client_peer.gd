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
	if peer == 1:
		close()


func _on_frame(frame: PackedByteArray) -> void:
	if _status == CONNECTION_CONNECTING:
		# Nothing else is sent before the peer ID.
		if frame[0] == Frames.Kind.PEER_ID and frame.size() >= 5:
			_id = frame.decode_u32(1)
			_status = CONNECTION_CONNECTED
			peer_connected.emit(1)
	elif _status == CONNECTION_CONNECTED and frame[0] != Frames.Kind.PEER_ID:
		_receive(frame, 1, _link)


func _lost() -> void:
	var was := _status
	_status = CONNECTION_DISCONNECTED
	if was == CONNECTION_CONNECTED:
		peer_disconnected.emit(1)
