extends GdUnitTestSuite


func test_each_way_points_its_way_on_screen() -> void:
	assert_vector(Direction.to_vector(Direction.Cardinal.NORTH)).is_equal(Vector2(0, -1))
	assert_vector(Direction.to_vector(Direction.Cardinal.EAST)).is_equal(Vector2(1, 0))
	assert_vector(Direction.to_vector(Direction.Cardinal.SOUTH)).is_equal(Vector2(0, 1))
	assert_vector(Direction.to_vector(Direction.Cardinal.WEST)).is_equal(Vector2(-1, 0))


func test_opposite_ways_pair_up() -> void:
	assert_int(Direction.opposite(Direction.Cardinal.NORTH)).is_equal(Direction.Cardinal.SOUTH)
	assert_int(Direction.opposite(Direction.Cardinal.SOUTH)).is_equal(Direction.Cardinal.NORTH)
	assert_int(Direction.opposite(Direction.Cardinal.EAST)).is_equal(Direction.Cardinal.WEST)
	assert_int(Direction.opposite(Direction.Cardinal.WEST)).is_equal(Direction.Cardinal.EAST)
