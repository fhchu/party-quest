extends "res://tests/sim/world_fixture.gd"
## A shield in the player's second item slot: raising and lowering it, and
## what it blocks.

const Projectile := preload("res://sim/projectile.gd")
const DataRecords := preload("res://tests/data_records.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const Snapshot := preload("res://net/snapshot.gd")

const SHIELD_INPUT := 1
const SHIELD_THICKNESS := 2.0
const SHIELD_LENGTH := PLAYER_SIZE.y
const SHOT_RADIUS := 2.0
## px/s: 2 px a tick, so a shot never skips past the shield.
const SHOT_SPEED := 60.0
## Ticks for a shot placed just outside the player to reach it.
const SHOT_TICKS := 4


func before_test() -> void:
	super()
	var sword := _sword()
	var shield := ItemShield.new()
	shield.action = EquipItem.Action.GUARD
	shield.thickness_px = SHIELD_THICKNESS
	shield.length_px = SHIELD_LENGTH
	WorldSimulator.set_slot_item(world, PLAYER_ID, SWORD_INPUT, sword)
	WorldSimulator.set_slot_item(world, PLAYER_ID, SHIELD_INPUT, shield)
	_player().facing = Direction.Cardinal.EAST


## The raised shield in the shield's slot; null if it's down.
func _shield() -> RefCounted:
	return _player().slot_actions[SHIELD_INPUT].blocker()


## Presses the shield's input action and holds it, then steps; fails the
## test unless the shield is up.
func _raise() -> void:
	_send(PackedByteArray([0, 1]), true)
	WorldSimulator.step(world)
	assert_object(_shield()).is_not_null()


func _send(presses: PackedByteArray, held: bool, move := Vector2.ZERO) -> void:
	WorldSimulator.set_input(world, PLAYER_ID, move, presses, 1 << SHIELD_INPUT if held else 0)


## A shot just outside the player on side [param side], flying at it.
func _add_shot_from(side: Vector2) -> Projectile:
	var s := Projectile.new()
	s.pos = _player().pos + side * (PLAYER_SIZE.x / 2 + SHOT_RADIUS + 3.0)
	s.step = -side * SHOT_SPEED * GameTime.TICK_SEC
	s.radius = SHOT_RADIUS
	s.damage = 1
	s.push_px = 10.0
	s.push_ticks = 3
	world.projectiles.append(s)
	return s


## An enemy on side [param side], overlapping both the player's hurtbox and
## the strip along that side's edge.
func _add_enemy_on(side: Vector2) -> Dummy:
	var overlap := 1.0
	return _add_dummy(_player().pos + side * ((PLAYER_SIZE.x + DUMMY_SIZE.x) / 2 - overlap),
			DummyKinds.turret_kind)


func test_holding_without_a_new_press_doesnt_raise_it() -> void:
	_send(PackedByteArray([0, 0]), true)
	WorldSimulator.step(world)
	assert_object(_shield()).is_null()


func test_letting_go_lowers_it() -> void:
	_raise()
	_send(PackedByteArray([0, 0]), false)
	WorldSimulator.step(world)
	assert_object(_shield()).is_null()


func test_a_press_while_swinging_is_ignored_even_if_held_after() -> void:
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()
	_send(PackedByteArray([0, 1]), true)
	_advance(SWING_TICKS + 1)
	assert_bool(_is_swinging()).is_false()
	assert_object(_shield()).is_null()


func test_a_swing_lowers_it_and_holding_doesnt_bring_it_back() -> void:
	_raise()
	_send(PackedByteArray([1, 0]), true)
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()
	assert_object(_shield()).is_null()
	_advance(SWING_TICKS + 1)
	assert_object(_shield()).is_null()


func test_a_push_without_harm_leaves_it_up() -> void:
	_raise()
	_player().push(Vector2(10, 0), 3)
	assert_object(_shield()).is_not_null()


func test_entering_a_room_lowers_it() -> void:
	_raise()
	WorldSimulator.enter_room(world, DataRecords.new_room(false))
	assert_object(_shield()).is_null()


func test_a_shot_into_it_is_gone_harmlessly() -> void:
	_raise()
	_add_shot_from(Vector2.RIGHT)
	_advance(SHOT_TICKS)
	assert_array(world.projectiles).is_empty()
	assert_int(_player().health).is_equal(MAX_HEALTH)
	assert_bool(_player().is_pushed()).is_false()
	assert_object(_shield()).is_not_null()


func test_a_shot_from_behind_hurts_and_lowers_it() -> void:
	_raise()
	_add_shot_from(Vector2.LEFT)
	_advance(SHOT_TICKS)
	assert_int(_player().health).is_less(MAX_HEALTH)
	assert_object(_shield()).is_null()


func test_an_enemy_touching_it_pushes_without_hurting_and_it_stays_up() -> void:
	_raise()
	_add_enemy_on(Vector2.RIGHT)
	WorldSimulator.step(world)
	assert_int(_player().health).is_equal(MAX_HEALTH)
	assert_bool(_player().is_pushed()).is_true()
	assert_object(_shield()).is_not_null()


func test_an_enemy_behind_hurts_and_lowers_it() -> void:
	_raise()
	_add_enemy_on(Vector2.LEFT)
	WorldSimulator.step(world)
	assert_int(_player().health).is_less(MAX_HEALTH)
	assert_object(_shield()).is_null()


func test_it_turns_with_the_facing() -> void:
	_raise()
	_send(PackedByteArray([0, 0]), true, Vector2.UP)
	WorldSimulator.step(world)
	assert_int(_player().facing).is_equal(Direction.Cardinal.NORTH)
	_send(PackedByteArray([0, 0]), true)
	_add_shot_from(Vector2.UP)
	_advance(SHOT_TICKS)
	assert_array(world.projectiles).is_empty()
	assert_int(_player().health).is_equal(MAX_HEALTH)


func test_stopping_the_player_lowers_it() -> void:
	_raise()
	WorldSimulator.stop_player(world, PLAYER_ID)
	WorldSimulator.step(world)
	assert_object(_shield()).is_null()


func test_being_hurt_lowers_it() -> void:
	_raise()
	assert_bool(_player().lose_health(1)).is_true()
	assert_object(_shield()).is_null()


func test_the_snapshot_counts_a_raised_shield_up_and_stops_at_its_most() -> void:
	_raise()
	_advance(2)
	assert_int(WorldSnapshot.of(world).players[0].slot_ticks[SHIELD_INPUT]).is_equal(3)
	_advance(Snapshot.SLOT_TICKS_MAX)
	assert_int(WorldSnapshot.of(world).players[0].slot_ticks[SHIELD_INPUT]) \
			.is_equal(Snapshot.SLOT_TICKS_MAX)


func test_a_lowered_shield_reads_as_idle_in_the_snapshot() -> void:
	_raise()
	_send(PackedByteArray([0, 0]), false)
	WorldSimulator.step(world)
	assert_int(WorldSnapshot.of(world).players[0].slot_ticks[SHIELD_INPUT]).is_zero()
