extends GdUnitTestSuite

const Client := preload("res://client/client.gd")
const Protocol := preload("res://net/protocol.gd")


func test_one_color_per_seat() -> void:
	assert_int(Client.PLAYER_COLORS.size()).is_equal(Protocol.MAX_PLAYERS)
