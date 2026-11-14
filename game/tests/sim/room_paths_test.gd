extends GdUnitTestSuite
## A room's grid finds the next point on a way around circles in the way.

const RoomPaths := preload("res://sim/room_paths.gd")

const CELL := 16.0
## Ten cells by six.
const FLOOR := Rect2(32, 32, CELL * 10, CELL * 6)

var paths := RoomPaths.new(FLOOR, CELL)


func _blocker(center: Vector2, radius: float) -> RoomPaths.Blocker:
	var out := RoomPaths.Blocker.new()
	out.center = center
	out.radius = radius
	return out


## The center of cell ([param x], [param y]).
func _cell(x: int, y: int) -> Vector2:
	return FLOOR.position + (Vector2(x, y) + Vector2.ONE * 0.5) * CELL


func test_with_nothing_in_the_way_it_steps_toward_the_goal() -> void:
	var next := paths.next_point(_cell(1, 2), _cell(8, 2), [])
	assert_vector(next).is_equal(_cell(2, 2))


func test_it_steps_around_a_circle_in_the_way() -> void:
	var blockers: Array[RoomPaths.Blocker] = [_blocker(_cell(2, 2), CELL)]
	var next := paths.next_point(_cell(1, 2), _cell(8, 2), blockers)
	assert_float(next.distance_to(_cell(2, 2))).is_greater_equal(CELL)
	assert_float(next.distance_to(_cell(1, 2))).is_less_equal(CELL * sqrt(2.0))


func test_with_no_way_through_it_heads_straight_for_the_goal() -> void:
	# A wall of circles across the whole floor.
	var blockers: Array[RoomPaths.Blocker] = []
	for y in 6:
		blockers.append(_blocker(_cell(5, y), CELL / 2))
	var goal := _cell(8, 2)
	assert_vector(paths.next_point(_cell(1, 2), goal, blockers)).is_equal(goal)


func test_blockers_are_forgotten_after_each_query() -> void:
	var blockers: Array[RoomPaths.Blocker] = [_blocker(_cell(2, 2), CELL)]
	paths.next_point(_cell(1, 2), _cell(8, 2), blockers)
	assert_vector(paths.next_point(_cell(1, 2), _cell(8, 2), [])).is_equal(_cell(2, 2))
