extends "res://tests/sim/world_fixture.gd"
## A turret: a unit that turns toward the nearest living player and fires
## at where they were when its aim locked.


const FIRE_INTERVAL_TICKS := 30
const AIM_LOCK_TICKS := 6
## In radians per tick: a quarter turn lasts 30 ticks.
const TURN_STEP := PI / 60
const SHOT_STEP := 5.0
const SHOT_RADIUS := 4.0


## A turret straight above the player, facing it.
func _add_turret() -> Unit:
	var d := _add_unit(_player().pos + Vector2(0, -100), Units.turret_type)
	d.attack_interval_ticks = FIRE_INTERVAL_TICKS
	d.attack_ticks_left = FIRE_INTERVAL_TICKS
	var fire := Fire.new()
	fire.aim_lock_ticks = AIM_LOCK_TICKS
	_arm(d, fire)
	d.turn_step = TURN_STEP
	d.facing = Vector2.DOWN
	return d


## [method _add_turret]'s turret, its shot only along an axis,
## [constant SHOT_RADIUS] px and [constant SHOT_STEP] a tick.
func _add_cardinal_turret() -> Unit:
	var d := _add_turret()
	var fire: Fire = d.attacks[0]
	fire.cardinal_only = true
	fire.step = SHOT_STEP
	fire.radius = SHOT_RADIUS
	return d


## Ticks until the turret, aiming at [param target], fires; -1 if it
## doesn't within [param limit].
func _ticks_to_fire(d: Unit, target: Player, limit := A_WHILE) -> int:
	for i in limit:
		if d.step(target, [], null, world.rng):
			return i + 1
	return -1


func test_it_turns_no_faster_than_its_rate() -> void:
	var d := _add_turret()
	_player().pos = d.pos + Vector2(100, 0)
	WorldSimulator.step(world)
	var turned := Vector2.DOWN.angle_to(d.facing)
	assert_float(absf(turned)).is_equal_approx(TURN_STEP, 0.001)
	# The other 29 of a quarter turn's 30 steps at TURN_STEP, PI / 60.
	_advance(29)
	assert_float(d.facing.angle_to(Vector2.RIGHT)).is_equal_approx(0.0, 0.001)


func test_it_fires_an_aim_lock_after_each_lock_one_interval_apart() -> void:
	var d := _add_turret()
	# FIRE_INTERVAL_TICKS 30, then AIM_LOCK_TICKS 6.
	assert_int(_ticks_to_fire(d, _player())).is_equal(36)
	assert_int(_ticks_to_fire(d, _player())).is_equal(30)


func test_it_aims_at_where_the_target_was_when_the_aim_locked() -> void:
	var d := _add_turret()
	_advance(FIRE_INTERVAL_TICKS)
	var locked_at := _player().pos
	_player().pos += Vector2(50, 0)
	_advance(AIM_LOCK_TICKS - 1)
	assert_bool(d.is_aim_locked()).is_true()
	assert_vector(d.aim_spot).is_equal(locked_at)
	assert_float(d.facing.angle_to(locked_at - d.pos)).is_equal_approx(0.0, 0.001)


func test_it_targets_the_nearest_living_player_ties_to_the_lower_seat() -> void:
	var d := _add_turret()
	WorldSimulator.add_player(world, 2)
	WorldSimulator.add_player(world, 3)
	# 1 (dropped) and 2 are as near as each other; 3 is nearest but downed.
	_player().pos = d.pos + Vector2(100, 0)
	world.players[2].pos = d.pos + Vector2(-100, 0)
	world.players[3].pos = d.pos + Vector2(0, -10)
	world.players[3].health = 0
	WorldSimulator.set_connected(world, PLAYER_ID, false)
	# A quarter turn at TURN_STEP.
	_advance(30)
	assert_float(d.facing.angle_to(Vector2.RIGHT)).is_equal_approx(0.0, 0.001)


func test_a_cardinal_shot_goes_along_the_axis_nearest_its_target() -> void:
	var d := _add_cardinal_turret()
	_player().pos = d.pos + Vector2(60, 7)
	# FIRE_INTERVAL_TICKS 30, then AIM_LOCK_TICKS 6.
	_advance(36)
	assert_array(world.projectiles).has_size(1)
	assert_vector(world.projectiles[0].step).is_equal_approx(
			Vector2(SHOT_STEP, 0), Vector2.ONE * 0.001)


func test_the_nearest_axis_is_along_x_when_both_are_as_near() -> void:
	assert_vector(Fire.nearest_axis(Vector2(-3, 3))).is_equal(Vector2.LEFT)


func test_the_nearest_axis_is_along_y_when_y_is_nearer() -> void:
	assert_vector(Fire.nearest_axis(Vector2(2, -5))).is_equal(Vector2.UP)


func test_a_cardinal_shot_waits_until_it_would_touch_its_target() -> void:
	var d := _add_cardinal_turret()
	# Half of PLAYER_SIZE 16 plus SHOT_RADIUS 4 is 12: 13 across just misses.
	_player().pos = d.pos + Vector2(13, 50)
	assert_int(_ticks_to_fire(d, _player())).is_equal(-1)
	# 11 across just touches.
	_player().pos = d.pos + Vector2(11, 50)
	# It locks on the next tick and fires AIM_LOCK_TICKS 6 after.
	assert_int(_ticks_to_fire(d, _player())).is_equal(7)


func test_a_cardinal_shot_keeps_its_axis_when_the_turret_is_pushed() -> void:
	var d := _add_cardinal_turret()
	_player().pos = d.pos + Vector2(60, 7)
	_advance(FIRE_INTERVAL_TICKS)
	assert_bool(d.is_aim_locked()).is_true()
	# From here the locked spot is 60 across and 63 up: nearest up.
	d.pos += Vector2(0, 70)
	_advance(AIM_LOCK_TICKS)
	assert_array(world.projectiles).has_size(1)
	assert_vector(world.projectiles[0].step).is_equal_approx(
			Vector2(SHOT_STEP, 0), Vector2.ONE * 0.001)


func test_a_cardinal_turret_turns_to_its_axis_while_aiming() -> void:
	var d := _add_cardinal_turret()
	_player().pos = d.pos + Vector2(60, 7)
	_advance(FIRE_INTERVAL_TICKS - 1)
	assert_float(d.facing.angle_to(Vector2(60, 7))).is_equal_approx(0.0, 0.001)
	_advance(AIM_LOCK_TICKS)
	assert_vector(d.facing).is_equal_approx(Vector2.RIGHT, Vector2.ONE * 0.001)


func test_with_nobody_alive_it_skips_the_shot() -> void:
	var d := _add_turret()
	assert_int(_ticks_to_fire(d, null, FIRE_INTERVAL_TICKS * 2)).is_equal(-1)
	assert_vector(d.facing).is_equal(Vector2.DOWN)
	# FIRE_INTERVAL_TICKS 30, then AIM_LOCK_TICKS 6.
	assert_int(_ticks_to_fire(d, _player())).is_less_equal(36)


func test_a_swing_hits_the_turned_hurtbox_not_the_upright_one() -> void:
	# Turned a quarter of a right angle, the box reaches past its upright
	# edge straight ahead, and pulls back from where its upright corners were.
	var d := _add_unit(_player().pos + Vector2(-100, 0), Units.turret_type)
	d.facing = Vector2.from_angle(PI / 4)
	var half := UNIT_SIZE.x / 2
	var tip := half * sqrt(2.0)
	_player().facing = Direction.Cardinal.WEST
	# The arc's reach ends between the upright edge and the turned tip.
	_player().pos = d.pos + Vector2(SWING_RADIUS + (half + tip) / 2, 0)
	_press()
	WorldSimulator.step(world)
	assert_array(world.swing_contacts).has_size(1)


func test_contact_follows_the_turned_hurtbox() -> void:
	var d := _add_unit(_player().pos + Vector2(-100, 0), Units.turret_type)
	d.facing = Vector2.from_angle(PI / 4)
	var half := UNIT_SIZE.x / 2
	# Beside where an upright corner would be: the turned box has pulled away.
	_player().pos = d.pos + Vector2(half, half) + PLAYER_SIZE / 2 - Vector2.ONE
	WorldSimulator.step(world)
	assert_int(_player().health).is_equal(MAX_HEALTH)
	# Just past the upright right edge, overlapping the turned tip.
	_player().pos = d.pos + Vector2(half + PLAYER_SIZE.x / 2 + 1, 0)
	WorldSimulator.step(world)
	assert_int(_player().health).is_less(MAX_HEALTH)
