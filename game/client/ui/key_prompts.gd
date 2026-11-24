extends HBoxContainer
## The movement keys, shaped as on a keyboard, and item slot 1's key, read from
## the input map so rebinding a key changes them too. Each group shows and
## hides on its own (see GameView).

## In the order of the key caps: up on top; left, down, right below.
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]
## For an action with no key bound.
const UNBOUND := "?"

@onready var _move_keys: Array[Label] = [%UpLabel, %LeftLabel, %DownLabel, %RightLabel]
@onready var _attack_key: Label = %UseItem1KeyLabel
@onready var _move: Control = %Move
@onready var _attack: Control = %Attack


## The first key bound to [param action], as printed on a US keyboard.
static func key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_physical_keycode()
	return UNBOUND


func _ready() -> void:
	for i in MOVE_ACTIONS.size():
		_move_keys[i].text = key_name(MOVE_ACTIONS[i])
	_attack_key.text = key_name(&"use_item_1")


func show_prompts(show_move_keys: bool, show_action_keys: bool) -> void:
	_move.visible = show_move_keys
	_attack.visible = show_action_keys
	# Hidden whole when both are, so an empty row takes no room.
	visible = show_move_keys or show_action_keys
