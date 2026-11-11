extends MarginContainer
## One seat in the party bar: an icon in the seat's color, the name and a
## health bar with a status label on it. The slot keeps its place when the
## seat is empty, so cards don't move as people come and go.

const LobbyState := preload("res://net/lobby_state.gd")
const Palette := preload("res://client/palette.gd")

# PLACEHOLDER (design): the wording, until there are names.
const NAME_TEXT := "Player %d"
const READY_TEXT := "ready"
const NOT_READY_TEXT := "not ready"
const WAITING_TEXT := "waiting"
## PLACEHOLDER (art): how faint a disconnected player's icon is, under its
## "d/c".
const DISCONNECTED_ALPHA := 0.3

@onready var _card: Control = %Card
@onready var _icon: ColorRect = %Icon
@onready var _disconnected: Label = %Disconnected
@onready var _name: Label = %Name
@onready var _bar: ProgressBar = %Bar
@onready var _status: Label = %Status


## What the bar's label says: "waiting" for a late joiner, ready or not in
## town, nothing otherwise.
static func status_text(seat: LobbyState.Seat, phase: LobbyState.Phase) -> String:
	if seat.readiness == LobbyState.Readiness.SPECTATING:
		return WAITING_TEXT
	if phase == LobbyState.Phase.TOWN:
		return READY_TEXT if seat.readiness == LobbyState.Readiness.READY else NOT_READY_TEXT
	return ""


## Shows seat [param id], or an empty slot if [param seat] is null.
## [param disconnected] dims the icon under "d/c". [method show_health] fills
## the bar.
func show_seat(
		id: int, seat: LobbyState.Seat, phase: LobbyState.Phase, disconnected: bool) -> void:
	_card.visible = seat != null
	if not seat:
		return
	_icon.color = Palette.player_color(id)
	_icon.modulate.a = DISCONNECTED_ALPHA if disconnected else 1.0
	_disconnected.visible = disconnected
	_name.text = NAME_TEXT % id
	_status.text = status_text(seat, phase)


## Fills the bar to [param health] out of [param max_health].
func show_health(health: int, max_health: int) -> void:
	_bar.max_value = max_health
	_bar.value = health
