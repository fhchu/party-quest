extends GdUnitTestSuite


func test_opposite_ways_pair_up() -> void:
	for way: Direction.Cardinal in Direction.Cardinal.values():
		assert_int(Direction.opposite(way)).is_not_equal(way)
		assert_int(Direction.opposite(Direction.opposite(way))).is_equal(way)


func test_an_opposite_way_points_back() -> void:
	for way: Direction.Cardinal in Direction.Cardinal.values():
		assert_vector(Direction.to_vector(Direction.opposite(way))).is_equal(
				-Direction.to_vector(way))


func test_north_is_up_the_screen() -> void:
	assert_vector(Direction.to_vector(Direction.Cardinal.NORTH)).is_equal(Vector2(0, -1))


func test_each_next_way_is_a_quarter_turn_clockwise_on_screen() -> void:
	for way: Direction.Cardinal in Direction.Cardinal.values():
		var next := (way + 1) % Direction.Cardinal.size() as Direction.Cardinal
		assert_bool(Direction.to_vector(next).is_equal_approx(
				Direction.to_vector(way).rotated(PI / 2))).is_true()
