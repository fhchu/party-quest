extends Node
## The whole screen while in the room: the arena, with the room UI and the
## center notice drawn over it on their own layer. The client and the UI
## gallery both draw through it, so they show the same screen.

const GameViewState := preload("res://client/ui/game_view_state.gd")
const ArenaView := preload("res://client/arena_view.gd")
const RoomUI := preload("res://client/ui/room_ui.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

@onready var _arena: ArenaView = %Arena
@onready var _room_ui: RoomUI = %RoomUI
@onready var _notice: CenterNotice = %Notice


## Draws the arena, the room UI and the notice from [param state].
func render(state: GameViewState) -> void:
	_arena.show_view(state.view, state.my_id, state.room != null and state.room.all_ready())
	_room_ui.show_state(state)
	_notice.show_text(state.notice)
