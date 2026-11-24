extends GdUnitTestSuite
## Presses sort into keys, touches and attacks for the client.

const InputReader := preload("res://client/input_reader.gd")
const TouchControlsScene := preload("res://client/ui/touch_controls.tscn")


## Presses go to a viewport of the game's size, since the headless window
## isn't and would scale every touch.
var _screen: SubViewport


func before_test() -> void:
	_screen = auto_free(SubViewport.new())
	_screen.size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	add_child(_screen)


func _reader() -> InputReader:
	var reader := InputReader.new()
	_screen.add_child(reader)
	return reader


func _key_for(action: StringName) -> InputEventKey:
	var event := InputEventKey.new()
	var bound := InputMap.action_get_events(action)[0] as InputEventKey
	event.physical_keycode = bound.physical_keycode
	event.pressed = true
	return event


## Sends [param event] through the screen, as a real press would arrive.
func _press(event: InputEvent) -> void:
	_screen.push_input(event)
	await await_idle_frame()


func _touch(pos: Vector2, pressed := true) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = pos
	event.pressed = pressed
	return event


func test_a_move_key_is_told_apart_from_other_keys() -> void:
	var reader := _reader()
	var seen: Array[bool] = []
	reader.key_pressed.connect(func(is_move_key: bool) -> void: seen.append(is_move_key))
	await _press(_key_for(&"move_up"))
	await _press(_key_for(&"use_item_1"))
	assert_array(seen).is_equal([true, false])


func test_a_touch_on_the_left_is_in_the_move_area_and_on_the_right_is_not() -> void:
	var reader := _reader()
	var width := float(_screen.size.x)
	var seen: Array[bool] = []
	reader.screen_touched.connect(func(in_move_area: bool) -> void: seen.append(in_move_area))
	await _press(_touch(Vector2(width * 0.1, 100)))
	await _press(_touch(Vector2(width * 0.9, 100)))
	await _press(_touch(Vector2(width * 0.1, 100), false))
	assert_array(seen).is_equal([true, false])


func test_the_touch_attack_button_attacks() -> void:
	var reader := _reader()
	var controls: Control = TouchControlsScene.instantiate()
	_screen.add_child(controls)
	controls.show_buttons(true)
	var button_center: Vector2 = (controls.get_node("%AttackButton") as Control) \
			.get_global_rect().get_center()
	var attacks := [0]
	reader.attack_pressed.connect(func() -> void: attacks[0] += 1)
	await _press(_touch(button_center))
	await _press(_touch(button_center, false))
	assert_int(attacks[0]).is_equal(1)
