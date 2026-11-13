extends GdUnitTestSuite

const DataLoader := preload("res://shared/data_loader.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const RoomGraph := preload("res://shared/room_graph.gd")


func test_the_arena_is_whole_tiles_each_way() -> void:
	var tiles := DataLoader.arena.size / DataLoader.tile_size
	assert_vector(tiles).is_equal(tiles.floor())


func test_walls_and_floor_cover_the_arena_without_overlapping() -> void:
	var pieces := RoomShape.walls([])
	pieces.append(RoomShape.floor_area())
	var area := 0.0
	for i in pieces.size():
		assert_bool(DataLoader.arena.encloses(pieces[i])).is_true()
		area += pieces[i].get_area()
		for j in range(i + 1, pieces.size()):
			assert_bool(pieces[i].intersects(pieces[j])).is_false()
	assert_float(area).is_equal(DataLoader.arena.get_area())


func test_walls_are_one_tile_thick() -> void:
	for wall in RoomShape.walls([]):
		assert_float(minf(wall.size.x, wall.size.y)).is_equal(DataLoader.tile_size)


func test_with_every_door_walls_doors_and_floor_still_cover_the_arena() -> void:
	var every: Array[RoomGraph.Side] = []
	every.assign(RoomGraph.Side.values())
	var pieces := RoomShape.walls(every)
	for side in every:
		pieces.append(RoomShape.door(side))
	pieces.append(RoomShape.floor_area())
	var area := 0.0
	for i in pieces.size():
		area += pieces[i].get_area()
		for j in range(i + 1, pieces.size()):
			assert_bool(pieces[i].intersects(pieces[j])).is_false()
	assert_float(area).is_equal(DataLoader.arena.get_area())


func test_a_door_is_whole_tiles_on_the_grid() -> void:
	for side: RoomGraph.Side in RoomGraph.Side.values():
		var gap := RoomShape.door(side)
		var tiles := Vector2(gap.position.x, gap.position.y) / DataLoader.tile_size
		assert_vector(tiles).is_equal(tiles.floor())
		assert_float(maxf(gap.size.x, gap.size.y)).is_equal(DataLoader.door_width)
		assert_float(fmod(DataLoader.door_width, DataLoader.tile_size)).is_equal(0.0)
