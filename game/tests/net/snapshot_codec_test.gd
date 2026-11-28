extends GdUnitTestSuite

const RoomShape := preload("res://shared/room_shape.gd")
const Units := preload("res://tests/units.gd")
const Run := preload("res://server/run.gd")
const Snapshot := preload("res://net/snapshot.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const SnapshotSize := preload("res://tools/snapshot_size.gd")
const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Fire := preload("res://sim/fire.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const Lobby := preload("res://server/lobby.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const AttackCharge := preload("res://shared/data/attacks/attack_charge.gd")
const Projectile := preload("res://sim/projectile.gd")
const RoomState := preload("res://sim/room_state.gd")
const Items := preload("res://shared/data/items.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const ITEMS: Items = preload("res://shared/data/items.tres")

## Positions are sent in steps of 1 / POS_SCALE px.
const TOLERANCE := Vector2.ONE / SnapshotCodec.POS_SCALE
const BYTE_MAX := 0xff
const U16_MAX := 0xffff


## Any value its field holds.
const RUN_TICKS_LEFT := 1234

func _full_snapshot() -> Snapshot:
	var w := SnapshotSize.full_lobby(WorldLoader.TOWN.start)
	# Damaged and invulnerable, a unit just struck, so those fields carry
	# something.
	w.players[1].health = 1
	w.players[1].invulnerable_ticks = 1
	w.units[0].struck_tick = w.tick - 1
	w.units[0].facing = Vector2.from_angle(1.0)
	var shot := Projectile.new()
	shot.id = 7
	shot.pos = Vector2(10.5, 20.25)
	shot.radius = 2.5
	w.projectiles.append(shot)
	WorldSimulator.set_connected(w, 2, false)
	var snap := WorldSnapshot.of(w)
	snap.units[0].charge_windup_ticks_left = 1
	# Town's units are all the first unit type; the last one's number isn't 0.
	snap.units[0].unit_type = Units.UNITS.types.size() - 1
	snap.run_ticks_left = RUN_TICKS_LEFT
	snap.layout_number = LobbyState.BYTE_VALUES - 1
	snap.door_bits = RoomShape.door_bits([Direction.Cardinal.NORTH, Direction.Cardinal.WEST])
	snap.room_cleared = true
	snap.graphics_seed = U16_MAX
	return snap


func test_round_trip_keeps_every_field() -> void:
	var snap := _full_snapshot()
	assert_int(snap.players[0].slot_ticks[0]).is_greater(0)
	# A second slot, so each slot's value must land in its own place.
	snap.players[0].slot_ticks.append(Snapshot.SLOT_TICKS_MAX)
	var bytes := SnapshotCodec.pack(snap)
	var back := SnapshotCodec.unpack(bytes)
	assert_int(back.packed_size).is_equal(bytes.size())
	assert_int(back.tick).is_equal(snap.tick)
	assert_int(back.run_ticks_left).is_equal(snap.run_ticks_left)
	assert_int(back.layout_number).is_equal(snap.layout_number)
	assert_int(back.door_bits).is_equal(snap.door_bits)
	assert_bool(back.room_cleared).is_equal(snap.room_cleared)
	assert_int(back.graphics_seed).is_equal(snap.graphics_seed)
	assert_int(back.players.size()).is_equal(snap.players.size())
	for i in snap.players.size():
		_assert_player_kept(back.players[i], snap.players[i])
	assert_int(back.units.size()).is_equal(snap.units.size())
	for i in snap.units.size():
		_assert_unit_kept(back.units[i], snap.units[i])
	assert_int(back.projectiles.size()).is_equal(snap.projectiles.size())
	for i in snap.projectiles.size():
		_assert_shot_kept(back.projectiles[i], snap.projectiles[i])


func _assert_player_kept(b: Snapshot.Player, a: Snapshot.Player) -> void:
	assert_int(b.id).is_equal(a.id)
	assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
	assert_float(absf(b.facing.angle_to(a.facing))).is_less_equal(SnapshotCodec.FACING_STEP / 2)
	assert_array(b.slot_ticks).is_equal(a.slot_ticks)
	assert_bool(b.connected).is_equal(a.connected)
	assert_int(b.health).is_equal(a.health)
	assert_bool(b.invulnerable).is_equal(a.invulnerable)


func _assert_unit_kept(b: Snapshot.Unit, a: Snapshot.Unit) -> void:
	assert_int(b.id).is_equal(a.id)
	assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
	assert_float(absf(b.facing.angle_to(a.facing))).is_less_equal(SnapshotCodec.FACING_STEP / 2)
	assert_int(b.ticks_since_struck).is_equal(a.ticks_since_struck)
	assert_float(b.charge_windup_ticks_left).is_equal(a.charge_windup_ticks_left)
	assert_int(b.unit_type).is_equal(a.unit_type)


func _assert_shot_kept(b: Snapshot.Projectile, a: Snapshot.Projectile) -> void:
	assert_int(b.id).is_equal(a.id)
	assert_vector(b.pos).is_equal_approx(a.pos, TOLERANCE)
	assert_float(b.radius).is_equal(a.radius)


func test_a_full_lobby_fits_in_one_datagram_in_every_room() -> void:
	for room in _every_room():
		assert_int(SnapshotSize.packed_size(SnapshotSize.full_lobby(room))) \
				.override_failure_message("%s doesn't fit" % room.resource_path) \
				.is_less_equal(SnapshotCodec.MAX_SIZE)


func test_every_value_the_game_makes_fits_its_field() -> void:
	assert_float(WorldState.data.arena.end.x * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	assert_float(WorldState.data.arena.end.y * SnapshotCodec.POS_SCALE).is_less_equal(U16_MAX)
	for level in WorldLoader.level_count():
		assert_int(_run_timer_ticks(level)).override_failure_message(
				"level %d's timer" % level).is_less(Snapshot.NO_TIMER)
	assert_int(RoomState.GRAPHICS_SEED_VALUES - 1).is_less_equal(U16_MAX)
	for sword in _swords():
		assert_int(GameTime.ticks(sword.swing_active_sec)) \
				.override_failure_message("%s swings too long" % sword.resource_path) \
				.is_less_equal(Snapshot.SLOT_TICKS_MAX)
	assert_int(WorldState.data.player_max_health).is_less_equal(BYTE_MAX)
	assert_int(Lobby.MAX_PLAYERS).is_less_equal(BYTE_MAX)
	assert_int(SnapshotSize.full_lobby(WorldLoader.TOWN.start).units.size()) \
			.is_less_equal(BYTE_MAX)
	assert_int(Units.UNITS.types.size() - 1).is_less_equal(BYTE_MAX)
	assert_int(Snapshot.STRUCK_LONG_AGO).is_less_equal(BYTE_MAX)
	for charge in _charges():
		assert_int(GameTime.ticks(charge.aim_lock_sec)) \
				.override_failure_message("%s aims too long" % charge.resource_path) \
				.is_less_equal(BYTE_MAX)


func test_every_rooms_shots_fit_their_fields() -> void:
	for room in SnapshotSize.level_rooms():
		var lobby := SnapshotSize.full_lobby(room)
		assert_int(lobby.projectiles.size()).is_less_equal(BYTE_MAX)
		for fire in _shots(lobby):
			assert_float(fire.radius * SnapshotCodec.RADIUS_SCALE) \
					.override_failure_message("%s: a shot too big" % room.resource_path) \
					.is_less_equal(BYTE_MAX)


func test_truncated_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_snapshot())
	assert_object(SnapshotCodec.unpack(bytes.slice(0, bytes.size() - 1))).is_null()


func test_bytes_cut_inside_the_players_unpack_to_nothing() -> void:
	var snap := _full_snapshot()
	snap.units.clear()
	snap.projectiles.clear()
	var bytes := SnapshotCodec.pack(snap)
	for size in range(SnapshotCodec.HEADER_SIZE, bytes.size()):
		assert_object(SnapshotCodec.unpack(bytes.slice(0, size))) \
				.override_failure_message("cut to %d bytes" % size).is_null()


func test_extra_bytes_unpack_to_nothing() -> void:
	var bytes := SnapshotCodec.pack(_full_snapshot())
	bytes.append(0)
	assert_object(SnapshotCodec.unpack(bytes)).is_null()


func _every_room() -> Array[SnapshotSize.Room]:
	var out := SnapshotSize.rooms_of(WorldLoader.TOWN)
	out.append_array(SnapshotSize.level_rooms())
	return out


## Every shot the units in [param lobby] can fire.
func _shots(lobby: WorldState) -> Array[Fire]:
	var out: Array[Fire] = []
	for d in lobby.units:
		out.assign(out + d.attacks.filter(func(a: RefCounted) -> bool: return a is Fire))
	return out


func _swords() -> Array[ItemSword]:
	var out: Array[ItemSword] = []
	out.assign(ITEMS.items.filter(func(item: Resource) -> bool: return item is ItemSword))
	return out


func _charges() -> Array[AttackCharge]:
	var out: Array[AttackCharge] = []
	for unit_type in Units.UNITS.types:
		if unit_type.charge():
			out.append(unit_type.charge())
	return out


## Level [param level]'s run timer at its start.
func _run_timer_ticks(level: int) -> int:
	return WorldSnapshot.of(WorldSimulator.run(null, level)).run_ticks_left


func test_every_wall_has_a_door_bit() -> void:
	assert_int(Direction.Cardinal.size()).is_less_equal(Snapshot.DOOR_BIT_COUNT)
