extends "res://tests/sim/world_fixture.gd"
## Doors: shut until the room is cleared, then a way into the next room.

const DataRecords := preload("res://tests/data_records.gd")
const RoomPlan := preload("res://sim/room_plan.gd")

## One enemy, far from the north door, in each room.
const ENEMY_OFFSET := Vector2(200, 100)

var _south: RoomPlan
var _north: RoomPlan


func before_test() -> void:
	super()
	_south = DataRecords.new_room(true, ENEMY_OFFSET)
	_north = DataRecords.new_room(true, ENEMY_OFFSET)
	var run := DataRecords.run(_south)
	WorldLoader.join(run, _south, RoomShape.Side.NORTH, _north)
	world = WorldSimulator.start(run)
	WorldSimulator.add_player(world, PLAYER_ID)
	WorldSimulator.add_player(world, PLAYER_ID + 1)


func test_a_shut_door_is_a_wall() -> void:
	_player().pos = _north_gap().get_center() + Vector2(0, 40)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_float(_player().pos.y).is_equal_approx(_floor_top(), TOLERANCE)
	assert_bool(world.is_room_cleared(_north)).is_false()


func test_an_open_door_lets_a_player_into_its_gap() -> void:
	world.dummies.clear()
	WorldSimulator.step(world)
	_player().pos = Vector2(_north_gap().get_center().x, _floor_top())
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.UP, 0)
	WorldSimulator.step(world)
	assert_float(_player().pos.y).is_less(_floor_top())


func test_a_player_of_the_balance_size_walks_through_an_open_door() -> void:
	WorldState.data.player_hurtbox = WorldLoader.player_hurtbox
	_player().collider = WorldState.data.player_hurtbox
	world.dummies.clear()
	WorldSimulator.step(world)
	var south := world.room
	_player().pos = Vector2(_north_gap().get_center().x, RoomShape.floor_area().get_center().y)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_object(world.room).is_not_same(south)


func test_the_wall_beside_an_open_door_still_stops_players() -> void:
	world.dummies.clear()
	WorldSimulator.step(world)
	_player().pos = Vector2(_north_gap().position.x - PLAYER_SIZE.x, _floor_top() + 20)
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_float(_player().pos.y).is_equal_approx(_floor_top(), TOLERANCE)


func test_touching_an_open_door_from_the_floor_keeps_the_party_here() -> void:
	world.dummies.clear()
	WorldSimulator.step(world)
	var south := world.room
	_player().pos = Vector2(_north_gap().get_center().x, _floor_top())
	WorldSimulator.step(world)
	assert_object(world.room).is_same(south)


func test_a_center_past_the_wall_takes_the_whole_party_through() -> void:
	world.dummies.clear()
	WorldSimulator.step(world)
	var earlier := WorldSnapshot.of(world).layout_number
	_player().pos = _north_gap().get_center()
	WorldSimulator.step(world)
	assert_int(world.dummies.size()).is_equal(_north.spots.size())
	assert_int(WorldSnapshot.of(world).layout_number).is_not_equal(earlier)
	var arrival := RoomShape.door(RoomShape.Side.SOUTH)
	for p: Player in world.players.values():
		assert_bool(RoomShape.floor_area().has_point(p.pos)).is_true()
		assert_bool(arrival.grow(PLAYER_SIZE.x / 2).has_point(p.pos)).is_false()


func test_the_room_the_party_left_is_cleared_and_open_when_they_come_back() -> void:
	world.dummies.clear()
	WorldSimulator.step(world)
	_player().pos = _north_gap().get_center()
	WorldSimulator.step(world)
	world.dummies.clear()
	WorldSimulator.step(world)
	_player().pos = RoomShape.door(RoomShape.Side.SOUTH).get_center()
	WorldSimulator.step(world)
	assert_array(world.dummies).is_empty()
	assert_bool(WorldSnapshot.of(world).room_cleared).is_true()
	var sides := RoomShape.sides_in(WorldSnapshot.of(world).door_bits)
	assert_array(sides).contains_exactly([RoomShape.Side.NORTH])


func _north_gap() -> Rect2:
	return RoomShape.door(RoomShape.Side.NORTH)


## Where a player's center stops against the north wall.
func _floor_top() -> float:
	return RoomShape.floor_area().position.y + PLAYER_SIZE.y / 2
