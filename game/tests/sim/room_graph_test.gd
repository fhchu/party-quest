extends GdUnitTestSuite

const RoomGraph := preload("res://sim/room_graph.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const Map := preload("res://shared/data/map.gd")
const Passage := preload("res://shared/data/passage.gd")


func test_a_passage_is_a_door_at_each_end_on_opposite_walls() -> void:
	var south := Map.new()
	var north := Map.new()
	var passage := Passage.new()
	passage.from = south
	passage.side = RoomShape.Side.NORTH
	passage.to = north
	var passages: Array[Passage] = [passage]
	var graph := RoomGraph.new(passages)
	var out := graph.doors(south)
	var back := graph.doors(north)
	assert_int(out.size()).is_equal(1)
	assert_int(back.size()).is_equal(1)
	assert_object(out[0].to).is_same(north)
	assert_object(back[0].to).is_same(south)
	assert_int(out[0].side).is_equal(RoomShape.Side.NORTH)
	assert_int(back[0].side).is_equal(RoomShape.Side.SOUTH)
