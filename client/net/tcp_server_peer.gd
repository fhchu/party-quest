extends "res://net/framed_peer.gd"
## Browsers reach this through the relay, one TCP connection per player;
## bots and tests connect directly.

var _server := TCPServer.new()
var _conns: Dictionary[int, Conn] = {}
var _status := CONNECTION_DISCONNECTED


class Conn:
	var tcp: StreamPeerTCP
	var link := Link.new()


func listen(port: int, bind_address: String) -> Error:
	var err := _server.listen(port, bind_address)
	if err == OK:
		_status = CONNECTION_CONNECTED
	return err


func _poll() -> void:
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if _refusing:
			tcp.disconnect_from_host()
			continue
		tcp.set_no_delay(true)
		var id := generate_unique_id()
		while id <= 1 or _conns.has(id):  # 1 is the server.
			id = generate_unique_id()
		var c := Conn.new()
		c.tcp = tcp
		c.link.unsent = Frames.prefixed(Frames.make(Frames.Kind.PEER_ID, Frames.u32(id)))
		_conns[id] = c
		peer_connected.emit(id)
	for id: int in _conns.keys():
		var c: Conn = _conns[id]
		if not _pump_tcp(c.tcp, c.link, _receive.bind(id, c.link)):
			_drop(id)


func _put_packet_script(packet: PackedByteArray) -> Error:
	# Godot's targets: > 0 one peer, 0 everyone, < 0 everyone but that peer.
	for id: int in _conns.keys():
		if _target > 0 and id != _target or _target < 0 and id == -_target:
			continue
		var c: Conn = _conns[id]
		c.link.unsent.append_array(Frames.prefixed(_frame(c.link, packet)))
		_flush_tcp(c.tcp, c.link)
	return OK


func _disconnect_peer(peer: int, force: bool) -> void:
	var c: Conn = _conns.get(peer)
	if c and not force:
		_flush_tcp(c.tcp, c.link)  # A kick's reason should still get out.
	if c:
		_drop(peer)


func _close() -> void:
	for c: Conn in _conns.values():
		c.tcp.disconnect_from_host()
	_conns.clear()
	_server.stop()
	_status = CONNECTION_DISCONNECTED


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _drop(id: int) -> void:
	_conns[id].tcp.disconnect_from_host()
	_conns.erase(id)
	# Godot logs an error for each packet from a peer it no longer lists.
	_incoming = _incoming.filter(func(p: Array) -> bool: return p[0] != id)
	peer_disconnected.emit(id)
