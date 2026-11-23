extends GdUnitTestSuite
## The touch controls' layout rules.

const TouchControls := preload("res://client/ui/touch_controls.gd")


func test_a_square_icon_of_any_size_scales_to_the_icon_size() -> void:
	for side: float in [16.0, 32.0]:
		var image := Vector2(side, side)
		assert_float(image.x * TouchControls.icon_scale(image)) \
				.is_equal_approx(TouchControls.ATTACK_ICON_SIZE, 0.001)


func test_an_icon_keeps_its_shape_with_the_longer_side_fitting() -> void:
	var image := Vector2(32.0, 16.0)
	var scale := TouchControls.icon_scale(image)
	assert_float(image.x * scale).is_equal_approx(TouchControls.ATTACK_ICON_SIZE, 0.001)
	assert_float(image.y * scale).is_equal_approx(TouchControls.ATTACK_ICON_SIZE / 2, 0.001)
