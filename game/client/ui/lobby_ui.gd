extends Control
## In-game UI while in the lobby: the party bar along the bottom, the key
## prompts above it, the lobby code top left and the run timer top right.
## Drawn from a GameView only.

const GameView := preload("res://client/game_view.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")

@onready var _lobby_code: Label = %LobbyCode
@onready var _timer: Label = %Timer
@onready var _prompts: KeyPrompts = %Prompts
var _cards: Array[PlayerCard] = []


func _ready() -> void:
	_cards.assign(%PartyBar.get_children())


func show_state(view: GameView) -> void:
	visible = view.in_lobby
	if not visible:
		return
	_lobby_code.text = view.lobby_code
	_timer.text = view.timer_text
	_prompts.show_prompts(view.show_prompts)
	for i in _cards.size():
		var id := i + 1
		_cards[i].show_card(id, view.card(id))
