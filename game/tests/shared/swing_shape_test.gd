extends GdUnitTestSuite

const SwingShape := preload("res://shared/swing_shape.gd")

const RADIUS := 10.0


func test_each_piece_is_under_half_a_turn_and_together_they_span_the_arc() -> void:
	_assert_pieces_span(deg_to_rad(90.0))
	_assert_pieces_span(deg_to_rad(180.0))
	_assert_pieces_span(deg_to_rad(270.0))
	_assert_pieces_span(deg_to_rad(360.0))


func test_every_piece_is_convex() -> void:
	for piece in SwingShape.pieces(RADIUS, TAU):
		var hull := Geometry2D.convex_hull(piece)
		# The hull repeats its first point at the end.
		assert_int(hull.size() - 1).override_failure_message("a piece is concave: %s" % piece) \
				.is_equal(piece.size())


func test_slices_go_from_the_left_to_the_right_one_per_equal_share_of_the_swing() -> void:
	# Three 60-degree slices of a half turn, three ticks each, each turned to
	# its middle.
	assert_float(SwingShape.slice_turn(PI, 3, 0, 9)).is_equal_approx(deg_to_rad(-60.0), 0.001)
	assert_float(SwingShape.slice_turn(PI, 3, 2, 9)).is_equal_approx(deg_to_rad(-60.0), 0.001)
	assert_float(SwingShape.slice_turn(PI, 3, 3, 9)).is_equal_approx(0.0, 0.001)
	assert_float(SwingShape.slice_turn(PI, 3, 5, 9)).is_equal_approx(0.0, 0.001)
	assert_float(SwingShape.slice_turn(PI, 3, 6, 9)).is_equal_approx(deg_to_rad(60.0), 0.001)
	assert_float(SwingShape.slice_turn(PI, 3, 8, 9)).is_equal_approx(deg_to_rad(60.0), 0.001)


## Fails unless the pieces of an [param arc] each start at the center, turn
## under half a turn, and run edge to edge from one side of the arc to the
## other.
func _assert_pieces_span(arc: float) -> void:
	var edge := Vector2.from_angle(-arc / 2) * RADIUS
	for piece in SwingShape.pieces(RADIUS, arc):
		var last := piece[piece.size() - 1]
		assert_vector(piece[0]).is_equal(Vector2.ZERO)
		assert_vector(piece[1]).override_failure_message("a gap in the %s arc" % arc) \
				.is_equal_approx(edge, Vector2.ONE * 0.001)
		assert_float(absf(piece[1].angle_to(last))).is_less(PI)
		edge = last
	assert_vector(edge).is_equal_approx(Vector2.from_angle(arc / 2) * RADIUS, Vector2.ONE * 0.001)
