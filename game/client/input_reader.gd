extends Node
## Sorts the player's presses for the client: an input action, a key, or a
## touch and whether it landed where the joystick takes it. The move itself isn't
## read here: keys and the joystick both press the move actions, and the
## client reads those when it sends input.

## [param index] is the action's in Protocol.INPUT_ACTIONS.
signal input_action_pressed(index: int)
signal key_pressed(is_move_key: bool)
signal screen_touched(in_move_area: bool)

const TouchControls := preload("res://client/ui/touch_controls.gd")
const Protocol := preload("res://net/protocol.gd")

const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]


## Before the GUI, since the joystick takes the touches that land on it.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		key_pressed.emit(_is_move_key(event))
	elif event is InputEventScreenTouch and event.is_pressed():
		var touch := event as InputEventScreenTouch
		screen_touched.emit(TouchControls.in_move_area(
				touch.position, get_viewport().get_visible_rect().size))


## Keys and touch buttons both arrive as the input action they press.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	for i in Protocol.INPUT_ACTIONS.size():
		if event.is_action_pressed(Protocol.INPUT_ACTIONS[i]):
			input_action_pressed.emit(i)


func _is_move_key(event: InputEvent) -> bool:
	for action in MOVE_ACTIONS:
		if event.is_action(action):
			return true
	return false
