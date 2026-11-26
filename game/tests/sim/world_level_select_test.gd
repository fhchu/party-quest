extends "res://tests/sim/world_fixture.gd"
## A door that opens the level select, and the goal choosing a level meets.

const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const LEVEL := 3

var _room := Room.new()


func before_test() -> void:
	super()
	var passage := Passage.new()
	passage.from = _room
	passage.side = Direction.Cardinal.NORTH
	passage.opens_level_select = true
	var win := Condition.new()
	win.type = Condition.Type.LEVEL_SELECTED
	world = WorldSimulator.start(WorldLoader.run_plan(_room, [passage], [win]))
	WorldSimulator.add_player(world, PLAYER_ID)
	WorldSimulator.add_player(world, PLAYER_ID + 1)


func test_the_door_leads_to_no_room() -> void:
	assert_int(world.run_plan.rooms.size()).is_equal(1)
	assert_bool(world.room.doors[0].opens_level_select).is_true()


func test_going_through_it_freezes_the_world_with_the_party_in_this_room() -> void:
	var room_before := world.room
	_walk_into_the_door()
	assert_bool(world.level_select_requested).is_true()
	assert_bool(world.frozen).is_true()
	assert_object(world.room).is_same(room_before)
	assert_bool(_north_gap().has_point(_player().pos)).is_true()


func test_going_through_it_stops_everyone() -> void:
	_walk_into_the_door()
	assert_vector(_player().move).is_equal(Vector2.ZERO)


func test_shutting_the_level_select_runs_the_world_again() -> void:
	_walk_into_the_door()
	WorldSimulator.close_level_select(world, WorldState.NO_LEVEL)
	var tick_pos := _player().pos
	_steer(Vector2.DOWN)
	_advance(1)
	assert_bool(world.level_select_requested).is_false()
	assert_float(_player().pos.y).is_greater(tick_pos.y)


func test_selecting_a_level_wins_on_the_next_step() -> void:
	_walk_into_the_door()
	WorldSimulator.close_level_select(world, LEVEL)
	assert_int(world.outcome).is_equal(WorldState.Outcome.NONE)
	_advance(1)
	assert_int(world.outcome).is_equal(WorldState.Outcome.WON)
	assert_int(world.selected_level).is_equal(LEVEL)


## Walks the player north until the level select is asked for, or a while.
func _walk_into_the_door() -> void:
	_player().pos = _north_gap().get_center() + Vector2(0, 40)
	for i in A_WHILE:
		_steer(Vector2.UP)
		_advance(1)
		if world.level_select_requested:
			return


func _north_gap() -> Rect2:
	return RoomShape.door(Direction.Cardinal.NORTH)
