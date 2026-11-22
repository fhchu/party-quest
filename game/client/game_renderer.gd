extends Node
## Draws the whole screen from a GameView: the world, with the lobby UI, the
## center notice and the debug overlay over it on their own layer. The client
## and the UI gallery both draw through it, so they show the same screen.

const GameView := preload("res://client/game_view.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

@onready var _world: WorldRenderer = %World
@onready var _lobby_ui: LobbyUI = %LobbyUI
@onready var _notice: CenterNotice = %Notice
## Top left, over the rest; see debug_stats.gd for what it shows.
@onready var _debug_overlay: Label = %DebugOverlay


## Draws the world, the lobby UI, the notice and the debug overlay from
## [param state].
func render(state: GameView) -> void:
	_world.show_view(state.world, state.my_id, state.waiting_for_ready)
	_lobby_ui.show_state(state)
	_notice.show_text(state.notice)
	_debug_overlay.visible = not state.debug_text.is_empty()
	_debug_overlay.text = state.debug_text
