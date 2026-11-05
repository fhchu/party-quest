extends GdUnitTestSuite

const Palette := preload("res://client/palette.gd")
const Protocol := preload("res://net/protocol.gd")


func test_one_color_per_seat() -> void:
	assert_int(Palette.PLAYER_COLORS.size()).is_equal(Protocol.MAX_PLAYERS)
