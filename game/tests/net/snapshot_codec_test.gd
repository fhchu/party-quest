extends GdUnitTestSuite

const Snapshot := preload("res://net/snapshot.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")

## Packing stores 32-bit floats.
const TOLERANCE := Vector2.ONE * 0.001


## A full room in [param layout], each player facing its own way and
## mid-swing, so every field carries something.
func _full_world(layout := World.Layout.LOBBY) -> World:
	var w := World.new(layout)
	for id in range(1, Protocol.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, Vector2.from_angle(id * World.DIRECTION_STEP), 1)
	for i in ceili(Tuning.swing_ticks / 2.0):
		w.step()
	return w


func _full_snapshot() -> Snapshot:
	var w := _full_world()
	# Damaged and invulnerable, a dummy flashing, so those fields carry
	# something.
	w.players[1].health = Tuning.player_max_health - 1
	w.players[1].invulnerable_ticks = 1
	w.dummies[0].flash_ticks = 1
	w.set_connected(2, false)
	return w.snapshot()


func test_round_trip_keeps_every_field() -> void:
	var snap := _full_snapshot()
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
		assert_int(b.health).is_equal(a.health)
		assert_bool(b.invulnerable).is_equal(a.invulnerable)
	assert_int(back.dummies.size()).is_equal(snap.dummies.size())
	for i in snap.dummies.size():
		var a := snap.dummies[i]
		var b := back.dummies[i]
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_bool(b.flashing).is_equal(a.flashing)
		assert_int(b.kind).is_equal(a.kind)


func test_a_full_room_fits_in_one_datagram() -> void:
	for layout in [World.Layout.LOBBY, World.Layout.MATCH]:
		assert_int(SnapshotCodec.pack(_full_world(layout).snapshot()).size()) \
				.is_less_equal(SnapshotCodec.MAX_SIZE)


func test_every_value_the_game_makes_fits_its_field() -> void:
	assert_int(Tuning.player_max_health).is_less_equal(0xff)
	assert_int((World.Kind.size() - 1) << SnapshotCodec.KIND_SHIFT).is_less_equal(0xff)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_snapshot())
	assert_object(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_null()
