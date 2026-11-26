extends GdUnitTestSuite
## ClientLoader: how the client draws what the data describes.

const ClientLoader := preload("res://client/client_loader.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")


func test_a_swing_look_turns_to_its_leftmost_slice_first_and_its_rightmost_last() -> void:
	var swing := ClientLoader.SwingLook.new(_sword(0.3, 0.0, 20.0, 120.0, 3))
	# Three 40-degree slices of a 120-degree arc, each turned to its middle.
	assert_bool(is_equal_approx(swing.turn(1), deg_to_rad(-40.0))).is_true()
	assert_bool(is_equal_approx(swing.turn(GameTime.ticks(0.3)), deg_to_rad(40.0))).is_true()


func test_a_swing_look_gets_its_swords_time_offset_and_reach() -> void:
	var swing := ClientLoader.SwingLook.new(_sword(0.3, 7.0, 20.0, 120.0, 3))
	assert_int(swing.ticks).is_equal(GameTime.ticks(0.3))
	assert_float(swing.offset).is_equal(7.0)
	var farthest := 0.0
	for piece in swing.pieces:
		for point in piece:
			farthest = maxf(farthest, point.length())
	assert_bool(is_equal_approx(farthest, 20.0)).is_true()


## A sword whose swing lasts [param sec], starts [param offset] px ahead,
## reaches [param radius] px and sweeps [param arc_deg] in [param slices].
func _sword(sec: float, offset: float, radius: float, arc_deg: float, slices: int) -> ItemSword:
	var out := ItemSword.new()
	out.swing_active_sec = sec
	out.swing_offset = offset
	out.swing_radius = radius
	out.swing_arc_deg = arc_deg
	out.swing_slices = slices
	return out
