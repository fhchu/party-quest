extends GdUnitTestSuite

const Snapshot := preload("res://net/snapshot.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const SnapshotSize := preload("res://tools/snapshot_size.gd")
const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")

## Positions are sent in steps of 1 / POS_SCALE px.
const TOLERANCE := Vector2.ONE / SnapshotCodec.POS_SCALE
const BYTE_MAX := 0xff
const U16_MAX := 0xffff


func _full_snapshot() -> Snapshot:
	var w := SnapshotSize.full_lobby(World.Layout.TOWN)
	# Damaged and invulnerable, a dummy just struck, so those fields carry
	# something.
	w.players[1].health = Tuning.player_max_health - 1
	w.players[1].invulnerable_ticks = 1
	w.dummies[0].struck_tick = w.tick - 1
	w.dummies[0].facing = Vector2.from_angle(1.0)
	var shot := World.Projectile.new()
	shot.id = 7
	shot.pos = Vector2(10.5, 20.25)
	shot.radius = 2.5
	w.projectiles.append(shot)
	w.set_connected(2, false)
	var snap := w.snapshot()
	snap.match_ticks_left = Tuning.match_ticks
	snap.world_number = LobbyState.BYTE_VALUES - 1
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
		assert_bool(b.invulnerable).is_equal(a.invulnerable)
	assert_int(back.dummies.size()).is_equal(snap.dummies.size())
	for i in snap.dummies.size():
		var a := snap.dummies[i]
		var b := back.dummies[i]
		assert_int(b.id).is_equal(a.id)
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_float(absf(b.facing.angle_to(a.facing))) \
				.is_less_equal(SnapshotCodec.DUMMY_FACING_STEP / 2)
		assert_int(b.ticks_since_struck).is_equal(a.ticks_since_struck)
		assert_int(b.kind).is_equal(a.kind)
	assert_int(back.projectiles.size()).is_equal(snap.projectiles.size())
	for i in snap.projectiles.size():
		var a := snap.projectiles[i]
		var b := back.projectiles[i]
		assert_int(b.id).is_equal(a.id)
		assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
		assert_float(b.radius).is_equal(a.radius)


func test_a_full_lobby_fits_in_one_datagram() -> void:
	for layout in [World.Layout.TOWN, World.Layout.MATCH]:
		assert_int(SnapshotSize.packed_size(SnapshotSize.full_lobby(layout))) \
				.is_less_equal(SnapshotCodec.MAX_SIZE)


func test_every_value_the_game_makes_fits_its_field() -> void:
	assert_float(Tuning.arena.end.x * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	assert_float(Tuning.arena.end.y * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	assert_int(Tuning.match_ticks).is_less_equal(U16_MAX)
	assert_int(Tuning.swing_ticks).is_less_equal(BYTE_MAX)
	assert_int(Tuning.player_max_health).is_less_equal(BYTE_MAX)
	assert_int(Protocol.MAX_PLAYERS).is_less_equal(BYTE_MAX)
	assert_int(SnapshotSize.full_lobby(World.Layout.TOWN).dummies.size()) \
			.is_less_equal(BYTE_MAX)
	assert_int((Protocol.DIRECTIONS - 1) << SnapshotCodec.FACING_SHIFT).is_less_equal(BYTE_MAX)
	assert_int(Protocol.DummyKind.size() - 1).is_less_equal(BYTE_MAX)
	assert_int(Snapshot.STRUCK_LONG_AGO).is_less_equal(BYTE_MAX)
	var in_match := SnapshotSize.full_lobby(World.Layout.MATCH)
	assert_int(in_match.projectiles.size()).is_less_equal(BYTE_MAX)
	# Every dummy and every shot of a match gets its own ID.
	var ids := in_match.dummies.size()
	for d in in_match.dummies:
		assert_float(d.projectile_radius * SnapshotCodec.RADIUS_SCALE).is_less_equal(BYTE_MAX)
		if d.fire_interval_ticks > 0:
			ids += ceili(float(Tuning.match_ticks) / d.fire_interval_ticks)
	assert_int(ids).is_less_equal(U16_MAX)


func test_flag_bits_sit_below_the_packed_fields() -> void:
	var player_flags := SnapshotCodec.PLAYER_CONNECTED | SnapshotCodec.PLAYER_INVULNERABLE
	assert_int(player_flags).is_less(1 << SnapshotCodec.FACING_SHIFT)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_snapshot())
	assert_object(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_null()


func test_a_dummy_of_an_unknown_kind_unpacks_to_nothing() -> void:
	var snap := Snapshot.new()
	var d := Snapshot.Dummy.new()
	d.kind = Protocol.DummyKind.size() as Protocol.DummyKind
	snap.dummies.append(d)
	assert_object(SnapshotCodec.unpack(SnapshotCodec.pack(snap))).is_null()
