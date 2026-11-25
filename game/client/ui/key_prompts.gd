extends HBoxContainer
## The movement keys, shaped as on a keyboard, and each item slot's key under
## its item's name. Keys are read from the input map so rebinding a key
## changes them too. Each group shows and hides on its own (see GameView),
## and keeps its room while hidden, so no key ever moves.

const GameView := preload("res://client/game_view.gd")
const ClientLoader := preload("res://client/client_loader.gd")

## In the order of the key caps: up on top; left, down, right below.
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]
## For an action with no key bound.
const UNBOUND := "?"

@onready var _move_keys: Array[Label] = [%UpLabel, %LeftLabel, %DownLabel, %RightLabel]
@onready var _move: Control = %Move
@onready var _slot_1: Control = %Slot1
@onready var _slot_2: Control = %Slot2
@onready var _slot_1_caption: Label = %Slot1Caption
@onready var _slot_2_caption: Label = %Slot2Caption


## The first key bound to [param action], as printed on a US keyboard.
static func key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_physical_keycode()
	return UNBOUND


func _ready() -> void:
	for i in MOVE_ACTIONS.size():
		_move_keys[i].text = key_name(MOVE_ACTIONS[i])
	(%UseItem1KeyLabel as Label).text = key_name(&"use_item_1")
	(%UseItem2KeyLabel as Label).text = key_name(&"use_item_2")
	_fit_slots_to_item_names()


## Each slot's keys are as wide as the widest item name, so what a slot holds
## never moves them or the keys beside them.
func _fit_slots_to_item_names() -> void:
	var font := _slot_1_caption.get_theme_font(&"font")
	var font_size := _slot_1_caption.get_theme_font_size(&"font_size")
	var widest := 0.0
	for look in ClientLoader.item_looks:
		widest = maxf(widest, font.get_string_size(
				look.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for slot_keys: Control in [_slot_1, _slot_2]:
		slot_keys.custom_minimum_size.x = ceilf(widest)


## [param slot_1] and [param slot_2] are what the slots hold, null for
## nothing; an empty slot's key shows with no caption.
func show_prompts(show_move_keys: bool, show_action_keys: bool,
		slot_1: GameView.ItemSlot, slot_2: GameView.ItemSlot) -> void:
	# Groups turn transparent rather than hide, so they keep their room and
	# the keys beside them don't move.
	_move.modulate.a = 1.0 if show_move_keys else 0.0
	for slot_keys: Control in [_slot_1, _slot_2]:
		slot_keys.modulate.a = 1.0 if show_action_keys else 0.0
	_slot_1_caption.text = slot_1.display_name if slot_1 else ""
	_slot_2_caption.text = slot_2.display_name if slot_2 else ""
	# Hidden whole when nothing in it shows, so an empty row uses no room.
	visible = show_move_keys or show_action_keys
