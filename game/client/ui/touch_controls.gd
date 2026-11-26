extends Control
## The controls for touch screens: a joystick that appears under your thumb
## on the left of the screen, and a button per item slot on the right, as on
## a controller. Over the level select, a menu's controls instead: no
## joystick or slot buttons, and a Back button in the bottom-left corner, just
## above the party bar. They press the same actions as the keys, so the
## client reads them the same way. The joystick shows only while touched;
## the buttons as the GameView says. The buttons keep their places whatever
## the slots hold.

const GameView := preload("res://client/game_view.gd")
const ItemButton := preload("res://client/ui/item_button.gd")

## How much of the screen's width, from the left, can start the joystick.
## PLACEHOLDER (design): untuned.
const MOVE_AREA_RATIO := 1.0 / 3.0
## Where slot 1's button's center is, as a share of the screen's width
## and height. PLACEHOLDER (design): untuned.
const SLOT_1_CENTER_RATIO := Vector2(0.85, 0.65)
## Where slot 2's button's center is from slot 1's, in px: down
## and to the left. PLACEHOLDER (design): untuned.
const SLOT_2_OFFSET := Vector2(-70.0, 70.0)
## From the left edge, and from what it sits on (see [method set_back_floor]),
## to the Back button's nearest corner, in px. PLACEHOLDER (design): untuned.
const BACK_MARGIN := Vector2(8.0, 8.0)

@onready var _joystick: VirtualJoystick = %Joystick
@onready var _slot_1_button: ItemButton = %Slot1Button
@onready var _slot_2_button: ItemButton = %Slot2Button
@onready var _back_button: TouchScreenButton = %BackButton
## How far down the Back button may reach, in px; the screen's bottom until
## [method set_back_floor] says otherwise.
var _back_floor := INF


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
## button shows with no icon. Over the level select
## ([param level_select_open]) only Back shows, and the joystick is off.
func show_buttons(shown: bool, slot_1: GameView.ItemSlot, slot_2: GameView.ItemSlot,
		level_select_open: bool) -> void:
	_slot_1_button.visible = shown and not level_select_open
	_slot_2_button.visible = shown and not level_select_open
	_back_button.visible = shown and level_select_open
	_joystick.visible = not level_select_open
	_slot_1_button.show_icon(slot_1.icon if slot_1 else null)
	_slot_2_button.show_icon(slot_2.icon if slot_2 else null)


## Puts the Back button's bottom [constant BACK_MARGIN] above [param y], in
## px from the top: the top of what fills the bottom-left corner.
func set_back_floor(y: float) -> void:
	_back_floor = y
	_place_buttons()


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
	var slot_1_center := size * SLOT_1_CENTER_RATIO
	_slot_1_button.position = slot_1_center - _slot_1_button.size / 2.0
	_slot_2_button.position = slot_1_center + SLOT_2_OFFSET - _slot_2_button.size / 2.0
	# Its shape is centered on its position.
	var back_size := (_back_button.shape as RectangleShape2D).size
	_back_button.position = Vector2(BACK_MARGIN.x + back_size.x / 2.0,
			minf(_back_floor, size.y) - BACK_MARGIN.y - back_size.y / 2.0)
