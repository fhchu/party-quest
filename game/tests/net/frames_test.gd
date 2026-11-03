extends GdUnitTestSuite

const Frames := preload("res://net/frames.gd")
const FramedPeer := preload("res://net/framed_peer.gd")


func test_reader_splits_a_stream_into_frames() -> void:
	var a := Frames.make(Frames.Kind.RELIABLE, PackedByteArray([1, 2, 3]))
	var b := Frames.make(Frames.Kind.UNRELIABLE, PackedByteArray([4]))
	var stream := Frames.prefixed(a) + Frames.prefixed(b)
	var reader := Frames.Reader.new()
	# One byte at a time, as a slow connection might deliver it.
	var out: Array[PackedByteArray] = []
	for byte in stream:
		reader.feed(PackedByteArray([byte]))
		var frame := reader.next()
		if not frame.is_empty():
			out.append(frame)
	assert_array(out).is_equal([a, b])


func test_reader_fails_on_an_oversized_length() -> void:
	var reader := Frames.Reader.new()
	reader.feed(Frames.u32(Frames.MAX_FRAME + 1))
	assert_array(reader.next()).is_empty()
	assert_bool(reader.failed).is_true()


func test_ordered_packets_that_arrive_late_are_dropped() -> void:
	var sender: FramedPeer = auto_free(FramedPeer.new())
	var receiver: FramedPeer = auto_free(FramedPeer.new())
	var out_link := FramedPeer.Link.new()
	var in_link := FramedPeer.Link.new()
	sender._set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	var first := sender._frame(out_link, PackedByteArray([1]))
	var second := sender._frame(out_link, PackedByteArray([2]))
	var from := 7
	receiver._receive(second, from, in_link)
	receiver._receive(first, from, in_link)
	assert_int(receiver._get_available_packet_count()).is_equal(1)
	assert_int(receiver._get_packet_peer()).is_equal(from)
	assert_int(receiver._get_packet_mode()).is_equal(
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	assert_array(receiver._get_packet_script()).is_equal(PackedByteArray([2]))


func test_reliable_and_unreliable_packets_all_arrive() -> void:
	var sender: FramedPeer = auto_free(FramedPeer.new())
	var receiver: FramedPeer = auto_free(FramedPeer.new())
	var link := FramedPeer.Link.new()
	for mode in [MultiplayerPeer.TRANSFER_MODE_RELIABLE, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE]:
		sender._set_transfer_mode(mode)
		receiver._receive(sender._frame(link, PackedByteArray([mode])), 1, link)
	assert_int(receiver._get_available_packet_count()).is_equal(2)
	assert_int(receiver._get_packet_mode()).is_equal(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
