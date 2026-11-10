extends GdUnitTestSuite

const Snapshot := preload("res://net/snapshot.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const SnapshotSize := preload("res://tools/snapshot_size.gd")
const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")
const RoomState := preload("res://net/room_state.gd")

## Positions are sent in steps of 1 / POS_SCALE px.
const TOLERANCE := Vector2.ONE / SnapshotCodec.POS_SCALE
const BYTE_MAX := 0xff
const U16_MAX := 0xffff


func _full_snapshot() -> Snapshot:
	var w := SnapshotSize.full_room(World.Layout.LOBBY)
	# Damaged and invulnerable, a dummy just struck, so those fields carry
	# something.
	w.players[1].health = Tuning.player_max_health - 1
	w.players[1].invulnerable_ticks = 1
	w.dummies[0].struck_tick = w.tick - 1
	w.set_connected(2, false)
	var snap := w.snapshot()
	snap.match_ticks_left = Tuning.match_ticks
	snap.world_number = RoomState.BYTE_VALUES - 1
	return snap


func test_round_trip_keeps_every_field() -> void:
	var snap := _full_snapshot()
	assert_int(snap.players[0].swing_ticks).is_greater(0)
	var bytes := SnapshotCodec.pack(snap)
	var back := SnapshotCodec.unpack(bytes)
	assert_int(back.packed_size).is_equal(bytes.size())
	assert_int(back.tick).is_equal(snap.tick)
	assert_int(back.match_ticks_left).is_equal(snap.match_ticks_left)
	assert_int(back.world_number).is_equal(snap.world_number)
	assert_int(back.players.size()).is_equal(snap.players.size())
	for i in snap.players.size():
		var a := snap.players[i]
		var b := back.players[i]
		assert_int(b.id).is_equal(a.id)
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_vector(b.facing).is_equal_approx(a.facing, Vector2.ONE * 0.001)
		assert_int(b.swing_ticks).is_equal(a.swing_ticks)
		assert_bool(b.connected).is_equal(a.connected)
		assert_int(b.health).is_equal(a.health)
		assert_int(b.invulnerable_ticks).is_equal(a.invulnerable_ticks)
	assert_int(back.dummies.size()).is_equal(snap.dummies.size())
	for i in snap.dummies.size():
		var a := snap.dummies[i]
		var b := back.dummies[i]
		assert_int(b.id).is_equal(a.id)
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_int(b.ticks_since_struck).is_equal(a.ticks_since_struck)
		assert_int(b.kind).is_equal(a.kind)


func test_a_full_room_fits_in_one_datagram() -> void:
	for layout in [World.Layout.LOBBY, World.Layout.MATCH]:
		assert_int(SnapshotSize.packed_size(SnapshotSize.full_room(layout))) \
				.is_less_equal(SnapshotCodec.MAX_SIZE)


func test_every_value_the_game_makes_fits_its_field() -> void:
	assert_float(Tuning.arena.end.x * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	assert_float(Tuning.arena.end.y * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	assert_int(Tuning.match_ticks).is_less_equal(U16_MAX)
	assert_int(Tuning.swing_ticks).is_less_equal(BYTE_MAX)
	assert_int(Tuning.player_max_health).is_less_equal(BYTE_MAX)
	assert_int(Tuning.player_invulnerable_ticks).is_less_equal(BYTE_MAX)
	assert_int(Protocol.MAX_PLAYERS).is_less_equal(BYTE_MAX)
	assert_int(SnapshotSize.full_room(World.Layout.LOBBY).dummies.size()) \
			.is_less_equal(BYTE_MAX)
	assert_int((World.DIRECTIONS - 1) << SnapshotCodec.FACING_SHIFT).is_less_equal(BYTE_MAX)
	assert_int(World.Kind.size() - 1).is_less_equal(BYTE_MAX)
	assert_int(Snapshot.STRUCK_LONG_AGO).is_less_equal(BYTE_MAX)


func test_flag_bits_sit_below_the_packed_fields() -> void:
	assert_int(SnapshotCodec.PLAYER_CONNECTED).is_less(1 << SnapshotCodec.FACING_SHIFT)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_snapshot())
	assert_object(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_null()
