extends GdUnitTestSuite

const Frames := preload("res://net/frames.gd")
const TcpServerPeer := preload("res://server/tcp_server_peer.gd")


func test_dropping_a_peer_discards_its_queued_packets() -> void:
	var peer: TcpServerPeer = auto_free(TcpServerPeer.new())
	var dropped := 5
	var kept := 6
	_queue_a_packet_from(peer, dropped)
	_queue_a_packet_from(peer, kept)
	peer._drop(dropped)
	assert_int(peer._get_available_packet_count()).is_equal(1)
	assert_int(peer._get_packet_peer()).is_equal(kept)


## Connects peer [param id] to [param peer] and queues a packet from it.
func _queue_a_packet_from(peer: TcpServerPeer, id: int) -> void:
	var c := TcpServerPeer.Conn.new()
	c.tcp = StreamPeerTCP.new()
	peer._conns[id] = c
	peer._receive(Frames.make(Frames.Kind.RELIABLE, PackedByteArray([id])), id, c.link)
