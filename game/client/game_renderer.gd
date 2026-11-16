extends Node
## Draws the whole screen from a GameView: the world, with the lobby UI and
## the center notice over it on their own layer. The client and the UI
## gallery both draw through it, so they show the same screen.

const GameView := preload("res://client/game_view.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

@onready var _world: WorldRenderer = %World
@onready var _lobby_ui: LobbyUI = %LobbyUI
@onready var _notice: CenterNotice = %Notice


## Draws the world, the lobby UI and the notice from [param state].
func render(state: GameView) -> void:
	_world.show_view(state.view, state.my_id, state.waiting_for_ready)
	_lobby_ui.show_state(state)
	_notice.show_text(state.notice)
