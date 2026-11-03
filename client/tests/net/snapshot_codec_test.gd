extends GdUnitTestSuite

const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Protocol := preload("res://net/protocol.gd")


func _full_world() -> World:
	var w := World.new()
	for id in range(1, Protocol.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, World.snap8(Vector2.from_angle(id * 1.3)), 1)
	for i in 30:
		w.step()
	return w


func test_round_trip_keeps_the_layout() -> void:
	var snap := _full_world().snapshot()
	var back := SnapshotCodec.unpack(SnapshotCodec.pack(snap))
	assert_int(back[0]).is_equal(snap[0])
	for i in snap[1].size():
		var a: Array = snap[1][i]
		var b: Array = back[1][i]
		assert_int(b[0]).is_equal(a[0])
		assert_vector(b[1]).is_equal_approx(a[1], Vector2.ONE * 0.001)
		assert_vector(b[2]).is_equal_approx(a[2], Vector2.ONE * 0.001)
		assert_int(b[3]).is_equal(a[3])
		assert_bool(b[4]).is_equal(a[4])
	for i in snap[2].size():
		assert_vector(back[2][i][0]).is_equal_approx(snap[2][i][0], Vector2.ONE * 0.001)
		assert_array(back[2][i].slice(1)).is_equal(snap[2][i].slice(1))


func test_a_full_room_fits_in_one_datagram() -> void:
	var size := SnapshotCodec.pack(_full_world().snapshot()).size()
	assert_int(size).is_less_equal(SnapshotCodec.MAX_SIZE)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_world().snapshot())
	assert_array(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_empty()
