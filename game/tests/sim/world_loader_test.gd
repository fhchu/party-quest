extends GdUnitTestSuite
## WorldLoader: rooms become plans, conditions goals, passages doors.

const World := preload("res://sim/world.gd")
const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const WorldLoader := World.WorldLoader


func test_a_passage_is_a_door_at_each_end_in_opposite_walls() -> void:
	var south := Room.new()
	var north := Room.new()
	var passage := Passage.new()
	passage.from = south
	passage.side = RoomShape.Side.NORTH
	passage.to = north
	var passages: Array[Passage] = [passage]
	var run := WorldLoader.run_plan(south, passages)
	assert_array(run.rooms).has_size(2)
	var door := run.start.doors[0]
	assert_vector(door.wall.inward).is_equal(RoomShape.inward(RoomShape.Side.NORTH))
	var back := run.rooms[door.leads_to].doors[0]
	assert_object(run.rooms[back.leads_to]).is_same(run.start)
	assert_object(back.wall).is_same(door.arrive_by)


func test_a_runs_plans_are_freed_with_it() -> void:
	var run := WorldLoader.first_run()
	var start: WeakRef = weakref(run.start)
	run = null
	assert_object(start.get_ref()).is_null()


func test_every_condition_type_has_a_goal_type() -> void:
	for type: Condition.Type in Condition.Type.values():
		assert_bool(WorldLoader.GOAL_TYPES.has(type)).is_true()
