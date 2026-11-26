extends GdUnitTestSuite
## The touch controls' layout rules, where the joystick starts and how far
## its base follows, and where the item buttons press.

const GameView := preload("res://client/game_view.gd")
const ItemButton := preload("res://client/ui/item_button.gd")
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
	var controls: Control = TouchControlsScene.instantiate()
	_screen.add_child(controls)
	controls.show_buttons(true, GameView.ItemSlot.new(), GameView.ItemSlot.new(), false)


func after_test() -> void:
	var actions: Array[StringName] = [
			&"move_left", &"move_right", &"move_up", &"move_down", &"use_item_1",
			&"use_item_2"]
	for action in actions:
		Input.action_release(action)


func _joystick() -> VirtualJoystick:
	return _screen.get_child(0).get_node("%Joystick")


func _send(event: InputEvent) -> void:
	_screen.push_input(event)
	await await_idle_frame()


## Every press and drag runs along the middle of the screen.
func _at(x: float) -> Vector2:
	return Vector2(x, _screen.size.y / 2.0)


func _touch(x: float, pressed := true) -> void:
	await _touch_at(_at(x), pressed)


func _touch_at(pos: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = pressed
	await _send(event)


func _controls() -> TouchControls:
	return _screen.get_child(0) as TouchControls


func _button_rect(button: String) -> Rect2:
	return (_controls().get_node(button) as Control).get_global_rect()


func _slot_1_center() -> Vector2:
	return Vector2(_screen.size) * TouchControls.SLOT_1_CENTER_RATIO


func _slot_2_center() -> Vector2:
	return _slot_1_center() + TouchControls.SLOT_2_OFFSET


func _drag(x: float) -> void:
	var event := InputEventScreenDrag.new()
	event.position = _at(x)
	await _send(event)


## Just inside or outside the move area's edge, by a joystick's width, so
## the base has room to move.
func _inside_move_area() -> float:
	return _screen.size.x * TouchControls.MOVE_AREA_RATIO - _joystick().joystick_size


func _outside_move_area() -> float:
	return _screen.size.x * TouchControls.MOVE_AREA_RATIO + _joystick().joystick_size


func _far_right() -> float:
	return _screen.size.x - _joystick().joystick_size


func test_a_square_icon_of_any_size_scales_to_the_icon_size() -> void:
	for side: float in [16.0, 32.0]:
		var image := Vector2(side, side)
		assert_bool(is_equal_approx(
				image.x * ItemButton.icon_scale(image), ItemButton.ICON_SIZE)).is_true()


func test_an_icon_keeps_its_shape_with_the_longer_side_fitting() -> void:
	var image := Vector2(32.0, 16.0)
	var scale := ItemButton.icon_scale(image)
	assert_bool(is_equal_approx(image.x * scale, ItemButton.ICON_SIZE)).is_true()
	assert_bool(is_equal_approx(image.y * scale, ItemButton.ICON_SIZE / 2)).is_true()


func test_a_touch_outside_the_move_area_doesnt_start_the_joystick() -> void:
	await _touch(_inside_move_area())
	await _drag(_far_right())
	assert_bool(Input.is_action_pressed(&"move_right")).is_true()
	await _touch(_far_right(), false)
	await _touch(_outside_move_area())
	await _drag(_far_right())
	assert_bool(Input.is_action_pressed(&"move_right")).is_false()


func test_the_base_follows_the_thumb_out_of_the_move_area() -> void:
	await _touch(_inside_move_area())
	await _drag(_far_right())
	# The base trails the thumb by at most a joystick's radius, so a
	# joystick's width back reads as left. A base left at the move area's
	# edge would read it as still right.
	await _drag(_far_right() - _joystick().joystick_size)
	assert_bool(Input.is_action_pressed(&"move_left")).is_true()


func test_a_touch_on_slot_1s_button_presses_use_item_1_until_lifted() -> void:
	await _touch_at(_slot_1_center())
	assert_bool(Input.is_action_pressed(&"use_item_1")).is_true()
	await _touch_at(_slot_1_center(), false)
	assert_bool(Input.is_action_pressed(&"use_item_1")).is_false()


func test_a_touch_in_the_slot_1_buttons_corner_outside_its_circle_misses() -> void:
	var button_rect := _button_rect("%Slot1Button")
	# A tenth of the way in on both axes: inside the button's square, outside
	# the circle that fits it.
	var corner := button_rect.position + button_rect.size * 0.1
	assert_bool(button_rect.has_point(corner)).is_true()
	await _touch_at(corner)
	assert_bool(Input.is_action_pressed(&"use_item_1")).is_false()


func test_a_touch_on_slot_2s_button_presses_use_item_2_until_lifted() -> void:
	await _touch_at(_slot_2_center())
	assert_bool(Input.is_action_pressed(&"use_item_2")).is_true()
	assert_bool(Input.is_action_pressed(&"use_item_1")).is_false()
	await _touch_at(_slot_2_center(), false)
	assert_bool(Input.is_action_pressed(&"use_item_2")).is_false()


func test_the_item_buttons_circles_dont_overlap() -> void:
	var slot_1 := _button_rect("%Slot1Button")
	var slot_2 := _button_rect("%Slot2Button")
	var radii := (slot_1.size.x + slot_2.size.x) / 2.0
	assert_float(slot_1.get_center().distance_to(slot_2.get_center())).is_greater(radii)


func test_the_buttons_keep_their_places_whatever_the_slots_hold() -> void:
	var slot_1 := _button_rect("%Slot1Button")
	var slot_2 := _button_rect("%Slot2Button")
	_controls().show_buttons(true, null, null, false)
	assert_object(_button_rect("%Slot1Button")).is_equal(slot_1)
	assert_object(_button_rect("%Slot2Button")).is_equal(slot_2)


func test_over_the_level_select_only_back_shows_and_the_joystick_is_off() -> void:
	_controls().show_buttons(true, null, null, true)
	assert_bool((_controls().get_node("%Slot1Button") as Control).visible).is_false()
	assert_bool((_controls().get_node("%Slot2Button") as Control).visible).is_false()
	assert_bool((_controls().get_node("%BackButton") as Node2D).visible).is_true()
	assert_bool(_joystick().visible).is_false()


func test_back_shows_only_over_the_level_select() -> void:
	assert_bool((_controls().get_node("%BackButton") as Node2D).visible).is_false()
	assert_bool(_joystick().visible).is_true()


func test_back_sits_across_from_slot_1() -> void:
	var back := _controls().get_node("%BackButton") as Node2D
	var screen := Vector2(_screen.size)
	assert_float(back.position.x).is_equal_approx(screen.x - _slot_1_center().x, 0.5)
	assert_float(back.position.y).is_equal_approx(_slot_1_center().y, 0.5)
