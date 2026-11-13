extends "res://tests/sim/world_fixture.gd"
## Rooms: entering one, clearing it, and coming back to it.

const DataRecords := preload("res://tests/data_records.gd")


func test_a_room_with_nothing_to_clear_starts_cleared() -> void:
	world.enter_room(DataRecords.map(false))
	assert_bool(world.room.cleared).is_true()


func test_a_room_clears_when_its_condition_is_met_and_stays_cleared() -> void:
	world.enter_room(DataRecords.map(true))
	world.step()
	assert_bool(world.room.cleared).is_false()
	world.dummies.clear()
	world.step()
	assert_bool(world.room.cleared).is_true()
	_add_dummy(_player().pos + Vector2(0, -100), DummyKinds.enemy_kind)
	world.step()
	assert_bool(world.room.cleared).is_true()


func test_entering_a_room_places_its_dummies_and_drops_shots_in_flight() -> void:
	world.projectiles.append(World.Projectile.new())
	var den := DataRecords.map(true)
	world.enter_room(den)
	assert_int(world.dummies.size()).is_equal(den.dummies.size())
	assert_array(world.projectiles).is_empty()


func test_entering_a_room_tells_clients_the_layout_is_new() -> void:
	var before := world.snapshot().layout_number
	world.enter_room(DataRecords.map(true))
	assert_int(world.snapshot().layout_number).is_not_equal(before)


func test_a_room_the_party_comes_back_to_is_as_they_left_it() -> void:
	var den := DataRecords.map(true)
	world.enter_room(den)
	world.dummies.clear()
	world.step()
	world.enter_room(DataRecords.map(false))
	world.enter_room(den)
	assert_array(world.dummies).is_empty()
	assert_bool(world.room.cleared).is_true()
	assert_bool(world.is_room_cleared(den)).is_true()
