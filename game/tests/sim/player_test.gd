extends GdUnitTestSuite
## A player's input handling that doesn't need a world.

const Player := preload("res://sim/player.gd")

const TOLERANCE := 0.001


func test_snap_direction() -> void:
	assert_vector(Player.snap_direction(Vector2(1, 0.3))).is_equal_approx(
			Vector2.RIGHT, Vector2.ONE * TOLERANCE)
	assert_vector(Player.snap_direction(Vector2(1, 1))).is_equal_approx(
			Vector2(1, 1).normalized(), Vector2.ONE * TOLERANCE)
	assert_vector(Player.snap_direction(Vector2.ZERO)).is_equal(Vector2.ZERO)
