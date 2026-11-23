extends GdUnitTestSuite
## The touch controls' layout rules, and where the joystick starts and how
## far its base follows.

const TouchControls := preload("res://client/ui/touch_controls.gd")
const TouchControlsScene := preload("res://client/ui/touch_controls.tscn")


## Touches go to a viewport of the game's size, since the headless window
## isn't and would scale every touch.
var _screen: SubViewport


func before_test() -> void:
	_screen = auto_free(SubViewport.new())
	_screen.size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child(_screen)
	_screen.add_child(TouchControlsScene.instantiate())


func after_test() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


func _send(event: InputEvent) -> void:
	_screen.push_input(event)
	await await_idle_frame()


func _touch(x: float) -> void:
	var event := InputEventScreenTouch.new()
	event.position = Vector2(x, 180)
	event.pressed = true
	await _send(event)


func _drag(x: float) -> void:
	var event := InputEventScreenDrag.new()
	event.position = Vector2(x, 180)
	await _send(event)


func _move_area_edge() -> float:
	return _screen.size.x * TouchControls.MOVE_AREA_RATIO


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


func test_a_touch_outside_the_move_area_doesnt_start_the_joystick() -> void:
	await _touch(_move_area_edge() + 40)
	await _drag(_screen.size.x - 20)
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()


func test_the_base_follows_the_thumb_out_of_the_move_area() -> void:
	await _touch(20)
	await _drag(_screen.size.x - 20)
	# A base left at the move area's edge would read this as still right.
	await _drag(_screen.size.x - 100)
	assert_bool(Input.is_action_pressed(&"move_left")).is_true()
