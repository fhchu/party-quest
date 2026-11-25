extends Control
## The controls for touch screens: a joystick that appears under your thumb
## on the left of the screen, and a button per item slot on the right. They
## press the same actions as the keys, so the client reads them the same way.
## The joystick shows only while touched; the buttons as the GameView says.
## The buttons keep their places whatever the slots hold.

const GameView := preload("res://client/game_view.gd")
const ItemButton := preload("res://client/ui/item_button.gd")

## How much of the screen's width, from the left, can start the joystick.
## PLACEHOLDER (design): untuned.
const MOVE_AREA_RATIO := 1.0 / 3.0
## Where the attack button's center is, as a share of the screen's width
## and height. PLACEHOLDER (design): untuned.
const ATTACK_CENTER_RATIO := Vector2(0.85, 0.65)
## Where slot 2's button's center is from the attack button's, in px: down
## and to the left. PLACEHOLDER (design): untuned.
const SLOT_2_OFFSET := Vector2(-70.0, 70.0)

@onready var _joystick: VirtualJoystick = %Joystick
@onready var _attack_button: ItemButton = %AttackButton
@onready var _slot_2_button: ItemButton = %Slot2Button


## Whether a touch at [param pos] goes to the joystick, on a screen of
## [param screen_size].
static func in_move_area(pos: Vector2, screen_size: Vector2) -> bool:
	return pos.x < screen_size.x * MOVE_AREA_RATIO


func _ready() -> void:
	_joystick.gui_input.connect(_only_start_in_move_area)
	resized.connect(_place_buttons)
	_place_buttons()


## [param shown] is whether the buttons show at all; [param slot_1] and
## [param slot_2] are what the slots hold, null for nothing; an empty slot's
## button shows with no icon.
func show_buttons(shown: bool, slot_1: GameView.ItemSlot, slot_2: GameView.ItemSlot) -> void:
	_attack_button.visible = shown
	_slot_2_button.visible = shown
	_attack_button.show_icon(slot_1.icon if slot_1 else null)
	_slot_2_button.show_icon(slot_2.icon if slot_2 else null)


## The joystick covers the whole screen so its base can follow the thumb
## anywhere, but a touch only starts it in the move area. Its gui_input
## signal comes before its own handling, so a press accepted here never
## reaches it. Drags and releases pass through. Mouse clicks reach it only
## as touches, since the joystick ignores mouse buttons.
func _only_start_in_move_area(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed and not in_move_area(touch.position, _joystick.size):
		_joystick.accept_event()


func _place_buttons() -> void:
	var attack_center := size * ATTACK_CENTER_RATIO
	_attack_button.position = attack_center - _attack_button.size / 2.0
	_slot_2_button.position = attack_center + SLOT_2_OFFSET - _slot_2_button.size / 2.0
