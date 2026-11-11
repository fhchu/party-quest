extends Node
## The whole screen while in the lobby: the arena, with the lobby UI and the
## center notice drawn over it on their own layer. The client and the UI
## gallery both draw through it, so they show the same screen.

const GameViewState := preload("res://client/ui/game_view_state.gd")
const ArenaView := preload("res://client/arena_view.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

@onready var _arena: ArenaView = %Arena
@onready var _lobby_ui: LobbyUI = %LobbyUI
@onready var _notice: CenterNotice = %Notice


## Draws the arena, the lobby UI and the notice from [param state].
func render(state: GameViewState) -> void:
	_arena.show_view(
			state.view, state.tuning, state.my_id, state.lobby != null and state.lobby.all_ready())
	_lobby_ui.show_state(state)
	_notice.show_text(state.notice)
