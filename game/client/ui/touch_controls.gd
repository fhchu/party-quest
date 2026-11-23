extends Control
## The controls for touch screens: a joystick that appears under your thumb
## on the left of the screen, and an attack button on the right. Both press
## the same actions as the keys, so the client reads them the same way. The
## joystick shows only while touched; the button as the GameView says.

## How much of the screen's width, from the left, can start the joystick.
## PLACEHOLDER (design): untuned.
const MOVE_AREA_RATIO := 1.0 / 3.0
## Where the attack button's center is, as a share of the screen's width
## and height. PLACEHOLDER (design): untuned.
const ATTACK_CENTER_RATIO := Vector2(0.8, 0.8)
## How big the attack icon draws, in px along its longer side, whatever its
## image's size.
## PLACEHOLDER (design): untuned.
const ATTACK_ICON_SIZE := 64.0
## Missing in a clone without the art, which is kept out of the public
## repo; the button then draws no icon.
const ATTACK_ICON_PATH := "res://client/assets/textures/sword_ui.png"

@onready var _joystick: VirtualJoystick = %Joystick
@onready var _attack_button: TouchScreenButton = %AttackButton
@onready var _attack_circle: Panel = %AttackCircle
@onready var _attack_icon: Sprite2D = %AttackIcon


## Whether a touch at [param pos] goes to the joystick, on a screen of
## [param screen_size].
static func in_move_area(pos: Vector2, screen_size: Vector2) -> bool:
	return pos.x < screen_size.x * MOVE_AREA_RATIO


## How much to scale an icon image of [param image_size] so its longer side
## is [constant ATTACK_ICON_SIZE].
static func icon_scale(image_size: Vector2) -> float:
	return ATTACK_ICON_SIZE / maxf(image_size.x, image_size.y)


func _ready() -> void:
	_joystick.gui_input.connect(_only_start_in_move_area)
	_size_attack_button()
	resized.connect(_place_attack_button)
	_place_attack_button()
	_attack_button.pressed.connect(_brighten_attack.bind(true))
	_attack_button.released.connect(_brighten_attack.bind(false))


func show_buttons(shown: bool) -> void:
	_attack_button.visible = shown


## The joystick covers the whole screen so its base can follow the thumb
## anywhere, but a touch only starts it in the move area. Its gui_input
## signal comes before its own handling, so a press accepted here never
## reaches it. Drags and releases pass through. Mouse clicks reach it only
## as touches, since the joystick ignores mouse buttons.
func _only_start_in_move_area(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed and not in_move_area(touch.position, _joystick.size):
		_joystick.accept_event()


## The circle holds the whole icon, corners included, and is what you press.
func _size_attack_button() -> void:
	var circle_radius := ATTACK_ICON_SIZE * sqrt(2.0) / 2.0
	(_attack_button.shape as CircleShape2D).radius = circle_radius
	_attack_circle.position = -Vector2.ONE * circle_radius
	_attack_circle.size = Vector2.ONE * circle_radius * 2.0
	(_attack_circle.get_theme_stylebox(&"panel") as StyleBoxFlat).set_corner_radius_all(
			ceili(circle_radius))
	if not ResourceLoader.exists(ATTACK_ICON_PATH):
		return
	var icon: Texture2D = load(ATTACK_ICON_PATH)
	_attack_icon.texture = icon
	_attack_icon.scale = Vector2.ONE * icon_scale(icon.get_size())


func _place_attack_button() -> void:
	_attack_button.position = size * ATTACK_CENTER_RATIO


func _brighten_attack(pressed: bool) -> void:
	(_attack_circle.material as ShaderMaterial).set_shader_parameter(&"pressed", pressed)
