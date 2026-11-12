extends "res://tests/sim/world_fixture.gd"
## A world's run conditions, and the outcome they give.

const DataLoader := preload("res://shared/data_loader.gd")
const Lobby := preload("res://server/lobby.gd")

## Short enough to run out within a test.
const TIME_LIMIT_SEC := 0.1


func test_defeat_all_wins_once_no_dummy_of_its_kind_is_left() -> void:
	_rebuild([_entry("defeat_all", "enemy")], [])
	_add_dummy(_player().pos + Vector2(0, 100), DummyKinds.start_kind)
	var enemy := _add_dummy(_player().pos + Vector2(0, -100), DummyKinds.enemy_kind)
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.dummies.erase(enemy)
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_party_downed_loses_once_every_player_is_downed() -> void:
	_rebuild([], [_entry("party_downed", true)])
	world.add_player(PLAYER_ID + 1)
	_player().health = 0
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	world.players[PLAYER_ID + 1].health = 0
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.LOST)


func test_time_up_loses_on_its_last_tick_and_shows_the_time_left() -> void:
	_rebuild([], [_entry("time_up_sec", TIME_LIMIT_SEC)])
	var ticks := GameTime.ticks(TIME_LIMIT_SEC)
	assert_int(world.snapshot().run_ticks_left).is_equal(ticks)
	_advance(ticks - 1)
	assert_int(world.outcome).is_equal(World.Outcome.NONE)
	assert_int(world.snapshot().run_ticks_left).is_equal(1)
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.LOST)


func test_a_win_and_a_loss_on_one_tick_is_a_win() -> void:
	_rebuild([_entry("defeat_all", "enemy")], [_entry("party_downed", true)])
	_player().health = 0
	world.step()
	assert_int(world.outcome).is_equal(World.Outcome.WON)


func test_a_world_without_a_time_limit_shows_no_timer() -> void:
	assert_int(world.snapshot().run_ticks_left).is_equal(World.Snapshot.NO_TIMER)


func test_every_condition_the_lobbys_run_names_has_a_check() -> void:
	var setup := DataLoader.run(Lobby.RUN)
	for entry in setup.win + setup.lose:
		assert_bool(World.run_condition_check(entry, World.new()).is_valid()).is_true()


func _entry(condition_name: String, arg: Variant) -> DataLoader.ConditionEntry:
	var entry := DataLoader.ConditionEntry.new()
	entry.name = condition_name
	entry.arg = arg
	return entry


## Replaces the fixture's world with one that has these run conditions.
func _rebuild(win: Array[DataLoader.ConditionEntry],
		lose: Array[DataLoader.ConditionEntry]) -> void:
	world = World.new(null, null, win, lose)
	world.add_player(PLAYER_ID)
