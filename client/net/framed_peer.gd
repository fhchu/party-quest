extends MultiplayerPeerExtension
## Base of every match transport.

const Frames := preload("res://net/frames.gd")

## More unsent data than this means the other end stopped reading.
const MAX_UNSENT := 1 << 20

var _incoming: Array = []  # [from peer, transfer mode, packet], oldest first.
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false


class Link:
	var reader := Frames.Reader.new()
	var unsent := PackedByteArray()
	var send_seq := 0
	var recv_seq := -1


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	return _incoming.pop_front()[2]


# Godot asks for a packet's sender and mode before taking it, so these look
# at the oldest one.
func _get_packet_peer() -> int:
	return _incoming[0][0] if _incoming else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[0][1] if _incoming else TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return 0


func _get_max_packet_size() -> int:
	return Frames.MAX_FRAME - Frames.HEADER_MAX


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


## Channels aren't used; everything shares one.
func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _is_server_relay_supported() -> bool:
	return false


## Ordered packets are numbered so the receiver can drop ones that arrive
## after a newer one.
func _frame(link: Link, packet: PackedByteArray) -> PackedByteArray:
	match _mode:
		TRANSFER_MODE_RELIABLE:
			return Frames.make(Frames.Kind.RELIABLE, packet)
		TRANSFER_MODE_UNRELIABLE:
			return Frames.make(Frames.Kind.UNRELIABLE, packet)
	link.send_seq += 1
	var payload := Frames.u32(link.send_seq)
	payload.append_array(packet)
	return Frames.make(Frames.Kind.ORDERED, payload)


func _receive(frame: PackedByteArray, from: int, link: Link) -> void:
	match frame[0]:
		Frames.Kind.RELIABLE:
			_incoming.append([from, TRANSFER_MODE_RELIABLE, frame.slice(1)])
		Frames.Kind.UNRELIABLE:
			_incoming.append([from, TRANSFER_MODE_UNRELIABLE, frame.slice(1)])
		Frames.Kind.ORDERED:
			if frame.size() < 5:
				return
			var seq := frame.decode_u32(1)
			if seq <= link.recv_seq:
				return  # A newer one was already handled.
			link.recv_seq = seq
			_incoming.append([from, TRANSFER_MODE_UNRELIABLE_ORDERED, frame.slice(5)])


## Returns false once the connection should be dropped.
func _pump_tcp(tcp: StreamPeerTCP, link: Link, on_frame: Callable) -> bool:
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var available := tcp.get_available_bytes()
	if available > 0:
		var got: Array = tcp.get_partial_data(available)
		if got[0] != OK:
			return false
		link.reader.feed(got[1])
	var frame := link.reader.next()
	while not frame.is_empty():
		on_frame.call(frame)
		frame = link.reader.next()
	return not link.reader.failed and _flush_tcp(tcp, link)


## Partial writes, so a slow connection never stalls the game loop.
func _flush_tcp(tcp: StreamPeerTCP, link: Link) -> bool:
	if link.unsent.is_empty():
		return true
	var sent: Array = tcp.put_partial_data(link.unsent)
	if sent[0] != OK:
		return false
	link.unsent = link.unsent.slice(sent[1])
	return link.unsent.size() <= MAX_UNSENT
