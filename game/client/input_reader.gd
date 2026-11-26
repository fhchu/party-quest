extends Node
## Sorts the player's presses for the client: an input action, a key, or a
## touch and whether it landed where the joystick uses it. The move itself isn't
## read here: keys and the joystick both press the move actions, and the
## client reads those when it sends input.

## [param index] is the action's number in [member input_actions].
signal input_action_pressed(index: int)
signal key_pressed(is_move_key: bool)
signal screen_touched(in_move_area: bool)

const TouchControls := preload("res://client/ui/touch_controls.gd")
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

## The input actions it reports, by number.
var input_actions: Dictionary[int, StringName] = {}


func _init(reported: Dictionary[int, StringName]) -> void:
	input_actions = reported


## Before the GUI, since the joystick consumes the touches that land on it.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		key_pressed.emit(_is_move_key(event))
	elif event is InputEventScreenTouch and event.is_pressed():
		var touch := event as InputEventScreenTouch
		screen_touched.emit(TouchControls.in_move_area(
				touch.position, get_viewport().get_visible_rect().size))


## Keys and touch buttons both arrive as the input action they press. A held
## move key's repeats count as presses too, so holding one keeps moving the
## level select's cursor at the system's key repeat rate.
func _unhandled_input(event: InputEvent) -> void:
	for i: int in input_actions:
		if event.is_action_pressed(input_actions[i], _is_move_action(input_actions[i])):
			input_action_pressed.emit(i)


func _is_move_action(action: StringName) -> bool:
	return action in MOVE_ACTIONS


func _is_move_key(event: InputEvent) -> bool:
	for action in MOVE_ACTIONS:
		if event.is_action(action):
			return true
	return false
