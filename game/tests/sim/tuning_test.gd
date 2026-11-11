extends GdUnitTestSuite

const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")


func test_ticks_rounds_seconds_to_whole_ticks() -> void:
	assert_int(Tuning.ticks(0.0)).is_equal(0)
	assert_int(Tuning.ticks(0.001)).is_equal(1)
	assert_int(Tuning.ticks(0.5)).is_equal(Protocol.TICK_RATE / 2)


func test_arena_fits_the_viewport() -> void:
	var viewport := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	assert_bool(Tuning.arena.end.x <= viewport.x and Tuning.arena.end.y <= viewport.y).is_true()


func test_balance_file_loads() -> void:
	assert_str(Tuning.balance_version).is_not_empty()
	assert_bool(Tuning.arena.size.x > 0).is_true()
	assert_bool(Tuning.swing_ticks > 0).is_true()


func test_the_swing_arc_stays_convex() -> void:
	# The world hits with the arc as a convex polygon, which a slice wider
	# than half a turn isn't.
	assert_float(Tuning.swing_arc).is_less_equal(PI)
