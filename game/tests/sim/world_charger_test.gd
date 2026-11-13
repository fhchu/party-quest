extends "res://tests/sim/world_fixture.gd"
## A charger: a dummy that walks toward the nearest living player and, once
## a charge would reach them, locks its aim and charges in a straight line.

const Dummy := preload("res://sim/dummy.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")

const ATTACK_INTERVAL_TICKS := 30
const AIM_LOCK_TICKS := 6
const RADIUS := 8.0
const WALK_STEP := 1.0
const CHARGE_STEP := 4.0
const CHARGE_LENGTH := 48.0
const OTHER_ID := PLAYER_ID + 1
## Between the charger's edge and the player's: in reach, but not touching,
## so contact doesn't hurt the player before the charge.
const IN_REACH := CHARGE_LENGTH / 2


## A charger [param offset] from the player that doesn't walk unless a test
## says so.
func _add_charger(offset: Vector2) -> World.Dummy:
	var d := _add_dummy(_player().pos + offset, DummyKinds.charger_kind)
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	d.collider = circle
	d.attack_interval_ticks = ATTACK_INTERVAL_TICKS
	d.attack_ticks_left = ATTACK_INTERVAL_TICKS
	d.attack_choice = DummyKind.AttackChoice.CHARGE
	d.aim_lock_ticks = AIM_LOCK_TICKS
	d.charge_step = CHARGE_STEP
	d.charge_length = CHARGE_LENGTH
	d.contact_damage = 1
	return d


## Center to center along x, for a gap of [param gap] between the
## charger's edge and the player's.
func _apart(gap: float) -> float:
	return RADIUS + World.player_hurtbox.x / 2 + gap


## Steps the world until [param d] is in [param state]; returns the ticks
## taken, or -1 if it isn't within [constant A_WHILE].
func _ticks_until(d: World.Dummy, state: Dummy.State) -> int:
	for i in A_WHILE:
		world.step()
		if d.state == state:
			return i + 1
	return -1


func test_it_walks_toward_the_nearest_player() -> void:
	var d := _add_charger(Vector2(100, 0))
	d.walk_step = WALK_STEP
	var start := d.pos
	_advance(2)
	assert_vector(d.pos).is_equal_approx(start + Vector2.LEFT * WALK_STEP, Vector2.ONE * TOLERANCE)


func test_it_waits_until_a_charge_would_reach_before_it_locks() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH + 1), 0))
	_advance(ATTACK_INTERVAL_TICKS * 2)
	assert_int(d.state).is_equal(Dummy.State.IDLE)
	_player().pos.x += 2
	world.step()
	assert_int(d.state).is_equal(Dummy.State.AIMING)


func test_a_player_in_reach_from_the_start_waits_for_the_timer() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	assert_int(_ticks_until(d, Dummy.State.AIMING)).is_equal(
			ATTACK_INTERVAL_TICKS - AIM_LOCK_TICKS)


func test_a_charge_snaps_its_facing_and_goes_its_whole_length() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	_ticks_until(d, Dummy.State.AIMING)
	assert_vector(d.facing).is_equal_approx(Vector2.UP, Vector2.ONE * TOLERANCE)
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	_ticks_until(d, Dummy.State.IDLE)
	assert_float(d.pos.distance_to(start)).is_equal_approx(CHARGE_LENGTH, TOLERANCE)


func test_the_next_attack_counts_from_the_end_of_a_charge() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	assert_int(d.attack_ticks_left).is_equal(ATTACK_INTERVAL_TICKS)


func test_a_wall_ends_a_charge_early() -> void:
	var wall_x := RoomShape.floor_area().end.x
	var d := _add_charger(Vector2.ZERO)
	d.pos = Vector2(wall_x - RADIUS - CHARGE_LENGTH / 2, _player().pos.y)
	# Its far edge against the wall.
	_player().pos = Vector2(wall_x - World.player_hurtbox.x / 2, d.pos.y)
	_ticks_until(d, Dummy.State.CHARGING)
	assert_int(_ticks_until(d, Dummy.State.IDLE)).is_less(
			ceili(CHARGE_LENGTH / CHARGE_STEP))
	assert_float(d.pos.x).is_equal_approx(wall_x - RADIUS, TOLERANCE)


func test_one_charge_hurts_every_player_in_its_path() -> void:
	world.add_player(OTHER_ID)
	var d := _add_charger(Vector2(-_apart(RADIUS), 0))
	# Within the charge's end, just past the first player.
	var past := World.player_hurtbox.x + RADIUS
	world.players[OTHER_ID].pos = _player().pos + Vector2(past, 0)
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	assert_int(_player().health).is_equal(World.player_max_health - 1)
	assert_int(world.players[OTHER_ID].health).is_equal(World.player_max_health - 1)


func test_nothing_pushes_it_mid_charge() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	assert_bool(d.push(Vector2.RIGHT, 1)).is_true()
	_ticks_until(d, Dummy.State.CHARGING)
	assert_bool(d.push(Vector2.RIGHT, 1)).is_false()


func test_by_range_fires_out_of_reach_and_charges_within_it() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH + 1), 0))
	d.attack_choice = DummyKind.AttackChoice.BY_RANGE
	_ticks_until(d, Dummy.State.AIMING)
	assert_int(d.locked_attack).is_equal(Dummy.Attack.FIRE)
	var near := _add_charger(Vector2(_apart(CHARGE_LENGTH), 0))
	near.attack_choice = DummyKind.AttackChoice.BY_RANGE
	_ticks_until(near, Dummy.State.AIMING)
	assert_int(near.locked_attack).is_equal(Dummy.Attack.CHARGE)


func test_it_counts_distances_in_whole_steps_ties_to_the_lower_seat() -> void:
	world.add_player(OTHER_ID)
	var d := _add_charger(Vector2(0, -A_WHILE))
	d.walk_step = WALK_STEP
	var step := World.target_distance_step
	# Both in the same step from it, the other seat a little nearer.
	_player().pos = d.pos + Vector2(step * 4 + step * 0.75, 0)
	world.players[OTHER_ID].pos = d.pos + Vector2(-step * 4 - step * 0.25, 0)
	_advance(2)
	assert_float(d.move.x).is_greater(0.0)
