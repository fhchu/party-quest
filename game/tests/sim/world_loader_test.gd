extends GdUnitTestSuite
## WorldLoader: rooms become plans, conditions goals, passages doors.

const EquipItem := preload("res://shared/data/items/equip_item.gd")
const ItemShield := preload("res://shared/data/items/item_shield.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const ActionSwing := preload("res://sim/action_swing.gd")
const ActionGuard := preload("res://sim/action_guard.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const Fire := preload("res://sim/fire.gd")
const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const UnitType := preload("res://shared/data/unit_type.gd")
const AttackFire := preload("res://shared/data/attacks/attack_fire.gd")
const AttackCharge := preload("res://shared/data/attacks/attack_charge.gd")
const Units := preload("res://tests/units.gd")
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


func test_a_passage_is_a_door_at_each_end_in_opposite_walls() -> void:
	var south := Room.new()
	var north := Room.new()
	var passage := Passage.new()
	passage.from = south
	passage.side = Direction.Cardinal.NORTH
	passage.to = north
	var passages: Array[Passage] = [passage]
	var run := WorldLoader.run_plan(south, passages)
	assert_array(run.rooms).has_size(2)
	var door := run.start.doors[0]
	assert_int(door.wall.inward).is_equal(Direction.Cardinal.SOUTH)
	var back := run.rooms[door.leads_to].doors[0]
	assert_object(run.rooms[back.leads_to]).is_same(run.start)
	assert_object(back.wall).is_same(door.arrive_by)


func test_a_rooms_spawn_facing_reaches_its_plan() -> void:
	var room := Room.new()
	room.spawn_facing = Direction.Cardinal.WEST
	var no_passages: Array[Passage] = []
	assert_int(WorldLoader.run_plan(room, no_passages).start.spawn_facing).is_equal(
			Direction.Cardinal.WEST)


func test_a_runs_plans_are_freed_with_it() -> void:
	var run := WorldLoader.run_of(0)
	var start: WeakRef = weakref(run.start)
	run = null
	assert_object(start.get_ref()).is_null()


func test_a_run_keeps_its_win_gold() -> void:
	# A variable, since a property can't be set through a constant.
	var setup: Resource = WorldLoader.LEVELS.runs[0]
	var real: int = setup.win_gold
	setup.win_gold = real + 5
	var plan := WorldLoader.run_of(0)
	setup.win_gold = real
	assert_int(plan.win_gold).is_equal(real + 5)


func test_every_condition_type_has_a_goal_type() -> void:
	assert_array(WorldLoader.GOAL_TYPES.keys()).contains_exactly_in_any_order(
			Condition.Type.values())


func test_a_condition_counts_its_seconds_in_ticks() -> void:
	var time_up := Condition.new()
	time_up.type = Condition.Type.TIME_UP
	time_up.sec = 2.0
	var lose: Array[Condition] = [time_up]
	var run := WorldLoader.run_plan(Room.new(), [], [], lose)
	assert_int(run.lose[0].ticks).is_equal(GameTime.ticks(2.0))


func test_a_condition_names_its_unit_type_and_room_by_their_plans() -> void:
	var start := Room.new()
	var far := Room.new()
	var passage := Passage.new()
	passage.from = start
	passage.side = Direction.Cardinal.NORTH
	passage.to = far
	var defeat := Condition.new()
	defeat.type = Condition.Type.DEFEAT_ALL
	defeat.unit_type = Units.CHARGER
	var clear := Condition.new()
	clear.type = Condition.Type.CLEAR_ROOM
	clear.room = far
	var passages: Array[Passage] = [passage]
	var win: Array[Condition] = [defeat, clear]
	var run := WorldLoader.run_plan(start, passages, win)
	assert_int(run.win[0].unit_type).is_equal(Units.charger_type)
	assert_object(run.win[1].room).is_same(run.rooms[run.start.doors[0].leads_to])


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


func test_an_item_that_swings_gets_a_swing() -> void:
	assert_object(WorldLoader.new_action(_sword(0.1, 0.0, 10.0, 90.0, 1))).is_instanceof(
			ActionSwing)


func test_an_item_that_guards_gets_a_guard() -> void:
	var shield := ItemShield.new()
	shield.action = EquipItem.Action.GUARD
	assert_object(WorldLoader.new_action(shield)).is_instanceof(ActionGuard)


func test_a_shields_guard_gets_the_shields_size() -> void:
	var shield := ItemShield.new()
	shield.action = EquipItem.Action.GUARD
	shield.thickness_px = 3.0
	shield.length_px = 21.0
	var guard: ActionGuard = WorldLoader.new_action(shield)
	assert_float(guard.thickness_px).is_equal(3.0)
	assert_float(guard.length_px).is_equal(21.0)


func test_a_swords_swing_gets_its_time_offset_and_reach() -> void:
	var swing: ActionSwing = WorldLoader.new_action(_sword(0.3, 7.0, 20.0, 120.0, 3))
	assert_int(swing.active_ticks).is_equal(GameTime.ticks(0.3))
	assert_float(swing.offset).is_equal(7.0)
	assert_float(_farthest_point(swing)).is_equal_approx(20.0, 0.001)


func test_a_swords_swing_sweeps_its_slices_left_to_right_over_its_time() -> void:
	var swing: ActionSwing = WorldLoader.new_action(_sword(0.3, 0.0, 20.0, 120.0, 3))
	assert_int(swing.turns.size()).is_equal(GameTime.ticks(0.3))
	# Three 40-degree slices of a 120-degree arc, each turned to its middle.
	assert_float(swing.turns[0]).is_equal_approx(deg_to_rad(-40.0), 0.001)
	assert_float(swing.turns[-1]).is_equal_approx(deg_to_rad(40.0), 0.001)


func test_everything_an_item_can_do_has_an_action() -> void:
	for action: EquipItem.Action in EquipItem.Action.values():
		assert_object(WorldLoader.new_action(_item_that(action))).override_failure_message(
				"no action for item action %d" % action).is_not_null()


func test_no_item_does_nothing() -> void:
	assert_object(WorldLoader.new_action(null)).is_null()


## A sword for SWING and a shield for anything else, as the data's items are.
func _item_that(action: EquipItem.Action) -> EquipItem:
	if action == EquipItem.Action.SWING:
		return _sword(0.1, 0.0, 10.0, 90.0, 1)
	var item := ItemShield.new()
	item.action = action
	return item


## How far from the player the swing's farthest point reaches.
func _farthest_point(swing: ActionSwing) -> float:
	var out := 0.0
	for piece in swing.pieces:
		for point in piece.points:
			out = maxf(out, point.length())
	return out


## A sword whose swing lasts [param sec], starts [param offset] px ahead,
## reaches [param radius] px and sweeps [param arc_deg] in [param slices].
func _sword(sec: float, offset: float, radius: float, arc_deg: float, slices: int) -> ItemSword:
	var out := ItemSword.new()
	out.action = EquipItem.Action.SWING
	out.swing_active_sec = sec
	out.swing_offset = offset
	out.swing_radius = radius
	out.swing_arc_deg = arc_deg
	out.swing_slices = slices
	return out
