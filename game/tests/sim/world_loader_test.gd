extends GdUnitTestSuite
## WorldLoader: rooms become plans, conditions goals, passages doors.

const WorldState := preload("res://sim/world_state.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const Fire := preload("res://sim/fire.gd")
const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const GameTime := preload("res://shared/game_time.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldLoader := preload("res://sim/world_loader.gd")

# Every value _kind() sets: each off its default and unlike the others, so
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
const TOLERANCE := 0.001


func test_a_passage_is_a_door_at_each_end_in_opposite_walls() -> void:
	var south := Room.new()
	var north := Room.new()
	var passage := Passage.new()
	passage.from = south
	passage.side = RoomShape.Side.NORTH
	passage.to = north
	var passages: Array[Passage] = [passage]
	var run := WorldLoader.run_plan(south, passages)
	assert_array(run.rooms).has_size(2)
	var door := run.start.doors[0]
	assert_vector(door.wall.inward).is_equal(RoomShape.inward(RoomShape.Side.NORTH))
	var back := run.rooms[door.leads_to].doors[0]
	assert_object(run.rooms[back.leads_to]).is_same(run.start)
	assert_object(back.wall).is_same(door.arrive_by)


func test_a_runs_plans_are_freed_with_it() -> void:
	var run := WorldLoader.first_run()
	var start: WeakRef = weakref(run.start)
	run = null
	assert_object(start.get_ref()).is_null()


func test_a_run_keeps_its_win_gold() -> void:
	# A variable, since a property can't be set through a constant.
	var setup: Resource = WorldLoader.RUN
	var real: int = setup.win_gold
	setup.win_gold = real + 5
	var plan := WorldLoader.first_run()
	setup.win_gold = real
	assert_int(plan.win_gold).is_equal(real + 5)


func test_every_condition_type_has_a_goal_type() -> void:
	for type: Condition.Type in Condition.Type.values():
		assert_bool(WorldLoader.GOAL_TYPES.has(type)).is_true()


func test_a_condition_counts_its_seconds_in_ticks() -> void:
	var time_up := Condition.new()
	time_up.type = Condition.Type.TIME_UP
	time_up.sec = 2.0
	var lose: Array[Condition] = [time_up]
	var run := WorldLoader.run_plan(Room.new(), [], [], lose)
	assert_int(run.lose[0].ticks).is_equal(roundi(2.0 * GameTime.TICK_RATE))


func test_a_condition_names_its_kind_and_room_by_their_plans() -> void:
	var start := Room.new()
	var far := Room.new()
	var passage := Passage.new()
	passage.from = start
	passage.side = RoomShape.Side.NORTH
	passage.to = far
	var defeat := Condition.new()
	defeat.type = Condition.Type.DEFEAT_ALL
	defeat.kind = DummyKinds.CHARGER
	var clear := Condition.new()
	clear.type = Condition.Type.CLEAR_ROOM
	clear.room = far
	var passages: Array[Passage] = [passage]
	var win: Array[Condition] = [defeat, clear]
	var run := WorldLoader.run_plan(start, passages, win)
	assert_int(run.win[0].kind).is_equal(DummyKinds.charger_kind)
	assert_object(run.win[1].room).is_same(run.rooms[run.start.doors[0].leads_to])


func test_a_kinds_speeds_become_px_per_tick() -> void:
	var kind := _kind()
	kind.walk_speed = 60.0
	kind.turn_deg_per_sec = 90.0
	var d := _loaded(kind)
	var fire: Fire = d.attacks[0]
	assert_float(d.walk_step * GameTime.TICK_RATE).is_equal_approx(60.0, TOLERANCE)
	assert_float(d.turn_step * GameTime.TICK_RATE).is_equal_approx(PI / 2, TOLERANCE)
	assert_float(fire.step * GameTime.TICK_RATE).is_equal_approx(SHOT_SPEED, TOLERANCE)
	assert_float(d.charge.step * GameTime.TICK_RATE).is_equal_approx(CHARGE_SPEED, TOLERANCE)
	assert_float(d.charge.cooldown_walk_step * GameTime.TICK_RATE).is_equal_approx(
			COOLDOWN_WALK_SPEED, TOLERANCE)


func test_a_kinds_times_become_ticks() -> void:
	var kind := _kind()
	kind.first_attack_delay_sec = 0.5
	kind.attack_interval_sec = 2.0
	kind.contact_push_sec = 1.0
	var d := _loaded(kind)
	var fire: Fire = d.attacks[0]
	assert_int(d.attack_ticks_left).is_equal(roundi(0.5 * GameTime.TICK_RATE))
	assert_int(d.attack_interval_ticks).is_equal(roundi(2.0 * GameTime.TICK_RATE))
	assert_int(d.contact_push_ticks).is_equal(roundi(1.0 * GameTime.TICK_RATE))
	assert_int(fire.aim_lock_ticks).is_equal(roundi(SHOT_AIM_SEC * GameTime.TICK_RATE))
	assert_int(fire.push_ticks).is_equal(roundi(PUSH_SEC * GameTime.TICK_RATE))
	assert_int(d.charge.aim_lock_ticks).is_equal(roundi(CHARGE_AIM_SEC * GameTime.TICK_RATE))
	assert_int(d.charge.cooldown_ticks).is_equal(roundi(COOLDOWN_SEC * GameTime.TICK_RATE))


func test_a_push_goes_its_speed_for_its_time() -> void:
	var kind := _kind()
	kind.contact_push_speed = 100.0
	kind.contact_push_sec = 0.5
	var d := _loaded(kind)
	var fire: Fire = d.attacks[0]
	assert_float(d.contact_push_px).is_equal_approx(50.0, TOLERANCE)
	assert_float(fire.push_px).is_equal_approx(PUSH_SPEED * PUSH_SEC, TOLERANCE)


func test_a_charge_brakes_steadily_from_its_speed_to_its_end_speed() -> void:
	var d := _loaded(_kind())
	var brake_ticks := BRAKE_SEC * GameTime.TICK_RATE
	var speed_lost := (CHARGE_SPEED - BRAKE_END_SPEED) / GameTime.TICK_RATE
	assert_float(d.charge.brake_slowdown).is_equal_approx(speed_lost / brake_ticks, TOLERANCE)
	assert_float(d.charge.brake_end_step * GameTime.TICK_RATE).is_equal_approx(
			BRAKE_END_SPEED, TOLERANCE)
	# Slowing steadily, it covers its average speed for the brake's time.
	assert_float(d.charge.brake_px).is_equal_approx(
			(CHARGE_SPEED + BRAKE_END_SPEED) / 2 * BRAKE_SEC, TOLERANCE)


func test_a_kind_keeps_its_attacks_in_order_with_their_weights_and_rule() -> void:
	var kind := _kind()
	kind.attack_choice = DummyKind.AttackChoice.CYCLE
	var d := _loaded(kind)
	assert_bool(d.attacks[0] is Fire).is_true()
	assert_object(d.attacks[1]).is_same(d.charge)
	assert_array(Array(d.weights)).is_equal([SHOT_WEIGHT, CHARGE_WEIGHT])
	assert_int(d.attack_rule).is_equal(AttackChoice.Rule.CYCLE)


func test_a_kind_with_health_can_be_hurt_and_one_without_cant() -> void:
	var tough := _kind()
	tough.health = 3
	tough.pushed_by_swings = false
	tough.contact_damage = 2
	var d := _loaded(tough)
	assert_bool(d.damageable).is_true()
	assert_int(d.health).is_equal(3)
	assert_bool(d.pushed_by_swings).is_false()
	assert_int(d.contact_damage).is_equal(2)
	var inert := _kind()
	inert.health = 0
	assert_bool(_loaded(inert).damageable).is_false()


## A kind with a shot and then a charge, each value off its default.
func _kind() -> DummyKind:
	var fire := FireAttack.new()
	fire.projectile_speed = SHOT_SPEED
	fire.aim_lock_sec = SHOT_AIM_SEC
	fire.push_speed = PUSH_SPEED
	fire.push_sec = PUSH_SEC
	fire.weight = SHOT_WEIGHT
	var charge := ChargeAttack.new()
	charge.speed = CHARGE_SPEED
	charge.aim_lock_sec = CHARGE_AIM_SEC
	charge.brake_sec = BRAKE_SEC
	charge.brake_end_speed = BRAKE_END_SPEED
	charge.cooldown_sec = COOLDOWN_SEC
	charge.cooldown_walk_speed = COOLDOWN_WALK_SPEED
	charge.weight = CHARGE_WEIGHT
	var kind := DummyKind.new()
	kind.attacks.assign([fire, charge])
	return kind


## The dummy WorldLoader makes from [param kind], added to the kinds only
## while it's made.
func _loaded(kind: DummyKind) -> WorldState.Dummy:
	var kinds := WorldLoader.DUMMY_KINDS.kinds
	kinds.append(kind)
	var d := WorldLoader.new_dummy(kinds.size() - 1)
	kinds.pop_back()
	return d
