extends GdUnitTestSuite

const RoomGraph := preload("res://shared/room_graph.gd")
const RoomShape := preload("res://shared/room_shape.gd")


func test_a_passage_is_a_door_at_each_end_on_opposite_walls() -> void:
	var passages: Array[RoomGraph.Passage] = [
		RoomGraph.Passage.new("south room", RoomShape.Side.NORTH, "north room"),
	]
	var out := RoomGraph.doors(passages, "south room")
	var back := RoomGraph.doors(passages, "north room")
	assert_int(out.size()).is_equal(1)
	assert_int(back.size()).is_equal(1)
	assert_str(out[0].to).is_equal("north room")
	assert_str(back[0].to).is_equal("south room")
	assert_int(out[0].side).is_equal(RoomShape.Side.NORTH)
	assert_int(back[0].side).is_equal(RoomShape.Side.SOUTH)


func test_sides_are_found_by_name_in_any_case() -> void:
	assert_int(RoomGraph.side_named("north")).is_equal(RoomShape.Side.NORTH)
	assert_int(RoomGraph.side_named("Up")).is_equal(-1)
