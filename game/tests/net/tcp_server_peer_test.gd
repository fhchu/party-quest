extends GdUnitTestSuite

const Frames := preload("res://net/frames.gd")
const TcpServerPeer := preload("res://net/tcp_server_peer.gd")


func test_dropping_a_peer_discards_its_queued_packets() -> void:
	var peer: TcpServerPeer = auto_free(TcpServerPeer.new())
	for id in [5, 6]:
		var c := TcpServerPeer.Conn.new()
		c.tcp = StreamPeerTCP.new()
		peer._conns[id] = c
		peer._receive(Frames.make(Frames.Kind.RELIABLE, PackedByteArray([id])), id, c.link)
	peer._drop(5)
	assert_int(peer._get_available_packet_count()).is_equal(1)
	assert_int(peer._get_packet_peer()).is_equal(6)
