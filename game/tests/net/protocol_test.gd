extends GdUnitTestSuite

const GameTime := preload("res://shared/game_time.gd")
const Protocol := preload("res://net/protocol.gd")


func test_snapshot_rate_divides_tick_rate() -> void:
	assert_int(GameTime.TICK_RATE % Protocol.SNAPSHOT_RATE).is_zero()
