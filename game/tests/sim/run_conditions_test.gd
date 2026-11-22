extends "res://tests/sim/world_fixture.gd"
## A world's run conditions, and the outcome they give.

const DataRecords := preload("res://tests/data_records.gd")
const Room := preload("res://shared/data/room.gd")

## Short enough to run out within a test.
const TIME_LIMIT_SEC := 0.1


func test_defeat_all_wins_once_no_dummy_of_its_kind_is_left() -> void:
	_rebuild([DataRecords.enemies_defeated()], [])
	_add_dummy(_player().pos + Vector2(0, 100), DummyKinds.ready_kind)
	var enemy := _add_dummy(_player().pos + Vector2(0, -100), DummyKinds.turret_kind)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.dummies.erase(enemy)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_defeat_all_with_no_kind_wins_once_no_dummy_is_left() -> void:
	_rebuild([DataRecords.goal(DataRecords.Goal.Type.DEFEAT_ALL)], [])
	var turret := _add_dummy(_player().pos + Vector2(0, -100), DummyKinds.turret_kind)
	var charger := _add_dummy(_player().pos + Vector2(0, 100), DummyKinds.charger_kind)
	world.dummies.erase(turret)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.dummies.erase(charger)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_clear_room_wins_once_that_room_is_cleared() -> void:
	var far := DataRecords.new_room(true)
	_rebuild([DataRecords.clear_room(far)], [])
	WorldSimulator.enter_room(world, far)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.dummies.clear()
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_party_downed_loses_once_every_player_is_downed() -> void:
	_rebuild([], [DataRecords.goal(DataRecords.Goal.Type.PARTY_DOWNED)])
	WorldSimulator.add_player(world, PLAYER_ID + 1)
	_player().health = 0
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.players[PLAYER_ID + 1].health = 0
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.LOST)


func test_time_up_loses_on_its_last_tick_and_shows_the_time_left() -> void:
	_rebuild([], [DataRecords.time_up(TIME_LIMIT_SEC)])
	var ticks := GameTime.ticks(TIME_LIMIT_SEC)
	assert_int(WorldSnapshot.of(world).run_ticks_left).is_equal(ticks)
	_advance(ticks - 1)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	assert_int(WorldSnapshot.of(world).run_ticks_left).is_equal(1)
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.LOST)


func test_a_win_and_a_loss_on_one_tick_is_a_win() -> void:
	var downed := DataRecords.goal(DataRecords.Goal.Type.PARTY_DOWNED)
	_rebuild([DataRecords.enemies_defeated()], [downed])
	_player().health = 0
	WorldSimulator.step(world)
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_a_world_without_a_time_limit_shows_no_timer() -> void:
	assert_int(WorldSnapshot.of(world).run_ticks_left).is_equal(WorldSnapshot.Snapshot.NO_TIMER)


func test_every_condition_the_lobbys_run_names_has_a_check() -> void:
	var run := World.WorldLoader.first_run()
	for goal in run.win + run.lose:
		assert_bool(WorldSimulator.goal_check(goal, WorldSimulator.start()).is_valid()).is_true()


## Replaces the fixture's world with one that has these run conditions.
func _rebuild(win: Array[World.Goal], lose: Array[World.Goal]) -> void:
	world = WorldSimulator.start(DataRecords.run(null, win, lose))
	WorldSimulator.add_player(world, PLAYER_ID)


func test_a_won_world_earns_its_runs_win_gold() -> void:
	var w := _world_with_win_gold(5)
	w.outcome = World.Outcome.WON
	assert_int(w.gold_earned()).is_equal(5)


func test_a_lost_world_earns_nothing() -> void:
	var w := _world_with_win_gold(5)
	w.outcome = World.Outcome.LOST
	assert_int(w.gold_earned()).is_equal(0)


func _world_with_win_gold(gold: int) -> World:
	var plan := World.WorldLoader.run_plan(Room.new())
	plan.win_gold = gold
	return WorldSimulator.start(plan)
