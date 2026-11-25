extends GdUnitTestSuite
## A player's input handling that doesn't need a world.

const Player := preload("res://sim/player.gd")

const TOLERANCE := 0.001
const NORTH := Direction.Cardinal.NORTH
const EAST := Direction.Cardinal.EAST
const SOUTH := Direction.Cardinal.SOUTH
const WEST := Direction.Cardinal.WEST
const NORTHEAST := Vector2(1, -1)
const SOUTHEAST := Vector2(1, 1)
const SOUTHWEST := Vector2(-1, 1)
const NORTHWEST := Vector2(-1, -1)


func test_snap_direction() -> void:
	assert_vector(Player.snap_direction(Vector2(1, 0.3))).is_equal_approx(
			Vector2.RIGHT, Vector2.ONE * TOLERANCE)
	assert_vector(Player.snap_direction(Vector2(1, 1))).is_equal_approx(
			Vector2(1, 1).normalized(), Vector2.ONE * TOLERANCE)
	assert_vector(Player.snap_direction(Vector2.ZERO)).is_equal(Vector2.ZERO)


func test_a_cardinal_move_faces_it_from_any_facing() -> void:
	for facing: Direction.Cardinal in Direction.Cardinal.values():
		for way: Direction.Cardinal in Direction.Cardinal.values():
			assert_int(_facing_after(facing, Direction.to_vector(way))).is_equal(way)


func test_a_diagonal_keeps_a_facing_along_either_of_its_cardinals() -> void:
	var cases: Array[Array] = [
		[NORTH, NORTHEAST], [EAST, NORTHEAST],
		[EAST, SOUTHEAST], [SOUTH, SOUTHEAST],
		[SOUTH, SOUTHWEST], [WEST, SOUTHWEST],
		[WEST, NORTHWEST], [NORTH, NORTHWEST],
	]
	for c in cases:
		assert_int(_facing_after(c[0], c[1])).override_failure_message(
				"facing %s, moving %s" % c).is_equal(c[0])


func test_a_diagonal_from_another_facing_faces_its_counter_clockwise_cardinal() -> void:
	# [facing, move, expected]: the two facings that aren't the move's.
	var cases: Array[Array] = [
		[SOUTH, NORTHEAST, NORTH], [WEST, NORTHEAST, NORTH],
		[NORTH, SOUTHEAST, EAST], [WEST, SOUTHEAST, EAST],
		[NORTH, SOUTHWEST, SOUTH], [EAST, SOUTHWEST, SOUTH],
		[EAST, NORTHWEST, WEST], [SOUTH, NORTHWEST, WEST],
	]
	for c in cases:
		assert_int(_facing_after(c[0], c[1])).override_failure_message(
				"facing %s, moving %s" % [c[0], c[1]]).is_equal(c[2])


func test_no_move_keeps_the_facing() -> void:
	for facing: Direction.Cardinal in Direction.Cardinal.values():
		assert_int(_facing_after(facing, Vector2.ZERO)).is_equal(facing)


## A player facing [param facing] after one step's input of [param move].
func _facing_after(facing: Direction.Cardinal, move: Vector2) -> Direction.Cardinal:
	var p := Player.new()
	# Alive: a downed player doesn't turn.
	p.health = 1
	p.facing = facing
	p.set_input(move, PackedByteArray(), 0)
	p.step()
	return p.facing
