extends GdUnitTestSuite


func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(GameTime.ticks(0.0)).is_equal(0)
	assert_int(GameTime.ticks(0.001)).is_equal(1)
	assert_int(GameTime.ticks(0.5)).is_equal(int(GameTime.TICK_RATE * 0.5))


func test_seconds_undoes_ticks() -> void:
	assert_bool(is_equal_approx(GameTime.seconds(GameTime.ticks(2.0)), 2.0)).is_true()
	assert_bool(is_equal_approx(GameTime.seconds(GameTime.TICK_RATE), 1.0)).is_true()
