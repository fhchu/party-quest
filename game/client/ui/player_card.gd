extends MarginContainer
## One seat in the party bar: an icon in the seat's color, the name and a
## health bar with a status label on it, filled green while the seat is
## ready. The slot keeps its place when the
## seat is empty, so cards don't move as people come and go.

const Palette := preload("res://client/palette.gd")
const GameView := preload("res://client/game_view.gd")

# PLACEHOLDER (design): the wording, until there are names.
const NAME_TEXT := "Player %d"
## The bar's look while the seat is ready (theme.tres).
const READY_BAR := &"ReadyBar"
## PLACEHOLDER (art): how faint a disconnected player's icon is, under its
## "d/c".
const DISCONNECTED_ALPHA := 0.3

@onready var _card: Control = %Card
@onready var _icon: ColorRect = %Icon
@onready var _disconnected: Label = %Disconnected
@onready var _name: Label = %Name
@onready var _bar: ProgressBar = %Bar
@onready var _status: Label = %Status


## Shows seat [param id]'s [param card], or an empty slot if it's null.
func show_card(id: int, card: GameView.Card) -> void:
	_card.visible = card != null
	if not card:
		return
	_icon.color = Palette.player_color(id)
	_icon.modulate.a = DISCONNECTED_ALPHA if card.disconnected else 1.0
	_disconnected.visible = card.disconnected
	_name.text = NAME_TEXT % id
	_bar.max_value = card.max_health
	_bar.value = card.health
	_bar.theme_type_variation = READY_BAR if card.ready else &""
	_status.text = card.status_text
