extends "res://tests/sim/world_fixture.gd"
## Doors: shut until the room is cleared, then a way into the next room.

const DataLoader := preload("res://shared/data_loader.gd")
const RoomGraph := preload("res://shared/room_graph.gd")

var _setup: DataLoader.RunSetup


func before_test() -> void:
	super()
	_setup = DataLoader.RunSetup.new()
	_setup.start = "south"
	_setup.rooms["south"] = _guarded_map("south")
	_setup.rooms["north"] = _guarded_map("north")
	_setup.passages = [RoomGraph.Passage.new("south", RoomGraph.Side.NORTH, "north")]
	world = World.new(_setup.rooms["south"], null, _setup)
	world.add_player(PLAYER_ID)
	world.add_player(PLAYER_ID + 1)


func test_a_shut_door_is_a_wall() -> void:
	_player().pos = _north_gap().get_center() + Vector2(0, 40)
	world.set_input(PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_float(_player().pos.y).is_equal_approx(_floor_top(), TOLERANCE)
	assert_bool(world.is_room_cleared("north")).is_false()


func test_an_open_door_lets_a_player_into_its_gap() -> void:
	world.dummies.clear()
	world.step()
	_player().pos = Vector2(_north_gap().get_center().x, _floor_top())
	world.set_input(PLAYER_ID, Vector2.UP, 0)
	world.step()
	assert_float(_player().pos.y).is_less(_floor_top())


func test_the_wall_beside_an_open_door_still_stops_players() -> void:
	world.dummies.clear()
	world.step()
	_player().pos = Vector2(_north_gap().position.x - World.player_hurtbox.x, _floor_top() + 20)
	world.set_input(PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_float(_player().pos.y).is_equal_approx(_floor_top(), TOLERANCE)


func test_touching_an_open_door_from_the_floor_keeps_the_party_here() -> void:
	world.dummies.clear()
	world.step()
	var south := world.room
	_player().pos = Vector2(_north_gap().get_center().x, _floor_top())
	world.step()
	assert_object(world.room).is_same(south)


func test_a_center_past_the_wall_takes_the_whole_party_through() -> void:
	world.dummies.clear()
	world.step()
	var before := world.snapshot().layout_number
	_player().pos = _north_gap().get_center()
	world.step()
	assert_int(world.dummies.size()).is_equal(_setup.rooms["north"].dummies.size())
	assert_int(world.snapshot().layout_number).is_not_equal(before)
	var arrival := RoomShape.door(RoomGraph.Side.SOUTH)
	for p: World.Player in world.players.values():
		assert_bool(RoomShape.floor_area().has_point(p.pos)).is_true()
		assert_bool(arrival.grow(World.player_hurtbox.x / 2).has_point(p.pos)).is_false()


func test_the_room_the_party_left_is_cleared_and_open_when_they_come_back() -> void:
	world.dummies.clear()
	world.step()
	_player().pos = _north_gap().get_center()
	world.step()
	world.dummies.clear()
	world.step()
	_player().pos = RoomShape.door(RoomGraph.Side.SOUTH).get_center()
	world.step()
	assert_array(world.dummies).is_empty()
	assert_bool(world.snapshot().room_cleared).is_true()
	assert_array(world.snapshot().door_sides).contains_exactly([RoomGraph.Side.NORTH])


func _north_gap() -> Rect2:
	return RoomShape.door(RoomGraph.Side.NORTH)


## Where a player's center stops against the north wall.
func _floor_top() -> float:
	return RoomShape.floor_area().position.y + World.player_hurtbox.y / 2


## One enemy, far from the north door, that must be defeated to clear it.
func _guarded_map(map_name: String) -> DataLoader.Map:
	var m := DataLoader.Map.new()
	m.name = map_name
	var spot := DataLoader.MapDummy.new()
	spot.kind = DummyKinds.enemy_kind
	spot.offset = Vector2(200, 100)
	m.dummies = [spot]
	var entry := DataLoader.ConditionEntry.new()
	entry.name = "defeat_all"
	entry.arg = "enemy"
	m.clear_when = [entry]
	return m
