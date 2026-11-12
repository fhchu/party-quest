extends "res://tests/sim/world_fixture.gd"
## The conditions that end a run.

const DefeatAll := preload("res://sim/run_conditions/defeat_all.gd")
const PartyDowned := preload("res://sim/run_conditions/party_downed.gd")
const TimeUp := preload("res://sim/run_conditions/time_up.gd")


func test_defeat_all_is_met_once_no_dummy_of_its_kind_is_left() -> void:
	var condition := DefeatAll.new(DummyKinds.enemy_kind)
	_add_dummy(_player().pos + Vector2(0, 100), DummyKinds.start_kind)
	var enemy := _add_dummy(_player().pos + Vector2(0, -100), DummyKinds.enemy_kind)
	assert_bool(condition.step(world)).is_false()
	world.dummies.erase(enemy)
	assert_bool(condition.step(world)).is_true()


func test_party_downed_is_met_once_every_player_is_downed() -> void:
	var condition := PartyDowned.new()
	world.add_player(PLAYER_ID + 1)
	_player().health = 0
	assert_bool(condition.step(world)).is_false()
	world.players[PLAYER_ID + 1].health = 0
	assert_bool(condition.step(world)).is_true()


func test_time_up_is_met_on_its_last_tick() -> void:
	var ticks := 3
	var condition := TimeUp.new(ticks)
	for i in ticks - 1:
		assert_bool(condition.step(world)).is_false()
	assert_bool(condition.step(world)).is_true()
	assert_int(condition.ticks_left).is_zero()
