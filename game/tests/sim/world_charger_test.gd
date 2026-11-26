extends "res://tests/sim/world_fixture.gd"
## A charger: a dummy that walks toward the nearest living player and, once
## a charge would reach them, locks its aim and charges in a straight line.

const AttackChoice := preload("res://sim/attack_choice.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")


const ATTACK_INTERVAL_TICKS := 30
const AIM_LOCK_TICKS := 6
const RADIUS := 8.0
const WALK_STEP := 1.0
const CHARGE_STEP := 4.0
const CHARGE_LENGTH := 48.0
const COOLDOWN_TICKS := 5
const COOLDOWN_WALK_STEP := 0.25
const OTHER_ID := PLAYER_ID + 1
## Between the charger's edge and the player's: in reach, but not touching,
## so contact doesn't hurt the player before the charge.
const IN_REACH := CHARGE_LENGTH / 2


## A charger [param offset] from the player that doesn't walk unless a test
## says so.
func _add_charger(offset: Vector2) -> Dummy:
	var d := _add_dummy(_player().pos + offset, DummyKinds.charger_kind)
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	d.collider = circle
	d.attack_interval_ticks = ATTACK_INTERVAL_TICKS
	d.attack_ticks_left = ATTACK_INTERVAL_TICKS
	var charge := Charge.new()
	charge.aim_lock_ticks = AIM_LOCK_TICKS
	charge.step = CHARGE_STEP
	charge.length = CHARGE_LENGTH
	charge.cooldown_ticks = COOLDOWN_TICKS
	charge.cooldown_walk_step = COOLDOWN_WALK_STEP
	_arm(d, null, charge)
	d.contact_damage = 1
	return d


## Center to center along x, for a gap of [param gap] between the
## charger's edge and the player's.
func _apart(gap: float) -> float:
	return RADIUS + PLAYER_SIZE.x / 2 + gap


## Steps the world until [param d] is in [param state]; returns the ticks
## needed, or -1 if it isn't within [constant A_WHILE].
func _ticks_until(d: Dummy, state: Dummy.State) -> int:
	for i in A_WHILE:
		WorldSimulator.step(world)
		if d.state == state:
			return i + 1
	return -1


func test_it_walks_toward_the_nearest_player() -> void:
	var d := _add_charger(Vector2(100, 0))
	d.walk_step = WALK_STEP
	var start := d.pos
	_advance(2)
	assert_bool(d.pos.is_equal_approx(start + Vector2.LEFT * WALK_STEP)).is_true()


func test_it_waits_until_a_charge_would_reach_before_it_locks() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH + 1), 0))
	_advance(ATTACK_INTERVAL_TICKS * 2)
	assert_int(d.state).is_equal(Dummy.State.IDLE)
	_player().pos.x += 2
	WorldSimulator.step(world)
	assert_int(d.state).is_equal(Dummy.State.AIMING)


func test_a_player_in_reach_from_the_start_waits_for_the_timer() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	assert_int(_ticks_until(d, Dummy.State.AIMING)).is_equal(ATTACK_INTERVAL_TICKS)


func test_a_charge_snaps_its_facing_and_goes_its_whole_length() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	_ticks_until(d, Dummy.State.AIMING)
	assert_bool(d.facing.is_equal_approx(Vector2.UP)).is_true()
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	_ticks_until(d, Dummy.State.IDLE)
	assert_bool(is_equal_approx(d.pos.distance_to(start), CHARGE_LENGTH)).is_true()


func test_each_lock_comes_an_interval_after_the_last() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	assert_int(_ticks_until(d, Dummy.State.AIMING)).is_equal(ATTACK_INTERVAL_TICKS)
	var to_next_lock := _ticks_until(d, Dummy.State.CHARGING) + _ticks_until(d, Dummy.State.IDLE)
	to_next_lock += _ticks_until(d, Dummy.State.AIMING)
	assert_int(to_next_lock).is_equal(ATTACK_INTERVAL_TICKS)


func test_a_wall_ends_a_charge_early() -> void:
	var wall_x := RoomShape.floor_area().end.x
	var d := _add_charger(Vector2.ZERO)
	d.pos = Vector2(wall_x - RADIUS - CHARGE_LENGTH / 2, _player().pos.y)
	# Its far edge against the wall.
	_player().pos = Vector2(wall_x - PLAYER_SIZE.x / 2, d.pos.y)
	_ticks_until(d, Dummy.State.CHARGING)
	assert_int(_ticks_until(d, Dummy.State.IDLE)).is_less(
			ceili(CHARGE_LENGTH / CHARGE_STEP))
	assert_bool(is_equal_approx(d.pos.x, wall_x - RADIUS)).is_true()


func test_one_charge_hurts_every_player_in_its_path() -> void:
	WorldSimulator.add_player(world, OTHER_ID)
	var d := _add_charger(Vector2(-_apart(RADIUS), 0))
	# Within the charge's end, just past the first player.
	var past := PLAYER_SIZE.x + RADIUS
	world.players[OTHER_ID].pos = _player().pos + Vector2(past, 0)
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	assert_int(_player().health).is_equal(WorldState.data.player_max_health - 1)
	assert_int(world.players[OTHER_ID].health).is_equal(WorldState.data.player_max_health - 1)


func test_nothing_pushes_it_mid_charge() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	assert_bool(d.push(Vector2.RIGHT, 1)).is_true()
	_ticks_until(d, Dummy.State.CHARGING)
	assert_bool(d.push(Vector2.RIGHT, 1)).is_false()


func test_with_a_shot_too_it_fires_out_of_reach_and_charges_within_it() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH + 1), 0))
	_arm(d, Fire.new(), d.charge)
	_ticks_until(d, Dummy.State.AIMING)
	assert_int(d.locked_attack).is_equal(Dummy.Attack.FIRE)
	var near := _add_charger(Vector2(_apart(CHARGE_LENGTH), 0))
	_arm(near, Fire.new(), near.charge)
	_ticks_until(near, Dummy.State.AIMING)
	assert_int(near.locked_attack).is_equal(Dummy.Attack.CHARGE)


func test_cycling_fire_fire_charge_charges_third_even_out_of_reach() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH * 2), 0))
	var fire := Fire.new()
	# Long enough for the test to see it aiming.
	fire.aim_lock_ticks = AIM_LOCK_TICKS
	d.attacks.assign([fire, fire, d.charge])
	d.weights = PackedFloat32Array([1.0, 1.0, 1.0])
	d.attack_rule = AttackChoice.Rule.CYCLE
	var locked: Array[Dummy.Attack] = []
	for i in 3:
		_ticks_until(d, Dummy.State.AIMING)
		locked.append(d.locked_attack)
		_ticks_until(d, Dummy.State.IDLE)
	assert_array(locked).is_equal([Dummy.Attack.FIRE, Dummy.Attack.FIRE, Dummy.Attack.CHARGE])


func test_it_counts_distances_in_whole_steps_ties_to_the_lower_seat() -> void:
	WorldSimulator.add_player(world, OTHER_ID)
	var d := _add_charger(Vector2(0, -A_WHILE))
	d.walk_step = WALK_STEP
	var step := WorldState.data.target_distance_step
	# Both in the same step from it, the other seat a little nearer.
	_player().pos = d.pos + Vector2(step * 4 + step * 0.75, 0)
	world.players[OTHER_ID].pos = d.pos + Vector2(-step * 4 - step * 0.25, 0)
	_advance(2)
	assert_float(d.move.x).is_greater(0.0)


func test_the_snapshot_counts_down_the_ticks_to_a_charge() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	_ticks_until(d, Dummy.State.AIMING)
	var windup := WorldSnapshot.of(world).dummies[0].charge_windup_ticks_left
	assert_float(windup).is_greater(0.0)
	assert_int(_ticks_until(d, Dummy.State.CHARGING)).is_equal(roundi(windup))


func test_the_snapshot_shows_no_windup_for_a_shot() -> void:
	var d := _add_charger(Vector2(_apart(CHARGE_LENGTH * 2), 0))
	var fire := Fire.new()
	fire.aim_lock_ticks = AIM_LOCK_TICKS
	_arm(d, fire, d.charge)
	_ticks_until(d, Dummy.State.AIMING)
	assert_int(d.locked_attack).is_equal(Dummy.Attack.FIRE)
	assert_float(WorldSnapshot.of(world).dummies[0].charge_windup_ticks_left).is_zero()


func test_after_a_charge_it_speeds_up_steadily_to_its_own_walk_over_its_cooldown() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	d.walk_step = WALK_STEP
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	# The tick it stops charging, it hasn't chosen a way to walk yet.
	WorldSimulator.step(world)
	var steps: Array[float] = []
	for i in COOLDOWN_TICKS:
		var earlier := d.pos
		WorldSimulator.step(world)
		steps.append(d.pos.distance_to(earlier))
	assert_float(steps[0]).is_greater_equal(COOLDOWN_WALK_STEP)
	assert_float(steps[0]).is_less(WALK_STEP)
	assert_bool(is_equal_approx(steps[steps.size() - 1], WALK_STEP)).is_true()


func test_a_charge_pushes_players_square_to_it_toward_their_side() -> void:
	WorldSimulator.add_player(world, OTHER_ID)
	var d := _add_charger(Vector2(-_apart(IN_REACH), 0))
	d.contact_push_px = 20.0
	d.contact_push_ticks = 4
	# P1 is the target, so on the charge's line; the other is a little to its
	# left, up the screen.
	world.players[OTHER_ID].pos = _player().pos + Vector2(0, -4)
	_ticks_until(d, Dummy.State.CHARGING)
	var right := -d.charge.direction.orthogonal()
	_ticks_until(d, Dummy.State.IDLE)
	assert_bool(_player().knockback.step.normalized().is_equal_approx(right)).is_true()
	assert_bool(world.players[OTHER_ID].knockback.step.normalized().is_equal_approx(
			-right)).is_true()


func test_a_charge_brakes_steadily_near_its_end_and_still_goes_its_whole_length() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	d.charge.brake_slowdown = 1.0
	d.charge.brake_end_step = 1.0
	d.charge.brake_px = 7.5
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	var steps: Array[float] = []
	while d.state == Dummy.State.CHARGING:
		var earlier := d.pos
		WorldSimulator.step(world)
		steps.append(d.pos.distance_to(earlier))
	assert_bool(is_equal_approx(d.pos.distance_to(start), CHARGE_LENGTH)).is_true()
	assert_bool(is_equal_approx(steps[0], CHARGE_STEP)).is_true()
	assert_float(steps[steps.size() - 2]).is_less(CHARGE_STEP)


func test_a_charge_that_brakes_to_a_stop_still_ends() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	d.charge.brake_slowdown = 1.0
	d.charge.brake_end_step = 0.0
	d.charge.brake_px = 8.0
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	assert_int(_ticks_until(d, Dummy.State.IDLE)).is_not_equal(-1)
	assert_bool(is_equal_approx(d.pos.distance_to(start), CHARGE_LENGTH)).is_true()
