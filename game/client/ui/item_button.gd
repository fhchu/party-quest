extends "res://client/ui/round_button.gd"
## A touch button for one item slot: it presses the slot's action as its key
## does, and draws the slot's item's icon. Sized to the circle that holds an
## icon of [constant ICON_SIZE], whether or not one shows.

## How big an icon draws, in px along its longer side, whatever its image's
## size.
## PLACEHOLDER (design): untuned.
const ICON_SIZE := 64.0

## The input action it presses.
@export var action: StringName

@onready var _circle: Panel = %Circle
@onready var _icon: Sprite2D = %Icon


## How much to scale an icon image of [param image_size] so its longer side
## is [constant ICON_SIZE].
static func icon_scale(image_size: Vector2) -> float:
	return ICON_SIZE / maxf(image_size.x, image_size.y)


func _ready() -> void:
	_fit_circle()
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))


## Draws [param icon]; null for none.
func show_icon(icon: Texture2D) -> void:
	_icon.texture = icon
	if icon:
		_icon.scale = Vector2.ONE * icon_scale(icon.get_size())


## The circle holds the whole icon, corners included, and is what you press.
func _fit_circle() -> void:
	var circle_radius := ICON_SIZE * sqrt(2.0) / 2.0
	size = Vector2.ONE * circle_radius * 2.0
	_circle.size = size
	_icon.position = size / 2.0
	(_circle.get_theme_stylebox(&"panel") as StyleBoxFlat).set_corner_radius_all(
			ceili(circle_radius))


## Presses or releases [member action] as its key does: its state, and an
## event for the readers of _unhandled_input.
func _press(down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	get_viewport().push_input(event, true)
	(_circle.material as ShaderMaterial).set_shader_parameter(&"pressed", down)
