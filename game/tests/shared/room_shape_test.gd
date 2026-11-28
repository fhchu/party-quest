extends GdUnitTestSuite

const RoomShape := preload("res://shared/room_shape.gd")

const BALANCE := RoomShape.BALANCE


func test_the_arena_is_whole_tiles_each_way() -> void:
	var tiles := BALANCE.arena().size / BALANCE.tile_size
	assert_vector(tiles).is_equal(tiles.floor())


func test_walls_and_floor_cover_the_arena_without_overlapping() -> void:
	var pieces := RoomShape.walls([])
	pieces.append(RoomShape.floor_area())
	_assert_tile_the_arena(pieces)


func test_walls_are_whole_tiles_thick() -> void:
	assert_float(fmod(BALANCE.wall_thickness, BALANCE.tile_size)).is_equal(0.0)
	for wall in RoomShape.walls([]):
		assert_float(minf(wall.size.x, wall.size.y)).override_failure_message(
				"%s is the wrong thickness" % wall).is_equal(BALANCE.wall_thickness)


func test_with_every_door_walls_doors_and_floor_still_cover_the_arena() -> void:
	var every: Array[Direction.Cardinal] = []
	every.assign(Direction.Cardinal.values())
	var pieces := RoomShape.walls(every)
	pieces.append_array(_doors(every))
	pieces.append(RoomShape.floor_area())
	_assert_tile_the_arena(pieces)


func test_a_door_is_whole_tiles_on_the_grid() -> void:
	assert_float(fmod(RoomShape.door_width, BALANCE.tile_size)).is_equal(0.0)
	for side: Direction.Cardinal in Direction.Cardinal.values():
		var gap := RoomShape.door(side)
		var tiles := gap.position / BALANCE.tile_size
		assert_vector(tiles).override_failure_message("door %d is off the grid" % side) \
				.is_equal(tiles.floor())
		assert_float(maxf(gap.size.x, gap.size.y)).is_equal(RoomShape.door_width)


## Fails unless [param pieces] lie in the arena without overlapping and
## cover all of it.
func _assert_tile_the_arena(pieces: Array[Rect2]) -> void:
	var area := 0.0
	for i in pieces.size():
		assert_bool(BALANCE.arena().encloses(pieces[i])) \
				.override_failure_message("%s is outside the arena" % pieces[i]).is_true()
		area += pieces[i].get_area()
		for j in range(i + 1, pieces.size()):
			assert_bool(pieces[i].intersects(pieces[j])) \
					.override_failure_message("%s overlaps %s" % [pieces[i], pieces[j]]).is_false()
	assert_float(area).is_equal(BALANCE.arena().get_area())


func test_door_bits_give_back_the_sides_they_were_made_from() -> void:
	var sides: Array[Direction.Cardinal] = [Direction.Cardinal.EAST, Direction.Cardinal.WEST]
	assert_array(RoomShape.sides_in(RoomShape.door_bits(sides))).contains_exactly(sides)


func _doors(sides: Array[Direction.Cardinal]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side in sides:
		out.append(RoomShape.door(side))
	return out
