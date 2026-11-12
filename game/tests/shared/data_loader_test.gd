extends GdUnitTestSuite

const DataLoader := preload("res://shared/data_loader.gd")


func test_arena_fits_the_viewport() -> void:
	var viewport := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	var arena := DataLoader.arena
	assert_bool(arena.end.x <= viewport.x and arena.end.y <= viewport.y).is_true()


func test_balance_file_loads() -> void:
	assert_bool(DataLoader.arena.size.x > 0).is_true()
	assert_bool(DataLoader.swing_active_sec > 0).is_true()


func test_the_swing_arc_stays_convex() -> void:
	# The world hits with the arc as a convex polygon, which a slice wider
	# than half a turn isn't.
	assert_float(DataLoader.swing_arc).is_less_equal(PI)
