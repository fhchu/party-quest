extends GdUnitTestSuite

const SwingShape := preload("res://shared/swing_shape.gd")

const RADIUS := 10.0


func test_each_piece_is_under_half_a_turn_and_together_they_span_the_arc() -> void:
	for degrees: float in [90.0, 180.0, 270.0, 360.0]:
		var arc := deg_to_rad(degrees)
		var pieces := SwingShape.pieces(RADIUS, arc)
		var edge := Vector2.from_angle(-arc / 2) * RADIUS
		for piece in pieces:
			assert_vector(piece[0]).is_equal(Vector2.ZERO)
			assert_bool(piece[1].is_equal_approx(edge)).is_true()
			var last := piece[piece.size() - 1]
			assert_float(absf(piece[1].angle_to(last))).is_less(PI)
			edge = last
		assert_bool(edge.is_equal_approx(Vector2.from_angle(arc / 2) * RADIUS)).is_true()


func test_every_piece_is_convex() -> void:
	for piece in SwingShape.pieces(RADIUS, TAU):
		var hull := Geometry2D.convex_hull(piece)
		# The hull repeats its first point at the end.
		assert_int(hull.size() - 1).is_equal(piece.size())


func test_slices_go_from_the_left_to_the_right_one_per_equal_share_of_the_swing() -> void:
	var arc := PI
	var slices := 3
	var total := 9
	var slice_arc := arc / slices
	for elapsed in total:
		var expected := -arc / 2 + slice_arc * (floori(elapsed / 3.0) + 0.5)
		assert_bool(is_equal_approx(
				SwingShape.slice_turn(arc, slices, elapsed, total), expected)).is_true()
