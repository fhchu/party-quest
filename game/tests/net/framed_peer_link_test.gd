extends GdUnitTestSuite
## Ordered frames on one link: which are taken, and the loss counts.

const FramedPeer := preload("res://net/framed_peer.gd")


func test_frames_in_order_are_all_taken() -> void:
	var link := FramedPeer.Link.new()
	for seq in [1, 2, 3]:
		assert_bool(link.take_ordered(seq)).is_true()
	assert_int(link.frames_received).is_equal(3)
	assert_int(link.frames_missed).is_zero()
	assert_int(link.frames_late).is_zero()


func test_a_gap_counts_the_frames_skipped() -> void:
	var link := FramedPeer.Link.new()
	link.take_ordered(1)
	link.take_ordered(5)
	assert_int(link.frames_missed).is_equal(3)
	assert_int(link.frames_received).is_equal(2)


func test_a_frame_after_a_newer_one_is_dropped_as_late() -> void:
	var link := FramedPeer.Link.new()
	link.take_ordered(1)
	link.take_ordered(3)
	assert_bool(link.take_ordered(2)).is_false()
	assert_int(link.frames_late).is_equal(1)
	assert_int(link.frames_missed).is_equal(1)
	assert_int(link.frames_received).is_equal(2)
