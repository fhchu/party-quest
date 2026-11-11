extends GdUnitTestSuite

const Protocol := preload("res://net/protocol.gd")


func test_snapshot_rate_divides_tick_rate() -> void:
	assert_int(Protocol.TICK_RATE % Protocol.SNAPSHOT_RATE).is_zero()


func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(Protocol.ticks(0.0)).is_equal(0)
	assert_int(Protocol.ticks(0.001)).is_equal(1)
	assert_int(Protocol.ticks(0.5)).is_equal(Protocol.TICK_RATE / 2)
