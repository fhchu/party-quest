extends "res://tests/sim/world_fixture.gd"
## Rooms: entering one, clearing it, and coming back to it.

const DataLoader := preload("res://shared/data_loader.gd")


func test_a_room_with_nothing_to_clear_starts_cleared() -> void:
	world.enter_room(_map("hall", false))
	assert_bool(world.room.cleared).is_true()


func test_a_room_clears_when_its_condition_is_met_and_stays_cleared() -> void:
	world.enter_room(_map("den", true))
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
	var den := _map("den", true)
	world.enter_room(den)
	assert_int(world.dummies.size()).is_equal(den.dummies.size())
	assert_array(world.projectiles).is_empty()


func test_entering_a_room_tells_clients_the_layout_is_new() -> void:
	var before := world.snapshot().layout_number
	world.enter_room(_map("den", true))
	assert_int(world.snapshot().layout_number).is_not_equal(before)


func test_a_room_the_party_comes_back_to_is_as_they_left_it() -> void:
	var den := _map("den", true)
	world.enter_room(den)
	world.dummies.clear()
	world.step()
	world.enter_room(_map("hall", false))
	world.enter_room(den)
	assert_array(world.dummies).is_empty()
	assert_bool(world.room.cleared).is_true()
	assert_bool(world.is_room_cleared("den")).is_true()


## A map named [param map_name]; with [param guarded], one enemy that must
## be defeated to clear it.
func _map(map_name: String, guarded: bool) -> DataLoader.Map:
	var m := DataLoader.Map.new()
	m.name = map_name
	if guarded:
		var spot := DataLoader.MapDummy.new()
		spot.kind = DummyKinds.enemy_kind
		m.dummies = [spot]
		var entry := DataLoader.ConditionEntry.new()
		entry.name = "defeat_all"
		entry.arg = "enemy"
		m.clear_when = [entry]
	return m
