extends "res://client/client_peer.gd"
## For bots and tests, which connect straight to the game server; browsers
## go through the relay.

var _tcp := StreamPeerTCP.new()
var _no_delay_set := false


func _poll_transport() -> void:
	_tcp.poll()
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		return
	if not _no_delay_set and _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		# Otherwise TCP holds small packets back to batch them.
		_tcp.set_no_delay(true)
		_no_delay_set = true
	if not _pump_tcp(_tcp, _link, _on_frame):
		_lost()


func _send_frame(frame: PackedByteArray, _frame_mode: TransferMode) -> void:
	_link.unsent.append_array(_stream(frame))
	_flush_tcp(_tcp, _link)


func _close_transport() -> void:
	_tcp.disconnect_from_host()


func connect_to(host: String, port: int) -> Error:
	return _tcp.connect_to_host(host, port)
