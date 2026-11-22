extends "res://tests/sim/world_fixture.gd"
## Rooms: entering one, clearing it, and coming back to it.

const DataRecords := preload("res://tests/data_records.gd")
const Projectile := preload("res://sim/projectile.gd")


func test_a_room_with_nothing_to_clear_starts_cleared() -> void:
	WorldSimulator.enter_room(world, DataRecords.new_room(false))
	assert_bool(world.room.cleared).is_true()


func test_a_room_clears_when_its_condition_is_met_and_stays_cleared() -> void:
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	WorldSimulator.step(world)
	assert_bool(world.room.cleared).is_false()
	world.dummies.clear()
	WorldSimulator.step(world)
	assert_bool(world.room.cleared).is_true()
	_add_dummy(_player().pos + Vector2(0, -100), DummyKinds.turret_kind)
	WorldSimulator.step(world)
	assert_bool(world.room.cleared).is_true()


func test_entering_a_room_places_its_dummies_and_drops_shots_in_flight() -> void:
	world.projectiles.append(Projectile.new())
	var den := DataRecords.new_room(true)
	WorldSimulator.enter_room(world, den)
	assert_int(world.dummies.size()).is_equal(den.spots.size())
	assert_array(world.projectiles).is_empty()


func test_entering_a_room_tells_clients_the_layout_is_new() -> void:
	var earlier := WorldSnapshot.of(world).layout_number
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	assert_int(WorldSnapshot.of(world).layout_number).is_not_equal(earlier)


func test_entering_a_room_tells_clients_its_graphics_seed() -> void:
	# Fixed, so two rooms' seeds can't happen to match.
	seed(1)
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	var earlier := WorldSnapshot.of(world).graphics_seed
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	assert_int(WorldSnapshot.of(world).graphics_seed).is_not_equal(earlier)


func test_a_rooms_graphics_seed_leaves_the_worlds_random_choices_alone() -> void:
	var rng_state := world.rng.state
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	assert_int(world.rng.state).is_equal(rng_state)


func test_a_room_the_party_comes_back_to_is_as_they_left_it() -> void:
	var den := DataRecords.new_room(true)
	WorldSimulator.enter_room(world, den)
	var den_seed := WorldSnapshot.of(world).graphics_seed
	world.dummies.clear()
	WorldSimulator.step(world)
	WorldSimulator.enter_room(world, DataRecords.new_room(false))
	assert_int(WorldSnapshot.of(world).graphics_seed).is_not_equal(den_seed)
	WorldSimulator.enter_room(world, den)
	assert_int(WorldSnapshot.of(world).graphics_seed).is_equal(den_seed)
	assert_array(world.dummies).is_empty()
	assert_bool(world.room.cleared).is_true()
	assert_bool(world.is_room_cleared(den)).is_true()
