extends GdUnitTestSuite


func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(GameTime.ticks(0.0)).is_equal(0)
	assert_int(GameTime.ticks(0.001)).is_equal(1)
	# 30 ticks a second.
	assert_int(GameTime.ticks(0.5)).is_equal(15)


func test_seconds_undoes_ticks() -> void:
	assert_float(GameTime.seconds(GameTime.ticks(2.0))).is_equal_approx(2.0, 0.0001)
	assert_float(GameTime.seconds(30)).is_equal_approx(1.0, 0.0001)
