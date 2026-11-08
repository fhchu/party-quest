extends Node
## The whole screen while in the room: the arena, with the room HUD and the
## center notice drawn over it on their own layer. The client and the UI
## gallery both draw through it, so they show the same screen.

const HudState := preload("res://client/ui/hud_state.gd")
const ArenaView := preload("res://client/arena_view.gd")
const RoomHud := preload("res://client/ui/room_hud.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")

@onready var _arena: ArenaView = %Arena
@onready var _room_hud: RoomHud = %RoomHud
@onready var _notice: CenterNotice = %Notice


## Draws the arena, the HUD and the notice from [param state].
func render(state: HudState) -> void:
	_arena.show_view(state.view, state.my_id, state.room != null and state.room.all_ready())
	_room_hud.show_state(state)
	_notice.show_text(state.notice)
