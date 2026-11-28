extends GdUnitTestSuite
## WorldLoader: a unit type becomes a unit's attributes, its durations in
## ticks and its speeds in px a tick.

const AttackChoice := preload("res://sim/attack_choice.gd")
const Fire := preload("res://sim/fire.gd")
const UnitType := preload("res://shared/data/unit_type.gd")
const AttackFire := preload("res://shared/data/attacks/attack_fire.gd")
const AttackCharge := preload("res://shared/data/attacks/attack_charge.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Unit := preload("res://sim/unit.gd")

# Every value _unit_type() sets: each off its default and unlike the others, so
# a field read from the wrong place shows. Times are whole ticks.
const SHOT_SPEED := 120.0
const SHOT_AIM_SEC := 0.2
const SHOT_WEIGHT := 3.0
const PUSH_SPEED := 200.0
const PUSH_SEC := 0.4
const CHARGE_SPEED := 300.0
const CHARGE_AIM_SEC := 0.6
const CHARGE_WEIGHT := 5.0
const BRAKE_SEC := 0.5
const BRAKE_END_SPEED := 30.0
const COOLDOWN_SEC := 0.8
const COOLDOWN_WALK_SPEED := 45.0


func test_a_unit_types_speeds_become_px_per_tick() -> void:
	var unit_type := _unit_type()
	unit_type.walk_speed = 60.0
	unit_type.turn_deg_per_sec = 90.0
	var d := _loaded(unit_type)
	var fire: Fire = d.attacks[0]
	# Each step a tick, back in its speed a second.
	assert_float(d.walk_step * GameTime.TICK_RATE).is_equal_approx(60.0, 0.001)
	assert_float(d.turn_step * GameTime.TICK_RATE).is_equal_approx(deg_to_rad(90.0), 0.001)
	assert_float(fire.step * GameTime.TICK_RATE).is_equal_approx(SHOT_SPEED, 0.001)
	assert_float(d.charge.step * GameTime.TICK_RATE).is_equal_approx(CHARGE_SPEED, 0.001)
	assert_float(d.charge.cooldown_walk_step * GameTime.TICK_RATE).is_equal_approx(
			COOLDOWN_WALK_SPEED, 0.001)


func test_a_unit_types_times_become_ticks() -> void:
	var unit_type := _unit_type()
	unit_type.first_attack_delay_sec = 0.5
	unit_type.attack_interval_sec = 2.0
	unit_type.contact_push_sec = 1.0
	var d := _loaded(unit_type)
	var fire: Fire = d.attacks[0]
	assert_int(d.attack_ticks_left).is_equal(GameTime.ticks(0.5))
	assert_int(d.attack_interval_ticks).is_equal(GameTime.ticks(2.0))
	assert_int(d.contact_push_ticks).is_equal(GameTime.ticks(1.0))
	assert_int(fire.aim_lock_ticks).is_equal(GameTime.ticks(SHOT_AIM_SEC))
	assert_int(fire.push_ticks).is_equal(GameTime.ticks(PUSH_SEC))
	assert_int(d.charge.aim_lock_ticks).is_equal(GameTime.ticks(CHARGE_AIM_SEC))
	assert_int(d.charge.cooldown_ticks).is_equal(GameTime.ticks(COOLDOWN_SEC))


func test_a_push_goes_its_speed_for_its_time() -> void:
	var unit_type := _unit_type()
	unit_type.contact_push_speed = 100.0
	unit_type.contact_push_sec = 0.5
	var d := _loaded(unit_type)
	var fire: Fire = d.attacks[0]
	# 100 px/s for 0.5 s; PUSH_SPEED 200 px/s for PUSH_SEC 0.4 s.
	assert_float(d.contact_push_px).is_equal_approx(50.0, 0.001)
	assert_float(fire.push_px).is_equal_approx(80.0, 0.001)


func test_a_charge_brakes_steadily_from_its_speed_to_its_end_speed() -> void:
	var d := _loaded(_unit_type())
	# From CHARGE_SPEED 300 to BRAKE_END_SPEED 30 px/s over BRAKE_SEC 0.5 s:
	# 540 px/s lost each second, in px a tick lost each tick.
	var per_sec_squared := GameTime.TICK_RATE * GameTime.TICK_RATE
	assert_float(d.charge.brake_slowdown * per_sec_squared).is_equal_approx(540.0, 0.001)
	assert_float(d.charge.brake_end_step * GameTime.TICK_RATE).is_equal_approx(
			BRAKE_END_SPEED, 0.001)
	# Slowing steadily, it covers its average speed, 165 px/s, for 0.5 s.
	assert_float(d.charge.brake_px).is_equal_approx(82.5, 0.001)


func test_a_unit_type_keeps_its_attacks_in_order_with_their_weights_and_rule() -> void:
	var unit_type := _unit_type()
	unit_type.attack_choice = UnitType.AttackChoice.CYCLE
	var d := _loaded(unit_type)
	assert_bool(d.attacks[0] is Fire).is_true()
	assert_object(d.attacks[1]).is_same(d.charge)
	assert_array(Array(d.weights)).is_equal([SHOT_WEIGHT, CHARGE_WEIGHT])
	assert_int(d.attack_rule).is_equal(AttackChoice.Rule.CYCLE)


func test_a_unit_type_with_health_can_be_hurt_and_one_without_cant() -> void:
	var tough := _unit_type()
	tough.health = 3
	tough.pushed_by_swings = false
	tough.contact_damage = 2
	var d := _loaded(tough)
	assert_bool(d.damageable).is_true()
	assert_int(d.health).is_equal(3)
	assert_bool(d.pushed_by_swings).is_false()
	assert_int(d.contact_damage).is_equal(2)
	var inert := _unit_type()
	inert.health = 0
	assert_bool(_loaded(inert).damageable).is_false()


func test_a_cardinal_shot_is_cardinal_only() -> void:
	var unit_type := _unit_type()
	(unit_type.attacks[0] as AttackFire).directions = AttackFire.Directions.CARDINAL
	var fire: Fire = _loaded(unit_type).attacks[0]
	assert_bool(fire.cardinal_only).is_true()


func test_a_shot_in_any_direction_isnt_cardinal_only() -> void:
	var fire: Fire = _loaded(_unit_type()).attacks[0]
	assert_bool(fire.cardinal_only).is_false()


func test_a_unit_types_walk_style_reaches_its_unit() -> void:
	var unit_type := _unit_type()
	unit_type.walk_style = UnitType.WalkStyle.ALIGN
	assert_int(_loaded(unit_type).walk_style).is_equal(Unit.WalkStyle.ALIGN)


## A unit type with a shot and then a charge, each value off its default.
func _unit_type() -> UnitType:
	var fire := AttackFire.new()
	fire.projectile_speed = SHOT_SPEED
	fire.aim_lock_sec = SHOT_AIM_SEC
	fire.push_speed = PUSH_SPEED
	fire.push_sec = PUSH_SEC
	fire.weight = SHOT_WEIGHT
	var charge := AttackCharge.new()
	charge.speed = CHARGE_SPEED
	charge.aim_lock_sec = CHARGE_AIM_SEC
	charge.brake_sec = BRAKE_SEC
	charge.brake_end_speed = BRAKE_END_SPEED
	charge.cooldown_sec = COOLDOWN_SEC
	charge.cooldown_walk_speed = COOLDOWN_WALK_SPEED
	charge.weight = CHARGE_WEIGHT
	var unit_type := UnitType.new()
	unit_type.attacks.assign([fire, charge])
	return unit_type


## The unit WorldLoader makes from [param unit_type], added to the unit types only
## while it's made.
func _loaded(unit_type: UnitType) -> Unit:
	var types := WorldLoader.UNITS.types
	types.append(unit_type)
	var d := WorldLoader.new_unit(types.size() - 1)
	types.pop_back()
	return d
