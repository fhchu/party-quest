extends Node
## Draws the whole screen from a GameView: the world, the level select over
## it when it shows, and the lobby UI, the center notice and the debug overlay
## over both on their own layer. The client and the UI gallery both draw
## through it, so they show the same screen.

## A square of the level select was tapped; [param level] is its, from 0.
signal level_tapped(level: int)

const GameView := preload("res://client/game_view.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")
const LevelSelect := preload("res://client/ui/level_select.gd")

@onready var _world: WorldRenderer = %World
@onready var _level_select: LevelSelect = %LevelSelect
@onready var _lobby_ui: LobbyUI = %LobbyUI
@onready var _notice: CenterNotice = %Notice
## Top left, over the rest; see debug_stats.gd for what it shows.
@onready var _debug_overlay: Label = %DebugOverlay


func _ready() -> void:
	_level_select.level_tapped.connect(level_tapped.emit)


## Draws the world, the level select, the lobby UI, the notice and the debug
## overlay from [param state].
func render(state: GameView) -> void:
	_world.show_view(state.world, state.my_id, state.waiting_for_ready, state.is_ready,
			state.slot_looks)
	_level_select.show_level_select(state.level_select_open, state.level_cursor)
	_lobby_ui.show_state(state)
	_notice.show_text(state.notice)
	_debug_overlay.visible = not state.debug_text.is_empty()
	_debug_overlay.text = state.debug_text
