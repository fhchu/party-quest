extends Node
## Draws the whole screen from a GameView: the world, with the lobby UI, the
## center notice and the debug overlay over it on their own layer. The client
## and the UI gallery both draw through it, so they show the same screen.

const GameView := preload("res://client/game_view.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

## The debug overlay redraws this often: slow enough to read, fast enough to
## stay current.
const DEBUG_EVERY_SEC := 0.25

@onready var _world: WorldRenderer = %World
@onready var _lobby_ui: LobbyUI = %LobbyUI
@onready var _notice: CenterNotice = %Notice
## Top left, over the rest; see debug_stats.gd for what it shows.
@onready var _debug_overlay: Label = %DebugOverlay
var _debug_next_at := 0.0


## Draws the world, the lobby UI, the notice and the debug overlay from
## [param state].
func render(state: GameView) -> void:
	_world.show_view(state.world, state.my_id, state.waiting_for_ready)
	_lobby_ui.show_state(state)
	_notice.show_text(state.notice)
	_show_debug(state.debug_text)


## Hidden while [param text] is empty.
func _show_debug(text: String) -> void:
	_debug_overlay.visible = not text.is_empty()
	var now := Time.get_ticks_msec() / 1000.0
	if text.is_empty() or now < _debug_next_at:
		return
	_debug_next_at = now + DEBUG_EVERY_SEC
	_debug_overlay.text = text
