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
## A gap from which a charge ends past the player, clear of them.
const CHARGES_THROUGH := 4.0
const SHIELD_THICKNESS := 4.0
## The input action whose slot holds the shield in the tests that give one.
const SHIELD_INPUT := 1
## Invulnerable when contact is checked: the player's step uses up one tick
## before it.
const INVULNERABLE_AT_CONTACT := 2


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


## Waits for [param d]'s next aim and its end; returns the attack it locked.
func _next_attack(d: Dummy) -> Dummy.Attack:
	_ticks_until(d, Dummy.State.AIMING)
	var out := d.locked_attack
	_ticks_until(d, Dummy.State.IDLE)
	return out


## How far [param d] moves in each of the next [param ticks] steps.
func _steps(d: Dummy, ticks: int) -> Array[float]:
	var out: Array[float] = []
	for i in ticks:
		var earlier := d.pos
		WorldSimulator.step(world)
		out.append(d.pos.distance_to(earlier))
	return out


## How far [param d] moves in each step until its charge ends.
func _charge_steps(d: Dummy) -> Array[float]:
	var out: Array[float] = []
	while d.state == Dummy.State.CHARGING:
		out.append_array(_steps(d, 1))
	return out


## Steps, keeping the player invulnerable as contact is checked, until
## [param d]'s charge has touched them.
func _step_invulnerable_until_struck(d: Dummy) -> void:
	for i in A_WHILE:
		_player().invulnerable_ticks = INVULNERABLE_AT_CONTACT
		WorldSimulator.step(world)
		if PLAYER_ID in d.charge.struck_ids:
			return


func test_it_walks_toward_the_nearest_player() -> void:
	var d := _add_charger(Vector2(100, 0))
	d.walk_step = WALK_STEP
	var start := d.pos
	_advance(2)
	assert_vector(d.pos).is_equal_approx(start + Vector2(-WALK_STEP, 0), Vector2.ONE * 0.001)


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
	assert_vector(d.facing).is_equal_approx(Vector2.UP, Vector2.ONE * 0.001)
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	_ticks_until(d, Dummy.State.IDLE)
	assert_float(d.pos.distance_to(start)).is_equal_approx(CHARGE_LENGTH, 0.001)


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
	# CHARGE_LENGTH 48 at CHARGE_STEP 4 a tick.
	assert_int(_ticks_until(d, Dummy.State.IDLE)).is_less(12)
	assert_float(d.pos.x).is_equal_approx(wall_x - RADIUS, 0.001)


func test_one_charge_hurts_every_player_in_its_path() -> void:
	WorldSimulator.add_player(world, OTHER_ID)
	var d := _add_charger(Vector2(-_apart(RADIUS), 0))
	# Within the charge's end, just past the first player.
	var past := PLAYER_SIZE.x + RADIUS
	world.players[OTHER_ID].pos = _player().pos + Vector2(past, 0)
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	# MAX_HEALTH 3, less the charger's contact_damage 1.
	assert_int(_player().health).is_equal(2)
	assert_int(world.players[OTHER_ID].health).is_equal(2)


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
	assert_int(_next_attack(d)).is_equal(Dummy.Attack.FIRE)
	assert_int(_next_attack(d)).is_equal(Dummy.Attack.FIRE)
	assert_int(_next_attack(d)).is_equal(Dummy.Attack.CHARGE)


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


func test_after_a_charge_it_speeds_up_from_its_cooldown_walk_to_its_own() -> void:
	var d := _add_charger(Vector2(_apart(IN_REACH), 0))
	d.walk_step = WALK_STEP
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	# The tick it stops charging, it hasn't chosen a way to walk yet.
	WorldSimulator.step(world)
	var steps := _steps(d, COOLDOWN_TICKS)
	assert_float(steps[0]).is_greater_equal(COOLDOWN_WALK_STEP)
	assert_float(steps[0]).is_less(WALK_STEP)
	assert_float(steps[-1]).is_equal_approx(WALK_STEP, 0.001)


func test_a_charge_pushes_players_square_to_it_toward_their_side() -> void:
	WorldSimulator.add_player(world, OTHER_ID)
	var d := _add_charger(Vector2(-_apart(IN_REACH), 0))
	d.contact_push_px = 20.0
	d.contact_push_ticks = 4
	# P1 is the target, so on the charge's line; the other is a little to its
	# left, up the screen.
	world.players[OTHER_ID].pos = _player().pos + Vector2(0, -4)
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	# Charging east, its right is south.
	assert_vector(_player().knockback.step.normalized()).is_equal_approx(
			Vector2.DOWN, Vector2.ONE * 0.001)
	assert_vector(world.players[OTHER_ID].knockback.step.normalized()).is_equal_approx(
			Vector2.UP, Vector2.ONE * 0.001)


func test_a_charge_slows_near_its_end_and_still_goes_its_whole_length() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	d.charge.brake_slowdown = 1.0
	d.charge.brake_end_step = 1.0
	d.charge.brake_px = 7.5
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	var steps := _charge_steps(d)
	assert_float(d.pos.distance_to(start)).is_equal_approx(CHARGE_LENGTH, 0.001)
	assert_float(steps[0]).is_equal_approx(CHARGE_STEP, 0.001)
	assert_float(steps[-2]).is_less(CHARGE_STEP)


func test_a_charge_that_brakes_to_a_stop_still_ends() -> void:
	var d := _add_charger(Vector2(0, _apart(CHARGE_LENGTH)))
	d.charge.brake_slowdown = 1.0
	d.charge.brake_end_step = 0.0
	d.charge.brake_px = 8.0
	_ticks_until(d, Dummy.State.CHARGING)
	var start := d.pos
	assert_int(_ticks_until(d, Dummy.State.IDLE)).is_not_equal(-1)
	assert_float(d.pos.distance_to(start)).is_equal_approx(CHARGE_LENGTH, 0.001)


func test_a_charge_its_shield_blocks_never_hurts_the_player() -> void:
	var shield := ItemShield.new()
	shield.action = EquipItem.Action.GUARD
	shield.thickness_px = SHIELD_THICKNESS
	shield.length_px = PLAYER_SIZE.y
	WorldSimulator.set_slot_item(world, PLAYER_ID, SHIELD_INPUT, shield)
	_player().facing = Direction.Cardinal.WEST
	var d := _add_charger(Vector2(-_apart(CHARGES_THROUGH), 0))
	var presses := PackedByteArray()
	presses.resize(SHIELD_INPUT + 1)
	presses[SHIELD_INPUT] = 1
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, presses, 1 << SHIELD_INPUT)
	_ticks_until(d, Dummy.State.CHARGING)
	_ticks_until(d, Dummy.State.IDLE)
	assert_array(d.charge.struck_ids).contains([PLAYER_ID])
	assert_bool(d.touches_body(_player())).is_false()
	assert_int(_player().health).is_equal(MAX_HEALTH)


func test_a_charge_that_first_touches_an_invulnerable_player_never_hurts_them() -> void:
	var d := _add_charger(Vector2(-_apart(CHARGES_THROUGH), 0))
	_ticks_until(d, Dummy.State.CHARGING)
	_step_invulnerable_until_struck(d)
	assert_array(d.charge.struck_ids).contains([PLAYER_ID])
	_ticks_until(d, Dummy.State.IDLE)
	assert_bool(d.touches_body(_player())).is_false()
	assert_int(_player().health).is_equal(MAX_HEALTH)
