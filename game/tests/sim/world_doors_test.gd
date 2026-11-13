extends "res://tests/sim/world_fixture.gd"
## Doors: shut until the room is cleared, then a way into the next room.

const Map := preload("res://shared/data/map.gd")
const Passage := preload("res://shared/data/passage.gd")
const RoomGraph := preload("res://sim/room_graph.gd")
const DataRecords := preload("res://tests/data_records.gd")

## One enemy, far from the north door, in each room.
const ENEMY_OFFSET := Vector2(200, 100)

var _south: Map
var _north: Map


func before_test() -> void:
	super()
	_south = DataRecords.map(true, ENEMY_OFFSET)
	_north = DataRecords.map(true, ENEMY_OFFSET)
	var passage := Passage.new()
	passage.from = _south
	passage.side = RoomShape.Side.NORTH
	passage.to = _north
	var passages: Array[Passage] = [passage]
	world = World.new(_south, null, RoomGraph.new(passages))
	world.add_player(PLAYER_ID)
	world.add_player(PLAYER_ID + 1)


func test_a_shut_door_is_a_wall() -> void:
	_player().pos = _north_gap().get_center() + Vector2(0, 40)
	world.set_input(PLAYER_ID, Vector2.UP, 0)
	_advance(A_WHILE)
	assert_float(_player().pos.y).is_equal_approx(_floor_top(), TOLERANCE)
	assert_bool(world.is_room_cleared(_north)).is_false()


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
	assert_int(world.dummies.size()).is_equal(_north.dummies.size())
	assert_int(world.snapshot().layout_number).is_not_equal(before)
	var arrival := RoomShape.door(RoomShape.Side.SOUTH)
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
	_player().pos = RoomShape.door(RoomShape.Side.SOUTH).get_center()
	world.step()
	assert_array(world.dummies).is_empty()
	assert_bool(world.snapshot().room_cleared).is_true()
	var sides := RoomShape.sides_in(world.snapshot().door_bits)
	assert_array(sides).contains_exactly([RoomShape.Side.NORTH])


func _north_gap() -> Rect2:
	return RoomShape.door(RoomShape.Side.NORTH)


## Where a player's center stops against the north wall.
func _floor_top() -> float:
	return RoomShape.floor_area().position.y + World.player_hurtbox.y / 2
