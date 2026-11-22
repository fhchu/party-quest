extends "res://net/framed_peer.gd"
## Reports connected only once the server's first frame gives it a peer ID,
## as Godot's own WebSocket peer does.
##
## With [member lag] set, packets both ways and the connection's status wait
## in one queue, so a reject still arrives before the close that follows it.

const LagSimulator := preload("res://client/lag_simulator.gd")

## Set before connecting; null sends and receives at once.
var lag: LagSimulator

var _id := 0
## What Godot sees: [member _transport_status] once [member lag] lets it
## through.
var _status := CONNECTION_CONNECTING
var _transport_status := CONNECTION_CONNECTING
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


# The queue is flushed even once the transport is gone, so a lost
# connection is reported after what arrived before it.
func _poll() -> void:
	if _transport_status != CONNECTION_DISCONNECTED:
		_poll_transport()
	if lag:
		lag.flush(_now(), func() -> bool: return _transport_status == CONNECTION_CONNECTED)


func _put_packet_script(packet: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	# Framed now, so sequence numbers follow the order of sends.
	var send := _send_frame.bind(_frame(_link, packet), _mode)
	if lag:
		lag.outgoing(_now(), send)
	else:
		send.call()
	return OK


func _close() -> void:
	drop_delayed()
	_close_transport()
	_transport_status = CONNECTION_DISCONNECTED
	_status = CONNECTION_DISCONNECTED


## Drops whatever [member lag] still holds.
func drop_delayed() -> void:
	if lag:
		lag.clear()


func _deliver(packet: Packet) -> void:
	_after_lag(func() -> void: _incoming.append(packet))


## Reads what the transport received, passing each frame to [method _on_frame]
## and calling [method _lost] once it's gone.
func _poll_transport() -> void:
	pass


## Sends one [param frame], with the transfer mode it was framed with.
func _send_frame(_frame_bytes: PackedByteArray, _frame_mode: TransferMode) -> void:
	pass


func _close_transport() -> void:
	pass


func _on_frame(frame: PackedByteArray) -> void:
	if _transport_status == CONNECTION_CONNECTING:
		# Nothing else is sent before the peer ID.
		if _is_peer_id_frame(frame):
			_transport_status = CONNECTION_CONNECTED
			var id := _peer_id_of(frame)
			_after_lag(func() -> void:
					_id = id
					_status = CONNECTION_CONNECTED
					peer_connected.emit(TARGET_PEER_SERVER))
	elif _transport_status == CONNECTION_CONNECTED and not _is_peer_id_frame(frame):
		_receive(frame, TARGET_PEER_SERVER, _link)


func _lost() -> void:
	_transport_status = CONNECTION_DISCONNECTED
	_after_lag(func() -> void:
			var was := _status
			_status = CONNECTION_DISCONNECTED
			if was == CONNECTION_CONNECTED:
				peer_disconnected.emit(TARGET_PEER_SERVER))


func _after_lag(f: Callable) -> void:
	if lag:
		lag.incoming(_now(), f)
	else:
		f.call()


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
