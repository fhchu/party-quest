extends GdUnitTestSuite

const Protocol := preload("res://net/protocol.gd")


func test_snapshot_rate_divides_tick_rate() -> void:
	assert_int(Protocol.TICK_RATE % Protocol.SNAPSHOT_RATE).is_zero()
