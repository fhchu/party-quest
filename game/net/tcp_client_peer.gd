extends "res://net/client_peer.gd"
## For bots and tests, which connect straight to the game server; browsers
## go through the relay.

var _tcp := StreamPeerTCP.new()
var _no_delay_set := false


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_tcp.poll()
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		return
	if not _no_delay_set and _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		# Otherwise TCP holds small packets back to batch them.
		_tcp.set_no_delay(true)
		_no_delay_set = true
	if not _pump_tcp(_tcp, _link, _on_frame):
		_lost()


func _put_packet_script(packet: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	_link.unsent.append_array(Frames.prefixed(_frame(_link, packet)))
	_flush_tcp(_tcp, _link)
	return OK


func _close() -> void:
	_tcp.disconnect_from_host()
	_status = CONNECTION_DISCONNECTED


func connect_to(host: String, port: int) -> Error:
	return _tcp.connect_to_host(host, port)
