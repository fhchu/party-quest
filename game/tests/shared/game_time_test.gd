extends GdUnitTestSuite

const GameTime := preload("res://shared/game_time.gd")


func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(GameTime.ticks(0.0)).is_equal(0)
	assert_int(GameTime.ticks(0.001)).is_equal(1)
	assert_int(GameTime.ticks(0.5)).is_equal(GameTime.TICK_RATE / 2)


func test_seconds_undoes_ticks() -> void:
	assert_float(GameTime.seconds(GameTime.ticks(2.0))).is_equal_approx(2.0, 0.0001)
	assert_float(GameTime.seconds(GameTime.TICK_RATE)).is_equal_approx(1.0, 0.0001)
