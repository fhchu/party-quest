extends GdUnitTestSuite

const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")

## Packing stores 32-bit floats.
const TOLERANCE := Vector2.ONE * 0.001


## A full room with each player facing its own way and mid-swing, so every
## field carries something.
func _full_world() -> World:
	var w := World.new()
	for id in range(1, Protocol.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, Vector2.from_angle(id * World.DIRECTION_STEP), 1)
	for i in ceili(Tuning.swing_ticks / 2.0):
		w.step()
	return w


func test_round_trip_keeps_every_field() -> void:
	var snap := _full_world().snapshot()
	assert_int(snap.players[0].swing_ticks).is_greater(0)
	var back := SnapshotCodec.unpack(SnapshotCodec.pack(snap))
	assert_int(back.tick).is_equal(snap.tick)
	assert_int(back.players.size()).is_equal(snap.players.size())
	for i in snap.players.size():
		var a := snap.players[i]
		var b := back.players[i]
		assert_int(b.id).is_equal(a.id)
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_vector(b.facing).is_equal_approx(a.facing, TOLERANCE)
		assert_int(b.swing_ticks).is_equal(a.swing_ticks)
		assert_bool(b.connected).is_equal(a.connected)
	assert_int(back.dummies.size()).is_equal(snap.dummies.size())
	for i in snap.dummies.size():
		var a := snap.dummies[i]
		var b := back.dummies[i]
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_bool(b.hit).is_equal(a.hit)
		assert_bool(b.target).is_equal(a.target)


func test_a_full_room_fits_in_one_datagram() -> void:
	var size := SnapshotCodec.pack(_full_world().snapshot()).size()
	assert_int(size).is_less_equal(SnapshotCodec.MAX_SIZE)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_world().snapshot())
	assert_object(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_null()
