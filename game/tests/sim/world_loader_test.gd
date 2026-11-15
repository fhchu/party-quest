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
	var start := WorldLoader.run_plan(south, passages).start
	var door := start.doors[0]
	assert_object(door.leads_to).is_same(WorldLoader.room_plan(north))
	assert_vector(door.wall.inward).is_equal(RoomShape.inward(RoomShape.Side.NORTH))
	var back := door.leads_to.doors[0]
	assert_object(back.leads_to).is_same(start)
	assert_object(back.wall).is_same(door.arrive_by)


func test_a_room_is_the_same_plan_every_time() -> void:
	var room := Room.new()
	assert_object(WorldLoader.room_plan(room)).is_same(WorldLoader.room_plan(room))


func test_every_condition_type_has_a_goal_type() -> void:
	for type: Condition.Type in Condition.Type.values():
		assert_bool(WorldLoader.GOAL_TYPES.has(type)).is_true()
